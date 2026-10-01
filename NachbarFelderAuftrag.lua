-- ============================================================
-- NachbarFelderAuftrag (Build 139): "Auftrag an den Lohnunternehmer"
--
-- Der Spieler steht an einem Feld und beauftragt die NachbarFelder-Helfer,
-- genau dieses Feld zu bearbeiten - auch wenn es ihm selbst gehoert.
-- Ausloeser: Taste "NachbarFelder: Lohnunternehmer beauftragen" (NF_ORDER_FIELD)
-- oder die Zeile "Dieses Feld bearbeiten lassen" im Reiter Wegpunkte.
--
-- Ablauf (server-autoritativ):
--   Client: Position + eigene Farm -> NachbarFelderAuftragEvent an den Server
--   Server: Feld an der Position suchen, Rechte und Feldzustand pruefen,
--           Helfer ueber createMission() starten, Antwort an den Absender
--   SP / eigener Host: dieselbe Server-Funktion direkt, ohne Event
--
-- Wer darf was:
--   * eigenes Feld (Farm des Absenders ist Besitzer): Recht "hireAssistant"
--     dieser Farm (gleiche Pruefung wie AIJobFieldWork:getIsStartable)
--   * freies Feld (kein Besitzer): nur Admin - wie "Helfer sofort starten"
--   * Feld einer anderen Farm: nie
--
-- Bearbeitet wird wie bei der normalen Feldarbeit nur Pfluegen oder Grubbern
-- (Build 125), die Wahl trifft getFeldAktion. Steht Frucht auf dem Feld,
-- wird der Auftrag abgelehnt.
--
-- Eigene Klassen-Tabelle statt Methoden am NachbarFelderManager: die Manager-
-- Datei wird von addSpecialization ein zweites Mal geladen und die globale
-- Tabelle dabei neu angelegt - hier angehaengte Methoden waeren danach weg.
-- Verifiziert (FS25-Community-LUADOC):
--   FarmlandManager:getFarmlandAtWorldPosition / getFarmlandOwner,
--   Farmland.field (FieldManager:loadMapData -> farmland:setField(field)),
--   FarmlandManager.NO_OWNER_FARM_ID, FarmManager.FARM_ID_SEND_NUM_BITS,
--   streamWriteUIntN/streamReadUIntN, connection:getIsServer(),
--   connection:sendEvent() (AIJobStartRequestEvent),
--   g_currentMission:getHasPlayerPermission("hireAssistant", connection, farmId)
--   (AIJobFieldWork:getIsStartable), g_currentMission:getFarmId(),
--   field:getId() (AbstractFieldMission: Feldnummer in den Vertragsmeldungen).
-- ============================================================
NachbarFelderAuftrag = {}

-- Groesster Abstand Spieler -> Feldrand, damit das Feld noch "hier" ist (m).
-- Man steht meist am Feldrand auf dem Weg, nicht im Feld.
NachbarFelderAuftrag.MAX_ABSTAND = 25

-- Ergebnis-Texte (l10n-Keys). Platzhalter: 1. %s = Feldnummer, 2. %s = Arbeit.
NachbarFelderAuftrag.TEXT = {
    OK            = "NF_auftrag_ok",
    GESENDET      = "NF_auftrag_gesendet",
    KEINE_POS     = "NF_auftrag_keinePosition",
    KEIN_FELD     = "NF_auftrag_keinFeld",
    FREMD         = "NF_auftrag_fremd",
    KEIN_RECHT    = "NF_auftrag_keinRecht",
    NUR_ADMIN     = "NF_auftrag_nurAdmin",
    BELEGT        = "NF_auftrag_belegt",
    GESPERRT      = "NF_auftrag_gesperrt",
    VERTRAG       = "NF_auftrag_vertrag",
    BEBAUT        = "NF_auftrag_bebaut",
    WEIDE         = "NF_auftrag_weide",
    KLEIN         = "NF_auftrag_klein",
    GRUENLAND     = "NF_auftrag_gruenland",
    FRUCHT        = "NF_auftrag_frucht",
    BEARBEITET    = "NF_auftrag_bearbeitet",
    UNKLAR        = "NF_auftrag_unklar",
    ARBEIT_AUS    = "NF_auftrag_arbeitAus",
    VOLL          = "NF_auftrag_voll",
    KEINE_FARM    = "NF_auftrag_keineFarm",
    INAKTIV       = "NF_auftrag_inaktiv",
    PLATZ         = "NF_auftrag_platz",
    FEHLER        = "NF_auftrag_fehler",
}

-- Arbeit je missionHelper-Index (3 = Pfluegen, 4 = Grubbern)
NachbarFelderAuftrag.ARBEIT_TEXT = {
    [3] = "NF_auftrag_arbeitPflug",
    [4] = "NF_auftrag_arbeitGrubber",
}

-- Bits fuer die Farm-ID im Stream: wie die Spiel-Events, sonst 8 Bit
local function nfFarmBits()
    if FarmManager ~= nil and FarmManager.FARM_ID_SEND_NUM_BITS ~= nil then
        return FarmManager.FARM_ID_SEND_NUM_BITS
    end
    return 8
end

local function nfKeinBesitzer()
    if FarmlandManager ~= nil and FarmlandManager.NO_OWNER_FARM_ID ~= nil then
        return FarmlandManager.NO_OWNER_FARM_ID
    end
    return 0
end

-- ============================================================
-- Network-Event (Build 139): Client -> Server Auftrag, Server -> Client Antwort
-- Eine Klasse fuer beide Richtungen, Muster AIJobStartRequestEvent: die
-- Richtung entscheidet connection:getIsServer() (true = Verbindung ZUM Server,
-- wir sind also der Client).
-- ============================================================
NachbarFelderAuftragEvent = {}
NachbarFelderAuftragEvent_mt = Class(NachbarFelderAuftragEvent, Event)
InitEventClass(NachbarFelderAuftragEvent, "NachbarFelderAuftragEvent")

function NachbarFelderAuftragEvent.emptyNew()
    return Event.new(NachbarFelderAuftragEvent_mt)
end

--- Client -> Server: Auftrag an Position x/z fuer die Farm farmId
function NachbarFelderAuftragEvent.new(x, z, farmId)
    local self = NachbarFelderAuftragEvent.emptyNew()
    self.x      = x or 0
    self.z      = z or 0
    self.farmId = farmId or 0
    return self
end

--- Server -> Client: Ergebnis fuer den Absender
--- @param feldNr angezeigte Feldnummer (field:getId()), -1 = keine
function NachbarFelderAuftragEvent.newAntwort(ok, textKey, feldNr, arbeitKey)
    local self = NachbarFelderAuftragEvent.emptyNew()
    self.ok        = ok == true
    self.textKey   = textKey or ""
    self.feldNr    = feldNr or -1
    self.arbeitKey = arbeitKey or ""
    return self
end

function NachbarFelderAuftragEvent:writeStream(streamId, connection)
    if connection:getIsServer() then
        -- wir sind Client und schicken den Auftrag
        streamWriteFloat32(streamId, self.x or 0)
        streamWriteFloat32(streamId, self.z or 0)
        streamWriteUIntN(streamId, math.max(0, self.farmId or 0), nfFarmBits())
    else
        -- wir sind Server und antworten
        streamWriteUInt8(streamId, self.ok and 1 or 0)
        streamWriteString(streamId, self.textKey or "")
        streamWriteInt32(streamId, self.feldNr or -1)
        streamWriteString(streamId, self.arbeitKey or "")
    end
end

function NachbarFelderAuftragEvent:readStream(streamId, connection)
    if not connection:getIsServer() then
        -- Server: Auftrag lesen (Stream immer komplett lesen, auch bei Ablehnung)
        self.x      = streamReadFloat32(streamId)
        self.z      = streamReadFloat32(streamId)
        self.farmId = streamReadUIntN(streamId, nfFarmBits())
        local ok, textKey, feldNr, arbeitKey = false, NachbarFelderAuftrag.TEXT.FEHLER, -1, ""
        if g_NachbarFelderManager ~= nil then
            local pok, a, b, c, d = pcall(NachbarFelderAuftrag.ausfuehren,
                g_NachbarFelderManager, self.x, self.z, self.farmId, connection)
            if pok then
                ok, textKey, feldNr, arbeitKey = a, b, c, d
            else
                print("NachbarFelder: [AUFTRAG] Fehler: " .. tostring(a))
            end
        end
        pcall(function()
            connection:sendEvent(NachbarFelderAuftragEvent.newAntwort(ok, textKey, feldNr, arbeitKey))
        end)
    else
        -- Client: Antwort lesen und anzeigen
        self.ok        = streamReadUInt8(streamId) == 1
        self.textKey   = streamReadString(streamId)
        self.feldNr    = streamReadInt32(streamId)
        self.arbeitKey = streamReadString(streamId)
        pcall(NachbarFelderAuftrag.zeigeAntwort, self.ok, self.textKey, self.feldNr, self.arbeitKey)
    end
end

-- ============================================================
-- Client: Spielerposition (gleiche Reihenfolge wie addWaypointAtPlayer)
-- Fahrzeug -> zu Fuss getMapPositionAndLookYaw -> Spieler-rootNode -> Kamera
-- ============================================================
function NachbarFelderAuftrag.getSpielerPosition(mgr)
    local x, z = nil, nil
    local player = (mgr ~= nil and mgr.localPlayer) or g_localPlayer
    if player ~= nil then
        pcall(function()
            local vehicle = nil
            if player.getCurrentVehicle ~= nil then
                vehicle = player:getCurrentVehicle()
            end
            if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
                local vx, _, vz = getWorldTranslation(vehicle.rootNode)
                if math.abs(vx) > 1 or math.abs(vz) > 1 then
                    x, z = vx, vz
                end
            end
        end)
        if x == nil and player.getMapPositionAndLookYaw ~= nil then
            pcall(function()
                local px, pz = player:getMapPositionAndLookYaw()
                if px ~= nil and pz ~= nil and (math.abs(px) > 1 or math.abs(pz) > 1) then
                    x, z = px, pz
                end
            end)
        end
        if x == nil and player.rootNode ~= nil and player.rootNode ~= 0 then
            pcall(function()
                local px, _, pz = getWorldTranslation(player.rootNode)
                if math.abs(px) > 1 or math.abs(pz) > 1 then
                    x, z = px, pz
                end
            end)
        end
    end
    if x == nil and getCamera ~= nil then
        pcall(function()
            local cam = getCamera()
            if cam ~= nil and cam ~= 0 then
                local cx, _, cz = getWorldTranslation(cam)
                if math.abs(cx) > 1 or math.abs(cz) > 1 then
                    x, z = cx, cz
                end
            end
        end)
    end
    return x, z
end

--- Client: Farm des lokalen Spielers (0 = unbekannt)
function NachbarFelderAuftrag.getEigeneFarmId(mgr)
    local farmId = nil
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
            farmId = g_currentMission:getFarmId()
        end
    end)
    if farmId == nil or farmId == 0 then
        local player = (mgr ~= nil and mgr.localPlayer) or g_localPlayer
        if player ~= nil and player.farmId ~= nil then
            farmId = player.farmId
        end
    end
    return farmId or 0
end

-- ============================================================
-- Client-Einstieg (Taste und Button im Reiter Wegpunkte)
-- @return string Text fuer die Infozeile im Menue
-- ============================================================
function NachbarFelderAuftrag.anfordern(mgr)
    if g_currentMission == nil or mgr == nil then
        return nil
    end
    local x, z = NachbarFelderAuftrag.getSpielerPosition(mgr)
    if x == nil then
        return NachbarFelderAuftrag.zeigeAntwort(false, NachbarFelderAuftrag.TEXT.KEINE_POS, -1, "")
    end
    local farmId = NachbarFelderAuftrag.getEigeneFarmId(mgr)
    mgr:log(1, string.format("NachbarFelder: [AUFTRAG] angefordert bei x=%d z=%d (Farm %d)",
        math.floor(x), math.floor(z), farmId))

    if g_currentMission:getIsServer() then
        -- SP / eigener Host: direkt, lokaler Aufruf ohne Verbindung
        local ok, textKey, feldNr, arbeitKey = NachbarFelderAuftrag.ausfuehren(mgr, x, z, farmId, nil)
        return NachbarFelderAuftrag.zeigeAntwort(ok, textKey, feldNr, arbeitKey)
    end
    if g_client == nil then
        return NachbarFelderAuftrag.zeigeAntwort(false, NachbarFelderAuftrag.TEXT.FEHLER, -1, "")
    end
    g_client:getServerConnection():sendEvent(NachbarFelderAuftragEvent.new(x, z, farmId))
    -- Zwischenstand; die Antwort des Servers ersetzt den Text
    return NachbarFelderAuftrag.zeigeAntwort(true, NachbarFelderAuftrag.TEXT.GESENDET, -1, "")
end

--- Taste NF_ORDER_FIELD
function NachbarFelderAuftrag.onInput(mgr, actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    NachbarFelderAuftrag.anfordern(mgr)
end

--- Client: Ergebnis als Meldung und in der Infozeile des Reiters Wegpunkte
--- (Ingame-Meldungen verdeckt das offene Menue).
--- @param feldNr Feldnummer vom Server (field:getId())
--- @return string angezeigter Text
function NachbarFelderAuftrag.zeigeAntwort(ok, textKey, feldNr, arbeitKey)
    local vorlage = g_i18n:getText(textKey or NachbarFelderAuftrag.TEXT.FEHLER)
    -- zweiter Platzhalter: l10n-Key ("NF_...", z.B. die Arbeit) oder fertiger Text (z.B. "GRASS waechst")
    local arbeit  = ""
    if arbeitKey ~= nil and arbeitKey ~= "" then
        if string.sub(arbeitKey, 1, 3) == "NF_" then
            arbeit = g_i18n:getText(arbeitKey)
        else
            arbeit = arbeitKey
        end
    end
    local feld    = (feldNr ~= nil and feldNr >= 0) and tostring(feldNr) or "?"
    local text    = vorlage
    pcall(function()
        text = string.format(vorlage, feld, arbeit)
    end)
    text = "NachbarFelder: " .. text
    pcall(function()
        g_currentMission:addIngameNotification(
            ok and FSBaseMission.INGAME_NOTIFICATION_OK or FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            text)
    end)
    local page = g_NachbarFelderWaypointPage
    if page ~= nil then
        page._hinweisText = text
        page._hinweisBis  = (g_time or 0) + 8000
        pcall(function() page:refreshWpInfo() end)
    end
    return text
end

-- ============================================================
-- Server: Feld an einer Position
-- 1. Farmland unter dem Punkt -> farmland.field (eine Feld-Mitte je Farmland)
-- 2. sonst alle Felder: Punkt im Umriss = 0 m, sonst Abstand zum Rand
-- Gewaehlt wird das naechste Feld bis MAX_ABSTAND.
-- @return table|nil field, number|nil Abstand in m
-- ============================================================
function NachbarFelderAuftrag.getFeldAnPosition(mgr, x, z)
    local maxD = NachbarFelderAuftrag.MAX_ABSTAND

    local function abstand(field)
        local poly = mgr:getFeldPolygon(field)
        if poly == nil then
            -- kein Umriss: Feldmitte als grober Ersatz
            if field.posX == nil or field.posZ == nil then return nil end
            local r = math.sqrt(math.max(field.areaHa or 0.3, 0.1) * 10000 / math.pi)
            return math.max(0, MathUtil.vector2Length(x - field.posX, z - field.posZ) - r)
        end
        if x < poly.minX - maxD or x > poly.maxX + maxD or z < poly.minZ - maxD or z > poly.maxZ + maxD then
            return nil
        end
        if mgr.nfPunktInPolygon(x, z, poly) then
            return 0
        end
        return mgr.nfRandAbstand(x, z, poly)
    end

    -- 1. schneller Weg ueber das Farmland unter den Fuessen
    local field = nil
    pcall(function()
        local farmland = g_farmlandManager:getFarmlandAtWorldPosition(x, z)
        if farmland ~= nil and farmland.field ~= nil then
            field = farmland.field
        end
    end)
    if field ~= nil then
        local d = abstand(field)
        if d ~= nil and d <= 0 then
            return field, 0
        end
    end

    -- 2. alle Felder (Begrenzungsrahmen sortiert die meisten sofort aus)
    local best, bestD = nil, math.huge
    for _, f in pairs(g_fieldManager:getFields() or {}) do
        local ok, d = pcall(abstand, f)
        if ok and d ~= nil and d < bestD then
            best, bestD = f, d
        end
    end
    if best ~= nil and bestD <= maxD then
        return best, bestD
    end
    return nil, nil
end

--- Feldnummer eines Feld-Objekts = field:getId() (NachbarFelderManager:getFeldNummer).
--- Dieselbe Nummer zeigt das Spiel auf der Karte, und sie ist der Schluessel
--- fuer getFieldById, vehicleType und feldSperre. Bis zum Fix suchte diese
--- Funktion den Listenplatz in getFields() - auf Karten mit Luecken in der
--- Nummerierung fand der Auftrag dann kein Feld.
--- Nur gueltig, wenn getFieldById die Nummer wieder auf dasselbe Feld fuehrt.
function NachbarFelderAuftrag.getFeldId(mgr, field)
    if field == nil then return nil end
    local nr = mgr:getFeldNummer(field)
    if nr ~= nil and g_fieldManager:getFieldById(nr) == field then
        return nr
    end
    -- Fallback (getId fehlt in einer anderen Spielversion): Listenplatz, der getFieldById trifft
    for idx, f in pairs(g_fieldManager:getFields() or {}) do
        if f == field and g_fieldManager:getFieldById(idx) == field then
            return idx
        end
    end
    return nil
end

--- Wahrer Besitzer eines Farmlands. getFarmlandOwner liest farmlandMapping -
--- das bleibt vom voruebergehenden Helfer-Besitz (farmland.farmId) unberuehrt.
function NachbarFelderAuftrag.getBesitzer(farmland)
    if farmland == nil then return nil end
    local owner = nil
    pcall(function()
        owner = g_farmlandManager:getFarmlandOwner(farmland.id)
    end)
    if owner == nil and farmland.isOwned then
        owner = farmland.farmId
    end
    return owner or nfKeinBesitzer()
end

-- ============================================================
-- Server: Rechte und Feldzustand pruefen
-- @param pruefeRechte false bei gespeicherten Auftraegen (schon angenommen)
-- @return number|nil aktion (missionHelper-Index), string textKey,
--         string zusatz (zweiter Platzhalter der Meldung), string|nil Messwerte fuers Log
-- ============================================================
function NachbarFelderAuftrag.pruefe(mgr, field, fieldId, farmId, connection, pruefeRechte)
    local T = NachbarFelderAuftrag.TEXT
    if field == nil or field.farmland == nil then
        return nil, T.KEIN_FELD
    end

    -- Besitz: eigenes Feld, freies Feld oder fremd
    local owner = NachbarFelderAuftrag.getBesitzer(field.farmland)
    local frei  = owner == nil or owner == nfKeinBesitzer()
    if not frei and owner ~= farmId then
        return nil, T.FREMD
    end
    if pruefeRechte then
        if frei then
            if not mgr:getIsConnectionAdmin(connection) then
                return nil, T.NUR_ADMIN
            end
        elseif connection ~= nil then
            -- Recht "Helfer einstellen" fuer die eigene Farm (prueft auch die Mitgliedschaft)
            local erlaubt = false
            pcall(function()
                erlaubt = g_currentMission:getHasPlayerPermission("hireAssistant", connection, farmId) == true
            end)
            if not erlaubt and not mgr:getIsConnectionAdmin(connection) then
                return nil, T.KEIN_RECHT
            end
        end
    end

    if mgr.active == false then
        return nil, T.INAKTIV
    end
    if mgr.vehicleType[fieldId] ~= nil then
        return nil, T.BELEGT
    end
    if mgr.feldSperre ~= nil and mgr.feldSperre[fieldId] then
        return nil, T.GESPERRT
    end
    -- angenommener Vertrag auf dem Feld (nur angebotene stoeren nicht, Build 109)
    for _, mission in ipairs(g_missionManager.missions or {}) do
        if type(mission.getField) == "function" and mgr:getIstVertragAktiv(mission) then
            local mf = mission:getField()
            if mf ~= nil and (mf == field or (mf.farmland ~= nil and mf.farmland == field.farmland)) then
                return nil, T.VERTRAG
            end
        end
    end
    -- Sicherheitspruefungen wie isFieldUseful: der Helfer fuehre sonst in
    -- Gebaeude oder Weidezaeune
    local bebaut = mgr:getBebauteFelder()
    if bebaut ~= nil and bebaut[field] ~= nil then
        return nil, T.BEBAUT
    end
    if field.posX ~= nil and mgr:isPunktInWeide(field.posX, field.posZ) then
        return nil, T.WEIDE
    end
    if field.areaHa ~= nil and field.areaHa < 0.3 then
        return nil, T.KLEIN
    end
    if field.grassMissionOnly then
        return nil, T.GRUENLAND
    end

    -- info = Messwerte fuers Log, frucht = z.B. "GRASS waechst" fuer die Meldung
    local aktion, grund, info, frucht = mgr:getFeldAktion(field)
    if aktion == nil then
        if grund == "frucht" or grund == "waechst" or grund == "erntereif" then
            return nil, T.FRUCHT, frucht or "?", info
        elseif grund == "bearbeitet" then
            return nil, T.BEARBEITET, "", info
        end
        return nil, T.UNKLAR, "", info
    end
    -- Pfluegen abgeschaltet -> Grubbern (wie isFieldUseful)
    if aktion == 3 and not (mgr.missionHelper[3] ~= nil and mgr.missionHelper[3].active) then
        aktion = 4
    end
    if aktion == 4 and not (mgr.missionHelper[4] ~= nil and mgr.missionHelper[4].active) then
        return nil, T.ARBEIT_AUS
    end
    return aktion, T.OK
end

--- Server: Helfer fuer das Feld starten (Grenzen wie generateWorkMission)
--- @return boolean gestartet, string textKey, number|nil tatsaechliche Arbeit (Build 144)
function NachbarFelderAuftrag.starte(mgr, fieldId, aktion, farmId)
    local T = NachbarFelderAuftrag.TEXT
    local fieldWorkers = 0
    for _, k in pairs(mgr.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and not w.isPatrol and w.status ~= 100 and w.status ~= 9999 then
            fieldWorkers = fieldWorkers + 1
        end
    end
    if fieldWorkers >= (mgr.MAX_ASSISTANT_WORKERS or 12) then
        return false, T.VOLL
    end
    -- Build 132: Spawnpunkte vorhanden, aber alle belegt
    if mgr:getHatSpawnpunkte() and mgr:waehleSpawnpunkt(true) == nil then
        return false, T.PLATZ
    end

    mgr.feldSpawnBlockiert = false
    local created = mgr:createMission(fieldId, mgr.missionHelper[aktion])
    -- Build 144: kein taugliches Grubber-Gespann (z.B. nach Kipp-Sperre) -> Pfluegen,
    -- wenn eingeschaltet. Der Auftrag heisst "Feld bearbeiten", nicht "grubbern".
    if not created and not mgr.feldSpawnBlockiert and aktion == 4 and mgr.vehicleType[fieldId] == nil
       and mgr.missionHelper[3] ~= nil and mgr.missionHelper[3].active then
        print("NachbarFelder: [AUFTRAG] Feld " .. tostring(fieldId) .. " - kein Grubber-Gespann, versuche Pfluegen")
        created = mgr:createMission(fieldId, mgr.missionHelper[3])
        if created then
            aktion = 3
        end
    end
    if not created then
        return false, mgr.feldSpawnBlockiert and T.PLATZ or T.FEHLER
    end
    local eintrag = mgr.vehicleType[fieldId]
    if eintrag ~= nil and eintrag.NachbarFelderWorker ~= nil then
        eintrag.NachbarFelderWorker.istAuftrag    = true
        eintrag.NachbarFelderWorker.auftragFarmId = farmId
    end
    return true, T.OK, aktion
end

-- ============================================================
-- Server: Auftrag annehmen und ausfuehren
-- @param connection nil = lokaler Aufruf (SP / eigener Host)
-- @return boolean ok, string textKey, number feldNr (field:getId()), string arbeitKey
-- ============================================================
function NachbarFelderAuftrag.ausfuehren(mgr, x, z, farmId, connection)
    local T = NachbarFelderAuftrag.TEXT
    if g_currentMission == nil or not g_currentMission:getIsServer() then
        return false, T.FEHLER, -1, ""
    end
    mgr:loadServerConfig()

    -- Helfer-Farm muss feststehen (Build 138); Spectator = keine passende Farm
    local spectator = (FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID) or 0
    if mgr:getEffectiveFarmId() == spectator then
        return false, T.KEINE_FARM, -1, ""
    end

    local field, abstand = NachbarFelderAuftrag.getFeldAnPosition(mgr, x, z)
    local fieldId = NachbarFelderAuftrag.getFeldId(mgr, field)
    if field == nil or fieldId == nil then
        print(string.format("NachbarFelder: [AUFTRAG] kein Feld bis %d m bei x=%d z=%d",
            NachbarFelderAuftrag.MAX_ABSTAND, math.floor(x), math.floor(z)))
        return false, T.KEIN_FELD, -1, ""
    end

    -- es gibt nur eine Feldnummer: fieldId ist field:getId()
    local feldLog = "Feld " .. tostring(fieldId)

    local aktion, textKey, zusatz, info = NachbarFelderAuftrag.pruefe(mgr, field, fieldId, farmId, connection, true)
    if aktion == nil then
        print(string.format("NachbarFelder: [AUFTRAG] %s (%.0f m) abgelehnt fuer Farm %d: %s%s",
            feldLog, abstand or 0, farmId or 0, tostring(textKey), info ~= nil and (" | " .. info) or ""))
        return false, textKey, fieldId, zusatz or ""
    end

    local gestartet, startKey, aktionNeu = NachbarFelderAuftrag.starte(mgr, fieldId, aktion, farmId)
    aktion = aktionNeu or aktion   -- Build 144: ggf. Pfluegen statt Grubbern
    local arbeitKey = NachbarFelderAuftrag.ARBEIT_TEXT[aktion] or ""
    if not gestartet then
        print(string.format("NachbarFelder: [AUFTRAG] %s angenommen, Start nicht moeglich: %s",
            feldLog, tostring(startKey)))
        return false, startKey, fieldId, arbeitKey
    end
    local name = mgr.missionHelper[aktion] ~= nil and mgr.missionHelper[aktion].name or "?"
    print(string.format("NachbarFelder: [AUFTRAG] %s fuer Farm %d gestartet (%s, Besitzer %s)",
        feldLog, farmId or 0, name, tostring(NachbarFelderAuftrag.getBesitzer(field.farmland))))
    return true, T.OK, fieldId, arbeitKey
end

--- Server: gespeicherten Auftrag nach dem Neuladen fortsetzen. Die Rechte
--- wurden beim Annehmen geprueft; Besitz und Feldzustand werden neu geprueft.
--- @return boolean gestartet, boolean verworfen (wie startSavedMission)
function NachbarFelderAuftrag.starteGespeichert(mgr, eintrag)
    local fieldId = eintrag.fieldId
    local field   = fieldId ~= nil and g_fieldManager:getFieldById(fieldId) or nil
    local feldLog = "Feld " .. tostring(fieldId)
    local aktion, textKey, _, info = NachbarFelderAuftrag.pruefe(mgr, field, fieldId,
        eintrag.auftragFarmId or 0, nil, false)
    if aktion == nil and textKey == NachbarFelderAuftrag.TEXT.BELEGT then
        -- Build 143: alter Helfer wird noch entfernt (Neuversuch nach Fehlschlag) -> spaeter erneut
        return false, false
    end
    if aktion == nil then
        print("NachbarFelder: [AUFTRAG] Gespeicherter Auftrag auf " .. feldLog ..
            " verworfen: " .. tostring(textKey) .. (info ~= nil and (" | " .. info) or ""))
        return false, true
    end
    local gestartet, startKey = NachbarFelderAuftrag.starte(mgr, fieldId, aktion, eintrag.auftragFarmId or 0)
    if not gestartet then
        -- Platz oder Helfer-Grenze: beim naechsten Takt erneut
        local verworfen = startKey ~= NachbarFelderAuftrag.TEXT.PLATZ and startKey ~= NachbarFelderAuftrag.TEXT.VOLL
        return false, verworfen
    end
    print("NachbarFelder: [AUFTRAG] Gespeicherter Auftrag auf " .. feldLog .. " fortgesetzt")
    return true, false
end

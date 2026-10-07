NachbarFelderManager = {}

-- Build 165: Log-Ausgaben nur im Debug-Log (Warnungen/Fehler immer), siehe NachbarFelder.lua
local print = NachbarFelderLog.print

-- Build-Nummer: erscheint im Log bei loadMap - IMMER prüfen ob der Server
-- wirklich den erwarteten Build fährt (Server und Client werden getrennt bestückt)
NachbarFelderManager.BUILD = 170

local NachbarFelderManager_class = Class(NachbarFelderManager)

-- Build 166: Begegnung zweier Nachbar-Fahrzeuge (siehe loeseBegegnung)
NachbarFelderManager.BEGEGNUNG_RADIUS  = 100     -- m, so nah muss der stehende Nachbar sein
NachbarFelderManager.BEGEGNUNG_NAH     = 20      -- m, bis hier zaehlt jede Richtung, darueber nur "vor mir"
NachbarFelderManager.BEGEGNUNG_STEHT_MS = 15000  -- so lange muss auch er schon stehen
NachbarFelderManager.BEGEGNUNG_MAX     = 3       -- Ausweichen je Fahrzeug, danach normale Stufen

local modSettingDirectory = g_currentModSettingsDirectory
local modName = g_currentModName
local xmlSchema = XMLSchema.new("NachbarFelderSchema")
local baseXmlKey = "NachbarFelder"

-- Separates Schema + Dateipfad für Traffic-Wegpunkte (mod-settings, nicht savegame)
local wpXmlSchema = XMLSchema.new("NachbarFelderWaypointSchema")
local wpXmlKey    = "NachbarFelderWaypoints"
-- Bis Build 131 eine Datei fuer ALLE Karten - nach einem Kartenwechsel lagen die
-- alten Punkte auf der neuen Karte. Seit Build 132 je Karte (nfGetWpFilePath).
local wpFilePathAlt = modSettingDirectory .. "NachbarFelderWaypoints.xml"
local wpFilePath    = nil
wpXmlSchema:register(XMLValueType.STRING, wpXmlKey .. "#uebernommenFuer", "Karte, in deren Datei diese alte Datei uebernommen wurde")
wpXmlSchema:register(XMLValueType.FLOAT,  wpXmlKey .. ".wp(?)#x",     "WpX")
wpXmlSchema:register(XMLValueType.FLOAT,  wpXmlKey .. ".wp(?)#z",     "WpZ")
wpXmlSchema:register(XMLValueType.STRING, wpXmlKey .. ".wp(?)#label", "WpLabel")
wpXmlSchema:register(XMLValueType.FLOAT,  wpXmlKey .. ".wp(?)#ry",   "WpRy")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. ".wp(?)#cat",  "WpCat")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. "#catTractorS",   "CatTractorS")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. "#catTractorM",   "CatTractorM")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. "#catTractorL",   "CatTractorL")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. "#catLoader",     "CatLoader")
wpXmlSchema:register(XMLValueType.INT,    wpXmlKey .. "#catTeleLoader", "CatTeleLoader")

-- Build 142: gesperrte Ladeplaetze je Karte dauerhaft merken (vorher nur je Session -
-- derselbe schlechte Platz im Shop-Hof wurde nach jedem Neustart wieder genommen)
local lpXmlSchema = XMLSchema.new("NachbarFelderLadeplatzSchema")
local lpXmlKey    = "NachbarFelderLadeplaetze"
lpXmlSchema:register(XMLValueType.FLOAT,  lpXmlKey .. ".platz(?)#x",     "LadeplatzX")
lpXmlSchema:register(XMLValueType.FLOAT,  lpXmlKey .. ".platz(?)#z",     "LadeplatzZ")
lpXmlSchema:register(XMLValueType.STRING, lpXmlKey .. ".platz(?)#grund", "Grund der Sperre")

--- Kennung der geladenen Karte fuer Dateinamen (Build 132).
--- missionInfo.mapId steht im Spielstand als <mapId> (z.B.
--- FS25_Beuren.MultifruitModMap_Beuren); ersatzweise der letzte Ordnername von
--- g_currentMission.baseDirectory (verifiziert: FarmlandManager.lua:62).
--- @return string|nil
-- Build 158: Spieler-Texte kommen aus l10n (der ModHub verlangt Deutsch UND
-- Englisch fuer alles, was im Spiel sichtbar ist). hasText prueft den Schluessel,
-- damit bei einem fehlenden Eintrag nicht der rohe Schluessel in der Meldung steht.
local function nfText(key, ...)
    local s = key
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        s = g_i18n:getText(key)
    end
    if select("#", ...) > 0 then
        s = string.format(s, ...)
    end
    return s
end

-- Meldung mit vorangestelltem Mod-Namen, so wie der Spieler sie sieht.
local function nfMeldung(key, ...)
    return nfText("NachbarFelder") .. ": " .. nfText(key, ...)
end

local function nfGetKartenKennung()
    local kennung = nil
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if mi ~= nil and type(mi.mapId) == "string" and mi.mapId ~= "" then
        kennung = mi.mapId
    end
    if kennung == nil then
        local bd = g_currentMission ~= nil and g_currentMission.baseDirectory or nil
        if type(bd) == "string" and bd ~= "" then
            kennung = string.match(bd, "([^/\\]+)[/\\]*$")
        end
    end
    if kennung == nil or kennung == "" then return nil end
    kennung = string.gsub(kennung, "[^%w]", "_")
    kennung = string.gsub(kennung, "_+", "_")
    return string.sub(kennung, 1, 80)
end

--- Wegpunkt-Datei der geladenen Karte (Build 132). Erst zur Laufzeit ermittelt -
--- beim Einlesen dieser Datei existiert noch keine Mission. Ohne Kartenkennung
--- bleibt es bei der alten gemeinsamen Datei (Verhalten bis Build 131).
local function nfGetWpFilePath()
    if wpFilePath == nil then
        local kennung = nfGetKartenKennung()
        if kennung == nil then
            wpFilePath = wpFilePathAlt
        else
            wpFilePath = modSettingDirectory .. "NachbarFelderWaypoints_" .. kennung .. ".xml"
        end
    end
    return wpFilePath
end

local misssionSettingsPage = nil
local vehicleMission = {}

function NachbarFelderManager.new()
    local self = setmetatable({}, NachbarFelderManager_class)
    self.active = true
    self.vehicleType = {}
    self.farmId = 0
    if FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID ~= nil then
        self.farmId = FarmManager.SPECTATOR_FARM_ID
    end
    self.vehiclesToLoad = {}
    self.aiVeh = nil
    self.countWorkers = 0
    self.timeToNextStart = -1

    self.MAX_ASSISTANT_WORKERS = 12

    self.playersOnline = 0    -- Anzahl verbundener Spieler (0 = niemand online → Helfer pausiert)
    self.playerJoinTime       = nil  -- g_time beim ersten Join; 3 Echtzeit-Minuten warten (robust gegen Zeitsprünge)
    self.regularVehicleXMLs   = {}   -- bis zu 3 Stamm-Fahrzeug-XMLs (Wiederkehrende Fahrzeuge)
    self.pendingRespawns      = {}   -- {filename, spawnAt} – Respawn-Warteschlange für Stammfahrzeuge
    self.spawnPlaceIndex = 1 -- Index des besten Shop-Spawn-Punktes (wird in selectBestSpawnPlace gesetzt)
    self.trafficVehicleBlacklist = {}   -- filename → true (Session-Blacklist: Patrol-Fahrzeuge ohne Navigation-Agent)
    self.patrolCounter = 0          -- negative Pseudo-Keys für Patrol-Einträge in vehicleType
    self.trafficLimit = 4           -- max. gleichzeitige Traffic-Fahrzeuge (1–8, einstellbar)
    self.trafficPaused = false      -- nachbarFelderTrafficStop/Start Console-Befehl
    self.trafficTrailerSize = 2     -- 0=keine Anhänger  1=klein(≤4kL)  2=mittel(≤8kL)  3=alle(≤15kL)
    self.engeMap        = true      -- enge Karte: nur Kleintraktoren + leichte Anbaugeraete
    self.debugLog       = false     -- Build 165: ausfuehrliches Log (Einstellungen / logLevel=2)
    self.spawnBereichRadius = 25    -- Umkreis um den Shop-Spawn, der frei sein muss (m)
    self.spawnLookAt    = nil       -- gecachter Zielpunkt der Spawn-Blickrichtung {x=,z=,quelle=}
    self.trafficPool = {}           -- Fahrzeug-Pool (Build 65): schlafende Patrol-Fahrzeuge
    self.poolSize    = 6            -- max. schlafende Fahrzeuge (0 = Pool aus, Server-Konfig)
    self.fahrerfigurenAufServer = true  -- Build 95: false = Fahrerfiguren nur auf dem Server weglassen
    self.spielverkehrAnmelden   = true  -- Build 152: Fahrzeuge beim Spielverkehr anmelden (Autos bremsen)
    self.rueckwaertsPlanen      = false -- Build 108; Build 125: Standard aus (Server-Konfig ohne Eintrag lief mit true, viele Sofort-Abweisungen)
    self.dayRhythm      = true      -- Tagesrhythmus (Build 68): Verkehrsdichte folgt der Uhrzeit
    self.zielQuelle     = "strassen" -- Build 104: "strassen" = Ziele aus dem KI-Strassennetz,
                                     -- "wegpunkte" = nur die selbst gesetzten Punkte
    self.trailerChance  = 40        -- Gespann-Quote in % (Build 69, Server-Konfig)
    self.gespannSpawns  = 0         -- Zaehler: Traktor-Spawns MIT Anbaugeraet
    self.soloSpawns     = 0         -- Zaehler: Traktor-Spawns OHNE Anbaugeraet
    self.userTrafficWaypoints = {}  -- user-gesetzte Wegpunkte: {{x,z}, ...}
    self._mgr_viewIdx = 0           -- Waypoint-Anzeige-Index für Shift+Alt+W Notification
    self._wpHotspots  = {}          -- MapHotspot-Objekte für die Karte
    self.trafficTrailerList   = nil  -- schwere Anbaugeraete (Pflug/Maehwerk) → Großtraktoren
    self.trafficImplListLight = nil  -- leichte Anbaugeraete (Rechen/Zinkenrotor) → Mittelklasse
    self.vehicleCatEnabled = {      -- Fahrzeugkategorien: true = aktiv, false = ausgeblendet
        TRACTORSS           = true,
        TRACTORSM           = true,
        TRACTORSL           = true,
        WHEELLOADERVEHICLES = true,
        TELELOADERVEHICLES  = true,
    }

    self.counter = 1

    self.startReady = false
    self.startReadyTimer = 0
    self.startReadyField = 0

    self.missionHelper = {}
    self.missionHelper[1]  = { id = 1,  name = "baleMission",           class = BaleMission,           skip = true,  active = true }
    self.missionHelper[2]  = { id = 2,  name = "baleWrapMission",       class = BaleWrapMission,       skip = true,  active = true }
    self.missionHelper[3]  = { id = 3,  name = "plowMission",           class = PlowMission,           skip = false, active = true }
    self.missionHelper[4]  = { id = 4,  name = "cultivateMission",      class = CultivateMission,      skip = false, active = true }
    self.missionHelper[5]  = { id = 5,  name = "sowMission",            class = SowMission,            skip = false, active = true }
    self.missionHelper[6]  = { id = 6,  name = "harvestMission",        class = HarvestMission,        skip = false, active = true }
    self.missionHelper[7]  = { id = 7,  name = "hoeMission",            class = HoeMission,            skip = true,  active = false }
    self.missionHelper[8]  = { id = 8,  name = "weedMission",           class = WeedMission,           skip = true,  active = false }
    self.missionHelper[9]  = { id = 9,  name = "herbicideMission",      class = HerbicideMission,      skip = true,  active = false }
    self.missionHelper[10] = { id = 10, name = "fertilizeMission",      class = FertilizeMission,      skip = false, active = true }
    self.missionHelper[11] = { id = 11, name = "mowMission",            class = MowMission,            skip = true,  active = true }
    self.missionHelper[12] = { id = 12, name = "tedderMission",         class = TedderMission,         skip = true,  active = true }
    self.missionHelper[13] = { id = 13, name = "stonePickMission",      class = StonePickMission,      skip = true,  active = true }
    self.missionHelper[14] = { id = 14, name = "deadwoodMission",       class = DeadwoodMission,       skip = true,  active = true }
    self.missionHelper[15] = { id = 15, name = "treeTransportMission",  class = TreeTransportMission,  skip = true,  active = true }
    self.missionHelper[16] = { id = 16, name = "deadwoodMission",       class = DestructibleRockMission, skip = true, active = true }


    createFolder(modSettingDirectory)
    xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".worker(?)#missionType", "Missionname")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".worker(?)#fieldId",    "FieldId")
    -- Build 139: Auftrag an den Lohnunternehmer (NachbarFelderAuftrag.lua)
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".worker(?)#auftrag",       "Auftrag eines Spielers")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".worker(?)#auftragFarmId", "Farm des Auftraggebers")
    -- Settings im SAVEGAME (Build 67): server-autoritativ, MP-synct.
    -- Die lokale NachbarFelderSetting.xml bleibt nur Fallback fuer
    -- Savegames, die noch keinen settings-Block haben.
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#active",             "ModActive")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#maxWorkers",         "MaxWorkers")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#trafficLimit",       "TrafficLimit")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#trafficTrailerSize", "TrafficTrailerSize")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#engeMap",            "EngeMap")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#debugLog",           "DebugLog")
    xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".settings.mission(?)#type",   "MissionType")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings.mission(?)#active", "MissionActive")
    -- Vorfrucht-Gedaechtnis (Build 68): welche Frucht stand zuletzt auf dem Feld
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".fieldFruits.field(?)#id",    "FieldId")
    xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".fieldFruits.field(?)#fruit", "FruitName")
    return self
end

-- ============================================================
-- Settings-State (Build 67): server-autoritativer Einstellungs-Satz.
-- Architektur wie beim Wegpunkt-Editing: Client schickt Aenderung
-- (NachbarFelderSettingsEditEvent) -> Server wendet an, merkt sie
-- fuers Savegame vor und broadcastet den kompletten Stand
-- (NachbarFelderSettingsSyncEvent) an alle Clients zurueck.
-- ============================================================

-- Kompletten Einstellungs-Stand als Tabelle liefern
function NachbarFelderManager:getSettingsState()
    local missions = {}
    for _, mh in pairs(self.missionHelper or {}) do
        if not mh.skip then
            missions[mh.name] = mh.active == true
        end
    end
    return {
        active             = self.active ~= false,
        maxWorkers         = self.MAX_ASSISTANT_WORKERS or 12,
        trafficLimit       = self.trafficLimit or 4,
        trafficTrailerSize = self.trafficTrailerSize or 2,
        engeMap            = self.engeMap ~= false,
        debugLog           = self.debugLog == true,   -- Build 165
        missions           = missions,
        -- Build 157: Helfer-Farm fuer die Clients (Karten-Symbole ausblenden); 0 = noch unbekannt
        helferFarmId       = self:getHelferFarmIdAnzeige(),
    }
end

-- Einstellungs-Stand anwenden (Server nach Savegame-Load, Client nach Sync)
function NachbarFelderManager:applySettingsState(state)
    if state == nil then return end
    if state.helferFarmId ~= nil then   -- Build 157, nur fuer die Anzeige
        self.helferFarmIdSync = state.helferFarmId
    end
    if state.active ~= nil then
        self.active = state.active == true
    end
    if state.maxWorkers ~= nil then
        self.MAX_ASSISTANT_WORKERS = math.max(0, math.min(30, math.floor(state.maxWorkers)))
    end
    if state.trafficLimit ~= nil then
        self.trafficLimit = math.max(0, math.min(12, math.floor(state.trafficLimit)))
    end
    if state.trafficTrailerSize ~= nil then
        local tts = math.max(0, math.min(3, math.floor(state.trafficTrailerSize)))
        if tts ~= self.trafficTrailerSize then
            self.trafficTrailerList = nil  -- Cache mit neuer Groesse neu aufbauen
        end
        self.trafficTrailerSize = tts
    end
    if state.engeMap ~= nil then
        local neu = state.engeMap == true
        if neu ~= (self.engeMap ~= false) then
            -- Beide Caches muessen weg: die Fahrzeugliste haengt an den
            -- Kategorien, die Geraeteliste am Gewichtslimit.
            self.trafficVehicleList = nil
            self.trafficTrailerList = nil
        end
        self.engeMap = neu
    end
    if state.debugLog ~= nil then   -- Build 165
        self:setDebugLog(state.debugLog == true)
    end
    if state.missions ~= nil then
        for name, act in pairs(state.missions) do
            for _, mh in pairs(self.missionHelper or {}) do
                if mh.name == name and not mh.skip then
                    mh.active = act == true
                end
            end
        end
    end
    -- Settings-Seite aktualisieren, falls geladen (Client + SP)
    if self.settingsPage ~= nil and self.settingsPage.refreshFromManager ~= nil then
        if self.settingsPage ~= nil and self.settingsPage.refreshFromManager ~= nil then self.settingsPage:refreshFromManager() end
    end
end

-- Einzelne Einstellung anwenden (laeuft auf dem SERVER; Wert kommt als
-- Zahl vom Event oder als bool/Zahl direkt von der SP/Host-GUI)
function NachbarFelderManager:applySettingEdit(name, value)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if name == nil or name == "" then return end
    local function asBool(v)
        if type(v) == "boolean" then return v end
        return (tonumber(v) or 0) >= 0.5
    end
    local function asInt(v)
        return math.floor((tonumber(v) or 0) + 0.5)
    end

    local known = true
    if name == "active" then
        self.active = asBool(value)
    elseif name == "MAX_ASSISTANT_WORKERS" then
        self.MAX_ASSISTANT_WORKERS = math.max(0, math.min(30, asInt(value)))
    elseif name == "trafficLimit" then
        self.trafficLimit = math.max(0, math.min(12, asInt(value)))
    elseif name == "trafficTrailerSize" then
        self.trafficTrailerSize = math.max(0, math.min(3, asInt(value)))
        self.trafficTrailerList = nil
    elseif name == "debugLog" then   -- Build 165
        self:setDebugLog(asBool(value))
    elseif name == "engeMap" then
        self.engeMap = asBool(value)
        self.trafficVehicleList = nil
        self.trafficTrailerList = nil
    else
        known = false
        for _, mh in pairs(self.missionHelper or {}) do
            if mh.name == name and not mh.skip then
                mh.active = asBool(value)
                known = true
            end
        end
    end
    if not known then
        print("NachbarFelder: [SETTINGS] Unbekannte Einstellung ignoriert: " .. tostring(name))
        return
    end

    -- Ab jetzt ist der Live-Stand autoritativ: landet beim naechsten
    -- Speichern im Savegame und schlaegt die Server-Konfig-Datei.
    self.settingsFromSavegame = true
    print("NachbarFelder: [SETTINGS] " .. tostring(name) .. " = " .. tostring(value))
    self:broadcastSettingsToClients()
end

-- Kompletten Stand an alle Clients schicken (nur Server)
function NachbarFelderManager:broadcastSettingsToClients()
    if g_server ~= nil and NachbarFelderSettingsSyncEvent ~= nil then
        g_server:broadcastEvent(NachbarFelderSettingsSyncEvent.new(self:getSettingsState()))
    end
end

-- ============================================================
-- Effektive Farm-ID ermitteln (nie Spectator-Farm verwenden!)
-- AI-Jobs werden von der Engine sofort abgewiesen wenn farmId = SPECTATOR_FARM_ID.
--
-- Build 138: nicht mehr fest 2. Die Helfer-Farm bekommt Sonderrechte
-- (kein Geldabzug, darf jedes Feld bearbeiten) - sie darf deshalb NIE eine
-- Farm mit Spielern sein. Reihenfolge:
--   1. Server-Konfig <farmId> > 0 und die Farm existiert ohne Spieler
--   2. automatisch: hoechste Farm ohne Spieler, ohne Farmland, ohne Gebaeude
--   3. hoechste Farm ohne Spieler (auch mit Land/Gebaeuden)
--   4. keine gefunden -> Spectator-Farm, Helfer starten dann nicht (Warnung im Log)
-- Die Wahl gilt bis zum Server-Neustart.
-- ============================================================
function NachbarFelderManager:getFarmInfoForHelper(farmId)
    if g_farmManager == nil or g_farmManager.getFarmById == nil then
        return nil
    end
    local farm = g_farmManager:getFarmById(farmId)
    if type(farm) ~= "table" then
        return nil
    end
    local info = { farmId = farmId, name = tostring(farm.name or "?"), hatSpieler = false,
                   listeBekannt = false, farmlands = 0, gebaeude = 0 }
    -- Mitglieder stehen in farm.players (aus farms.xml <players>), siehe AgrarOekonomie
    for _, feld in ipairs({ "players", "userIds", "activeUsers" }) do
        local liste = farm[feld]
        if type(liste) == "table" then
            info.listeBekannt = true
            if next(liste) ~= nil then
                info.hatSpieler = true
            end
        end
    end
    if g_farmlandManager ~= nil and g_farmlandManager.getOwnedFarmlandIdsByFarmId ~= nil then
        local ids = g_farmlandManager:getOwnedFarmlandIdsByFarmId(farmId)
        if type(ids) == "table" then
            info.farmlands = #ids
        end
    end
    local ps = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if ps ~= nil and type(ps.placeables) == "table" then
        for _, p in ipairs(ps.placeables) do
            if p ~= nil and p.getOwnerFarmId ~= nil and p:getOwnerFarmId() == farmId then
                info.gebaeude = info.gebaeude + 1
            end
        end
    end
    return info
end

function NachbarFelderManager:getEffectiveFarmId()
    if self.farmIdResolved and self.farmId ~= nil then
        return self.farmId
    end

    local spectator = (FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID) or 0
    local kandidaten = {}
    for id = 1, 16 do
        if id ~= spectator then
            local info = self:getFarmInfoForHelper(id)
            -- Ohne bekannte Mitgliederliste lieber nicht nehmen (koennte eine Spieler-Farm sein)
            if info ~= nil and info.listeBekannt and not info.hatSpieler then
                table.insert(kandidaten, info)
            end
        end
    end

    local gewaehlt, grund = nil, nil
    local cfg = self.cfgFarmId or 0
    if cfg > 0 then
        for _, info in ipairs(kandidaten) do
            if info.farmId == cfg then
                gewaehlt, grund = info, "Server-Konfig"
            end
        end
        if gewaehlt == nil then
            print(string.format("NachbarFelder: WARNUNG Konfig farmId=%d existiert nicht oder hat Spieler - waehle automatisch", cfg))
        end
    end
    if gewaehlt == nil then
        for _, info in ipairs(kandidaten) do
            if info.farmlands == 0 and info.gebaeude == 0 then
                gewaehlt, grund = info, "automatisch (leere Farm)"
            end
        end
    end
    if gewaehlt == nil then
        for _, info in ipairs(kandidaten) do
            gewaehlt, grund = info, "automatisch (Farm ohne Spieler, hat Land/Gebaeude)"
        end
    end

    self.farmIdResolved = true
    if gewaehlt == nil then
        self.farmId = spectator
        print("NachbarFelder: WARNUNG keine Farm ohne Spieler gefunden - Helfer koennen nicht starten. " ..
              "Im Spiel eine leere Farm anlegen und Server neu starten.")
        return self.farmId
    end
    self.farmId = gewaehlt.farmId
    print(string.format("NachbarFelder: Helfer-Farm = %d '%s' (%s, Farmland %d, Gebaeude %d)",
        gewaehlt.farmId, gewaehlt.name, grund, gewaehlt.farmlands, gewaehlt.gebaeude))
    self:broadcastSettingsToClients()   -- Build 157: Clients kennen damit die Helfer-Farm
    return self.farmId
end

-- ============================================================
-- Admin-Check (Build 75)
-- Eingreifende Aktionen (Wegpunkte/Settings aendern, Helfer starten/
-- loeschen) sind nur noch fuer Admins erlaubt. Reine Anzeige (Karte
-- an/aus, WP-Liste ansehen) bleibt fuer alle frei.
-- Server-seitig: Verbindungen von Master-Usern werden ueber
-- MessageType.MASTERUSER_ADDED gemerkt (Muster aus FS25_EasyDevControls);
-- Fallback prueft den User direkt an der Connection.
-- ============================================================
function NachbarFelderManager:onMasterUserAdded(user)
    if user ~= nil and user.getConnection ~= nil then
        self.adminConnections = self.adminConnections or {}
        self.adminConnections[user:getConnection()] = true
        local name = (user.getNickname ~= nil) and user:getNickname() or "?"
        print("NachbarFelder: [ADMIN] Master-User registriert: " .. tostring(name))
    end
end

-- Server: Ist die Verbindung ein Admin? (nil = lokaler Aufruf -> ja)
function NachbarFelderManager:getIsConnectionAdmin(connection)
    if connection == nil then return true end
    if self.adminConnections ~= nil and self.adminConnections[connection] == true then
        return true
    end
    -- Fallback: direkt am User-Objekt nachsehen
    local isAdmin = false
    if g_currentMission ~= nil and g_currentMission.userManager ~= nil
       and g_currentMission.userManager.getUserByConnection ~= nil then
        local user = g_currentMission.userManager:getUserByConnection(connection)
        if user ~= nil and user.getIsMasterUser ~= nil then
            isAdmin = user:getIsMasterUser() == true
        end
    end
    return isAdmin
end

-- Client/SP: Darf der LOKALE Spieler eingreifen?
-- SP/Host = immer; Dedi-Client nur nach Admin-Login (isMasterUser).
function NachbarFelderManager:getIsLocalAdmin()
    if g_currentMission == nil then return false end
    if g_currentMission:getIsServer() then return true end
    return g_currentMission.isMasterUser == true
end

function NachbarFelderManager:notifyAdminRequired()
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            nfMeldung("NF_msg_nurAdmin"))
    end
end

-- ============================================================
-- Geld: NF-Jobs kosten nichts (Build 91)
--
-- Frueher fuellte ensureFarmMoney() das Konto der NPC-Farm 2 auf, weil
-- AIJob:updateCost() einen Job sofort mit AIMessageErrorOutOfMoney stoppt,
-- sobald das Guthaben die Helferkosten nicht mehr deckt (AIJob.lua:177).
-- Die Funktion las allerdings farm.money - ein Feld, das es in FS25 nicht
-- gibt; der Kontostand heisst farm:getBalance(). Sie hat also nie etwas
-- bewirkt (belegt: Diagnose meldete "Farm -1 EUR", und "Konto aufgefuellt"
-- stand nie im Log). Dass es trotzdem lief, lag allein daran, dass Farm 2
-- genug Guthaben hatte.
--
-- Statt das Auffuellen zu reparieren - was einen echten Eingriff in das
-- NPC-Konto und in farms.xml bedeutet haette - bekommen die Jobs jetzt
-- getPricePerMs() = 0 (siehe driveToField und die Feldarbeit). Ohne Kosten
-- gibt es keine Geldpruefung, kein Leerlaufen und nichts zurueckzusetzen.
-- ============================================================

-- ============================================================
-- WP-Erreichbarkeit lernen: Ziele die wiederholt nicht erreichbar
-- sind (AIMessageErrorNotReachable) werden für die Session als
-- Fahrziel gesperrt - analog zu fieldPathFails bei Feldern.
-- ============================================================
--- "(x=... z=...)" zu einer Wegpunkt-Nummer, leer wenn unbekannt (Build 104).
--- Liest die gemeinsame Liste, damit auch Strassenziele Koordinaten zeigen.
function NachbarFelderManager:getWaypointPosText(idx)
    local list = self.patrolWpList or self.userTrafficWaypoints
    local wp = list ~= nil and list[idx] or nil
    if wp == nil then return "" end
    return string.format(" (x=%d z=%d)",
        math.floor(wp.x or wp[1] or 0), math.floor(wp.z or wp[2] or 0))
end

-- Wegpunkt-Typ "Spawnpunkt" (Build 132): vom Admin gesetzter Ladeplatz fuer
-- neue Fahrzeuge. 3 ist bereits "Durchfahrt" (Strassenziele aus dem KI-Netz).
NachbarFelderManager.WP_CAT_SPAWN = 4

--- Ist der Wegpunkt ein Spawnpunkt? Fuer beide WP-Formen:
--- { x=, z=, cat= } (userTrafficWaypoints) und { x, z, ry, cat } (Fahrzeug-Zielliste).
function NachbarFelderManager:getIstSpawnpunkt(wp)
    if wp == nil then return false end
    return (wp.cat or wp[4] or 0) == NachbarFelderManager.WP_CAT_SPAWN
end

--- Ist die Nummer einer der selbst gesetzten Wegpunkte? (Build 104)
function NachbarFelderManager:getIsEigenerWaypoint(idx)
    return self.userTrafficWaypoints ~= nil and idx ~= nil
       and idx <= #self.userTrafficWaypoints
end

--- Ist idx in der Zielliste DIESES Fahrzeugs ein Parkpunkt? (Build 107)
function NachbarFelderManager:getIsParkpunkt(w, idx)
    if idx == nil then return false end
    if w ~= nil and w.anzahlParkpunkte ~= nil then
        return idx <= w.anzahlParkpunkte
    end
    return self:getIsEigenerWaypoint(idx)
end

function NachbarFelderManager:registerWaypointFail(idx)
    if idx == nil then return end
    self.wpFails = self.wpFails or {}
    self.wpFails[idx] = (self.wpFails[idx] or 0) + 1
    if self.wpFails[idx] == 2 then
        -- Koordinaten mitloggen: WP-Nummer = Nummer des Karten-Hotspots,
        -- damit der Punkt in-game direkt gefunden und neu gesetzt werden kann.
        local pos = self:getWaypointPosText(idx)
        print("NachbarFelder: [TRAFFIC] WP" .. tostring(idx) .. pos ..
            " fuer diese Session als Ziel gesperrt (2x nicht erreichbar)")
        -- Gesamtliste der aktuell gesperrten WPs (eine Zeile, greifbar per Log-Suche)
        local list = {}
        for i, c in pairs(self.wpFails) do
            if c >= 2 then table.insert(list, i) end
        end
        table.sort(list)
        local names = {}
        for _, i in ipairs(list) do table.insert(names, "WP" .. tostring(i)) end
        print("NachbarFelder: [TRAFFIC] Aktuell gesperrte Ziele: " .. table.concat(names, ", "))
    end
end

function NachbarFelderManager:isWaypointBlocked(idx)
    return self.wpFails ~= nil and idx ~= nil and (self.wpFails[idx] or 0) >= 2
end

-- ============================================================
-- Start-Tauglichkeit eines Wegpunkts (Build 86)
--
-- Ein Wegpunkt kann als ZIEL prima funktionieren und als STARTPLATZ trotzdem
-- unbrauchbar sein: Die KI faehrt beim GOTO bis in die Naehe des Ziels und
-- haelt auf befahrbarem Grund. Liegt die WP-Koordinate selbst ein paar Meter
-- daneben (typisch, wenn der Punkt zu Fuss am Strassenrand gesetzt wurde),
-- dann steht das Fahrzeug nach dem Einschnappen auf die exakte Koordinate
-- abseits des Navmesh - und der naechste GOTO wird nach ~60 ms abgewiesen.
--
-- Belegt im Server-Log vom 2026-09-10: Abweisungen immer bei "0m" Abstand zum
-- WP, mit UND ohne Anbaugeraet, waehrend derselbe WP als Fahrziel erreicht
-- wurde. Deshalb wird die Start-Untauglichkeit getrennt von der Ziel-Sperre
-- gefuehrt - ein solcher WP bleibt weiterhin anfahrbar.
-- ============================================================
function NachbarFelderManager:registerWaypointStartFail(idx)
    if idx == nil then return end
    self.wpStartFails = self.wpStartFails or {}
    self.wpStartFails[idx] = (self.wpStartFails[idx] or 0) + 1
    if self.wpStartFails[idx] == 2 then
        local pos = self:getWaypointPosText(idx)
        print("NachbarFelder: [TRAFFIC] WP" .. tostring(idx) .. pos ..
            " taugt nicht als Startplatz - dort halten keine Fahrzeuge mehr" ..
            (self:getIsEigenerWaypoint(idx)
                and " (Tipp: den Punkt aus dem fahrenden Fahrzeug mitten auf der Strasse neu setzen)."
                or  " (Strassenziel aus dem KI-Netz, nichts zu tun)."))
    end
end

function NachbarFelderManager:isWaypointBadStart(idx)
    return self.wpStartFails ~= nil and idx ~= nil and (self.wpStartFails[idx] or 0) >= 2
end


-- Zufälligen WP wählen; gesperrte WPs, excludeIdx und von schlafenden
-- Pool-Fahrzeugen belegte WPs werden vermieden.
-- Nach 30 Fehlversuchen wird der letzte Zufallswert akzeptiert
-- (Schutz falls fast alle WPs gesperrt sind).
-- Funktioniert für beide WP-Formen: {x=,z=} (userTrafficWaypoints)
-- und {[1]=x,[2]=z} (worker.waypoints).
--- Naechster freier Parkpunkt fuer ein Patrol-Fahrzeug (Build 105).
--- Parkpunkte sind die selbst gesetzten Wegpunkte (Nummern 1 bis
--- #userTrafficWaypoints). Steht das Fahrzeug schon an einem (< 25 m), gibt es
--- nil zurueck - dann macht es genau dort Feierabend.
--- @return integer|nil Index in w.waypoints
function NachbarFelderManager:findFreeParkpunkt(w)
    local wps = w ~= nil and w.waypoints or nil
    local anzahl = w.anzahlParkpunkte
    if anzahl == nil then
        anzahl = math.min(#(self.userTrafficWaypoints or {}), wps ~= nil and #wps or 0)
    end
    if anzahl == 0 then return nil end
    local veh = w.vehiclesToLoad and w.vehiclesToLoad[1]
    if veh == nil or veh.rootNode == nil then return nil end
    local vx, _, vz = getWorldTranslation(veh.rootNode)
    local best, bestD = nil, math.huge
    for i = 1, anzahl do
        local wp = wps[i]
        local d = MathUtil.vector2Length(vx - wp[1], vz - wp[2])
        if d < 25 then
            return nil
        end
        if d < bestD and not self:isWaypointBlocked(i) and not self:isWaypointBadStart(i)
           and not self:getIstSpawnpunkt(wp)   -- Build 132: nie auf dem Spawnpunkt parken
           and not self:isWpPosOccupied(wp[1], wp[2])
           and not self:isSpotBlockedByAnyVehicle(wp[1], wp[2], 10, veh) then
            best, bestD = i, d
        end
    end
    return best
end

-- Build 106: bevorzugte Hop-Laenge. Log 13.09.: Ziele quer ueber die Karte
-- brauchten bis zu 87 s Wegsuche (68805/70385/87358 ms) und scheiterten dann
-- oft trotzdem; waehrenddessen meldete der Waechter "30s ohne Bewegung".
-- Kurze Fahrten waren frueher in 2-12 s geplant.
local NF_HOP_MIN_M = 150
local NF_HOP_MAX_M = 700

--- @param refX number|nil, refZ number|nil Bezugspunkt fuer die Hop-Laenge;
--- ohne Angabe gilt der Wegpunkt excludeIdx (= letztes Ziel) als Bezug.
function NachbarFelderManager:pickPatrolWaypoint(waypoints, excludeIdx, refX, refZ)
    local n = waypoints ~= nil and #waypoints or 0
    if n < 1 then return nil end
    if n == 1 then return 1 end

    -- Build 106: erst ein Ziel in 150-700 m suchen; nur wenn keins frei ist,
    -- geht es wie bisher per Zufall ueber die ganze Liste.
    if refX == nil and excludeIdx ~= nil and waypoints[excludeIdx] ~= nil then
        local ref = waypoints[excludeIdx]
        refX, refZ = ref.x or ref[1], ref.z or ref[2]
    end
    if refX ~= nil and refZ ~= nil then
        local nah = {}
        for i = 1, n do
            -- Build 132: Spawnpunkte sind nie Fahrziel (sonst parkt dort jemand)
            if i ~= excludeIdx and not self:isWaypointBlocked(i)
               and not self:isWaypointBadStart(i)
               and not self:getIstSpawnpunkt(waypoints[i]) then
                local wp = waypoints[i]
                local wx, wz = wp.x or wp[1], wp.z or wp[2]
                if wx ~= nil and wz ~= nil then
                    local d = MathUtil.vector2Length(wx - refX, wz - refZ)
                    -- Build 107: isWpPosOccupied kennt nur schlafende Pool-Fahrzeuge.
                    -- Ein Fahrzeug, das gerade an einem Parkpunkt PARKT, war fuer die
                    -- Zielwahl unsichtbar - der naechste bekam denselben Punkt als Ziel
                    -- und blieb davor stehen (13.09. 12:12, Ziel WP7, "30s ohne Bewegung").
                    if d >= NF_HOP_MIN_M and d <= NF_HOP_MAX_M
                       and not self:isWpPosOccupied(wx, wz)
                       and not self:isSpotBlockedByAnyVehicle(wx, wz, 12, nil) then
                        nah[#nah + 1] = i
                    end
                end
            end
        end
        if #nah > 0 then
            return nah[math.random(#nah)]
        end
    end
    -- Build 103: Ein Wegpunkt, der als STARTPLATZ gesperrt ist, taugt auch als
    -- Ziel nichts mehr. Dort kommen Fahrzeuge zwar an, aber nie wieder weg -
    -- am 12.09. sammelten sich so vier Stueck an der Sackgasse bei WP21
    -- (x=190 z=-52). Findet die Schleife nichts Freies, bleibt es beim
    -- Zufallspunkt: lieber ein schlechtes Ziel als gar keine Fahrt.
    local idx = math.random(n)
    for _ = 1, 30 do
        if idx ~= excludeIdx and not self:isWaypointBlocked(idx)
           and not self:isWaypointBadStart(idx)
           and not self:getIstSpawnpunkt(waypoints[idx]) then
            local wp = waypoints[idx]
            local wx = wp ~= nil and (wp.x or wp[1]) or nil
            local wz = wp ~= nil and (wp.z or wp[2]) or nil
            if not self:isWpPosOccupied(wx, wz) then
                break
            end
        end
        idx = math.random(n)
    end
    return idx
end

-- ============================================================
-- Server-Konfiguration: modSettings/FS25_NachbarFelder/
--                       NachbarFelderServerConfig.xml
-- (gleicher Ordner wie NachbarFelderWaypoints.xml)
-- Die Settings-GUI wirkt nur lokal - auf dem Dedicated Server
-- gilt diese Datei. Fehlt sie, wird eine Vorlage mit den
-- aktuellen Defaults geschrieben (dann editieren + Neustart).
-- ============================================================
function NachbarFelderManager:loadServerConfig()
    if self.serverConfigLoaded then return end
    self.serverConfigLoaded = true
    local function schritt()
        local dir  = modSettingDirectory
        createFolder(dir)
        local path = dir .. "NachbarFelderServerConfig.xml"
        local root = "nachbarFelder"
        print("NachbarFelder: Server-Konfig-Pfad: " .. tostring(path))
        if not fileExists(path) then
            local xf = createXMLFile("nfConfig", path, root)
            if xf ~= nil and xf ~= 0 then
                local c = self.vehicleCatEnabled or {}
                setXMLString(xf, root .. ".hinweis",
                    "Serverseitige Einstellungen fuer FS25_NachbarFelder - Aenderungen wirken nach Server-Neustart")
                setXMLInt(xf, root .. ".farmId",              0)   -- Build 138: 0 = automatisch (leere Farm ohne Spieler)
                setXMLInt(xf, root .. ".maxWorkers",          self.MAX_ASSISTANT_WORKERS)
                setXMLInt(xf, root .. ".trafficLimit",        self.trafficLimit)
                setXMLInt(xf, root .. ".trafficTrailerSize",  self.trafficTrailerSize)
                setXMLBool(xf, root .. ".engeMap",            self.engeMap ~= false)
                setXMLInt(xf, root .. ".spawnBereichRadius",  self.spawnBereichRadius or 25)
                setXMLInt(xf, root .. ".firstSpawnDelaySecs", 180)
                setXMLInt(xf, root .. ".patrolHopsMin",       10)
                setXMLInt(xf, root .. ".patrolHopsMax",       20)
                setXMLInt(xf, root .. ".logLevel",            1)
                setXMLInt(xf, root .. ".spawnPerTick",            1)
                setXMLInt(xf, root .. ".spawnIntervalMinMinutes", 2)
                setXMLInt(xf, root .. ".spawnIntervalMaxMinutes", 5)
                setXMLFloat(xf, root .. ".parkTimeFactor",        1.0)
                setXMLInt(xf, root .. ".poolSize",                6)
                setXMLBool(xf, root .. ".fahrerfigurenAufServer", true)
                setXMLBool(xf, root .. ".rueckwaertsPlanen",      false)   -- Build 125
                setXMLBool(xf, root .. ".spielverkehrAnmelden",   true)    -- Build 152
                setXMLBool(xf, root .. ".dayRhythm",              true)
                setXMLString(xf, root .. ".zielQuelle",           "strassen")
                setXMLInt(xf, root .. ".trailerChance",           40)
                setXMLBool(xf, root .. ".vehicles.tractorsSmall",  c.TRACTORSS ~= false)
                setXMLBool(xf, root .. ".vehicles.tractorsMedium", c.TRACTORSM ~= false)
                setXMLBool(xf, root .. ".vehicles.tractorsLarge",  c.TRACTORSL ~= false)
                setXMLBool(xf, root .. ".vehicles.wheelLoaders",   c.WHEELLOADERVEHICLES ~= false)
                setXMLBool(xf, root .. ".vehicles.teleLoaders",    c.TELELOADERVEHICLES ~= false)
                saveXMLFile(xf)
                delete(xf)
                print("NachbarFelder: Konfig-Vorlage angelegt: " .. path)
            end
            return
        end
        local xf = loadXMLFile("nfConfig", path)
        if xf == nil or xf == 0 then return end
        local function readInt(key, cur, minV, maxV)
            local v = getXMLInt(xf, root .. "." .. key)
            if v == nil then return cur end
            if minV ~= nil and v < minV then v = minV end
            if maxV ~= nil and v > maxV then v = maxV end
            return v
        end
        self.MAX_ASSISTANT_WORKERS = readInt("maxWorkers",         self.MAX_ASSISTANT_WORKERS, 0, 30)
        self.trafficLimit          = readInt("trafficLimit",       self.trafficLimit,          0, 12)
        self.trafficTrailerSize    = readInt("trafficTrailerSize", self.trafficTrailerSize,    0, 3)
        self.firstSpawnDelayMs     = readInt("firstSpawnDelaySecs", 180, 0, 3600) * 1000
        self.patrolHopsMin         = readInt("patrolHopsMin",      10, 1, 99)
        self.patrolHopsMax         = readInt("patrolHopsMax",      20, 1, 99)
        -- Log-Stufe: 1 = normal (ohne Hop-/GOTO-Dauerzeilen), 2 = Debug
        self.logLevel              = readInt("logLevel",           1, 1, 2)
        -- Build 165: logLevel=2 schaltet das Debug-Log ein (Einstellung im Spiel geht vor)
        self:setDebugLog(self.logLevel >= 2)
        -- Build 138: Helfer-Farm, 0 = automatisch (siehe getEffectiveFarmId)
        self.cfgFarmId             = readInt("farmId",             0, 0, 16)
        if self.patrolHopsMax < self.patrolHopsMin then
            self.patrolHopsMax = self.patrolHopsMin
        end
        -- Spawn-Taktung (Ruckler-Vermeidung): Fahrzeuge pro Spawn-Tick und
        -- Pause zwischen Spawns (in SPIELminuten)
        self.spawnPerTick     = readInt("spawnPerTick",            1, 1, 3)
        self.spawnIntervalMin = readInt("spawnIntervalMinMinutes", 2, 0, 60)
        self.spawnIntervalMax = readInt("spawnIntervalMaxMinutes", 5, 1, 120)
        if self.spawnIntervalMax < self.spawnIntervalMin then
            self.spawnIntervalMax = self.spawnIntervalMin
        end
        -- Parkzeit-Faktor: 1.0 = Standard, 2.0 = doppelt so lange Pausen
        local ptf = getXMLFloat(xf, root .. ".parkTimeFactor")
        if ptf ~= nil and ptf >= 0.2 and ptf <= 10 then
            self.parkTimeFactor = ptf
        end
        -- Fahrzeug-Pool (Build 65): max. schlafende Fahrzeuge, 0 = Pool aus
        self.poolSize = readInt("poolSize", self.poolSize or 6, 0, 12)
        -- Tagesrhythmus (Build 68): Verkehrsdichte folgt der Uhrzeit
        local dr = getXMLBool(xf, root .. ".dayRhythm")
        if dr ~= nil then self.dayRhythm = dr end
        -- Build 104: Woher kommen die Fahrziele?
        --   strassen  = Punkte auf dem KI-Strassennetz der Karte (Standard)
        --   wegpunkte = ausschliesslich die selbst gesetzten Wegpunkte
        local zq = getXMLString(xf, root .. ".zielQuelle")
        if zq ~= nil then
            zq = string.lower(zq)
            if zq == "strassen" or zq == "wegpunkte" then
                self.zielQuelle = zq
            end
        end
        -- Gespann-Quote in % (Build 69): Ziel-Anteil Traktoren mit Geraet
        self.trailerChance = readInt("trailerChance", self.trailerChance or 40, 0, 100)
        -- Fahrzeugkategorien: Konfig-Datei ist nur noch FALLBACK (Build 71).
        -- Hat die Wegpunkt-Datei bereits Kategorien (= in der GUI gesetzt),
        -- gewinnen diese - sonst ging die GUI-Einstellung beim Neustart verloren.
        local function readBool(key, cur)
            local v = getXMLBool(xf, root .. "." .. key)
            if v == nil then return cur end
            return v
        end
        -- Umkreis um den Haendler, der frei sein muss, bevor neu gespawnt wird.
        self.spawnBereichRadius = readInt("spawnBereichRadius",
            self.spawnBereichRadius or 25, 0, 200)

        -- Fahrerfiguren nur auf dem Server weglassen (Build 95). NUR auf einem
        -- Dedicated Server auf false setzen - auf einem Spieler-Host saessen
        -- fuer diesen Spieler sonst keine Fahrer in den NF-Fahrzeugen.
        self.fahrerfigurenAufServer = readBool("fahrerfigurenAufServer",
            self.fahrerfigurenAufServer ~= false)

        -- Build 108: Rueckwaertsplanen fuer NF-Fahrzeuge ohne Anbaugeraet.
        self.rueckwaertsPlanen = readBool("rueckwaertsPlanen", self.rueckwaertsPlanen ~= false)

        -- Build 152: beim Spielverkehr anmelden (false = Verhalten bis Build 151)
        self.spielverkehrAnmelden = readBool("spielverkehrAnmelden", self.spielverkehrAnmelden ~= false)

        -- Enge Karte: schmale Wege, nur Kleintraktoren mit leichtem Geraet.
        local em = readBool("engeMap", nil)
        if em ~= nil and em ~= (self.engeMap ~= false) then
            self.engeMap = em
            self.trafficVehicleList = nil
            self.trafficTrailerList = nil
        end

        if not self.vehicleCatsFromFile then
            local c = self.vehicleCatEnabled or {}
            c.TRACTORSS           = readBool("vehicles.tractorsSmall",  c.TRACTORSS ~= false)
            c.TRACTORSM           = readBool("vehicles.tractorsMedium", c.TRACTORSM ~= false)
            c.TRACTORSL           = readBool("vehicles.tractorsLarge",  c.TRACTORSL ~= false)
            c.WHEELLOADERVEHICLES = readBool("vehicles.wheelLoaders",   c.WHEELLOADERVEHICLES ~= false)
            c.TELELOADERVEHICLES  = readBool("vehicles.teleLoaders",    c.TELELOADERVEHICLES ~= false)
            self.vehicleCatEnabled = c
            self.trafficVehicleList = nil  -- Fahrzeugliste mit neuen Kategorien neu aufbauen
        else
            print("NachbarFelder: Server-Konfig vehicles.* ignoriert - " ..
                "In-Game-Kategorien aus der Wegpunkt-Datei sind aktiv")
        end
        delete(xf)
        -- WICHTIG: eigene lokale Referenz nutzen - 'c' existiert nur im
        -- vehicles.*-Zweig (Build-71-Fehler: index nil with 'TRACTORSS')
        local c = self.vehicleCatEnabled or {}
        print("NachbarFelder: Server-Konfig geladen: maxWorkers=" ..
            tostring(self.MAX_ASSISTANT_WORKERS) ..
            " trafficLimit=" .. tostring(self.trafficLimit) ..
            " trailerSize=" .. tostring(self.trafficTrailerSize) ..
            " firstSpawnDelay=" .. tostring(math.floor((self.firstSpawnDelayMs or 180000) / 1000)) .. "s" ..
            " hops=" .. tostring(self.patrolHopsMin) .. "-" .. tostring(self.patrolHopsMax) ..
            " logLevel=" .. tostring(self.logLevel or 1) ..
            " spawnPerTick=" .. tostring(self.spawnPerTick) ..
            " spawnInterval=" .. tostring(self.spawnIntervalMin) .. "-" .. tostring(self.spawnIntervalMax) .. "min" ..
            " parkFaktor=" .. tostring(self.parkTimeFactor or 1) ..
            " poolSize=" .. tostring(self.poolSize) ..
            " fahrerfigurenAufServer=" .. tostring(self.fahrerfigurenAufServer ~= false) ..
            " rueckwaertsPlanen=" .. tostring(self.rueckwaertsPlanen ~= false) ..
            " spielverkehrAnmelden=" .. tostring(self.spielverkehrAnmelden ~= false) ..
            " dayRhythm=" .. tostring(self.dayRhythm) ..
            " zielQuelle=" .. tostring(self.zielQuelle) ..
            " trailerChance=" .. tostring(self.trailerChance) .. "%" ..
            " engeMap=" .. tostring(self.engeMap ~= false) ..
            " spawnRadius=" .. tostring(self.spawnBereichRadius) .. "m" ..
            " Kategorien: S=" .. tostring(c.TRACTORSS) .. " M=" .. tostring(c.TRACTORSM) ..
            " L=" .. tostring(c.TRACTORSL) .. " Radlader=" .. tostring(c.WHEELLOADERVEHICLES) ..
            " Telelader=" .. tostring(c.TELELOADERVEHICLES))
    end
    schritt()
end

-- ============================================================
-- Hooks installieren (einmalig, mit Guard)
-- ============================================================
function NachbarFelderManager:installHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true
    print("NachbarFelder: Hooks werden installiert")

    -- FarmlandManager: KLASSEN-Level-Hooks
    -- Für unsere Farm-ID ÜBERALL true liefern solange Helfer aktiv sind -
    -- exakt der letzte nachweislich funktionierende Stand (PFDump-Build).
    if FarmlandManager ~= nil then
        -- getIsOwnedByFarmAtWorldPosition: AI prüft Feldzugang je Position (Feldarbeit)
        -- WICHTIG: KEINE Positions-Einschränkung einbauen! Eine spätere Version
        -- beschränkte das auf "unsere aktiven Felder" (isOurActiveFieldAtPosition) -
        -- damit bekam die asynchrone Course-Generierung des FIELDWORK-Jobs
        -- nirgendwo "erlaubt" (das Original prüft das interne farmlandMapping,
        -- nicht das von uns temporär gepatchte farmland.farmId) -> der Kurs
        -- wurde nie fertig -> Helfer stand ewig mit laufendem Motor auf dem Feld.
        FarmlandManager.getIsOwnedByFarmAtWorldPosition = Utils.overwrittenFunction(
            FarmlandManager.getIsOwnedByFarmAtWorldPosition,
            function(fm, superFunc, farmId, x, z)
                if g_NachbarFelderManager ~= nil and
                   farmId ~= nil and farmId > 0 and
                   farmId == g_NachbarFelderManager.farmId and
                   g_NachbarFelderManager:hasActiveWorkers() then
                    return true
                end
                return superFunc(fm, farmId, x, z)
            end)

        -- getCanAccessLandAtWorldPosition: Zugangs-Check (GOTO-Navigation)
        -- Hier breiter halten damit die Fahrt zum Feld funktioniert
        FarmlandManager.getCanAccessLandAtWorldPosition = Utils.overwrittenFunction(
            FarmlandManager.getCanAccessLandAtWorldPosition,
            function(fm, superFunc, farmId, x, z)
                if g_NachbarFelderManager ~= nil and
                   farmId ~= nil and farmId > 0 and
                   farmId == g_NachbarFelderManager.farmId and
                   g_NachbarFelderManager:hasActiveWorkers() then
                    return true
                end
                return superFunc(fm, farmId, x, z)
            end)

        -- getIsOwnedByFarmAlongLine: Pfad-Check für Navigation (GOTO-Routing)
        if FarmlandManager.getIsOwnedByFarmAlongLine ~= nil then
            FarmlandManager.getIsOwnedByFarmAlongLine = Utils.overwrittenFunction(
                FarmlandManager.getIsOwnedByFarmAlongLine,
                function(fm, superFunc, farmId, ...)
                    if g_NachbarFelderManager ~= nil and
                       farmId ~= nil and farmId > 0 and
                       farmId == g_NachbarFelderManager.farmId and
                       g_NachbarFelderManager:hasActiveWorkers() then
                        return true
                    end
                    return superFunc(fm, farmId, ...)
                end)
        end

        print("NachbarFelder: FarmlandManager-Klassen-Hooks installiert")
    else
        print("NachbarFelder: WARNUNG - FarmlandManager-Klasse nicht verfuegbar!")
    end

    -- AIJobTypeManager: nil-Rückgabe absichern
    AIJobTypeManager.getJobTypeIndex = Utils.overwrittenFunction(
        AIJobTypeManager.getJobTypeIndex,
        function(aiJobTypeManager, superFunc, job)
            local ret = superFunc(aiJobTypeManager, job)
            if ret == nil and job ~= nil and job.name then
                return aiJobTypeManager.nameToIndex[job.name]
            end
            return ret
        end)

    -- Kein Geldabzug für unsere Farm
    if not self.moneyHookInstalled and FSBaseMission ~= nil and FSBaseMission.addMoney ~= nil then
        FSBaseMission.addMoney = Utils.overwrittenFunction(FSBaseMission.addMoney,
            function(mission, superFunc, amount, farmId, moneyType, ...)
                if g_NachbarFelderManager ~= nil
                   and amount ~= nil and amount < 0
                   and farmId == g_NachbarFelderManager.farmId
                   and g_NachbarFelderManager:hasActiveWorkers() then
                    return
                end
                return superFunc(mission, amount, farmId, moneyType, ...)
            end)
        self.moneyHookInstalled = true
    end

    -- Aufräumen beim Spielende: NUR AI-Jobs stoppen und Feldbesitz
    -- wiederherstellen - die Fahrzeuge löscht die Engine beim Shutdown
    -- selbst (BaseMission.delete). Eigenes vehicle:delete() hier erzeugte
    -- "doppelt geloescht"-Callstacks im Log (Vehicle.lua:1377), weil die
    -- Engine die Fahrzeuge danach nochmal löschte.
    -- Referenz FWA (newFile.lua): stoppt beim Delete nur die Agents.
    FSBaseMission.delete = Utils.overwrittenFunction(FSBaseMission.delete,
        function(mission, superFunc, ...)
            if g_NachbarFelderManager ~= nil then
                g_NachbarFelderManager.isShuttingDown = true
                g_NachbarFelderManager:prepareForShutdown()
            end
            return superFunc(mission, ...)
        end)

    -- Spielstand speichern
    ItemSystem.save = Utils.prependedFunction(ItemSystem.save, g_NachbarFelderManager.saveToXMLFile)
end

-- ============================================================
-- loadMap: Wird auf ALLEN Instanzen aufgerufen (Server + Client)
-- Wichtig: Server bekommt das jetzt auch, weil addModEventListener
-- bereits in init() in NachbarFelder.lua aufgerufen wird!
-- ============================================================
function NachbarFelderManager:loadMap()
    print("NachbarFelder: loadMap auf " ..
        (g_currentMission:getIsServer() and "SERVER" or "CLIENT") ..
        " (Build " .. tostring(NachbarFelderManager.BUILD) .. ")")

    -- Settings-UI: nur wenn Spieler vorhanden (Client oder SP)
    if not g_currentMission:getIsServer() or g_currentMission.isMasterUser then
        if misssionSettingsPage == nil then
            misssionSettingsPage = NachbarFelderSettingsPage.new(self)
            misssionSettingsPage:init()
            self.settingsPage = misssionSettingsPage
        end
    end

    self:addConsoleCommands()

    -- Build 153: eigene Kategorie im Hilfe-Menue (ESC > Hilfe)
    self:ladeHilfe()

    -- Build 157: Nachbar-Fahrzeuge ohne Helfer-Symbol auf der Karte
    self:installKartenHook()

    -- Client-lokale Anzeige-Einstellungen (Karten-Hotspots an/aus, Build 71)
    self:loadClientPrefs()

    -- Wegpunkte immer laden (Client: für UI + Map-Marker; Server: für Traffic-Logik)
    self:loadWaypoints()

    -- Server-seitige Initialisierung
    if g_currentMission:getIsServer() then
        self:serverSideInit()
        -- Server-Konfig SOFORT beim Start laden/anlegen - NICHT erst bei der
        -- ersten Spielminute mit Spielern (sonst existiert die Vorlage nie,
        -- wenn niemand joint). Muss NACH loadWaypoints laufen, damit die
        -- Konfig-Kategorien die WP-Datei-Werte überschreiben.
        self:loadServerConfig()
        -- Savegame-Settings zuletzt anwenden (Build 67): im Spiel
        -- gesetzte Einstellungen schlagen die Server-Konfig-Datei
        -- (die Datei liefert nur noch die Basis-Defaults).
        if self.savegameSettings ~= nil then
            self:applySettingsState(self.savegameSettings)
            self.settingsFromSavegame = true
            self.savegameSettings = nil
            print("NachbarFelder: [SETTINGS] Einstellungen aus dem Savegame angewendet")
        end
    end
end

--- Helfer-Farm fuer die Anzeige (Build 157): Server = eigene Wahl, Client = per Settings-Sync.
--- 0 = unbekannt bzw. Spectator - dann wird nichts ausgeblendet.
function NachbarFelderManager:getHelferFarmIdAnzeige()
    local fid = nil
    if g_currentMission ~= nil and g_currentMission:getIsServer() then
        fid = self.farmIdResolved and self.farmId or nil
    else
        fid = self.helferFarmIdSync
    end
    local spectator = (FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID) or 0
    if fid == nil or fid <= 0 or fid == spectator then return 0 end
    return fid
end

--- Gehoert der Karten-Hotspot zu einem Nachbar-Fahrzeug? (Build 157)
--- Kennzeichen: Besitzer-Farm des Fahrzeugs (bzw. seines Zugfahrzeugs) = Helfer-Farm. Die
--- Helfer-Farm hat nie Spieler (Build 138), andere Fahrzeuge trifft das also nicht.
function NachbarFelderManager:getIstNachbarHotspot(hotspot)
    local fid = self:getHelferFarmIdAnzeige()
    if fid == 0 or hotspot == nil then return false end
    local veh = nil
    if hotspot.getVehicle ~= nil then veh = hotspot:getVehicle() end
    if veh == nil then veh = hotspot.vehicle end
    if type(veh) ~= "table" or veh.getOwnerFarmId == nil then return false end
    if veh.getRootVehicle ~= nil then
        local root = veh:getRootVehicle()
        if root ~= nil and root.getOwnerFarmId ~= nil then veh = root end
    end
    return veh:getOwnerFarmId() == fid
end

--- Helfer-Symbol der Nachbar-Fahrzeuge auf Minimap und grosser Karte ausblenden (Build 157).
--- Beide zeichnen jeden Hotspot ueber IngameMap:drawHotspot (IngameMapElement ->
--- drawHotspotsOnly); Hotspots kennen ihr Fahrzeug (getVehicle, vgl. IngameMapElement).
--- So verwechselt niemand die Nachbarn mit eigenen Helfern. Nur mit Client, einmal.
function NachbarFelderManager:installKartenHook()
    if NachbarFelderManager.kartenHookInstalliert or g_client == nil then return end
    if IngameMap == nil or IngameMap.drawHotspot == nil then
        print("NachbarFelder: Karten-Symbole bleiben sichtbar (IngameMap.drawHotspot fehlt)")
        return
    end
    NachbarFelderManager.kartenHookInstalliert = true
    IngameMap.drawHotspot = Utils.overwrittenFunction(IngameMap.drawHotspot,
        function(map, superFunc, hotspot, ...)
            local nf = g_NachbarFelderManager
            if nf ~= nil then
                if nf.getIstNachbarHotspot ~= nil and nf:getIstNachbarHotspot(hotspot) then
                    return
                end
            end
            return superFunc(map, hotspot, ...)
        end)
    print("NachbarFelder: Helfer-Symbole der Nachbar-Fahrzeuge auf der Karte ausgeblendet")
end

--- Ingame-Hilfe laden (Build 153). Gleiches Format und gleicher Weg wie die
--- Hilfe des Spiels: HelpLineManager:loadFromXML liest <helpLines>/<category>/<page>
--- (so laedt z. B. Courseplay FS25 seine Hilfe); die $l10n_-Texte kommen aus
--- dem l10n-Block der modDesc. Nur mit Spieler (nicht auf dem reinen Dedi), einmal je Sitzung.
function NachbarFelderManager:ladeHilfe()
    if self.hilfeGeladen or g_client == nil then return end
    self.hilfeGeladen = true
    local dir = NachbarFelderManager.modDirectory
    if dir == nil or g_helpLineManager == nil or g_helpLineManager.loadFromXML == nil then
        print("NachbarFelder: Ingame-Hilfe nicht geladen (HelpLineManager nicht verfuegbar)")
        return
    end
    if g_helpLineManager ~= nil and g_helpLineManager.loadFromXML ~= nil then
        g_helpLineManager:loadFromXML(Utils.getFilename("help/helpLine.xml", dir))
        print("NachbarFelder: Ingame-Hilfe geladen (ESC > Hilfe > Lebendige Strassen)")
    else
        print("NachbarFelder: Ingame-Hilfe konnte nicht geladen werden (Hilfe-Manager fehlt)")
    end
end

-- ============================================================
-- Server-Initialisierung (einmalig, mit Guard)
-- ============================================================
function NachbarFelderManager:serverSideInit()
    if self.serverInitialized then return end
    self.serverInitialized = true
    print("NachbarFelder: Server-Initialisierung gestartet")

    -- Alle Hooks installieren
    self:installHooks()

    -- Alle verfügbaren Shop-Spawn-Punkte loggen und besten auswählen
    self:selectBestSpawnPlace()

    -- Anzahl mietbarer Helfer erhöhen
    if g_currentMission.maxNumHirables ~= nil then
        g_currentMission.maxNumHirables = g_currentMission.maxNumHirables + 20
    end

    -- Einstellungen aus dem Spielstand lesen (angewendet in loadMap)
    self:loadFromXML()
    -- Wegpunkte wurden bereits in loadMap() geladen (Client + Server)
    self:updateWpHotspots()

    local timeScale = g_currentMission:getEffectiveTimeScale()
    self.timeToNextStart = math.random(1 * timeScale, 2 * timeScale)

    -- Events auf dem Server abonnieren
    g_messageCenter:unsubscribe(MessageType.MINUTE_CHANGED, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)

    g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.deleteAllVehicles, self)

    -- Admin-Logins merken (Build 75): Grundlage fuer den Event-Admin-Check
    if MessageType ~= nil and MessageType.MASTERUSER_ADDED ~= nil then
        g_messageCenter:unsubscribe(MessageType.MASTERUSER_ADDED, self)
        g_messageCenter:subscribe(MessageType.MASTERUSER_ADDED, self.onMasterUserAdded, self)
    end

    -- MISSION_GENERATED wird bewusst NICHT mehr abonniert: Die periodische
    -- Vertragsgenerierung des Spiels feuerte onMissionStarted und löschte
    -- laufende Helfer (zudem über den falschen Tabellen-Key, ohne Aufräumen)
    -- → tote Fahrzeug-Referenzen → Lua-Fehler jede Spielminute bis zum
    -- Server-Neustart. Helfer werden nur noch entfernt, wenn ein Spieler
    -- wirklich einen Vertrag auf dem Feld STARTET (MissionStartedEvent).
    g_messageCenter:unsubscribe(MessageType.MISSION_GENERATED, self)

    -- KEIN Mission00.addPlayer Hook mehr - funktioniert nicht zuverlässig auf Dedicated Server.
    -- Stattdessen: playerSystem-Abgleich in onMinuteChanged() übernimmt die Zählung.
    -- removePlayer-Hook für sofortiges stopAllHelpers wenn letzter Spieler geht:
    if g_currentMission.playerSystem ~= nil and g_currentMission.playerSystem.removePlayer ~= nil then
        -- overwrittenFunction statt appendedFunction: unser Code läuft BEVOR der Original-
        -- removePlayer die Spieler-Daten bereinigt. So sind Agents noch gültig wenn wir
        -- stopAllHelpers() aufrufen → kein "attempt to index nil with deleteAgent".
        g_currentMission.playerSystem.removePlayer = Utils.overwrittenFunction(
            g_currentMission.playerSystem.removePlayer,
            function(ps, superFunc, player)
                if g_NachbarFelderManager ~= nil and g_currentMission:getIsServer() then
                    -- Anzahl verbleibender Spieler bestimmen (ohne den weggehenden)
                    local remaining = 0
                    if ps.players ~= nil then
                        for _, p in pairs(ps.players) do
                            if p ~= nil and p ~= player and (p.farmId or 0) > 0 then
                                remaining = remaining + 1
                            end
                        end
                    end
                    if remaining <= 0 then
                        -- Letzter Spieler: Helfer ZUERST stoppen (Agents noch gültig)
                        print("NachbarFelder: Letzter Spieler weg - stoppe alle Helfer")
                        g_NachbarFelderManager:stopAllHelpers()
                    end
                end
                -- Dann originale Spieler-Entfernung
                superFunc(ps, player)
                -- Spielerzähler aktualisieren
                if g_NachbarFelderManager ~= nil then
                    local finalCount = 0
                    if g_currentMission.players ~= nil then
                        for _, p in pairs(g_currentMission.players) do
                            if p ~= nil and (p.farmId or 0) > 0 then
                                finalCount = finalCount + 1
                            end
                        end
                    end
                    g_NachbarFelderManager.playersOnline = finalCount
                end
            end)
    end

    print("NachbarFelder: Server bereit. Naechster Start in " .. tostring(self.timeToNextStart) .. " Minuten")
end

-- ============================================================
-- prepareForShutdown: Beim Spielende NUR AI-Jobs stoppen.
-- KEINE Fahrzeuge löschen - das
-- macht die Engine direkt danach selbst (sonst "delete twice").
-- ============================================================
function NachbarFelderManager:prepareForShutdown()
    for fieldId, k in pairs(self.vehicleType or {}) do
        for _, veh in ipairs(k.vehicleType or {}) do
            if self:getIsVehicleAlive(veh) then
                self:stopAIJobSafely(veh)
            end
            self:meldeBeimSpielverkehrAb(veh)   -- Build 152: solange das Verkehrssystem noch lebt
        end
    end
    for _, p in ipairs(self.trafficPool or {}) do
        for _, veh in ipairs(p.vehicles or p.vehicleType or {}) do
            self:meldeBeimSpielverkehrAb(veh)
        end
    end
    print("NachbarFelder: Shutdown - AI-Jobs gestoppt, Fahrzeuge raeumt die Engine auf")
end

-- ============================================================
-- stopAllHelpers: Alle aktiven Helfer sofort stoppen und despawnen.
-- Wird aufgerufen wenn letzter Spieler den Server verlässt.
-- ============================================================
function NachbarFelderManager:stopAllHelpers()
    if not g_currentMission:getIsServer() then return end
    -- Alle Fahrzeuge löschen (nutzt die bestehende Logik)
    self:deleteAllVehicles()
    -- Respawn-Queue leeren: kein Spieler → kein Respawn nötig; nach Login startet der
    -- timeToNextStart-Timer ohnehin neu.
    self.pendingRespawns = {}
    -- Timer zurücksetzen damit nach Wiedereinstieg sauber neu gestartet wird
    local timeScale = (g_currentMission and g_currentMission:getEffectiveTimeScale()) or 1
    self.timeToNextStart = math.random(1 * timeScale, 4 * timeScale)
    -- Nach Login läuft erst 3 Echtzeit-Minuten Ladepause, dann der timeToNextStart-Timer.
    print(string.format(
        "NachbarFelder: Alle Helfer gestoppt (kein Spieler online). Erster Spawn ca. %d Min " ..
        "nach Spieler-Login (3 Min Echtzeit-Pause + %d Min Timer)",
        self.timeToNextStart + 3, self.timeToNextStart))
end

-- ============================================================
-- Wegpunkt an der aktuellen Spielerposition setzen
-- Taste "NachbarFelder: Wegpunkt setzen" (Standard Strg+Alt+O, die Belegung
-- im Spielerprofil kann abweichen) und die Buttons "Wegpunkt/Spawnpunkt hier
-- setzen" im Reiter Wegpunkte (Build 134). Gespeichert in der Wegpunkt-Datei
-- der Karte. Nur Admin.
-- ============================================================
function NachbarFelderManager:onInputAddWaypoint(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    self:addWaypointAtPlayer(0)
end

--- Neuen Punkt an der Position des lokalen Spielers setzen (MP-Client: an den Server senden).
--- @param cat number 0 = normaler Wegpunkt, WP_CAT_SPAWN = Spawnpunkt
--- @return boolean true, wenn gesetzt bzw. an den Server gesendet
--- @return string|nil Grund, wenn nicht gesetzt - fuer die Anzeige im Menue, wo
---                    Ingame-Meldungen vom Menue verdeckt sind
function NachbarFelderManager:addWaypointAtPlayer(cat)
    local istSpawn = cat == NachbarFelderManager.WP_CAT_SPAWN
    if not istSpawn then cat = 0 end
    local art = nfText(istSpawn and "NF_wpArt_spawn" or "NF_wpArt_wegpunkt")
    -- Nur Admins duerfen Wegpunkte setzen (Build 75)
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return false, "Nur fuer Admins"
    end
    print("NachbarFelder: [WP] " .. art .. " setzen ausgeloest")
    local x, y, z, ry
    -- Build 133: FS25 kennt kein player.currentVehicle / controlledVehicle - der
    -- Spielcode fragt das Fahrzeug nur ueber getCurrentVehicle() ab (64 Aufrufe,
    -- kein einziger Feldzugriff). Versuch 1 lief deshalb nie: zu Fuss wurde die
    -- Richtung 0, aus dem Fahrzeug Kamera-Euler-Y (nur -90..+90 Grad, Blick statt
    -- Fahrtrichtung). Fuer Spawnpunkte ist die Richtung aber entscheidend.
    -- Muster wie AISystem.lua:862-875: Fahrzeug -> rootNode + Vorwaertsvektor,
    -- zu Fuss -> getMapPositionAndLookYaw (Player.lua:1310), sonst Kamera (0,0,-1).
    -- ry-Konvention wie waehleSpawnpunkt: dx = sin(ry), dz = cos(ry).
    local richtungQuelle = nil
    local player = self.localPlayer or g_localPlayer
    if player ~= nil then
        -- Versuch 1: Fahrzeug, in dem der Spieler sitzt -> Fahrtrichtung
        local vehicle = nil
        if player.getCurrentVehicle ~= nil then
            vehicle = player:getCurrentVehicle()
        end
        if vehicle == nil then
            vehicle = player.currentVehicle or player.controlledVehicle
        end
        if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
            local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
            if math.abs(vx) > 1 or math.abs(vz) > 1 then
                x, y, z = vx, vy, vz
                -- Vorwaertsvektor statt Euler-Y: am Hang kann getWorldRotation
                -- das Y um 180 Grad kippen (x/z-Rotation gleicht es aus).
                local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
                if math.abs(dx) > 0.001 or math.abs(dz) > 0.001 then
                    ry = math.atan2(dx, dz)
                    richtungQuelle = "NF_richtung_fahrzeug"
                end
            end
        end
        -- Versuch 2: zu Fuss -> Spielerposition, Richtung = Blickrichtung
        if x == nil and player.getMapPositionAndLookYaw ~= nil then
            local px, pz, yaw = player:getMapPositionAndLookYaw()
            if px ~= nil and pz ~= nil and (math.abs(px) > 1 or math.abs(pz) > 1) then
                x, z = px, pz
                if yaw ~= nil then
                    ry = yaw
                    richtungQuelle = "NF_richtung_blick"
                end
            end
        end
        -- Versuch 2b: Spieler-rootNode (nur Position, dessen Drehung ist immer 0)
        if x == nil and player.rootNode ~= nil and player.rootNode ~= 0 then
            local px, py, pz = getWorldTranslation(player.rootNode)
            if math.abs(px) > 1 or math.abs(pz) > 1 then
                x, y, z = px, py, pz
            end
        end
    end
    -- Versuch 3: Kamera (immer in der Welt positioniert – zuverlässigster Fallback)
    if x == nil and getCamera ~= nil then
        local cam = getCamera()
        if cam ~= nil and cam ~= 0 then
            local cx, cy, cz = getWorldTranslation(cam)
            if math.abs(cx) > 1 or math.abs(cz) > 1 then
                x, y, z = cx, cy, cz
            end
        end
    end
    if x == nil then
        print("NachbarFelder: [WP] Position nicht verfuegbar")
        return false, "Position nicht verfuegbar"
    end
    -- Richtung noch offen (Versuch 2b/3): Blickrichtung der Kamera (schaut entlang -Z)
    if ry == nil and getCamera ~= nil then
        local cam = getCamera()
        if cam ~= nil and cam ~= 0 then
            local dx, _, dz = localDirectionToWorld(cam, 0, 0, -1)
            if math.abs(dx) > 0.001 or math.abs(dz) > 0.001 then
                ry = math.atan2(dx, dz)
                richtungQuelle = "NF_richtung_kamera"
            end
        end
    end
    x  = math.floor(x + 0.5)
    z  = math.floor(z + 0.5)
    ry = ry or 0
    local richtungText = nfText("NF_richtungAus", nfText(richtungQuelle or "NF_richtung_unbekannt"))
    print(string.format("NachbarFelder: [WP] Position x=%d z=%d, %s (%.0f Grad)",
        x, z, richtungText, math.deg(ry) % 360))
    -- Nähecheck: kein Duplikat innerhalb von 10 Metern
    local MIN_DIST = 10
    self.userTrafficWaypoints = self.userTrafficWaypoints or {}
    for i, wp in ipairs(self.userTrafficWaypoints) do
        local dist = math.sqrt((x - wp.x)^2 + (z - wp.z)^2)
        if dist < MIN_DIST then
            local grund = nfText("NF_msg_zuNah", i, dist)
            print("NachbarFelder: [TRAFFIC] " .. art .. " - " .. grund)
            if g_currentMission ~= nil then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                    nfText("NachbarFelder") .. ": " .. art .. " " .. grund)
            end
            return false, grund
        end
    end
    -- Spawnpunkt: das eigene Fahrzeug steht noch auf der Flaeche und zaehlt als Hindernis
    local zusatz = istSpawn and (" " .. nfText("NF_msg_jetztWegfahren")) or ""
    -- Dedi-MP-Client: Änderung an den Server schicken (der speichert + synct zurück)
    if not g_currentMission:getIsServer() then
        if g_client == nil then
            return false, "Keine Verbindung zum Server"
        end
        local op = istSpawn and NachbarFelderWaypointEditEvent.OP_ADD_SPAWN
                   or NachbarFelderWaypointEditEvent.OP_ADD
        g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(op, x, z, ry))
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            nfMeldung("NF_msg_anServer", art, x, z, richtungText) .. zusatz)
        return true
    end
    table.insert(self.userTrafficWaypoints, { x=x, z=z, ry=ry, cat=cat, label="" })
    print(string.format("NachbarFelder: [TRAFFIC] %s %d gesetzt x=%d z=%d Richtung %.0f Grad",
        art, #self.userTrafficWaypoints, x, z, math.deg(ry) % 360))
    self:saveWaypoints()
    self:updateWpHotspots()
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            nfMeldung("NF_msg_gesetzt", art, #self.userTrafficWaypoints, x, z, richtungText) .. zusatz
        )
    end
    return true
end

-- ============================================================
-- Taste "NachbarFelder: Wegpunkte nacheinander anzeigen": jeder Druck zeigt
-- den naechsten WP als Meldung. Teleportieren/Loeschen/Typ: Reiter Wegpunkte.
-- ============================================================
function NachbarFelderManager:onInputManageWaypoints(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    local wps   = self.userTrafficWaypoints or {}
    local count = #wps
    if count == 0 then
        if g_currentMission ~= nil then
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                nfMeldung("NF_msg_keineWegpunkte"))
        end
        return
    end
    self._mgr_viewIdx = (self._mgr_viewIdx % count) + 1
    local wp = wps[self._mgr_viewIdx]
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            nfMeldung("NF_msg_wpAnzeige", self._mgr_viewIdx, count,
                math.floor(wp.x), math.floor(wp.z)))
    end
end

function NachbarFelderManager:_teleportToWp(wp)
    local x, z = wp.x, wp.z
    local y = 0
    if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
        y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 1
    end
    local lp = self.localPlayer
    if lp ~= nil then
        local vehicle = lp.currentVehicle or lp.controlledVehicle
        if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
            setTranslation(vehicle.rootNode, x, y, z)
        elseif lp.rootNode ~= nil and lp.rootNode ~= 0 then
            setTranslation(lp.rootNode, x, y, z)
        end
    end
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            nfMeldung("NF_msg_teleportiert", math.floor(x), math.floor(z)))
    end
    print("NachbarFelder: [MGR] Teleport x=" .. math.floor(x) .. " z=" .. math.floor(z))
end

-- ============================================================
-- Letzten Traffic-Wegpunkt entfernen (Taste "NachbarFelder: Letzten Wegpunkt entfernen").
-- ============================================================
function NachbarFelderManager:onInputRemoveWaypoint(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    -- Nur Admins duerfen Wegpunkte loeschen (Build 75)
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return
    end
    if #self.userTrafficWaypoints == 0 then
        print("NachbarFelder: [TRAFFIC] Keine Wegpunkte vorhanden")
        return
    end
    -- Dedi-MP-Client: Änderung an den Server schicken (der speichert + synct zurück)
    if not g_currentMission:getIsServer() then
        if g_client ~= nil then
            g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                NachbarFelderWaypointEditEvent.OP_REMOVELAST))
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_INFO,
                nfMeldung("NF_msg_loeschAnServer"))
        end
        return
    end
    local removed = table.remove(self.userTrafficWaypoints)
    print("NachbarFelder: [TRAFFIC] Wegpunkt entfernt (x=" .. tostring(removed.x) ..
        " z=" .. tostring(removed.z) .. "). Verbleibend: " .. tostring(#self.userTrafficWaypoints))
    self:saveWaypoints()
    self:updateWpHotspots()
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_INFO,
            nfMeldung("NF_msg_wpEntfernt", #self.userTrafficWaypoints)
        )
    end
end

-- ============================================================
-- Wegpunkt-Änderung ausführen (läuft auf dem SERVER).
-- Aufgerufen via NachbarFelderWaypointEditEvent vom Dedi-Client.
-- saveWaypoints() schreibt die Datei und broadcastet die neue
-- Liste an alle Clients (Hotspots/WP-Seite aktualisieren sich).
-- ============================================================
NachbarFelderManager.VEHCAT_KEYS = {
    "TRACTORSS", "TRACTORSM", "TRACTORSL", "WHEELLOADERVEHICLES", "TELELOADERVEHICLES",
}

function NachbarFelderManager:applyWaypointEdit(op, a, b, c)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local E = NachbarFelderWaypointEditEvent
    if E == nil then return end
    if op == E.OP_ADD or (E.OP_ADD_SPAWN ~= nil and op == E.OP_ADD_SPAWN) then
        local x  = math.floor((a or 0) + 0.5)
        local z  = math.floor((b or 0) + 0.5)
        local ry = c or 0
        -- Build 134: OP_ADD_SPAWN legt den Punkt gleich als Spawnpunkt an
        local cat = (op == E.OP_ADD_SPAWN) and NachbarFelderManager.WP_CAT_SPAWN or 0
        local art = (cat == NachbarFelderManager.WP_CAT_SPAWN) and "Spawnpunkt" or "Wegpunkt"
        for i, wp in ipairs(self.userTrafficWaypoints) do
            local dist = math.sqrt((x - wp.x)^2 + (z - wp.z)^2)
            if dist < 10 then
                print("NachbarFelder: [TRAFFIC] " .. art .. " verworfen - nur " ..
                    tostring(math.floor(dist)) .. "m von WP" .. tostring(i))
                return
            end
        end
        table.insert(self.userTrafficWaypoints, { x=x, z=z, ry=ry, cat=cat, label="" })
        print(string.format("NachbarFelder: [TRAFFIC] %s %d gesetzt (Client-Event) x=%d z=%d Richtung %.0f Grad",
            art, #self.userTrafficWaypoints, x, z, math.deg(ry) % 360))
    elseif op == E.OP_REMOVELAST then
        if #self.userTrafficWaypoints == 0 then return end
        local removed = table.remove(self.userTrafficWaypoints)
        print("NachbarFelder: [TRAFFIC] Wegpunkt entfernt (Client-Event) x=" ..
            tostring(removed.x) .. " z=" .. tostring(removed.z) ..
            ". Verbleibend: " .. tostring(#self.userTrafficWaypoints))
    elseif op == E.OP_DELETE then
        local idx = math.floor((a or 0) + 0.5)
        if self.userTrafficWaypoints[idx] == nil then return end
        table.remove(self.userTrafficWaypoints, idx)
        print("NachbarFelder: [TRAFFIC] WP" .. tostring(idx) ..
            " geloescht (Client-Event). Verbleibend: " .. tostring(#self.userTrafficWaypoints))
    elseif op == E.OP_SETCAT then
        local idx = math.floor((a or 0) + 0.5)
        local wp  = self.userTrafficWaypoints[idx]
        if wp == nil then return end
        -- Erlaubt: 0 Normal, 1 Kurz, 2 Lang, 4 Spawnpunkt (Build 132)
        local c = math.floor((b or 0) + 0.5)
        if c ~= 1 and c ~= 2 and c ~= NachbarFelderManager.WP_CAT_SPAWN then c = 0 end
        wp.cat = c
        if c == NachbarFelderManager.WP_CAT_SPAWN then
            print(string.format("NachbarFelder: [TRAFFIC] WP%d ist jetzt Spawnpunkt (x=%d z=%d)",
                idx, math.floor(wp.x or 0), math.floor(wp.z or 0)))
        end
    elseif op == E.OP_VEHCAT then
        local key = NachbarFelderManager.VEHCAT_KEYS[math.floor((a or 0) + 0.5)]
        if key == nil then return end
        self.vehicleCatEnabled = self.vehicleCatEnabled or {}
        self.vehicleCatEnabled[key] = ((b or 0) >= 0.5)
        self.trafficVehicleList = nil
        print("NachbarFelder: [TRAFFIC] Fahrzeugkategorie " .. key .. " = " ..
            tostring(self.vehicleCatEnabled[key]) .. " (Client-Event)")
    else
        return
    end
    self:saveWaypoints()
    self:updateWpHotspots()
end

-- ============================================================
-- Besten Shop-Spawn-Punkt auswählen
-- Logkt alle verfügbaren Spawn-Punkte und wählt den, der am nächsten
-- zur Mitte aller Spawn-Punkte liegt (= zentralster Platz auf dem Hof).
-- ============================================================
function NachbarFelderManager:selectBestSpawnPlace()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces
    if sp == nil or #sp == 0 then
        print("NachbarFelder: Keine storeSpawnPlaces gefunden!")
        return
    end

    self.spawnPlaceIndex = 1
    local best = self:getNfSpawnPlace() or sp[1]
    print("NachbarFelder: Shop-Spawn [1] x=" ..
        tostring(math.floor(best.startX or 0)) ..
        " z=" .. tostring(math.floor(best.startZ or 0)) ..
        " (" .. tostring(#sp) .. " Punkte)")
end

--- Spawnplatz der NachbarFelder-Fahrzeuge (Build 96): der Shop-Spawnplatz,
--- den auch das Spiel fuer gekaufte Fahrzeuge nimmt - bei aktiver Mod
--- "Filiallieferungen" also der Lieferort des Spielers.
---
--- Build 94 hatte stattdessen den Original-Shop der Karte wiederhergestellt.
--- Gemessen war das schlechter: vom Original-Shop (Beuren x=-157 z=-138) kam am
--- 11.09. KEIN einziger GOTO weg (0 von 5, jeweils ~55 ms NotReachable), vom
--- Lieferort (x=-528 z=190) am 10.09. beide frischen Spawns (2 von 2).
--- Deshalb wieder der Platz des Spiels - live, ohne Kopie, damit eine spaetere
--- Aenderung des Lieferorts sofort mitwirkt.
function NachbarFelderManager:getNfSpawnPlace()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces
    return sp and sp[1] or nil
end

--- Spawnplatz-Liste fuer VehicleLoadingData:setLoadingPlace() (Build 96):
--- unveraendert die Liste des Spiels. Beim ersten Spawn wird der tatsaechliche
--- Platz einmal geloggt (bei Serverstart hat Filiallieferungen ihn evtl. noch
--- nicht verschoben, die Zeile "Shop-Spawn [1]" zeigt dann den Kartenplatz).
function NachbarFelderManager:getNfSpawnPlaces()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces or {}
    if not self.spawnPlatzGemeldet and sp[1] ~= nil then
        self.spawnPlatzGemeldet = true
        print(string.format("NachbarFelder: Spawn am Shop-Platz des Spiels x=%.0f z=%.0f",
            sp[1].startX or 0, sp[1].startZ or 0))
    end
    return sp
end

--- Strassenrichtung aus den KI-Strassensplines der Karte (Build 98).
---
--- Der GOTO-Job braucht eine Zielrichtung (AIParameterPositionAngle:validate
--- lehnt ohne Winkel ab) und die KI rangiert am Ziel, bis sie genau so steht
--- (AITaskDriveTo -> setAITarget mit dirX/dirZ). Bisher war das die beim Setzen
--- des Wegpunkts gespeicherte ry - zu Fuss gesetzt ist die aber nicht die
--- Strassenrichtung, und das Gespann drehte sich am Ziel quer.
---
--- Die Karte bringt die Strassen mit, auf denen die KI faehrt: jede Spline unter
--- einem onCreateAIRoadSpline-Knoten landet auf dem Server in
--- aiSystem.roadSplines und im Navigationsnetz (AISystem.lua:217-236; Beuren:
--- ein Knoten in maps/mapEU.i3d). AISystem liest sie selbst mit
--- getSplinePosition als Weltkoordinaten (AISystem.lua:1272-1274).
---
--- Hier werden sie einmal alle 4 m abgetastet und in ein 32-m-Raster gelegt;
--- eine Abfrage prueft dann nur die Nachbarzellen.
--- @return boolean true, wenn die Stuetzpunkte vorliegen
function NachbarFelderManager:buildRoadSamples()
    if self.roadSamples ~= nil then return true end
    local ai = g_currentMission and g_currentMission.aiSystem
    local splines = ai and ai.roadSplines
    if splines == nil or #splines == 0 then return false end

    local cell = 32
    local grid, n = {}, 0
    for _, spline in ipairs(splines) do
        local function schritt()
            local len = getSplineLength(spline)
            if len == nil or len < 1 then return end
            local steps = math.max(1, math.ceil(len / 4))
            local px, py, pz = getSplinePosition(spline, 0)   -- Build 127: Hoehe mit
            for i = 1, steps do
                local x, y, z = getSplinePosition(spline, i / steps)
                local dx, dz = x - px, z - pz
                local l = math.sqrt(dx * dx + dz * dz)
                if l > 0.01 then
                    local mx, mz = (x + px) * 0.5, (z + pz) * 0.5
                    local key = math.floor(mx / cell) .. ":" .. math.floor(mz / cell)
                    local list = grid[key]
                    if list == nil then
                        list = {}
                        grid[key] = list
                    end
                    list[#list + 1] = { mx, mz, dx / l, dz / l, ((y or 0) + (py or 0)) * 0.5 }   -- [5] Fahrbahnhoehe
                    n = n + 1
                end
                px, py, pz = x, y, z
            end
        end
        schritt()
    end
    self.roadSamples    = grid
    self.roadSampleCell = cell

    -- Abdeckung der Wegpunkte gleich mitloggen: wer keine KI-Strasse im
    -- Umkreis hat, parkt weiter mit der gespeicherten Richtung.
    local ohne, mit = {}, 0
    for i, wp in ipairs(self.userTrafficWaypoints or {}) do
        if self:getRoadHeadingAt(wp.x or 0, wp.z or 0, 20) ~= nil then
            mit = mit + 1
        else
            table.insert(ohne, "WP" .. tostring(i))
        end
    end
    print(string.format("NachbarFelder: [TRAFFIC] Strassenrichtung: %d KI-Splines, %d Stuetzpunkte" ..
        " - %d von %d Wegpunkten parken laengs zur Strasse%s",
        #splines, n, mit, #(self.userTrafficWaypoints or {}),
        #ohne > 0 and (" (ohne KI-Strasse im Umkreis 20 m: " .. table.concat(ohne, ", ") .. ")") or ""))

    -- Build 104: Fahrziele gleich mit erzeugen - das laeuft hier ohne Spieler.
    self:buildRoadWaypointList()
    return true
end

--- Fahrziele aus dem KI-Strassennetz erzeugen (Build 104).
---
--- Handgesetzte Wegpunkte liegen zwangslaeufig NEBEN der Fahrbahn - dort haelt
--- die KI im Seitenstreifen und kommt nicht wieder weg (Logs 11./12.09.:
--- Dauerparker auf x=190/-52, x=-918/358, x=-888/334). Punkte des Strassennetzes
--- haben dieses Problem nicht: die KI faehrt selbst darauf.
---
--- Aus den ~10000 Stuetzpunkten wird eine handliche Auswahl mit Mindestabstand
--- ausgeduennt, damit Ziele ueber die Karte verteilt sind und nicht drei Stueck
--- in derselben Kurve liegen. Kategorie 3 = Durchfahrt (Build 105).
--- @return table|nil Liste { x, z, ry, kategorie }
function NachbarFelderManager:buildRoadWaypointList()
    if self.roadWaypoints ~= nil then return self.roadWaypoints end
    if self.roadSamples == nil and not self:buildRoadSamples() then return nil end

    local flach = {}
    for _, list in pairs(self.roadSamples) do
        for _, sp in ipairs(list) do
            flach[#flach + 1] = sp
        end
    end
    if #flach == 0 then return nil end

    -- Mischen, sonst haengt die Auswahl an der Reihenfolge der Rasterzellen
    for i = #flach, 2, -1 do
        local j = math.random(i)
        flach[i], flach[j] = flach[j], flach[i]
    end

    local MIN_ABSTAND, MAX_ZIELE = 200, 150
    local gewaehlt = {}
    for _, sp in ipairs(flach) do
        local frei = true
        for _, g in ipairs(gewaehlt) do
            if MathUtil.vector2Length(sp[1] - g[1], sp[2] - g[2]) < MIN_ABSTAND then
                frei = false
                break
            end
        end
        if frei then
            gewaehlt[#gewaehlt + 1] = { sp[1], sp[2],
                MathUtil.getYRotationFromDirection(sp[3], sp[4]), 3 }
            if #gewaehlt >= MAX_ZIELE then break end
        end
    end

    self.roadWaypoints = gewaehlt
    print(string.format("NachbarFelder: [TRAFFIC] %d Fahrziele aus dem KI-Strassennetz erzeugt" ..
        " (Mindestabstand %d m)", #gewaehlt, MIN_ABSTAND))
    return gewaehlt
end

--- Fahrziel-Liste der Patrol-Fahrzeuge (Build 104): eigene Wegpunkte zuerst,
--- danach - bei zielQuelle="strassen" - die Punkte des KI-Strassennetzes.
--- Die Nummerierung bleibt damit stabil: WP1..WP38 sind weiter deine Punkte.
--- Eigene Punkte behalten ihre Pausen-Kategorie (dort wird geparkt),
--- Strassenziele bekommen Kategorie 3 = Durchfahrt (Build 105): geparkt wird
--- nur an Parkpunkten, nie auf der Fahrbahn.
--- @return table Liste { x, z, ry, kategorie }
function NachbarFelderManager:getPatrolWaypointList()
    if self.patrolWpList ~= nil then return self.patrolWpList end
    local liste = {}
    for _, wp in ipairs(self.userTrafficWaypoints or {}) do
        liste[#liste + 1] = { wp.x, wp.z, wp.ry or 0, wp.cat or 0 }
    end
    local eigene = #liste
    if (self.zielQuelle or "strassen") == "strassen" then
        for _, rp in ipairs(self:buildRoadWaypointList() or {}) do
            liste[#liste + 1] = { rp[1], rp[2], rp[3], rp[4] }
        end
    end
    self.patrolWpList = liste
    print(string.format("NachbarFelder: [TRAFFIC] Fahrziele gesamt: %d (%d eigene Wegpunkte" ..
        " + %d Strassenziele, zielQuelle=%s)",
        #liste, eigene, #liste - eigene, tostring(self.zielQuelle or "strassen")))
    return liste
end

--- Naechster Punkt der KI-Strasse zu (x, z) (Build 99).
---
--- Build 102: optionaler Mindestabstand. Fuer die Rettung eines festsitzenden
--- Fahrzeugs ist der naechstgelegene Punkt naemlich wertlos: die nSeries stand
--- am 12.09. auf x=190 z=-52 DIREKT auf der Strasse und wurde trotzdem bei
--- jedem Aufwecken dreimal abgewiesen. Nicht die Entfernung zur Strasse ist
--- dort das Problem, sondern der Platz selbst. Mit Mindestabstand verlaesst das
--- Fahrzeug die tote Zone wirklich.
--- @param minDist number|nil nur Punkte ab diesem Abstand (Vorgabe 0)
--- @return number|nil rx, number|nil rz Punkt auf der Strasse
--- @return number|nil ry Y-Rotation der Strasse dort
--- @return number|nil dist Abstand in m
function NachbarFelderManager:getNearestRoadPoint(x, z, maxDist, minDist)
    if self.roadSamples == nil and not self:buildRoadSamples() then
        return nil
    end
    local cell = self.roadSampleCell
    local cx, cz = math.floor(x / cell), math.floor(z / cell)
    local r = math.ceil(maxDist / cell)
    local minD2 = (minDist or 0) * (minDist or 0)
    local best, bestD2 = nil, maxDist * maxDist
    for ix = cx - r, cx + r do
        for iz = cz - r, cz + r do
            local list = self.roadSamples[ix .. ":" .. iz]
            if list ~= nil then
                for _, sp in ipairs(list) do
                    local ddx, ddz = sp[1] - x, sp[2] - z
                    local d2 = ddx * ddx + ddz * ddz
                    if d2 < bestD2 and d2 >= minD2 then
                        best, bestD2 = sp, d2
                    end
                end
            end
        end
    end
    if best == nil then return nil end
    return best[1], best[2],
        MathUtil.getYRotationFromDirection(best[3], best[4]), math.sqrt(bestD2), best[5]   -- Build 127: [5] Hoehe
end

--- Punkt der KI-Strasse mit passender Fahrtrichtung (Build 136).
---
--- KI-Strassen sind Einbahn-Splines: fuer Gegenverkehr legt der Kartenbauer eine
--- zweite, umgekehrte Spline daneben (Bergisch Land: 61 von 68 Strassen-Splines
--- haben einen Zwilling mit "R" am Namen, 7 sind echte Einbahnen). Bis Build 135
--- wurde die Richtung des naechsten Punkts einfach um 180 Grad gedreht, wenn sie
--- nicht zum Ziel zeigte - beim Ladeplatz, bei der Zielrichtung des Fahrauftrags
--- und bei jeder Rettung. Auf einer Einbahn steht Fahrzeug oder Ziel dann gegen die
--- Fahrtrichtung, und die KI (nur vorwaerts, AIDrivable:getAIAllowsBackwards = false,
--- AIDrivable.lua:587) lehnt nach ~50 ms ab (AIMessageErrorNotReachable). Log
--- 19.09. Bergisch Land: Ziel WP50 von drei Standorten sofort abgewiesen, alle drei
--- Ladeplaetze am Shop ebenso.
---
--- Jetzt: unter den Punkten im Umkreis der naechste, dessen Richtung hoechstens
--- 60 Grad von der Wunschrichtung abweicht (bei Gegenverkehr also die Zwillings-
--- Spur). Gibt es keinen, der naechste Punkt MIT seiner eigenen Richtung - nie
--- gedreht; die KI sucht sich den Weg dann selbst uebers Netz.
--- @param wantDx number|nil Wunschrichtung x (nil = egal, naechster Punkt)
--- @param wantDz number|nil Wunschrichtung z
--- @return number|nil rx, number|nil rz, number|nil ry, number|nil dist, number|nil h
--- @return boolean passt true, wenn die Richtung zur Wunschrichtung passt
function NachbarFelderManager:getRoadPointInRichtung(x, z, maxDist, minDist, wantDx, wantDz)
    if self.roadSamples == nil and not self:buildRoadSamples() then
        return nil
    end
    local wl = (wantDx ~= nil and wantDz ~= nil) and math.sqrt(wantDx * wantDx + wantDz * wantDz) or 0
    local wx, wz = 0, 0
    if wl > 0.001 then wx, wz = wantDx / wl, wantDz / wl end
    local cell = self.roadSampleCell
    local cx, cz = math.floor(x / cell), math.floor(z / cell)
    local r = math.ceil(maxDist / cell)
    local minD2 = (minDist or 0) * (minDist or 0)
    local maxD2 = maxDist * maxDist
    local best, bestD2 = nil, maxD2
    local passend, passD2 = nil, maxD2
    for ix = cx - r, cx + r do
        for iz = cz - r, cz + r do
            local list = self.roadSamples[ix .. ":" .. iz]
            if list ~= nil then
                for _, sp in ipairs(list) do
                    local ddx, ddz = sp[1] - x, sp[2] - z
                    local d2 = ddx * ddx + ddz * ddz
                    if d2 >= minD2 then
                        if d2 < bestD2 then best, bestD2 = sp, d2 end
                        -- cos(60 Grad) = 0.5
                        if wl > 0.001 and d2 < passD2 and sp[3] * wx + sp[4] * wz >= 0.5 then
                            passend, passD2 = sp, d2
                        end
                    end
                end
            end
        end
    end
    local sp, d2, passt = best, bestD2, false
    if passend ~= nil then sp, d2, passt = passend, passD2, true end
    if sp == nil then return nil end
    return sp[1], sp[2], MathUtil.getYRotationFromDirection(sp[3], sp[4]), math.sqrt(d2), sp[5], passt
end

--- Richtung der naechsten KI-Strasse an (x, z) (Build 98).
--- @return number|nil Y-Rotation (wie MathUtil.getYRotationFromDirection), nil ohne Strasse
--- @return number|nil Abstand zur Strasse in m
function NachbarFelderManager:getRoadHeadingAt(x, z, maxDist)
    local _, _, ry, dist = self:getNearestRoadPoint(x, z, maxDist)
    return ry, dist
end

--- Y-Rotation, mit der das Spiel Fahrzeuge auf den Spawnplatz stellt (Build 94):
--- VehicleLoadingData:setLoadingPlace() nimmt die Querrichtung des Platzes,
--- MathUtil.getYRotationFromDirection(place.dirPerpX, place.dirPerpZ).
function NachbarFelderManager:getNfSpawnRotY()
    local place = self:getNfSpawnPlace()
    if place ~= nil and place.dirPerpX ~= nil and place.dirPerpZ ~= nil
       and (math.abs(place.dirPerpX) > 0.0001 or math.abs(place.dirPerpZ) > 0.0001) then
        return MathUtil.getYRotationFromDirection(place.dirPerpX, place.dirPerpZ)
    end
    return 0
end

--- Fahrerfigur eines NF-Fahrzeugs auf dem Server weglassen (Build 95).
---
--- Das Spiel loescht und laedt die Fahrerfigur bei JEDEM KI-Start neu
--- (Enterable:setVehicleCharacter, Enterable.lua:1240/1259). Auf dem Dedicated
--- Server kostete das in 67 Minuten 32 s Ladezeit, bis zu 524 ms am Stueck -
--- und jeder dieser Stillstaende trifft alle Spieler. Gezeichnet wird auf dem
--- Server aber nichts (Render System Driver: NULL).
---
--- Sicher, weil die Figur nicht uebers Netz geht: Enterable:onWriteStream()
--- schickt nur isTabbable und den steuernden Nutzer, keinen Figurenstil - die
--- Clients bauen ihre Figur selbst. Und weil das Spiel Spezialisierungs-
--- Funktionen als Felder auf jedes Fahrzeug kopiert
--- (SpecializationUtil.copyTypeFunctionsInto: target[funcName] = func), greift
--- das Ueberschreiben pro Fahrzeug fuer jeden Aufruf, auch fuer
--- setRandomVehicleCharacter, das intern self:setVehicleCharacter() ruft.
---
--- Wirkt nur mit fahrerfigurenAufServer=false in der Server-Konfig und nur auf
--- der Instanz, die der Server ist - der Client eines Spielers ist nie betroffen.
--- Rueckwaertsplanen fuer ein NF-Fahrzeug erlauben (Build 108).
---
--- Das Spiel laesst KI-Fahrauftraege grundsaetzlich nicht rueckwaerts planen:
--- AIDrivable:getAIAllowsBackwards() gibt fest false zurueck (AIDrivable.lua:587),
--- createAgent reicht den Wert an createVehicleNavigationAgent weiter
--- (AIDrivable.lua:370-372). Am 13.09. stand ein TK4 mit der Front vor einem
--- Gebaeude und drueckte minutenlang vorwaerts dagegen, obwohl ein kurzes
--- Zuruecksetzen gereicht haette.
---
--- Die Funktion wird pro Fahrzeug ueberschrieben (Spezialisierungsfunktionen
--- sind Instanzfelder, SpecializationUtil.copyTypeFunctionsInto). Die Pruefung
--- laeuft bei JEDEM Auftrag neu, weil createAgent jedes Mal neu fragt:
--- mit angehaengtem Geraet bleibt es beim Spielverhalten (kein Rueckwaerts-
--- rangieren mit Anhaenger - Einknickgefahr).
function NachbarFelderManager:applyRueckwaertsPlanen(vehicle)
    if self.rueckwaertsPlanen == false then return end
    if vehicle == nil or vehicle.getAIAllowsBackwards == nil or vehicle.nf_rueckwaerts then return end
    vehicle.nf_rueckwaerts = true
    local original = vehicle.getAIAllowsBackwards
    vehicle.getAIAllowsBackwards = function(v, ...)
        local impl = nil
        if v.getAttachedImplements ~= nil then impl = v:getAttachedImplements() end
        if impl == nil or #impl == 0 then
            return true
        end
        return original(v, ...)
    end
end

--- Fahrerfigur bleibt im Fahrzeug, bis es geloescht wird (Build 168).
---
--- Das Spiel entlaedt die Figur bei jedem Auftragsende (restoreVehicleCharacter ->
--- deleteVehicleCharacter, wenn niemand drinsitzt) und laedt beim naechsten Start eine
--- neue (setRandomVehicleCharacter -> setVehicleCharacter -> loadCharacter). Nachbar-
--- Fahrzeuge bekommen bei jedem Ziel, Parkende und Waechter-Schritt einen neuen Auftrag -
--- jedes Mal Figur weg und neu laden = Ruckler beim Spieler. Jetzt: nach dem ersten
--- Laden werden Loeschen und Neuladen fuer dieses Fahrzeug uebersprungen, solange kein
--- Spieler drinsitzt. Beim Loeschen des Fahrzeugs raeumt Enterable:onDelete die Figur
--- direkt ab (spec.vehicleCharacter:delete(), ohne deleteVehicleCharacter) - nichts bleibt
--- liegen. Die Figur ist sichtbar wie bisher (Sichtbarkeit nur nach Kamera-Abstand,
--- VehicleCharacter:updateVisibility), also auch beim Parken.
---
--- Laeuft auf Server und Clients: die Clients laden ihre Figur selbst (Build 95). Auf dem
--- Client wird ein Nachbar-Fahrzeug wie bei den Karten-Symbolen (Build 157) an der
--- Helfer-Farm erkannt (pruefeFahrerfiguren). Mit fahrerfigurenAufServer=false bleibt es
--- auf dem Server beim Weglassen der Figur (applyServerDriverFigure).
function NachbarFelderManager:applyFahrerBleibt(vehicle)
    if vehicle == nil or vehicle.nf_fahrerBleibt or vehicle.nf_keineFigur then return end
    if vehicle.spec_enterable == nil or vehicle.setVehicleCharacter == nil
       or vehicle.deleteVehicleCharacter == nil then return end
    vehicle.nf_fahrerBleibt = true
    local origSet = vehicle.setVehicleCharacter
    local origDelete = vehicle.deleteVehicleCharacter
    local function spielerDrin(v)
        return v.getIsControlled ~= nil and v:getIsControlled()
    end
    vehicle.setVehicleCharacter = function(v, ...)
        if v.nf_figurGeladen and not spielerDrin(v) then return end
        -- Merker erst danach setzen: origSet ruft selbst deleteVehicleCharacter
        origSet(v, ...)
        v.nf_figurGeladen = true
    end
    vehicle.deleteVehicleCharacter = function(v, ...)
        if v.nf_figurGeladen and not spielerDrin(v) then return end
        v.nf_figurGeladen = false
        return origDelete(v, ...)
    end
end

--- Nachbar-Fahrzeuge auf Server und Client mit applyFahrerBleibt versehen (Build 168).
--- Alle 2 s; Kennzeichen wie bei den Karten-Symbolen: Besitzer-Farm = Helfer-Farm.
function NachbarFelderManager:pruefeFahrerfiguren()
    if g_time == nil or (self.fahrerPruefungAm or 0) > g_time then return end
    self.fahrerPruefungAm = g_time + 2000
    local fid = self:getHelferFarmIdAnzeige()
    if fid == 0 or g_currentMission == nil or g_currentMission.vehicleSystem == nil then return end
    local liste = g_currentMission.vehicleSystem.vehicles
    if liste == nil then return end
    for _, v in pairs(liste) do
        if type(v) == "table" and v.isDeleted ~= true and not v.nf_fahrerBleibt and v.spec_enterable ~= nil
           and v.getOwnerFarmId ~= nil and v:getOwnerFarmId() == fid then
            self:applyFahrerBleibt(v)
        end
    end
end

function NachbarFelderManager:applyServerDriverFigure(vehicle)
    if self.fahrerfigurenAufServer ~= false then return end
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if vehicle == nil or vehicle.spec_enterable == nil or vehicle.setVehicleCharacter == nil then return end
    if vehicle.nf_keineFigur then return end
    vehicle.nf_keineFigur = true
    vehicle.setVehicleCharacter = function() end
    if not self.figurHinweisGezeigt then
        self.figurHinweisGezeigt = true
        print("NachbarFelder: Fahrerfiguren der NF-Fahrzeuge werden auf dem Server nicht geladen" ..
            " (fahrerfigurenAufServer=false) - bitte pruefen, ob auf den Clients weiter Fahrer sitzen")
    end
end

-- ============================================================
-- registerGlobalActionEvents: Kompatibilität (Legacy-Hook)
-- ============================================================
function NachbarFelderManager:registerGlobalActionEvents(player, inputBinding)
    -- Nichts mehr nötig hier; alles läuft über addPlayerActionEvents und loadMap
end

-- ============================================================
-- stopAIJobSafely: Laufenden AI-Job stoppen BEVOR das Fahrzeug
-- gelöscht wird. Ohne diesen Stopp bleibt der Job im aiSystem
-- registriert und crasht dann jeden Frame in AIJobFieldWork:stop()
-- mit "attempt to index nil with 'deleteAgent'" (Vehicle weg).
-- API verifiziert (FS25-LUADOC): AIJobVehicle:stopCurrentAIJob(message),
-- AIJobVehicle:getJob(), AIJobVehicle:getIsAIActive()
-- ============================================================
function NachbarFelderManager:stopAIJobSafely(vehicle)
    local function schritt()
        if vehicle == nil then return end
        local hasJob = false
        if vehicle.getJob ~= nil and vehicle:getJob() ~= nil then
            hasJob = true
        elseif vehicle.getIsAIActive ~= nil and vehicle:getIsAIActive() then
            hasJob = true
        end
        if hasJob and vehicle.stopCurrentAIJob ~= nil then
            local msg = nil
            if AIMessageSuccessStoppedByUser ~= nil and AIMessageSuccessStoppedByUser.new ~= nil then
                msg = AIMessageSuccessStoppedByUser.new()
            end
            vehicle:stopCurrentAIJob(msg)
        end
    end
    schritt()
end

-- WP-Kategorien: 0=Normal(20-60s)  1=Kurz(5-20s)  2=Lang(2-5min)
-- Build 105: 3 = Durchfahrt (Strassenziele) - kein Parken auf der Fahrbahn
local NF_CAT_NAMES = { [0]="Normal", [1]="Kurz", [2]="Lang", [3]="Durchfahrt", [4]="Spawnpunkt" }

-- ============================================================
-- Log-Stufen (Build 130): 1 = normal (Standard), 2 = Debug.
-- Auf Stufe 1 entfallen die Dauerschreiber (jede Hop-/GOTO-Zeile,
-- ~6-12 Zeilen/Minute bei 4 Patrols) - spart String-Müll (Lua-GC)
-- und Schreib-I/O und hält das Log lesbar.
-- Für Fehlersuche in der ServerConfig logLevel=2 setzen.
-- Fehler/Lebenszyklus loggen immer.
-- ============================================================
--- Debug-Log an/aus (Build 165). Steuert NachbarFelderLog.debug (alle Log-Zeilen
--- der Mod) und die alte Log-Stufe (Dauerschreiber nur auf Stufe 2).
function NachbarFelderManager:setDebugLog(an)
    an = an == true
    local vorher = self.debugLog == true
    self.debugLog = an
    self.logLevel = an and 2 or 1
    if NachbarFelderLog ~= nil then
        NachbarFelderLog.debug = an
    end
    if an ~= vorher then
        print("NachbarFelder: Debug-Log " .. (an and "an" or "aus"))
    end
end

function NachbarFelderManager:log(lvl, msg)
    if (self.logLevel or 1) >= lvl then
        print(msg)
    end
end

-- Verbundene Spieler zaehlen (Build 131) - gleiche Regel wie onMinuteChanged
-- (farmId > 0 = wirklich im Spiel). Benannte Funktion ohne
-- Closure, damit der Sekundentakt im update() keinen GC-Muell erzeugt.
local function nfCountConnectedPlayers()
    local n = 0
    local players = g_currentMission ~= nil and g_currentMission.players or nil
    if players ~= nil then
        for _, player in pairs(players) do
            if player ~= nil and (player.farmId or 0) > 0 then
                n = n + 1
            end
        end
    end
    return n
end

-- Mähdrescher-Tank leeren. Als benannte Funktion ausgelagert (Build 79):
-- nfEmptyCombineTank(veh) erzeugt KEINE Closure pro Aufruf -
-- die frühere anonyme Funktion war Pro-Frame-GC-Müll.
local function nfEmptyCombineTank(veh)
    for idx, fu in ipairs(veh:getFillUnits()) do
        if (fu.fillLevel or 0) > 0 then
            veh:setFillUnitFillLevel(fu.fillUnitIndex or idx, 0, fu.fillType)
        end
    end
end

-- Parkzeiten mit Server-Konfig-Faktor skalieren (parkTimeFactor,
-- z.B. 2.0 = doppelt so lange Pausen → weniger Fahr-/Spawn-Zyklen)
function NachbarFelderManager:scaleParkSecs(secs)
    local f = self.parkTimeFactor or 1
    if f == 1 then return secs end
    return math.max(3, math.floor(secs * f + 0.5))
end

local function nfCatParkSecs(cat)
    -- Build 105: Strassenziele sind reine Durchfahrt - nur der Moment, den der
    -- naechste Auftrag zum Anlaufen braucht, keine Standzeit auf der Strasse.
    if cat == 3 then return 2 end
    local s
    if cat == 1 then s = math.random(5, 20)
    elseif cat == 2 then s = math.random(120, 300)
    else s = math.random(20, 60) end
    if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.scaleParkSecs ~= nil then
        s = g_NachbarFelderManager:scaleParkSecs(s)
    end
    return s
end

-- ============================================================
-- update: NUR auf Server (oder SP)
-- ============================================================
function NachbarFelderManager:update(dt)
    -- Ruckler-Diagnose (Build 74): auffaellig lange Frames protokollieren,
    -- damit im Log sichtbar wird, WOMIT ein Ruckler zusammenfaellt
    -- (Spawn? Loeschung? Speichern? gar nichts von uns?).
    -- Laeuft auf Server UND Client (vor dem Server-Guard), max. 80 Eintraege.
    -- Frame-Spike-Telemetrie (Build 78): NUR bei verbundenen Spielern messen.
    -- Der Dedi drosselt im Leerlauf auf 5 Ticks/s (= konstant 200ms/Frame) -
    -- das ist normales Idle-Verhalten, keine Last. Die frueheren Dauer-
    -- Meldungen "50 langsame Frames, max 200ms" rund um die Uhr waren
    -- deshalb Fehlalarme (Beleg: Wert fiel exakt beim Spieler-Join).
    -- Schwelle zusaetzlich ADAPTIV: > max(100ms, 2.5x gleitender Schnitt),
    -- damit Uebergaenge zwischen Idle- und Aktiv-Tickrate nicht fehlzaehlen.
    if dt ~= nil and dt > 0 then
        if self._dtAvg == nil then
            self._dtAvg = dt
        else
            self._dtAvg = self._dtAvg * 0.98 + dt * 0.02
        end
    end
    -- Build 168: Fahrerfiguren der Nachbar-Fahrzeuge bleiben sitzen (Server und Client)
    self:pruefeFahrerfiguren()
    -- Build 98: Strassen-Stuetzpunkte vorberechnen, solange niemand online ist -
    -- dann trifft die einmalige Rechenzeit keinen Spieler. Ohne Splines
    -- (noch nicht geladen / Karte ohne) ist der Aufruf nur ein Tabellen-Check.
    if self.roadSamples == nil and g_currentMission:getIsServer()
       and (self.playersOnline or 0) == 0 then
        self:buildRoadSamples()
    end
    -- Build 105: Fahrzeug- und Geraetelisten ebenfalls ohne Spieler bauen - sie
    -- lesen jetzt pro Kandidat eine XML-Datei (nfLoadSpecs).
    if self.serverConfigLoaded and g_currentMission:getIsServer()
       and (self.playersOnline or 0) == 0 then
        if self.trafficVehicleList == nil then self:buildTrafficVehicleList() end
        if self.trafficTrailerList == nil then self:buildTrafficTrailerList() end
    end

    local perfActive = true
    if g_currentMission:getIsServer() then
        -- Build 131: Spieler im SEKUNDENTAKT pruefen statt playersOnline
        -- (nur minuetlich aktualisiert). Der Dedi drosselt beim letzten
        -- Disconnect sofort auf 5 Ticks/s - bis zur naechsten Spielminute
        -- wurden diese Leerlauf-Frames als "langsam" gezaehlt (Test 17.09.:
        -- 18+2 bzw. 14+5 Frames direkt nach dem Verlassen).
        if self._perfPlayersAt == nil or (g_time or 0) >= self._perfPlayersAt then
            self._perfPlayersAt = (g_time or 0) + 1000
            local n = nfCountConnectedPlayers()
            self._perfPlayers = n or (self.playersOnline or 0)
        end
        perfActive = (self._perfPlayers or 0) > 0
    end
    if perfActive then
        -- Build 131: Schwelle auf 190 ms gedeckelt. Die Engine kappt dt bei
        -- 200 ms - eine hoehere adaptive Schwelle machte den Detektor nach
        -- laengerer Last blind (kein Frame kann sie mehr ueberschreiten).
        local slowLimit = math.min(190, math.max(100, (self._dtAvg or 0) * 2.5))
        if dt ~= nil and dt > slowLimit then
            self._spkCount = (self._spkCount or 0) + 1
            if dt > (self._spkMax or 0) then self._spkMax = dt end
            -- Kleinste TATSAECHLICH angewandte Schwelle merken: fuer sie gilt
            -- die Log-Aussage ">Xms" fuer jeden gezaehlten Frame. Frueher
            -- wurde die Schwelle erst beim Drucken neu berechnet ("(>377ms)
            -- ... max 200ms" - widerspruechlich).
            if self._spkLimitMin == nil or slowLimit < self._spkLimitMin then
                self._spkLimitMin = slowLimit
            end
        end
        if self._spkNextAt == nil then
            self._spkNextAt = (g_time or 0) + 10000
        end
        if (g_time or 0) >= self._spkNextAt then
            self._spkNextAt = (g_time or 0) + 10000
            if (self._spkCount or 0) > 0 and (self._spkReports or 0) < 200 then
                self._spkReports = (self._spkReports or 0) + 1
                print(string.format(
                    "NachbarFelder: [PERF] %d langsame Frames (>%dms) in 10s, max %dms (%s)",
                    self._spkCount, math.floor(self._spkLimitMin or slowLimit),
                    math.floor(self._spkMax or 0),
                    g_currentMission:getIsServer() and "Server" or "Client"))
            end
            self._spkCount    = 0
            self._spkMax      = 0
            self._spkLimitMin = nil
        end
    else
        -- Leerlauf: nichts zaehlen und Fenster verwerfen, damit nach dem
        -- naechsten Join keine Idle-Reste gemeldet werden
        self._spkCount    = 0
        self._spkMax      = 0
        self._spkLimitMin = nil
        self._spkNextAt   = nil
    end

    -- Speicher-Telemetrie (Build 76) entfaellt seit Build 158: die ModHub-Pruefung
    -- beanstandet das manuelle Aufraeumen des Speichers. Die Meldung ueber
    -- langsame Frames bleibt.

    -- Im Dedicated-MP: nur Server führt Status-Maschine aus
    if not g_currentMission:getIsServer() then return end

    -- Wiederkehrende Fahrzeuge: Respawn-Warteschlange prüfen
    if (self.playersOnline or 0) > 0 and self.pendingRespawns ~= nil and #self.pendingRespawns > 0 then
        for i = #self.pendingRespawns, 1, -1 do
            local p = self.pendingRespawns[i]
            if g_time >= p.spawnAt then
                table.remove(self.pendingRespawns, i)
                if not self.trafficPaused then
                    local stampWp = (self.userTrafficWaypoints ~= nil and #self.userTrafficWaypoints >= 1)
                        and math.random(#self.userTrafficWaypoints) or nil
                    local created = self:generateTraffic(p.filename, stampWp)
                    -- Blockiert (Nacht-Limit, Shop belegt, Limit voll):
                    -- spaeter erneut versuchen statt Respawn zu verlieren
                    if created ~= true then
                        p.retries = (p.retries or 0) + 1
                        if p.retries <= 10 then
                            p.spawnAt = g_time + math.random(180, 300) * 1000
                            table.insert(self.pendingRespawns, p)
                        end
                    end
                end
            end
        end
    end

    -- Zurückgestellte Kupplungen (needAttachment): InputAttacher-Joints sind
    -- jetzt im vehicleSystem registriert → Attachment sicher möglich.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.needAttachment then
            w.needAttachment = false
            self:setAttachment(k)
        end
    end

    -- Überwachungs-Blöcke (Build 79): laufen im 250ms-Takt statt jeden Frame.
    -- Sie prüfen ausschließlich Sekunden-Grenzen (90s-Timeout, Parkzeiten,
    -- 12s/60s-Watchdogs, Tank-Leerung) - Frame-Genauigkeit bringt dort nichts,
    -- kostet aber pro Frame mehrere Tabellen-Scans + getWorldTranslation-Aufrufe.
    local slowTick = false
    if self._slowNextAt == nil or (g_time or 0) >= self._slowNextAt then
        self._slowNextAt = (g_time or 0) + 250
        slowTick = true
    end

    if slowTick then

    -- Status=9999 Fahrzeuge nach 5 Echtzeit-Minuten automatisch löschen
    -- (needTimer ist dort false → separater Check nötig)
    for v, k in pairs(self.vehicleType) do
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.status == 9999 then
            if k.NachbarFelderWorker.stuckAt == nil then
                k.NachbarFelderWorker.stuckAt = g_time
            elseif g_time - k.NachbarFelderWorker.stuckAt > 90000 then
                print("NachbarFelder: Status=9999 Timeout (5min) - Fahrzeug wird geloescht (Feld " ..
                    tostring(k.NachbarFelderWorker.fieldId) .. ")")
                k.NachbarFelderWorker.status = 100
                k.NachbarFelderWorker.needTimer = true
            end
        end
    end

    -- Patrol-Park-Timer: geparktes Fahrzeug fährt nach Ablauf zum Shop zurück.
    -- Läuft AUSSERHALB des needTimer-Mechanismus (Patrol hat kein needTimer im Status 2).
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.isPatrol and w.status == 2 and w.parkUntil ~= nil then
            if g_time >= w.parkUntil then
                w.parkUntil = nil
                -- Tagesrhythmus (Build 68): sind mehr Fahrzeuge aktiv als
                -- die Uhrzeit erlaubt (Nacht/Mittag/Abend), macht dieses
                -- Fahrzeug jetzt Feierabend statt den naechsten Hop.
                if self:countActivePatrols() > self:getEffectiveTrafficLimit() then
                    w.hopsLeft = 1
                end
                w.hopsLeft  = (w.hopsLeft or 1) - 1
                -- Build 105: Feierabend nur an einem Parkpunkt. Bisher schlief
                -- das Fahrzeug dort ein, wo es gerade stand - oft auf der Strasse,
                -- und blieb dort bis zum naechsten Aufwecken im Weg. Jetzt faehrt es
                -- vorher zum naechsten freien Parkpunkt (einmal pro Feierabend).
                local parkZiel = nil
                if w.hopsLeft <= 0 and not w.feierabendFahrt then
                    parkZiel = self:findFreeParkpunkt(w)
                end
                if parkZiel ~= nil then
                    w.feierabendFahrt = true
                    w.waypointIdx   = w.patrolDestIdx or 1
                    w.patrolDestIdx = parkZiel
                    w.patrolTargetX = w.waypoints[parkZiel][1]
                    w.patrolTargetZ = w.waypoints[parkZiel][2]
                    w.parkSecs      = 5
                    w.patrolWdLastX = nil
                    w.patrolWdStage = nil
                    print("NachbarFelder: [TRAFFIC] Feierabend - faehrt zum Parkpunkt WP" ..
                        tostring(parkZiel) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                    w.status    = 1
                    w.needTimer = true
                elseif w.hopsLeft <= 0 then
                    -- Alle Hops erledigt → Feierabend: an Ort und Stelle in den
                    -- Pool (Build 65). Das Fahrzeug steht bereits geparkt am WP
                    -- und bleibt dort stehen bis es wieder gebraucht wird.
                    -- Scheitert das Poolen (voll/deaktiviert), greift der alte
                    -- Weg (Heimfahrt bzw. Loeschen).
                    w.patrolWdLastX = nil
                    w.patrolWdStage = nil
                    if self:sleepPatrolEntry(k, true) then
                        -- Eintrag ist bereits entfernt; nichts weiter zu tun
                    else
                        w.status        = 60
                        w.gotoStartedAt = nil
                        w.needTimer     = true
                        print("NachbarFelder: [TRAFFIC] Hops erledigt - Heimfahrt (patrolId=" ..
                            tostring(w.fieldId) .. ")")
                    end
                else
                    -- Zufälligen nächsten WP wählen (Kategorie bestimmt Parkzeit;
                    -- gesperrte/unerreichbare WPs werden vermieden)
                    local curIdx = w.patrolDestIdx or 1
                    w.waypointIdx   = curIdx
                    local newDest   = self:pickPatrolWaypoint(w.waypoints, curIdx) or curIdx
                    w.patrolDestIdx = newDest
                    w.patrolTargetX = w.waypoints[newDest][1]
                    w.patrolTargetZ = w.waypoints[newDest][2]
                    local newCat    = (w.waypoints[newDest] or {})[4] or 0
                    w.parkSecs      = nfCatParkSecs(newCat)
                    w.patrolWdLastX  = nil
                    w.patrolWdStage  = nil
                    -- Dauerschreiber (jeder Hop): nur im Debug-Log (logLevel=2)
                    self:log(2, "NachbarFelder: [TRAFFIC] -> WP" .. tostring(newDest) ..
                        " [" .. (NF_CAT_NAMES[newCat] or "?") .. "]" ..
                        " (noch " .. tostring(w.hopsLeft) .. " Hops, patrolId=" ..
                        tostring(w.fieldId) .. ")")
                    w.status    = 1
                    w.needTimer = true
                end
            end
        end
    end

    -- Bewegungs-Watchdog für Patrol-Fahrzeuge im GOTO (Status 1):
    -- Steht es 12 s still und ist schon am Ziel (< 15 m) → gilt als angekommen,
    --   parkt (Build 98). Sonst steckt es fest:
    -- Stufe 1 (30s): NEUES zufaelliges Ziel (nicht dasselbe Ziel!), kein Teleport.
    --   Gleiches Ziel wuerde das Fahrzeug sofort wieder in dieselbe Engstelle schicken.
    -- Stufe 2 (60s): Nochmal neues Ziel, letzte Chance.
    -- Stufe 3 (90s): an Ort und Stelle in den Pool, bei vollem Pool loeschen.
    --
    -- Build 101: Fristen verdreifacht. Die Messzeilen vom 12.09. zeigen beim
    -- 12-s-Alarm durchgehend "Motor an | fahrbereit true | Agent ja" bei 0 km/h -
    -- das ist die laufende Wegsuche, kein Feststecken. Im selben Log brauchte sie
    -- 2416, 9059, 11504 und 12147 ms. Mit 12 s Frist hat der Wächter also genau
    -- die Auftraege abgebrochen, die gleich losgefahren waeren.
    -- Echte Bewegung (>5m) setzt Stufen-Zaehler zurueck.
    -- Build 122: Klapp-Nachpruefung 10 s nach dem Einklappbefehl
    if self.klappPruefung ~= nil and #self.klappPruefung > 0 then
        for i = #self.klappPruefung, 1, -1 do
            local e = self.klappPruefung[i]
            if g_time >= e.at then
                table.remove(self.klappPruefung, i)
                local function schritt()
                    local impl = e.impl
                    if impl == nil or impl.isDeleted or impl.spec_foldable == nil then return end
                    local zu = self:getIstEingeklappt(impl)
                    if zu == false then
                        local sf = impl.spec_foldable
                        print("NachbarFelder: [KLAPP] nach 10 s noch offen: " .. self:getKlappText(impl))
                        if (sf.foldMoveDirection or 0) == 0 then
                            impl:setFoldState(-(sf.turnOnFoldDirection or 1), false)
                            print("NachbarFelder: [KLAPP] Einklappbefehl wiederholt")
                        end
                    elseif zu == true then
                        print("NachbarFelder: [KLAPP] eingeklappt: " .. self:getKlappText(impl))
                    end
                end
                schritt()
            end
        end
    end

    -- Build 142: umgekipptes Gespann sofort erkennen statt 60 s Stillstand abzuwarten
    -- (Log 01.10.: Helfer lag am Ladeplatz im Shop-Hof auf dem Dach).
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.status ~= nil and w.status < 100 then
            local veh = w.vehiclesToLoad and w.vehiclesToLoad[1]
            if self:getIsVehicleAlive(veh) then
                local _, upY, _ = localDirectionToWorld(veh.rootNode, 0, 1, 0)
                if upY < NachbarFelderManager.KIPP_GRENZE then
                    w.kippSeit = w.kippSeit or g_time
                    if g_time - w.kippSeit > 3000 then
                        local x, _, z = getWorldTranslation(veh.rootNode)
                        print(string.format("NachbarFelder: %s %s ist umgekippt bei x=%d z=%d (Status %s) - wird entfernt",
                            "[TRAFFIC] Fahrzeug",
                            tostring(self:getWorkerName(w)), math.floor(x), math.floor(z), tostring(w.status)))
                        -- Build 148: Platz sperren (zwei verschiedene Gespanne kippten auf demselben Platz)
                        self:merkeSpawnFehlschlag(w, x, z, "umgekippt (Platz)")
                        self:stopAIJobSafely(veh)
                        w.kippSeit  = nil
                        w.status    = 100
                        w.needTimer = true
                    end
                else
                    w.kippSeit = nil
                end
            end
        end
    end

    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        -- Build 94: erst messen, wenn der GOTO-Job tatsaechlich laeuft.
        -- Status 1 gilt schon waehrend der ~6 s Wartezeit vor dem Start und
        -- nach jedem neuen Ziel; bisher lief die Uhr dabei weiter, und
        -- "Stufe1 - 12s fest" loeste ~6 s nach einem neuen Ziel aus, obwohl das
        -- Fahrzeug nie festsass (60 Ausloesungen in 66 min, jede mit neuem Job
        -- und neu geladener Fahrerfigur = Standbild beim Spieler).
        -- fieldGotoStartedAt wird beim echten Job-Start gesetzt und bei jedem
        -- Job-Ende wieder geloescht.
        if w ~= nil and w.isPatrol and w.status == 1 and w.fieldGotoStartedAt == nil then
            w.patrolWdLastX = nil
        elseif w ~= nil and w.isPatrol and w.status == 1 then
            if w.patrolWdJobStart ~= w.fieldGotoStartedAt then
                -- neuer Job: Messung ab seinem Start neu beginnen
                w.patrolWdJobStart = w.fieldGotoStartedAt
                w.patrolWdLastX    = nil
            end
            local veh = w.vehiclesToLoad[1]
            if self:getIsVehicleAlive(veh) then
                local x, _, z = getWorldTranslation(veh.rootNode)
                if w.patrolWdLastX == nil then
                    w.patrolWdLastX, w.patrolWdLastZ, w.patrolWdSince = x, z, g_time
                elseif MathUtil.vector2Length(x - w.patrolWdLastX, z - w.patrolWdLastZ) > 5 then
                    -- Echte Bewegung → alles zuruecksetzen
                    w.patrolWdLastX, w.patrolWdLastZ, w.patrolWdSince = x, z, g_time
                    w.patrolWdStage = 0
                    w.wdRettungen   = nil   -- Build 107
                    w.begegnungen   = nil   -- Build 166: faehrt wieder
                else
                    local stuckMs = g_time - (w.patrolWdSince or g_time)
                    local stage   = w.patrolWdStage or 0

                    local zielDist = math.huge
                    if w.patrolTargetX ~= nil and w.patrolTargetZ ~= nil then
                        zielDist = MathUtil.vector2Length(x - w.patrolTargetX, z - w.patrolTargetZ)
                    end

                    -- Build 167: Steht ein frisch geladenes Fahrzeug nach 30 s noch auf
                    -- seinem Ladeplatz, taugt der Platz nicht. Log 04.10. 14:01-14:12: vier
                    -- von fuenf Fahrzeugen kamen vom Ladeplatz ~78 m vor dem Shop nie weg
                    -- (Motor an, Auftrag aktiv, 0 km/h). Bisher zaehlte nur ein sofort
                    -- abgewiesener Start als Fehlschlag. merkeSpawnFehlschlag wirkt nur bis
                    -- 10 m vom Ladeplatz und nur einmal je Fahrzeug.
                    if stuckMs > 30000 and stage == 0 and zielDist >= 15 then
                        self:merkeSpawnFehlschlag(w, x, z, "steht nach dem Start still")
                    end

                    if stuckMs > 12000 and zielDist < 15 then
                        -- Build 98: Steht am Ziel, der Job endet aber nicht - die
                        -- KI erreicht die geforderte Zielrichtung nicht ganz und
                        -- wartet. Bisher griff dann Stufe 1 und setzte das
                        -- Fahrzeug 4 m zurueck ("stand gut, wurde nach Sekunden
                        -- einen Tick nach hinten versetzt", 11.09.). Jetzt: Job
                        -- beenden und parken wie bei normaler Ankunft (Worker,
                        -- Build 90: stehen bleiben, wo und wie es angekommen ist).
                        self:stopAIJobSafely(veh)
                        w.fieldGotoStartedAt = nil
                        w.gotoRejects   = nil
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 0
                        w.waypointIdx   = w.patrolDestIdx
                        local secs = w.parkSecs or self:scaleParkSecs(math.random(60, 180))
                        w.parkUntil = g_time + secs * 1000
                        w.status    = 2
                        -- Routine-Ankunft (Durchfahrts-Logik): nur im Debug-Log
                        self:log(2, string.format("NachbarFelder: [TRAFFIC] steht %.0f m vor Ziel WP%s still -" ..
                            " gilt als angekommen, parkt (patrolId=%s)",
                            zielDist, tostring(w.patrolDestIdx), tostring(w.fieldId)))

                    elseif stuckMs > 30000 and stage == 0 and self:loeseBegegnung(k, veh, x, z) then
                        -- Build 166: zwei Nachbar-Fahrzeuge warten aufeinander - dieses
                        -- weicht aus (siehe loeseBegegnung), das andere faehrt weiter
                        w.patrolWdStage = 1

                    elseif stuckMs > 30000 and stage == 0 then
                        -- Stufe 1: neues zufaelliges Ziel
                        -- (gleiches Ziel waere sinnlos - fuehrt direkt zur selben Engstelle)
                        -- Laufenden Job SAUBER stoppen bevor neu gestartet wird -
                        -- sonst kollidiert der neue GOTO mit dem alten Job.
                        -- Build 98: ohne den frueheren 4-m-Teleport rueckwaerts -
                        -- das Zuruecksetzen war fuer Spieler ein sichtbarer Ruck.
                        -- Den Weg aus der Engstelle plant die KI selbst.
                        -- Build 100: Zustand VOR dem Stoppen festhalten - danach
                        -- ist der Agent geloescht und nichts mehr zu sehen.
                        -- Build 107: zeigen, OB etwas im Weg ist - Zielabstand, ob der
                        -- Zielplatz besetzt ist und welches Fahrzeug am naechsten steht.
                        local fremdD, fremdName = self:getNaechstesFremdfahrzeug(x, z, veh)
                        local zielBelegt = w.patrolTargetX ~= nil
                            and self:isSpotBlockedByAnyVehicle(w.patrolTargetX, w.patrolTargetZ, 10, veh)
                        print(string.format("NachbarFelder: [TRAFFIC][DIAG] 30s ohne Bewegung" ..
                            " (Ziel WP%s, noch %.0f m, Zielplatz %s, naechstes Fahrzeug %s in %.0f m): %s",
                            tostring(w.patrolDestIdx), math.min(zielDist, 99999),
                            zielBelegt and "BELEGT" or "frei",
                            tostring(fremdName or "-"), fremdD or -1, self:getVehicleAiDiag(veh)))
                        self:stopAIJobSafely(veh)
                        w.fieldGotoStartedAt = nil   -- Build 94: Uhr ruht bis zum naechsten Start
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 1
                        local curDest = w.patrolDestIdx or 1
                        local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Build 109: ab Fahrzeug
                        w.waypointIdx   = curDest
                        w.patrolDestIdx = newDest
                        w.patrolTargetX = w.waypoints[newDest][1]
                        w.patrolTargetZ = w.waypoints[newDest][2]
                        w.parkSecs      = self:scaleParkSecs(math.random(20, 60))
                        print("NachbarFelder: [TRAFFIC] Stufe1 - 30s fest, neues Ziel WP" ..
                            tostring(newDest) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                        w.status    = 1
                        w.needTimer = true

                    elseif stuckMs > 60000 and stage == 1 then
                        -- Stufe 2: Wieder fest → anderes zufaelliges Ziel, letzte Chance
                        self:stopAIJobSafely(veh)
                        w.fieldGotoStartedAt = nil   -- Build 94: Uhr ruht bis zum naechsten Start
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 2
                        local curDest = w.patrolDestIdx or 1
                        local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Build 109: ab Fahrzeug
                        w.waypointIdx   = curDest
                        w.patrolDestIdx = newDest
                        w.patrolTargetX = w.waypoints[newDest][1]
                        w.patrolTargetZ = w.waypoints[newDest][2]
                        w.parkSecs      = self:scaleParkSecs(math.random(20, 60))
                        print("NachbarFelder: [TRAFFIC] Stufe2 - neues Ziel WP" ..
                            tostring(newDest) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                        w.status    = 1
                        w.needTimer = true

                    elseif stuckMs > 90000 and stage == 2 then
                        -- Stufe 3: Aufgeben → an Ort und Stelle in den Pool
                        -- (Build 93: kein Teleport); sonst wie frueher loeschen
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 0
                        -- Build 107: Wer drei Stufen lang keinen Meter vorankam, steckt
                        -- fest (TK4 am 13.09.: Front vor einem Gebaeude, vier Runden
                        -- Stufe1/2/3 - Pool - Aufwecken ohne jede Bewegung). Einschlafen
                        -- an Ort und Stelle aendert daran nichts. Deshalb einmal auf die
                        -- KI-Strasse setzen und mit neuem Ziel weiterfahren; erst wenn
                        -- auch das nichts bringt, wie bisher in den Pool.
                        local gerettet = false
                        if (w.wdRettungen or 0) < 1 then
                            self:stopAIJobSafely(veh)
                            w.fieldGotoStartedAt = nil
                            if self:rettungAufStrasse(veh, x, z) then
                                gerettet = true
                                w.wdRettungen   = (w.wdRettungen or 0) + 1
                                w.patrolWdLastX = nil
                                local curDest = w.patrolDestIdx or 1
                                local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Build 109: ab Fahrzeug
                                w.waypointIdx   = curDest
                                w.patrolDestIdx = newDest
                                w.patrolTargetX = w.waypoints[newDest][1]
                                w.patrolTargetZ = w.waypoints[newDest][2]
                                print("NachbarFelder: [TRAFFIC] Stufe3 - steckte fest, faehrt von der Strasse" ..
                                    " aus weiter zu WP" .. tostring(newDest) .. " (patrolId=" ..
                                    tostring(w.fieldId) .. ")")
                                w.status    = 1
                                w.needTimer = true
                            end
                        end
                        if gerettet then
                            -- weiter mit neuem Ziel
                        elseif self:sleepPatrolEntry(k, false) then
                            print("NachbarFelder: [TRAFFIC] Stufe3 - Fahrzeug schlaeft im Pool (patrolId=" ..
                                tostring(w.fieldId) .. ")")
                        else
                            print("NachbarFelder: [TRAFFIC] Stufe3 - Fahrzeug loeschen (patrolId=" ..
                                tostring(w.fieldId) .. ")")
                            w.status    = 100
                            w.needTimer = true
                        end
                    end
                end
            end
        end
    end

    end  -- Ende slowTick-Block (Build 79)

    for v, k in pairs(self.vehicleType) do
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.needTimer then
            if self.startReadyTimer + dt >= 3000 then
                local vehicle = k.NachbarFelderWorker.vehiclesToLoad[1]
                self.startReadyTimer = 0
                k.NachbarFelderWorker.needTimer = false

                local s = k.NachbarFelderWorker.status

                -- Fahrzeug extern verschwunden (z.B. von anderem System gelöscht)?
                -- Dann sofort Cleanup statt auf tote Referenzen zuzugreifen.
                if s ~= 100 and not self:getIsVehicleAlive(vehicle) then
                    k.NachbarFelderWorker.status = 100
                    s = 100
                end

                if s >= 0 and s < 1 then
                    local vehIndex = (s == 0) and 2 or 3
                    local attached = k.NachbarFelderWorker.vehiclesToLoad[vehIndex]
                    local pendingInfo = self:attachObjects(vehicle, attached, vehIndex == 2)
                    -- Build 125: Feldhelfer UND Verkehr an die Kupplung setzen (Build 117:
                    -- k.NachbarFelderWorker ist hier schon der Worker)
                    if pendingInfo ~= nil then
                        self:kuppleGeraet(pendingInfo)   -- Build 156: drehrichtig setzen, weich kuppeln
                    elseif attached ~= nil then
                        if not attached.isAddedToPhysics then attached:addToPhysics() end
                    end
                    if #k.NachbarFelderWorker.vehiclesToLoad >= 3 and vehIndex == 2 then
                        k.NachbarFelderWorker.status = 0.5
                    else
                        k.NachbarFelderWorker.status = 1
                        -- Patrol + Anbaugeraet: Foldanimation sofort anstoßen.
                        -- foldWaitUntil haelt GOTO zurueck bis die Animation abgelaufen ist.
                        if k.NachbarFelderWorker.isPatrol then
                            local implVeh = k.NachbarFelderWorker.vehiclesToLoad[2]
                            if implVeh ~= nil then
                                if implVeh.prepareForAIDriving ~= nil then
                                    implVeh:prepareForAIDriving()
                                end
                                if implVeh.spec_foldable ~= nil
                                   and implVeh.setFoldDirection ~= nil then
                                    local wd = implVeh.spec_foldable.turnOnFoldDirection or 1
                                    implVeh:setFoldDirection(-wd)
                                end
                                k.NachbarFelderWorker.foldWaitUntil = g_time + 9000
                            end
                        end
                    end
                    k.NachbarFelderWorker.needTimer = true

                elseif s == 1 then
                    -- Patrol: Fahrzeug muss spec_aiFieldWorker haben, sonst kann es keinen GOTO-Job
                    -- ausführen → sofort sperren, bevor ein GOTO-Versuch (Spawn+Verschwinden) entsteht.
                    if k.NachbarFelderWorker.isPatrol and vehicle.spec_aiFieldWorker == nil then
                        local fname    = vehicle.configFileName
                        local baseName = fname ~= nil and (string.match(fname, "[^/\\]+$") or fname)
                                         or tostring(vehicle.typeName or "?")
                        print("NachbarFelder: [TRAFFIC] Blacklist: " .. baseName ..
                            " (kein spec_aiFieldWorker, kann keinen GOTO-Job ausfuehren)")
                        if fname ~= nil then
                            self.trafficVehicleBlacklist = self.trafficVehicleBlacklist or {}
                            self.trafficVehicleBlacklist[fname] = true
                            self.trafficVehicleList = nil
                            -- Auch aus Stammfahrzeug-Slots entfernen (verhindert endloses Respawnen)
                            for i = #self.regularVehicleXMLs, 1, -1 do
                                if self.regularVehicleXMLs[i] == fname then
                                    table.remove(self.regularVehicleXMLs, i)
                                end
                            end
                            for i = #self.pendingRespawns, 1, -1 do
                                if self.pendingRespawns[i] ~= nil
                                   and self.pendingRespawns[i].filename == fname then
                                    table.remove(self.pendingRespawns, i)
                                end
                            end
                        end
                        k.NachbarFelderWorker.noPool    = true
                        k.NachbarFelderWorker.status    = 100
                        k.NachbarFelderWorker.needTimer = true

                    elseif k.NachbarFelderWorker.isPatrol and k.NachbarFelderWorker.firstStart then
                        -- Gespann-Teleport NACH dem Kuppeln (Zapfwellen-Fix) bzw.
                        -- Fallback wenn onSpawnedVehicle keinen Teleport ausführen konnte.
                        -- teleportVehicle bewegt Traktor + gekuppeltes Gerät gemeinsam.
                        local nfW = k.NachbarFelderWorker
                        local wps = nfW.waypoints
                        nfW.firstStart = nil
                        if wps ~= nil and #wps >= 1 then
                            local nearestIdx = nfW.waypointIdx or 1
                            if nfW.spawnWpIdx ~= nil and wps[nfW.spawnWpIdx] ~= nil then
                                -- In onSpawnedVehicle bereits gewählter Start-WP
                                nearestIdx = nfW.spawnWpIdx
                                nfW.spawnWpIdx = nil
                            elseif nfW.overrideSpawnWpIdx ~= nil and wps[nfW.overrideSpawnWpIdx] ~= nil then
                                nearestIdx = nfW.overrideSpawnWpIdx
                            else
                                local function schritt()
                                    local refX, refZ = self:getShopBuildingPosition()
                                    if refX == nil and vehicle.rootNode ~= nil then
                                        refX, _, refZ = getWorldTranslation(vehicle.rootNode)
                                    end
                                    if refX == nil then return end
                                    local minD2 = math.huge
                                    for i, wp in ipairs(wps) do
                                        local d2 = (wp[1]-refX)^2 + (wp[2]-refZ)^2
                                        if d2 < minD2 then minD2 = d2; nearestIdx = i end
                                    end
                                end
                                schritt()
                            end
                            -- Belegte Plaetze meiden (Build 73): kein Teleport auf
                            -- einen WP, an dem schon ein Fahrzeug steht (Explosion).
                            local freeIdx = self:findFreeSpawnWp(wps, nearestIdx, vehicle)
                            if freeIdx ~= nil then nearestIdx = freeIdx end
                            nfW.waypointIdx = nearestIdx
                            if nfW.patrolDestIdx == nearestIdx and #wps >= 2 then
                                local nd = self:pickPatrolWaypoint(wps, nearestIdx) or nearestIdx
                                nfW.patrolDestIdx = nd
                                nfW.patrolTargetX = wps[nd][1]
                                nfW.patrolTargetZ = wps[nd][2]
                            end
                            -- Build 91: gar kein Spawn-Teleport mehr.
                            -- Fuer einen Spawn auf einem Wegpunkt gibt es keine
                            -- verlaessliche Ausrichtung: die gespeicherte ry ist
                            -- die Blickrichtung beim Setzen (zu Fuss = quer zur
                            -- Fahrbahn), die Luftlinie zum Ziel trifft die Strasse
                            -- nur auf geraden Stuecken. Das Ergebnis war beide
                            -- Male ein quer abgestelltes Gespann. Der Shop-Spawn
                            -- ist die einzige Stelle mit einer vom Spiel selbst
                            -- definierten, korrekten Ausrichtung - also starten
                            -- Fahrzeuge dort und fahren die Strecke selbst.
                            -- Build 136: "Ladeplatz" statt "Shop" - geladen wird laengst an
                            -- der KI-Strasse bzw. am Spawnpunkt, nicht mehr am Shop
                            print("NachbarFelder: [TRAFFIC] Gespann startet am Ladeplatz " ..
                                "und faehrt selbst zu WP" .. tostring(nearestIdx))
                            if #wps >= 2 and nfW.patrolDestIdx ~= nil then
                                nfW.status    = 1.5
                                nfW.needTimer = true
                            else
                                nfW.parkUntil = g_time + (nfW.parkSecs or 30) * 1000
                                nfW.status    = 2
                            end
                        else
                            nfW.status    = 100
                            nfW.needTimer = true
                        end

                    elseif k.NachbarFelderWorker.isPatrol then
                        -- Patrol: teleportVehicle ist im MP-Dedicated-Server asynchron (ein Frame Latenz).
                        -- Status=1.5 gibt weitere 3s Settle-Zeit, damit das Fahrzeug physikalisch
                        -- an der WP-Position ist bevor createAgent() den Navmesh-Startknoten sucht.
                        k.NachbarFelderWorker.status    = 1.5
                        k.NachbarFelderWorker.needTimer = true
                    else
                        -- Build 150: Feldhelfer gibt es nicht mehr - Eintrag ohne Patrol aufraeumen
                        k.NachbarFelderWorker.status    = 100
                        k.NachbarFelderWorker.needTimer = true
                    end

                elseif s == 1.5 then
                    -- Post-Teleport-Settle abgelaufen → GOTO starten.
                    -- Status MUSS vor driveToField auf 1 zurück: onAIJobFinished prüft status==1.
                    local nfW = k.NachbarFelderWorker
                    nfW.status = 1
                    nfW.fieldGotoStartedAt = g_time
                    -- Ziel-Winkel: die KI rangiert am Ziel, bis sie genau so
                    -- steht. Build 98: Richtung der naechsten KI-Strasse
                    -- (getRoadHeadingAt) - so parkt das Fahrzeug laengs, auch
                    -- wenn der Wegpunkt zu Fuss und quer gesetzt wurde. Nur ohne
                    -- Strasse im Umkreis von 20 m gilt die gespeicherte WP-Richtung.
                    -- 180-Grad-Variante nach Anfahrtsrichtung waehlen.
                    -- Build 99: Auch der ZIELPUNKT wandert auf die KI-Strasse.
                    -- Ein Wegpunkt liegt oft ein paar Meter daneben; die KI haelt
                    -- dann im Seitenstreifen, und von dort kommt kein neuer
                    -- Fahrauftrag mehr weg (Log 12.09.: zwei Fahrzeuge standen bei
                    -- x=124 z=-93 bzw. x=218 z=-50 dauerhaft fest).
                    local targetRy = 0
                    local wps = nfW.waypoints
                    local wp  = (wps ~= nil and nfW.patrolDestIdx ~= nil)
                                and wps[nfW.patrolDestIdx] or nil
                    if wp ~= nil then
                        targetRy = wp[3] or 0
                        local vx, vz = nil, nil
                        if vehicle.rootNode ~= nil then
                            local px, _, pz = getWorldTranslation(vehicle.rootNode)
                            vx, vz = px, pz
                        end
                        -- Build 136: Fahrspur passend zur Anfahrtsrichtung waehlen
                        -- (Zwillings-Spline) statt die Richtung um 180 Grad zu drehen -
                        -- gedreht zeigte das Ziel auf Einbahnen gegen die Fahrtrichtung.
                        local wdx, wdz = nil, nil
                        if vx ~= nil then wdx, wdz = wp[1] - vx, wp[2] - vz end
                        local rx, rz, roadRy = self:getRoadPointInRichtung(wp[1], wp[2], 20, 0, wdx, wdz)
                        if roadRy ~= nil then
                            targetRy = roadRy
                            -- Build 105: Parkpunkte (eigene Wegpunkte) NICHT auf
                            -- die Strasse ziehen - dort soll das Fahrzeug ja
                            -- gerade neben der Fahrbahn stehen. Nur Strassenziele
                            -- wandern auf die Fahrbahn.
                            if not self:getIsParkpunkt(nfW, nfW.patrolDestIdx) then
                                nfW.patrolTargetX, nfW.patrolTargetZ = rx, rz
                            end
                        elseif vx ~= nil then
                            -- ohne KI-Strasse im Umkreis (Parkpunkt abseits): wie bisher
                            -- nach Anfahrtsrichtung drehen - dort gibt es keine Spur
                            local dx = (nfW.patrolTargetX or vx) - vx
                            local dz = (nfW.patrolTargetZ or vz) - vz
                            if math.sqrt(dx * dx + dz * dz) > 1 then
                                local fx, fz = math.sin(targetRy), math.cos(targetRy)
                                if fx * dx + fz * dz < 0 then
                                    targetRy = targetRy + math.pi
                                end
                            end
                        end
                    end
                    self:driveToField(vehicle, nfW.fieldId,
                        nfW.patrolTargetX, 0, nfW.patrolTargetZ, targetRy)

                elseif s == 60 then
                    -- Rückfahrt zum Spawn-Punkt
                    if k.NachbarFelderWorker.gotoStartedAt == nil then
                        local shopX, shopZ = self:getShopPosition()
                        self:driveToField(vehicle, k.NachbarFelderWorker.fieldId, shopX, 0, shopZ)
                        k.NachbarFelderWorker.gotoStartedAt = g_time
                        k.NachbarFelderWorker.needTimer = true
                    else
                        if g_time - k.NachbarFelderWorker.gotoStartedAt > 120000 then
                            print("NachbarFelder: Rueckfahrt-Timeout Feld " ..
                                tostring(k.NachbarFelderWorker.fieldId) .. " - loesche Fahrzeug")
                            k.NachbarFelderWorker.gotoStartedAt = nil
                            k.NachbarFelderWorker.status = 100
                            k.NachbarFelderWorker.needTimer = true
                        else
                            k.NachbarFelderWorker.needTimer = true
                        end
                    end

                elseif s == 100 then
                    -- Patrol: in den Pool statt loeschen (Build 65). Klappt das
                    -- nicht (Pool voll/aus, noPool-Blacklist, kein freier WP),
                    -- wird wie bisher geloescht.
                    if k.NachbarFelderWorker.isPatrol and self:sleepPatrolEntry(k, false) then
                        -- schlaeft im Pool; Eintrag wurde bereits entfernt.
                        -- Kein pendingRespawn noetig - das Fahrzeug existiert weiter.
                    else
                        local wVehs = k.NachbarFelderWorker.vehiclesToLoad
                        for _, veh in ipairs(wVehs) do
                            if self:getIsVehicleAlive(veh) then
                                self:stopAIJobSafely(veh)
                                veh:delete()
                            end
                        end
                        -- Wiederkehrendes Fahrzeug → nach 5-8 Min Echtzeit neu spawnen
                        if k.NachbarFelderWorker.isPatrol and k.NachbarFelderWorker.isRegular
                           and not k.NachbarFelderWorker.noPool then
                            local xml = k.NachbarFelderWorker.regularXML
                            if xml ~= nil then
                                table.insert(self.pendingRespawns, {
                                    filename = xml,
                                    spawnAt  = g_time + math.random(300, 480) * 1000
                                })
                                print("NachbarFelder: [TRAFFIC] Stammfahrzeug respawnt in 5-8 Min: " ..
                                    tostring(string.match(xml, "[^/\\]+$") or xml))
                            end
                        end
                        g_NachbarFelderManager:deleteMission(k.NachbarFelderWorker.fieldId, 100)
                    end
                end
            else
                self.startReadyTimer = self.startReadyTimer + dt
            end
        end
    end
end

-- ============================================================
-- onMinuteChanged: NUR auf Server
-- ============================================================
function NachbarFelderManager:onMinuteChanged(minute)
    if not g_currentMission:getIsServer() then return end

    -- Server-Konfig einmalig laden (modSettings/FS25_NachbarFelder/NachbarFelderServerConfig.xml)
    self:loadServerConfig()


    -- Spieler-Zähler ZUERST aktualisieren (addPlayer-Hook feuert auf Ded. Server nicht zuverlässig)
    -- Nur Spieler zählen die wirklich im Spiel sind (farmId > 0 = Stufe-2, nicht nur Ladebildschirm)
    local realCount = 0
    if g_currentMission.players ~= nil then
        for _, player in pairs(g_currentMission.players) do
            if player ~= nil then
                -- Stufe-2 Spieler haben farmId > 0; Stufe-1 (lädt noch) haben farmId=0 oder nil
                local pFarmId = player.farmId or 0
                if pFarmId > 0 then
                    realCount = realCount + 1
                end
            end
        end
    end
    if realCount ~= self.playersOnline then
        print("NachbarFelder: Spieler: " .. tostring(self.playersOnline) .. " -> " .. tostring(realCount))
        -- Wenn jemand neu dazukommt während niemand da war → Grace-Period starten
        -- (Stufe-1: Spieler ist im Ladebildschirm, noch nicht wirklich im Spiel)
        if self.playersOnline <= 0 and realCount > 0 then
            self.playerJoinTime = g_time  -- Echtzeit-Timestamp; robust gegen Zeitsprünge
            print("NachbarFelder: Erster Spieler erkannt - warte " ..
                tostring(math.floor((self.firstSpawnDelayMs or 180000) / 60000)) ..
                " Minuten (Echtzeit) vor erstem Spawn")
        end
        self.playersOnline = realCount
        if realCount <= 0 then
            self.playerJoinTime = nil
            self:stopAllHelpers()
            return
        end
    end

    -- Player-Gate: Keine Helfer wenn kein Spieler online
    if self.playersOnline <= 0 then return end

    -- Grace-Period nach erstem Join (Echtzeit statt Spielminuten,
    -- sonst frisst TimeResetOnJoin den Zähler bei Zeitsprung sofort leer)
    if self.playerJoinTime ~= nil then
        if g_time - self.playerJoinTime < (self.firstSpawnDelayMs or 180000) then return end
        self.playerJoinTime = nil
        self.timeToNextStart = 0  -- sofort spawnen nach der Wartezeit
    end

    local timeScale = g_currentMission:getEffectiveTimeScale()
    local cc = 0
    for v, k in pairs(self.vehicleType) do
        cc = cc + 1
        if k.NachbarFelderWorker.isBlocked > 0 then
            if k.NachbarFelderWorker.isBlocked >= 1 * timeScale then
                local vehsBlocked = k.NachbarFelderWorker.vehiclesToLoad
                for _, vehicle in ipairs(vehsBlocked) do
                    if not self:getIsVehicleAlive(vehicle) then continue end
                    local x, y, z = getWorldTranslation(vehicle.rootNode)
                    x = math.floor(x * 1000) / 100
                    if k.NachbarFelderWorker.lastKnownPos == x or k.NachbarFelderWorker.lastKnownPos == 0 then
                        if k.NachbarFelderWorker.isBlocked > 300 * timeScale then
                            -- Patrol: geblocktes Fahrzeug in den Pool (Teleport an
                            -- freien WP loest die Blockade) statt loeschen (Build 65)
                            if k.NachbarFelderWorker.isPatrol and self:sleepPatrolEntry(k, false) then
                                break
                            end
                            local status = k.NachbarFelderWorker.status
                            local vehsRM = k.NachbarFelderWorker.vehiclesToLoad
                            for _, vehicleRM in ipairs(vehsRM) do
                                if self:getIsVehicleAlive(vehicleRM) then
                                    self:stopAIJobSafely(vehicleRM)
                                    vehicleRM:delete()
                                end
                            end
                            self:deleteMission(k.NachbarFelderWorker.fieldId, status)
                        end
                        k.NachbarFelderWorker.isBlocked = k.NachbarFelderWorker.isBlocked + (100 * timeScale)
                    else
                        k.NachbarFelderWorker.isBlocked = 2 * timeScale
                    end
                    k.NachbarFelderWorker.lastKnownPos = x
                    break
                end
            else
                k.NachbarFelderWorker.isBlocked = k.NachbarFelderWorker.isBlocked + 1
            end
        end
    end

    local sleeping = g_sleepManager:getIsSleeping()
    if sleeping then return end

    -- "Mod aktiv"-Schalter (Settings-Seite): Aus = keine neuen Spawns,
    -- laufende Fahrzeuge arbeiten fertig. Der Schalter war bisher ohne
    -- Wirkung - seit Build 67 wird er MP-synct und greift hier.
    if self.active == false then return end

    -- Spawn-Tick fuer den KI-VERKEHR: gegen das Traffic-Limit pruefen,
    -- NICHT gegen "Anzahl Arbeiter" (Bug bis Build 71: cc zaehlte auch
    -- Patrol-Fahrzeuge - mit maxWorkers=2 blieb der Verkehr bei 2 stehen,
    -- egal wie hoch trafficLimit stand). Seit Build 150 gibt es nur noch
    -- den Verkehr.
    if self:countActivePatrols() < self:getEffectiveTrafficLimit() then
        self.timeToNextStart = self.timeToNextStart - 1
        if self.timeToNextStart <= 0 then
            -- Standard: nur 1 Fahrzeug pro Spawn-Tick (spawnPerTick).
            -- Jeder Spawn (I3D-Laden + Physik + MP-Sync) erzeugt einen kurzen
            -- Ruckler - mehrere direkt hintereinander stapeln sich spürbar.
            local spawnedThisTick = 0
            local nWpsTotal = self.userTrafficWaypoints ~= nil and #self.userTrafficWaypoints or 0
            local lastOverride = nil
            for _attempt = 1, (self.spawnPerTick or 1) do
                -- Start-WP über pickPatrolWaypoint: gesperrte WPs vermeiden.
                -- lastOverride ausschließen: sonst spawnen mehrere Fahrzeuge
                -- desselben Ticks am SELBEN WP und blockieren sich gegenseitig.
                local overrideWp = nil
                if nWpsTotal >= 1 then
                    overrideWp = self:pickPatrolWaypoint(self.userTrafficWaypoints, lastOverride)
                        or math.random(nWpsTotal)
                end
                lastOverride = overrideWp
                local created = self:generateTraffic(nil, overrideWp)
                if created then
                    spawnedThisTick = spawnedThisTick + 1
                else
                    break  -- Limit erreicht oder keine Fahrzeuge verfuegbar
                end
            end
            if spawnedThisTick > 0 then
                -- Pause bis zum nächsten Spawn (Spielminuten, konfigurierbar):
                -- entzerrt die Spawns → weniger Ruckler auf dem Server.
                self.timeToNextStart = math.random(self.spawnIntervalMin or 2,
                                                   self.spawnIntervalMax or 5)
            else
                self.timeToNextStart = math.max(1, math.floor(1 * timeScale))
            end
        end
    end
end

-- ============================================================
-- Spawn-Blickrichtung (map-unabhaengig)
--
-- Frisch gespawnte Traktoren schauen sonst in die Richtung, die der
-- Shop-Spawnplatz vorgibt - auf manchen Karten ist das eine Wand, ein Hang
-- oder Wasser. Frueher stand hier die feste Krebach-Koordinate der Werkstatt
-- (98.65 / 119.08); die ist auf jeder anderen Karte sinnlos.
--
-- Zwei Stufen, in dieser Reihenfolge:
--   1. Naechstgelegene Werkstatt. Das reproduziert genau die alte Absicht
--      ("Blick zur Ausfahrt = Richtung Workshop"), nur eben auf jeder Karte -
--      auf Krebach findet die Suche exakt jene 98.65/119.08 wieder.
--      Verifiziert: PlaceableWorkshop legt spec_workshop an,
--      g_currentMission.placeableSystem.placeables ist die Liste aller
--      gesetzten Placeables (Placeable.lua:1275).
--   2. Ist keine Werkstatt vorhanden, die Senkrechte des Spawnplatzes selbst.
--      Genau danach richtet das Basisspiel gekaufte Fahrzeuge aus:
--      VehicleLoadingData.lua:539 rechnet
--      MathUtil.getYRotationFromDirection(place.dirPerpX, place.dirPerpZ).
--
-- Findet keine Stufe etwas, bleibt die Rotation unangetastet - lieber die
-- Vorgabe der Karte als ein geratener Winkel.
-- ============================================================

--- Zielpunkt fuer die Blickrichtung. Wird einmal ermittelt und gecacht.
--- @return table|nil { x=, z=, quelle= }
function NachbarFelderManager:getSpawnLookAt()
    if self.spawnLookAt ~= nil then
        return self.spawnLookAt
    end

    -- getShopPosition() ist weiter unten in dieser Datei definiert; als
    -- Methode wird sie erst zur Laufzeit aufgeloest, das ist unkritisch.
    local spX, spZ = self:getShopPosition()

    -- Stufe 1: naechstgelegene Werkstatt
    local bestX, bestZ, bestDist = nil, nil, nil
    local ps = g_currentMission and g_currentMission.placeableSystem
    for _, p in ipairs((ps and ps.placeables) or {}) do
        if p ~= nil and p.spec_workshop ~= nil and p.rootNode ~= nil then
            local x, _, z = getWorldTranslation(p.rootNode)
            local d = MathUtil.vector2Length(x - spX, z - spZ)
            if bestDist == nil or d < bestDist then
                bestDist, bestX, bestZ = d, x, z
            end
        end
    end

    if bestX ~= nil then
        self.spawnLookAt = { x = bestX, z = bestZ, quelle = "Werkstatt" }
        print(string.format("NachbarFelder: Spawn-Blickrichtung = Werkstatt bei x=%.1f z=%.1f (%.0f m entfernt)",
            bestX, bestZ, bestDist or 0))
        return self.spawnLookAt
    end

    -- Stufe 2: Senkrechte des Spawnplatzes (Vorgabe des Karten-Bauers)
    local place = self:getNfSpawnPlace()
    if place ~= nil and place.dirPerpX ~= nil and place.dirPerpZ ~= nil then
        local dx, dz = place.dirPerpX, place.dirPerpZ
        if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
            -- 50 m in Blickrichtung reichen als Zielpunkt voellig aus.
            self.spawnLookAt = { x = spX + dx * 50, z = spZ + dz * 50, quelle = "Spawnplatz" }
        end
    end

    if self.spawnLookAt ~= nil then
        print("NachbarFelder: Spawn-Blickrichtung = Ausrichtung des Shop-Spawnplatzes")
        return self.spawnLookAt
    end

    print("NachbarFelder: Keine Spawn-Blickrichtung ermittelbar - Rotation bleibt wie vom Spiel gesetzt")
    return nil
end

-- ============================================================
-- Spawn-Logik
-- ============================================================
function NachbarFelderManager:onSpawnedVehicle(vehicles, vehicleLoadState, loadingInfo)
    if vehicleLoadState == VehicleLoadingState.OK then
        for _, vehicle in ipairs(vehicles) do
            vehicle.isVehicleSaved = false
            self:applyServerDriverFigure(vehicle)   -- Build 95
            self:applyRueckwaertsPlanen(vehicle)    -- Build 108
            self:applyFahrerBleibt(vehicle)         -- Build 168
            if vehicle.addWearAmount ~= nil then
                vehicle:addWearAmount(math.random() * 0.3 + 0.1)
            end
            vehicle:setOperatingTime(1000 * 60 * 60 * (math.random() * 40 + 30))

            table.remove(loadingInfo.NachbarFelderWorker.vehiclesToLoad, 1)
            local vehAdd = true
            if #loadingInfo.NachbarFelderWorker.vehicleType > 0 then
                if vehicle.typeName == "pallet" then
                    vehAdd = false
                end
                if type(vehicle.getMotor) == "function" or vehicle.typeName == "pallet" then
                    loadingInfo.NachbarFelderWorker.vehiclesToLoad = {}
                    vehicle:delete()
                    vehAdd = false
                end
                -- Anbaugerät/Anhänger SOFORT vom Shop-Spawn weg teleportieren.
                -- Ohne dies steckt der Spawn-Platz (Nähe Boot) das Implement
                -- in der Physik fest, bevor setAttachment es kuppeln kann.
                -- Ziel: Traktor-Position → kein Offset, setAttachment richtet aus.
                if vehAdd then
                    -- Build 116/125: Geraet bis zum Kuppeln ohne Physik - fuer Feldhelfer
                    -- UND Verkehr. Auf den Traktor-Mittelpunkt teleportiert stak es im
                    -- Traktor und flog weg (Server 14.09.: Gespanne landeten im
                    -- eingezaeunten Nachbargrundstueck). setAttachment setzt es spaeter
                    -- genau an die Kupplung und nimmt es wieder in die Physik.
                    if vehicle.isAddedToPhysics then vehicle:removeFromPhysics() end
                end
            else
                -- Ausrichtung korrigieren: Manche Spawn-Plätze schauen gegen
                -- eine Wand oder aufs Wasser. Ziel ist die Ausfahrt, also die
                -- Richtung zur Werkstatt bzw. ersatzweise die Ausrichtung, die
                -- der Karten-Bauer dem Spawnplatz mitgegeben hat.
                -- Siehe getSpawnLookAt(); findet sie nichts, bleibt die vom
                -- Spiel gesetzte Rotation stehen.
                local x0, _, z0 = localToWorld(vehicle.rootNode, 0, 0, 0)
                -- Build 117: Feldhelfer nicht am Shop-Platz stehen lassen. Auf der
                -- Beuren steht der Platz (x=-157 z=-138) zu dicht an der Mauer:
                -- lange Gespanne bekamen dort sofort NotReachable (kein Navmesh
                -- fuer den Agent) und Geraete flogen beim Ausrichten gegen die Wand.
                -- Der Traktor kommt deshalb vor dem Kuppeln auf den naechsten freien
                -- Punkt der KI-Strasse (Build 118: mind. 40 m, ersatzweise 80 m -
                -- 15 m reichten fuer Valtra N + Cultivator 980 nicht), Richtung Feld.
                -- Build 118: auch der Verkehr (Trac 900 solo am Platz sofort
                -- abgewiesen), dort Richtung erstes Fahrziel.
                -- Findet sich keiner, bleibt es beim alten Ausrichten am Platz.
                local nfWS = loadingInfo.NachbarFelderWorker.NachbarFelderWorker
                local istVerkehrS = nfWS ~= nil and nfWS.isPatrol
                -- Build 126: schon an der Strasse geladen -> nicht mehr versetzen
                local aufStrasse = nfWS ~= nil and nfWS.spawnAufStrasse == true
                if not aufStrasse and self.getNearestRoadPoint ~= nil then
                    local function schritt()
                        local zielX, zielZ = nil, nil
                        if istVerkehrS then
                            zielX, zielZ = nfWS.patrolTargetX, nfWS.patrolTargetZ
                        end
                        -- Build 136: Spur in Richtung Ziel statt 180-Grad-Drehung (Einbahn-Splines)
                        local wdx, wdz = nil, nil
                        if zielX ~= nil and zielZ ~= nil then wdx, wdz = zielX - x0, zielZ - z0 end
                        local rx, rz, rry, rdist = self:getRoadPointInRichtung(x0, z0, 160, 40, wdx, wdz)
                        if rx ~= nil and self:isSpotBlockedByAnyVehicle(rx, rz, 12, vehicle) then
                            rx, rz, rry, rdist = self:getRoadPointInRichtung(x0, z0, 200, 80, wdx, wdz)
                            if rx ~= nil and self:isSpotBlockedByAnyVehicle(rx, rz, 12, vehicle) then
                                rx = nil
                            end
                        end
                        if rx == nil then return end
                        local ry = rry or 0
                        g_currentMission:teleportVehicle(vehicle, rx, rz, ry)
                        aufStrasse = true
                        print(string.format("NachbarFelder: [TRAFFIC] %.0f m vom Shop-Platz auf die KI-Strasse" ..
                            " gesetzt (weg von der Wand)", rdist or 0))
                    end
                    schritt()
                end
                local lookAt = self:getSpawnLookAt()
                if lookAt ~= nil and not aufStrasse then
                    local spawnRotY = MathUtil.getYRotationFromDirection(
                        lookAt.x - x0, lookAt.z - z0)
                    g_currentMission:teleportVehicle(vehicle, x0, z0, spawnRotY)
                end
                local x, y, z = localToWorld(vehicle.rootNode, 0, 0, 0)
                local dirX, _, dirZ = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
                local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
                self.vehicleType[loadingInfo.NachbarFelderWorker.fieldId].NachbarFelderWorker.posX = x
                self.vehicleType[loadingInfo.NachbarFelderWorker.fieldId].NachbarFelderWorker.posY = y
                self.vehicleType[loadingInfo.NachbarFelderWorker.fieldId].NachbarFelderWorker.posZ = z
                local useAngle = angle + 180
                if angle > 180 then useAngle = angle - 180 end
                self.vehicleType[loadingInfo.NachbarFelderWorker.fieldId].NachbarFelderWorker.angle = useAngle
            end

            self:setFillCapacity(vehicle, 100000)
            if vehAdd then
                table.insert(self.vehicleType[loadingInfo.NachbarFelderWorker.fieldId].NachbarFelderWorker.vehiclesToLoad, vehicle)
                table.insert(loadingInfo.NachbarFelderWorker.vehicleType, vehicle)
            end
            if #loadingInfo.NachbarFelderWorker.vehiclesToLoad > 0 then
                self:loadVehicles(loadingInfo.NachbarFelderWorker)
            else
                -- Attachment auf nächsten Frame verschieben: InputAttacher-Joints
                -- des letzten Fahrzeugs werden erst nach Rückkehr des Spawn-Callbacks
                -- im vehicleSystem registriert. Sofortiger Aufruf findet das Implement
                -- nicht in g_currentMission.vehicleSystem.inputAttacherJoints → nil-Return.
                loadingInfo.NachbarFelderWorker.NachbarFelderWorker.needAttachment = true
                -- Patrol OHNE Anbaugerät: sofort zum Start-WP teleportieren.
                -- Patrol MIT Anbaugerät: ERST am Shop kuppeln (setAttachment), DANN
                -- als komplettes Gespann zum WP (update-Fallback). Kuppeln direkt
                -- nach einem Weit-Teleport verdrahtet die Zapfwelle mit einem alten
                -- Weltpunkt → kilometerlange "Stange" am Gerät.
                local nfW = loadingInfo.NachbarFelderWorker.NachbarFelderWorker
                if nfW ~= nil and nfW.isPatrol and nfW.firstStart then
                    local wps     = nfW.waypoints
                    local tractor = loadingInfo.NachbarFelderWorker.vehicleType[1]
                    local hasImplement = #loadingInfo.NachbarFelderWorker.vehicleType >= 2
                    if wps ~= nil and #wps >= 1 and tractor ~= nil then
                        local nearestIdx = 1
                        -- Vorgegebener Startpunkt (overrideSpawnWpIdx) hat Vorrang
                        if nfW.overrideSpawnWpIdx ~= nil and wps[nfW.overrideSpawnWpIdx] ~= nil then
                            nearestIdx = nfW.overrideSpawnWpIdx
                        else
                            nearestIdx = self:pickPatrolWaypoint(wps, nil) or math.random(#wps)
                        end
                        -- Belegte Plaetze meiden (Build 73): kein Teleport auf
                        -- einen WP, an dem schon ein Fahrzeug steht (Explosion).
                        local freeIdx = self:findFreeSpawnWp(wps, nearestIdx, tractor)
                        if freeIdx ~= nil then nearestIdx = freeIdx end
                        -- Build 86: WPs, von denen aus nachweislich kein GOTO
                        -- startet, nicht als Startplatz verwenden. Lieber am
                        -- Shop-Spawn stehen bleiben - von dort faehrt es sicher los.
                        -- Build 91: gar kein Spawn-Teleport mehr - siehe die
                        -- ausfuehrliche Begruendung beim Gespann-Spawn. Kurz:
                        -- keine verlaessliche Ausrichtung fuer einen Wegpunkt,
                        -- also startet alles am Shop und faehrt selbst los.
                        nfW.waypointIdx = nearestIdx
                        if nfW.patrolDestIdx == nearestIdx and #wps >= 2 then
                            local nd = self:pickPatrolWaypoint(wps, nearestIdx) or nearestIdx
                            nfW.patrolDestIdx = nd
                            nfW.patrolTargetX = wps[nd][1]
                            nfW.patrolTargetZ = wps[nd][2]
                        end
                        -- Build 96: Die Zeile "freeIdx = nil" aus Build 91 war beim
                        -- Aufraeumen verloren gegangen - Einzeltraktoren wurden
                        -- dadurch weiter auf Wegpunkte teleportiert (mit der
                        -- gespeicherten Blickrichtung = quer). Der Teleport-Zweig
                        -- ist jetzt ganz entfernt, damit er nicht wiederkommt.
                        if not hasImplement then
                            -- Einzeltraktor: am Shop stehen lassen, GOTO faehrt von dort
                            nfW.firstStart = nil
                            print("NachbarFelder: [TRAFFIC] Einzelfahrzeug faehrt vom Ladeplatz los, Ziel WP" ..
                                tostring(nfW.patrolDestIdx))
                        else
                            -- Gespann: am Shop kuppeln, danach faehrt es von dort
                            -- (firstStart bleibt fuer den Kuppel-Ablauf gesetzt).
                            nfW.spawnWpIdx = nearestIdx
                            print("NachbarFelder: [TRAFFIC] Gespann wird am Ladeplatz gekuppelt")
                        end
                    end
                end
            end
        end
    end
end

--- Geraet mit seinem Eingangs-Kupplungspunkt auf den Kupplungspunkt des
--- Traktors setzen und wieder in die Physik nehmen (Build 116).
--- Build 156: auch die DREHUNG passend setzen - wie SupportVehicle:enableSupportVehicle:
--- Position = localToWorld(jointTransform, jointOrigOffsetComponent), Drehung =
--- localRotationToWorld(jointTransform, jointOrigRotOffsetComponent) (Attachable.lua:1957/1958).
--- Bis Build 155 nur die Gierrichtung (wie AttacherJoints:additionalAttachmentLoaded); stand der
--- Eingangspunkt des Geraets anders geneigt als die Kupplung, riss das sofortige Kuppeln den
--- Traktor zur Seite (Test 01.10.: Lintrac 130 / Vario 500 kippten beim Ankuppeln).
--- Mindestens 5 cm ueber dem Boden.
function NachbarFelderManager:setzeGeraetAnKupplung(attacher, attacherJointIndex, implement, inputJointIndex)
    -- Build 160: jede Spielfunktion vorher auf Existenz pruefen
    if attacher == nil or implement == nil or attacher.getAttacherJoints == nil
       or implement.getInputAttacherJoints == nil then
        return
    end
    local ajs = attacher:getAttacherJoints()
    local ijs = implement:getInputAttacherJoints()
    local aj = ajs ~= nil and attacherJointIndex ~= nil and ajs[attacherJointIndex] or nil
    local ij = ijs ~= nil and inputJointIndex ~= nil and ijs[inputJointIndex] or nil
    if aj ~= nil and aj.jointTransform ~= nil and ij ~= nil then
        local offset = ij.jointOrigOffsetComponent or { 0, 0, 0 }
        local x, y, z = localToWorld(aj.jointTransform, unpack(offset))
        local rx, ry, rz = nil, nil, nil
        if ij.jointOrigRotOffsetComponent ~= nil then
            rx, ry, rz = localRotationToWorld(aj.jointTransform, unpack(ij.jointOrigRotOffsetComponent))
        end
        if rx == nil or ry == nil or rz == nil then
            local dirX, _, dirZ = localDirectionToWorld(aj.jointTransform, 1, 0, 0)
            rx, ry, rz = 0, MathUtil.getYRotationFromDirection(dirX, dirZ), 0
        end
        local terrainY = y
        if g_terrainNode ~= nil then
            terrainY = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
        end
        if implement.setAbsolutePosition ~= nil then
            implement:setAbsolutePosition(x, math.max(y, terrainY + 0.05), z, rx, ry, rz)
        end
    end
    if not implement.isAddedToPhysics and implement.addToPhysics ~= nil then implement:addToPhysics() end
end

--- Geraet ankuppeln (Build 156): an die Kupplung setzen, dann WEICH kuppeln wie ein Spieler
--- (VehicleAttachEvent: noSmoothAttach = nil). Mit noSmoothAttach = true (bis Build 155,
--- Spielstand-Laden) sind die Gelenkgrenzen sofort 0 (AttacherJoints:createAttachmentJoint) -
--- jede Restabweichung wird in einem Physik-Schritt erzwungen, der Ruck kippte leichte Traktoren.
--- Gesenkt wird nicht (startLowered = false).
function NachbarFelderManager:kuppleGeraet(info)
    if info == nil then return end
    self:setzeGeraetAnKupplung(info.attacherVehicle, info.attacherVehicleJointDescIndex,
        info.attachable, info.attachableJointDescIndex)
    info.attacherVehicle:attachImplement(info.attachable, info.attachableJointDescIndex,
        info.attacherVehicleJointDescIndex, true, nil, false, false, false)
end

function NachbarFelderManager:attachObjects(vehicle, attachedVehicle, isBackSetting)
    local spec = vehicle.spec_attacherJoints
    local pendingInfo = spec.pendingAttachableInfo
    local attachableInfo = spec.attachableInfo

    local numJoints = #g_currentMission.vehicleSystem.inputAttacherJoints
    local minUpdateJoints = math.max(math.floor(numJoints / 5), 1)
    local firstJoint = 1
    local lastJoint = numJoints

    spec.lastInputAttacherCheckIndex = lastJoint % numJoints
    for attacherJointIndex = 1, #spec.attacherJoints do
        local attacherJoint = spec.attacherJoints[attacherJointIndex]
        if attacherJoint.jointIndex == 0 then
            if vehicle:getIsAttachingAllowed(attacherJoint) then
                for i = firstJoint, lastJoint do
                    local jointInfo = g_currentMission.vehicleSystem.inputAttacherJoints[i]
                    if jointInfo.jointType == attacherJoint.jointType then
                        if jointInfo.vehicle:getIsInputAttacherActive(jointInfo.inputAttacherJoint) then
                            if jointInfo.vehicle:getActiveInputAttacherJointDescIndex() == nil or
                               jointInfo.vehicle:getAllowMultipleAttachments() then
                                local compatibility = AttacherJoints.getAttacherJointCompatibility(
                                    vehicle, attacherJoint, jointInfo.vehicle, jointInfo.inputAttacherJoint)
                                if compatibility then
                                    local isBackCorrect = isBackSetting and attacherJoint.attacherJointDirection < 0
                                                       or not isBackSetting and attacherJoint.attacherJointDirection >= 0
                                    if jointInfo.vehicle == attachedVehicle and isBackCorrect then
                                        pendingInfo.attacherVehicle = vehicle
                                        pendingInfo.attacherVehicleJointDescIndex = attacherJointIndex
                                        pendingInfo.attachable = jointInfo.vehicle
                                        pendingInfo.attachableJointDescIndex = jointInfo.jointIndex
                                        return pendingInfo
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

--- Ladeplatz als ungeeignet merken, wenn ein Fahrzeug dort scheitert (Build 129).
--- Nur wenn es noch innerhalb von 10 m um seinen Ladeplatz steht; je Fahrzeug einmal.
function NachbarFelderManager:merkeSpawnFehlschlag(w, x, z, grund)
    local sp = w ~= nil and w.spawnStrasse or nil
    if type(sp) ~= "table" or x == nil or z == nil or w.spawnPlatzGemeldet then return end
    if MathUtil.vector2Length(x - sp.x, z - sp.z) > 10 then return end
    w.spawnPlatzGemeldet = true
    -- Build 132: Admin-Spawnpunkte nie automatisch sperren (mit nur einem Punkt
    -- ginge es sonst zurueck ins Dorf) - stattdessen einmal einen Hinweis geben.
    if sp.spawnpunktIdx ~= nil then
        self.spawnpunktGemeldet = self.spawnpunktGemeldet or {}
        if not self.spawnpunktGemeldet[sp.spawnpunktIdx] then
            self.spawnpunktGemeldet[sp.spawnpunktIdx] = true
            print(string.format("NachbarFelder: Spawnpunkt WP%d: Fahrzeug kam dort nicht weg (%s) - Punkt pruefen:" ..
                " freie Flaeche, nah an einer befahrbaren Strasse, beim Setzen in Abfahrtrichtung schauen",
                sp.spawnpunktIdx, tostring(grund)))
        end
        return
    end
    self:ladeLadeplatzSperre()
    table.insert(self.spawnPlatzSperre, { sp.x, sp.z, tostring(grund) })
    self:speichereLadeplatzSperre()
    self:hinweisSpawnpunkt(grund)   -- Build 148
    print(string.format("NachbarFelder: Ladeplatz x=%d z=%d taugt nicht (%s) - dauerhaft fuer diese Karte gesperrt" ..
        " (%d Plaetze gesperrt, Datei %s)", math.floor(sp.x), math.floor(sp.z), tostring(grund),
        #self.spawnPlatzSperre, tostring(self:getLadeplatzDatei())))
end

--- Einmaliger Hinweis "Spawnpunkt setzen" (Build 148), wenn ein automatischer Ladeplatz
--- scheitert und auf der Karte noch kein Spawnpunkt gesetzt ist. Ein Spawnpunkt hat immer
--- Vorrang vor der automatischen Suche. Meldung nur, wo ein lokaler Spieler ist (SP / Host);
--- auf dem Dedi steht der Hinweis im Log.
function NachbarFelderManager:hinweisSpawnpunkt(grund)
    if self.spawnHinweisGegeben or self:getHatSpawnpunkte() then return end
    self.spawnHinweisGegeben = true
    print("NachbarFelder: Hinweis - automatischer Ladeplatz gescheitert (" .. tostring(grund) ..
        "). Zuverlaessiger: Spawnpunkt setzen (ESC > Einstellungen > Wegpunkte > Spawnpunkt hier setzen)")
    if g_client ~= nil and g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            nfMeldung("NF_hinweisSpawnpunkt"))
    end
end

--- Datei der gesperrten Ladeplaetze fuer die geladene Karte (Build 142), nil ohne Kartenkennung.
function NachbarFelderManager:getLadeplatzDatei()
    local kennung = nfGetKartenKennung()
    if kennung == nil then return nil end
    return modSettingDirectory .. "NachbarFelderLadeplaetze_" .. kennung .. ".xml"
end

--- Gesperrte Ladeplaetze einmal je Sitzung aus der Kartendatei lesen (Build 142).
--- Wieder freigeben: Datei loeschen (oder Eintrag entfernen) und neu laden.
function NachbarFelderManager:ladeLadeplatzSperre()
    if self.spawnPlatzSperre ~= nil then return end
    self.spawnPlatzSperre = {}
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local pfad = self:getLadeplatzDatei()
    if pfad == nil then return end
    local verworfen = 0
    local function schritt()
        local xmlFile = XMLFile.loadIfExists("NachbarFelderLadeplaetze", pfad, lpXmlSchema)
        if xmlFile == nil then return end
        xmlFile:iterate(lpXmlKey .. ".platz", function(_, key)
            local x = xmlFile:getValue(key .. "#x")
            local z = xmlFile:getValue(key .. "#z")
            local grund = xmlFile:getValue(key .. "#grund") or "?"
            -- Build 145: "umgekippt" lag am Gespann, nicht am Platz (Builds 142-144 sperrten
            -- trotzdem den Platz) -> solche Eintraege verwerfen
            if grund == "umgekippt" then
                verworfen = verworfen + 1
            elseif x ~= nil and z ~= nil then
                table.insert(self.spawnPlatzSperre, { x, z, grund })
            end
        end)
        xmlFile:delete()
    end
    schritt()
    if #self.spawnPlatzSperre > 0 then
        print(string.format("NachbarFelder: %d gesperrte Ladeplaetze geladen (%s)", #self.spawnPlatzSperre, pfad))
    end
    if verworfen > 0 then
        print(string.format("NachbarFelder: %d Ladeplatz-Sperren wegen 'umgekippt' aufgehoben (lag am Gespann)", verworfen))
        self:speichereLadeplatzSperre()
    end
end

function NachbarFelderManager:speichereLadeplatzSperre()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local pfad = self:getLadeplatzDatei()
    if pfad == nil then return end
    local function schritt()
        local xmlFile = XMLFile.create("NachbarFelderLadeplaetze", pfad, lpXmlKey, lpXmlSchema)
        if xmlFile == nil then return end
        for i, p in ipairs(self.spawnPlatzSperre or {}) do
            local key = ("%s.platz(%d)"):format(lpXmlKey, i - 1)
            xmlFile:setFloat(key .. "#x", p[1])
            xmlFile:setFloat(key .. "#z", p[2])
            xmlFile:setString(key .. "#grund", p[3] or "?")
        end
        xmlFile:save(false, false)
        xmlFile:delete()
    end
    schritt()
end

function NachbarFelderManager:getIstSpawnPlatzGesperrt(x, z)
    self:ladeLadeplatzSperre()
    for _, p in ipairs(self.spawnPlatzSperre or {}) do
        if MathUtil.vector2Length(x - p[1], z - p[2]) < NachbarFelderManager.LADEPLATZ_SPERR_RADIUS then return true end
    end
    return false
end

--- Stuetzpunkte der KI-Strasse im Ring minD..maxD um (x, z), nach Entfernung sortiert (Build 128).
--- @return table { {sample, dist}, ... }, sample = { x, z, dirX, dirZ, hoehe }
function NachbarFelderManager:getSpawnKandidaten(x, z, minD, maxD)
    local liste = {}
    if self.roadSamples == nil and not self:buildRoadSamples() then return liste end
    local cell = self.roadSampleCell
    local cx, cz = math.floor(x / cell), math.floor(z / cell)
    local r = math.ceil(maxD / cell)
    for ix = cx - r, cx + r do
        for iz = cz - r, cz + r do
            local list = self.roadSamples[ix .. ":" .. iz]
            if list ~= nil then
                for _, sp in ipairs(list) do
                    local d = MathUtil.vector2Length(sp[1] - x, sp[2] - z)
                    if d >= minD and d <= maxD then
                        liste[#liste + 1] = { sp, d }
                    end
                end
            end
        end
    end
    table.sort(liste, function(a, b) return a[2] < b[2] end)
    return liste
end

--- Echte Fahrbahnhoehe per Strahl von oben (Build 128).
--- Build 127 nahm die Hoehe der KI-Spline - liegt die ueber der Fahrbahn, fiel das Fahrzeug
--- herunter und sprang in die Mauer (Server 14.09. 12:20). Strahl wie
--- GuiTopDownCamera.lua:269 (RaycastUtil.raycastClosest liefert hit, x, y, z sofort).
--- Build 148: Der Strahl trifft auch Baumkronen, Daecher und Schilder UEBER der Strasse.
--- Mit Spline-Hoehe (Ladeplatz an der KI-Strasse): Treffer mehr als HOEHE_UEBERKOPF ueber
--- der Bezugshoehe = Hindernis ueber der Fahrbahn -> Bezugshoehe zurueck, zweiter Wert true.
--- Log 01.10.: Gespanne kippten immer wieder auf denselben Plaetzen nahe dem Shop, auch
--- leichte (Vario 500 + Juwel 6) - abgesetzt in einer Baumkrone, dann heruntergefallen.
--- Ohne Spline-Hoehe (Admin-Spawnpunkt, evtl. auf einer Bruecke) wie bisher.
--- @return number Hoehe, boolean ueberkopf
function NachbarFelderManager:getFahrbahnHoehe(x, z, splineH)
    local gelaende = splineH or 0
    if g_terrainNode ~= nil then
        gelaende = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    end
    local h = nil
    local oben = math.max(gelaende, splineH or gelaende) + 3
    -- Build 154: TERRAIN_DELTA dazu (wie VehicleSystem.lua beim Paletten-Spawn). Ohne sie traf der
    -- Strahl auf Strassen aus Gelaende-Deltas das tiefere Grundgelaende - das Fahrzeug wurde IN
    -- der Fahrbahn geladen, von der Physik herausgedrueckt und huepfte.
    -- Build 162: jede Flagge und den Strahl vorher pruefen (ohne Absicherung waere ein
    -- fehlender Wert ein Spielfehler); ohne Strahl gilt die Gelaendehoehe
    if CollisionFlag ~= nil and RaycastUtil ~= nil and RaycastUtil.raycastClosest ~= nil then
        local maske = 0
        for _, name in ipairs({ "TERRAIN", "TERRAIN_DELTA", "ROAD", "STATIC_OBJECT", "BUILDING" }) do
            local f = CollisionFlag[name]
            if type(f) == "number" then maske = maske + f end
        end
        if maske > 0 then
            local hit, _, hitY = RaycastUtil.raycastClosest(x, oben, z, 0, -1, 0, 10, maske)
            if hit and hitY ~= nil then h = hitY end
        end
    end
    if h ~= nil and splineH ~= nil then
        local bezug = math.max(gelaende, splineH)
        if h > bezug + NachbarFelderManager.HOEHE_UEBERKOPF then
            return bezug, true
        end
    end
    return h or gelaende, false
end

--- Ist die Flaeche fuer ein Gespann frei? (Build 128)
--- Kasten laenge x breite, der Traktor steht vorn am Punkt (x, z), das Gespann reicht
--- nach hinten (gegen ry). Unterkante 0,3 m ueber der Fahrbahnhoehe h, 2 m hoch.
--- Maske wie AISystem.lua:1216; Strassen und Kollisionen ohne Filter ignoriert wie
--- AISystem.lua:1235/1242. Synchron ausgewertet wie PlaceablePlacement.lua:398-408.
function NachbarFelderManager:getIstSpawnFlaecheFrei(x, h, z, ry, laenge, breite)
    local frei = false
    local function schritt()
        local fx, fz = math.sin(ry), math.cos(ry)
        local mx = x - fx * (laenge * 0.5 - 3)
        local mz = z - fz * (laenge * 0.5 - 3)
        local ziel = { treffer = nil }
        ziel.nfUeberlappung = function(target, nodeId)
            if nodeId == nil or nodeId == 0 then return true end
            if getCollisionFilterMask(nodeId) == 1 then return true end
            if CollisionFlag.getHasGroupFlagSet ~= nil and CollisionFlag.ROAD ~= nil
               and CollisionFlag.getHasGroupFlagSet(nodeId, CollisionFlag.ROAD) then return true end
            target.treffer = nodeId
            return false
        end
        -- Build 162: Masken-Werte vorher pruefen; fehlt einer, gilt die Flaeche als belegt
        if CollisionMask == nil or type(CollisionMask.ALL) ~= "number" or CollisionFlag == nil then return end
        local maske = CollisionMask.ALL
        for _, name in ipairs({ "TERRAIN", "TERRAIN_DELTA", "TERRAIN_DISPLACEMENT", "TRIGGER", "FILLABLE" }) do
            local f = CollisionFlag[name]
            if type(f) ~= "number" then return end
            maske = maske - f
        end
        overlapBox(mx, h + 1.3, mz, 0, ry, 0, breite * 0.5, 1.0, laenge * 0.5,
            "nfUeberlappung", ziel, maske, true, true, true, true)
        frei = ziel.treffer == nil
    end
    schritt()
    return frei
end

-- ============================================================
-- Admin-Spawnpunkte (Build 132)
--
-- Die automatische Platzsuche beginnt am Shop-Spawn - der liegt auf vielen
-- Karten mitten im Ort. Dort wurden Fahrzeuge abgewiesen und per Rettungs-
-- Teleport versetzt; Clients sehen jede Positionsaenderung interpoliert
-- (Vehicle.lua:1768 setTargetPosition) - also als Flug durch die Luft.
-- Log 17.09.: "Ladeplatz taugt nicht (Verkehr sofort abgewiesen)" gefolgt von
-- "GOTO kommt nicht weg ... weiter vorn gesetzt".
-- Kartenunabhaengige Loesung: Der Admin setzt Wegpunkte vom Typ Spawnpunkt an
-- Stellen mit Platz. Richtung = Blickrichtung beim Setzen (aus dem Fahrzeug:
-- Fahrtrichtung). Gibt es Spawnpunkte, wird nur dort geladen.
-- ============================================================

function NachbarFelderManager:getHatSpawnpunkte()
    for _, wp in ipairs(self.userTrafficWaypoints or {}) do
        if self:getIstSpawnpunkt(wp) then return true end
    end
    return false
end

--- Freien Spawnpunkt waehlen. Mehrere Punkte werden zufaellig reihum genutzt.
--- @param nurPruefen boolean true = nur feststellen, ob einer frei ist (keine Reservierung)
--- @return table|nil { x, z, ry, h, spawnpunktIdx } im Format von w.spawnStrasse
function NachbarFelderManager:waehleSpawnpunkt(nurPruefen)
    local wps = self.userTrafficWaypoints
    if wps == nil then return nil end
    local kandidaten = {}
    for i, wp in ipairs(wps) do
        if self:getIstSpawnpunkt(wp) and wp.x ~= nil and wp.z ~= nil then
            kandidaten[#kandidaten + 1] = i
        end
    end
    if #kandidaten == 0 then return nil end
    for i = #kandidaten, 2, -1 do
        local j = math.random(i)
        kandidaten[i], kandidaten[j] = kandidaten[j], kandidaten[i]
    end

    self.spawnpunktReserviert = self.spawnpunktReserviert or {}
    local jetzt = g_time or 0
    for _, i in ipairs(kandidaten) do
        -- Reservierung: zwischen Auswahl und fertig geladenem Fahrzeug steht dort
        -- noch nichts Physisches - ohne Sperre naehmen zwei Spawns denselben Platz.
        if (self.spawnpunktReserviert[i] or 0) <= jetzt then
            local wp = wps[i]
            local ry = wp.ry or 0
            -- Liegt eine KI-Strasse direkt am Punkt (8 m) und zeigt die gespeicherte
            -- Richtung ungefaehr an ihr entlang (< 45 Grad), exakt laengs ausrichten.
            -- Bewusst quer gesetzte Punkte (Hofausfahrt) bleiben unveraendert.
            -- Build 136: die Spur mit passender Richtung nehmen (Zwillings-Spline), nie
            -- eine Spur um 180 Grad drehen. Laeuft die Strasse dort nur in Gegenrichtung
            -- (Einbahn), wird mit der Spur ausgerichtet - sonst lehnt die KI jeden Start ab.
            local _, _, rry, _, _, passt = self:getRoadPointInRichtung(wp.x, wp.z, 8, 0,
                math.sin(ry), math.cos(ry))
            if rry ~= nil then
                local dot = math.sin(ry) * math.sin(rry) + math.cos(ry) * math.cos(rry)
                if passt and dot >= 0.707 then
                    ry = rry
                elseif dot <= -0.707 then
                    ry = rry
                    self.spawnpunktEinbahnGemeldet = self.spawnpunktEinbahnGemeldet or {}
                    if not self.spawnpunktEinbahnGemeldet[i] then
                        self.spawnpunktEinbahnGemeldet[i] = true
                        print(string.format("NachbarFelder: Spawnpunkt WP%d: die KI-Strasse ist dort nur in" ..
                            " Gegenrichtung befahrbar - Fahrzeuge starten in Fahrtrichtung der Strasse", i))
                    end
                end
            end
            local h = self:getFahrbahnHoehe(wp.x, wp.z, nil)
            if self:getIstSpawnFlaecheFrei(wp.x, h, wp.z, ry, 17, 4.0) then
                if not nurPruefen then
                    self.spawnpunktReserviert[i] = jetzt + 45000
                end
                return { x = wp.x, z = wp.z, ry = ry, h = h, dist = 0, geprueft = 0, spawnpunktIdx = i }
            end
        end
    end
    return nil
end

--- Ladeposition an der KI-Strasse (Build 126).
---
--- Bis Build 125 wurde am Shop-Platz geladen und der Traktor danach 40 m auf die
--- Strasse versetzt, das Geraet an die Kupplung gesetzt. Auf dem Dedicated Server
--- sahen die Clients das als Flug durch die Luft (14.09.: "Feldhelfer kommen aus der
--- Luft gespawnt", vorher "landen im eingezaeunten Nachbargrundstueck").
--- Jetzt wird der Strassenpunkt EINMAL je Gespann bestimmt (mind. 40 m vom Shop-Platz,
--- ersatzweise 80 m, frei von Fahrzeugen, Richtung Feld bzw. erstes Fahrziel) und jedes
--- Fahrzeug dort geladen: der Traktor auf dem Punkt, Geraete 9/16 m dahinter. Die
--- Geraete bleiben bis zum Kuppeln ohne Physik (Build 116/125).
--- @return boolean true, wenn die Position gesetzt wurde
function NachbarFelderManager:setzeLadepositionStrasse(data, entry)
    local w = entry ~= nil and entry.NachbarFelderWorker or nil
    if w == nil or self.getNearestRoadPoint == nil then return false end
    if w.spawnStrasse == nil then
        w.spawnStrasse = false
        local function schritt()
            -- Build 132: Admin-Spawnpunkt hat Vorrang vor der Suche am Shop
            local spp = self:waehleSpawnpunkt(false)
            if spp ~= nil then
                w.spawnStrasse = spp
                return
            end
            if self:getHatSpawnpunkte() then
                print("NachbarFelder: Alle Spawnpunkte belegt - Ausweich auf die Platzsuche am Shop")
            end
            local sx, sz = self:getShopPosition()
            if sx == nil then return end
            local zielX, zielZ = w.patrolTargetX, w.patrolTargetZ
            -- Build 128: Stuetzpunkte nach Entfernung pruefen, erster freier Platz gewinnt
            -- Build 136: KEINE 180-Grad-Drehung mehr - KI-Strassen sind Einbahn-Splines
            -- (siehe getRoadPointInRichtung). Durchgang 1 nur Punkte, deren Spur Richtung
            -- Ziel zeigt, Durchgang 2 die uebrigen mit ihrer eigenen Richtung. Dazu muss es
            -- voraus frei sein (6-26 m): Log 19.09. standen neue Fahrzeuge 7-9 m hinter
            -- einem schlafenden Pool-Gespann und kamen nie weg.
            -- Build 143: Stufen. Auch Hoefe haben KI-Splines - an einer Hofecke passte der
            -- 17x4-m-Kasten gerade noch, das Gespann kam nicht weg und kippte (Bergisch Land,
            -- Shop-Hof x=-478 z=11). Zuerst nur "echte Strassenstuecke" (gerade, eben, 30x5 m
            -- frei), erst nah, dann weiter draussen; erst danach die alte lockere Pruefung.
            local geprueft = 0
            local mitZiel = zielX ~= nil and zielZ ~= nil
            local stufen = NachbarFelderManager.LADEPLATZ_STUFEN
            for stufe, st in ipairs(stufen) do
                local kandidaten = self:getSpawnKandidaten(sx, sz, st.minD, st.maxD)
                local inStufe = 0
                for durchgang = 1, (mitZiel and 2 or 1) do
                    for _, k in ipairs(kandidaten) do
                        if inStufe >= NachbarFelderManager.LADEPLATZ_MAX_PRUEFUNGEN then break end
                        local sp = k[1]
                        local rx, rz = sp[1], sp[2]
                        local zumZiel = (not mitZiel) or (zielX - rx) * sp[3] + (zielZ - rz) * sp[4] >= 0
                        if (durchgang == 1 and zumZiel) or (durchgang == 2 and not zumZiel) then
                            inStufe = inStufe + 1
                            geprueft = geprueft + 1
                            local ry = MathUtil.getYRotationFromDirection(sp[3], sp[4])
                            local h = self:getFahrbahnHoehe(rx, rz, sp[5])
                            if self:getIstLadeplatzGut(sp, rx, rz, ry, h, st.streng) then
                                w.spawnStrasse = { x = rx, z = rz, ry = ry, h = h, dist = k[2],
                                                   geprueft = geprueft, stufe = stufe }
                                return
                            end
                        end
                    end
                end
            end
            print("NachbarFelder: Kein freier Strassenplatz fuer den Spawn gefunden (" .. tostring(geprueft) ..
                " Stellen geprueft) - Laden am Shop-Platz")
        end
        schritt()
    end
    local sp = w.spawnStrasse
    if sp == false or sp == nil then return false end

    local index = #(entry.vehicleType or {}) + 1
    local hinten = 0
    if index >= 2 then hinten = 9 + (index - 2) * 7 end
    local x = sp.x - math.sin(sp.ry) * hinten
    local z = sp.z - math.cos(sp.ry) * hinten
    local function schritt()
        local modellDrehung = (data.rotation ~= nil and data.rotation[2]) or 0
        -- Build 127: Fahrbahnhoehe statt Gelaendehoehe - Strassen liegen als Objekte
        -- ueber dem Gelaende; darin geladen rutschte das Fahrzeug seitlich heraus.
        -- Build 128: an der Ladestelle (Traktor bzw. Geraet dahinter) gemessene Fahrbahnhoehe
        local y = self:getFahrbahnHoehe(x, z, sp.h) + NachbarFelderManager.SPAWN_HOEHE
        -- Build 155: waagerecht laden, aber so hoch, dass keine Ecke in der Fahrbahn steckt.
        -- Build 154 lud mit der Laengsneigung der Strasse; das Spiel addiert beim Laden aber
        -- die Shop-Drehung des Modells (storeData.shopRotationOffset, VehicleLoadingData) auf
        -- unsere Winkel - aus der Neigung wurde eine Schraeglage zur Seite (Test 01.10.: Vario
        -- 500 lag mit einer Seite am Boden und kippte auf die Raeder). Jetzt: Fahrbahnhoehe
        -- vorn/hinten/links/rechts messen, hoechsten Punkt nehmen (gedeckelt, falls der Strahl
        -- ein Objekt am Rand trifft) - das Fahrzeug faellt hoechstens ein paar cm auf die Raeder.
        local dx, dz = math.sin(sp.ry), math.cos(sp.ry)
        local px, pz = dz, -dx
        local hMitte = y - NachbarFelderManager.SPAWN_HOEHE
        local hMax = hMitte
        local la, sa = NachbarFelderManager.SPAWN_MESS_LAENGS, NachbarFelderManager.SPAWN_MESS_SEITE
        local messpunkte = { { la, 0 }, { -la, 0 }, { 0, sa }, { 0, -sa } }
        for _, o in ipairs(messpunkte) do
            local hh = self:getFahrbahnHoehe(x + dx * o[1] + px * o[2], z + dz * o[1] + pz * o[2], sp.h)
            if hh ~= nil and hh > hMax then hMax = hh end
        end
        hMax = math.min(hMax, hMitte + NachbarFelderManager.SPAWN_MAX_ANHEBEN)
        y = hMax + NachbarFelderManager.SPAWN_HOEHE
        data:setPosition(x, y, z)
        data:setRotation(0, sp.ry + modellDrehung, 0)
        -- Build 154: Anbaugeraete gar nicht erst in die Physik - setAttachment setzt sie an die
        -- Kupplung und nimmt sie dann auf (vorher: geladen, einen Takt Physik, erst dann entfernt)
        if index >= 2 and data.setAddToPhysics ~= nil then
            data:setAddToPhysics(false)
        end
    end
    schritt()
    if index == 1 then
        w.spawnAufStrasse = true
        local wer = "[TRAFFIC] Fahrzeug"
        if sp.spawnpunktIdx ~= nil then
            print(string.format("NachbarFelder: %s wird am Spawnpunkt WP%d geladen", wer, sp.spawnpunktIdx))
        else
            print(string.format("NachbarFelder: %s wird direkt an der KI-Strasse geladen (%.0f m vom Shop-Platz," ..
                " freier Platz, Stufe %s, %d Stellen geprueft)", wer, sp.dist or 0, tostring(sp.stufe or "?"),
                sp.geprueft or 0))
        end
    end
    return true
end

-- Build 154/155: Ladehoehe ueber der hoechsten Fahrbahnstelle unter dem Fahrzeug
NachbarFelderManager.SPAWN_HOEHE        = 0.10   -- m ueber der Fahrbahn (bis Build 153: 0,15)
NachbarFelderManager.SPAWN_MESS_LAENGS  = 2.5    -- m vor und hinter dem Ladepunkt messen
NachbarFelderManager.SPAWN_MESS_SEITE   = 1.2    -- m links und rechts messen
NachbarFelderManager.SPAWN_MAX_ANHEBEN  = 0.5    -- m hoechstens anheben (mehr = Strahl traf ein Objekt)

-- Build 143: Ladeplatz-Suche in Stufen (setzeLadepositionStrasse)
-- streng = echtes Strassenstueck: gerade, eben, grosser freier Kasten
NachbarFelderManager.LADEPLATZ_STUFEN = {
    { minD = 40,  maxD = 250, streng = true  },
    { minD = 250, maxD = 800, streng = true  },
    { minD = 40,  maxD = 250, streng = false },   -- bisherige Pruefung (bis Build 142)
}
NachbarFelderManager.LADEPLATZ_MAX_PRUEFUNGEN = 150   -- je Stufe
NachbarFelderManager.LADEPLATZ_GERADE_ABST    = { -20, -10, 10, 20 }   -- m entlang der Spur
NachbarFelderManager.LADEPLATZ_GERADE_COS     = 0.9   -- Richtungsabweichung hoechstens ~25 Grad
NachbarFelderManager.LADEPLATZ_MAX_HOEHE      = 1.2   -- m Hoehenunterschied auf der Gespannlaenge
-- Build 167: Sperrradius um einen gescheiterten Ladeplatz (vorher 15 m). Log 04.10.: nach der
-- Sperre von x=-363 z=29 wurde der naechste Platz wenige Meter daneben gewaehlt - dasselbe
-- Strassenstueck, das die KI nicht erreicht (NotReachable), die Fahrzeuge kamen wieder nicht weg.
NachbarFelderManager.LADEPLATZ_SPERR_RADIUS   = 40
NachbarFelderManager.HOEHE_UEBERKOPF          = 1.0   -- Build 148: Treffer so weit ueber der Strasse = Hindernis darueber

--- Taugt der Strassenpunkt als Ladeplatz? (Build 143, kartenunabhaengig)
--- Immer: nicht gesperrt, hinten noch Strasse, voraus kein Fahrzeug, Kasten 17 x 4 m frei.
--- streng zusaetzlich: Strasse laeuft 20 m vor und hinter dem Punkt gerade weiter
--- (keine Hofecke, keine Kurve), Fahrbahn eben, Kasten 30 x 5 m frei (Platz zum Losfahren).
function NachbarFelderManager:getIstLadeplatzGut(sp, rx, rz, ry, h, streng)
    if self:getIstSpawnPlatzGesperrt(rx, rz) then return false end   -- Build 129/142
    local dx, dz = sp[3], sp[4]
    -- Build 148: nichts ueber der Fahrbahn (Baumkrone, Dach) auf der Gespannlaenge -
    -- dort landete das Fahrzeug beim Laden oben und stuerzte
    for _, d in ipairs({ 3, 0, -5, -10, -15 }) do
        local _, ueberkopf = self:getFahrbahnHoehe(rx + dx * d, rz + dz * d, sp[5])
        if ueberkopf then return false end
    end
    if self:getNearestRoadPoint(rx - dx * 9, rz - dz * 9, 2.5, 0) == nil then return false end
    if self:isSpotBlockedByAnyVehicle(rx + dx * 16, rz + dz * 16, 10, nil) then return false end
    if not streng then
        return self:getIstSpawnFlaecheFrei(rx, h, rz, ry, 17, 4.0)
    end

    -- gerade Strasse: Stuetzpunkte vor und hinter dem Punkt mit gleicher (oder Gegen-) Richtung
    local abstaende = NachbarFelderManager.LADEPLATZ_GERADE_ABST
    for _, d in ipairs(abstaende) do
        local qx, _, qry = self:getNearestRoadPoint(rx + dx * d, rz + dz * d, 3, 0)
        if qx == nil or qry == nil then return false end
        if math.abs(math.sin(qry) * dx + math.cos(qry) * dz) < NachbarFelderManager.LADEPLATZ_GERADE_COS then
            return false
        end
    end

    -- eben: Fahrbahnhoehe vorn, hinten (Gespannende) und seitlich
    local hMin, hMax = h, h
    local px, pz = -dz, dx
    local messpunkte = { { 3, 0 }, { -14, 0 }, { -5, 2 }, { -5, -2 } }
    for _, p in ipairs(messpunkte) do
        local hx = rx + dx * p[1] + px * p[2]
        local hz = rz + dz * p[1] + pz * p[2]
        local hh = self:getFahrbahnHoehe(hx, hz, sp[5])
        hMin, hMax = math.min(hMin, hh), math.max(hMax, hh)
    end
    if hMax - hMin > NachbarFelderManager.LADEPLATZ_MAX_HOEHE then return false end

    -- Platz: Gespann (17 m) plus Raum zum Losfahren, Kasten reicht 3 m vor den Punkt -> 13 m davor frei
    if not self:getIstSpawnFlaecheFrei(rx + dx * 13, h, rz + dz * 13, ry, 30, 5.0) then return false end
    return true
end

function NachbarFelderManager:loadVehicles(NachbarFelderWorker)
    local vehicles = NachbarFelderWorker.vehiclesToLoad
    if vehicles == nil or #vehicles == 0 then
        print("Keine vehicles gefunden")
        return
    end
    local info = vehicles[1]
    local data = VehicleLoadingData.new()
    data:setFilename(info.filename)
    if data.isValid then
        if info.configurations ~= nil then
            data:setConfigurations(info.configurations)
        end
        local mission = g_currentMission
        -- Spawn exakt wie gekaufte Fahrzeuge: Die Engine wählt einen FREIEN
        -- Shop-Platz inkl. korrekter Ausrichtung (Richtung Ausfahrt/Schranke)
        -- und Kollisionsprüfung. Jedes Fahrzeug (Traktor + Anbaugeräte) bekommt
        -- so seinen eigenen Platz - kein Physik-Clash; setAttachment teleportiert
        -- die Geräte anschliessend hinter den Traktor.
        -- Verifiziert in der Referenz-Mod FarmerWorkingAssistant
        -- (MissionInfo:loadVehicles). Die manuelle Position+Rotation
        -- (Workshop-Mathe) stellte die Helfer verkehrt herum an den falschen
        -- Platz (am Boot) und ist deshalb entfernt.
        -- Build 94: Original-Shop statt Filiallieferungen-Lieferort, die
        -- uebrigen Kartenplaetze als Ausweich (getNfSpawnPlaces).
        -- Build 126: direkt an der KI-Strasse laden (sonst Shop-Platz wie bisher)
        if not self:setzeLadepositionStrasse(data, NachbarFelderWorker) then
            data:setLoadingPlace(self:getNfSpawnPlaces(), mission.usedStorePlaces)
        end
        data:setPropertyState(VehiclePropertyState.MISSION)
        data:setOwnerFarmId(self.farmId)

        local loadingInfo = {loadingData = data, vehicleInfo = info, NachbarFelderWorker = NachbarFelderWorker}
        data:load(self.onSpawnedVehicle, self, loadingInfo)
    end
end

function NachbarFelderManager:setAttachment(NachbarFelderWorker)
    local vehicle = NachbarFelderWorker.vehicleType[1]

    self.vehicleType[NachbarFelderWorker.fieldId].NachbarFelderWorker.status = 1
    self.vehicleType[NachbarFelderWorker.fieldId].NachbarFelderWorker.needTimer = true

    do
        -- Anbaugeräte kuppeln – fehlgeschlagene Kupplungen sind kein Abbruchgrund
        -- (Implement 3 hängt z.B. am Implement 2, nicht direkt am Traktor → fail ist normal)
        for v = 2, #NachbarFelderWorker.vehicleType do
            local implement = NachbarFelderWorker.vehicleType[v]
            local isPatrolRig = NachbarFelderWorker.NachbarFelderWorker ~= nil
                and NachbarFelderWorker.NachbarFelderWorker.isPatrol
            -- Implement direkt hinter den Traktor teleportieren bevor Kupplung.
            -- Verhindert Physik-Explosion wenn Traktor und Implement weit auseinander spawnen.
            -- Build 116: nur noch beim Verkehr (kurze Dreipunkt-Geraete); Feldhelfer
            -- werden unten genau an der Kupplung positioniert.
            -- Build 125: kein Teleport auf den Traktor-Mittelpunkt mehr, auch nicht fuer
            -- den Verkehr - das Geraet wird unten an die Kupplung gesetzt.
            local attacherRef = (v == 2) and vehicle or NachbarFelderWorker.vehicleType[v - 1]
            -- Kupplung: erst am richtigen Kettenglied (attacherRef) probieren, beide Richtungen;
            -- bei v≥3 als Fallback auch direkt am Traktor (vehicle) – FS25 hängt Implement 3
            -- oft direkt an den Traktor, nicht an Implement 2.
            -- v==2 Feldarbeit: nur Heckkupplung (Front-Fallback würde Feldarbeit blockieren)
            -- v==2 Patrol: auch Frontkupplung – Front-Mähwerke (Kategorie MOWERS) gehören
            --              nach VORNE, nicht ans Heck
            -- v>=3: Zusatzgewicht o.ä. → auch Frontkupplung erlaubt
            local pendingInfo = self:attachObjects(attacherRef, implement, true)
            if pendingInfo == nil and (v >= 3 or isPatrolRig) then
                pendingInfo = self:attachObjects(attacherRef, implement, false)
            end
            if pendingInfo == nil and attacherRef ~= vehicle then
                pendingInfo = self:attachObjects(vehicle, implement, true)
                if pendingInfo == nil and v >= 3 then
                    pendingInfo = self:attachObjects(vehicle, implement, false)
                end
            end
            if pendingInfo ~= nil then
                self:kuppleGeraet(pendingInfo)   -- Build 156: drehrichtig setzen, weich kuppeln
            elseif implement ~= nil then
                if not implement.isAddedToPhysics then implement:addToPhysics() end
                if not isPatrolRig then
                    print("NachbarFelder: Feldhelfer - Geraet [" .. tostring(implement.configFileName) ..
                        "] liess sich nicht kuppeln")
                end
            end
        end
    end

    -- Patrol: nicht kuppelbare Geraete löschen statt als Waisen stehen lassen
    -- (z.B. Geraet ohne passende Kupplung am gewaehlten Traktor).
    -- Das Fahrzeug patrouilliert dann solo.
    if NachbarFelderWorker.NachbarFelderWorker ~= nil
       and NachbarFelderWorker.NachbarFelderWorker.isPatrol then
        local worker = NachbarFelderWorker.NachbarFelderWorker
        for v = #NachbarFelderWorker.vehicleType, 2, -1 do
            local impl = NachbarFelderWorker.vehicleType[v]
            local attached = false
            attached = impl ~= nil and impl.getAttacherVehicle ~= nil
                and impl:getAttacherVehicle() ~= nil
            if impl ~= nil and not attached then
                local fname = impl.configFileName or ""
                local base  = string.match(fname, "[^/\\]+$") or fname
                print("NachbarFelder: [TRAFFIC] Anbaugeraet nicht kuppelbar (" .. base ..
                    ") - entfernt, Fahrzeug faehrt solo.")
                if impl ~= nil and impl.delete ~= nil then impl:delete() end
                table.remove(NachbarFelderWorker.vehicleType, v)
                if worker.vehiclesToLoad ~= nil then
                    for i = #worker.vehiclesToLoad, 1, -1 do
                        if worker.vehiclesToLoad[i] == impl then
                            table.remove(worker.vehiclesToLoad, i)
                        end
                    end
                end
            end
        end
    end

    -- Gespann NACH dem Kuppeln geradeziehen: grosse Anbaugeraete ziehen den
    -- Traktor beim Kuppeln schief ("verkehrt herum"). teleportVehicle bewegt
    -- angehaengte Implements mit.
    -- Feldarbeit (spawnt am Shop): Richtung Ausfahrt/Workshop.
    -- Patrol (steht am Start-WP): Richtung Ziel-WP - NICHT Workshop, sonst
    -- dreht sich das Gespann irgendwo auf der Map in Felder/Hindernisse!
    if #NachbarFelderWorker.vehicleType >= 2 then
        local worker = NachbarFelderWorker.NachbarFelderWorker
        local function schritt()
            if vehicle ~= nil and vehicle.rootNode ~= nil then
                local vx, _, vz = getWorldTranslation(vehicle.rootNode)

                -- Build 116: Feldhelfer sitzen jetzt genau an der Kupplung, nichts
                -- ist schief gezogen. Das Drehen des ganzen Gespanns schwenkte ein
                -- langes Geraet am engen Shop in Mauern - der Traktor wurde schon
                -- beim Spawn Richtung Ausfahrt gedreht.
                if not (worker ~= nil and worker.isPatrol) then
                    return
                end

                -- Feldarbeit: Richtung Ausfahrt. Frueher stand hier die feste
                -- Krebach-Koordinate der Werkstatt; jetzt liefert
                -- getSpawnLookAt() den Zielpunkt fuer die geladene Karte.
                -- Ohne Zielpunkt bleibt die Ausrichtung, wie das Kuppeln sie
                -- hinterlassen hat.
                local lookAt = self:getSpawnLookAt()
                if lookAt == nil and not (worker ~= nil and worker.isPatrol) then
                    return
                end

                local tXd, tZd = 0, 0
                if lookAt ~= nil then
                    tXd, tZd = lookAt.x - vx, lookAt.z - vz
                end

                if worker ~= nil and worker.isPatrol then
                    if worker.firstStart then
                        -- Gespann wird gleich komplett zum Start-WP teleportiert
                        -- (inkl. Ausrichtung) → hier nichts drehen.
                        return
                    end
                    if worker.patrolTargetX == nil or worker.patrolTargetZ == nil then
                        return  -- kein Ziel bekannt → Ausrichtung nicht anfassen
                    end
                    tXd = worker.patrolTargetX - vx
                    tZd = worker.patrolTargetZ - vz
                end
                if math.sqrt(tXd * tXd + tZd * tZd) > 1 then
                    local ry = MathUtil.getYRotationFromDirection(tXd, tZd)
                    g_currentMission:teleportVehicle(vehicle, vx, vz, ry)
                end
            end
        end
        schritt()
    end
end

-- Klassennamen einer AIMessage ermitteln. Das Vehicle-Event onAIJobFinished
-- bekommt die AIMessage NICHT übergeben - nur job:stop. Der Klassenname steuert
-- die Fehlerbehandlung im Worker (NotReachable → neues Ziel, OutOfMoney →
-- Konto auffüllen + Retry, SuccessFinishedJob → angekommen).
local NF_AI_MSG_CLASSES = {
    "AIMessageSuccessFinishedJob", "AIMessageSuccessStoppedByUser",
    "AIMessageErrorNoPathFound", "AIMessageErrorOutOfMoney",
    "AIMessageErrorNoHelperAvailable", "AIMessageErrorBlockedByObject",
    "AIMessageErrorVehicleBroken", "AIMessageErrorVehicleDeleted",
    "AIMessageErrorUnknown", "AIMessageErrorFieldNotOwned",
    "AIMessageErrorNoFieldFound", "AIMessageErrorNotReachable",
    "AIMessageErrorOutOfFill", "AIMessageErrorOutOfFuel",
    "AIMessageErrorIsFull", "AIMessageErrorWrongFillType",
    -- Build 147: aus AIDriveStrategyFieldCourse (LUADOC)
    "AIMessageErrorFieldNotReady", "AIMessageErrorVineyardNotSupported",
}

local function nfAIMessageName(msg)
    if msg == nil then return nil end
    for _, n in ipairs(NF_AI_MSG_CLASSES) do
        local cls = _G[n]
        if cls ~= nil then
            if msg.isa ~= nil and msg:isa(cls) then return n end
        end
    end
    return "AIMessageUnbekannt"
end

-- ============================================================
-- Spielverkehr (Build 152)
-- Die Autos des Spielverkehrs (Engine, g_currentMission.trafficSystem) bremsen
-- nur fuer angemeldete Objekte. Das Spiel meldet einen Spieler zu Fuss an
-- (Player.lua: addTrafficSystemPlayer mit graphicsRootNode) und ein Fahrzeug,
-- in das ein Spieler einsteigt (Enterable.lua:1724, components[1].node; beim
-- Aussteigen removeTrafficSystemPlayer, Zeile 1808). Fahrzeuge ohne Fahrer -
-- also auch unsere - kennt der Spielverkehr nicht und faehrt in sie hinein.
-- Deshalb melden wir Traktor und Geraete beim Losfahren genauso an und beim
-- Einschlafen im Pool, Loeschen und Spielende wieder ab.
-- Abschaltbar: <spielverkehrAnmelden>false</...> in der Server-Konfig.
-- ============================================================
function NachbarFelderManager:getSpielverkehrId()
    local ts = g_currentMission ~= nil and g_currentMission.trafficSystem or nil
    if ts == nil or ts.trafficSystemId == nil or ts.trafficSystemId == 0 then return nil end
    return ts.trafficSystemId
end

function NachbarFelderManager:meldeBeimSpielverkehrAn(vehicle)
    if self.spielverkehrAnmelden == false or self.isShuttingDown then return end
    if not self:getIsVehicleAlive(vehicle) or vehicle.nf_spielverkehrNode ~= nil then return end
    if addTrafficSystemPlayer == nil then return end
    local id = self:getSpielverkehrId()
    if id == nil then return end
    local node = vehicle.components ~= nil and vehicle.components[1] ~= nil and vehicle.components[1].node or nil
    if node == nil then return end
    addTrafficSystemPlayer(id, node)
    vehicle.nf_spielverkehrNode = node
    if not self.spielverkehrGemeldet then
        self.spielverkehrGemeldet = true
        print("NachbarFelder: [TRAFFIC] Fahrzeuge werden beim Spielverkehr angemeldet (Autos bremsen fuer sie)")
    end
end

function NachbarFelderManager:meldeGespannBeimSpielverkehrAn(vehicle)
    if self.spielverkehrAnmelden == false or vehicle == nil then return end
    self:meldeBeimSpielverkehrAn(vehicle)
    local function schritt()
        if vehicle.getChildVehicles == nil then return end
        for _, v in ipairs(vehicle:getChildVehicles()) do
            if v ~= vehicle then self:meldeBeimSpielverkehrAn(v) end
        end
    end
    schritt()
end

function NachbarFelderManager:meldeBeimSpielverkehrAb(vehicle)
    local node = vehicle ~= nil and vehicle.nf_spielverkehrNode or nil
    if node == nil then return end
    vehicle.nf_spielverkehrNode = nil
    if removeTrafficSystemPlayer == nil then return end
    local id = self:getSpielverkehrId()
    if id == nil then return end
    if removeTrafficSystemPlayer ~= nil then removeTrafficSystemPlayer(id, node) end
end

-- ============================================================
-- driveToField: GOTO-Job zum naechsten Ziel oder zurück zum Ladeplatz
-- (Name historisch - seit Build 150 nur noch Verkehr)
-- WICHTIG: farmId darf NICHT 0 (Spectator) sein – der Engine
-- lehnt solche Jobs sofort ab → onAIJobFinished nach 5ms!
-- ============================================================
function NachbarFelderManager:driveToField(vehicle, fieldId, x, y, z, angleSD)
    if x == nil or z == nil then return end

    -- Build 150: nur noch Verkehr (fieldId < 0 = Patrol-Schluessel). Kein createAgent:
    -- Vanilla "Freie Fahrt" macht das auch nicht. AIJobGoTo ruft createAgent intern
    -- auf - ein vorheriger Aufruf korrumpiert den Agent-State.
    -- prepareForAIDriving, aber OHNE createAgent.
    if vehicle.prepareForAIDriving ~= nil then
        vehicle:prepareForAIDriving()
    end

    -- Anbaugeräte für Straßenfahrt falten (auch für Patrol sinnvoll).
    if vehicle.getAttachedImplements ~= nil then
        for _, att in ipairs(vehicle:getAttachedImplements()) do
            local impl = att.object
            if impl ~= nil then
                if impl.prepareForAIDriving ~= nil then
                    impl:prepareForAIDriving()
                end
                -- Build 112: Einklapp-Richtung haengt vom Geraet ab. Ausgeklappt
                -- ist ein Geraet in Richtung turnOnFoldDirection (Foldable.lua:941-949),
                -- eingeklappt wird mit -turnOnFoldDirection (so macht es das Spiel,
                -- FillUnit.lua:1746, und die Mod beim Ankuppeln). Das feste -1 klappte
                -- Geraete mit turnOnFoldDirection = -1 vor JEDER Fahrt wieder aus -
                -- Verkehr fuhr mit ausgeklapptem Wender/Grubber und blieb ueberall haengen.
                if impl.setFoldDirection ~= nil then
                    local wd = 1
                    if impl.spec_foldable ~= nil and impl.spec_foldable.turnOnFoldDirection ~= nil then
                        wd = impl.spec_foldable.turnOnFoldDirection
                    end
                    impl:setFoldDirection(-wd)
                end
            end
        end
    end

    -- Build 122: nicht eingeklappte Geraete loggen und in 10 s nachpruefen
    local function schritt()
        if vehicle.getAttachedImplements == nil then return end
        for _, att in ipairs(vehicle:getAttachedImplements()) do
            local impl = att.object
            if self:getIstEingeklappt(impl) == false then
                print("NachbarFelder: [KLAPP] Einklappbefehl gegeben, noch offen: " .. self:getKlappText(impl))
                self.klappPruefung = self.klappPruefung or {}
                table.insert(self.klappPruefung, { impl = impl, at = g_time + 10000 })
            end
        end
    end
    schritt()

    -- Motor sicherstellen (nach fehlgeschlagener Feldarbeit kann Motor aus sein)
    if vehicle.startMotor ~= nil and vehicle.getIsMotorStarted ~= nil
       and not vehicle:getIsMotorStarted() then
        vehicle:startMotor(true)
    end

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
    -- Kostenneutral (Build 91): NF-Jobs laufen auf der NPC-Farm 2 und sollen
    -- dort nichts kosten. AIJob:updateCost() bucht pro Millisekunde
    -- getPricePerMs() ab (Basis 0.0004, AIJob.lua:203) und stoppt den Job mit
    -- AIMessageErrorOutOfMoney, sobald getBalance() nicht mehr reicht
    -- (AIJob.lua:177). Preis 0 heisst: keine Buchung, keine Geldpruefung, kein
    -- Eingriff in den Kontostand der NPC-Farm.
    if job ~= nil then
        job.getPricePerMs = function() return 0 end
    end
    if job == nil then
        print("NachbarFelder: FEHLER - AIJobType.GOTO konnte nicht erstellt werden!")
        return
    end
    job.positionAngleParameter:setPosition(x, z)
    job.positionAngleParameter:setAngle(angleSD or 0)
    job.vehicleParameter:setVehicle(vehicle)
    job:setValues()

    -- Dauerschreiber (jeder Hop): nur im Debug-Log (logLevel=2)
    self:log(2, "NachbarFelder: GOTO Start -> x=" .. tostring(math.floor(x or 0)) ..
        " z=" .. tostring(math.floor(z or 0)) ..
        " farmId=" .. tostring(self.farmId) ..
        " Feld=" .. tostring(fieldId))

    -- Fahrzeuge ohne createAgent können keinen GOTO-Job ausführen
    -- (AIJobGoTo.lua ruft createAgent intern auf → Engine-Crash)
    if vehicle.createAgent == nil then
        local fname = vehicle.configFileName
        local baseName = fname ~= nil and (string.match(fname, "[^/\\]+$") or fname) or tostring(vehicle.typeName)
        print("NachbarFelder: kein createAgent auf " .. baseName .. " - Fahrzeug wird gesperrt")
        -- Session-Blacklist: nie wieder spawnen
        if fname ~= nil then
            self.trafficVehicleBlacklist = self.trafficVehicleBlacklist or {}
            if not self.trafficVehicleBlacklist[fname] then
                self.trafficVehicleBlacklist[fname] = true
                print("NachbarFelder: [TRAFFIC] Blacklist: " .. baseName .. " (kein createAgent)")
                self.trafficVehicleList = nil
                -- Aus Stammfahrzeug-Slots entfernen
                for i = #self.regularVehicleXMLs, 1, -1 do
                    if self.regularVehicleXMLs[i] == fname then
                        table.remove(self.regularVehicleXMLs, i)
                    end
                end
                for i = #self.pendingRespawns, 1, -1 do
                    if self.pendingRespawns[i] ~= nil
                       and self.pendingRespawns[i].filename == fname then
                        table.remove(self.pendingRespawns, i)
                    end
                end
            end
        end
        local entry = self.vehicleType[fieldId]
        if entry ~= nil and entry.NachbarFelderWorker ~= nil then
            entry.NachbarFelderWorker.noPool    = true
            entry.NachbarFelderWorker.status    = 100
            entry.NachbarFelderWorker.needTimer = true
        end
        return
    end

    -- Berechtigungen VOR startJob setzen (Job prüft Erlaubnis beim Start).
    -- setOwnerFarmId ist zwingend: aiSystem:startJob prüft vehicle.ownerFarmId == farmId;
    -- MISSION-Vehicles können ownerFarmId=0 haben obwohl beim Laden farmId=2 gesetzt wurde.
    if vehicle ~= nil and vehicle.setOwnerFarmId ~= nil then vehicle:setOwnerFarmId(self.farmId) end
    self:markVehiclesAsHelper(vehicle)

    -- Stop-Grund für den Worker merken: nur job:stop sieht die AIMessage.
    local nfWEntry = self.vehicleType[fieldId]
    local nfW = nfWEntry ~= nil and nfWEntry.NachbarFelderWorker or nil
    if nfW ~= nil and job.stop ~= nil then
        local origStop = job.stop
        job.stop = function(jSelf, aiMessage)
            nfW.lastStopMsg = nfAIMessageName(aiMessage)
            return origStop(jSelf, aiMessage)
        end
    end

    g_currentMission.aiSystem:startJob(job, self.farmId)

    -- Build 152: Gespann beim Spielverkehr anmelden, damit die Autos bremsen
    self:meldeGespannBeimSpielverkehrAn(vehicle)

    -- Build 100: Zustand direkt NACH dem Start. Nur so ist zu sehen, warum ein
    -- Auftrag ohne Fehlermeldung anlaeuft und das Fahrzeug trotzdem steht.
    if nfW ~= nil and nfW.isPatrol then
        print("NachbarFelder: [TRAFFIC][DIAG] nach Start: " .. self:getVehicleAiDiag(vehicle))
    end
end

--- Ist ein Geraet eingeklappt? (Build 122) nil = hat keine Klappteile.
--- Eingeklappt = Animationsende gegenueber turnOnFoldDirection (Foldable.lua:378-381).
function NachbarFelderManager:getIstEingeklappt(impl)
    local sf = impl ~= nil and impl.spec_foldable or nil
    if sf == nil or not sf.hasFoldingParts or sf.foldAnimTime == nil then return nil end
    if (sf.turnOnFoldDirection or 1) < 0 then
        return sf.foldAnimTime > 0.99
    end
    return sf.foldAnimTime < 0.01
end

function NachbarFelderManager:getKlappText(impl)
    local sf = impl ~= nil and impl.spec_foldable or nil
    if sf == nil then return "kein Foldable" end
    local f = impl.configFileName or ""
    return string.format("%s animTime=%.2f turnOn=%s moveDir=%s middle=%s allowByAI=%s foldAllowed=%s",
        string.match(f, "[^/\\]+$") or f, sf.foldAnimTime or -1, tostring(sf.turnOnFoldDirection),
        tostring(sf.foldMoveDirection), tostring(sf.foldMiddleAnimTime), tostring(sf.allowUnfoldingByAI),
        tostring(sf.isFoldAllowed))
end

function NachbarFelderManager:setFillCapacity(vehicle, cap, forceFillTypeName)
    if vehicle.getFillUnits ~= nil then
        for index, fillUnit in ipairs(vehicle:getFillUnits()) do
            local fillUnitIndex = fillUnit.fillUnitIndex or index
            if vehicle.spec_fillUnit.fillUnits[fillUnitIndex] ~= nil then
                local fillUnitData = vehicle.spec_fillUnit.fillUnits[fillUnitIndex]
                local fillTypeIndex = fillUnitData.fillType
                local fillTypeName = g_fillTypeManager:getFillTypeNameByIndex(fillTypeIndex)

                -- Wenn forceFillTypeName angegeben: diesen Fülltyp erzwingen (z.B. HERBICIDE für herbicideMission)
                if forceFillTypeName ~= nil and fillUnitData.supportedFillTypes ~= nil then
                    local forcedIndex = g_fillTypeManager:getFillTypeIndexByName(forceFillTypeName)
                    if forcedIndex ~= nil and fillUnitData.supportedFillTypes[forcedIndex] then
                        fillTypeIndex = forcedIndex
                        fillTypeName = forceFillTypeName
                    end
                end

                if fillTypeName == "UNKNOWN" or fillTypeName == nil then
                    local preferredFillTypes = {"FERTILIZER","LIQUIDFERTILIZER","HERBICIDE","SEEDS","LIME"}
                    if fillUnitData.supportedFillTypes ~= nil then
                        for _, preferredName in ipairs(preferredFillTypes) do
                            local preferredIndex = g_fillTypeManager:getFillTypeIndexByName(preferredName)
                            if preferredIndex ~= nil and fillUnitData.supportedFillTypes[preferredIndex] then
                                fillTypeIndex = preferredIndex
                                fillTypeName = preferredName
                                break
                            end
                        end
                    end
                end

                if fillTypeName ~= "UNKNOWN" and fillTypeName ~= nil then
                    local targetCapacity = tonumber(fillUnitData.capacity) or 0
                    if targetCapacity <= 0 then
                        targetCapacity = tonumber(cap) or 100000
                        fillUnitData.capacity = targetCapacity
                    end
                    -- Tank vollständig füllen (kein künstliches Limit mehr)
                    local targetFillLevel = targetCapacity
                    if vehicle.setFillUnitFillLevel ~= nil then
                        vehicle:setFillUnitFillLevel(fillUnitIndex, targetFillLevel, fillTypeIndex, nil)
                    else
                        fillUnitData.fillLevel = targetFillLevel
                        fillUnitData.fillLevelToDisplay = targetFillLevel
                    end
                end
            end
        end
    end
end

-- Build 142: Hochachse des Traktors zeigt weniger als so weit nach oben (cos ~72 Grad) = umgekippt
NachbarFelderManager.KIPP_GRENZE = 0.3

-- ============================================================
-- generateTraffic: Fahrzeug fährt zu einem Feld-Zielpunkt, parkt
-- eine Weile und kehrt zum Shop zurück (kein Feldarbeit-Job).
-- Liefert einen Punkt nahe dem Rand eines zufälligen Feldes.
-- Felder werden von Straßen umgeben → Feldrand ≈ Straßenrand.
-- Radius wird aus areaHa geschätzt (Kreisannäherung + 10m Puffer).
-- ============================================================
function NachbarFelderManager:getTrafficWaypoint()
    -- User-Wegpunkte: wenn gesetzt, werden NUR diese verwendet (kein Zufall).
    -- Macht die Mod karten-unabhängig und verhindert Stopps mitten auf dem Feld.
    -- Fallback auf Zufalls-Suche nur wenn noch gar keine Wegpunkte gesetzt wurden.
    if self.userTrafficWaypoints ~= nil and #self.userTrafficWaypoints > 0 then
        local wp = self.userTrafficWaypoints[math.random(#self.userTrafficWaypoints)]
        return wp.x, wp.z
    end

    local fields = g_fieldManager:getFields()

    -- Feldmittelpunkte + Sicherheitsradien vorberechnen (Kreisannäherung + 60m Puffer)
    local fieldCircles = {}
    for _, f in pairs(fields) do
        if f ~= nil and f.posX ~= nil then
            local r = 80
            if f.areaHa ~= nil and f.areaHa > 0 then
                r = math.sqrt(f.areaHa * 10000 / math.pi) + 60
            end
            table.insert(fieldCircles, { x = f.posX, z = f.posZ, r = r })
        end
    end

    -- Map-Ausdehnung ermitteln
    local halfSize = 1400
    if g_currentMission.terrainSize ~= nil then
        halfSize = g_currentMission.terrainSize * 0.34
    end

    -- Zufällige Map-Positionen testen bis eine außerhalb aller Felder liegt
    for _ = 1, 60 do
        local x = (math.random() * 2 - 1) * halfSize
        local z = (math.random() * 2 - 1) * halfSize
        local inField = false
        for _, fc in ipairs(fieldCircles) do
            if MathUtil.vector2Length(x - fc.x, z - fc.z) < fc.r then
                inField = true
                break
            end
        end
        if not inField then
            return x, z
        end
    end
    return nil
end

-- Hilfsfunktionen für Traffic-Listen (Modul-Scope, wiederverwendbar)
local function nfIsWaterVehicle(filename)
    local f = filename:lower()
    return f:find("boat")        ~= nil or f:find("ship")      ~= nil
        or f:find("ferry")       ~= nil or f:find("barge")     ~= nil
        or f:find("vessel")      ~= nil or f:find("aquaculture") ~= nil
        or f:find("maritime")    ~= nil or f:find("fishing")   ~= nil
        or f:find("highlandsfishing") ~= nil
end

-- Build 105: Shop-Werte nachladen. Das Spiel setzt storeItem.specs beim Laden
-- auf nil (StoreManager.lua:943) und fuellt sie erst bei Bedarf aus der
-- Fahrzeug-XML (StoreItemUtil.loadSpecsFromXML, StoreItemUtil.lua:215). Auf
-- dem Dedicated Server oeffnet niemand den Shop - specs blieb nil. Nur fuer
-- Kandidaten aufrufen: es liest pro Artikel eine XML-Datei.
local function nfLoadSpecs(item)
    if item ~= nil and item.specs == nil and StoreItemUtil ~= nil
       and StoreItemUtil.loadSpecsFromXML ~= nil then
        if StoreItemUtil ~= nil and StoreItemUtil.loadSpecsFromXML ~= nil then
            StoreItemUtil.loadSpecsFromXML(item)
        end
    end
end

-- Leergewicht aus StoreItem-Specs (in kg, nil wenn nicht verfügbar).
--
-- Build 105: specs.weight ist KEINE Zahl, sondern eine Tabelle (componentMass
-- in Tonnen, Konfigurationen, Raeder ... - Vehicle.loadSpecValueWeight,
-- Vehicle.lua:4658). tonumber() darauf ergab immer nil, und der Filter
-- "w == nil or w <= max" liess jedes Fahrzeug durch - deshalb fuhren TK4, 7S
-- und 6R trotz "bis 12 t". Das Spiel rechnet die Masse selbst mit
-- Vehicle.getSpecValueWeight aus (Tonnen, Vehicle.lua:4728).
local function nfGetItemWeight(item)
    nfLoadSpecs(item)
    local t = nil
    if item.specs ~= nil and item.specs.weight ~= nil
       and Vehicle ~= nil and Vehicle.getSpecValueWeight ~= nil then
        t = Vehicle.getSpecValueWeight(item, nil, nil, nil, true, false)
    end
    t = tonumber(t)
    return (t ~= nil and t > 0) and (t * 1000) or nil
end

-- Motorleistung laut Shop (specs.power, Motorized.lua:97/3747), nil wenn unbekannt.
local function nfGetItemPower(item)
    nfLoadSpecs(item)
    local p = nil
    if item.specs ~= nil then p = tonumber(item.specs.power) end
    return (type(p) == "number" and p > 0) and p or nil
end

-- Leistungsbedarf eines Geraets (specs.neededPower.base, PowerConsumer.lua:502/538).
-- Gleiche Einheit wie specs.power - beides steht so in den Store-Daten.
local function nfGetItemNeededPower(item)
    nfLoadSpecs(item)
    local p = nil
    local np = item.specs ~= nil and item.specs.neededPower or nil
    if type(np) == "table" then p = tonumber(np.base) else p = tonumber(np) end
    return (type(p) == "number" and p > 0) and p or nil
end

-- Build 159: Arbeitsbreite laut Shop in Metern, nil wenn unbekannt.
-- specs.workingWidth = { width, minWidth } (Vehicle.loadSpecValueWorkingWidth),
-- bei Geraeten mit Breiten-Konfiguration specs.workingWidthConfig =
-- { [configName] = { [index] = { width, isSelectable } } } - dann zaehlt die
-- groesste Breite, weil das Geraet mit Standard-Konfiguration geladen wird und
-- wir die nicht sicher kennen (lieber zu vorsichtig).
local function nfGetItemWorkingWidth(item)
    nfLoadSpecs(item)
    local specs = item ~= nil and item.specs or nil
    if type(specs) ~= "table" then
        return nil
    end
    local w = nil
    local ww = specs.workingWidth
    if type(ww) == "table" then
        w = tonumber(ww.width)
    elseif ww ~= nil then
        w = tonumber(ww)
    end
    if w == nil and type(specs.workingWidthConfig) == "table" then
        for _, liste in pairs(specs.workingWidthConfig) do
            if type(liste) == "table" then
                for _, e in pairs(liste) do
                    local b = type(e) == "table" and tonumber(e.width) or nil
                    if b ~= nil and (w == nil or b > w) then w = b end
                end
            end
        end
    end
    return (type(w) == "number" and w > 0) and w or nil
end

-- Build 164: Hoechstgeschwindigkeit laut Shop in km/h, nil wenn unbekannt.
-- specs.maxSpeed (Motorized.loadSpecValueMaxSpeed: storeData-Wert, Motor-Konfiguration
-- oder aus den Gaengen berechnet).
local function nfGetItemMaxSpeed(item)
    nfLoadSpecs(item)
    local specs = item ~= nil and item.specs or nil
    if type(specs) ~= "table" then
        return nil
    end
    local v = tonumber(specs.maxSpeed)
    return (type(v) == "number" and v > 0) and v or nil
end

-- Nutzlast aus StoreItem-Specs (in Litern, nil wenn nicht verfügbar).
local function nfGetItemCapacity(item)
    local cap = nil
    if item.specs ~= nil then
        cap = tonumber(item.specs.maxCapacity) or tonumber(item.specs.capacity)
    end
    return (type(cap) == "number" and cap > 0) and cap or nil
end

-- Fahrzeugkategorien für KI-Traffic:
-- NUR Traktoren haben in FS25 einen AIFieldWorker-Navigation-Agent (GOTO-fähig).
-- CARS / TRUCKS / MOTORCYCLES haben KEINEN Navigation-Agent → scheitern bei 0ms.
-- TRACTORSL eingeschlossen: Großtraktoren können navigieren, sind nur breiter.
local NF_MAX_VEH_WEIGHT_KG       = 18000  -- 18 t: schließt Sattelzugmaschinen aus, Traktoren bleiben
local NF_MAX_TRAILER_WEIGHT_KG   =  6000  -- 6 t Leergewicht-Grenze (gilt für alle Größen-Stufen)
-- Kapazitätsgrenzen nach trafficTrailerSize (0=keine, 1=klein, 2=mittel, 3=alle)
local NF_TRAILER_CAP_BY_SIZE = { [0]=0, [1]=4000, [2]=8000, [3]=15000 }

-- Enge Karte (engeMap): Kleintraktoren wiegen 3-6 t, ein Fendt 900 gut 11 t.
-- Die 8-t-Grenze laesst die Klasse TRACTORSS vollstaendig durch und faengt
-- falsch einsortierte Brocken ab, ohne dass eine zweite Liste noetig waere.
-- Klein- UND Mitteltraktoren sind zugelassen, nur die Grossklasse faellt raus.
-- 12 t laesst einen Fendt 700 (~9 t) oder JD 6R (~11 t) durch und faengt
-- Brocken ab, die faelschlich in TRACTORSM einsortiert sind.
local NF_ENG_MAX_VEH_WEIGHT_KG  = 12000
-- Build 105: Kleintraktoren wiegen 3-6 t; 7 t faengt Ausreisser ab, die
-- faelschlich in TRACTORSS einsortiert sind.
local NF_KLEIN_MAX_VEH_WEIGHT_KG = 7000
-- Build 164: Mini- und Raupen-Kompakttraktoren fahren nur 10-20 km/h, halten den
-- Verkehr auf und blieben im Test ohne Hindernis stehen. Darunter kein Verkehr.
-- Unbekanntes Tempo zaehlt nicht als zu langsam.
local NF_MIN_VEH_SPEED_KMH = 30
-- Auch innerhalb der leichten Kategorien gibt es Brocken: ein 8-m-Schwader
-- zaehlt als RAKES, ist aber breiter als der halbe Feldweg. Die Arbeitsbreite
-- steht nicht in den StoreItem-Specs (nur item.specs.weight ist dort belegt),
-- deshalb dient das Leergewicht als Ersatzmass.
local NF_ENG_MAX_IMPL_WEIGHT_KG = 3000
-- Build 159: Groessenverhaeltnis Traktor/Geraet. Ein Rigitrac SKH 60 zog einen
-- 7,7-m-Zettwender (Claas Volto 80) - Gewicht und Leistung passten, die Optik
-- nicht. Erlaubte Arbeitsbreite je Tonne Traktorgewicht, mit Unter-/Obergrenze.
-- Bei unbekanntem Traktorgewicht gilt die Untergrenze.
local NF_IMPL_BREITE_JE_TONNE = 1.2   -- m Arbeitsbreite je t Traktor
local NF_IMPL_BREITE_MIN      = 3.0   -- m, so breit darf es immer sein
local NF_IMPL_BREITE_MAX      = 6.0   -- m, breiter nie (Kleintraktoren bis 7 t)
-- Geraete ohne lesbare Arbeitsbreite nur, wenn sie hoechstens so viel wiegen.
local NF_IMPL_OHNE_BREITE_MAX_KG = 1000

-- Kategorien, die bei engeMap gefahren werden duerfen. Radlader und
-- Teleskoplader bleiben draussen: kurz, aber breit, und sie rangieren staendig.
local NF_ENG_CATS = { TRACTORSS = true, TRACTORSM = true }

local nfMotorCats = {
    TRACTORSS=true,              -- Kleintraktoren  (bis ~100 PS)
    TRACTORSM=true,              -- Mitteltraktoren (100–200 PS)
    TRACTORSL=true,              -- Großtraktoren   (200+ PS) – breit, aber GOTO-fähig
    WHEELLOADERVEHICLES=true,    -- Radlader – wird beim Spawn blacklistet falls kein Nav-Agent
    TELELOADERVEHICLES=true,     -- Teleskoplader – wird beim Spawn blacklistet falls kein Nav-Agent
    CARS=true,                   -- Autos – wird beim Spawn blacklistet falls kein Nav-Agent
    MOTORCYCLES=true,            -- Motorraeder – wird beim Spawn blacklistet falls kein Nav-Agent
}

-- ============================================================
-- Nutzt negative Pseudo-IDs als vehicleType-Key.
-- Fahrzeugtypen: alle motorisierten Store-Fahrzeuge.
-- ============================================================
function NachbarFelderManager:buildTrafficVehicleList()
    self.trafficVehicleList = {}
    if g_storeManager == nil then return end

    local allItems = {}
    if g_storeManager ~= nil and g_storeManager.getItems ~= nil then allItems = g_storeManager:getItems() end

    local eng = (self.engeMap ~= false)

    -- Aktive Kategorien: nfMotorCats als Basis, durch vehicleCatEnabled ueberschrieben
    local activeCats = {}
    for cat, _ in pairs(nfMotorCats) do
        if self.vehicleCatEnabled ~= nil and self.vehicleCatEnabled[cat] ~= nil then
            activeCats[cat] = self.vehicleCatEnabled[cat]
        else
            activeCats[cat] = true
        end
    end

    -- Build 105: auf JEDER Karte nur Kleintraktoren. Mittel- und Grossmaschinen
    -- samt Zugfahrzeug machen als Nachbar-Verkehr nirgends Sinn (Wunsch des
    -- Users). Die Kategorie-Schalter bleiben wirksam: wer Kleintraktoren
    -- abschaltet, bekommt keinen Verkehr.
    for cat, _ in pairs(activeCats) do
        activeCats[cat] = (cat == "TRACTORSS") and activeCats[cat] == true
    end

    local maxGewicht  = NF_KLEIN_MAX_VEH_WEIGHT_KG
    local ohneGewicht = {}
    local zuLangsam   = 0

    for _, item in pairs(allItems) do
        if item ~= nil and item.xmlFilename ~= nil
           and activeCats[item.categoryName] == true
           and not nfIsWaterVehicle(item.xmlFilename)
           and not (self.trafficVehicleBlacklist and self.trafficVehicleBlacklist[item.xmlFilename]) then
            local w = nfGetItemWeight(item)
            local tempo = nfGetItemMaxSpeed(item)
            -- Build 164: zu langsame Fahrzeuge (Mini-/Raupentraktoren) aussortieren
            if tempo ~= nil and tempo < NF_MIN_VEH_SPEED_KMH then
                zuLangsam = zuLangsam + 1
                print(string.format("NachbarFelder: [TRAFFIC]   zu langsam (%.0f km/h): %s", tempo,
                    tostring(string.match(item.xmlFilename, "[^/\\]+$") or item.xmlFilename)))
            -- Build 105: unbekanntes Gewicht wird nicht mehr durchgewunken.
            elseif w ~= nil and w <= maxGewicht then
                table.insert(self.trafficVehicleList, {
                    filename  = item.xmlFilename,
                    category  = item.categoryName or "",
                    gewichtKg = w,
                    leistung  = nfGetItemPower(item),
                })
            elseif w == nil then
                table.insert(ohneGewicht, {
                    filename = item.xmlFilename,
                    category = item.categoryName or "",
                    leistung = nfGetItemPower(item),
                })
            end
        end
    end

    if #self.trafficVehicleList == 0 and #ohneGewicht > 0 then
        -- Sicherheitsnetz: liefert das Spiel fuer keinen Kleintraktor ein
        -- Gewicht, lieber nur nach Kategorie als gar kein Verkehr.
        for _, e in ipairs(ohneGewicht) do
            table.insert(self.trafficVehicleList, e)
        end
        print("NachbarFelder: [TRAFFIC] Warnung: kein Traktorgewicht lesbar - Liste nur nach Kategorie")
    end
    print(string.format("NachbarFelder: [TRAFFIC] Fahrzeugliste: %d Kleintraktoren bis %.0f t" ..
        " (%d ohne lesbares Gewicht, %d unter %d km/h aussortiert)", #self.trafficVehicleList,
        NF_KLEIN_MAX_VEH_WEIGHT_KG / 1000, #ohneGewicht, zuLangsam, NF_MIN_VEH_SPEED_KMH))
end

-- ============================================================
-- Anbaugeraete-Liste fuer Traffic-Convoy (gecacht)
-- Nur Feldgeraete ohne Transportfunktion (kein Fuellvolumen).
-- ============================================================
--- Sofort-Abweisung eines Verkehrsgespanns dem Anbaugeraet anrechnen (Build 119).
--- Gesperrt (nur fuer diese Session) wird ein Geraet erst nach 3 Abweisungen an
--- mindestens 2 verschiedenen Stellen - ein schlechter Standort allein sperrt nichts.
function NachbarFelderManager:merkeVerkehrGeraetAbweisung(filename, x, z)
    if filename == nil or x == nil or z == nil then return end
    local key = string.lower(tostring(filename))
    self.verkehrGeraetAbw = self.verkehrGeraetAbw or {}
    local e = self.verkehrGeraetAbw[key]
    if e == nil then
        e = { n = 0, orte = {} }
        self.verkehrGeraetAbw[key] = e
    end
    e.n = e.n + 1
    local neu = true
    for _, o in ipairs(e.orte) do
        if MathUtil.vector2Length(o[1] - x, o[2] - z) < 25 then
            neu = false
            break
        end
    end
    if neu then
        e.orte[#e.orte + 1] = { x, z }
    end
    if not e.gesperrt and e.n >= 3 and #e.orte >= 2 then
        e.gesperrt = true
        print(string.format("NachbarFelder: [TRAFFIC] Anbaugeraet [%s] %dx sofort abgewiesen an %d Stellen" ..
            " - fuer diese Session nicht mehr im Verkehr", tostring(filename), e.n, #e.orte))
    end
end

function NachbarFelderManager:getIstVerkehrGeraetGesperrt(filename)
    if filename == nil or self.verkehrGeraetAbw == nil then return false end
    local e = self.verkehrGeraetAbw[string.lower(tostring(filename))]
    return e ~= nil and e.gesperrt == true
end

--- Passt das Geraet zum Traktor? (Build 105)
--- Leistungsbedarf des Geraets hoechstens die Motorleistung des Traktors, und
--- das Geraet wiegt hoechstens halb so viel wie der Traktor. Fehlt ein Wert,
--- gilt die vorsichtige Variante (nur kleine, leichte Geraete).
function NachbarFelderManager:getPasstGeraetZuTraktor(traktor, geraet)
    if traktor == nil or geraet == nil then return false end
    local ps, bedarf = traktor.leistung, geraet.bedarf
    if ps ~= nil and bedarf ~= nil then
        if bedarf > ps then return false end
    elseif bedarf ~= nil then
        if bedarf > 80 then return false end
    elseif (geraet.gewichtKg or 0) > 1500 then
        return false
    end
    if traktor.gewichtKg ~= nil and geraet.gewichtKg ~= nil
       and geraet.gewichtKg > traktor.gewichtKg * 0.5 then
        return false
    end
    -- Build 159: Arbeitsbreite passend zur Traktorgroesse
    if geraet.breiteM ~= nil and geraet.breiteM > self:getMaxGeraeteBreite(traktor) then
        return false
    end
    return true
end

--- Groesste erlaubte Arbeitsbreite eines Geraets fuer diesen Traktor in m (Build 159).
function NachbarFelderManager:getMaxGeraeteBreite(traktor)
    local t = (traktor ~= nil and traktor.gewichtKg ~= nil) and (traktor.gewichtKg / 1000) or 0
    local maxB = t * NF_IMPL_BREITE_JE_TONNE
    if maxB < NF_IMPL_BREITE_MIN then maxB = NF_IMPL_BREITE_MIN end
    if maxB > NF_IMPL_BREITE_MAX then maxB = NF_IMPL_BREITE_MAX end
    return maxB
end

function NachbarFelderManager:buildTrafficTrailerList()
    self.trafficTrailerList   = {}  -- schwer: Pflug, Maehwerk → nur Großtraktoren (TRACTORSL)
    self.trafficImplListLight = {}  -- leicht: Rechen, Zinkenrotor → Mittelklasse (TRACTORSM)
    if (self.trafficTrailerSize or 2) == 0 then
        print("NachbarFelder: [TRAFFIC] Anbaugeraete: deaktiviert (Einstellung = 0)")
        return
    end
    if g_storeManager == nil then return end

    -- Brücken-sichere Kategorien (Transport-Zustand niedrig genug).
    -- CULTIVATORS/DRILLS ausgeschlossen: gefaltete Flügel ragen zu weit nach oben.
    local heavyCats = { PLOWS=true, MOWERS=true }   -- Großtraktor
    local lightCats = { TEDDERS=true, RAKES=true }  -- Mittelklasse

    -- Enge Karte: die schwere Liste bleibt leer. Pflug und Maehwerk gehen nur
    -- an Grosstraktoren (siehe Gespann-Auswahl weiter unten), und die faehrt
    -- bei engeMap niemand mehr - die Liste waere also ohnehin nie benutzt.
    -- Build 105: auf jeder Karte - es gibt keine Grosstraktoren mehr.
    heavyCats = {}

    local allItems = {}
    if g_storeManager ~= nil and g_storeManager.getItems ~= nil then allItems = g_storeManager:getItems() end

    local eng = (self.engeMap ~= false)

    for _, item in pairs(allItems) do
        -- Build 105: erst die Kategorie pruefen, dann Werte laden - das Laden
        -- liest pro Artikel eine XML-Datei.
        if item ~= nil and item.xmlFilename ~= nil and lightCats[item.categoryName]
           and not nfIsWaterVehicle(item.xmlFilename) then
            local w   = nfGetItemWeight(item)
            local cap = nfGetItemCapacity(item)
            if (cap == nil or cap == 0) and w ~= nil and w <= NF_ENG_MAX_IMPL_WEIGHT_KG then
                -- Build 159: Breite merken; unbekannte Breite nur bei leichten Geraeten
                local breite = nfGetItemWorkingWidth(item)
                if breite ~= nil or w <= NF_IMPL_OHNE_BREITE_MAX_KG then
                    table.insert(self.trafficImplListLight, {
                        filename  = item.xmlFilename,
                        gewichtKg = w,
                        bedarf    = nfGetItemNeededPower(item),
                        breiteM   = breite,
                    })
                end
            end
        end
    end

    print("NachbarFelder: [TRAFFIC] Anbaugeraete: " ..
        tostring(#self.trafficTrailerList) .. " schwer (Pflug/Maehwerk)" ..
        " + " .. tostring(#self.trafficImplListLight) .. " leicht (Rechen/Zinkenrotor)" ..
        (eng and "  [enge Karte: nur leichte bis "
                  .. tostring(NF_ENG_MAX_IMPL_WEIGHT_KG / 1000) .. " t]" or ""))
end

-- ============================================================
-- Tagesrhythmus (Build 68)
-- Die Verkehrs-Obergrenze folgt der Uhrzeit: Hochbetrieb morgens
-- und nachmittags, weniger mittags/abends, nachts schlaeft alles
-- (der Pool haelt die Fahrzeuge - kein Loeschen/Spawnen noetig).
-- dayRhythm=false in der Server-Konfig schaltet das ab.
-- ============================================================
function NachbarFelderManager:countActivePatrols()
    local n = 0
    for _, k in pairs(self.vehicleType) do
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.isPatrol
           and k.NachbarFelderWorker.status ~= 100 and k.NachbarFelderWorker.status ~= 9999 then
            n = n + 1
        end
    end
    return n
end

--- Fahrzeug-Zustand fuer die Log-Diagnose (Build 100).
---
--- Offene Frage aus dem Log vom 12.09.: um 15:16:08 startet ein GOTO ohne
--- Fehlermeldung, das Fahrzeug bewegt sich danach keinen Meter (Stufe 1/2/3).
--- Weder Position noch Ziel erklaeren das. Diese Zeile zeigt, woran es liegt:
--- `getIsAIReadyToDrive`/`getIsAIPreparingToDrive` (AIDrivable.lua:620/636),
--- Agent, Motor, Sprit, Schaden. `agentInfo.isValid` ist die Bedingung, ohne
--- die `getCanStartAIVehicle()` grundsaetzlich false liefert (AIDrivable:1040).
--- @return string kompakte Zustandsbeschreibung
function NachbarFelderManager:getVehicleAiDiag(veh)
    if veh == nil then return "kein Fahrzeug" end
    local t = {}
    local function add(txt) t[#t + 1] = txt end

    if veh.getLastSpeed ~= nil then
        add(string.format("%.1f km/h", veh:getLastSpeed()))
    end
    if veh.getIsMotorStarted ~= nil then
        add("Motor " .. (veh:getIsMotorStarted() and "an" or "AUS"))
    end
    if veh.getIsAIReadyToDrive ~= nil then
        add("fahrbereit " .. tostring(veh:getIsAIReadyToDrive()))
    end
    if veh.getIsAIPreparingToDrive ~= nil then
        add("bereitet vor " .. tostring(veh:getIsAIPreparingToDrive()))
    end
    local spec = veh.spec_aiDrivable
    if spec ~= nil then
        add("Agent " .. (spec.agentId ~= nil and "ja" or "NEIN"))
        if spec.agentInfo ~= nil then
            add("AgentInfo " .. tostring(spec.agentInfo.isValid))
        end
    end
    if veh.getCanStartAIVehicle ~= nil then
        add("startbar " .. tostring(veh:getCanStartAIVehicle()))
    end
    if veh.getFillUnits ~= nil then
        for _, fu in ipairs(veh:getFillUnits()) do
            local ft = fu.fillType
            if ft ~= nil and FillType ~= nil
               and (ft == FillType.DIESEL or ft == FillType.ELECTRICCHARGE
                    or ft == FillType.METHANE) then
                local cap = fu.capacity or 0
                if cap > 0 then
                    add(string.format("Sprit %.0f%%", (fu.fillLevel or 0) / cap * 100))
                end
            end
        end
    end
    if veh.getDamageAmount ~= nil then
        add(string.format("Schaden %.0f%%", (veh:getDamageAmount() or 0) * 100))
    end
    -- Build 162: ClassUtil.getClassNameByObject gibt es zur Laufzeit nicht (Log 01.10.
    -- 19:15: "attempt to call a nil value" - bis Build 157 war das still abgefangen)
    local job = veh.getJob ~= nil and veh:getJob() or nil
    local jobName = "keiner"
    if job ~= nil then
        jobName = "aktiv"
        if ClassUtil ~= nil and ClassUtil.getClassNameByObject ~= nil then
            jobName = tostring(ClassUtil.getClassNameByObject(job))
        elseif job.name ~= nil then
            jobName = tostring(job.name)
        end
    end
    add("Job " .. jobName)

    return table.concat(t, " | ")
end

function NachbarFelderManager:getEffectiveTrafficLimit()
    local limit = self.trafficLimit or 4
    if self.dayRhythm == false then return limit end
    local hour = 12
    if g_currentMission ~= nil and g_currentMission.environment ~= nil
       and g_currentMission.environment.currentHour ~= nil then
        hour = g_currentMission.environment.currentHour
    end
    local f
    if hour >= 22 or hour < 5 then
        f = 0        -- Nacht: alle schlafen
    elseif hour < 7 then
        f = 0.5      -- fruehe Morgenstunden: langsamer Start
    elseif hour < 11 then
        f = 1.0      -- Vormittag: Hochbetrieb
    elseif hour < 13 then
        f = 0.6      -- Mittag: ruhiger
    elseif hour < 18 then
        f = 1.0      -- Nachmittag: Hochbetrieb
    else
        f = 0.5      -- Abend (18-22): ausklingen
    end
    return math.floor(limit * f + 0.5)
end

-- ============================================================
-- Fahrzeug-Pool (Build 65)
-- Spawnen ist der teure Moment (I3D-Laden, Physik-Erzeugung,
-- MP-Sync des neuen Objekts = der Server-Ruckler). Deshalb werden
-- Patrol-Fahrzeuge am Lebensende nicht mehr geloescht, sondern
-- "schlafen gelegt": AI-Job stoppen, an einem freien Wegpunkt
-- parken (laengs zur Strasse, Motor aus) und beim naechsten
-- Spawn-Tick wiederverwenden. Nach der Aufwaermphase entstehen
-- so keine Spawn-Ruckler mehr. poolSize=0 in der Server-Konfig
-- schaltet den Pool ab (Verhalten wie vor Build 65).
-- ============================================================

-- Liegt an Position (x,z) ein schlafendes Pool-Fahrzeug? (12m-Radius)
function NachbarFelderManager:isWpPosOccupied(x, z)
    if self.trafficPool == nil or x == nil or z == nil then return false end
    for _, p in ipairs(self.trafficPool) do
        if p.restX ~= nil and MathUtil.vector2Length(x - p.restX, z - p.restZ) < 12 then
            return true
        end
    end
    return false
end

-- Steht IRGENDEIN Fahrzeug (auch Spieler-Fahrzeuge!) im Umkreis um (x,z)?
-- Pflicht-Check vor jedem Teleport an einen WP (Build 73): Teleport auf
-- einen belegten Platz erzeugt eine Physik-Explosion (senkrecht stehende
-- Fahrzeuge). excludeVeh = eigenes Gespann wird ignoriert.
--- Festsitzendes Fahrzeug auf einen freien Punkt der KI-Strasse setzen (Build 107).
--- Sucht zuerst ab 10 m Abstand (raus aus der Engstelle), bei belegtem Platz
--- noch einmal ab 30 m. Nur fuer Fahrzeuge ohne laufenden Auftrag aufrufen.
--- @return boolean true, wenn versetzt
function NachbarFelderManager:rettungAufStrasse(veh, x, z)
    if veh == nil or self.getNearestRoadPoint == nil then return false end
    local rx, rz, rry, rdist = self:getNearestRoadPoint(x, z, 150, 10)
    if rx ~= nil and self:isSpotBlockedByAnyVehicle(rx, rz, 10, veh) then
        rx, rz, rry, rdist = self:getNearestRoadPoint(x, z, 150, 30)
        if rx ~= nil and self:isSpotBlockedByAnyVehicle(rx, rz, 10, veh) then
            rx = nil
        end
    end
    if rx == nil then return false end
    local ok = g_currentMission ~= nil and g_currentMission.teleportVehicle ~= nil
    if ok then
        g_currentMission:teleportVehicle(veh, rx, rz, rry or 0)
        print(string.format("NachbarFelder: [TRAFFIC] steckte fest - %.0f m weiter auf die KI-Strasse gesetzt",
            rdist or 0))
    end
    return ok
end

--- Steht ein anderes Nachbar-Fahrzeug in der Naehe ebenfalls still? (Build 166)
--- Log 04.10.: series6M und arion550 standen 14 m auseinander gleichzeitig 30 s fest,
--- bekamen beide neue Ziele und standen eine Minute spaeter 4 m auseinander wieder.
--- Zwei KI-Fahrzeuge warten aufeinander - das loest sich nicht von selbst.
--- @return table|nil Eintrag aus vehicleType des stehenden Nachbarn
function NachbarFelderManager:getStehenderNachbar(eigenerEintrag, x, z, radius, fx, fz)
    -- Build 166: Screenshot 04.10.: der Claas stand quer zum Wenden, der Gegenverkehr
    -- wartete weit ueber 30 m entfernt. Darum bis 100 m - ab 20 m aber nur, wenn der
    -- Nachbar grob vor dem Fahrzeug steht (innerhalb 60 Grad zur Fahrtrichtung fx/fz).
    for _, k2 in pairs(self.vehicleType or {}) do
        local w2 = k2 ~= eigenerEintrag and k2.NachbarFelderWorker or nil
        if w2 ~= nil and w2.isPatrol and w2.status == 1 and w2.patrolWdLastX ~= nil
           and g_time - (w2.patrolWdSince or g_time) > NachbarFelderManager.BEGEGNUNG_STEHT_MS then
            local v2 = w2.vehiclesToLoad and w2.vehiclesToLoad[1]
            if self:getIsVehicleAlive(v2) then
                local x2, _, z2 = getWorldTranslation(v2.rootNode)
                local d = MathUtil.vector2Length(x2 - x, z2 - z)
                if d <= radius then
                    local vorMir = true
                    if d > NachbarFelderManager.BEGEGNUNG_NAH and fx ~= nil and fz ~= nil and d > 0.01 then
                        vorMir = ((x2 - x) * fx + (z2 - z) * fz) / d > 0.5
                    end
                    if vorMir then
                        return k2
                    end
                end
            end
        end
    end
    return nil
end

--- Begegnung zweier stehender Nachbar-Fahrzeuge aufloesen (Build 166).
--- Dieses Fahrzeug (dessen Waechter zuerst ausloest) weicht aus: Auftrag stoppen, neues
--- Ziel, und in Richtung des neuen Ziels mind. 25 m weiter auf die KI-Strasse setzen.
--- Der Nachbar behaelt sein Ziel und bekommt neue 30 s, um durch die frei gewordene
--- Stelle zu fahren. Ohne freien Ausweichplatz passiert nichts (normaler Ablauf).
--- @return boolean true, wenn ausgewichen
function NachbarFelderManager:loeseBegegnung(eintrag, veh, x, z)
    local w = eintrag ~= nil and eintrag.NachbarFelderWorker or nil
    if w == nil or w.waypoints == nil or #w.waypoints < 2 or self.getRoadPointInRichtung == nil then
        return false
    end
    if (w.begegnungen or 0) >= NachbarFelderManager.BEGEGNUNG_MAX then return false end
    local fx, fz = nil, nil
    if veh.rootNode ~= nil and localDirectionToWorld ~= nil then
        local dx, _, dz = localDirectionToWorld(veh.rootNode, 0, 0, 1)
        local l = math.sqrt(dx * dx + dz * dz)
        if l > 0.001 then fx, fz = dx / l, dz / l end
    end
    local partner = self:getStehenderNachbar(eintrag, x, z, NachbarFelderManager.BEGEGNUNG_RADIUS, fx, fz)
    if partner == nil then return false end

    local curDest = w.patrolDestIdx or 1
    local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest
    local tx, tz = w.waypoints[newDest][1], w.waypoints[newDest][2]
    local rx, rz, rry, rdist = self:getRoadPointInRichtung(x, z, 150, 25, tx - x, tz - z)
    if rx == nil or self:isSpotBlockedByAnyVehicle(rx, rz, 8, veh) then return false end
    if g_currentMission == nil or g_currentMission.teleportVehicle == nil then return false end

    self:stopAIJobSafely(veh)
    w.fieldGotoStartedAt = nil
    w.patrolWdLastX = nil
    g_currentMission:teleportVehicle(veh, rx, rz, rry or 0)
    w.roadSnapped   = true
    w.begegnungen   = (w.begegnungen or 0) + 1
    w.waypointIdx   = curDest
    w.patrolDestIdx = newDest
    w.patrolTargetX = tx
    w.patrolTargetZ = tz
    w.parkSecs      = self:scaleParkSecs(math.random(20, 60))
    w.status        = 1
    w.needTimer     = true

    -- Nachbar: Uhr neu starten, er soll jetzt durchfahren statt selbst auszuweichen
    local w2 = partner.NachbarFelderWorker
    w2.patrolWdSince = g_time
    local v2 = w2.vehiclesToLoad and w2.vehiclesToLoad[1]
    local name2 = v2 ~= nil and (string.match(v2.configFileName or "", "[^/\\]+$") or "?") or "?"
    print(string.format("NachbarFelder: [TRAFFIC] Begegnung mit %s - weicht %.0f m auf die KI-Strasse aus," ..
        " neues Ziel WP%s (patrolId=%s)", name2, rdist or 0, tostring(newDest), tostring(w.fieldId)))
    return true
end

--- Naechstes Fahrzeug zu (x, z), das nicht zum eigenen Gespann gehoert (Build 107).
--- @return number|nil Abstand in m, string|nil Dateiname des Fahrzeugs
function NachbarFelderManager:getNaechstesFremdfahrzeug(x, z, eigenes)
    local bestD, bestName = nil, nil
    local function schritt()
        local list = (g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles)
                     or g_currentMission.vehicles
        for _, v in pairs(list or {}) do
            if v ~= nil and v ~= eigenes and v.isDeleted ~= true
               and v.rootNode ~= nil and v.rootNode ~= 0 then
                local root = v
                if v.getRootVehicle ~= nil then
                    if v.getRootVehicle ~= nil then
                        local r = v:getRootVehicle()
                        if r ~= nil then root = r end
                    end
                end
                if root ~= eigenes then
                    local vx, _, vz = getWorldTranslation(v.rootNode)
                    local d = MathUtil.vector2Length(vx - x, vz - z)
                    if bestD == nil or d < bestD then
                        bestD = d
                        local f = v.configFileName or ""
                        bestName = string.match(f, "[^/\\]+$") or f
                    end
                end
            end
        end
    end
    schritt()
    return bestD, bestName
end

function NachbarFelderManager:isSpotBlockedByAnyVehicle(x, z, radius, excludeVeh)
    if x == nil or z == nil then return false end
    local blocked = false
    local function schritt()
        local list = nil
        if g_currentMission ~= nil then
            if g_currentMission.vehicleSystem ~= nil
               and g_currentMission.vehicleSystem.vehicles ~= nil then
                list = g_currentMission.vehicleSystem.vehicles
            elseif g_currentMission.vehicles ~= nil then
                list = g_currentMission.vehicles
            end
        end
        if list == nil then return end
        for _, veh in pairs(list) do
            if veh ~= nil and veh.isDeleted ~= true
               and veh.rootNode ~= nil and veh.rootNode ~= 0 then
                local isOwn = false
                if excludeVeh ~= nil then
                    if veh == excludeVeh then
                        isOwn = true
                    elseif veh.getRootVehicle ~= nil then
                        if veh.getRootVehicle ~= nil and veh:getRootVehicle() == excludeVeh then
                            isOwn = true
                        end
                    end
                end
                if not isOwn then
                    local vx, _, vz = getWorldTranslation(veh.rootNode)
                    if MathUtil.vector2Length(x - vx, z - vz) < (radius or 10) then
                        blocked = true
                        return
                    end
                end
            end
        end
    end
    schritt()
    return blocked
end

-- Freien WP fuer einen Teleport finden: bevorzugt preferIdx, sonst bis zu
-- 6 Alternativen. Frei = kein Pool-Schlaefer UND kein anderes Fahrzeug.
-- nil = nichts frei (Aufrufer soll den Teleport weglassen).
function NachbarFelderManager:findFreeSpawnWp(wps, preferIdx, excludeVeh)
    if wps == nil or #wps == 0 then return nil end
    local function isFree(i)
        local wp = i ~= nil and wps[i] or nil
        if wp == nil then return false end
        local x = wp.x or wp[1]
        local z = wp.z or wp[2]
        return not self:isWpPosOccupied(x, z)
           and not self:isSpotBlockedByAnyVehicle(x, z, 10, excludeVeh)
    end
    if isFree(preferIdx) then return preferIdx end
    for _ = 1, 6 do
        local i = self:pickPatrolWaypoint(wps, preferIdx)
        if isFree(i) then return i end
    end
    return nil
end

-- Patrol-Eintrag schlafen legen: AI-Jobs stoppen, parken, in den Pool
-- aufnehmen und den aktiven Eintrag entfernen. Liefert true wenn das
-- Fahrzeug gepoolt wurde; false = Aufrufer soll normal loeschen.
-- Der frueher unterschiedene Parameter inPlace ist seit Build 93 wirkungslos:
-- Fahrzeuge bleiben immer dort stehen, wo sie sind (siehe unten). Er wird nur
-- noch fuer den Text der Log-Meldung ausgewertet.
function NachbarFelderManager:sleepPatrolEntry(entry, inPlace)
    if entry == nil or entry.NachbarFelderWorker == nil then return false end
    local w = entry.NachbarFelderWorker
    if not w.isPatrol then return false end
    if self.isShuttingDown then return false end
    if (self.poolSize or 0) <= 0 then return false end
    if w.noPool then return false end
    self.trafficPool = self.trafficPool or {}
    -- Effektiver Pool-Deckel = mindestens trafficLimit (Build 74): sonst
    -- werden bei trafficLimit > poolSize jede Nacht Fahrzeuge geloescht
    -- und morgens neu gespawnt - genau die Ruckler, die der Pool
    -- verhindern soll.
    local cap = math.max(self.poolSize or 0, self.trafficLimit or 0)
    if #self.trafficPool >= cap then return false end

    -- Nur lebende Fahrzeuge poolen; ohne Traktor kein Pool-Eintrag
    local vehs = {}
    for _, veh in ipairs(entry.vehicleType or {}) do
        if self:getIsVehicleAlive(veh) then table.insert(vehs, veh) end
    end
    local tractor = vehs[1]
    if tractor == nil then return false end

    -- Status VOR dem Job-Stopp auf 9999 setzen: stopAIJobSafely feuert
    -- synchron onAIJobFinished, dessen Status-1/60-Logik sonst waehrend
    -- des Einschlafens neu zielt oder teleportiert (gleiches Muster wie
    -- in deleteAllVehicles).
    w.status = 9999

    -- AI-Jobs stoppen: ein schlafendes Fahrzeug darf keinen Job im
    -- aiSystem behalten (sonst Frame-Fehler wie bei geloeschten Vehicles)
    for _, veh in ipairs(vehs) do
        self:stopAIJobSafely(veh)
        self:meldeBeimSpielverkehrAb(veh)   -- Build 152: schlafend wie ein abgestelltes Fahrzeug
    end

    -- Build 103: nicht zu mehreren am selben Fleck einschlafen. Am 12.09.
    -- standen vier Fahrzeuge in Reihe an derselben Sackgasse: jedes strandete
    -- dort, schlief an Ort und Stelle ein (Build 93) und wurde beim Aufwecken
    -- sofort wieder abgewiesen. Ist der Platz belegt, kommt das Fahrzeug
    -- vorher auf einen freien Strassenpunkt 25-150 m weiter.
    local function schritt()
        if tractor.rootNode == nil or self.getNearestRoadPoint == nil then return end
        local vx, _, vz = getWorldTranslation(tractor.rootNode)
        if not self:isSpotBlockedByAnyVehicle(vx, vz, 25, tractor) then return end
        local rx, rz, rry = self:getNearestRoadPoint(vx, vz, 150, 25)
        if rx == nil or self:isSpotBlockedByAnyVehicle(rx, rz, 12, tractor) then
            print("NachbarFelder: [TRAFFIC] Schlafplatz belegt, kein freier Strassenplatz" ..
                " in der Naehe - Fahrzeug bleibt stehen")
            return
        end
        g_currentMission:teleportVehicle(tractor, rx, rz, rry or 0)
        print(string.format("NachbarFelder: [TRAFFIC] Schlafplatz war belegt - Fahrzeug %.0f m" ..
            " weiter auf die KI-Strasse gestellt", MathUtil.vector2Length(rx - vx, rz - vz)))
    end
    schritt()

    -- Build 93: Fahrzeuge schlafen IMMER an Ort und Stelle.
    --
    -- Frueher wurde fuer inPlace=false ein freier Wegpunkt gesucht und das
    -- Fahrzeug dorthin teleportiert - mit wp.ry, also der Blickrichtung des
    -- Admins beim Setzen des Punktes. Das war die letzte Stelle, die ein
    -- Fahrzeug quer zur Fahrbahn abstellte. Schlimmer noch: Fand sich kein
    -- freier WP, lieferte die Funktion false, das Fahrzeug wurde geloescht
    -- und spaeter neu geladen - und jedes Laden eines Fahrzeugmodells kostet
    -- den Server auf HDD mehrere hundert Millisekunden Stillstand, was alle
    -- Spieler zurueckzieht (belegt: arion400.i3d 690 ms).
    --
    -- Dort stehen zu bleiben, wo die KI angehalten hat, ist in beidem besser:
    -- die Ausrichtung stimmt, und das Fahrzeug bleibt im Pool statt neu
    -- geladen zu werden.
    local restX, restZ
    local x, _, z = getWorldTranslation(tractor.rootNode)
    restX, restZ = x, z
    if restX == nil then return false end

    -- Motor aus: schlafende Fahrzeuge stehen still am Strassenrand
    if tractor.stopMotor ~= nil and tractor.getIsMotorStarted ~= nil
       and tractor:getIsMotorStarted() then
        tractor:stopMotor()
    end

    table.insert(self.trafficPool, {
        vehicles  = vehs,
        restX     = restX,
        restZ     = restZ,
        sleptAt   = g_time,
    })

    local fname = tractor.configFileName or ""
    local base  = string.match(fname, "[^/\\]+$") or fname
    print("NachbarFelder: [POOL] " .. base .. " schlaeft" ..
        (inPlace and " an Ort und Stelle (Hops fertig)" or " an Ort und Stelle") ..
        " - Pool: " .. tostring(#self.trafficPool) .. "/" .. tostring(self.poolSize))

    -- Aktiven Eintrag entfernen (wie deleteMission fuer Patrol)
    self.vehicleType[w.fieldId] = nil
    self.counter = self.counter - 1
    return true
end

-- Schlafendes Pool-Fahrzeug aufwecken: neue Route/Hops zuweisen und vom
-- aktuellen Standort losfahren lassen. Kein Spawn, kein I3D-Laden ->
-- kein Ruckler. Liefert true wenn ein Fahrzeug geweckt wurde.
function NachbarFelderManager:wakePooledVehicle()
    if self.trafficPool == nil or #self.trafficPool == 0 then return false end
    -- Build 136: alle Fahrziele zaehlen, nicht nur eigene Wegpunkte. Mit zielQuelle=strassen
    -- gibt es auch ohne einen einzigen eigenen Punkt genug Ziele - Bergisch Land 19.09.:
    -- 0 eigene + 53 Strassenziele, der Pool wurde nie geweckt, die Schlaefer blockierten
    -- die Strasse am Shop, und jedes weitere Fahrzeug wurde frisch geladen.
    if #(self:getPatrolWaypointList() or {}) < 3 then return false end

    -- Aeltesten Eintrag zuerst (gleichmaessige Nutzung); tote Eintraege
    -- (Fahrzeug von extern geloescht/verkauft) werden ausgesondert.
    local poolEntry = nil
    while #self.trafficPool > 0 do
        local cand  = table.remove(self.trafficPool, 1)
        local alive = cand.vehicles ~= nil and #cand.vehicles >= 1
        if alive then
            for _, veh in ipairs(cand.vehicles) do
                if not self:getIsVehicleAlive(veh) then alive = false break end
            end
        end
        if alive then
            poolEntry = cand
            break
        else
            print("NachbarFelder: [POOL] Eintrag verworfen (Fahrzeug existiert nicht mehr)")
        end
    end
    if poolEntry == nil then return false end

    local vehs    = poolEntry.vehicles
    local tractor = vehs[1]

    -- Route wie in generateTraffic aufbauen (aktueller Stand)
    local waypoints = {}
    for _, wp in ipairs(self:getPatrolWaypointList()) do
        table.insert(waypoints, { wp[1], wp[2], wp[3], wp[4] })
    end
    local destIdx = self:pickPatrolWaypoint(waypoints, nil) or math.random(#waypoints)

    self.patrolCounter = self.patrolCounter - 1
    local patrolId     = self.patrolCounter
    local proxyMission = { type = { name = "trafficDrive" } }

    local worker = NachbarFelderWorker.new(vehs, proxyMission, 1, patrolId)
    worker.isPatrol      = true
    worker.waypoints     = waypoints
    -- Build 107: Parkpunkt-Anzahl dieser Liste merken. Die Liste ist eine
    -- Kopie vom Spawn; werden danach Parkpunkte gesetzt, verschieben sich die
    -- Nummern nur in NEUEN Listen - #userTrafficWaypoints passt dann nicht mehr.
    worker.anzahlParkpunkte = math.min(#(self.userTrafficWaypoints or {}), #waypoints)
    worker.patrolDestIdx = destIdx
    worker.patrolTargetX = waypoints[destIdx][1]
    worker.patrolTargetZ = waypoints[destIdx][2]
    worker.parkSecs      = nfCatParkSecs((waypoints[destIdx] or {})[4] or 0)
    worker.hopsLeft      = math.random(self.patrolHopsMin or 10,
                                       self.patrolHopsMax or 20)
    -- Standort-WP bestimmen (fuer Fehler-Bookkeeping + Ziel!=Standort)
    local sx, sz = poolEntry.restX, poolEntry.restZ
    local x, _, z = getWorldTranslation(tractor.rootNode)
    sx, sz = x, z
    local nearestIdx = nil
    if sx ~= nil then
        local minD2 = math.huge
        for i, wp in ipairs(waypoints) do
            local d2 = (wp[1] - sx)^2 + (wp[2] - sz)^2
            if d2 < minD2 then minD2 = d2; nearestIdx = i end
        end
    end
    worker.waypointIdx = nearestIdx or 1
    if nearestIdx ~= nil and worker.patrolDestIdx == nearestIdx and #waypoints >= 2 then
        local nd = self:pickPatrolWaypoint(waypoints, nearestIdx) or worker.patrolDestIdx
        worker.patrolDestIdx = nd
        worker.patrolTargetX = waypoints[nd][1]
        worker.patrolTargetZ = waypoints[nd][2]
        worker.parkSecs      = nfCatParkSecs((waypoints[nd] or {})[4] or 0)
    end

    -- Getrennte Fahrzeuglisten fuer Eintrag und Worker (wie nach Spawn)
    local vt = {}
    for i, v in ipairs(vehs) do vt[i] = v end

    self.vehicleType[patrolId] = {
        vehiclesToLoad      = vehs,
        saveVehicleToLoad   = vehs,
        mission             = proxyMission,
        status              = 1,
        fieldId             = patrolId,
        vehicleType         = vt,
        NachbarFelderWorker = worker,
    }

    -- 1.5 = kurze Settle-Zeit, dann GOTO vom Standort aus (update())
    worker.status    = 1.5
    worker.needTimer = true

    self.countWorkers = self.countWorkers + 1

    local fname = tractor.configFileName or ""
    local base  = string.match(fname, "[^/\\]+$") or fname
    print("NachbarFelder: [POOL] " .. base .. " aufgeweckt -> Ziel WP" ..
        tostring(worker.patrolDestIdx) .. " | " .. tostring(worker.hopsLeft) ..
        " Hops | Pool: " .. tostring(#self.trafficPool) .. "/" .. tostring(self.poolSize))
    return true
end

-- Pool leeren: alle schlafenden Fahrzeuge wirklich loeschen.
-- Nur fuer explizite Admin-Aktionen (Taste/Konsole/Client-Event).
function NachbarFelderManager:clearTrafficPool()
    if self.isShuttingDown then return end
    if self.trafficPool == nil then return end
    local n = 0
    for _, p in ipairs(self.trafficPool) do
        for _, veh in ipairs(p.vehicles or {}) do
            if self:getIsVehicleAlive(veh) then
                self:stopAIJobSafely(veh)
                veh:delete()
                n = n + 1
            end
        end
    end
    self.trafficPool = {}
    if n > 0 then
        print("NachbarFelder: [POOL] geleert - " .. tostring(n) .. " Fahrzeug(e) geloescht")
    end
end

-- Admin-Vollreinigung: aktive Eintraege UND Pool entfernen.
-- deleteAllVehicles legt Patrols zunaechst in den Pool (Build 65),
-- deshalb wird der Pool DANACH geleert.
function NachbarFelderManager:deleteAllVehiclesAndPool(quit)
    -- Als Tasten-/Client-Aktion nur fuer Admins (Build 75). Auf dem Server
    -- selbst (Konsole, Events nach Admin-Pruefung) laeuft es immer durch.
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return
    end
    self:deleteAllVehicles(quit)
    self:clearTrafficPool()
end

function NachbarFelderManager:generateTraffic(forcedVehicleXML, overrideSpawnWpIdx)
    if not g_currentMission:getIsServer() then return false end
    if self.trafficPaused then return false end

    -- Traffic-Limit: max. gleichzeitig aktive Patrol-Fahrzeuge.
    -- Seit Build 68 uhrzeitabhaengig (Tagesrhythmus): nachts 0,
    -- mittags/abends reduziert, vor-/nachmittags volles Limit.
    local activePatrol = self:countActivePatrols()
    local effLimit     = self:getEffectiveTrafficLimit()
    if activePatrol >= effLimit then return false end

    -- Farm-ID sicherstellen (muss vor loadVehicles und startJob gesetzt sein)
    self:getEffectiveFarmId()

    -- Fahrzeug-Pool (Build 65): schlafendes Fahrzeug aufwecken statt neu
    -- spawnen - kein I3D-Laden, kein Ruckler. Der Shop-Spawn-Blocker ist
    -- dafuer irrelevant (das Fahrzeug startet von seinem Schlafplatz).
    --
    -- Build 100: aber erst, wenn die Flotte gross genug ist. Vorher wurde bei
    -- JEDEM Spawn-Takt ein Pool-Fahrzeug geweckt, nie ein weiteres gebaut - mit
    -- zwei Fahrzeugen, die immer wieder im Pool landeten, blieb es dauerhaft bei
    -- zwei, obwohl das Limit mehr erlaubte (Log 12.09., "es fahren nur 2").
    local flotte = activePatrol + #(self.trafficPool or {})
    if forcedVehicleXML == nil and flotte >= effLimit and self:wakePooledVehicle() then
        return true
    end

    -- Build 132: Mit Admin-Spawnpunkten nur spawnen, wenn einer frei ist - lieber
    -- einen Takt warten als im Ort laden. Der Shop-Blocker entfaellt dann (der
    -- Shop ist gar nicht mehr der Ladeplatz).
    local mitSpawnpunkten = self:getHatSpawnpunkte()
    if mitSpawnpunkten and self:waehleSpawnpunkt(true) == nil then
        return false
    end

    -- Spawn-Blocker: läuft schon ein Fahrzeug am Shop?
    if not mitSpawnpunkten then
        local tx, tz = self:getShopPosition()
        for _, k in pairs(self.vehicleType) do
            local ws = k.NachbarFelderWorker and k.NachbarFelderWorker.status or 0
            if ws ~= 9999 and ws ~= 100 and ws ~= 60 then
                for _, veh in ipairs(k.vehicleType) do
                    if self:getIsVehicleAlive(veh) then
                        local x, _, z = getWorldTranslation(veh.rootNode)
                        if MathUtil.vector2Length(x - tx, z - tz) < 50 then
                            return false
                        end
                    end
                end
            end
        end
    end

    -- Fahrzeug aus Store-Liste (einmalig gecacht, enthält alle motorisierten Fahrzeuge).
    if self.trafficVehicleList == nil then self:buildTrafficVehicleList() end
    if #self.trafficVehicleList == 0 then return false end
    local vehInfo
    if forcedVehicleXML ~= nil then
        -- Stammfahrzeug: erzwungenes XML (Wiederkehrender Nachbar)
        -- Build 164: steht das Stammfahrzeug nicht mehr in der Liste (z. B. zu langsam),
        -- kommt ein anderes Fahrzeug aus der Liste
        vehInfo = nil
        for _, v in ipairs(self.trafficVehicleList) do
            if v.filename == forcedVehicleXML then vehInfo = v; break end
        end
        if vehInfo == nil then
            vehInfo = self.trafficVehicleList[math.random(1, #self.trafficVehicleList)]
        end
    else
        vehInfo = self.trafficVehicleList[math.random(1, #self.trafficVehicleList)]
    end

    -- Gespann-Quote (Build 69): trailerChance (Server-Konfig, 0-100%)
    -- wird als LAUFENDE QUOTE erzwungen statt nur gewuerfelt. Liegt der
    -- bisherige Gespann-Anteil unter dem Ziel, bekommt dieser Traktor ein
    -- Geraet (sofern seine Groessenklasse eines darf). So stimmt der
    -- Anteil auch bei wenigen Spawns - wichtig, weil der Pool (Build 65)
    -- die Mischung der Aufwaermphase dauerhaft einfriert.
    local cat = vehInfo.category or ""
    local isTractor = cat:find("TRACTORS") ~= nil
    local vehList = { vehInfo }
    local trailerAdded = false
    local trailerSizeOk = (self.trafficTrailerSize or 2) > 0
    local wantImplement = false
    if isTractor and trailerSizeOk and (self.trailerChance or 40) > 0 then
        local total = (self.gespannSpawns or 0) + (self.soloSpawns or 0)
        local share = 0
        if total > 0 then
            share = (self.gespannSpawns or 0) / total
        end
        wantImplement = share < (self.trailerChance or 40) / 100
    end
    if wantImplement then
        if self.trafficTrailerList == nil then self:buildTrafficTrailerList() end
        -- Geraet nach Traktorgroesse waehlen (verhindert Kleintrak + Riesen-Geraet):
        -- TRACTORSS → kein Geraet
        -- TRACTORSM → leicht (Rechen, Zinkenrotor)
        -- TRACTORSL/andere Großklassen → schwer (Pflug, Maehwerk)
        -- Build 105: Es gibt nur noch Kleintraktoren. Ein Geraet kommt nur dran,
        -- wenn es zum Traktor passt (getPasstGeraetZuTraktor). Passt nichts,
        -- faehrt der Traktor solo.
        local implList = nil
        local passend = {}
        for _, impl in ipairs(self.trafficImplListLight or {}) do
            if self:getPasstGeraetZuTraktor(vehInfo, impl)
               and not self:getIstVerkehrGeraetGesperrt(impl.filename) then   -- Build 119
                passend[#passend + 1] = impl
            end
        end
        if #passend > 0 then implList = passend end
        if implList ~= nil then
            local trailerInfo = implList[math.random(#implList)]
            table.insert(vehList, trailerInfo)
            trailerAdded = true
        end
    end

    local proxyMission = { type = { name = "trafficDrive" } }

    -- Route aufbauen: User-Wegpunkte (in Reihenfolge) oder zufällige Positionen als Fallback.
    -- Der Navmesh sorgt in beiden Fällen für straßenbasierte Navigation.
    local waypoints = {}
    local zielListe = self:getPatrolWaypointList()
    if #zielListe > 0 then
        for _, wp in ipairs(zielListe) do
            table.insert(waypoints, { wp[1], wp[2], wp[3], wp[4] })
        end
    else
        for _ = 1, 3 do
            local wx, wz = self:getTrafficWaypoint()
            if wx ~= nil then table.insert(waypoints, { wx, wz, 0, 0 }) end
        end
    end
    -- Mindestens 3 WPs, sonst gibt es keine sinnvollen Routen (Fahrzeuge
    -- stauen sich / Ziele sofort gesperrt) - z.B. während der User gerade
    -- ein neues WP-Netz aufnimmt.
    if #waypoints < 3 then
        if not self.wpFewWarned then
            self.wpFewWarned = true
            print("NachbarFelder: [TRAFFIC] Zu wenige Wegpunkte (" ..
                tostring(#waypoints) .. "/3) - kein Traffic-Spawn bis mehr WPs gesetzt sind.")
        end
        return false
    end
    self.wpFewWarned = nil

    -- Startpunkt: wird in Status 1 dynamisch als nächster WP zum Shop berechnet.
    -- Ziel: zufällig aus allen WPs (gesperrte vermieden). Nach Hops Heimfahrt.
    local nWps    = #waypoints
    -- Build 106: erstes Ziel in Hop-Reichweite des Shops
    local shopRefX, shopRefZ = self:getShopPosition()
    local destIdx = self:pickPatrolWaypoint(waypoints, nil, shopRefX, shopRefZ) or math.random(nWps)

    -- Pseudo-Key: negative ID
    self.patrolCounter = self.patrolCounter - 1
    local patrolId = self.patrolCounter

    local worker = NachbarFelderWorker.new({}, proxyMission, 0, patrolId)
    worker.isPatrol      = true
    worker.waypoints     = waypoints
    -- Build 107: Parkpunkt-Anzahl dieser Liste merken. Die Liste ist eine
    -- Kopie vom Spawn; werden danach Parkpunkte gesetzt, verschieben sich die
    -- Nummern nur in NEUEN Listen - #userTrafficWaypoints passt dann nicht mehr.
    worker.anzahlParkpunkte = math.min(#(self.userTrafficWaypoints or {}), #waypoints)
    local firstDestCat   = (waypoints[destIdx] or {})[4] or 0
    worker.waypointIdx   = 1                        -- Platzhalter; wird in onSpawnedVehicle überschrieben
    worker.patrolDestIdx = destIdx                  -- erstes Fahrziel (zufällig)
    worker.patrolTargetX = waypoints[destIdx][1]
    worker.patrolTargetZ = waypoints[destIdx][2]
    worker.parkSecs      = nfCatParkSecs(firstDestCat)
    worker.firstStart         = true               -- Trigger: Sofort-Teleport in onSpawnedVehicle
    worker.overrideSpawnWpIdx = overrideSpawnWpIdx -- Batch-Spawn: vorgegebener Startpunkt (nil = zufaelliger WP)
    worker.hopsLeft           = math.random(self.patrolHopsMin or 10,
                                            self.patrolHopsMax or 20) -- Stops vor Heimfahrt

    -- Wiederkehrende Fahrzeuge: 30 % Chance (oder immer wenn forcedXML gesetzt)
    local isReg = (forcedVehicleXML ~= nil) or (math.random() < 0.30)
    if isReg then
        local xml = vehInfo.filename
        local alreadyIn = false
        for _, r in ipairs(self.regularVehicleXMLs) do
            if r == xml then alreadyIn = true; break end
        end
        if not alreadyIn and #self.regularVehicleXMLs < 3 then
            table.insert(self.regularVehicleXMLs, xml)
        end
        worker.isRegular  = true
        worker.regularXML = xml
    end

    -- Gespann-Quote fortschreiben (nur Traktor-Spawns zaehlen, Build 69)
    if isTractor then
        if trailerAdded then
            self.gespannSpawns = (self.gespannSpawns or 0) + 1
        else
            self.soloSpawns = (self.soloSpawns or 0) + 1
        end
    end

    self.vehicleType[patrolId] = {
        vehiclesToLoad    = vehList,
        saveVehicleToLoad = vehList,
        mission           = proxyMission,
        status            = 0,
        fieldId           = patrolId,
        vehicleType       = {},
        NachbarFelderWorker = worker,
    }

    self:loadVehicles(self.vehicleType[patrolId])
    self.countWorkers = self.countWorkers + 1
    local fname = string.match(vehInfo.filename, "[^/\\]+$") or vehInfo.filename
    print("NachbarFelder: [TRAFFIC] " .. tostring(fname) ..
        (trailerAdded and (" + " .. tostring(string.match(vehList[2].filename or "", "[^/\\]+$") or "Anbaugeraet")
            .. string.format(" (%s m, Traktor %.1f t, max %.1f m)",          -- Build 159
                vehList[2].breiteM ~= nil and string.format("%.1f", vehList[2].breiteM) or "?",
                (vehInfo.gewichtKg or 0) / 1000, self:getMaxGeraeteBreite(vehInfo))) or "") ..
        " | Ziel: WP" .. tostring(destIdx) ..
        " | " .. tostring(worker.hopsLeft) .. " Hops" ..
        " | Aktiv: " .. tostring(activePatrol + 1) .. "/" .. tostring(effLimit) ..
        (effLimit < (self.trafficLimit or 4)
            and (" [Tagesrhythmus: eingestellt " .. tostring(self.trafficLimit) ..
                 ", jetzt " .. tostring(effLimit) .. "]") or "") ..
        " | Gespanne: " .. tostring(self.gespannSpawns or 0) .. "/" ..
        tostring((self.gespannSpawns or 0) + (self.soloSpawns or 0)) ..
        " (Ziel " .. tostring(self.trailerChance or 40) .. "%)")
    return true
end

--- Position und Name des Zugfahrzeugs eines Workers (Build 109).
function NachbarFelderManager:getWorkerPos(w)
    local veh = w ~= nil and w.vehiclesToLoad ~= nil and w.vehiclesToLoad[1] or nil
    if veh == nil or veh.rootNode == nil then return nil, nil end
    local x, z = nil, nil
    local vx, _, vz = getWorldTranslation(veh.rootNode)
    x, z = vx, vz
    return x, z
end

function NachbarFelderManager:getWorkerName(w)
    local veh = w ~= nil and w.vehiclesToLoad ~= nil and w.vehiclesToLoad[1] or nil
    local f = veh ~= nil and veh.configFileName or ""
    return string.match(f, "[^/\\]+$") or "?"
end

-- ============================================================
-- Fahrzeuge löschen
-- ============================================================
function NachbarFelderManager:deleteAllVehicles(quit)
    -- Beim Spiel-Shutdown nichts mehr löschen - prepareForShutdown hat die
    -- AI-Jobs gestoppt, die Fahrzeuge löscht die Engine selbst. Eigene
    -- Löschungen hier ergäben "delete twice"-Callstacks.
    if self.isShuttingDown then return end

    -- Im Dedicated-MP: nur Server löscht
    if not g_currentMission:getIsServer() then
        -- Client: Event an Server schicken
        if g_client ~= nil then
            g_client:getServerConnection():sendEvent(NachbarFelderDeleteEvent.new())
        end
        return
    end

    if self.vehicleType == nil then return end

    for v, k in pairs(self.vehicleType) do
        -- Patrol-Fahrzeuge in den Pool statt loeschen (Build 65): beim
        -- naechsten Bedarf werden sie ohne Spawn-Ruckler geweckt. Der
        -- Admin-Vollweg (deleteAllVehiclesAndPool) leert den Pool danach.
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.isPatrol
           and self:sleepPatrolEntry(k, false) then
            -- gepoolt; Eintrag wurde bereits entfernt
        else
            local status = k.NachbarFelderWorker.status
            k.NachbarFelderWorker.status = 9999
            for _, veh in ipairs(k.vehicleType) do
                -- AI-Job sauber stoppen (toggleAIVehicle reicht nicht - Job bleibt
                -- sonst im aiSystem und crasht nach delete jeden Frame)
                if self:getIsVehicleAlive(veh) then
                    self:stopAIJobSafely(veh)
                    local dynamicVeh = string.sub(veh.typeName, 1, string.len("dynamic")) == "dynamic"
                    if (dynamicVeh and status ~= 2) or not dynamicVeh then
                        veh:delete()
                    end
                end
            end
            if quit ~= nil then status = 1 end
            self:deleteMission(k.NachbarFelderWorker.fieldId, status)
        end
    end
end

function NachbarFelderManager:deleteMission(fieldId, status)
    -- Build 150: nur noch Verkehr - Eintrag entfernen, keine Feldarbeit nachzutragen
    if self.vehicleType[fieldId] == nil then return end
    self.vehicleType[fieldId] = nil
    self.counter = self.counter - 1
end

-- ============================================================
-- Shop-Position für Rückfahrt (Navmesh-Spawnpunkt, Straße)
-- ============================================================
function NachbarFelderManager:getShopPosition()
    -- Build 96: Shop-Spawnplatz des Spiels (mit Filiallieferungen = Lieferort).
    local place = self:getNfSpawnPlace()
    if place ~= nil then
        return place.startX or 0, place.startZ or 0
    end
    return 0, 0
end

-- ============================================================
-- Shop-Gebäudeposition (Hofplatz, nicht Straßen-Spawnpunkt).
-- Liefert nil,nil wenn nicht gefunden → Fallback auf Straße.
-- ============================================================
function NachbarFelderManager:getShopBuildingPosition()
    local bx, bz = nil, nil
    -- Versuch 1: PlaceableVehicleShop im PlaceableSystem (Kauf-Shops)
    local function schritt()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil then return end
        for _, p in pairs(ps.placeables or {}) do
            if p.spec_vehicleShop ~= nil and p.rootNode ~= nil then
                local x, _, z = getWorldTranslation(p.rootNode)
                bx, bz = x, z
                return
            end
        end
    end
    schritt()
    -- Versuch 2: g_currentMission.vehicleShops (einige Maps/FS25-Versionen)
    if bx == nil then
        local function schritt()
            for _, s in pairs(g_currentMission.vehicleShops or {}) do
                local nd = s.rootNode
                if nd ~= nil then
                    local x, _, z = getWorldTranslation(nd)
                    bx, bz = x, z
                    return
                end
            end
        end
        schritt()
    end
    if bx ~= nil then
        print("NachbarFelder: [TRAFFIC] Shop-Gebaeude x=" .. math.floor(bx) .. " z=" .. math.floor(bz))
    end
    return bx, bz
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================
-- Prüft ob ein Fahrzeug-Objekt noch existiert (nicht gelöscht).
-- Nach veh:delete() bleiben Referenzen in unseren Tabellen zurück -
-- jeder Zugriff auf rootNode wirft dann Lua-Fehler. Auf dem Dedicated
-- Server läuft dadurch das Log voll und Joins schlagen fehl bis zum
-- Neustart. Deshalb VOR jedem Zugriff/delete prüfen.
function NachbarFelderManager:getIsVehicleAlive(veh)
    return veh ~= nil and veh.isDeleted ~= true and veh.rootNode ~= nil
end

-- Markiert Traktor UND alle Anbaugeräte als Helfer-Fahrzeug.
-- getIsMissionWorkAllowed wird pro Arbeitsbereich mit dem jeweiligen GERÄT
-- aufgerufen - hatte nur der Traktor das Flag, durfte das Gerät (Spritze/
-- Pflug) nicht arbeiten → Helfer fuhr ohne zu sprühen/pflügen.
function NachbarFelderManager:markVehiclesAsHelper(vehicle)
    if vehicle == nil then return end
    vehicle.nf_isHelper = true
    vehicle.allowedDrive = true
    if vehicle.getChildVehicles ~= nil then
        for _, v in ipairs(vehicle:getChildVehicles()) do
            if v ~= vehicle then
                v.allowedDrive = true
                v.nf_isHelper = true
            end
        end
    end
end

function NachbarFelderManager:getCorrectobject(vehicle)
    for v, k in pairs(self.vehicleType) do
        for _, veh in ipairs(k.vehicleType) do
            if veh == vehicle then
                return k.NachbarFelderWorker
            end
        end
    end
    return nil
end

function NachbarFelderManager:hasActiveWorkers()
    if self.vehicleType == nil then return false end
    for _, entry in pairs(self.vehicleType) do
        if entry ~= nil and entry.NachbarFelderWorker ~= nil then return true end
    end
    return false
end

-- ============================================================
-- deleteMap / deleteAllVehicles beim Spielende
-- ============================================================
function NachbarFelderManager:deleteMap()
    if g_currentMission:getIsServer() then
        self:deleteAllVehicles("q")
    end
end

-- ============================================================
-- Speichern / Laden
-- ============================================================
function NachbarFelderManager:saveToXMLFile()
    -- Build 160: laeuft vor ItemSystem.save mit - ein Fehler hier wuerde ohne
    -- Absicherung das Speichern des Spielstands abbrechen. Darum alles vorher pruefen.
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local path = mi ~= nil and mi.savegameDirectory or nil
    if path == nil or g_NachbarFelderManager == nil or g_NachbarFelderManager.getSettingsState == nil then return end
    local modSaveDir = path .. "/NachbarFelder.xml"
    local xmlFile = XMLFile.create("NachbarFelder", modSaveDir, baseXmlKey, xmlSchema)
    if xmlFile == nil then return end
    -- Build 150: keine Feldauftraege mehr - nur noch die Einstellungen speichern
    if g_NachbarFelderManager.vehicleType ~= nil then
        -- Settings-Block (Build 67): kompletter Einstellungs-Stand ins
        -- Savegame - server-autoritativ, ueberlebt Neustarts.
        local st = g_NachbarFelderManager:getSettingsState() or {}
        xmlFile:setBool(baseXmlKey .. ".settings#active",             st.active ~= false)
        xmlFile:setInt( baseXmlKey .. ".settings#maxWorkers",         math.floor(tonumber(st.maxWorkers) or 0))
        xmlFile:setInt( baseXmlKey .. ".settings#trafficLimit",       math.floor(tonumber(st.trafficLimit) or 0))
        xmlFile:setInt( baseXmlKey .. ".settings#trafficTrailerSize", math.floor(tonumber(st.trafficTrailerSize) or 0))
        xmlFile:setBool(baseXmlKey .. ".settings#engeMap",            st.engeMap ~= false)
        xmlFile:setBool(baseXmlKey .. ".settings#debugLog",           st.debugLog == true)
        local j = 0
        for mName, mActive in pairs(st.missions or {}) do
            local mKey = ("%s.settings.mission(%d)"):format(baseXmlKey, j)
            xmlFile:setString(mKey .. "#type",   tostring(mName))
            xmlFile:setBool(  mKey .. "#active", mActive == true)
            j = j + 1
        end
        xmlFile:save(false, false)
    end
    xmlFile:delete()
end

function NachbarFelderManager:loadFromXML()
    local path = g_currentMission.missionInfo.savegameDirectory
    if path == nil then return end
    local modSaveDir = path .. "/NachbarFelder.xml"
    local xmlFile = XMLFile.loadIfExists("NachbarFelder", modSaveDir, xmlSchema)
    if xmlFile == nil then return end
    -- Build 150: gespeicherte Feldauftraege (".worker") aelterer Builds werden ignoriert
    -- Settings-Block lesen (Build 67). NICHT sofort anwenden - erst
    -- nach loadServerConfig() (in loadMap), damit die Savegame-Werte
    -- die Konfig-Datei-Werte ueberschreiben und nicht umgekehrt.
    local sgActive = xmlFile:getValue(baseXmlKey .. ".settings#active")
    if sgActive ~= nil then
        local st = {
            active             = sgActive,
            maxWorkers         = xmlFile:getValue(baseXmlKey .. ".settings#maxWorkers"),
            trafficLimit       = xmlFile:getValue(baseXmlKey .. ".settings#trafficLimit"),
            trafficTrailerSize = xmlFile:getValue(baseXmlKey .. ".settings#trafficTrailerSize"),
            engeMap            = xmlFile:getValue(baseXmlKey .. ".settings#engeMap"),
            debugLog           = xmlFile:getValue(baseXmlKey .. ".settings#debugLog"),   -- Build 165
            missions           = {},
        }
        xmlFile:iterate(baseXmlKey .. ".settings.mission", function(_, mKey)
            local mName   = xmlFile:getValue(mKey .. "#type")
            local mActive = xmlFile:getValue(mKey .. "#active")
            if mName ~= nil and mActive ~= nil then
                st.missions[mName] = mActive
            end
        end)
        self.savegameSettings = st
    end
    xmlFile:delete()
end

-- ============================================================
-- Traffic-Wegpunkte: eigene Datei im Mod-Settings-Ordner
-- Wird auf Server UND Client geladen/gespeichert.
-- Pfad: modSettingDirectory .. "NachbarFelderWaypoints.xml"
-- ============================================================
-- ============================================================
-- ============================================================
-- Wegpunkte auf der Ingame-Karte (MapHotspot-System)
-- MapHotspot wird vom Spiel selbst mit korrekter Zoom/Pan-Unterstützung
-- gerendert — kein manuelles Koordinaten-Rechnen nötig.
-- Referenz: FS25_EasyDevControls EasyDevControlsHotspotsManager.lua
-- ============================================================

-- NFWaypointHotspot-Klasse (lazy definiert beim ersten Aufruf von updateWpHotspots)
local NFWaypointHotspot_cls = nil
local function ensureWpHotspotClass()
    if NFWaypointHotspot_cls ~= nil then return true end
    if MapHotspot == nil then return false end
    local function schritt()
        local cls    = {}
        local cls_mt = Class(cls, MapHotspot)

        function cls.new(worldX, worldZ)
            local self     = MapHotspot.new(cls_mt)
            self.width, self.height = getNormalizedScreenValues(32, 32)
            -- "mapHotspots.other" = generisches Karten-Icon aus dem Spiel-Atlas
            self.icon = g_overlayManager:createOverlay(
                "mapHotspots.other", 0, 0, self.width, self.height)
            self:setColor(1.0, 0.55, 0.0)   -- Orange = NF-Wegpunkt
            self:setWorldPosition(worldX, worldZ)
            self:setVisible(true)
            return self
        end

        function cls:getCategory()
            return MapHotspot.CATEGORY_OTHER
        end

        NFWaypointHotspot_cls = cls
    end
    schritt()
    return NFWaypointHotspot_cls ~= nil
end

function NachbarFelderManager:setupMapDrawHook()
    if self._mapDrawHookSetup then return end
    self._mapDrawHookSetup = true
    -- Initial-Hotspots anlegen (Wegpunkte aus gespeicherter Datei)
    self:updateWpHotspots()

    -- Nummern-Hook: renderText NACH dem Hotspot-Rendering des Spiels.
    -- getLastScreenPosition() liefert zoom/pan-korrigierte Bildschirmkoords.
    -- Referenz: FS25_EasyDevControls EasyDevControlsTeleportScreen:onDrawPostIngameMapHotspots
    if InGameMenuMapFrame ~= nil then
        local mgr = self
        -- Allokationsfrei (Build 76): Zeichenfunktion EINMAL definieren und per
        -- benannte Funktion aufrufen - kein Closure-/String-Müll pro Frame (GC-Ruckler).
        -- Nummern-Strings werden in updateWpHotspots vorberechnet (hs._nfLabel).
        local function nfDrawWpNumbers()
            local hss = mgr._wpMapHotspots
            for i = 1, #hss do
                local hs = hss[i]
                local sx, sy = nil, nil
                if hs ~= nil and hs.getLastScreenPosition ~= nil then
                    sx, sy = hs:getLastScreenPosition()
                end
                if sx ~= nil and sy ~= nil then
                    local w = hs.width  or 0.008
                    local h = hs.height or 0.008
                    -- Nummer rechts oben neben dem Icon
                    setTextColor(1.0, 0.9, 0.3, 1)
                    setTextBold(true)
                    renderText(sx + w * 0.9, sy + h * 0.6, 0.011, hs._nfLabel or "?")
                    setTextBold(false)
                end
            end
            setTextColor(1, 1, 1, 1)
        end
        local function schritt()
            InGameMenuMapFrame.draw = Utils.appendedFunction(InGameMenuMapFrame.draw,
            function(frame)
                if mgr._wpHotspotsEnabled == false then return end
                local hss = mgr._wpMapHotspots
                if hss == nil or #hss == 0 then return end
                nfDrawWpNumbers()
            end)
        end
        schritt()
    end
    print("NachbarFelder: [MAP] MapHotspot-System + Nummern-Hook initialisiert")
end

-- ============================================================
-- Client-lokale Anzeige-Einstellungen (Build 71): Dinge, die nur
-- diesen Rechner betreffen (Karten-Hotspots an/aus), landen in
-- modSettings/FS25_NachbarFelder/NachbarFelderClient.xml -
-- NICHT im Savegame und nicht auf dem Server.
-- ============================================================
function NachbarFelderManager:loadClientPrefs()
    local function schritt()
        local path = modSettingDirectory .. "NachbarFelderClient.xml"
        if not fileExists(path) then
            -- Datei mit Defaults anlegen (Build 73): so ist sofort sichtbar,
            -- dass der Mechanismus laeuft; gespeichert wird bei jedem Umschalten.
            self:saveClientPrefs()
            print("NachbarFelder: [MAP] Client-Einstellungsdatei angelegt: " .. path)
            return
        end
        local xf = loadXMLFile("nfClient", path)
        if xf == nil or xf == 0 then return end
        local show = getXMLBool(xf, "nachbarFelderClient.showWpOnMap")
        if show ~= nil then
            self._wpHotspotsEnabled = show
            print("NachbarFelder: [MAP] Karten-Hotspots laut Client-Einstellung: " ..
                tostring(show))
        end
        delete(xf)
    end
    schritt()
end

function NachbarFelderManager:saveClientPrefs()
    local function schritt()
        createFolder(modSettingDirectory)
        local path = modSettingDirectory .. "NachbarFelderClient.xml"
        local xf = createXMLFile("nfClient", path, "nachbarFelderClient")
        if xf == nil or xf == 0 then return end
        setXMLBool(xf, "nachbarFelderClient.showWpOnMap", self._wpHotspotsEnabled ~= false)
        saveXMLFile(xf)
        delete(xf)
    end
    schritt()
end

-- Wegpunkte auf Karte ein-/ausblenden (für Einstellungsseite)
function NachbarFelderManager:setWpHotspotsVisible(visible)
    self._wpHotspotsEnabled = visible
    self:updateWpHotspots()
    -- Client-lokal merken (Build 71): ueberlebt den Neustart
    self:saveClientPrefs()
end

-- Hotspots neu aufbauen — wird nach jeder WP-Änderung und beim Init aufgerufen
function NachbarFelderManager:updateWpHotspots()
    -- Bestehende Hotspots entfernen
    if self._wpMapHotspots ~= nil then
        for _, hs in ipairs(self._wpMapHotspots) do
            if g_currentMission ~= nil then
                if g_currentMission ~= nil and g_currentMission.removeMapHotspot ~= nil then g_currentMission:removeMapHotspot(hs) end
            end
        end
        self._wpMapHotspots = nil
    end

    if self._wpHotspotsEnabled == false then return end
    if g_currentMission == nil then return end
    if not ensureWpHotspotClass() then
        print("NachbarFelder: [MAP] MapHotspot nicht verfügbar")
        return
    end

    self._wpMapHotspots = {}
    local wps = self.userTrafficWaypoints or {}
    for i, wp in ipairs(wps) do
        local hs = nil
        if NFWaypointHotspot_cls.new ~= nil then hs = NFWaypointHotspot_cls.new(wp.x, wp.z) end
        if hs ~= nil then
            -- vorberechnet für den Draw-Hook (kein Müll pro Frame); Spawnpunkte mit "S"
            hs._nfLabel = self:getIstSpawnpunkt(wp) and (tostring(i) .. " S") or tostring(i)
            if g_currentMission ~= nil and g_currentMission.addMapHotspot ~= nil then g_currentMission:addMapHotspot(hs) end
            table.insert(self._wpMapHotspots, hs)
        end
    end
    print(string.format("NachbarFelder: [MAP] %d WP-Hotspots gesetzt", #(self._wpMapHotspots))  )
end

function NachbarFelderManager:saveWaypoints()
    -- Reiner Client (Dedi-MP): Die Datei gehört dem SERVER - hier nie schreiben.
    -- Client-Änderungen laufen als NachbarFelderWaypointEditEvent zum Server,
    -- der speichert und die Liste zurück-synct.
    if g_currentMission ~= nil and not g_currentMission:getIsServer() then
        return
    end
    -- WP-Liste wurde geändert (hinzugefügt/gelöscht) → Indizes verschieben sich,
    -- gemerkte Erreichbarkeits-Sperren passen nicht mehr → zurücksetzen.
    self.wpFails = {}
    self.patrolWpList = nil   -- Build 104: Ziel-Liste neu aufbauen
    local pfad = nfGetWpFilePath()   -- Build 132: Datei der geladenen Karte
    local xmlFile = XMLFile.create("NachbarFelderWaypoints", pfad, wpXmlKey, wpXmlSchema)
    if xmlFile == nil then
        print("NachbarFelder: [TRAFFIC] Konnte Waypoint-Datei nicht schreiben: " .. pfad)
        return
    end
    -- Fahrzeugkategorie-Filter
    if self.vehicleCatEnabled ~= nil then
        local c = self.vehicleCatEnabled
        xmlFile:setInt(wpXmlKey .. "#catTractorS",   (c.TRACTORSS           ~= false) and 1 or 0)
        xmlFile:setInt(wpXmlKey .. "#catTractorM",   (c.TRACTORSM           ~= false) and 1 or 0)
        xmlFile:setInt(wpXmlKey .. "#catTractorL",   (c.TRACTORSL           ~= false) and 1 or 0)
        xmlFile:setInt(wpXmlKey .. "#catLoader",     (c.WHEELLOADERVEHICLES ~= false) and 1 or 0)
        xmlFile:setInt(wpXmlKey .. "#catTeleLoader", (c.TELELOADERVEHICLES  ~= false) and 1 or 0)
    end
    for wi, wp in ipairs(self.userTrafficWaypoints) do
        local key = ("%s.wp(%d)"):format(wpXmlKey, wi - 1)
        xmlFile:setFloat(key .. "#x", wp.x)
        xmlFile:setFloat(key .. "#z", wp.z)
        xmlFile:setString(key .. "#label", wp.label or "")
        xmlFile:setFloat(key .. "#ry",  wp.ry  or 0)
        xmlFile:setInt(  key .. "#cat", wp.cat or 0)
    end
    xmlFile:save(false, false)
    xmlFile:delete()
    print("NachbarFelder: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
        " Wegpunkte gespeichert -> " .. pfad)
    -- Im Dedicated-MP: Änderung sofort an alle Clients broadcasten
    if g_currentMission:getIsServer() and g_server ~= nil then
        g_server:broadcastEvent(NachbarFelderWaypointSyncEvent.new(self.userTrafficWaypoints))
    end
end

function NachbarFelderManager:loadWaypoints()
    local pfad = nfGetWpFilePath()   -- Build 132: Datei der geladenen Karte
    local xmlFile = XMLFile.loadIfExists("NachbarFelderWaypoints", pfad, wpXmlSchema)

    -- Build 132: Gibt es fuer diese Karte noch keine Datei, wird die alte
    -- gemeinsame Datei EINMAL uebernommen - fuer die erste Karte, die der Server
    -- damit laedt. Die alte Datei bleibt liegen und bekommt eine Markierung, damit
    -- eine spaeter geladene andere Karte die Punkte nicht noch einmal erbt.
    local ausAlterDatei = false
    if xmlFile == nil and pfad ~= wpFilePathAlt and g_currentMission:getIsServer() then
        local alt = XMLFile.loadIfExists("NachbarFelderWaypoints", wpFilePathAlt, wpXmlSchema)
        if alt ~= nil then
            local vergeben = alt:getString(wpXmlKey .. "#uebernommenFuer")
            if vergeben == nil or vergeben == "" then
                xmlFile = alt
                ausAlterDatei = true
            else
                alt:delete()
            end
        end
    end

    if xmlFile == nil then
        print("NachbarFelder: [TRAFFIC] Keine Wegpunkt-Datei fuer diese Karte: " .. pfad)
        return
    end
    self.wpFails = {}  -- neue WP-Liste → alte Erreichbarkeits-Sperren verwerfen
    self.patrolWpList = nil   -- Build 104: Ziel-Liste neu aufbauen
    self.userTrafficWaypoints = {}
    -- Fahrzeugkategorien nur uebernehmen, wenn die Datei sie enthaelt.
    -- Sind Werte da, wurden sie IN-GAME gesetzt -> autoritativ:
    -- loadServerConfig darf sie dann nicht mehr ueberschreiben (Build 71,
    -- vorher gewann die Konfig-Datei und die GUI-Einstellung ging beim
    -- Neustart verloren).
    if xmlFile:getInt(wpXmlKey .. "#catTractorS") ~= nil then
        self.vehicleCatEnabled = {
            TRACTORSS           = xmlFile:getInt(wpXmlKey .. "#catTractorS",   1) ~= 0,
            TRACTORSM           = xmlFile:getInt(wpXmlKey .. "#catTractorM",   1) ~= 0,
            TRACTORSL           = xmlFile:getInt(wpXmlKey .. "#catTractorL",   1) ~= 0,
            WHEELLOADERVEHICLES = xmlFile:getInt(wpXmlKey .. "#catLoader",     1) ~= 0,
            TELELOADERVEHICLES  = xmlFile:getInt(wpXmlKey .. "#catTeleLoader", 1) ~= 0,
        }
        self.vehicleCatsFromFile = true
    end
    xmlFile:iterate(wpXmlKey .. ".wp", function(_, key)
        local x = xmlFile:getFloat(key .. "#x", nil)
        local z = xmlFile:getFloat(key .. "#z", nil)
        local label = xmlFile:getString(key .. "#label", "")
        local ry  = xmlFile:getFloat(key .. "#ry",  0)
        local cat = xmlFile:getInt(  key .. "#cat", 0)
        if x ~= nil and z ~= nil then
            table.insert(self.userTrafficWaypoints, { x=x, z=z, ry=ry, cat=cat, label=label })
        end
    end)
    if ausAlterDatei then
        -- alte Datei markieren (bleibt als Sicherung liegen), danach die neue
        -- Kartendatei schreiben
        xmlFile:setString(wpXmlKey .. "#uebernommenFuer", nfGetKartenKennung() or "?")
        xmlFile:save(false, false)
    end
    xmlFile:delete()
    if ausAlterDatei then
        print("NachbarFelder: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
            " Wegpunkte aus der alten gemeinsamen Datei fuer diese Karte uebernommen -> " .. pfad)
        self:saveWaypoints()
    elseif #self.userTrafficWaypoints > 0 then
        print("NachbarFelder: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
            " Wegpunkte geladen: " .. pfad)
    end
end

-- ============================================================
-- Console Commands
-- ============================================================
function NachbarFelderManager:addConsoleCommands()
    if self.consoleCommandsAdded then return end
    self.consoleCommandsAdded = true

    addConsoleCommand("nachbarFelderTimer",
        "NachbarFelder: Zeit bis zum naechsten Verkehrs-Spawn anzeigen",
        "consoleCommandNachbarFelderTimer", self)
    addConsoleCommand("nachbarFelderEntfernen",
        "NachbarFelder: alle aktiven Fahrzeuge entfernen",
        "consoleCommandNachbarFelderEntfernen", self)
    addConsoleCommand("nachbarFelderTrafficStop",
        "NachbarFelder: alle Traffic-Fahrzeuge entfernen und neue sperren",
        "consoleCommandNachbarFelderTrafficStop", self)
    addConsoleCommand("nachbarFelderTrafficStart",
        "NachbarFelder: Traffic-Fahrzeuge wieder erlauben",
        "consoleCommandNachbarFelderTrafficStart", self)
end

function NachbarFelderManager:consoleCommandNachbarFelderTimer()
    print("NachbarFelder: naechster Verkehrs-Spawn in " .. tostring(self.timeToNextStart) .. " Spielminuten")
end

function NachbarFelderManager:consoleCommandNachbarFelderEntfernen()
    self:deleteAllVehiclesAndPool()
end

function NachbarFelderManager:consoleCommandNachbarFelderTrafficStop()
    if not g_currentMission:getIsServer() then
        print("NachbarFelder: nachbarFelderTrafficStop nur auf Server/SP verfuegbar!")
        return
    end
    self.trafficPaused = true
    -- Auch schlafende Pool-Fahrzeuge entfernen (Kommando = "alle weg")
    self:clearTrafficPool()
    local count = 0
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.isPatrol and w.status ~= 100 and w.status ~= 9999 then
            w.noPool    = true
            w.status    = 100
            w.needTimer = true
            count = count + 1
        end
    end
    print("NachbarFelder: [TRAFFIC] gestoppt – " .. tostring(count) .. " Fahrzeug(e) werden entfernt.")
end

function NachbarFelderManager:consoleCommandNachbarFelderTrafficStart()
    if not g_currentMission:getIsServer() then
        print("NachbarFelder: nachbarFelderTrafficStart nur auf Server/SP verfuegbar!")
        return
    end
    self.trafficPaused = false
    print("NachbarFelder: [TRAFFIC] wieder aktiv – neue Fahrzeuge spawnen normal.")
end

-- ============================================================
-- Settings-Seite (Client)
-- ============================================================
function NachbarFelderManager:initializeSettingsPage()
    if misssionSettingsPage == nil then
        misssionSettingsPage = NachbarFelderSettingsPage.new(self)
        misssionSettingsPage:init()
    end
    self.settingsPage = misssionSettingsPage
end

-- Legacy-Kompatibilität: initialize() wurde früher von OWN_PLAYER_ENTERED aufgerufen
function NachbarFelderManager:initialize()
    self:initializeSettingsPage()
    if not self.consoleCommandsAdded then
        self:addConsoleCommands()
    end
    -- Server-Init läuft jetzt in loadMap / serverSideInit
    if g_currentMission:getIsServer() and not self.serverInitialized then
        self:serverSideInit()
    end
end

NachbarFelderManager = {}

-- Normale Ausgaben nur im Debug-Log, Warnungen/Fehler immer (siehe NachbarFelder.lua)
local print = NachbarFelderLog.print

-- Steht beim loadMap im Log. Server und Clients werden getrennt bestückt,
-- daran sieht man, ob beide denselben Stand fahren.
NachbarFelderManager.BUILD = 179

local NachbarFelderManager_class = Class(NachbarFelderManager)

-- Begegnung zweier Nachbar-Fahrzeuge (siehe loeseBegegnung)
NachbarFelderManager.BEGEGNUNG_RADIUS  = 100     -- m, so nah muss der stehende Nachbar sein
NachbarFelderManager.BEGEGNUNG_NAH     = 20      -- m, bis hier zaehlt jede Richtung, darueber nur "vor mir"
NachbarFelderManager.BEGEGNUNG_STEHT_MS = 15000  -- so lange muss auch er schon stehen
NachbarFelderManager.BEGEGNUNG_MAX     = 3       -- Ausweichen je Fahrzeug, danach normale Stufen

local modSettingDirectory = g_currentModSettingsDirectory
local modName = g_currentModName
local xmlSchema = XMLSchema.new("NachbarFelderSchema")
local baseXmlKey = "NachbarFelder"

-- Eigenes Schema für die Verkehrs-Wegpunkte (liegen in modSettings, nicht im Savegame)
local wpXmlSchema = XMLSchema.new("NachbarFelderWaypointSchema")
local wpXmlKey    = "NachbarFelderWaypoints"
-- Wegpunkte gelten je Karte (nfGetWpFilePath). Die alte gemeinsame Datei ist nur
-- noch Rückfall, wenn sich die Karte nicht bestimmen lässt.
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

-- Gesperrte Ladeplätze je Karte dauerhaft merken, sonst wird ein schlechter Platz
-- nach jedem Neustart wieder genommen.
local lpXmlSchema = XMLSchema.new("NachbarFelderLadeplatzSchema")
local lpXmlKey    = "NachbarFelderLadeplaetze"
lpXmlSchema:register(XMLValueType.FLOAT,  lpXmlKey .. ".platz(?)#x",     "LadeplatzX")
lpXmlSchema:register(XMLValueType.FLOAT,  lpXmlKey .. ".platz(?)#z",     "LadeplatzZ")
lpXmlSchema:register(XMLValueType.STRING, lpXmlKey .. ".platz(?)#grund", "Grund der Sperre")

--- Text aus l10n (ModHub verlangt Deutsch und Englisch für alles Sichtbare).
--- Fehlt der Eintrag, wird der Schlüssel selbst zurückgegeben.
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

--- Kennung der geladenen Karte für Dateinamen: missionInfo.mapId
--- (z. B. FS25_Beuren.MultifruitModMap_Beuren), ersatzweise der letzte
--- Ordnername von g_currentMission.baseDirectory (wie in FarmlandManager.lua).
--- @return string|nil
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

--- Wegpunkt-Datei der geladenen Karte. Wird erst zur Laufzeit bestimmt, beim
--- Laden des Skripts gibt es noch keine Mission. Ohne Kartenkennung die alte
--- gemeinsame Datei.
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

    self.playersOnline = 0    -- verbundene Spieler; 0 = Helfer pausieren
    self.playerJoinTime       = nil  -- g_time beim ersten Join; Wartezeit in Echtzeit, unabhängig von Zeitsprüngen
    self.regularVehicleXMLs   = {}   -- bis zu 3 wiederkehrende Stammfahrzeuge (XML-Pfade)
    self.pendingRespawns      = {}   -- {filename, spawnAt}: Respawn-Warteschlange der Stammfahrzeuge
    self.spawnPlaceIndex = 1 -- bester Shop-Spawnpunkt, gesetzt in selectBestSpawnPlace
    self.trafficVehicleBlacklist = {}   -- filename = true: Fahrzeuge ohne Navigations-Agent (gilt bis Neustart)
    self.patrolCounter = 0          -- negative Pseudo-Keys für Patrol-Einträge in vehicleType
    self.trafficLimit = 4           -- max. gleichzeitige Verkehrsfahrzeuge
    self.trafficPaused = false      -- Konsole: nachbarFelderTrafficStop/Start
    self.trafficTrailerSize = 2     -- 0 = keine Anhänger, 1 = bis 4 kL, 2 = bis 8 kL, 3 = bis 15 kL
    self.engeMap        = true      -- enge Karte: nur Kleintraktoren und leichte Anbaugeräte
    self.debugLog       = false     -- ausführliches Log (Einstellung oder logLevel=2)
    self.spawnBereichRadius = 25    -- m, so weit muss der Shop-Spawn frei sein
    self.spawnLookAt    = nil       -- Cache für die Spawn-Blickrichtung {x=,z=,quelle=}
    self.trafficPool = {}           -- schlafende Patrol-Fahrzeuge
    self.poolSize    = 6            -- max. schlafende Fahrzeuge, 0 = Pool aus
    self.fahrerfigurenAufServer = true  -- false = auf dem Server keine Fahrerfiguren
    self.spielverkehrAnmelden   = true  -- beim Spielverkehr anmelden, damit Autos bremsen
    self.rueckwaertsPlanen      = false -- standardmäßig aus, führte zu vielen sofort abgewiesenen Fahrten
    self.dayRhythm      = true      -- Verkehrsdichte folgt der Uhrzeit
    self.zielQuelle     = "strassen" -- "strassen" = Ziele aus dem KI-Straßennetz,
                                     -- "wegpunkte" = nur selbst gesetzte Punkte
    self.trailerChance  = 40        -- Anteil Traktoren mit Anbaugerät in %
    self.gespannSpawns  = 0         -- Zähler: Traktor-Spawns mit Anbaugerät
    self.soloSpawns     = 0         -- Zähler: Traktor-Spawns ohne Anbaugerät
    self.userTrafficWaypoints = {}  -- selbst gesetzte Wegpunkte {{x,z}, ...}
    self._mgr_viewIdx = 0           -- Anzeige-Index für Shift+Alt+W
    self._wpHotspots  = {}          -- MapHotspots der Wegpunkte
    self.trafficTrailerList   = nil  -- schwere Anbaugeräte (Pflug, Mähwerk) für Großtraktoren
    self.trafficImplListLight = nil  -- leichte Anbaugeräte (Schwader, Zinkenrotor) für die Mittelklasse
    self.vehicleCatEnabled = {      -- Fahrzeugkategorien, false = ausgeblendet
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
    -- Auftrag an den Lohnunternehmer (NachbarFelderAuftrag.lua)
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".worker(?)#auftrag",       "Auftrag eines Spielers")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".worker(?)#auftragFarmId", "Farm des Auftraggebers")
    -- Einstellungen liegen im Savegame (Server entscheidet, wird im MP synchronisiert).
    -- NachbarFelderSetting.xml gilt nur für Spielstände ohne settings-Block.
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#active",             "ModActive")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#maxWorkers",         "MaxWorkers")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#trafficLimit",       "TrafficLimit")
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".settings#trafficTrailerSize", "TrafficTrailerSize")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#engeMap",            "EngeMap")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings#debugLog",           "DebugLog")
    xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".settings.mission(?)#type",   "MissionType")
    xmlSchema:register(XMLValueType.BOOL,   baseXmlKey .. ".settings.mission(?)#active", "MissionActive")
    -- Vorfrucht je Feld
    xmlSchema:register(XMLValueType.INT,    baseXmlKey .. ".fieldFruits.field(?)#id",    "FieldId")
    xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".fieldFruits.field(?)#fruit", "FruitName")
    return self
end

-- ============================================================
-- Einstellungen (der Server ist maßgeblich)
-- Client schickt eine Änderung (NachbarFelderSettingsEditEvent), der Server
-- übernimmt sie, merkt sie fürs Savegame vor und verteilt den kompletten
-- Stand per NachbarFelderSettingsSyncEvent an alle Clients.
-- ============================================================

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
        debugLog           = self.debugLog == true,
        missions           = missions,
        -- Clients brauchen die Helfer-Farm, um deren Kartensymbole auszublenden; 0 = noch unbekannt
        helferFarmId       = self:getHelferFarmIdAnzeige(),
    }
end

-- Einstellungs-Stand anwenden (Server nach Savegame-Load, Client nach Sync)
function NachbarFelderManager:applySettingsState(state)
    if state == nil then return end
    if state.helferFarmId ~= nil then   -- nur für die Anzeige
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
            self.trafficTrailerList = nil  -- Cache für die neue Größe verwerfen
        end
        self.trafficTrailerSize = tts
    end
    if state.engeMap ~= nil then
        local neu = state.engeMap == true
        if neu ~= (self.engeMap ~= false) then
            -- Beide Caches verwerfen: Fahrzeugliste hängt an den Kategorien,
            -- Geräteliste am Gewichtslimit.
            self.trafficVehicleList = nil
            self.trafficTrailerList = nil
        end
        self.engeMap = neu
    end
    if state.debugLog ~= nil then
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
    if self.settingsPage ~= nil and self.settingsPage.refreshFromManager ~= nil then
        if self.settingsPage ~= nil and self.settingsPage.refreshFromManager ~= nil then self.settingsPage:refreshFromManager() end
    end
end

-- Nur auf dem Server. value kommt vom Event als Zahl, aus der SP/Host-GUI
-- auch als bool.
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
    elseif name == "debugLog" then
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
        print("LivingRoads: [SETTINGS] Unbekannte Einstellung ignoriert: " .. tostring(name))
        return
    end

    -- Der Live-Stand landet beim nächsten Speichern im Savegame und hat
    -- dann Vorrang vor der Server-Konfig.
    self.settingsFromSavegame = true
    print("LivingRoads: [SETTINGS] " .. tostring(name) .. " = " .. tostring(value))
    self:broadcastSettingsToClients()
end

function NachbarFelderManager:broadcastSettingsToClients()
    if g_server ~= nil and NachbarFelderSettingsSyncEvent ~= nil then
        g_server:broadcastEvent(NachbarFelderSettingsSyncEvent.new(self:getSettingsState()))
    end
end

-- ============================================================
-- Helfer-Farm
-- AI-Jobs mit farmId = SPECTATOR_FARM_ID weist die Engine sofort ab.
-- Die Helfer-Farm hat Sonderrechte (keine Kosten, jedes Feld), darf also
-- nie eine Farm mit Spielern sein. Reihenfolge:
--   1. <farmId> aus der Server-Konfig, wenn die Farm existiert und leer ist
--   2. höchste Farm ohne Spieler, Farmland und Gebäude
--   3. höchste Farm ohne Spieler
--   4. sonst Spectator-Farm, die Helfer starten dann nicht (Warnung im Log)
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
    -- Mitglieder stehen in farm.players (farms.xml <players>), die anderen Felder zur Sicherheit
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
            -- Ohne Mitgliederliste nicht nehmen, könnte eine Spieler-Farm sein
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
            print(string.format("LivingRoads: WARNUNG Konfig farmId=%d existiert nicht oder hat Spieler - waehle automatisch", cfg))
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
        print("LivingRoads: WARNUNG keine Farm ohne Spieler gefunden - Helfer koennen nicht starten. " ..
              "Im Spiel eine leere Farm anlegen und Server neu starten.")
        return self.farmId
    end
    self.farmId = gewaehlt.farmId
    print(string.format("LivingRoads: Helfer-Farm = %d '%s' (%s, Farmland %d, Gebaeude %d)",
        gewaehlt.farmId, gewaehlt.name, grund, gewaehlt.farmlands, gewaehlt.gebaeude))
    self:broadcastSettingsToClients()   -- damit die Clients die Helfer-Farm kennen
    return self.farmId
end

-- ============================================================
-- Admin-Rechte
-- Ändern (Wegpunkte, Einstellungen, Helfer starten/löschen) nur für Admins,
-- reine Anzeige für alle. Der Server merkt sich Master-User-Verbindungen über
-- MessageType.MASTERUSER_ADDED (wie FS25_EasyDevControls), ersatzweise wird
-- der User an der Connection geprüft.
-- ============================================================
function NachbarFelderManager:onMasterUserAdded(user)
    if user ~= nil and user.getConnection ~= nil then
        self.adminConnections = self.adminConnections or {}
        self.adminConnections[user:getConnection()] = true
        local name = (user.getNickname ~= nil) and user:getNickname() or "?"
        print("LivingRoads: [ADMIN] Master-User registriert: " .. tostring(name))
    end
end

-- Server: connection == nil ist ein lokaler Aufruf und gilt als Admin.
function NachbarFelderManager:getIsConnectionAdmin(connection)
    if connection == nil then return true end
    if self.adminConnections ~= nil and self.adminConnections[connection] == true then
        return true
    end
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

-- Lokaler Spieler: SP und Host immer, auf dem Dedi nur nach Admin-Login.
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
-- Kosten
-- AIJob:updateCost() stoppt einen Job mit AIMessageErrorOutOfMoney, sobald
-- das Guthaben die Helferkosten nicht deckt. Die NF-Jobs liefern deshalb
-- getPricePerMs() = 0 (siehe driveToField und Feldarbeit), so gibt es keine
-- Geldprüfung und keinen Eingriff ins Konto der Helfer-Farm.
-- Der Kontostand heißt in FS25 farm:getBalance(), ein farm.money gibt es nicht.
-- ============================================================

-- ============================================================
-- Erreichbarkeit der Wegpunkte
-- Ziele, die wiederholt AIMessageErrorNotReachable liefern, werden bis zum
-- Neustart als Fahrziel gesperrt (wie fieldPathFails bei Feldern).
-- ============================================================
--- "(x=... z=...)" zu einer Wegpunkt-Nummer, leer wenn unbekannt.
--- Nutzt die gemeinsame Liste, damit auch Straßenziele Koordinaten zeigen.
function NachbarFelderManager:getWaypointPosText(idx)
    local list = self.patrolWpList or self.userTrafficWaypoints
    local wp = list ~= nil and list[idx] or nil
    if wp == nil then return "" end
    return string.format(" (x=%d z=%d)",
        math.floor(wp.x or wp[1] or 0), math.floor(wp.z or wp[2] or 0))
end

-- Wegpunkt-Typ "Spawnpunkt": vom Admin gesetzter Ladeplatz für neue Fahrzeuge.
-- 3 ist "Durchfahrt" (Straßenziele aus dem KI-Netz).
NachbarFelderManager.WP_CAT_SPAWN = 4

--- Für beide Formen: { x=, z=, cat= } (userTrafficWaypoints) und
--- { x, z, ry, cat } (Zielliste eines Fahrzeugs).
function NachbarFelderManager:getIstSpawnpunkt(wp)
    if wp == nil then return false end
    return (wp.cat or wp[4] or 0) == NachbarFelderManager.WP_CAT_SPAWN
end

--- Selbst gesetzte Wegpunkte stehen vorn in der Liste.
function NachbarFelderManager:getIsEigenerWaypoint(idx)
    return self.userTrafficWaypoints ~= nil and idx ~= nil
       and idx <= #self.userTrafficWaypoints
end

--- Parkpunkt in der Zielliste dieses Fahrzeugs?
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
        -- Nummer entspricht dem Karten-Hotspot, mit Koordinaten lässt sich
        -- der Punkt im Spiel finden und neu setzen.
        local pos = self:getWaypointPosText(idx)
        print("LivingRoads: [TRAFFIC] WP" .. tostring(idx) .. pos ..
            " fuer diese Session als Ziel gesperrt (2x nicht erreichbar)")
        -- alle gesperrten Ziele in einer Logzeile
        local list = {}
        for i, c in pairs(self.wpFails) do
            if c >= 2 then table.insert(list, i) end
        end
        table.sort(list)
        local names = {}
        for _, i in ipairs(list) do table.insert(names, "WP" .. tostring(i)) end
        print("LivingRoads: [TRAFFIC] Aktuell gesperrte Ziele: " .. table.concat(names, ", "))
    end
end

function NachbarFelderManager:isWaypointBlocked(idx)
    return self.wpFails ~= nil and idx ~= nil and (self.wpFails[idx] or 0) >= 2
end

-- ============================================================
-- Wegpunkt als Startplatz
-- Ein Punkt kann als Ziel funktionieren und als Startplatz trotzdem nicht:
-- Die KI hält beim GOTO in der Nähe des Ziels auf befahrbarem Grund. Liegt
-- die Koordinate ein paar Meter daneben (z. B. zu Fuß am Straßenrand gesetzt),
-- steht das Fahrzeug nach dem Einschnappen abseits des Navmesh und der
-- nächste GOTO wird nach rund 60 ms abgewiesen. Darum getrennt von der
-- Ziel-Sperre geführt, der Punkt bleibt anfahrbar.
-- ============================================================
function NachbarFelderManager:registerWaypointStartFail(idx)
    if idx == nil then return end
    self.wpStartFails = self.wpStartFails or {}
    self.wpStartFails[idx] = (self.wpStartFails[idx] or 0) + 1
    if self.wpStartFails[idx] == 2 then
        local pos = self:getWaypointPosText(idx)
        print("LivingRoads: [TRAFFIC] WP" .. tostring(idx) .. pos ..
            " taugt nicht als Startplatz - dort halten keine Fahrzeuge mehr" ..
            (self:getIsEigenerWaypoint(idx)
                and " (Tipp: den Punkt aus dem fahrenden Fahrzeug mitten auf der Strasse neu setzen)."
                or  " (Strassenziel aus dem KI-Netz, nichts zu tun)."))
    end
end

function NachbarFelderManager:isWaypointBadStart(idx)
    return self.wpStartFails ~= nil and idx ~= nil and (self.wpStartFails[idx] or 0) >= 2
end


--- Nächster freier Parkpunkt für ein Patrol-Fahrzeug. Parkpunkte sind die
--- selbst gesetzten Wegpunkte (1 bis #userTrafficWaypoints). Steht das Fahrzeug
--- schon an einem (< 25 m), kommt nil zurück und es parkt dort.
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
           and not self:getIstSpawnpunkt(wp)   -- nie auf dem Spawnpunkt parken
           and not self:isWpPosOccupied(wp[1], wp[2])
           and not self:isSpotBlockedByAnyVehicle(wp[1], wp[2], 10, veh) then
            best, bestD = i, d
        end
    end
    return best
end

-- Bevorzugte Hop-Länge in m. Ziele quer über die Karte brauchen über eine Minute
-- Wegsuche und scheitern oft trotzdem, kurze Strecken sind in Sekunden geplant.
local NF_HOP_MIN_M = 150
local NF_HOP_MAX_M = 700

--- Zufälliges Fahrziel; meidet gesperrte Punkte, Spawnpunkte, excludeIdx und belegte Plätze.
--- Für beide Formen: {x=,z=} (userTrafficWaypoints) und {[1]=x,[2]=z} (worker.waypoints).
--- @param refX number|nil, refZ number|nil Bezugspunkt für die Hop-Länge;
--- ohne Angabe gilt der Wegpunkt excludeIdx (= letztes Ziel) als Bezug.
function NachbarFelderManager:pickPatrolWaypoint(waypoints, excludeIdx, refX, refZ)
    local n = waypoints ~= nil and #waypoints or 0
    if n < 1 then return nil end
    if n == 1 then return 1 end

    -- Erst ein Ziel im Hop-Bereich suchen, sonst Zufall über die ganze Liste.
    if refX == nil and excludeIdx ~= nil and waypoints[excludeIdx] ~= nil then
        local ref = waypoints[excludeIdx]
        refX, refZ = ref.x or ref[1], ref.z or ref[2]
    end
    if refX ~= nil and refZ ~= nil then
        local nah = {}
        for i = 1, n do
            -- Spawnpunkte nie als Ziel, sonst parkt dort jemand
            if i ~= excludeIdx and not self:isWaypointBlocked(i)
               and not self:isWaypointBadStart(i)
               and not self:getIstSpawnpunkt(waypoints[i]) then
                local wp = waypoints[i]
                local wx, wz = wp.x or wp[1], wp.z or wp[2]
                if wx ~= nil and wz ~= nil then
                    local d = MathUtil.vector2Length(wx - refX, wz - refZ)
                    -- isWpPosOccupied kennt nur schlafende Pool-Fahrzeuge. Ein gerade
                    -- parkendes Fahrzeug fängt erst isSpotBlockedByAnyVehicle ab, sonst
                    -- bekommt der Nächste denselben Punkt und bleibt davor stehen.
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
    -- Als Startplatz untaugliche Punkte auch als Ziel meiden: Fahrzeuge kommen
    -- dort an, aber nicht mehr weg. Nach 30 Versuchen gilt der letzte Zufallspunkt,
    -- lieber ein schlechtes Ziel als gar keine Fahrt.
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
-- Server-Konfiguration: modSettings/FS25_LivingRoads/NachbarFelderServerConfig.xml
-- Auf dem Dedicated Server gibt es keine Settings-GUI, dort gilt diese Datei.
-- Fehlt sie, wird eine Vorlage mit den Standardwerten angelegt
-- (bearbeiten, dann Server neu starten).
-- ============================================================
function NachbarFelderManager:loadServerConfig()
    if self.serverConfigLoaded then return end
    self.serverConfigLoaded = true
    local function schritt()
        local dir  = modSettingDirectory
        createFolder(dir)
        local path = NachbarFelderLesePfad(dir .. "NachbarFelderServerConfig.xml")
        local root = "nachbarFelder"
        print("LivingRoads: Server-Konfig-Pfad: " .. tostring(path))
        if not fileExists(path) then
            local xf = createXMLFile("nfConfig", path, root)
            if xf ~= nil and xf ~= 0 then
                local c = self.vehicleCatEnabled or {}
                setXMLString(xf, root .. ".hinweis",
                    "Serverseitige Einstellungen fuer FS25_LivingRoads - wirken nach einem Server-Neustart")
                setXMLInt(xf, root .. ".farmId",              0)   -- 0 = automatisch (leere Farm ohne Spieler)
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
                setXMLInt(xf, root .. ".aufraeumenMinTage",       NachbarFelderManager.AUFRAEUMEN_MIN_TAGE)
                setXMLBool(xf, root .. ".fahrerfigurenAufServer", true)
                setXMLBool(xf, root .. ".rueckwaertsPlanen",      false)
                setXMLBool(xf, root .. ".spielverkehrAnmelden",   true)
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
                print("LivingRoads: Konfig-Vorlage angelegt: " .. path)
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
        -- 1 = normal, 2 = Debug-Log (die Einstellung im Spiel hat Vorrang)
        self.logLevel              = readInt("logLevel",           1, 1, 2)
        self:setDebugLog(self.logLevel >= 2)
        -- 0 = automatisch, siehe getEffectiveFarmId
        self.cfgFarmId             = readInt("farmId",             0, 0, 16)
        if self.patrolHopsMax < self.patrolHopsMin then
            self.patrolHopsMax = self.patrolHopsMin
        end
        -- Spawns verteilen, sonst ruckelt es: Fahrzeuge pro Tick und Pause dazwischen
        -- in Minuten (mit dem Zeitfaktor skaliert, also etwa Echtzeit)
        self.spawnPerTick     = readInt("spawnPerTick",            1, 1, 3)
        self.spawnIntervalMin = readInt("spawnIntervalMinMinutes", 2, 0, 60)
        self.spawnIntervalMax = readInt("spawnIntervalMaxMinutes", 5, 1, 120)
        if self.spawnIntervalMax < self.spawnIntervalMin then
            self.spawnIntervalMax = self.spawnIntervalMin
        end
        -- 1.0 = Standard, 2.0 = doppelt so lange Parkpausen
        local ptf = getXMLFloat(xf, root .. ".parkTimeFactor")
        if ptf ~= nil and ptf >= 0.2 and ptf <= 10 then
            self.parkTimeFactor = ptf
        end
        self.poolSize = readInt("poolSize", self.poolSize or 6, 0, 12)
        -- Mindestabstand in Spieltagen für das Aufräumen beim Monatswechsel, 0 = nie
        self.aufraeumenMinTage = readInt("aufraeumenMinTage", NachbarFelderManager.AUFRAEUMEN_MIN_TAGE, 0, 365)
        local dr = getXMLBool(xf, root .. ".dayRhythm")
        if dr ~= nil then self.dayRhythm = dr end
        -- Fahrziele: "strassen" = KI-Straßennetz der Karte (Standard),
        -- "wegpunkte" = nur die selbst gesetzten Punkte
        local zq = getXMLString(xf, root .. ".zielQuelle")
        if zq ~= nil then
            zq = string.lower(zq)
            if zq == "strassen" or zq == "wegpunkte" then
                self.zielQuelle = zq
            end
        end
        self.trailerChance = readInt("trailerChance", self.trailerChance or 40, 0, 100)
        -- Fahrzeugkategorien: Stehen sie schon in der Wegpunkt-Datei (in der GUI
        -- gesetzt), haben diese Vorrang, sonst ginge die GUI-Wahl beim Neustart verloren.
        local function readBool(key, cur)
            local v = getXMLBool(xf, root .. "." .. key)
            if v == nil then return cur end
            return v
        end
        -- Umkreis um den Händler, der vor einem Spawn frei sein muss
        self.spawnBereichRadius = readInt("spawnBereichRadius",
            self.spawnBereichRadius or 25, 0, 200)

        -- false nur auf einem Dedicated Server: auf einem Spieler-Host säßen
        -- für diesen Spieler sonst keine Fahrer in den Fahrzeugen.
        self.fahrerfigurenAufServer = readBool("fahrerfigurenAufServer",
            self.fahrerfigurenAufServer ~= false)

        -- Rückwärtsplanen, nur für Fahrzeuge ohne Anbaugerät
        self.rueckwaertsPlanen = readBool("rueckwaertsPlanen", self.rueckwaertsPlanen ~= false)

        self.spielverkehrAnmelden = readBool("spielverkehrAnmelden", self.spielverkehrAnmelden ~= false)

        -- Enge Karte: schmale Wege, nur Kleintraktoren mit leichtem Gerät
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
            self.trafficVehicleList = nil  -- mit den neuen Kategorien neu aufbauen
        else
            print("LivingRoads: Server-Konfig vehicles.* ignoriert - " ..
                "In-Game-Kategorien aus der Wegpunkt-Datei sind aktiv")
        end
        delete(xf)
        -- Eigenes c, das obige existiert nur im vehicles.*-Zweig
        local c = self.vehicleCatEnabled or {}
        print("LivingRoads: Server-Konfig geladen: maxWorkers=" ..
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
            " aufraeumenMinTage=" .. tostring(self.aufraeumenMinTage or NachbarFelderManager.AUFRAEUMEN_MIN_TAGE) ..
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
    print("LivingRoads: Hooks werden installiert")

    -- Bewusst keine FarmlandManager-Hooks (getIsOwnedByFarmAtWorldPosition usw.): der
    -- GOTO-Weg fragt sie nicht ab, sie wirken nur bei Feldarbeit, Leveler, Platzieren und
    -- WheelDestruction - dort wuerden die Raeder der Nachbarn sonst Pflanzen zerstoeren.

    -- getJobTypeIndex kann nil liefern; dann ueber den Jobnamen nachschlagen
    AIJobTypeManager.getJobTypeIndex = Utils.overwrittenFunction(
        AIJobTypeManager.getJobTypeIndex,
        function(aiJobTypeManager, superFunc, job)
            local ret = superFunc(aiJobTypeManager, job)
            if ret == nil and job ~= nil and job.name then
                return aiJobTypeManager.nameToIndex[job.name]
            end
            return ret
        end)

    -- Kein Geldabzug fuer die Helfer-Farm, solange Nachbar-Fahrzeuge unterwegs sind: KI-Lohn
    -- und Sprit liefen sonst als Minus auf ihrem Konto auf (im MP in der Farmuebersicht sichtbar).
    if FSBaseMission ~= nil and FSBaseMission.addMoney ~= nil then
        FSBaseMission.addMoney = Utils.overwrittenFunction(FSBaseMission.addMoney,
            function(mission, superFunc, amount, farmId, moneyType, ...)
                if g_NachbarFelderManager ~= nil
                   and amount ~= nil and amount < 0
                   and farmId == g_NachbarFelderManager.farmId
                   and g_NachbarFelderManager:getHatFahrzeugeUnterwegs() then
                    return
                end
                return superFunc(mission, amount, farmId, moneyType, ...)
            end)
    end

    -- Beim Spielende nur die KI-Jobs stoppen. Die Fahrzeuge loescht BaseMission.delete
    -- selbst; ein eigenes vehicle:delete() hier fuehrt zu doppeltem Loeschen (Vehicle.lua).
    FSBaseMission.delete = Utils.overwrittenFunction(FSBaseMission.delete,
        function(mission, superFunc, ...)
            if g_NachbarFelderManager ~= nil then
                g_NachbarFelderManager.isShuttingDown = true
                g_NachbarFelderManager:prepareForShutdown()
            end
            return superFunc(mission, ...)
        end)

    ItemSystem.save = Utils.prependedFunction(ItemSystem.save, g_NachbarFelderManager.saveToXMLFile)
end

-- ============================================================
-- loadMap: laeuft auf Server und Client (addModEventListener sitzt
-- schon in init() von NachbarFelder.lua, daher auch auf dem Dedi)
-- ============================================================
function NachbarFelderManager:loadMap()
    print("LivingRoads: loadMap auf " ..
        (g_currentMission:getIsServer() and "SERVER" or "CLIENT") ..
        " (Build " .. tostring(NachbarFelderManager.BUILD) .. ")")

    -- Einstellungsseite nur mit Spieler (Client oder SP)
    if not g_currentMission:getIsServer() or g_currentMission.isMasterUser then
        if misssionSettingsPage == nil then
            misssionSettingsPage = NachbarFelderSettingsPage.new(self)
            misssionSettingsPage:init()
            self.settingsPage = misssionSettingsPage
        end
    end

    self:addConsoleCommands()

    self:ladeHilfe()
    self:installKartenHook()

    -- Client-lokale Anzeige-Einstellungen (Karten-Hotspots an/aus)
    self:loadClientPrefs()

    -- Client braucht die Wegpunkte fuer UI und Kartenmarker, der Server fuer den Verkehr
    self:loadWaypoints()

    if g_currentMission:getIsServer() then
        self:serverSideInit()
        -- Server-Konfig schon beim Start laden bzw. anlegen, sonst entsteht die Vorlage
        -- nie, solange niemand joint. Nach loadWaypoints, damit die Konfig-Kategorien
        -- die Werte aus der Wegpunkt-Datei ueberschreiben.
        self:loadServerConfig()
        -- Einstellungen aus dem Savegame zuletzt: sie schlagen die Konfig-Datei,
        -- die nur die Grundwerte liefert.
        if self.savegameSettings ~= nil then
            self:applySettingsState(self.savegameSettings)
            self.settingsFromSavegame = true
            self.savegameSettings = nil
            print("LivingRoads: [SETTINGS] Einstellungen aus dem Savegame angewendet")
        end
    end
end

--- Helfer-Farm fuer die Anzeige: Server = eigene Wahl, Client = per Settings-Sync.
--- @return number farmId, 0 bei unbekannt oder Spectator (dann wird nichts ausgeblendet)
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

--- Gehoert der Karten-Hotspot zu einem Nachbar-Fahrzeug?
--- Kennzeichen: Besitzer-Farm des (Zug-)Fahrzeugs = Helfer-Farm. Die Helfer-Farm hat
--- nie Spieler, andere Fahrzeuge trifft das also nicht.
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

--- Blendet das Helfer-Symbol der Nachbar-Fahrzeuge auf Minimap und grosser Karte aus,
--- damit sie nicht mit eigenen Helfern verwechselt werden. Beide Karten zeichnen ueber
--- IngameMap:drawHotspot (auch IngameMapElement:drawHotspotsOnly). Nur mit Client, einmalig.
function NachbarFelderManager:installKartenHook()
    if NachbarFelderManager.kartenHookInstalliert or g_client == nil then return end
    if IngameMap == nil or IngameMap.drawHotspot == nil then
        print("LivingRoads: Karten-Symbole bleiben sichtbar (IngameMap.drawHotspot fehlt)")
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
    print("LivingRoads: Helfer-Symbole der Nachbar-Fahrzeuge auf der Karte ausgeblendet")
end

--- Eigene Kategorie in der Ingame-Hilfe (ESC > Hilfe). HelpLineManager:loadFromXML liest
--- <helpLines>/<category>/<page> wie bei der Spielhilfe (so macht es auch Courseplay);
--- die $l10n_-Texte kommen aus der modDesc. Nur mit Client, einmal je Sitzung.
function NachbarFelderManager:ladeHilfe()
    if self.hilfeGeladen or g_client == nil then return end
    self.hilfeGeladen = true
    local dir = NachbarFelderManager.modDirectory
    if dir == nil or g_helpLineManager == nil or g_helpLineManager.loadFromXML == nil then
        print("LivingRoads: Ingame-Hilfe nicht geladen (HelpLineManager nicht verfuegbar)")
        return
    end
    if g_helpLineManager ~= nil and g_helpLineManager.loadFromXML ~= nil then
        g_helpLineManager:loadFromXML(Utils.getFilename("help/helpLine.xml", dir))
        self:setzeHilfeSymbole(dir)
        print("LivingRoads: Ingame-Hilfe geladen (ESC > Hilfe > Lebendige Strassen)")
    else
        print("LivingRoads: Ingame-Hilfe konnte nicht geladen werden (Hilfe-Manager fehlt)")
    end
end

--- Symbole fuer die Seitenliste der Ingame-Hilfe.
--- Die Liste zeigt je Seite page.iconSliceId (BitmapElement:setImageSlice ->
--- OverlayManager:getSliceInfoById); ohne Wert bleibt das Feld dunkel. Der Atlas
--- help/hilfe_icons.dds wird per addTextureConfigFile unter "nfHilfe" angemeldet
--- (wie Courseplay "cpIconSprite"). Gesetzt wird nur in unserer Kategorie und nur,
--- wo noch nichts eingetragen ist.
NachbarFelderManager.HILFE_SYMBOLE = {
    "nfHilfe.ueberblick", "nfHilfe.wegpunkte", "nfHilfe.einstellungen",
    "nfHilfe.tasten", "nfHilfe.verkehr",
}
function NachbarFelderManager:setzeHilfeSymbole(dir)
    local hm = g_helpLineManager
    if dir == nil or hm == nil or hm.getCategories == nil
       or g_overlayManager == nil or g_overlayManager.addTextureConfigFile == nil then
        return
    end
    local configs = g_overlayManager.textureConfigs
    if configs == nil or configs["nfHilfe"] == nil then
        g_overlayManager:addTextureConfigFile(Utils.getFilename("help/hilfe_icons.xml", dir), "nfHilfe")
    end
    -- Nur Umgebungsnamen, die das Spiel selbst liefert; wie sich getCategories bei
    -- fremden Namen verhaelt, ist nicht belegt. Unsere Mod zuerst.
    if hm.getCustomEnvironmentNames == nil then return end
    local umgebungen = {}
    for _, name in ipairs(hm:getCustomEnvironmentNames() or {}) do
        if name == modName then
            table.insert(umgebungen, 1, name)
        else
            table.insert(umgebungen, name)
        end
    end
    local titel = g_i18n ~= nil and g_i18n.getText ~= nil and g_i18n:getText("NF_help_title") or nil
    local gefunden = false
    for _, env in ipairs(umgebungen) do
        for _, kat in ipairs(hm:getCategories(env) or {}) do
            if type(kat) == "table" and (kat.title == "$l10n_NF_help_title" or (titel ~= nil and kat.title == titel)) and type(kat.pages) == "table" then
                gefunden = true
                for i, seite in ipairs(kat.pages) do
                    local sym = NachbarFelderManager.HILFE_SYMBOLE[i]
                    if type(seite) == "table" and sym ~= nil and seite.iconSliceId == nil then
                        seite.iconSliceId = sym
                    end
                end
            end
        end
        if gefunden then break end
    end
    if not gefunden then
        print("LivingRoads: Hilfe-Symbole fehlgeschlagen (Kategorie nicht gefunden)")
    end
end

-- ============================================================
-- Server-Initialisierung (einmalig, mit Guard)
-- ============================================================
function NachbarFelderManager:serverSideInit()
    if self.serverInitialized then return end
    self.serverInitialized = true
    print("LivingRoads: Server-Initialisierung gestartet")

    self:installHooks()
    self:selectBestSpawnPlace()

    -- Mehr Helfer-Plaetze, damit die Nachbarn die Spieler-Helfer nicht blockieren
    if g_currentMission.maxNumHirables ~= nil then
        g_currentMission.maxNumHirables = g_currentMission.maxNumHirables + 20
    end

    -- Savegame-Einstellungen nur lesen, angewendet werden sie in loadMap
    self:loadFromXML()
    self:updateWpHotspots()

    local timeScale = g_currentMission:getEffectiveTimeScale()
    self.timeToNextStart = math.random(1 * timeScale, 2 * timeScale)

    g_messageCenter:unsubscribe(MessageType.MINUTE_CHANGED, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)

    -- Aufgeraeumt wird beim Monatswechsel erst nach AUFRAEUMEN_MIN_TAGE Spieltagen, sonst
    -- wuerde bei "1 Tag pro Monat" jeden Spieltag alles geloescht.
    g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.onPeriodChanged, self)
    self.aufraeumTag = self:getSpieltag()

    -- Admin-Logins merken, Grundlage fuer den Admin-Check bei Events
    if MessageType ~= nil and MessageType.MASTERUSER_ADDED ~= nil then
        g_messageCenter:unsubscribe(MessageType.MASTERUSER_ADDED, self)
        g_messageCenter:subscribe(MessageType.MASTERUSER_ADDED, self.onMasterUserAdded, self)
    end

    -- Mission00.addPlayer ist auf dem Dedi unzuverlaessig; gezaehlt wird in onMinuteChanged.
    -- removePlayer wird gehookt, um beim letzten Spieler sofort alle Helfer zu stoppen.
    if g_currentMission.playerSystem ~= nil and g_currentMission.playerSystem.removePlayer ~= nil then
        -- overwritten statt appended: stopAllHelpers muss laufen, bevor removePlayer die
        -- Spielerdaten abraeumt, sonst sind die Agents schon ungueltig (deleteAgent auf nil).
        g_currentMission.playerSystem.removePlayer = Utils.overwrittenFunction(
            g_currentMission.playerSystem.removePlayer,
            function(ps, superFunc, player)
                if g_NachbarFelderManager ~= nil and g_currentMission:getIsServer() then
                    local remaining = 0
                    if ps.players ~= nil then
                        for _, p in pairs(ps.players) do
                            if p ~= nil and p ~= player and (p.farmId or 0) > 0 then
                                remaining = remaining + 1
                            end
                        end
                    end
                    if remaining <= 0 then
                        print("LivingRoads: Letzter Spieler weg - stoppe alle Helfer")
                        g_NachbarFelderManager:stopAllHelpers()
                    end
                end
                superFunc(ps, player)
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

    print("LivingRoads: Server bereit. Naechster Start in " .. tostring(self.timeToNextStart) .. " Minuten")
end

-- ============================================================
-- prepareForShutdown: nur KI-Jobs stoppen. Die Fahrzeuge loescht die
-- Engine direkt danach selbst (sonst "delete twice").
-- ============================================================
function NachbarFelderManager:prepareForShutdown()
    for fieldId, k in pairs(self.vehicleType or {}) do
        for _, veh in ipairs(k.vehicleType or {}) do
            if self:getIsVehicleAlive(veh) then
                self:stopAIJobSafely(veh)
            end
            self:meldeBeimSpielverkehrAb(veh)   -- solange das Verkehrssystem noch existiert
        end
    end
    for _, p in ipairs(self.trafficPool or {}) do
        for _, veh in ipairs(p.vehicles or p.vehicleType or {}) do
            self:meldeBeimSpielverkehrAb(veh)
        end
    end
    print("LivingRoads: Shutdown - AI-Jobs gestoppt, Fahrzeuge raeumt die Engine auf")
end

-- ============================================================
-- stopAllHelpers: alle Helfer stoppen und entfernen, wenn der letzte
-- Spieler den Server verlaesst.
-- ============================================================
function NachbarFelderManager:stopAllHelpers()
    if not g_currentMission:getIsServer() then return end
    self:deleteAllVehicles()
    -- Ohne Spieler kein Respawn; nach dem naechsten Login startet der Timer neu
    self.pendingRespawns = {}
    local timeScale = (g_currentMission and g_currentMission:getEffectiveTimeScale()) or 1
    self.timeToNextStart = math.random(1 * timeScale, 4 * timeScale)
    -- Nach dem Login laufen erst 3 Min Echtzeit-Ladepause, dann timeToNextStart
    print(string.format(
        "LivingRoads: Alle Helfer gestoppt (kein Spieler online). Erster Spawn ca. %d Min " ..
        "nach Spieler-Login (3 Min Echtzeit-Pause + %d Min Timer)",
        self.timeToNextStart + 3, self.timeToNextStart))
end

-- ============================================================
-- Wegpunkt an der Spielerposition setzen (nur Admin)
-- Taste "LivingRoads: Wegpunkt setzen" (Standard Strg+Alt+O) und die Buttons
-- im Reiter Wegpunkte. Gespeichert in der Wegpunkt-Datei der Karte.
-- ============================================================
function NachbarFelderManager:onInputAddWaypoint(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    self:addWaypointAtPlayer(0)
end

--- Neuen Punkt an der Position des lokalen Spielers setzen (MP-Client: an den Server senden).
--- @param cat number 0 = normaler Wegpunkt, WP_CAT_SPAWN = Spawnpunkt
--- @return boolean true, wenn gesetzt bzw. an den Server gesendet
--- @return string|nil Grund, wenn nicht gesetzt (fuer die Anzeige im Menue, das
---                    Ingame-Meldungen verdeckt)
function NachbarFelderManager:addWaypointAtPlayer(cat)
    local istSpawn = cat == NachbarFelderManager.WP_CAT_SPAWN
    if not istSpawn then cat = 0 end
    local art = nfText(istSpawn and "NF_wpArt_spawn" or "NF_wpArt_wegpunkt")
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return false, "Nur fuer Admins"
    end
    print("LivingRoads: [WP] " .. art .. " setzen ausgeloest")
    local x, y, z, ry
    -- Position und Richtung wie in AISystem.lua: im Fahrzeug rootNode + Vorwaertsvektor,
    -- zu Fuss getMapPositionAndLookYaw, sonst die Kamera. FS25 liefert das Fahrzeug nur
    -- ueber getCurrentVehicle(), currentVehicle/controlledVehicle gibt es nicht mehr.
    -- Fuer Spawnpunkte zaehlt die Richtung. ry wie in waehleSpawnpunkt: dx = sin(ry), dz = cos(ry).
    local richtungQuelle = nil
    local player = self.localPlayer or g_localPlayer
    if player ~= nil then
        -- 1. Fahrzeug, in dem der Spieler sitzt: Fahrtrichtung
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
                -- Vorwaertsvektor statt Euler-Y: am Hang kann getWorldRotation das Y
                -- um 180 Grad kippen (die x/z-Rotation gleicht es aus).
                local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
                if math.abs(dx) > 0.001 or math.abs(dz) > 0.001 then
                    ry = math.atan2(dx, dz)
                    richtungQuelle = "NF_richtung_fahrzeug"
                end
            end
        end
        -- 2. Zu Fuss: Spielerposition und Blickrichtung
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
        -- 2b. Spieler-rootNode: nur Position, seine Drehung ist immer 0
        if x == nil and player.rootNode ~= nil and player.rootNode ~= 0 then
            local px, py, pz = getWorldTranslation(player.rootNode)
            if math.abs(px) > 1 or math.abs(pz) > 1 then
                x, y, z = px, py, pz
            end
        end
    end
    -- 3. Kamera: ist immer in der Welt positioniert, daher der sicherste Fallback
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
        print("LivingRoads: [WP] Position nicht verfuegbar")
        return false, "Position nicht verfuegbar"
    end
    -- Richtung noch offen (Fall 2b/3): Blickrichtung der Kamera, die entlang -Z schaut
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
    print(string.format("LivingRoads: [WP] Position x=%d z=%d, %s (%.0f Grad)",
        x, z, richtungText, math.deg(ry) % 360))
    local MIN_DIST = 10   -- m, Mindestabstand zum naechsten Wegpunkt
    self.userTrafficWaypoints = self.userTrafficWaypoints or {}
    for i, wp in ipairs(self.userTrafficWaypoints) do
        local dist = math.sqrt((x - wp.x)^2 + (z - wp.z)^2)
        if dist < MIN_DIST then
            local grund = nfText("NF_msg_zuNah", i, dist)
            print("LivingRoads: [TRAFFIC] " .. art .. " - " .. grund)
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
    -- MP-Client: Aenderung an den Server schicken, der speichert und zurueck synct
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
    print(string.format("LivingRoads: [TRAFFIC] %s %d gesetzt x=%d z=%d Richtung %.0f Grad",
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
-- Taste "Wegpunkte nacheinander anzeigen": jeder Druck zeigt den naechsten
-- WP als Meldung. Teleportieren, Loeschen und Typ gibt es im Reiter Wegpunkte.
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
    print("LivingRoads: [MGR] Teleport x=" .. math.floor(x) .. " z=" .. math.floor(z))
end

-- ============================================================
-- Letzten Wegpunkt entfernen (Taste, nur Admin)
-- ============================================================
function NachbarFelderManager:onInputRemoveWaypoint(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return
    end
    if #self.userTrafficWaypoints == 0 then
        print("LivingRoads: [TRAFFIC] Keine Wegpunkte vorhanden")
        return
    end
    -- MP-Client: Loeschen beim Server anfragen
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
    print("LivingRoads: [TRAFFIC] Wegpunkt entfernt (x=" .. tostring(removed.x) ..
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
-- Wegpunkt-Aenderung vom Client (NachbarFelderWaypointEditEvent), nur Server.
-- saveWaypoints() schreibt die Datei und verteilt die Liste an alle Clients.
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
        local cat = (op == E.OP_ADD_SPAWN) and NachbarFelderManager.WP_CAT_SPAWN or 0
        local art = (cat == NachbarFelderManager.WP_CAT_SPAWN) and "Spawnpunkt" or "Wegpunkt"
        for i, wp in ipairs(self.userTrafficWaypoints) do
            local dist = math.sqrt((x - wp.x)^2 + (z - wp.z)^2)
            if dist < 10 then
                print("LivingRoads: [TRAFFIC] " .. art .. " verworfen - nur " ..
                    tostring(math.floor(dist)) .. "m von WP" .. tostring(i))
                return
            end
        end
        table.insert(self.userTrafficWaypoints, { x=x, z=z, ry=ry, cat=cat, label="" })
        print(string.format("LivingRoads: [TRAFFIC] %s %d gesetzt (Client-Event) x=%d z=%d Richtung %.0f Grad",
            art, #self.userTrafficWaypoints, x, z, math.deg(ry) % 360))
    elseif op == E.OP_REMOVELAST then
        if #self.userTrafficWaypoints == 0 then return end
        local removed = table.remove(self.userTrafficWaypoints)
        print("LivingRoads: [TRAFFIC] Wegpunkt entfernt (Client-Event) x=" ..
            tostring(removed.x) .. " z=" .. tostring(removed.z) ..
            ". Verbleibend: " .. tostring(#self.userTrafficWaypoints))
    elseif op == E.OP_DELETE then
        local idx = math.floor((a or 0) + 0.5)
        if self.userTrafficWaypoints[idx] == nil then return end
        table.remove(self.userTrafficWaypoints, idx)
        print("LivingRoads: [TRAFFIC] WP" .. tostring(idx) ..
            " geloescht (Client-Event). Verbleibend: " .. tostring(#self.userTrafficWaypoints))
    elseif op == E.OP_SETCAT then
        local idx = math.floor((a or 0) + 0.5)
        local wp  = self.userTrafficWaypoints[idx]
        if wp == nil then return end
        -- Erlaubt: 0 Normal, 1 Kurz, 2 Lang, 4 Spawnpunkt
        local c = math.floor((b or 0) + 0.5)
        if c ~= 1 and c ~= 2 and c ~= NachbarFelderManager.WP_CAT_SPAWN then c = 0 end
        wp.cat = c
        if c == NachbarFelderManager.WP_CAT_SPAWN then
            print(string.format("LivingRoads: [TRAFFIC] WP%d ist jetzt Spawnpunkt (x=%d z=%d)",
                idx, math.floor(wp.x or 0), math.floor(wp.z or 0)))
        end
    elseif op == E.OP_VEHCAT then
        local key = NachbarFelderManager.VEHCAT_KEYS[math.floor((a or 0) + 0.5)]
        if key == nil then return end
        self.vehicleCatEnabled = self.vehicleCatEnabled or {}
        self.vehicleCatEnabled[key] = ((b or 0) >= 0.5)
        self.trafficVehicleList = nil
        print("LivingRoads: [TRAFFIC] Fahrzeugkategorie " .. key .. " = " ..
            tostring(self.vehicleCatEnabled[key]) .. " (Client-Event)")
    else
        return
    end
    self:saveWaypoints()
    self:updateWpHotspots()
end

-- ============================================================
-- Shop-Spawnplatz bestimmen und loggen
-- ============================================================
function NachbarFelderManager:selectBestSpawnPlace()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces
    if sp == nil or #sp == 0 then
        print("LivingRoads: Keine storeSpawnPlaces gefunden!")
        return
    end

    self.spawnPlaceIndex = 1
    local best = self:getNfSpawnPlace() or sp[1]
    print("LivingRoads: Shop-Spawn [1] x=" ..
        tostring(math.floor(best.startX or 0)) ..
        " z=" .. tostring(math.floor(best.startZ or 0)) ..
        " (" .. tostring(#sp) .. " Punkte)")
end

--- Spawnplatz der NachbarFelder-Fahrzeuge: derselbe Shop-Spawnplatz, den das
--- Spiel fuer gekaufte Fahrzeuge nimmt (mit "Filiallieferungen" also der
--- Lieferort). Vom Lieferort kommt die KI zuverlaessiger los als vom
--- Original-Shop. Bewusst live gelesen, damit ein geaenderter Lieferort sofort gilt.
function NachbarFelderManager:getNfSpawnPlace()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces
    return sp and sp[1] or nil
end

--- Spawnplatz-Liste fuer VehicleLoadingData:setLoadingPlace(), unveraendert vom Spiel.
--- Der tatsaechliche Platz wird beim ersten Spawn einmal geloggt: bei Serverstart
--- hat Filiallieferungen ihn evtl. noch nicht verschoben.
function NachbarFelderManager:getNfSpawnPlaces()
    local sp = g_currentMission and g_currentMission.storeSpawnPlaces or {}
    if not self.spawnPlatzGemeldet and sp[1] ~= nil then
        self.spawnPlatzGemeldet = true
        print(string.format("LivingRoads: Spawn am Shop-Platz des Spiels x=%.0f z=%.0f",
            sp[1].startX or 0, sp[1].startZ or 0))
    end
    return sp
end

--- Strassenrichtung aus den KI-Strassensplines der Karte.
---
--- Der GOTO-Job braucht eine Zielrichtung (AIParameterPositionAngle:validate lehnt
--- ohne Winkel ab), und die KI rangiert am Ziel, bis sie genau so steht
--- (AITaskDriveTo -> setAITarget mit dirX/dirZ). Die beim Setzen des Wegpunkts
--- gespeicherte ry taugt dafuer nicht, wenn er zu Fuss gesetzt wurde.
---
--- Splines unter einem onCreateAIRoadSpline-Knoten landen auf dem Server in
--- aiSystem.roadSplines (AISystem.lua:217-236); getSplinePosition liefert
--- Weltkoordinaten. Abgetastet wird alle 4 m, abgelegt in einem 32-m-Raster,
--- damit eine Abfrage nur die Nachbarzellen prueft.
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
            local px, py, pz = getSplinePosition(spline, 0)
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

    -- Abdeckung gleich mitloggen: Wegpunkte ohne KI-Strasse im Umkreis parken
    -- mit ihrer gespeicherten Richtung.
    local ohne, mit = {}, 0
    for i, wp in ipairs(self.userTrafficWaypoints or {}) do
        if self:getRoadHeadingAt(wp.x or 0, wp.z or 0, 20) ~= nil then
            mit = mit + 1
        else
            table.insert(ohne, "WP" .. tostring(i))
        end
    end
    print(string.format("LivingRoads: [TRAFFIC] Strassenrichtung: %d KI-Splines, %d Stuetzpunkte" ..
        " - %d von %d Wegpunkten parken laengs zur Strasse%s",
        #splines, n, mit, #(self.userTrafficWaypoints or {}),
        #ohne > 0 and (" (ohne KI-Strasse im Umkreis 20 m: " .. table.concat(ohne, ", ") .. ")") or ""))

    -- Fahrziele gleich mit erzeugen, solange kein Spieler online ist
    self:buildRoadWaypointList()
    return true
end

--- Fahrziele aus dem KI-Strassennetz erzeugen.
---
--- Handgesetzte Wegpunkte liegen meist neben der Fahrbahn; dort haelt die KI im
--- Seitenstreifen und kommt oft nicht wieder weg. Punkte des Strassennetzes
--- faehrt sie selbst an. Die Stuetzpunkte werden mit Mindestabstand ausgeduennt,
--- damit sich die Ziele ueber die Karte verteilen. Kategorie 3 = Durchfahrt.
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
    print(string.format("LivingRoads: [TRAFFIC] %d Fahrziele aus dem KI-Strassennetz erzeugt" ..
        " (Mindestabstand %d m)", #gewaehlt, MIN_ABSTAND))
    return gewaehlt
end

--- Fahrziel-Liste der Patrol-Fahrzeuge: eigene Wegpunkte zuerst (ihre Nummern
--- bleiben stabil), danach bei zielQuelle="strassen" die Punkte des KI-Strassennetzes.
--- Eigene Punkte behalten ihre Pausen-Kategorie, Strassenziele bekommen
--- Kategorie 3 (Durchfahrt): auf der Fahrbahn wird nie geparkt.
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
    print(string.format("LivingRoads: [TRAFFIC] Fahrziele gesamt: %d (%d eigene Wegpunkte" ..
        " + %d Strassenziele, zielQuelle=%s)",
        #liste, eigene, #liste - eigene, tostring(self.zielQuelle or "strassen")))
    return liste
end

--- Naechster Punkt der KI-Strasse zu (x, z).
---
--- minDist dient der Rettung festsitzender Fahrzeuge: steht eines direkt auf der
--- Strasse und kommt trotzdem nicht los, liegt es am Platz selbst, und der
--- naechstgelegene Punkt hilft nicht weiter.
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
        MathUtil.getYRotationFromDirection(best[3], best[4]), math.sqrt(bestD2), best[5]   -- [5] Fahrbahnhoehe
end

--- Punkt der KI-Strasse mit passender Fahrtrichtung.
---
--- KI-Strassen sind Einbahn-Splines; Gegenverkehr ist eine zweite, umgekehrte
--- Spline daneben (oft mit "R" am Namen). Eine um 180 Grad gedrehte Richtung
--- stuende auf einer Einbahn gegen die Fahrtrichtung. Die KI faehrt nur vorwaerts
--- (AIDrivable:getAIAllowsBackwards = false) und lehnt dann mit
--- AIMessageErrorNotReachable ab.
---
--- Gesucht wird daher der naechste Punkt, dessen Richtung hoechstens 60 Grad von
--- der Wunschrichtung abweicht (bei Gegenverkehr die Zwillingsspur). Gibt es
--- keinen, der naechste Punkt mit seiner eigenen Richtung, nie gedreht.
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

--- Richtung der naechsten KI-Strasse an (x, z).
--- @return number|nil Y-Rotation (wie MathUtil.getYRotationFromDirection), nil ohne Strasse
--- @return number|nil Abstand zur Strasse in m
function NachbarFelderManager:getRoadHeadingAt(x, z, maxDist)
    local _, _, ry, dist = self:getNearestRoadPoint(x, z, maxDist)
    return ry, dist
end

--- Y-Rotation, mit der das Spiel Fahrzeuge auf den Spawnplatz stellt:
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

--- Rueckwaertsplanen fuer ein NF-Fahrzeug erlauben.
---
--- AIDrivable:getAIAllowsBackwards() gibt fest false zurueck (AIDrivable.lua:587),
--- createAgent reicht das an createVehicleNavigationAgent weiter. Ein Fahrzeug, das
--- mit der Front vor einem Hindernis steht, drueckt dann endlos dagegen.
---
--- Spezialisierungsfunktionen sind Instanzfelder (SpecializationUtil.copyTypeFunctionsInto),
--- daher pro Fahrzeug ueberschreibbar. createAgent fragt bei jedem Auftrag neu; mit
--- angehaengtem Geraet bleibt es beim Spielverhalten (Einknickgefahr).
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

--- Fahrerfigur bleibt im Fahrzeug, bis es geloescht wird.
---
--- Das Spiel entlaedt die Figur bei jedem Auftragsende (restoreVehicleCharacter ->
--- deleteVehicleCharacter, wenn niemand drinsitzt) und laedt beim naechsten Start eine
--- neue (setRandomVehicleCharacter -> setVehicleCharacter -> loadCharacter). Nachbar-
--- Fahrzeuge bekommen sehr oft neue Auftraege, das gaebe jedes Mal einen Ruckler.
--- Nach dem ersten Laden werden Loeschen und Neuladen daher uebersprungen, solange
--- kein Spieler drinsitzt. Beim Loeschen des Fahrzeugs raeumt Enterable:onDelete die
--- Figur direkt ab (spec.vehicleCharacter:delete()), es bleibt nichts liegen.
---
--- Laeuft auf Server und Clients; die Clients laden ihre Figur selbst. Mit
--- fahrerfigurenAufServer=false bleibt es auf dem Server beim Weglassen der Figur
--- (applyServerDriverFigure).
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

--- Nachbar-Fahrzeuge (Besitzer = Helfer-Farm) auf Server und Client mit
--- applyFahrerBleibt versehen. Prueft alle 2 s.
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

--- Fahrerfigur eines NF-Fahrzeugs auf dem Server weglassen
--- (nur mit fahrerfigurenAufServer=false).
---
--- Das Spiel laedt die Figur bei jedem KI-Start neu (Enterable:setVehicleCharacter).
--- Auf dem Dedicated Server kostet das Ladezeit am Stueck, die alle Spieler trifft,
--- obwohl dort nichts gezeichnet wird. Die Figur geht nicht uebers Netz
--- (Enterable:onWriteStream schickt keinen Figurenstil), die Clients bauen ihre
--- eigene. Das Ueberschreiben pro Fahrzeug greift auch fuer setRandomVehicleCharacter.
function NachbarFelderManager:applyServerDriverFigure(vehicle)
    if self.fahrerfigurenAufServer ~= false then return end
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if vehicle == nil or vehicle.spec_enterable == nil or vehicle.setVehicleCharacter == nil then return end
    if vehicle.nf_keineFigur then return end
    vehicle.nf_keineFigur = true
    vehicle.setVehicleCharacter = function() end
    if not self.figurHinweisGezeigt then
        self.figurHinweisGezeigt = true
        print("LivingRoads: Fahrerfiguren der NF-Fahrzeuge werden auf dem Server nicht geladen" ..
            " (fahrerfigurenAufServer=false) - bitte pruefen, ob auf den Clients weiter Fahrer sitzen")
    end
end

-- ============================================================
-- registerGlobalActionEvents: Legacy-Hook, bleibt aus Kompatibilität
-- ============================================================
function NachbarFelderManager:registerGlobalActionEvents(player, inputBinding)
    -- leer; Aktionen laufen über addPlayerActionEvents und loadMap
end

-- ============================================================
-- stopAIJobSafely: laufenden KI-Job stoppen, bevor das Fahrzeug
-- gelöscht wird. Sonst bleibt der Job im aiSystem registriert und
-- AIJobFieldWork:stop() wirft jeden Frame "attempt to index nil
-- with 'deleteAgent'".
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
-- 3=Durchfahrt (Strassenziele, kein Parken auf der Fahrbahn)
local NF_CAT_NAMES = { [0]="Normal", [1]="Kurz", [2]="Lang", [3]="Durchfahrt", [4]="Spawnpunkt" }

-- ============================================================
-- Log-Stufen: 1 = normal, 2 = Debug
-- ============================================================
--- Debug-Log an/aus. Steuert NachbarFelderLog.debug und die Log-Stufe:
--- Dauerschreiber (jede Hop-/GOTO-Zeile) erscheinen nur auf Stufe 2. Das spart
--- String-Muell fuer den GC und haelt das Log lesbar. Fehler und Lebenszyklus
--- werden immer geloggt.
function NachbarFelderManager:setDebugLog(an)
    an = an == true
    local vorher = self.debugLog == true
    self.debugLog = an
    self.logLevel = an and 2 or 1
    if NachbarFelderLog ~= nil then
        NachbarFelderLog.debug = an
    end
    if an ~= vorher then
        print("LivingRoads: Debug-Log " .. (an and "an" or "aus"))
    end
end

function NachbarFelderManager:log(lvl, msg)
    if (self.logLevel or 1) >= lvl then
        print(msg)
    end
end

-- Verbundene Spieler zaehlen (farmId > 0 = wirklich im Spiel). Benannte Funktion
-- statt Closure, damit der Sekundentakt in update() keinen GC-Muell erzeugt.
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

-- Mähdrescher-Tank leeren. Benannte Funktion statt Closure pro Aufruf (GC-Müll).
local function nfEmptyCombineTank(veh)
    for idx, fu in ipairs(veh:getFillUnits()) do
        if (fu.fillLevel or 0) > 0 then
            veh:setFillUnitFillLevel(fu.fillUnitIndex or idx, 0, fu.fillType)
        end
    end
end

-- Parkzeiten mit parkTimeFactor aus der Server-Konfig skalieren
-- (z. B. 2.0 = doppelt so lange Pausen, weniger Fahr-/Spawn-Zyklen)
function NachbarFelderManager:scaleParkSecs(secs)
    local f = self.parkTimeFactor or 1
    if f == 1 then return secs end
    return math.max(3, math.floor(secs * f + 0.5))
end

local function nfCatParkSecs(cat)
    -- Strassenziele sind reine Durchfahrt: nur kurz, bis der naechste Auftrag anlaeuft
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
-- update: Telemetrie überall, Statusmaschine nur auf Server (oder SP)
-- ============================================================
function NachbarFelderManager:update(dt)
    -- Ruckler-Diagnose: auffaellig lange Frames zaehlen, auf Server und Client.
    -- Gemessen wird nur mit verbundenen Spielern: der Dedi drosselt im Leerlauf
    -- auf 5 Ticks/s (konstant 200 ms/Frame), das ist keine Last. Die Schwelle ist
    -- adaptiv (> max(100 ms, 2.5x gleitender Schnitt)), damit Wechsel zwischen
    -- Idle- und Aktiv-Tickrate nicht fehlzaehlen.
    if dt ~= nil and dt > 0 then
        if self._dtAvg == nil then
            self._dtAvg = dt
        else
            self._dtAvg = self._dtAvg * 0.98 + dt * 0.02
        end
    end
    -- Fahrerfiguren der Nachbar-Fahrzeuge bleiben sitzen (Server und Client)
    self:pruefeFahrerfiguren()
    -- Strassen-Stuetzpunkte vorberechnen, solange niemand online ist, damit die
    -- einmalige Rechenzeit keinen Spieler trifft. Ohne Splines nur ein Tabellen-Check.
    if self.roadSamples == nil and g_currentMission:getIsServer()
       and (self.playersOnline or 0) == 0 then
        self:buildRoadSamples()
    end
    -- Fahrzeug- und Geraetelisten ebenfalls ohne Spieler bauen: sie lesen pro
    -- Kandidat eine XML-Datei (nfLoadSpecs).
    if self.serverConfigLoaded and g_currentMission:getIsServer()
       and (self.playersOnline or 0) == 0 then
        if self.trafficVehicleList == nil then self:buildTrafficVehicleList() end
        if self.trafficTrailerList == nil then self:buildTrafficTrailerList() end
    end

    local perfActive = true
    if g_currentMission:getIsServer() then
        -- Spieler im Sekundentakt zaehlen: playersOnline wird nur minuetlich
        -- aktualisiert, der Dedi drosselt aber sofort nach dem letzten Disconnect.
        if self._perfPlayersAt == nil or (g_time or 0) >= self._perfPlayersAt then
            self._perfPlayersAt = (g_time or 0) + 1000
            local n = nfCountConnectedPlayers()
            self._perfPlayers = n or (self.playersOnline or 0)
        end
        perfActive = (self._perfPlayers or 0) > 0
    end
    if perfActive then
        -- Schwelle bei 190 ms deckeln: die Engine kappt dt bei 200 ms, eine hoehere
        -- adaptive Schwelle koennte kein Frame mehr ueberschreiten.
        local slowLimit = math.min(190, math.max(100, (self._dtAvg or 0) * 2.5))
        if dt ~= nil and dt > slowLimit then
            self._spkCount = (self._spkCount or 0) + 1
            if dt > (self._spkMax or 0) then self._spkMax = dt end
            -- Kleinste tatsaechlich angewandte Schwelle merken: nur fuer sie gilt
            -- ">Xms" in der Log-Zeile fuer jeden gezaehlten Frame.
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
                    "LivingRoads: [PERF] %d langsame Frames (>%dms) in 10s, max %dms (%s)",
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

    -- Zurückgestellte Kupplungen (needAttachment): die InputAttacher-Joints
    -- sind inzwischen im vehicleSystem registriert.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.needAttachment then
            w.needAttachment = false
            self:setAttachment(k)
        end
    end

    -- Überwachung im 250-ms-Takt statt jeden Frame: geprüft werden nur
    -- Sekunden-Grenzen, Frame-Genauigkeit bringt dort nichts.
    local slowTick = false
    if self._slowNextAt == nil or (g_time or 0) >= self._slowNextAt then
        self._slowNextAt = (g_time or 0) + 250
        slowTick = true
    end

    if slowTick then

    -- Status 9999 nach 90 s löschen (needTimer ist dort false, daher eigener Check)
    for v, k in pairs(self.vehicleType) do
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.status == 9999 then
            if k.NachbarFelderWorker.stuckAt == nil then
                k.NachbarFelderWorker.stuckAt = g_time
            elseif g_time - k.NachbarFelderWorker.stuckAt > 90000 then
                print("LivingRoads: [TRAFFIC] Fahrzeug haengt seit 90 s beim Stoppen - wird entfernt (Eintrag " ..
                    tostring(k.NachbarFelderWorker.fieldId) .. ")")
                k.NachbarFelderWorker.status = 100
                k.NachbarFelderWorker.needTimer = true
            end
        end
    end

    -- Patrol-Park-Timer: geparktes Fahrzeug fährt nach Ablauf weiter.
    -- Läuft außerhalb von needTimer (Patrol hat in Status 2 keinen needTimer).
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.isPatrol and w.status == 2 and w.parkUntil ~= nil then
            if g_time >= w.parkUntil then
                w.parkUntil = nil
                -- Tagesrhythmus: sind mehr Fahrzeuge aktiv, als die Uhrzeit erlaubt,
                -- macht dieses Fahrzeug Feierabend.
                if self:countActivePatrols() > self:getEffectiveTrafficLimit() then
                    w.hopsLeft = 1
                end
                w.hopsLeft  = (w.hopsLeft or 1) - 1
                -- Feierabend nur an einem Parkpunkt, sonst bleibt das Fahrzeug auf der
                -- Strasse im Weg. Vorher einmal zum naechsten freien Parkpunkt fahren.
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
                    print("LivingRoads: [TRAFFIC] Feierabend - faehrt zum Parkpunkt WP" ..
                        tostring(parkZiel) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                    w.status    = 1
                    w.needTimer = true
                elseif w.hopsLeft <= 0 then
                    -- Feierabend: an Ort und Stelle in den Pool. Scheitert das
                    -- (voll/deaktiviert), Heimfahrt bzw. Loeschen.
                    w.patrolWdLastX = nil
                    w.patrolWdStage = nil
                    if self:sleepPatrolEntry(k, true) then
                        -- Eintrag ist bereits entfernt; nichts weiter zu tun
                    else
                        w.status        = 60
                        w.gotoStartedAt = nil
                        w.needTimer     = true
                        print("LivingRoads: [TRAFFIC] Hops erledigt - Heimfahrt (patrolId=" ..
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
                    self:log(2, "LivingRoads: [TRAFFIC] -> WP" .. tostring(newDest) ..
                        " [" .. (NF_CAT_NAMES[newCat] or "?") .. "]" ..
                        " (noch " .. tostring(w.hopsLeft) .. " Hops, patrolId=" ..
                        tostring(w.fieldId) .. ")")
                    w.status    = 1
                    w.needTimer = true
                end
            end
        end
    end

    -- Klapp-Nachpruefung 10 s nach dem Einklappbefehl
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
                        print("LivingRoads: [KLAPP] nach 10 s noch offen: " .. self:getKlappText(impl))
                        if (sf.foldMoveDirection or 0) == 0 then
                            impl:setFoldState(-(sf.turnOnFoldDirection or 1), false)
                            print("LivingRoads: [KLAPP] Einklappbefehl wiederholt")
                        end
                    elseif zu == true then
                        print("LivingRoads: [KLAPP] eingeklappt: " .. self:getKlappText(impl))
                    end
                end
                schritt()
            end
        end
    end

    -- Umgekipptes Gespann sofort erkennen statt 60 s Stillstand abzuwarten
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
                        print(string.format("LivingRoads: %s %s ist umgekippt bei x=%d z=%d (Status %s) - wird entfernt",
                            "[TRAFFIC] Fahrzeug",
                            tostring(self:getWorkerName(w)), math.floor(x), math.floor(z), tostring(w.status)))
                        -- Platz sperren: dort kippen erfahrungsgemaess auch andere Gespanne
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

    -- Bewegungs-Watchdog fuer Patrol-Fahrzeuge im GOTO (Status 1):
    --   steht es 12 s still und ist schon am Ziel (< 15 m), gilt es als angekommen.
    --   Sonst Stufe 1 (30 s): neues Ziel (dasselbe fuehrt in dieselbe Engstelle),
    --   Stufe 2 (60 s): nochmal neues Ziel, Stufe 3 (90 s): auf die Strasse setzen bzw. Pool.
    -- Die Fristen sind bewusst lang: die Wegsuche der KI steht teils ueber 10 s bei
    -- 0 km/h, ein kuerzerer Waechter bricht genau die Auftraege ab, die gleich losfahren.
    -- Echte Bewegung (> 5 m) setzt die Stufe zurueck.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        -- Erst messen, wenn der GOTO-Job wirklich laeuft (fieldGotoStartedAt, beim
        -- Job-Ende geloescht). Status 1 gilt schon waehrend der Wartezeit vor dem Start;
        -- sonst loest Stufe 1 aus, ohne dass das Fahrzeug je festsass.
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
                    -- echte Bewegung: alles zuruecksetzen
                    w.patrolWdLastX, w.patrolWdLastZ, w.patrolWdSince = x, z, g_time
                    w.patrolWdStage = 0
                    w.wdRettungen   = nil
                    w.begegnungen   = nil   -- faehrt wieder
                else
                    local stuckMs = g_time - (w.patrolWdSince or g_time)
                    local stage   = w.patrolWdStage or 0

                    local zielDist = math.huge
                    if w.patrolTargetX ~= nil and w.patrolTargetZ ~= nil then
                        zielDist = MathUtil.vector2Length(x - w.patrolTargetX, z - w.patrolTargetZ)
                    end

                    -- Steht ein frisch geladenes Fahrzeug nach 30 s noch auf seinem Ladeplatz,
                    -- taugt der Platz nicht: sperren, einmal je Fahrzeug. Der Umkreis ist grosszuegig,
                    -- weil es vorher oft ein paar Meter anrollt.
                    if stuckMs > 30000 and stage == 0 and zielDist >= 15 then
                        self:merkeSpawnFehlschlag(w, x, z, "steht nach dem Start still",
                            NachbarFelderManager.LADEPLATZ_STILLSTAND_RADIUS, true)
                    end

                    -- Stufe 3 als Funktion: die Schleifen-Erkennung springt ebenfalls hierher
                    local function stufe3()
                        -- Stufe 3: aufgeben
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 0
                        -- Wer drei Stufen lang nicht vorankam, steckt fest;
                        -- Einschlafen an Ort und Stelle aendert daran nichts. Daher einmal auf die
                        -- KI-Strasse setzen und weiterfahren, erst danach Pool bzw. Loeschen.
                        local gerettet = false
                        if (w.wdRettungen or 0) < 1 then
                            self:stopAIJobSafely(veh)
                            w.fieldGotoStartedAt = nil
                            if self:rettungAufStrasse(veh, x, z) then
                                gerettet = true
                                w.wdRettungen   = (w.wdRettungen or 0) + 1
                                w.patrolWdLastX = nil
                                local curDest = w.patrolDestIdx or 1
                                local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Ziel ab Fahrzeugposition
                                w.waypointIdx   = curDest
                                w.patrolDestIdx = newDest
                                w.patrolTargetX = w.waypoints[newDest][1]
                                w.patrolTargetZ = w.waypoints[newDest][2]
                                print("LivingRoads: [TRAFFIC] Stufe3 - steckte fest, faehrt von der Strasse" ..
                                    " aus weiter zu WP" .. tostring(newDest) .. " (patrolId=" ..
                                    tostring(w.fieldId) .. ")")
                                w.status    = 1
                                w.needTimer = true
                            end
                        end
                        if gerettet then
                            -- weiter mit neuem Ziel
                        elseif self:sleepPatrolEntry(k, false) then
                            print("LivingRoads: [TRAFFIC] Stufe3 - Fahrzeug schlaeft im Pool (patrolId=" ..
                                tostring(w.fieldId) .. ")")
                        else
                            print("LivingRoads: [TRAFFIC] Stufe3 - Fahrzeug loeschen (patrolId=" ..
                                tostring(w.fieldId) .. ")")
                            w.status    = 100
                            w.needTimer = true
                        end
                    end

                    if stuckMs > 12000 and zielDist < 15 then
                        -- Steht am Ziel, der Job endet aber nicht: die KI erreicht die geforderte
                        -- Zielrichtung nicht ganz und wartet. Job beenden und parken wie bei
                        -- normaler Ankunft, ohne das Fahrzeug zu versetzen.
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
                        self:log(2, string.format("LivingRoads: [TRAFFIC] steht %.0f m vor Ziel WP%s still -" ..
                            " gilt als angekommen, parkt (patrolId=%s)",
                            zielDist, tostring(w.patrolDestIdx), tostring(w.fieldId)))

                    elseif stuckMs > 30000 and stage == 0 and self:loeseBegegnung(k, veh, x, z) then
                        -- zwei Nachbar-Fahrzeuge warten aufeinander: dieses weicht aus (loeseBegegnung)
                        w.patrolWdStage = 1

                    elseif stuckMs > 30000 and stage == 0 and self:merkeStufe1Schleife(w) then
                        -- Wiederholte Stufe 1 in kurzer Zeit: das Fahrzeug rollt zwischendurch ein
                        -- paar Meter (Waechter beginnt neu), kommt aber nicht weiter. Direkt Stufe 3.
                        print(string.format("LivingRoads: [TRAFFIC] Stufe1 zum %d. Mal in %d min - gilt als" ..
                            " festgefahren, weiter mit Stufe 3 (patrolId=%s)",
                            NachbarFelderManager.STUFE1_SCHLEIFE_ANZAHL,
                            NachbarFelderManager.STUFE1_SCHLEIFE_MS / 60000, tostring(w.fieldId)))
                        stufe3()

                    elseif stuckMs > 30000 and stage == 0 then
                        -- Stufe 1: neues zufaelliges Ziel (dasselbe fuehrt in dieselbe Engstelle).
                        -- Laufenden Job sauber stoppen, sonst kollidiert der neue GOTO mit ihm.
                        -- Kein Teleport: den Weg aus der Engstelle plant die KI selbst.
                        -- Diagnose vor dem Stoppen loggen, danach ist der Agent geloescht.
                        local fremdD, fremdName = self:getNaechstesFremdfahrzeug(x, z, veh)
                        local zielBelegt = w.patrolTargetX ~= nil
                            and self:isSpotBlockedByAnyVehicle(w.patrolTargetX, w.patrolTargetZ, 10, veh)
                        print(string.format("LivingRoads: [DIAG] 30s ohne Bewegung" ..
                            " (Ziel WP%s, noch %.0f m, Zielplatz %s, naechstes Fahrzeug %s in %.0f m): %s",
                            tostring(w.patrolDestIdx), math.min(zielDist, 99999),
                            zielBelegt and "BELEGT" or "frei",
                            tostring(fremdName or "-"), fremdD or -1, self:getVehicleAiDiag(veh)))
                        self:stopAIJobSafely(veh)
                        w.fieldGotoStartedAt = nil   -- Uhr ruht bis zum naechsten Start
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 1
                        local curDest = w.patrolDestIdx or 1
                        local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Ziel ab Fahrzeugposition
                        w.waypointIdx   = curDest
                        w.patrolDestIdx = newDest
                        w.patrolTargetX = w.waypoints[newDest][1]
                        w.patrolTargetZ = w.waypoints[newDest][2]
                        w.parkSecs      = self:scaleParkSecs(math.random(20, 60))
                        print("LivingRoads: [TRAFFIC] Stufe1 - 30s fest, neues Ziel WP" ..
                            tostring(newDest) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                        w.status    = 1
                        w.needTimer = true

                    elseif stuckMs > 60000 and stage == 1 then
                        -- Stufe 2: wieder fest, anderes zufaelliges Ziel als letzte Chance
                        self:stopAIJobSafely(veh)
                        w.fieldGotoStartedAt = nil   -- Uhr ruht bis zum naechsten Start
                        w.patrolWdLastX = nil
                        w.patrolWdStage = 2
                        local curDest = w.patrolDestIdx or 1
                        local newDest = self:pickPatrolWaypoint(w.waypoints, curDest, x, z) or curDest  -- Ziel ab Fahrzeugposition
                        w.waypointIdx   = curDest
                        w.patrolDestIdx = newDest
                        w.patrolTargetX = w.waypoints[newDest][1]
                        w.patrolTargetZ = w.waypoints[newDest][2]
                        w.parkSecs      = self:scaleParkSecs(math.random(20, 60))
                        print("LivingRoads: [TRAFFIC] Stufe2 - neues Ziel WP" ..
                            tostring(newDest) .. " (patrolId=" .. tostring(w.fieldId) .. ")")
                        w.status    = 1
                        w.needTimer = true

                    elseif stuckMs > 90000 and stage == 2 then
                        stufe3()
                    end
                end
            end
        end
    end

    end  -- Ende slowTick-Block

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
                    -- Geraet an die Kupplung setzen
                    if pendingInfo ~= nil then
                        self:kuppleGeraet(pendingInfo)   -- drehrichtig setzen, weich kuppeln
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
                    -- Patrol ohne spec_aiFieldWorker kann keinen GOTO-Job ausführen:
                    -- sofort sperren, bevor es gespawnt wird und gleich wieder verschwindet.
                    if k.NachbarFelderWorker.isPatrol and vehicle.spec_aiFieldWorker == nil then
                        local fname    = vehicle.configFileName
                        local baseName = fname ~= nil and (string.match(fname, "[^/\\]+$") or fname)
                                         or tostring(vehicle.typeName or "?")
                        print("LivingRoads: [TRAFFIC] Blacklist: " .. baseName ..
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
                        -- Erster Start nach dem Kuppeln: Start- und Ziel-WP festlegen.
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
                            -- Belegte Plaetze meiden: kein WP, an dem schon ein Fahrzeug steht.
                            local freeIdx = self:findFreeSpawnWp(wps, nearestIdx, vehicle)
                            if freeIdx ~= nil then nearestIdx = freeIdx end
                            nfW.waypointIdx = nearestIdx
                            if nfW.patrolDestIdx == nearestIdx and #wps >= 2 then
                                local nd = self:pickPatrolWaypoint(wps, nearestIdx) or nearestIdx
                                nfW.patrolDestIdx = nd
                                nfW.patrolTargetX = wps[nd][1]
                                nfW.patrolTargetZ = wps[nd][2]
                            end
                            -- Kein Spawn-Teleport auf den Wegpunkt: dort gibt es keine verlaessliche
                            -- Ausrichtung (die gespeicherte ry ist die Blickrichtung beim Setzen, oft quer
                            -- zur Fahrbahn). Nur der Ladeplatz hat eine vom Spiel definierte Ausrichtung,
                            -- also startet das Gespann dort und faehrt die Strecke selbst.
                            print("LivingRoads: [TRAFFIC] Gespann startet am Ladeplatz " ..
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
                        -- Patrol: teleportVehicle ist auf dem Dedicated Server asynchron (ein Frame Latenz).
                        -- Status 1.5 gibt 3 s Settle-Zeit, damit das Fahrzeug physikalisch an der
                        -- WP-Position steht, bevor createAgent() den Navmesh-Startknoten sucht.
                        k.NachbarFelderWorker.status    = 1.5
                        k.NachbarFelderWorker.needTimer = true
                    else
                        -- Eintrag ohne Patrol (Feldhelfer gibt es nicht mehr) aufraeumen
                        k.NachbarFelderWorker.status    = 100
                        k.NachbarFelderWorker.needTimer = true
                    end

                elseif s == 1.5 then
                    -- Settle-Zeit abgelaufen: GOTO starten.
                    -- Status vor driveToField auf 1 setzen, onAIJobFinished prüft status==1.
                    local nfW = k.NachbarFelderWorker
                    nfW.status = 1
                    nfW.fieldGotoStartedAt = g_time
                    -- Ziel-Winkel: die KI rangiert am Ziel, bis sie genau so steht. Daher die
                    -- Richtung der naechsten KI-Strasse, damit das Fahrzeug laengs parkt; nur ohne
                    -- Strasse im Umkreis von 20 m gilt die gespeicherte WP-Richtung.
                    -- Strassenziele wandern zusaetzlich auf die Fahrbahn: daneben haelt die KI im
                    -- Seitenstreifen und kommt von dort nicht mehr weg.
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
                        -- Spur passend zur Anfahrtsrichtung waehlen (Zwillings-Spline), nicht drehen:
                        -- auf Einbahnen zeigte das Ziel sonst gegen die Fahrtrichtung.
                        local wdx, wdz = nil, nil
                        if vx ~= nil then wdx, wdz = wp[1] - vx, wp[2] - vz end
                        local rx, rz, roadRy = self:getRoadPointInRichtung(wp[1], wp[2], 20, 0, wdx, wdz)
                        if roadRy ~= nil then
                            targetRy = roadRy
                            -- Parkpunkte (eigene Wegpunkte) nicht auf die Strasse ziehen, dort soll
                            -- das Fahrzeug neben der Fahrbahn stehen.
                            if not self:getIsParkpunkt(nfW, nfW.patrolDestIdx) then
                                nfW.patrolTargetX, nfW.patrolTargetZ = rx, rz
                            end
                        elseif vx ~= nil then
                            -- ohne KI-Strasse im Umkreis (Parkpunkt abseits): nach Anfahrtsrichtung
                            -- drehen, dort gibt es keine Spur
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
                            print("LivingRoads: Rueckfahrt-Timeout Feld " ..
                                tostring(k.NachbarFelderWorker.fieldId) .. " - loesche Fahrzeug")
                            k.NachbarFelderWorker.gotoStartedAt = nil
                            k.NachbarFelderWorker.status = 100
                            k.NachbarFelderWorker.needTimer = true
                        else
                            k.NachbarFelderWorker.needTimer = true
                        end
                    end

                elseif s == 100 then
                    -- Patrol: in den Pool statt loeschen. Klappt das nicht (Pool voll/aus,
                    -- noPool, kein freier WP), wird geloescht.
                    if k.NachbarFelderWorker.isPatrol and self:sleepPatrolEntry(k, false) then
                        -- schlaeft im Pool; Eintrag ist entfernt, kein pendingRespawn noetig
                    else
                        local wVehs = k.NachbarFelderWorker.vehiclesToLoad
                        for _, veh in ipairs(wVehs) do
                            if self:getIsVehicleAlive(veh) then
                                self:stopAIJobSafely(veh)
                                veh:delete()
                            end
                        end
                        -- Stammfahrzeug: nach 5-8 Min Echtzeit neu spawnen
                        if k.NachbarFelderWorker.isPatrol and k.NachbarFelderWorker.isRegular
                           and not k.NachbarFelderWorker.noPool then
                            local xml = k.NachbarFelderWorker.regularXML
                            if xml ~= nil then
                                table.insert(self.pendingRespawns, {
                                    filename = xml,
                                    spawnAt  = g_time + math.random(300, 480) * 1000
                                })
                                print("LivingRoads: [TRAFFIC] Stammfahrzeug respawnt in 5-8 Min: " ..
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
-- onMinuteChanged (nur Server)
-- ============================================================
function NachbarFelderManager:onMinuteChanged(minute)
    if not g_currentMission:getIsServer() then return end

    -- Server-Konfig einmalig laden (modSettings/FS25_LivingRoads/NachbarFelderServerConfig.xml)
    self:loadServerConfig()


    -- Spieler selbst zaehlen, der addPlayer-Hook feuert auf dem Dedicated Server nicht zuverlaessig.
    -- Nur Spieler mit farmId > 0 sind wirklich im Spiel, farmId 0/nil heisst noch im Ladebildschirm.
    local realCount = 0
    if g_currentMission.players ~= nil then
        for _, player in pairs(g_currentMission.players) do
            if player ~= nil then
                local pFarmId = player.farmId or 0
                if pFarmId > 0 then
                    realCount = realCount + 1
                end
            end
        end
    end
    if realCount ~= self.playersOnline then
        print("LivingRoads: Spieler: " .. tostring(self.playersOnline) .. " -> " .. tostring(realCount))
        -- Erster Spieler auf leerem Server: Wartezeit vor dem ersten Spawn starten
        if self.playersOnline <= 0 and realCount > 0 then
            self.playerJoinTime = g_time  -- Echtzeit, robust gegen Zeitspruenge
            print("LivingRoads: Erster Spieler erkannt - warte " ..
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

    if self.playersOnline <= 0 then return end

    -- Wartezeit in Echtzeit, nicht in Spielminuten: TimeResetOnJoin wuerde
    -- einen Spielminuten-Zaehler beim Zeitsprung sofort leerlaufen lassen.
    if self.playerJoinTime ~= nil then
        if g_time - self.playerJoinTime < (self.firstSpawnDelayMs or 180000) then return end
        self.playerJoinTime = nil
        self.timeToNextStart = 0
    end

    local timeScale = g_currentMission:getEffectiveTimeScale()
    -- Faktor fuer Spielminuten-Zeitgeber, die eigentlich Echtzeit meinen (>= 1, auch bei Pause)
    local zeitFaktor = math.max(1, timeScale or 1)

    -- Blockier-Pruefung in Echtzeit: steht ein Fahrzeug BLOCK_ECHTZEIT_MS lang innerhalb
    -- von 1 m, ohne zu parken, kommt es in den Pool bzw. wird geloescht. In Spielminuten
    -- gerechnet waere die Schwelle bei hohem Zeitfaktor nur wenige Sekunden. Festgefahrene
    -- Fahrzeuge im Fahrbetrieb loest vorher schon der Waechter (30-s-Stufen).
    for v, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil then
            local veh = nil
            for _, vehicle in ipairs(w.vehiclesToLoad or {}) do
                if self:getIsVehicleAlive(vehicle) then veh = vehicle break end
            end
            local parkt = w.status == 2
            if veh == nil or parkt then
                w.blockSeit = nil
            else
                local x, _, z = getWorldTranslation(veh.rootNode)
                if w.blockSeit == nil or w.blockX == nil
                   or MathUtil.vector2Length(x - w.blockX, z - w.blockZ) > 1 then
                    w.blockX, w.blockZ, w.blockSeit = x, z, g_time
                elseif g_time - w.blockSeit > NachbarFelderManager.BLOCK_ECHTZEIT_MS then
                    w.blockSeit = nil
                    self:log(2, string.format("LivingRoads: [TRAFFIC] steht %d s unbewegt (Status %s) -" ..
                        " Pool bzw. entfernen (patrolId=%s)", math.floor(NachbarFelderManager.BLOCK_ECHTZEIT_MS / 1000),
                        tostring(w.status), tostring(w.fieldId)))
                    -- Verkehr: in den Pool statt loeschen
                    if not (w.isPatrol and self:sleepPatrolEntry(k, false)) then
                        local status = w.status
                        for _, vehicleRM in ipairs(w.vehiclesToLoad or {}) do
                            if self:getIsVehicleAlive(vehicleRM) then
                                self:stopAIJobSafely(vehicleRM)
                                vehicleRM:delete()
                            end
                        end
                        self:deleteMission(w.fieldId, status)
                    end
                end
            end
        end
    end

    local sleeping = g_sleepManager:getIsSleeping()
    if sleeping then return end

    -- "Mod aktiv" aus: keine neuen Spawns, laufende Fahrzeuge arbeiten fertig (MP-synchronisiert)
    if self.active == false then return end

    -- Gegen das Traffic-Limit pruefen, nicht gegen "Anzahl Arbeiter"
    if self:countActivePatrols() < self:getEffectiveTrafficLimit() then
        self.timeToNextStart = self.timeToNextStart - 1
        if self.timeToNextStart <= 0 then
            -- Standard 1 Fahrzeug pro Tick: jeder Spawn (I3D-Laden, Physik, MP-Sync)
            -- erzeugt einen kurzen Ruckler, mehrere direkt hintereinander stapeln sich.
            local spawnedThisTick = 0
            local nWpsTotal = self.userTrafficWaypoints ~= nil and #self.userTrafficWaypoints or 0
            local lastOverride = nil
            for _attempt = 1, (self.spawnPerTick or 1) do
                -- lastOverride ausschliessen, sonst spawnen mehrere Fahrzeuge desselben
                -- Ticks am selben WP und blockieren sich gegenseitig.
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
                -- Pause bis zum naechsten Spawn in Spielminuten, mit dem Zeitfaktor skaliert,
                -- damit sie auch bei hohem Zeitfaktor in Echtzeit spuerbar bleibt.
                local pMin = math.floor((self.spawnIntervalMin or 2) * zeitFaktor + 0.5)
                local pMax = math.max(pMin, math.floor((self.spawnIntervalMax or 5) * zeitFaktor + 0.5))
                self.timeToNextStart = math.random(pMin, pMax)
            else
                self.timeToNextStart = math.max(1, math.floor(1 * timeScale))
            end
        end
    end
end

-- ============================================================
-- Spawn-Blickrichtung (kartenunabhaengig)
--
-- Frisch gespawnte Fahrzeuge schauen sonst in die Richtung des Shop-Spawnplatzes,
-- auf manchen Karten gegen eine Wand, einen Hang oder ins Wasser.
--   1. Naechstgelegene Werkstatt (spec_workshop in placeableSystem.placeables).
--   2. Sonst die Senkrechte des Spawnplatzes, wie das Basisspiel gekaufte
--      Fahrzeuge ausrichtet (VehicleLoadingData: getYRotationFromDirection(dirPerpX, dirPerpZ)).
-- Findet keine Stufe etwas, bleibt die Rotation der Karte unangetastet.
-- ============================================================

--- Zielpunkt fuer die Blickrichtung, wird einmal ermittelt und gecacht.
--- @return table|nil { x=, z=, quelle= }
function NachbarFelderManager:getSpawnLookAt()
    if self.spawnLookAt ~= nil then
        return self.spawnLookAt
    end

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
        print(string.format("LivingRoads: Spawn-Blickrichtung = Werkstatt bei x=%.1f z=%.1f (%.0f m entfernt)",
            bestX, bestZ, bestDist or 0))
        return self.spawnLookAt
    end

    -- Stufe 2: Senkrechte des Spawnplatzes
    local place = self:getNfSpawnPlace()
    if place ~= nil and place.dirPerpX ~= nil and place.dirPerpZ ~= nil then
        local dx, dz = place.dirPerpX, place.dirPerpZ
        if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
            self.spawnLookAt = { x = spX + dx * 50, z = spZ + dz * 50, quelle = "Spawnplatz" }
        end
    end

    if self.spawnLookAt ~= nil then
        print("LivingRoads: Spawn-Blickrichtung = Ausrichtung des Shop-Spawnplatzes")
        return self.spawnLookAt
    end

    print("LivingRoads: Keine Spawn-Blickrichtung ermittelbar - Rotation bleibt wie vom Spiel gesetzt")
    return nil
end

-- ============================================================
-- Spawn-Logik
-- ============================================================
function NachbarFelderManager:onSpawnedVehicle(vehicles, vehicleLoadState, loadingInfo)
    if vehicleLoadState == VehicleLoadingState.OK then
        for _, vehicle in ipairs(vehicles) do
            vehicle.isVehicleSaved = false
            self:applyServerDriverFigure(vehicle)
            self:applyRueckwaertsPlanen(vehicle)
            self:applyFahrerBleibt(vehicle)
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
                if vehAdd then
                    -- Geraet bis zum Kuppeln ohne Physik: am Shop-Platz oder im Traktor
                    -- verkeilt es sich sonst und fliegt weg. setAttachment setzt es
                    -- spaeter an die Kupplung und nimmt es wieder in die Physik.
                    if vehicle.isAddedToPhysics then vehicle:removeFromPhysics() end
                end
            else
                -- Traktor nicht am Shop-Platz stehen lassen: liegt der zu dicht an einer
                -- Mauer, gibt es sofort NotReachable (kein Navmesh fuer lange Gespanne)
                -- und Geraete schlagen beim Ausrichten gegen die Wand. Deshalb vor dem
                -- Kuppeln auf den naechsten freien Punkt der KI-Strasse (40 m, ersatzweise
                -- 80 m), Richtung erstes Fahrziel. Sonst Ausrichtung per getSpawnLookAt().
                local x0, _, z0 = localToWorld(vehicle.rootNode, 0, 0, 0)
                local nfWS = loadingInfo.NachbarFelderWorker.NachbarFelderWorker
                local istVerkehrS = nfWS ~= nil and nfWS.isPatrol
                -- Schon an der Strasse geladen: nicht mehr versetzen
                local aufStrasse = nfWS ~= nil and nfWS.spawnAufStrasse == true
                if not aufStrasse and self.getNearestRoadPoint ~= nil then
                    local function schritt()
                        local zielX, zielZ = nil, nil
                        if istVerkehrS then
                            zielX, zielZ = nfWS.patrolTargetX, nfWS.patrolTargetZ
                        end
                        -- Spur in Richtung Ziel waehlen, wichtig bei Einbahn-Splines
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
                        print(string.format("LivingRoads: [TRAFFIC] %.0f m vom Shop-Platz auf die KI-Strasse" ..
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
                -- Kuppeln erst im naechsten Frame: die InputAttacherJoints des letzten
                -- Fahrzeugs stehen erst nach dem Spawn-Callback in vehicleSystem.inputAttacherJoints.
                loadingInfo.NachbarFelderWorker.NachbarFelderWorker.needAttachment = true
                -- Verkehr startet immer am Shop: ohne Geraet faehrt er direkt los, mit Geraet
                -- wird erst dort gekuppelt. Kuppeln direkt nach einem weiten Teleport
                -- verdrahtet die Zapfwelle mit einem alten Weltpunkt (meterlange "Stange").
                local nfW = loadingInfo.NachbarFelderWorker.NachbarFelderWorker
                if nfW ~= nil and nfW.isPatrol and nfW.firstStart then
                    local wps     = nfW.waypoints
                    local tractor = loadingInfo.NachbarFelderWorker.vehicleType[1]
                    local hasImplement = #loadingInfo.NachbarFelderWorker.vehicleType >= 2
                    if wps ~= nil and #wps >= 1 and tractor ~= nil then
                        local nearestIdx = 1
                        -- Vorgegebener Startpunkt hat Vorrang
                        if nfW.overrideSpawnWpIdx ~= nil and wps[nfW.overrideSpawnWpIdx] ~= nil then
                            nearestIdx = nfW.overrideSpawnWpIdx
                        else
                            nearestIdx = self:pickPatrolWaypoint(wps, nil) or math.random(#wps)
                        end
                        -- Belegte WPs meiden
                        local freeIdx = self:findFreeSpawnWp(wps, nearestIdx, tractor)
                        if freeIdx ~= nil then nearestIdx = freeIdx end
                        -- Kein Teleport auf den Wegpunkt: dort fehlt eine verlaessliche
                        -- Ausrichtung, das Fahrzeug stuende quer. Der WP dient nur als Index.
                        nfW.waypointIdx = nearestIdx
                        if nfW.patrolDestIdx == nearestIdx and #wps >= 2 then
                            local nd = self:pickPatrolWaypoint(wps, nearestIdx) or nearestIdx
                            nfW.patrolDestIdx = nd
                            nfW.patrolTargetX = wps[nd][1]
                            nfW.patrolTargetZ = wps[nd][2]
                        end
                        if not hasImplement then
                            nfW.firstStart = nil
                            print("LivingRoads: [TRAFFIC] Einzelfahrzeug faehrt vom Ladeplatz los, Ziel WP" ..
                                tostring(nfW.patrolDestIdx))
                        else
                            -- firstStart bleibt fuer den Kuppel-Ablauf gesetzt
                            nfW.spawnWpIdx = nearestIdx
                            print("LivingRoads: [TRAFFIC] Gespann wird am Ladeplatz gekuppelt")
                        end
                    end
                end
            end
        end
    end
end

--- Geraet mit seinem Eingangs-Kupplungspunkt auf die Kupplung des Traktors setzen
--- und wieder in die Physik nehmen. Position und Drehung wie
--- SupportVehicle:enableSupportVehicle (Attachable.lua:1957/1958). Nur die Gierrichtung
--- reicht nicht: ist der Eingangspunkt anders geneigt, reisst das Kuppeln den Traktor um.
--- Mindestens 5 cm ueber dem Boden.
function NachbarFelderManager:setzeGeraetAnKupplung(attacher, attacherJointIndex, implement, inputJointIndex)
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

--- Geraet ankuppeln: an die Kupplung setzen, dann weich kuppeln wie ein Spieler
--- (VehicleAttachEvent, noSmoothAttach = nil). Mit noSmoothAttach = true sind die
--- Gelenkgrenzen sofort 0 (AttacherJoints:createAttachmentJoint); der Ruck kippt leichte
--- Traktoren. Nicht absenken (startLowered = false).
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

--- Erkennt eine Schleife aus Stufe 1: true, wenn binnen STUFE1_SCHLEIFE_MS die
--- STUFE1_SCHLEIFE_ANZAHL-te Stufe 1 ansteht. Die Liste wird dann geleert, damit nach
--- der Rettung neu gezaehlt wird.
NachbarFelderManager.STUFE1_SCHLEIFE_ANZAHL = 3
NachbarFelderManager.STUFE1_SCHLEIFE_MS     = 5 * 60 * 1000
function NachbarFelderManager:merkeStufe1Schleife(w)
    if w == nil or g_time == nil then return false end
    local liste = {}
    for _, t in ipairs(w.stufe1Zeiten or {}) do
        if g_time - t <= NachbarFelderManager.STUFE1_SCHLEIFE_MS then table.insert(liste, t) end
    end
    table.insert(liste, g_time)
    if #liste >= NachbarFelderManager.STUFE1_SCHLEIFE_ANZAHL then
        w.stufe1Zeiten = nil
        return true
    end
    w.stufe1Zeiten = liste
    return false
end

--- Ladeplatz als ungeeignet merken, wenn ein Fahrzeug dort scheitert. Nur wenn es noch
--- innerhalb von maxDist (Standard 10 m) um seinen Ladeplatz steht, je Fahrzeug einmal.
--- diag = true: Ergebnis einmal je Fahrzeug ins Debug-Log.
function NachbarFelderManager:merkeSpawnFehlschlag(w, x, z, grund, maxDist, diag)
    if w == nil or x == nil or z == nil or w.spawnPlatzGemeldet then return end
    local sp = w.spawnStrasse
    local function diagnose(text)
        if diag and not w.spawnPlatzDiagnose then
            w.spawnPlatzDiagnose = true
            self:log(2, "LivingRoads: [TRAFFIC] Ladeplatz-Pruefung (" .. tostring(grund) .. "): " .. text)
        end
    end
    if type(sp) ~= "table" then
        diagnose("kein Ladeplatz an der Strasse bekannt (Shop-Platz oder Pool) - nichts gesperrt")
        return
    end
    local dist = MathUtil.vector2Length(x - sp.x, z - sp.z)
    -- weit weg vom Ladeplatz liegt es nicht am Platz, Diagnose waere nur Rauschen
    if diag and dist > NachbarFelderManager.LADEPLATZ_DIAG_MAX then return end
    if dist > (maxDist or 10) then
        diagnose(string.format("steht %.0f m vom Ladeplatz x=%d z=%d - weiter als %.0f m, nicht gesperrt",
            dist, math.floor(sp.x), math.floor(sp.z), maxDist or 10))
        return
    end
    diagnose(string.format("steht %.0f m vom Ladeplatz x=%d z=%d - Platz gilt als untauglich",
        dist, math.floor(sp.x), math.floor(sp.z)))
    w.spawnPlatzGemeldet = true
    -- Admin-Spawnpunkte nie automatisch sperren (bei nur einem Punkt ginge es sonst
    -- zurueck zum Shop), stattdessen einmal einen Hinweis geben.
    if sp.spawnpunktIdx ~= nil then
        self.spawnpunktGemeldet = self.spawnpunktGemeldet or {}
        if not self.spawnpunktGemeldet[sp.spawnpunktIdx] then
            self.spawnpunktGemeldet[sp.spawnpunktIdx] = true
            print(string.format("LivingRoads: Spawnpunkt WP%d: Fahrzeug kam dort nicht weg (%s) - Punkt pruefen:" ..
                " freie Flaeche, nah an einer befahrbaren Strasse, beim Setzen in Abfahrtrichtung schauen",
                sp.spawnpunktIdx, tostring(grund)))
        end
        return
    end
    self:ladeLadeplatzSperre()
    table.insert(self.spawnPlatzSperre, { sp.x, sp.z, tostring(grund) })
    self:speichereLadeplatzSperre()
    self:hinweisSpawnpunkt(grund)
    print(string.format("LivingRoads: Ladeplatz x=%d z=%d taugt nicht (%s) - dauerhaft fuer diese Karte gesperrt" ..
        " (%d Plaetze gesperrt, Datei %s)", math.floor(sp.x), math.floor(sp.z), tostring(grund),
        #self.spawnPlatzSperre, tostring(self:getLadeplatzDatei())))
end

--- Einmaliger Hinweis "Spawnpunkt setzen", wenn ein automatischer Ladeplatz scheitert und
--- die Karte noch keinen Spawnpunkt hat. Ingame-Meldung nur mit lokalem Spieler (SP/Host),
--- auf dem Dedi nur im Log.
function NachbarFelderManager:hinweisSpawnpunkt(grund)
    if self.spawnHinweisGegeben or self:getHatSpawnpunkte() then return end
    self.spawnHinweisGegeben = true
    print("LivingRoads: Hinweis - automatischer Ladeplatz gescheitert (" .. tostring(grund) ..
        "). Zuverlaessiger: Spawnpunkt setzen (ESC > Einstellungen > Wegpunkte > Spawnpunkt hier setzen)")
    if g_client ~= nil and g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            nfMeldung("NF_hinweisSpawnpunkt"))
    end
end

--- Datei der gesperrten Ladeplaetze fuer die geladene Karte, nil ohne Kartenkennung.
function NachbarFelderManager:getLadeplatzDatei()
    local kennung = nfGetKartenKennung()
    if kennung == nil then return nil end
    return modSettingDirectory .. "NachbarFelderLadeplaetze_" .. kennung .. ".xml"
end

--- Gesperrte Ladeplaetze einmal je Spielsitzung aus der Kartendatei lesen.
--- Wieder freigeben: Datei loeschen (oder Eintrag entfernen) und neu laden.
function NachbarFelderManager:ladeLadeplatzSperre()
    if self.spawnPlatzSperre ~= nil then return end
    self.spawnPlatzSperre = {}
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local pfad = self:getLadeplatzDatei()
    if pfad == nil then return end
    local verworfen = 0
    local function schritt()
        local xmlFile = XMLFile.loadIfExists("NachbarFelderLadeplaetze", NachbarFelderLesePfad(pfad), lpXmlSchema)
        if xmlFile == nil then return end
        xmlFile:iterate(lpXmlKey .. ".platz", function(_, key)
            local x = xmlFile:getValue(key .. "#x")
            local z = xmlFile:getValue(key .. "#z")
            local grund = xmlFile:getValue(key .. "#grund") or "?"
            -- "umgekippt" liegt am Gespann, nicht am Platz: alte Eintraege verwerfen
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
        print(string.format("LivingRoads: %d gesperrte Ladeplaetze geladen (%s)", #self.spawnPlatzSperre, pfad))
    end
    if verworfen > 0 then
        print(string.format("LivingRoads: %d Ladeplatz-Sperren wegen 'umgekippt' aufgehoben (lag am Gespann)", verworfen))
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

--- Stuetzpunkte der KI-Strasse im Ring minD..maxD um (x, z), nach Entfernung sortiert.
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

--- Echte Fahrbahnhoehe per Strahl von oben. Die Hoehe der KI-Spline liegt oft ueber der
--- Fahrbahn, das Fahrzeug faellt dann herunter. Strahl wie GuiTopDownCamera.lua:269
--- (RaycastUtil.raycastClosest liefert hit, x, y, z sofort).
--- Der Strahl trifft auch Baumkronen, Daecher und Schilder ueber der Strasse. Mit Spline-Hoehe
--- gilt ein Treffer mehr als HOEHE_UEBERKOPF ueber der Bezugshoehe als Hindernis: Rueckgabe
--- ist dann die Bezugshoehe und ueberkopf = true. Ohne Spline-Hoehe (Admin-Spawnpunkt,
--- evtl. auf einer Bruecke) zaehlt der Treffer.
--- @return number Hoehe, boolean ueberkopf
function NachbarFelderManager:getFahrbahnHoehe(x, z, splineH)
    local gelaende = splineH or 0
    if g_terrainNode ~= nil then
        gelaende = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    end
    local h = nil
    local oben = math.max(gelaende, splineH or gelaende) + 3
    -- TERRAIN_DELTA wie VehicleSystem.lua beim Paletten-Spawn: ohne sie trifft der Strahl bei
    -- Strassen aus Gelaende-Deltas das Grundgelaende, das Fahrzeug steckt in der Fahrbahn.
    -- Fehlt eine Flagge oder der Strahl, gilt die Gelaendehoehe.
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

--- Ist die Flaeche fuer ein Gespann frei?
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
        -- fehlt ein Masken-Wert, gilt die Flaeche als belegt
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
-- Admin-Spawnpunkte
--
-- Der Shop-Spawn liegt auf vielen Karten mitten im Ort; Teleports zur Rettung
-- sehen Clients interpoliert (Vehicle.lua:1768 setTargetPosition) als Flug.
-- Der Admin setzt daher Wegpunkte vom Typ Spawnpunkt an Stellen mit Platz.
-- Richtung = Blickrichtung beim Setzen (im Fahrzeug: Fahrtrichtung).
-- Gibt es Spawnpunkte, wird nur dort geladen.
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
        -- Reservierung: bis das Fahrzeug fertig geladen ist, steht dort nichts
        -- Physisches, sonst naehmen zwei Spawns denselben Platz.
        if (self.spawnpunktReserviert[i] or 0) <= jetzt then
            local wp = wps[i]
            local ry = wp.ry or 0
            -- Liegt eine KI-Strasse direkt am Punkt (8 m) und zeigt die gespeicherte
            -- Richtung ungefaehr an ihr entlang (< 45 Grad), exakt laengs ausrichten.
            -- Bewusst quer gesetzte Punkte (Hofausfahrt) bleiben unveraendert.
            -- Nie eine Spur um 180 Grad drehen (Zwillings-Spline). Ist dort nur die
            -- Gegenrichtung befahrbar, mit der Spur ausrichten, sonst lehnt die KI ab.
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
                        print(string.format("LivingRoads: Spawnpunkt WP%d: die KI-Strasse ist dort nur in" ..
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

--- Ladeposition an der KI-Strasse. Direkt dort laden statt nachtraeglich versetzen,
--- weil Clients auf dem Dedicated Server jedes Versetzen als Flug sehen.
--- Der Strassenpunkt wird einmal je Gespann bestimmt (Admin-Spawnpunkt, sonst Suche ab
--- 40 m vom Shop-Platz, frei, Richtung erstes Fahrziel). Traktor auf dem Punkt, Geraete
--- 9/16 m dahinter; sie bleiben bis zum Kuppeln ohne Physik.
--- @return boolean true, wenn die Position gesetzt wurde
function NachbarFelderManager:setzeLadepositionStrasse(data, entry)
    local w = entry ~= nil and entry.NachbarFelderWorker or nil
    if w == nil or self.getNearestRoadPoint == nil then return false end
    if w.spawnStrasse == nil then
        w.spawnStrasse = false
        local function schritt()
            -- Admin-Spawnpunkt hat Vorrang vor der Suche am Shop
            local spp = self:waehleSpawnpunkt(false)
            if spp ~= nil then
                w.spawnStrasse = spp
                return
            end
            if self:getHatSpawnpunkte() then
                print("LivingRoads: Alle Spawnpunkte belegt - Ausweich auf die Platzsuche am Shop")
            end
            local sx, sz = self:getShopPosition()
            if sx == nil then return end
            local zielX, zielZ = w.patrolTargetX, w.patrolTargetZ
            -- Stuetzpunkte nach Entfernung pruefen, der erste gute Platz gewinnt.
            -- KI-Strassen sind Einbahn-Splines (siehe getRoadPointInRichtung), daher nie
            -- drehen: Durchgang 1 nur Spuren Richtung Ziel, Durchgang 2 die uebrigen.
            -- Stufen, weil auch Hoefe KI-Splines haben: zuerst echte Strassenstuecke
            -- (gerade, eben, 30x5 m frei), nah, dann weiter draussen; zuletzt locker.
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
            print("LivingRoads: Kein freier Strassenplatz fuer den Spawn gefunden (" .. tostring(geprueft) ..
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
        -- Fahrbahnhoehe statt Gelaendehoehe: Strassen liegen als Objekte ueber dem Gelaende.
        -- Gemessen an der eigenen Ladestelle (Traktor bzw. Geraet dahinter).
        local y = self:getFahrbahnHoehe(x, z, sp.h) + NachbarFelderManager.SPAWN_HOEHE
        -- Waagerecht laden: das Spiel addiert beim Laden die Shop-Drehung des Modells
        -- (storeData.shopRotationOffset) auf unsere Winkel, aus einer Laengsneigung wuerde
        -- Schraeglage. Damit keine Ecke in der Fahrbahn steckt, vorn/hinten/links/rechts messen
        -- und den hoechsten Punkt nehmen (gedeckelt, falls der Strahl ein Objekt trifft).
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
        -- Anbaugeraete gar nicht erst in die Physik, setAttachment setzt sie an die Kupplung
        -- und nimmt sie dann auf
        if index >= 2 and data.setAddToPhysics ~= nil then
            data:setAddToPhysics(false)
        end
    end
    schritt()
    if index == 1 then
        w.spawnAufStrasse = true
        local wer = "[TRAFFIC] Fahrzeug"
        if sp.spawnpunktIdx ~= nil then
            print(string.format("LivingRoads: %s wird am Spawnpunkt WP%d geladen", wer, sp.spawnpunktIdx))
        else
            print(string.format("LivingRoads: %s wird direkt an der KI-Strasse geladen (%.0f m vom Shop-Platz," ..
                " freier Platz, Stufe %s, %d Stellen geprueft)", wer, sp.dist or 0, tostring(sp.stufe or "?"),
                sp.geprueft or 0))
        end
    end
    return true
end

-- Ladehoehe ueber der hoechsten Fahrbahnstelle unter dem Fahrzeug
NachbarFelderManager.SPAWN_HOEHE        = 0.10   -- m ueber der Fahrbahn
NachbarFelderManager.SPAWN_MESS_LAENGS  = 2.5    -- m vor und hinter dem Ladepunkt messen
NachbarFelderManager.SPAWN_MESS_SEITE   = 1.2    -- m links und rechts messen
NachbarFelderManager.SPAWN_MAX_ANHEBEN  = 0.5    -- m hoechstens anheben (mehr = Strahl traf ein Objekt)

-- Ladeplatz-Suche in Stufen (setzeLadepositionStrasse)
-- streng = echtes Strassenstueck: gerade, eben, grosser freier Kasten
NachbarFelderManager.LADEPLATZ_STUFEN = {
    { minD = 40,  maxD = 250, streng = true  },
    { minD = 250, maxD = 800, streng = true  },
    { minD = 40,  maxD = 250, streng = false },   -- lockere Rueckfall-Pruefung
}
NachbarFelderManager.LADEPLATZ_MAX_PRUEFUNGEN = 150   -- je Stufe
NachbarFelderManager.LADEPLATZ_GERADE_ABST    = { -20, -10, 10, 20 }   -- m entlang der Spur
NachbarFelderManager.LADEPLATZ_GERADE_COS     = 0.9   -- Richtungsabweichung hoechstens ~25 Grad
NachbarFelderManager.LADEPLATZ_MAX_HOEHE      = 1.2   -- m Hoehenunterschied auf der Gespannlaenge
-- Sperrradius (m) um einen gescheiterten Ladeplatz. Kleiner waehlt die Suche oft einen Platz
-- daneben auf demselben Strassenstueck, das die KI nicht erreicht (NotReachable).
NachbarFelderManager.LADEPLATZ_SPERR_RADIUS   = 40
-- Stillstand nach dem Start zaehlt als Fehlschlag des Ladeplatzes, wenn das Fahrzeug
-- nach 30 s noch hoechstens so weit (m) davon entfernt steht
NachbarFelderManager.LADEPLATZ_STILLSTAND_RADIUS = 25
-- Ladeplatz-Diagnose im Debug-Log nur bis zu diesem Abstand (m) vom Ladeplatz
NachbarFelderManager.LADEPLATZ_DIAG_MAX = 100
-- Aufraeumen beim Monatswechsel erst nach so vielen Spieltagen (Server-Konfig
-- aufraeumenMinTage ueberschreibt, 0 = nie)
NachbarFelderManager.AUFRAEUMEN_MIN_TAGE = 7
-- so lange (Echtzeit) darf ein nicht parkendes Nachbar-Fahrzeug unbewegt stehen,
-- bevor es in den Pool geht bzw. entfernt wird
NachbarFelderManager.BLOCK_ECHTZEIT_MS = 4 * 60 * 1000
NachbarFelderManager.HOEHE_UEBERKOPF          = 1.0   -- m; Treffer hoeher ueber der Strasse = Hindernis darueber

--- Taugt der Strassenpunkt als Ladeplatz? (kartenunabhaengig)
--- Immer: nicht gesperrt, hinten noch Strasse, voraus kein Fahrzeug, Kasten 17 x 4 m frei.
--- streng zusaetzlich: Strasse laeuft 20 m vor und hinter dem Punkt gerade weiter
--- (keine Hofecke, keine Kurve), Fahrbahn eben, Kasten 30 x 5 m frei (Platz zum Losfahren).
function NachbarFelderManager:getIstLadeplatzGut(sp, rx, rz, ry, h, streng)
    if self:getIstSpawnPlatzGesperrt(rx, rz) then return false end
    local dx, dz = sp[3], sp[4]
    -- nichts ueber der Fahrbahn (Baumkrone, Dach) auf der Gespannlaenge, sonst wird
    -- das Fahrzeug oben abgesetzt und stuerzt
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

    -- Gespann (17 m) plus Raum zum Losfahren; der Kasten reicht 3 m vor den Punkt, also 13 m versetzt
    if not self:getIstSpawnFlaecheFrei(rx + dx * 13, h, rz + dz * 13, ry, 30, 5.0) then return false end
    return true
end

function NachbarFelderManager:loadVehicles(NachbarFelderWorker)
    local vehicles = NachbarFelderWorker.vehiclesToLoad
    if vehicles == nil or #vehicles == 0 then
        print("LivingRoads: [TRAFFIC] Keine Fahrzeuge zum Laden gefunden")
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
        -- Bevorzugt direkt an der KI-Strasse laden. Rueckfall: wie gekaufte Fahrzeuge,
        -- die Engine waehlt einen freien Shop-Platz mit Ausrichtung und Kollisionspruefung
        -- (vgl. FarmerWorkingAssistant, MissionInfo:loadVehicles); setAttachment setzt die
        -- Geraete danach hinter den Traktor. getNfSpawnPlaces: Original-Shop zuerst.
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
        -- Anbaugeräte kuppeln. Eine fehlgeschlagene Kupplung ist kein Abbruchgrund,
        -- Implement 3 hängt z. B. oft an Implement 2 statt am Traktor.
        for v = 2, #NachbarFelderWorker.vehicleType do
            local implement = NachbarFelderWorker.vehicleType[v]
            local isPatrolRig = NachbarFelderWorker.NachbarFelderWorker ~= nil
                and NachbarFelderWorker.NachbarFelderWorker.isPatrol
            local attacherRef = (v == 2) and vehicle or NachbarFelderWorker.vehicleType[v - 1]
            -- Erst am Vorgänger in der Kette kuppeln, ab v >= 3 als Fallback direkt am Traktor.
            -- v == 2 Feldarbeit: nur Heck, eine Frontkupplung würde die Feldarbeit blockieren.
            -- v == 2 Verkehr: auch Front, Frontmähwerke (MOWERS) gehören nach vorne.
            -- v >= 3 (Zusatzgewicht o. ä.): Front ebenfalls erlaubt.
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
                self:kuppleGeraet(pendingInfo)   -- drehrichtig setzen, weich kuppeln
            elseif implement ~= nil then
                if not implement.isAddedToPhysics then implement:addToPhysics() end
                if not isPatrolRig then
                    print("LivingRoads: Feldhelfer - Geraet [" .. tostring(implement.configFileName) ..
                        "] liess sich nicht kuppeln")
                end
            end
        end
    end

    -- Verkehr: nicht kuppelbare Geraete loeschen statt sie verwaist stehen zu lassen,
    -- das Fahrzeug faehrt dann solo.
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
                print("LivingRoads: [TRAFFIC] Anbaugeraet nicht kuppelbar (" .. base ..
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

    -- Verkehrsgespann nach dem Kuppeln Richtung Ziel-WP ausrichten; grosse Geraete
    -- ziehen den Traktor beim Kuppeln schief. teleportVehicle nimmt die Anbaugeraete mit.
    if #NachbarFelderWorker.vehicleType >= 2 then
        local worker = NachbarFelderWorker.NachbarFelderWorker
        local function schritt()
            if vehicle ~= nil and vehicle.rootNode ~= nil then
                local vx, _, vz = getWorldTranslation(vehicle.rootNode)

                -- Feldhelfer nicht drehen: sie sitzen schon an der Kupplung, und am
                -- engen Shop wuerde ein langes Geraet in die Mauern schwenken.
                if not (worker ~= nil and worker.isPatrol) then
                    return
                end

                -- Ohne Zielpunkt bleibt die Ausrichtung so, wie das Kuppeln sie hinterlassen hat.
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
                        -- wird gleich samt Ausrichtung zum Start-WP teleportiert
                        return
                    end
                    if worker.patrolTargetX == nil or worker.patrolTargetZ == nil then
                        return  -- kein Ziel bekannt
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

-- Klassenname einer AIMessage. onAIJobFinished bekommt die Message nicht,
-- nur job:stop. Der Worker entscheidet danach, wie er reagiert
-- (NotReachable: neues Ziel, OutOfMoney: Konto auffüllen und erneut versuchen).
local NF_AI_MSG_CLASSES = {
    "AIMessageSuccessFinishedJob", "AIMessageSuccessStoppedByUser",
    "AIMessageErrorNoPathFound", "AIMessageErrorOutOfMoney",
    "AIMessageErrorNoHelperAvailable", "AIMessageErrorBlockedByObject",
    "AIMessageErrorVehicleBroken", "AIMessageErrorVehicleDeleted",
    "AIMessageErrorUnknown", "AIMessageErrorFieldNotOwned",
    "AIMessageErrorNoFieldFound", "AIMessageErrorNotReachable",
    "AIMessageErrorOutOfFill", "AIMessageErrorOutOfFuel",
    "AIMessageErrorIsFull", "AIMessageErrorWrongFillType",
    -- aus AIDriveStrategyFieldCourse
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
-- Spielverkehr
-- Die Autos des Spielverkehrs (g_currentMission.trafficSystem) bremsen nur fuer
-- angemeldete Objekte. Das Spiel meldet Spieler zu Fuss und besetzte Fahrzeuge an
-- (Enterable: addTrafficSystemPlayer mit components[1].node), fahrerlose nicht.
-- Deshalb melden wir Traktor und Geraete beim Losfahren an und beim Parken im Pool,
-- Loeschen und Spielende wieder ab. Abschaltbar ueber <spielverkehrAnmelden>.
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
        print("LivingRoads: [TRAFFIC] Fahrzeuge werden beim Spielverkehr angemeldet (Autos bremsen fuer sie)")
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
-- driveToField: GOTO-Job zum naechsten Ziel des Verkehrs
-- farmId darf nicht 0 (Spectator) sein, sonst lehnt die Engine den Job
-- sofort ab und onAIJobFinished kommt nach wenigen ms.
-- ============================================================
function NachbarFelderManager:driveToField(vehicle, fieldId, x, y, z, angleSD)
    if x == nil or z == nil then return end

    -- Kein eigenes createAgent: AIJobGoTo ruft es intern auf, ein zusaetzlicher
    -- Aufruf vorher bringt den Agent-State durcheinander.
    if vehicle.prepareForAIDriving ~= nil then
        vehicle:prepareForAIDriving()
    end

    -- Anbaugeräte für die Straßenfahrt einklappen
    if vehicle.getAttachedImplements ~= nil then
        for _, att in ipairs(vehicle:getAttachedImplements()) do
            local impl = att.object
            if impl ~= nil then
                if impl.prepareForAIDriving ~= nil then
                    impl:prepareForAIDriving()
                end
                -- Einklappen mit -turnOnFoldDirection wie im Spiel (FillUnit), nicht mit
                -- festem -1: Geraete mit turnOnFoldDirection = -1 wuerden sonst ausklappen.
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

    -- nicht eingeklappte Geraete loggen und nach 10 s nachpruefen
    local function schritt()
        if vehicle.getAttachedImplements == nil then return end
        for _, att in ipairs(vehicle:getAttachedImplements()) do
            local impl = att.object
            if self:getIstEingeklappt(impl) == false then
                print("LivingRoads: [KLAPP] Einklappbefehl gegeben, noch offen: " .. self:getKlappText(impl))
                self.klappPruefung = self.klappPruefung or {}
                table.insert(self.klappPruefung, { impl = impl, at = g_time + 10000 })
            end
        end
    end
    schritt()

    -- Motor kann nach einem abgebrochenen Job aus sein
    if vehicle.startMotor ~= nil and vehicle.getIsMotorStarted ~= nil
       and not vehicle:getIsMotorStarted() then
        vehicle:startMotor(true)
    end

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.GOTO)
    -- Kostenneutral: AIJob:updateCost() bucht getPricePerMs() je ms ab und stoppt
    -- mit AIMessageErrorOutOfMoney, wenn das Konto nicht reicht. Mit Preis 0 gibt es
    -- weder Buchung noch Geldpruefung auf der NPC-Farm.
    if job ~= nil then
        job.getPricePerMs = function() return 0 end
    end
    if job == nil then
        print("LivingRoads: FEHLER - AIJobType.GOTO konnte nicht erstellt werden!")
        return
    end
    job.positionAngleParameter:setPosition(x, z)
    job.positionAngleParameter:setAngle(angleSD or 0)
    job.vehicleParameter:setVehicle(vehicle)
    job:setValues()

    -- kommt bei jedem Hop, daher nur auf logLevel 2
    self:log(2, "LivingRoads: GOTO Start -> x=" .. tostring(math.floor(x or 0)) ..
        " z=" .. tostring(math.floor(z or 0)) ..
        " farmId=" .. tostring(self.farmId) ..
        " Feld=" .. tostring(fieldId))

    -- Ohne createAgent kein GOTO-Job: AIJobGoTo ruft es intern auf und die Engine stürzt ab.
    if vehicle.createAgent == nil then
        local fname = vehicle.configFileName
        local baseName = fname ~= nil and (string.match(fname, "[^/\\]+$") or fname) or tostring(vehicle.typeName)
        print("LivingRoads: kein createAgent auf " .. baseName .. " - Fahrzeug wird gesperrt")
        -- für den Rest der Sitzung nicht mehr spawnen
        if fname ~= nil then
            self.trafficVehicleBlacklist = self.trafficVehicleBlacklist or {}
            if not self.trafficVehicleBlacklist[fname] then
                self.trafficVehicleBlacklist[fname] = true
                print("LivingRoads: [TRAFFIC] Blacklist: " .. baseName .. " (kein createAgent)")
                self.trafficVehicleList = nil
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

    -- Vor startJob: aiSystem:startJob prüft vehicle.ownerFarmId == farmId, und
    -- MISSION-Fahrzeuge können trotz farmId beim Laden ownerFarmId 0 haben.
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

    self:meldeGespannBeimSpielverkehrAn(vehicle)

    -- Zustand direkt nach dem Start, fuer Jobs, die ohne Fehler anlaufen und trotzdem stehen
    if nfW ~= nil and nfW.isPatrol then
        print("LivingRoads: [DIAG] nach Start: " .. self:getVehicleAiDiag(vehicle))
    end
end

--- Ist das Geraet eingeklappt? Eingeklappt ist das Animationsende entgegen
--- turnOnFoldDirection (wie in Foldable).
--- @return boolean|nil nil, wenn das Geraet keine Klappteile hat
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

                -- optional vorgegebenen Fülltyp erzwingen (z. B. HERBICIDE)
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

-- Umgekippt, wenn die Hochachse des Traktors weniger nach oben zeigt (cos ~72 Grad)
NachbarFelderManager.KIPP_GRENZE = 0.3

-- ============================================================
-- Verkehr: Zielpunkte
-- ============================================================
--- Liefert ein Ziel fuer den Verkehr: einen gesetzten Wegpunkt oder, falls keine
--- existieren, eine zufaellige Kartenposition ausserhalb aller Felder.
function NachbarFelderManager:getTrafficWaypoint()
    -- Gesetzte Wegpunkte haben Vorrang, damit kein Fahrzeug mitten auf dem Feld haelt.
    if self.userTrafficWaypoints ~= nil and #self.userTrafficWaypoints > 0 then
        local wp = self.userTrafficWaypoints[math.random(#self.userTrafficWaypoints)]
        return wp.x, wp.z
    end

    local fields = g_fieldManager:getFields()

    -- Felder als Kreise aus areaHa annähern, plus 60 m Puffer
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

    local halfSize = 1400
    if g_currentMission.terrainSize ~= nil then
        halfSize = g_currentMission.terrainSize * 0.34
    end

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

-- Hilfsfunktionen für die Verkehrslisten
local function nfIsWaterVehicle(filename)
    local f = filename:lower()
    return f:find("boat")        ~= nil or f:find("ship")      ~= nil
        or f:find("ferry")       ~= nil or f:find("barge")     ~= nil
        or f:find("vessel")      ~= nil or f:find("aquaculture") ~= nil
        or f:find("maritime")    ~= nil or f:find("fishing")   ~= nil
        or f:find("highlandsfishing") ~= nil
end

-- Shop-Werte nachladen. storeItem.specs ist nach dem Laden nil und wird erst beim
-- Oeffnen des Shops gefuellt, auf dem Dedicated Server also nie. Nur fuer
-- Kandidaten aufrufen, es liest pro Artikel eine XML-Datei.
local function nfLoadSpecs(item)
    if item ~= nil and item.specs == nil and StoreItemUtil ~= nil
       and StoreItemUtil.loadSpecsFromXML ~= nil then
        if StoreItemUtil ~= nil and StoreItemUtil.loadSpecsFromXML ~= nil then
            StoreItemUtil.loadSpecsFromXML(item)
        end
    end
end

-- Leergewicht laut Shop in kg, nil wenn unbekannt.
-- specs.weight ist keine Zahl, sondern eine Tabelle (Vehicle.loadSpecValueWeight);
-- die Masse in Tonnen liefert erst Vehicle.getSpecValueWeight.
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

-- Motorleistung laut Shop (specs.power), nil wenn unbekannt.
local function nfGetItemPower(item)
    nfLoadSpecs(item)
    local p = nil
    if item.specs ~= nil then p = tonumber(item.specs.power) end
    return (type(p) == "number" and p > 0) and p or nil
end

-- Leistungsbedarf eines Geraets (specs.neededPower.base), gleiche Einheit wie specs.power.
local function nfGetItemNeededPower(item)
    nfLoadSpecs(item)
    local p = nil
    local np = item.specs ~= nil and item.specs.neededPower or nil
    if type(np) == "table" then p = tonumber(np.base) else p = tonumber(np) end
    return (type(p) == "number" and p > 0) and p or nil
end

-- Arbeitsbreite laut Shop in m, nil wenn unbekannt.
-- specs.workingWidth = { width, minWidth }; bei Breiten-Konfigurationen steht sie in
-- specs.workingWidthConfig[configName][index].width. Dann zaehlt die groesste,
-- weil die geladene Standard-Konfiguration nicht sicher bekannt ist.
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

-- Hoechstgeschwindigkeit laut Shop (specs.maxSpeed) in km/h, nil wenn unbekannt.
local function nfGetItemMaxSpeed(item)
    nfLoadSpecs(item)
    local specs = item ~= nil and item.specs or nil
    if type(specs) ~= "table" then
        return nil
    end
    local v = tonumber(specs.maxSpeed)
    return (type(v) == "number" and v > 0) and v or nil
end

-- Nutzlast laut Shop in Litern, nil wenn unbekannt.
local function nfGetItemCapacity(item)
    local cap = nil
    if item.specs ~= nil then
        cap = tonumber(item.specs.maxCapacity) or tonumber(item.specs.capacity)
    end
    return (type(cap) == "number" and cap > 0) and cap or nil
end

-- Grenzwerte fuer den Verkehr. Einen Navigations-Agent fuer GOTO haben in FS25
-- nur Traktoren; Autos, Lkw und Motorraeder scheitern sofort.
local NF_MAX_VEH_WEIGHT_KG       = 18000  -- kg, schliesst Sattelzugmaschinen aus
local NF_MAX_TRAILER_WEIGHT_KG   =  6000  -- kg Leergewicht, fuer alle Groessenstufen
-- Kapazitaet in l je trafficTrailerSize (0 = keine, 1 = klein, 2 = mittel, 3 = alle)
local NF_TRAILER_CAP_BY_SIZE = { [0]=0, [1]=4000, [2]=8000, [3]=15000 }

-- Enge Karte: Klein- und Mitteltraktoren. 12 t laesst Fendt 700 (~9 t) oder
-- JD 6R (~11 t) durch und faengt falsch in TRACTORSM einsortierte Brocken ab.
local NF_ENG_MAX_VEH_WEIGHT_KG  = 12000
-- Kleintraktoren wiegen 3-6 t; 7 t faengt falsch in TRACTORSS einsortierte ab.
local NF_KLEIN_MAX_VEH_WEIGHT_KG = 7000
-- Mini- und Raupen-Kompakttraktoren (10-20 km/h) halten den Verkehr auf und
-- bleiben gern stehen. Unbekanntes Tempo zaehlt nicht als zu langsam.
local NF_MIN_VEH_SPEED_KMH = 30
-- Ersatzmass fuer Geraete ohne Breitenangabe: ein 8-m-Schwader zaehlt als RAKES,
-- ist aber breiter als der halbe Feldweg.
local NF_ENG_MAX_IMPL_WEIGHT_KG = 3000
-- Groessenverhaeltnis Traktor/Geraet: erlaubte Arbeitsbreite je Tonne Traktorgewicht,
-- mit Unter- und Obergrenze. Bei unbekanntem Traktorgewicht gilt die Untergrenze.
local NF_IMPL_BREITE_JE_TONNE = 1.2   -- m Arbeitsbreite je t Traktor
local NF_IMPL_BREITE_MIN      = 3.0   -- m, so breit darf es immer sein
local NF_IMPL_BREITE_MAX      = 6.0   -- m, breiter nie (Kleintraktoren bis 7 t)
-- Geraete ohne lesbare Arbeitsbreite nur, wenn sie hoechstens so viel wiegen.
local NF_IMPL_OHNE_BREITE_MAX_KG = 1000

-- Kategorien bei engeMap. Rad- und Teleskoplader bleiben draussen: kurz, aber
-- breit, und sie rangieren staendig.
local NF_ENG_CATS = { TRACTORSS = true, TRACTORSM = true }

-- Fahrzeuge ohne Navigations-Agent werden beim ersten Spawn gesperrt.
local nfMotorCats = {
    TRACTORSS=true,              -- Kleintraktoren  (bis ~100 PS)
    TRACTORSM=true,              -- Mitteltraktoren (100-200 PS)
    TRACTORSL=true,              -- Grosstraktoren  (200+ PS)
    WHEELLOADERVEHICLES=true,
    TELELOADERVEHICLES=true,
    CARS=true,
    MOTORCYCLES=true,
}

-- ============================================================
-- Fahrzeugliste fuer den Verkehr
-- ============================================================
function NachbarFelderManager:buildTrafficVehicleList()
    self.trafficVehicleList = {}
    if g_storeManager == nil then return end

    local allItems = {}
    if g_storeManager ~= nil and g_storeManager.getItems ~= nil then allItems = g_storeManager:getItems() end

    local eng = (self.engeMap ~= false)

    -- nfMotorCats als Basis, vehicleCatEnabled ueberschreibt
    local activeCats = {}
    for cat, _ in pairs(nfMotorCats) do
        if self.vehicleCatEnabled ~= nil and self.vehicleCatEnabled[cat] ~= nil then
            activeCats[cat] = self.vehicleCatEnabled[cat]
        else
            activeCats[cat] = true
        end
    end

    -- Als Nachbarverkehr nur Kleintraktoren, auf jeder Karte. Wer TRACTORSS
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
            if tempo ~= nil and tempo < NF_MIN_VEH_SPEED_KMH then
                zuLangsam = zuLangsam + 1
                print(string.format("LivingRoads: [TRAFFIC]   zu langsam (%.0f km/h): %s", tempo,
                    tostring(string.match(item.xmlFilename, "[^/\\]+$") or item.xmlFilename)))
            -- unbekanntes Gewicht nur als Notfallliste, siehe unten
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
        -- Ist fuer keinen Kleintraktor ein Gewicht lesbar, lieber nur nach
        -- Kategorie filtern als gar kein Verkehr.
        for _, e in ipairs(ohneGewicht) do
            table.insert(self.trafficVehicleList, e)
        end
        print("LivingRoads: [TRAFFIC] Warnung: kein Traktorgewicht lesbar - Liste nur nach Kategorie")
    end
    print(string.format("LivingRoads: [TRAFFIC] Fahrzeugliste: %d Kleintraktoren bis %.0f t" ..
        " (%d ohne lesbares Gewicht, %d unter %d km/h aussortiert)", #self.trafficVehicleList,
        NF_KLEIN_MAX_VEH_WEIGHT_KG / 1000, #ohneGewicht, zuLangsam, NF_MIN_VEH_SPEED_KMH))
end

-- ============================================================
-- Anbaugeraete fuer den Verkehr
-- Nur Feldgeraete ohne Transportfunktion (kein Fuellvolumen).
-- ============================================================
--- Sofortige Abweisung eines Verkehrsgespanns dem Anbaugeraet anrechnen.
--- Gesperrt (fuer diese Sitzung) wird erst nach 3 Abweisungen an mindestens
--- 2 Stellen, damit ein schlechter Standort allein nichts sperrt.
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
        print(string.format("LivingRoads: [TRAFFIC] Anbaugeraet [%s] %dx sofort abgewiesen an %d Stellen" ..
            " - fuer diese Session nicht mehr im Verkehr", tostring(filename), e.n, #e.orte))
    end
end

function NachbarFelderManager:getIstVerkehrGeraetGesperrt(filename)
    if filename == nil or self.verkehrGeraetAbw == nil then return false end
    local e = self.verkehrGeraetAbw[string.lower(tostring(filename))]
    return e ~= nil and e.gesperrt == true
end

--- Passt das Geraet zum Traktor?
--- Leistungsbedarf hoechstens die Motorleistung, Gewicht hoechstens die Haelfte
--- des Traktors. Fehlt ein Wert, gilt die vorsichtige Variante (nur kleine, leichte Geraete).
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
    -- Arbeitsbreite muss zur Traktorgroesse passen
    if geraet.breiteM ~= nil and geraet.breiteM > self:getMaxGeraeteBreite(traktor) then
        return false
    end
    return true
end

--- Groesste erlaubte Arbeitsbreite eines Geraets fuer diesen Traktor in m.
function NachbarFelderManager:getMaxGeraeteBreite(traktor)
    local t = (traktor ~= nil and traktor.gewichtKg ~= nil) and (traktor.gewichtKg / 1000) or 0
    local maxB = t * NF_IMPL_BREITE_JE_TONNE
    if maxB < NF_IMPL_BREITE_MIN then maxB = NF_IMPL_BREITE_MIN end
    if maxB > NF_IMPL_BREITE_MAX then maxB = NF_IMPL_BREITE_MAX end
    return maxB
end

function NachbarFelderManager:buildTrafficTrailerList()
    self.trafficTrailerList   = {}  -- schwer: Pflug, Maehwerk (nur Grosstraktoren)
    self.trafficImplListLight = {}  -- leicht: Rechen, Zinkenrotor
    if (self.trafficTrailerSize or 2) == 0 then
        print("LivingRoads: [TRAFFIC] Anbaugeraete: deaktiviert (Einstellung = 0)")
        return
    end
    if g_storeManager == nil then return end

    -- Nur Kategorien, die im Transportzustand unter Bruecken passen.
    -- CULTIVATORS/DRILLS fehlen bewusst: die gefalteten Fluegel ragen zu hoch.
    local heavyCats = { PLOWS=true, MOWERS=true }   -- Grosstraktor
    local lightCats = { TEDDERS=true, RAKES=true }  -- Mittelklasse

    -- Schwere Geraete passen nur an Grosstraktoren, und die werden nicht gespawnt.
    heavyCats = {}

    local allItems = {}
    if g_storeManager ~= nil and g_storeManager.getItems ~= nil then allItems = g_storeManager:getItems() end

    local eng = (self.engeMap ~= false)

    for _, item in pairs(allItems) do
        -- Kategorie zuerst pruefen: das Laden der Werte liest pro Artikel eine XML-Datei.
        if item ~= nil and item.xmlFilename ~= nil and lightCats[item.categoryName]
           and not nfIsWaterVehicle(item.xmlFilename) then
            local w   = nfGetItemWeight(item)
            local cap = nfGetItemCapacity(item)
            if (cap == nil or cap == 0) and w ~= nil and w <= NF_ENG_MAX_IMPL_WEIGHT_KG then
                -- Unbekannte Arbeitsbreite nur bei leichten Geraeten zulassen
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

    print("LivingRoads: [TRAFFIC] Anbaugeraete: " ..
        tostring(#self.trafficTrailerList) .. " schwer (Pflug/Maehwerk)" ..
        " + " .. tostring(#self.trafficImplListLight) .. " leicht (Rechen/Zinkenrotor)" ..
        (eng and "  [enge Karte: nur leichte bis "
                  .. tostring(NF_ENG_MAX_IMPL_WEIGHT_KG / 1000) .. " t]" or ""))
end

-- ============================================================
-- Tagesrhythmus
-- Das Verkehrslimit folgt der Uhrzeit, nachts schlaeft alles im Pool
-- (kein Loeschen/Spawnen noetig). Abschaltbar mit dayRhythm=false.
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

--- Fahrzeug-Zustand fuer die Log-Diagnose, wenn ein GOTO startet, das Fahrzeug
--- aber nicht losfaehrt. Ohne gueltiges agentInfo liefert getCanStartAIVehicle()
--- immer false (siehe AIDrivable.lua).
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
    -- ClassUtil.getClassNameByObject existiert zur Laufzeit nicht immer, daher die Pruefung
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
-- Fahrzeug-Pool
-- Spawnen ist teuer (I3D-Laden, Physik, MP-Sync) und verursacht
-- Server-Ruckler. Patrol-Fahrzeuge werden deshalb am Ende nicht
-- geloescht, sondern schlafen gelegt (Job stoppen, Motor aus) und
-- spaeter wiederverwendet. poolSize=0 schaltet den Pool ab.
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

--- Festsitzendes Fahrzeug auf einen freien Punkt der KI-Strasse setzen.
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
        print(string.format("LivingRoads: [TRAFFIC] steckte fest - %.0f m weiter auf die KI-Strasse gesetzt",
            rdist or 0))
    end
    return ok
end

--- Steht ein anderes Nachbar-Fahrzeug in der Naehe ebenfalls still?
--- Zwei KI-Fahrzeuge, die aufeinander warten, loesen das nicht von selbst auf.
--- @return table|nil Eintrag aus vehicleType des stehenden Nachbarn
function NachbarFelderManager:getStehenderNachbar(eigenerEintrag, x, z, radius, fx, fz)
    -- Gegenverkehr wartet beim Wenden oft weit entfernt, daher grosser Radius. Jenseits
    -- von BEGEGNUNG_NAH zaehlt der Nachbar nur, wenn er grob voraus steht (60 Grad zu fx/fz).
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

--- Begegnung zweier stehender Nachbar-Fahrzeuge aufloesen.
--- Das Fahrzeug, dessen Waechter zuerst ausloest, weicht aus: neues Ziel und mind. 25 m
--- in dessen Richtung auf die KI-Strasse versetzt. Der Nachbar behaelt sein Ziel und
--- bekommt neue Wartezeit. Ohne freien Ausweichplatz passiert nichts.
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
    print(string.format("LivingRoads: [TRAFFIC] Begegnung mit %s - weicht %.0f m auf die KI-Strasse aus," ..
        " neues Ziel WP%s (patrolId=%s)", name2, rdist or 0, tostring(newDest), tostring(w.fieldId)))
    return true
end

--- Naechstes Fahrzeug zu (x, z), das nicht zum eigenen Gespann gehoert.
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

-- Steht irgendein Fahrzeug (auch von Spielern) im Umkreis um (x,z)?
-- Vor jedem Teleport pruefen: auf einem belegten Platz explodiert die Physik.
-- excludeVeh: eigenes Gespann wird ignoriert.
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
-- 6 Alternativen. Frei heisst: kein Pool-Schlaefer und kein anderes Fahrzeug.
-- nil, wenn nichts frei ist (dann nicht teleportieren).
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

-- Patrol-Eintrag schlafen legen: AI-Jobs stoppen, in den Pool aufnehmen,
-- aktiven Eintrag entfernen. false heisst: Aufrufer loescht normal.
-- inPlace beeinflusst nur noch den Log-Text, geschlafen wird immer am Standort.
function NachbarFelderManager:sleepPatrolEntry(entry, inPlace)
    if entry == nil or entry.NachbarFelderWorker == nil then return false end
    local w = entry.NachbarFelderWorker
    if not w.isPatrol then return false end
    if self.isShuttingDown then return false end
    if (self.poolSize or 0) <= 0 then return false end
    if w.noPool then return false end
    self.trafficPool = self.trafficPool or {}
    -- Pool-Deckel mindestens trafficLimit, sonst wird bei trafficLimit > poolSize
    -- jede Nacht geloescht und morgens neu gespawnt (genau die Ruckler, die der
    -- Pool verhindern soll).
    local cap = math.max(self.poolSize or 0, self.trafficLimit or 0)
    if #self.trafficPool >= cap then return false end

    -- Nur lebende Fahrzeuge poolen; ohne Traktor kein Pool-Eintrag
    local vehs = {}
    for _, veh in ipairs(entry.vehicleType or {}) do
        if self:getIsVehicleAlive(veh) then table.insert(vehs, veh) end
    end
    local tractor = vehs[1]
    if tractor == nil then return false end

    -- Status vor dem Job-Stopp setzen: stopAIJobSafely ruft synchron
    -- onAIJobFinished auf, dessen Status-1/60-Logik sonst neu zielt oder
    -- teleportiert (wie in deleteAllVehicles).
    w.status = 9999

    -- Ein schlafendes Fahrzeug darf keinen Job im aiSystem behalten
    -- (sonst Frame-Fehler wie bei geloeschten Fahrzeugen)
    for _, veh in ipairs(vehs) do
        self:stopAIJobSafely(veh)
        self:meldeBeimSpielverkehrAb(veh)   -- schlafend wie ein abgestelltes Fahrzeug
    end

    -- Nicht zu mehreren am selben Fleck einschlafen, sonst stauen sich Schlaefer
    -- z. B. in Sackgassen. Bei belegtem Platz 25-150 m weiter auf die Strasse setzen.
    local function schritt()
        if tractor.rootNode == nil or self.getNearestRoadPoint == nil then return end
        local vx, _, vz = getWorldTranslation(tractor.rootNode)
        if not self:isSpotBlockedByAnyVehicle(vx, vz, 25, tractor) then return end
        local rx, rz, rry = self:getNearestRoadPoint(vx, vz, 150, 25)
        if rx == nil or self:isSpotBlockedByAnyVehicle(rx, rz, 12, tractor) then
            print("LivingRoads: [TRAFFIC] Schlafplatz belegt, kein freier Strassenplatz" ..
                " in der Naehe - Fahrzeug bleibt stehen")
            return
        end
        g_currentMission:teleportVehicle(tractor, rx, rz, rry or 0)
        print(string.format("LivingRoads: [TRAFFIC] Schlafplatz war belegt - Fahrzeug %.0f m" ..
            " weiter auf die KI-Strasse gestellt", MathUtil.vector2Length(rx - vx, rz - vz)))
    end
    schritt()

    -- Geschlafen wird dort, wo die KI angehalten hat: die Ausrichtung zur Fahrbahn
    -- stimmt, und das Fahrzeug muss nie neu geladen werden (ein Modell zu laden
    -- kostet den Server auf HDD mehrere hundert ms Stillstand).
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
    print("LivingRoads: [POOL] " .. base .. " schlaeft" ..
        (inPlace and " an Ort und Stelle (Hops fertig)" or " an Ort und Stelle") ..
        " - Pool: " .. tostring(#self.trafficPool) .. "/" .. tostring(self.poolSize))

    -- Aktiven Eintrag entfernen (wie deleteMission fuer Patrol)
    self.vehicleType[w.fieldId] = nil
    self.counter = self.counter - 1
    return true
end

-- Schlafendes Pool-Fahrzeug aufwecken: neue Route/Hops zuweisen und vom
-- aktuellen Standort losfahren lassen, ohne I3D-Laden.
-- Liefert true, wenn ein Fahrzeug geweckt wurde.
function NachbarFelderManager:wakePooledVehicle()
    if self.trafficPool == nil or #self.trafficPool == 0 then return false end
    -- Alle Fahrziele zaehlen, nicht nur eigene Wegpunkte: mit zielQuelle=strassen
    -- gibt es auch ganz ohne eigene Punkte genug Ziele.
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
            print("LivingRoads: [POOL] Eintrag verworfen (Fahrzeug existiert nicht mehr)")
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
    -- Parkpunkt-Anzahl dieser Kopie merken: spaeter gesetzte Parkpunkte verschieben
    -- die Nummern nur in neuen Listen, #userTrafficWaypoints passt dann nicht mehr.
    worker.anzahlParkpunkte = math.min(#(self.userTrafficWaypoints or {}), #waypoints)
    worker.patrolDestIdx = destIdx
    worker.patrolTargetX = waypoints[destIdx][1]
    worker.patrolTargetZ = waypoints[destIdx][2]
    worker.parkSecs      = nfCatParkSecs((waypoints[destIdx] or {})[4] or 0)
    worker.hopsLeft      = math.random(self.patrolHopsMin or 10,
                                       self.patrolHopsMax or 20)
    -- Standort-WP bestimmen (Fehlerbuchhaltung, Ziel darf nicht der Standort sein)
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
    print("LivingRoads: [POOL] " .. base .. " aufgeweckt -> Ziel WP" ..
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
        print("LivingRoads: [POOL] geleert - " .. tostring(n) .. " Fahrzeug(e) geloescht")
    end
end

-- Admin-Vollreinigung: aktive Eintraege und Pool entfernen.
-- deleteAllVehicles legt Patrols erst in den Pool, deshalb wird er danach geleert.
function NachbarFelderManager:deleteAllVehiclesAndPool(quit)
    -- Als Tasten-/Client-Aktion nur fuer Admins. Auf dem Server selbst
    -- (Konsole, Events nach Admin-Pruefung) laeuft es immer durch.
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

    -- Max. gleichzeitig aktive Patrol-Fahrzeuge, abhaengig von der Uhrzeit
    local activePatrol = self:countActivePatrols()
    local effLimit     = self:getEffectiveTrafficLimit()
    if activePatrol >= effLimit then return false end

    -- Farm-ID sicherstellen (muss vor loadVehicles und startJob gesetzt sein)
    self:getEffectiveFarmId()

    -- Schlafendes Fahrzeug wecken statt neu spawnen (Shop-Blocker gilt dafuer nicht).
    -- Aber erst, wenn die Flotte das Limit erreicht, sonst waechst sie nie ueber
    -- die Zahl der Pool-Fahrzeuge hinaus.
    local flotte = activePatrol + #(self.trafficPool or {})
    if forcedVehicleXML == nil and flotte >= effLimit and self:wakePooledVehicle() then
        return true
    end

    -- Mit Admin-Spawnpunkten nur spawnen, wenn einer frei ist (lieber einen Takt
    -- warten als im Ort laden). Der Shop-Blocker entfaellt dann.
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

    -- Fahrzeug aus der Store-Liste (einmalig gecacht, alle motorisierten Fahrzeuge)
    if self.trafficVehicleList == nil then self:buildTrafficVehicleList() end
    if #self.trafficVehicleList == 0 then return false end
    local vehInfo
    if forcedVehicleXML ~= nil then
        -- Stammfahrzeug (wiederkehrender Nachbar); fehlt es in der Liste
        -- (z. B. zu langsam), kommt ein zufaelliges
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

    -- Gespann-Quote: trailerChance (0-100 %) wird als laufende Quote erzwungen
    -- statt gewuerfelt. So stimmt der Anteil auch bei wenigen Spawns, wichtig,
    -- weil der Pool die Mischung der Aufwaermphase dauerhaft einfriert.
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
        -- Nur leichte Geraete, die zum Traktor passen; passt keins, faehrt er solo
        local implList = nil
        local passend = {}
        for _, impl in ipairs(self.trafficImplListLight or {}) do
            if self:getPasstGeraetZuTraktor(vehInfo, impl)
               and not self:getIstVerkehrGeraetGesperrt(impl.filename) then
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

    -- Route: Admin-Wegpunkte oder ersatzweise zufaellige Positionen.
    -- Die Navigation laeuft in beiden Faellen ueber das Strassennetz.
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
    -- Unter 3 WPs gibt es keine sinnvollen Routen (Stau, Ziele sofort gesperrt),
    -- etwa waehrend ein neues WP-Netz aufgenommen wird.
    if #waypoints < 3 then
        if not self.wpFewWarned then
            self.wpFewWarned = true
            print("LivingRoads: [TRAFFIC] Zu wenige Wegpunkte (" ..
                tostring(#waypoints) .. "/3) - kein Traffic-Spawn bis mehr WPs gesetzt sind.")
        end
        return false
    end
    self.wpFewWarned = nil

    -- Startpunkt bestimmt Status 1 (naechster WP zum Shop). Ziel zufaellig,
    -- gesperrte WPs werden gemieden. Nach den Hops geht es heim.
    local nWps    = #waypoints
    -- Erstes Ziel in Hop-Reichweite des Shops
    local shopRefX, shopRefZ = self:getShopPosition()
    local destIdx = self:pickPatrolWaypoint(waypoints, nil, shopRefX, shopRefZ) or math.random(nWps)

    -- Pseudo-Key: negative ID
    self.patrolCounter = self.patrolCounter - 1
    local patrolId = self.patrolCounter

    local worker = NachbarFelderWorker.new({}, proxyMission, 0, patrolId)
    worker.isPatrol      = true
    worker.waypoints     = waypoints
    -- Parkpunkt-Anzahl dieser Kopie merken (siehe wakePooledVehicle)
    worker.anzahlParkpunkte = math.min(#(self.userTrafficWaypoints or {}), #waypoints)
    local firstDestCat   = (waypoints[destIdx] or {})[4] or 0
    worker.waypointIdx   = 1                        -- Platzhalter, setzt onSpawnedVehicle
    worker.patrolDestIdx = destIdx
    worker.patrolTargetX = waypoints[destIdx][1]
    worker.patrolTargetZ = waypoints[destIdx][2]
    worker.parkSecs      = nfCatParkSecs(firstDestCat)
    worker.firstStart         = true               -- Sofort-Teleport in onSpawnedVehicle
    worker.overrideSpawnWpIdx = overrideSpawnWpIdx -- Batch-Spawn: fester Startpunkt, nil = zufaellig
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

    -- Gespann-Quote fortschreiben (nur Traktor-Spawns zaehlen)
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
    print("LivingRoads: [TRAFFIC] " .. tostring(fname) ..
        (trailerAdded and (" + " .. tostring(string.match(vehList[2].filename or "", "[^/\\]+$") or "Anbaugeraet")
            .. string.format(" (%s m, Traktor %.1f t, max %.1f m)",
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

--- Position des Zugfahrzeugs eines Workers.
--- @return x, z oder nil, nil
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
--- Laufender Spieltag (environment.currentMonotonicDay), zaehlt ueber Monats- und
--- Jahresgrenzen hinweg weiter (so nutzt es auch AbstractMission:setDefaultEndDate).
--- @return Spieltag oder nil, solange die Umgebung fehlt
function NachbarFelderManager:getSpieltag()
    local env = g_currentMission ~= nil and g_currentMission.environment or nil
    if env == nil or type(env.currentMonotonicDay) ~= "number" then return nil end
    return env.currentMonotonicDay
end

--- Monatswechsel: Aufraeumen erst, wenn seit dem letzten Mal mindestens aufraeumenMinTage
--- Spieltage vergangen sind (Server-Konfig, Standard 7, 0 = nie). Die Monatslaenge ist 1 bis
--- 28 Tage einstellbar; ohne diese Sperre wuerde bei 1 Tag/Monat jeden Tag aufgeraeumt.
--- Der Zaehler wird nicht gespeichert, Fahrzeuge und Pool ueberleben einen Neustart ohnehin nicht.
function NachbarFelderManager:onPeriodChanged()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local minTage = self.aufraeumenMinTage or NachbarFelderManager.AUFRAEUMEN_MIN_TAGE
    if minTage <= 0 then return end
    local tag = self:getSpieltag()
    local env = g_currentMission.environment
    local tageProMonat = env ~= nil and env.daysPerPeriod or nil
    if tag == nil then
        -- Ohne Tageszaehler bei jedem Monatswechsel aufraeumen
        print("LivingRoads: WARNUNG - Spieltag nicht verfuegbar, Aufraeumen beim Monatswechsel wie bisher")
        self:deleteAllVehicles()
        return
    end
    if self.aufraeumTag == nil or tag < self.aufraeumTag then
        self.aufraeumTag = tag
        return
    end
    local vergangen = tag - self.aufraeumTag
    if vergangen < minTage then
        self:log(2, string.format("LivingRoads: Monatswechsel - kein Aufraeumen (%d von %d Spieltagen," ..
            " %s Tage pro Monat)", vergangen, minTage, tostring(tageProMonat)))
        return
    end
    print(string.format("LivingRoads: Monatswechsel - Nachbar-Fahrzeuge werden aufgeraeumt (%d Spieltage seit" ..
        " dem letzten Mal, %s Tage pro Monat)", vergangen, tostring(tageProMonat)))
    self.aufraeumTag = tag
    self:deleteAllVehicles()
end

function NachbarFelderManager:deleteAllVehicles(quit)
    -- Beim Shutdown nichts löschen: prepareForShutdown hat die AI-Jobs gestoppt,
    -- die Fahrzeuge löscht die Engine selbst (sonst "delete twice"-Callstacks).
    if self.isShuttingDown then return end

    -- Nur der Server löscht, Clients schicken ein Event
    if not g_currentMission:getIsServer() then
        if g_client ~= nil then
            g_client:getServerConnection():sendEvent(NachbarFelderDeleteEvent.new())
        end
        return
    end

    if self.vehicleType == nil then return end

    for v, k in pairs(self.vehicleType) do
        -- Patrol-Fahrzeuge kommen in den Pool statt geloescht zu werden und lassen
        -- sich spaeter ohne Spawn-Ruckler wecken. deleteAllVehiclesAndPool leert ihn.
        if k.NachbarFelderWorker ~= nil and k.NachbarFelderWorker.isPatrol
           and self:sleepPatrolEntry(k, false) then
            -- gepoolt; Eintrag wurde bereits entfernt
        else
            local status = k.NachbarFelderWorker.status
            k.NachbarFelderWorker.status = 9999
            for _, veh in ipairs(k.vehicleType) do
                -- toggleAIVehicle reicht nicht: der Job bliebe im aiSystem und
                -- wirft nach delete jeden Frame Fehler
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
    if self.vehicleType[fieldId] == nil then return end
    self.vehicleType[fieldId] = nil
    self.counter = self.counter - 1
end

-- ============================================================
-- Shop-Position für Rückfahrt (Navmesh-Spawnpunkt, Straße)
-- ============================================================
function NachbarFelderManager:getShopPosition()
    -- Shop-Spawnplatz des Spiels (bei Filiallieferungen der Lieferort)
    local place = self:getNfSpawnPlace()
    if place ~= nil then
        return place.startX or 0, place.startZ or 0
    end
    return 0, 0
end

-- ============================================================
-- Shop-Gebäudeposition (Hofplatz, nicht Straßen-Spawnpunkt).
-- nil, nil wenn nicht gefunden; der Aufrufer nimmt dann die Straße.
-- ============================================================
function NachbarFelderManager:getShopBuildingPosition()
    local bx, bz = nil, nil
    -- Zuerst PlaceableVehicleShop im PlaceableSystem
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
    -- Fallback: g_currentMission.vehicleShops (einige Maps)
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
        print("LivingRoads: [TRAFFIC] Shop-Gebaeude x=" .. math.floor(bx) .. " z=" .. math.floor(bz))
    end
    return bx, bz
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================
-- Prüft, ob ein Fahrzeug noch existiert. Nach veh:delete() bleiben Referenzen
-- in unseren Tabellen, ein Zugriff auf rootNode wirft dann Fehler (auf dem
-- Dedicated Server laeuft das Log voll, Joins schlagen fehl). Vor jedem Zugriff prüfen.
function NachbarFelderManager:getIsVehicleAlive(veh)
    return veh ~= nil and veh.isDeleted ~= true and veh.rootNode ~= nil
end

-- Markiert Traktor und alle Anbaugeräte als Helfer-Fahrzeug.
-- getIsMissionWorkAllowed wird pro Arbeitsbereich mit dem jeweiligen Gerät
-- aufgerufen, das Flag am Traktor allein genügt daher nicht.
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

--- Ist mindestens ein Nachbar-Fahrzeug unterwegs (geladen oder am Laden)?
function NachbarFelderManager:getHatFahrzeugeUnterwegs()
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
    -- Laeuft vor ItemSystem.save mit: ein Fehler hier bricht das Speichern des
    -- Spielstands ab, daher alles vorher pruefen.
    local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    local path = mi ~= nil and mi.savegameDirectory or nil
    if path == nil or g_NachbarFelderManager == nil or g_NachbarFelderManager.getSettingsState == nil then return end
    local modSaveDir = path .. "/NachbarFelder.xml"
    local xmlFile = XMLFile.create("NachbarFelder", modSaveDir, baseXmlKey, xmlSchema)
    if xmlFile == nil then return end
    -- Gespeichert werden nur die Einstellungen
    if g_NachbarFelderManager.vehicleType ~= nil then
        -- Kompletter Einstellungs-Stand, server-autoritativ
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
    -- Alte ".worker"-Eintraege werden ignoriert. Die Einstellungen erst nach
    -- loadServerConfig() (in loadMap) anwenden, damit Savegame-Werte die
    -- Konfig-Datei ueberschreiben und nicht umgekehrt.
    local sgActive = xmlFile:getValue(baseXmlKey .. ".settings#active")
    if sgActive ~= nil then
        local st = {
            active             = sgActive,
            maxWorkers         = xmlFile:getValue(baseXmlKey .. ".settings#maxWorkers"),
            trafficLimit       = xmlFile:getValue(baseXmlKey .. ".settings#trafficLimit"),
            trafficTrailerSize = xmlFile:getValue(baseXmlKey .. ".settings#trafficTrailerSize"),
            engeMap            = xmlFile:getValue(baseXmlKey .. ".settings#engeMap"),
            debugLog           = xmlFile:getValue(baseXmlKey .. ".settings#debugLog"),
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
-- Wegpunkte auf der Ingame-Karte (MapHotspot)
-- Das Spiel rendert MapHotspots selbst inkl. Zoom/Pan.
-- Vorbild: FS25_EasyDevControls, EasyDevControlsHotspotsManager.lua
-- ============================================================

-- Hotspot-Klasse wird erst beim ersten Bedarf definiert (MapHotspot muss existieren)
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
            -- generisches Karten-Icon aus dem Spiel-Atlas
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
    self:updateWpHotspots()

    -- Nummern nach dem Hotspot-Rendering zeichnen; getLastScreenPosition() liefert
    -- bereits zoom/pan-korrigierte Bildschirmkoordinaten.
    -- Vorbild: EasyDevControlsTeleportScreen:onDrawPostIngameMapHotspots
    if InGameMenuMapFrame ~= nil then
        local mgr = self
        -- Allokationsfrei: keine Closures oder Strings pro Frame (GC-Ruckler).
        -- Die Labels berechnet updateWpHotspots vor (hs._nfLabel).
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
    print("LivingRoads: [MAP] MapHotspot-System + Nummern-Hook initialisiert")
end

-- ============================================================
-- Client-lokale Anzeige-Einstellungen (z. B. Karten-Hotspots an/aus)
-- in modSettings/FS25_LivingRoads/NachbarFelderClient.xml,
-- nicht im Savegame und nicht auf dem Server.
-- ============================================================
function NachbarFelderManager:loadClientPrefs()
    local function schritt()
        local path = NachbarFelderLesePfad(modSettingDirectory .. "NachbarFelderClient.xml")
        if not fileExists(path) then
            -- Mit Defaults anlegen; gespeichert wird danach bei jedem Umschalten
            self:saveClientPrefs()
            print("LivingRoads: [MAP] Client-Einstellungsdatei angelegt: " .. path)
            return
        end
        local xf = loadXMLFile("nfClient", path)
        if xf == nil or xf == 0 then return end
        local show = getXMLBool(xf, "nachbarFelderClient.showWpOnMap")
        if show ~= nil then
            self._wpHotspotsEnabled = show
            print("LivingRoads: [MAP] Karten-Hotspots laut Client-Einstellung: " ..
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
    -- client-lokal merken, ueberlebt den Neustart
    self:saveClientPrefs()
end

-- Hotspots neu aufbauen, nach jeder WP-Änderung und beim Init
function NachbarFelderManager:updateWpHotspots()
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
        print("LivingRoads: [MAP] MapHotspot nicht verfügbar")
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
    print(string.format("LivingRoads: [MAP] %d WP-Hotspots gesetzt", #(self._wpMapHotspots))  )
end

function NachbarFelderManager:saveWaypoints()
    -- Die Datei gehört dem Server. Clients schicken Änderungen per
    -- NachbarFelderWaypointEditEvent, der Server speichert und synct zurück.
    if g_currentMission ~= nil and not g_currentMission:getIsServer() then
        return
    end
    -- Indizes haben sich verschoben, gemerkte Erreichbarkeits-Sperren verwerfen
    self.wpFails = {}
    self.patrolWpList = nil   -- Ziel-Liste neu aufbauen
    local pfad = nfGetWpFilePath()   -- Datei der geladenen Karte
    local xmlFile = XMLFile.create("NachbarFelderWaypoints", pfad, wpXmlKey, wpXmlSchema)
    if xmlFile == nil then
        print("LivingRoads: [TRAFFIC] Konnte Waypoint-Datei nicht schreiben: " .. pfad)
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
    print("LivingRoads: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
        " Wegpunkte gespeichert -> " .. pfad)
    -- Änderung sofort an alle Clients verteilen
    if g_currentMission:getIsServer() and g_server ~= nil then
        g_server:broadcastEvent(NachbarFelderWaypointSyncEvent.new(self.userTrafficWaypoints))
    end
end

function NachbarFelderManager:loadWaypoints()
    local pfad = nfGetWpFilePath()   -- Datei der geladenen Karte
    local xmlFile = XMLFile.loadIfExists("NachbarFelderWaypoints", NachbarFelderLesePfad(pfad), wpXmlSchema)

    -- Ohne kartenspezifische Datei wird die alte gemeinsame Datei einmalig
    -- uebernommen. Sie bleibt liegen, wird aber markiert, damit eine andere
    -- Karte die Punkte nicht noch einmal erbt.
    local ausAlterDatei = false
    if xmlFile == nil and pfad ~= wpFilePathAlt and g_currentMission:getIsServer() then
        local alt = XMLFile.loadIfExists("NachbarFelderWaypoints", NachbarFelderLesePfad(wpFilePathAlt), wpXmlSchema)
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
        print("LivingRoads: [TRAFFIC] Keine Wegpunkt-Datei fuer diese Karte: " .. pfad)
        return
    end
    self.wpFails = {}  -- alte Erreichbarkeits-Sperren verwerfen
    self.patrolWpList = nil   -- Ziel-Liste neu aufbauen
    self.userTrafficWaypoints = {}
    -- Fahrzeugkategorien aus der Datei wurden ingame gesetzt und haben Vorrang:
    -- loadServerConfig ueberschreibt sie dann nicht (vehicleCatsFromFile).
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
        -- alte Datei markieren (bleibt als Sicherung), danach Kartendatei schreiben
        xmlFile:setString(wpXmlKey .. "#uebernommenFuer", nfGetKartenKennung() or "?")
        xmlFile:save(false, false)
    end
    xmlFile:delete()
    if ausAlterDatei then
        print("LivingRoads: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
            " Wegpunkte aus der alten gemeinsamen Datei fuer diese Karte uebernommen -> " .. pfad)
        self:saveWaypoints()
    elseif #self.userTrafficWaypoints > 0 then
        print("LivingRoads: [TRAFFIC] " .. tostring(#self.userTrafficWaypoints) ..
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
        "LivingRoads: Zeit bis zum naechsten Verkehrs-Spawn anzeigen",
        "consoleCommandNachbarFelderTimer", self)
    addConsoleCommand("nachbarFelderEntfernen",
        "LivingRoads: alle aktiven Fahrzeuge entfernen",
        "consoleCommandNachbarFelderEntfernen", self)
    addConsoleCommand("nachbarFelderTrafficStop",
        "LivingRoads: alle Traffic-Fahrzeuge entfernen und neue sperren",
        "consoleCommandNachbarFelderTrafficStop", self)
    addConsoleCommand("nachbarFelderTrafficStart",
        "LivingRoads: Traffic-Fahrzeuge wieder erlauben",
        "consoleCommandNachbarFelderTrafficStart", self)
end

function NachbarFelderManager:consoleCommandNachbarFelderTimer()
    print("LivingRoads: naechster Verkehrs-Spawn in " .. tostring(self.timeToNextStart) .. " Spielminuten")
end

function NachbarFelderManager:consoleCommandNachbarFelderEntfernen()
    self:deleteAllVehiclesAndPool()
end

function NachbarFelderManager:consoleCommandNachbarFelderTrafficStop()
    if not g_currentMission:getIsServer() then
        print("LivingRoads: nachbarFelderTrafficStop nur auf Server/SP verfuegbar!")
        return
    end
    self.trafficPaused = true
    -- auch schlafende Pool-Fahrzeuge entfernen
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
    print("LivingRoads: [TRAFFIC] gestoppt – " .. tostring(count) .. " Fahrzeug(e) werden entfernt.")
end

function NachbarFelderManager:consoleCommandNachbarFelderTrafficStart()
    if not g_currentMission:getIsServer() then
        print("LivingRoads: nachbarFelderTrafficStart nur auf Server/SP verfuegbar!")
        return
    end
    self.trafficPaused = false
    print("LivingRoads: [TRAFFIC] wieder aktiv – neue Fahrzeuge spawnen normal.")
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

-- Kompatibilitäts-Einstieg; die Server-Initialisierung läuft regulär über loadMap/serverSideInit
function NachbarFelderManager:initialize()
    self:initializeSettingsPage()
    if not self.consoleCommandsAdded then
        self:addConsoleCommands()
    end
    if g_currentMission:getIsServer() and not self.serverInitialized then
        self:serverSideInit()
    end
end

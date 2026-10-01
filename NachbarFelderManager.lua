NachbarFelderManager = {}

-- Build-Nummer: erscheint im Log bei loadMap - IMMER prüfen ob der Server
-- wirklich den erwarteten Build fährt (Server und Client werden getrennt bestückt)
NachbarFelderManager.BUILD = 143

local NachbarFelderManager_class = Class(NachbarFelderManager)

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
local function nfGetKartenKennung()
    local kennung = nil
    pcall(function()
        local mi = g_currentMission ~= nil and g_currentMission.missionInfo or nil
        if mi ~= nil and type(mi.mapId) == "string" and mi.mapId ~= "" then
            kennung = mi.mapId
        end
    end)
    if kennung == nil then
        pcall(function()
            local bd = g_currentMission ~= nil and g_currentMission.baseDirectory or nil
            if type(bd) == "string" and bd ~= "" then
                kennung = string.match(bd, "([^/\\]+)[/\\]*$")
            end
        end)
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
    self.fieldID = 10
    self.aiVeh = nil
    self.loadVehiclesFromXML = {}
    self.countWorkers = 0
    self.timeToNextStart = -1

    self.MAX_ASSISTANT_WORKERS = 12

    self.playersOnline = 0    -- Anzahl verbundener Spieler (0 = niemand online → Helfer pausiert)
    self.playerJoinTime       = nil  -- g_time beim ersten Join; 3 Echtzeit-Minuten warten (robust gegen Zeitsprünge)
    self.regularVehicleXMLs   = {}   -- bis zu 3 Stamm-Fahrzeug-XMLs (Wiederkehrende Fahrzeuge)
    self.pendingRespawns      = {}   -- {filename, spawnAt} – Respawn-Warteschlange für Stammfahrzeuge
    self.fieldCooldown = {}  -- Felder die kürzlich gescheitert sind: fieldId → verbleibende Spielminuten
    self.fieldPathFails = {} -- fieldId → Anzahl "kein Pfad"-Fehlschläge (2x → Session-Sperre)
    self.spawnPlaceIndex = 1 -- Index des besten Shop-Spawn-Punktes (wird in selectBestSpawnPlace gesetzt)
    self.vehicleImplBlacklist = {}      -- missionType → {implFilename → failCount} für inkompatible Implements
    self.trafficVehicleBlacklist = {}   -- filename → true (Session-Blacklist: Patrol-Fahrzeuge ohne Navigation-Agent)
    self.patrolCounter = 0          -- negative Pseudo-Keys für Patrol-Einträge in vehicleType
    self.trafficLimit = 4           -- max. gleichzeitige Traffic-Fahrzeuge (1–8, einstellbar)
    self.trafficPaused = false      -- nachbarFelderTrafficStop/Start Console-Befehl
    self.trafficTrailerSize = 2     -- 0=keine Anhänger  1=klein(≤4kL)  2=mittel(≤8kL)  3=alle(≤15kL)
    self.engeMap        = true      -- enge Karte: nur Kleintraktoren + leichte Anbaugeraete
    self.spawnBereichRadius = 25    -- Umkreis um den Shop-Spawn, der frei sein muss (m)
    self.feldSperre     = {}        -- manuell ausgesperrte Felder: fieldId -> true
    self.bebauteFelder  = nil       -- Cache: Felder mit Gebaeude/Zaun im Umriss (Build 137)
    self.weideBereiche  = nil       -- Cache: eingezaeunte Weiden (Build 82)
    self.spawnLookAt    = nil       -- gecachter Zielpunkt der Spawn-Blickrichtung {x=,z=,quelle=}
    self.trafficPool = {}           -- Fahrzeug-Pool (Build 65): schlafende Patrol-Fahrzeuge
    self.poolSize    = 6            -- max. schlafende Fahrzeuge (0 = Pool aus, Server-Konfig)
    self.fahrerfigurenAufServer = true  -- Build 95: false = Fahrerfiguren nur auf dem Server weglassen
    self.rueckwaertsPlanen      = false -- Build 108; Build 125: Standard aus (Server-Konfig ohne Eintrag lief mit true, viele Sofort-Abweisungen)
    self.fieldLastFruit = {}        -- Vorfrucht-Gedaechtnis (Build 68): fieldId -> Fruchtname
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

    self.vehicleHarvestVariant = {}
    self.vehicleHarvestVariant["GRAIN"]     = {"WHEAT","BARLEY","OAT","CANOLA","MAIZE","SUNFLOWER","SOYBEAN","RICELONGGRAIN","SORGHUM"}
    self.vehicleHarvestVariant["POTATO"]    = {"POTATO"}
    self.vehicleHarvestVariant["SUGARBEET"] = {"SUGARBEET","BEETROOT"}
    self.vehicleHarvestVariant["COTTON"]    = {"COTTON"}
    self.vehicleHarvestVariant["PEA"]       = {"PEA"}
    self.vehicleHarvestVariant["SPINACH"]   = {"SPINACH"}
    self.vehicleHarvestVariant["ONION"]     = {"ONION"}
    self.vehicleHarvestVariant["GREENBEAN"] = {"GREENBEAN"}
    self.vehicleHarvestVariant["VEGETABLES"]= {"CARROT","PARSNIP"}
    self.vehicleHarvestVariant["SUGARCANE"] = {"SUGARCANE"}
    self.vehicleHarvestVariant["OLIVE"]     = {"GRAPE","OLIVE"}
    self.vehicleHarvestVariant["GRAPE"]     = {"GRAPE"}
    self.vehicleHarvestVariant["RICE"]      = {"RICE"}

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
        missions           = missions,
    }
end

-- Einstellungs-Stand anwenden (Server nach Savegame-Load, Client nach Sync)
function NachbarFelderManager:applySettingsState(state)
    if state == nil then return end
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
        pcall(function() self.settingsPage:refreshFromManager() end)
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
        pcall(function()
            g_server:broadcastEvent(NachbarFelderSettingsSyncEvent.new(self:getSettingsState()))
        end)
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
    pcall(function()
        if user ~= nil and user.getConnection ~= nil then
            self.adminConnections = self.adminConnections or {}
            self.adminConnections[user:getConnection()] = true
            local name = (user.getNickname ~= nil) and user:getNickname() or "?"
            print("NachbarFelder: [ADMIN] Master-User registriert: " .. tostring(name))
        end
    end)
end

-- Server: Ist die Verbindung ein Admin? (nil = lokaler Aufruf -> ja)
function NachbarFelderManager:getIsConnectionAdmin(connection)
    if connection == nil then return true end
    if self.adminConnections ~= nil and self.adminConnections[connection] == true then
        return true
    end
    -- Fallback: direkt am User-Objekt nachsehen
    local isAdmin = false
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.userManager ~= nil
           and g_currentMission.userManager.getUserByConnection ~= nil then
            local user = g_currentMission.userManager:getUserByConnection(connection)
            if user ~= nil and user.getIsMasterUser ~= nil then
                isAdmin = user:getIsMasterUser() == true
            end
        end
    end)
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
        pcall(function()
            g_currentMission:addIngameNotification(
                FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
                "NachbarFelder: Nur fuer Admins - bitte zuerst im Menue als Admin anmelden")
        end)
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
    local ok, err = pcall(function()
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
            " dayRhythm=" .. tostring(self.dayRhythm) ..
            " zielQuelle=" .. tostring(self.zielQuelle) ..
            " trailerChance=" .. tostring(self.trailerChance) .. "%" ..
            " engeMap=" .. tostring(self.engeMap ~= false) ..
            " spawnRadius=" .. tostring(self.spawnBereichRadius) .. "m" ..
            " Kategorien: S=" .. tostring(c.TRACTORSS) .. " M=" .. tostring(c.TRACTORSM) ..
            " L=" .. tostring(c.TRACTORSL) .. " Radlader=" .. tostring(c.WHEELLOADERVEHICLES) ..
            " Telelader=" .. tostring(c.TELELOADERVEHICLES))
    end)
    if not ok then
        print("NachbarFelder: Server-Konfig konnte nicht geladen werden: " .. tostring(err))
    end
end

-- ============================================================
-- Hooks installieren (einmalig, mit Guard)
-- ============================================================
function NachbarFelderManager:installHooks()
    if self.hooksInstalled then return end
    self.hooksInstalled = true
    print("NachbarFelder: Hooks werden installiert")

    -- MissionManager: Fahrzeuge mit allowedDrive dürfen überall arbeiten.
    -- WICHTIG: Die Engine ruft das pro ARBEITSBEREICH mit dem jeweiligen
    -- Geraet (Spritze/Pflug) als 'vehicle' auf - nicht mit dem Traktor.
    -- Deshalb tragen ALLE Worker-Fahrzeuge allowedDrive (siehe setAIOnField).
    MissionManager.getIsMissionWorkAllowed = Utils.overwrittenFunction(
        MissionManager.getIsMissionWorkAllowed,
        function(mm, superFunc, farmId, x, z, workAreaType, vehicle)
            local nf = g_NachbarFelderManager
            if vehicle ~= nil and nf ~= nil and
               (farmId == nf.farmId or
                (vehicle.allowedDrive ~= nil and vehicle.allowedDrive) or
                vehicle.nf_isHelper == true or
                (vehicle.getRootVehicle ~= nil and vehicle:getRootVehicle() ~= nil
                 and vehicle:getRootVehicle().nf_isHelper == true)) then
                return true
            end
            -- Diagnose: Verweigerte Aufrufe waehrend aktiver Helfer loggen
            -- (begrenzt), um "Geraet darf nicht arbeiten" zu bestaetigen.
            if nf ~= nil and nf:hasActiveWorkers() and (nf._wamLog or 0) < 8 then
                nf._wamLog = (nf._wamLog or 0) + 1
                print(string.format(
                    "NachbarFelder: [DIAG] WorkAllowed verweigert farmId=%s allowedDrive=%s isHelper=%s typ=%s",
                    tostring(farmId),
                    tostring(vehicle ~= nil and vehicle.allowedDrive),
                    tostring(vehicle ~= nil and vehicle.nf_isHelper),
                    tostring(vehicle ~= nil and vehicle.typeName)))
            end
            return superFunc(mm, farmId, x, z, workAreaType, vehicle)
        end)

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
            g_NachbarFelderManager.isShuttingDown = true
            g_NachbarFelderManager:prepareForShutdown()
            return superFunc(mission, ...)
        end)

    -- Savegame-Schutz: Temporären Helfer-Feldbesitz NIE mitspeichern.
    -- Wird während laufender Feldarbeit gespeichert, stünde sonst
    -- farmId=2 in farmland.xml (dauerhafte Savegame-Korruption).
    -- Vor dem Speichern Originalbesitz wiederherstellen, danach wieder
    -- anwenden, damit die laufende Feldarbeit weiterläuft.
    if FSBaseMission.saveSavegame ~= nil then
        FSBaseMission.saveSavegame = Utils.overwrittenFunction(FSBaseMission.saveSavegame,
            function(mission, superFunc, ...)
                local reapply = {}
                if g_NachbarFelderManager ~= nil then
                    local nfVehType = g_NachbarFelderManager.vehicleType or {}
                    for _, k in pairs(nfVehType) do
                        local w = k.NachbarFelderWorker
                        if w ~= nil and w.tempFarmland ~= nil then
                            table.insert(reapply, {
                                fl      = w.tempFarmland,
                                farmId  = w.tempFarmland.farmId,
                                isOwned = w.tempFarmland.isOwned
                            })
                            w.tempFarmland.farmId  = w.origFarmlandId
                            w.tempFarmland.isOwned = w.origIsOwned
                        end
                    end
                end
                local r1, r2, r3 = superFunc(mission, ...)
                for _, e in ipairs(reapply) do
                    e.fl.farmId  = e.farmId
                    e.fl.isOwned = e.isOwned
                end
                return r1, r2, r3
            end)
    end

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

    -- Gespeicherte Missionen aus XML einlesen (nur merken, NICHT sofort starten!)
    -- Start erfolgt erst wenn erster Spieler joined (in onMinuteChanged).
    self:loadFromXML()
    -- Wegpunkte wurden bereits in loadMap() geladen (Client + Server)
    self:updateWpHotspots()
    if #self.loadVehiclesFromXML > 0 then
        print("NachbarFelder: " .. tostring(#self.loadVehiclesFromXML) ..
            " gespeicherte Mission(en) - werden nach Spieler-Login geladen")
    end

    local timeScale = g_currentMission:getEffectiveTimeScale()
    self.timeToNextStart = math.random(1 * timeScale, 2 * timeScale)

    -- Events auf dem Server abonnieren
    g_messageCenter:unsubscribe(MessageType.MINUTE_CHANGED, self)
    g_messageCenter:subscribe(MessageType.MINUTE_CHANGED, self.onMinuteChanged, self)

    g_messageCenter:unsubscribe(MessageType.PERIOD_CHANGED, self)
    g_messageCenter:subscribe(MessageType.PERIOD_CHANGED, self.deleteAllVehicles, self)

    g_messageCenter:unsubscribe(MissionStartedEvent, self)
    g_messageCenter:subscribe(MissionStartedEvent, self.onMissionStarted, self)

    -- Admin-Logins merken (Build 75): Grundlage fuer den Event-Admin-Check
    pcall(function()
        if MessageType ~= nil and MessageType.MASTERUSER_ADDED ~= nil then
            g_messageCenter:unsubscribe(MessageType.MASTERUSER_ADDED, self)
            g_messageCenter:subscribe(MessageType.MASTERUSER_ADDED, self.onMasterUserAdded, self)
        end
    end)

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
                    pcall(function()
                        if ps.players ~= nil then
                            for _, p in pairs(ps.players) do
                                if p ~= nil and p ~= player and (p.farmId or 0) > 0 then
                                    remaining = remaining + 1
                                end
                            end
                        end
                    end)
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
                    pcall(function()
                        if g_currentMission.players ~= nil then
                            for _, p in pairs(g_currentMission.players) do
                                if p ~= nil and (p.farmId or 0) > 0 then
                                    finalCount = finalCount + 1
                                end
                            end
                        end
                    end)
                    g_NachbarFelderManager.playersOnline = finalCount
                end
            end)
    end

    print("NachbarFelder: Server bereit. Naechster Start in " .. tostring(self.timeToNextStart) .. " Minuten")
end

-- ============================================================
-- prepareForShutdown: Beim Spielende NUR AI-Jobs stoppen und
-- Feldbesitz wiederherstellen. KEINE Fahrzeuge löschen - das
-- macht die Engine direkt danach selbst (sonst "delete twice").
-- ============================================================
function NachbarFelderManager:prepareForShutdown()
    for fieldId, k in pairs(self.vehicleType or {}) do
        local worker = k.NachbarFelderWorker
        if worker ~= nil and worker.tempFarmland ~= nil then
            worker.tempFarmland.farmId  = worker.origFarmlandId
            worker.tempFarmland.isOwned = worker.origIsOwned
            worker.tempFarmland = nil
        end
        for _, veh in ipairs(k.vehicleType or {}) do
            if self:getIsVehicleAlive(veh) then
                self:stopAIJobSafely(veh)
            end
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
    -- Farmland-Besitz für alle Helfer wiederherstellen die gerade Feldarbeit machen
    for fieldId, k in pairs(self.vehicleType or {}) do
        local worker = k.NachbarFelderWorker
        if worker ~= nil and worker.tempFarmland ~= nil then
            worker.tempFarmland.farmId  = worker.origFarmlandId
            worker.tempFarmland.isOwned = worker.origIsOwned
            worker.tempFarmland = nil
            print("NachbarFelder: stopAllHelpers: Feldbesitz Feld " ..
                tostring(fieldId) .. " wiederhergestellt")
        end
    end
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
-- Key-Binding-Callbacks (Admin-Client)
-- Im Dedicated-MP: Event an Server schicken
-- In SP / Local-Host: direkt ausführen (getIsServer()=true)
-- ============================================================
function NachbarFelderManager:onInputStartNow(actionName, inputValue, callbackState, isAnalog, isMouse, deviceCategory)
    -- Nur Admins duerfen Helfer starten (Build 75)
    if not self:getIsLocalAdmin() then
        self:notifyAdminRequired()
        return
    end
    if g_currentMission:getIsServer() then
        -- SP oder Local-Host: direkt
        self.feldSpawnBlockiert = false
        local created = self:generateWorkMission(true)
        if created then
            print("NachbarFelder: Helfer manuell gestartet (Taste)")
        else
            if self.feldSpawnBlockiert then
                print("NachbarFelder: Feld gefunden, aber der Haendler-Platz ist gerade belegt" ..
                    " - in einer Minute nochmal versuchen")
            else
                print("NachbarFelder: Kein Helfer moeglich (Max. erreicht oder keine passenden Felder)")
            end
        end
    else
        -- Dedicated-MP: Event an Server schicken
        if g_client ~= nil then
            g_client:getServerConnection():sendEvent(NachbarFelderStartEvent.new())
            print("NachbarFelder: Start-Event an Server gesendet")
        end
    end
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
    local art = istSpawn and "Spawnpunkt" or "Wegpunkt"
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
        pcall(function()
            if player.getCurrentVehicle ~= nil then
                vehicle = player:getCurrentVehicle()
            end
        end)
        if vehicle == nil then
            vehicle = player.currentVehicle or player.controlledVehicle
        end
        if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
            pcall(function()
                local vx, vy, vz = getWorldTranslation(vehicle.rootNode)
                if math.abs(vx) > 1 or math.abs(vz) > 1 then
                    x, y, z = vx, vy, vz
                    -- Vorwaertsvektor statt Euler-Y: am Hang kann getWorldRotation
                    -- das Y um 180 Grad kippen (x/z-Rotation gleicht es aus).
                    local dx, _, dz = localDirectionToWorld(vehicle.rootNode, 0, 0, 1)
                    if math.abs(dx) > 0.001 or math.abs(dz) > 0.001 then
                        ry = math.atan2(dx, dz)
                        richtungQuelle = "Fahrzeug"
                    end
                end
            end)
        end
        -- Versuch 2: zu Fuss -> Spielerposition, Richtung = Blickrichtung
        if x == nil and player.getMapPositionAndLookYaw ~= nil then
            pcall(function()
                local px, pz, yaw = player:getMapPositionAndLookYaw()
                if px ~= nil and pz ~= nil and (math.abs(px) > 1 or math.abs(pz) > 1) then
                    x, z = px, pz
                    if yaw ~= nil then
                        ry = yaw
                        richtungQuelle = "Blickrichtung"
                    end
                end
            end)
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
        pcall(function()
            local cam = getCamera()
            if cam ~= nil and cam ~= 0 then
                local dx, _, dz = localDirectionToWorld(cam, 0, 0, -1)
                if math.abs(dx) > 0.001 or math.abs(dz) > 0.001 then
                    ry = math.atan2(dx, dz)
                    richtungQuelle = "Kamera"
                end
            end
        end)
    end
    x  = math.floor(x + 0.5)
    z  = math.floor(z + 0.5)
    ry = ry or 0
    local richtungText = "Richtung aus " .. (richtungQuelle or "? (0)")
    print(string.format("NachbarFelder: [WP] Position x=%d z=%d, %s (%.0f Grad)",
        x, z, richtungText, math.deg(ry) % 360))
    -- Nähecheck: kein Duplikat innerhalb von 10 Metern
    local MIN_DIST = 10
    self.userTrafficWaypoints = self.userTrafficWaypoints or {}
    for i, wp in ipairs(self.userTrafficWaypoints) do
        local dist = math.sqrt((x - wp.x)^2 + (z - wp.z)^2)
        if dist < MIN_DIST then
            local grund = ("Nicht gesetzt: WP %d ist nur %.0f m entfernt (mind. 10 m)"):format(i, dist)
            print("NachbarFelder: [TRAFFIC] " .. art .. " - " .. grund)
            if g_currentMission ~= nil then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_CRITICAL, "NachbarFelder: " .. art .. " " .. grund)
            end
            return false, grund
        end
    end
    -- Spawnpunkt: das eigene Fahrzeug steht noch auf der Flaeche und zaehlt als Hindernis
    local zusatz = istSpawn and " - jetzt wegfahren" or ""
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
            "NachbarFelder: " .. art .. " an Server gesendet (" ..
            tostring(x) .. " / " .. tostring(z) .. ", " .. richtungText .. ")" .. zusatz)
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
            "NachbarFelder: " .. art .. " " .. tostring(#self.userTrafficWaypoints) ..
            " gesetzt (" .. tostring(x) .. " / " .. tostring(z) .. ", " .. richtungText .. ")" .. zusatz
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
                "NachbarFelder: Keine Wegpunkte - setzen unter ESC > Einstellungen > Wegpunkte")
        end
        return
    end
    self._mgr_viewIdx = (self._mgr_viewIdx % count) + 1
    local wp = wps[self._mgr_viewIdx]
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("NF WP %d/%d: x=%d  z=%d  (ESC > Einstellungen: Teleportieren/Loeschen)",
                self._mgr_viewIdx, count, math.floor(wp.x), math.floor(wp.z)))
    end
end

function NachbarFelderManager:_teleportToWp(wp)
    local x, z = wp.x, wp.z
    local y = 0
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 1
        end
    end)
    local lp = self.localPlayer
    if lp ~= nil then
        local ok, err = pcall(function()
            local vehicle = lp.currentVehicle or lp.controlledVehicle
            if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
                setTranslation(vehicle.rootNode, x, y, z)
            elseif lp.rootNode ~= nil and lp.rootNode ~= 0 then
                setTranslation(lp.rootNode, x, y, z)
            end
        end)
        if not ok then print("NachbarFelder: [MGR] Teleport Fehler: " .. tostring(err)) end
    end
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(
            FSBaseMission.INGAME_NOTIFICATION_OK,
            string.format("NachbarFelder: Teleportiert zu x=%d z=%d", math.floor(x), math.floor(z)))
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
                "NachbarFelder: Wegpunkt-Löschung an Server gesendet")
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
            "NachbarFelder: Wegpunkt entfernt. Verbleibend: " .. tostring(#self.userTrafficWaypoints)
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
        pcall(function()
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
        end)
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
        pcall(function()
            if v.getAttachedImplements ~= nil then impl = v:getAttachedImplements() end
        end)
        if impl == nil or #impl == 0 then
            return true
        end
        return original(v, ...)
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
    pcall(function()
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
    end)
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
function NachbarFelderManager:log(lvl, msg)
    if (self.logLevel or 1) >= lvl then
        print(msg)
    end
end

-- Verbundene Spieler zaehlen (Build 131) - gleiche Regel wie onMinuteChanged
-- (farmId > 0 = wirklich im Spiel). Benannte Funktion: pcall(fn) ohne
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
-- pcall(nfEmptyCombineTank, veh) erzeugt KEINE Closure pro Aufruf -
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
            local ok, n = pcall(nfCountConnectedPlayers)
            self._perfPlayers = ok and n or (self.playersOnline or 0)
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
                local memMb = -1
                pcall(function() memMb = math.floor(collectgarbage("count") / 1024 + 0.5) end)
                print(string.format(
                    "NachbarFelder: [PERF] %d langsame Frames (>%dms) in 10s, max %dms (%s, LuaMem %d MB)",
                    self._spkCount, math.floor(self._spkLimitMin or slowLimit),
                    math.floor(self._spkMax or 0),
                    g_currentMission:getIsServer() and "Server" or "Client", memMb))
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

    -- Speicher-Telemetrie (Build 76): einmal pro Minute Lua-Heap loggen wenn er
    -- sich um >= 4 MB verändert hat. Wächst die Zahl stetig → echtes Leck;
    -- pendelt sie → GC-Druck. Läuft auf Server (nur mit Spielern) und Client.
    if perfActive and (self._memNextAt == nil or (g_time or 0) > self._memNextAt) then
        self._memNextAt = (g_time or 0) + 60000
        pcall(function()
            local mb = math.floor(collectgarbage("count") / 1024 + 0.5)
            if self._memLastMb == nil or math.abs(mb - self._memLastMb) >= 4 then
                self._memLastMb = mb
                print(string.format("NachbarFelder: [PERF] LuaMem %d MB (%s)",
                    mb, g_currentMission:getIsServer() and "Server" or "Client"))
            end
        end)
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
                if k.NachbarFelderWorker.tempFarmland ~= nil then
                    k.NachbarFelderWorker.tempFarmland.farmId  = k.NachbarFelderWorker.origFarmlandId
                    k.NachbarFelderWorker.tempFarmland.isOwned = k.NachbarFelderWorker.origIsOwned
                    k.NachbarFelderWorker.tempFarmland = nil
                end
                k.NachbarFelderWorker.status = 100
                k.NachbarFelderWorker.needTimer = true
            end
        end
    end

    -- Mähdrescher-Korntank regelmäßig leeren, damit der Erntehelfer nicht
    -- voll-stoppt. Ein KI-Mähdrescher ohne Abfahrer hält an, sobald der
    -- Tank voll ist - und bliebe dann mitten im Feld stehen. Das geerntete
    -- Korn ist für die reine Nachbar-Aktivität irrelevant.
    -- 250ms-Takt reicht dicke: pro Takt kommen nur wenige Liter zusammen,
    -- Tankgrößen liegen bei tausenden Litern. spec_combine sichert ab, dass
    -- nur echte Mähdrescher-Tanks geleert werden; pcall fängt API-Abweichungen ab.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.status == 2 and w.mission ~= nil and w.mission.type ~= nil
           and w.mission.type.name == "harvestMission" and w.vehiclesToLoad ~= nil then
            for _, veh in ipairs(w.vehiclesToLoad) do
                if veh ~= nil and veh.spec_combine ~= nil and self:getIsVehicleAlive(veh)
                   and veh.getFillUnits ~= nil and veh.setFillUnitFillLevel ~= nil then
                    pcall(nfEmptyCombineTank, veh)
                end
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

    -- Bewegungs-Watchdog: Ein Helfer der bei der Feldarbeit (Status 2)
    -- stehenbleibt (z.B. Pflug der nicht in den Boden greift) wird nach
    -- ~100s Echtzeit ohne Bewegung aufgeräumt - statt ewig auf dem Feld zu
    -- stehen. Ein ARBEITENDES Gerät fährt durchgehend (>2m/100s), löst also
    -- nie aus. Feld kommt auf kurzen Cooldown, damit nicht sofort dasselbe
    -- Problem-Feld erneut probiert wird.
    -- Patrol-Fahrzeuge im Status 2 (geparkt) werden NICHT vom Watchdog erfasst.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and w.status == 2 and not w.isPatrol and w.vehiclesToLoad ~= nil then
            local veh = w.vehiclesToLoad[1]
            if self:getIsVehicleAlive(veh) then
                local x, _, z = getWorldTranslation(veh.rootNode)
                if w.wdLastX == nil then
                    w.wdLastX, w.wdLastZ, w.wdSince = x, z, g_time
                elseif MathUtil.vector2Length(x - w.wdLastX, z - w.wdLastZ) > 2 then
                    w.wdLastX, w.wdLastZ, w.wdSince = x, z, g_time
                elseif g_time - (w.wdSince or g_time) > 60000 then
                    print("NachbarFelder: Helfer bewegt sich seit 100s nicht (Feld " ..
                        tostring(w.fieldId) .. ", Feldarbeit) - wird aufgeraeumt")
                    if w.tempFarmland ~= nil then
                        w.tempFarmland.farmId  = w.origFarmlandId
                        w.tempFarmland.isOwned = w.origIsOwned
                        w.tempFarmland = nil
                    end
                    self.fieldCooldown[w.fieldId] = 30
                    w.status = 100
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
                pcall(function()
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
                end)
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
                            w.isPatrol and "[TRAFFIC] Fahrzeug" or ("Feldhelfer fuer Feld " .. tostring(w.fieldId)),
                            tostring(self:getWorkerName(w)), math.floor(x), math.floor(z), tostring(w.status)))
                        self:merkeSpawnFehlschlag(w, x, z, "umgekippt")
                        self:stopAIJobSafely(veh)
                        w.kippSeit  = nil
                        w.status    = 100
                        w.needTimer = true
                        self:planeAuftragNeu(w, "umgekippt")   -- Build 143
                    end
                else
                    w.kippSeit = nil
                end
            end
        end
    end

    -- Build 121: Stillstand-Waechter fuer Feldhelfer auf der Anfahrt zum Feld.
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and not w.isPatrol and w.status == 1 and w.fieldGotoStartedAt ~= nil then
            if w.feldWdJobStart ~= w.fieldGotoStartedAt then
                w.feldWdJobStart = w.fieldGotoStartedAt
                w.feldWdLastX    = nil
            end
            local veh = w.vehiclesToLoad and w.vehiclesToLoad[1]
            if self:getIsVehicleAlive(veh) then
                local x, _, z = getWorldTranslation(veh.rootNode)
                if w.feldWdLastX == nil
                   or MathUtil.vector2Length(x - w.feldWdLastX, z - w.feldWdLastZ) > 5 then
                    w.feldWdLastX, w.feldWdLastZ, w.feldWdSince = x, z, g_time
                elseif self:getFeldWdAusloesen(w, x, z, veh) then   -- Build 124
                    local h = w.feldWdHindernis
                    print(string.format("NachbarFelder: Feldhelfer %s steht %d s ohne Bewegung auf der Anfahrt" ..
                        " zu Feld %s bei x=%d z=%d%s: %s", tostring(self:getWorkerName(w)), w.feldWdSekunden or 0,
                        tostring(w.fieldId), math.floor(x), math.floor(z),
                        h ~= nil and string.format(", %s steht %.0f m entfernt", tostring(h.name), h.d) or "",
                        tostring(self:getVehicleAiDiag(veh))))
                    self:merkeSpawnFehlschlag(w, x, z, "Stillstand")   -- Build 129
                    self:stopAIJobSafely(veh)
                    w.fieldGotoStartedAt = nil
                    w.feldWdLastX        = nil
                    if h ~= nil then
                        -- Build 124: Fahrzeug im Weg - neue Planung umfaehrt es; kein Fehlschlag
                        w.feldHindernisPlanungen = (w.feldHindernisPlanungen or 0) + 1
                        print("NachbarFelder: Feldhelfer wartet hinter " .. tostring(h.name) ..
                            " - neuer Weg wird geplant (" .. tostring(w.feldHindernisPlanungen) .. "/3)")
                        w.status    = 1
                        w.needTimer = true
                    elseif not w.feldNeuplanung then
                        w.feldNeuplanung = true
                        print("NachbarFelder: Feldhelfer - Anfahrt gestoppt, neuer Anlauf von hier")
                        w.status    = 1
                        w.needTimer = true
                    else
                        local impl = w.vehiclesToLoad[2]
                        self:sperreFeldGespann(veh.configFileName, impl ~= nil and impl.configFileName or nil)
                        print("NachbarFelder: Feldhelfer - zweiter Stillstand, Gespann " ..
                            tostring(self:getWorkerName(w)) .. " fuer diese Session gesperrt, Fahrzeug wird entfernt")
                        w.status    = 100
                        w.needTimer = true
                    end
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
                else
                    local stuckMs = g_time - (w.patrolWdSince or g_time)
                    local stage   = w.patrolWdStage or 0

                    local zielDist = math.huge
                    if w.patrolTargetX ~= nil and w.patrolTargetZ ~= nil then
                        zielDist = MathUtil.vector2Length(x - w.patrolTargetX, z - w.patrolTargetZ)
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
                    do
                        -- Build 116: Feldhelfer-Geraet an die Kupplung setzen / wieder in die Physik
                        if pendingInfo ~= nil then
                            self:setzeGeraetAnKupplung(pendingInfo.attacherVehicle, pendingInfo.attacherVehicleJointDescIndex,
                                pendingInfo.attachable, pendingInfo.attachableJointDescIndex)
                        elseif attached ~= nil then
                            pcall(function()
                                if not attached.isAddedToPhysics then attached:addToPhysics() end
                            end)
                        end
                    end
                    if pendingInfo ~= nil then
                        pendingInfo.attacherVehicle:attachImplement(
                            pendingInfo.attachable, pendingInfo.attachableJointDescIndex,
                            pendingInfo.attacherVehicleJointDescIndex, true, nil, false, true, true)
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
                                pcall(function()
                                    if implVeh.prepareForAIDriving ~= nil then
                                        implVeh:prepareForAIDriving()
                                    end
                                    if implVeh.spec_foldable ~= nil
                                       and implVeh.setFoldDirection ~= nil then
                                        local wd = implVeh.spec_foldable.turnOnFoldDirection or 1
                                        implVeh:setFoldDirection(-wd)
                                    end
                                end)
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
                                pcall(function()
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
                                end)
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

                    else
                        if k.NachbarFelderWorker.isPatrol then
                            -- Patrol: teleportVehicle ist im MP-Dedicated-Server asynchron (ein Frame Latenz).
                            -- Status=1.5 gibt weitere 3s Settle-Zeit, damit das Fahrzeug physikalisch
                            -- an der WP-Position ist bevor createAgent() den Navmesh-Startknoten sucht.
                            k.NachbarFelderWorker.status    = 1.5
                            k.NachbarFelderWorker.needTimer = true
                        else
                            -- Zeitstempel merken – onAIJobFinished prüft ob GOTO realistisch lange fuhr
                            k.NachbarFelderWorker.fieldGotoStartedAt = g_time
                            -- Build 118: Zielpunkt am Feldrand zur Strasse + Ankunftsrichtung
                            local fzx, fzz, fzw = self:getFeldZielpunkt(k.NachbarFelderWorker.fieldId, vehicle)
                            self:driveToField(vehicle, k.NachbarFelderWorker.fieldId, fzx, 0, fzz, fzw)
                        end
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
                    pcall(function()
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
                    end)
                    self:driveToField(vehicle, nfW.fieldId,
                        nfW.patrolTargetX, 0, nfW.patrolTargetZ, targetRy)

                elseif s == 2 then
                    -- Patrol: kein setAIOnField – Park-Timer-Loop in update() übernimmt
                    if not k.NachbarFelderWorker.isPatrol then
                        self:setAIOnField(k.NachbarFelderWorker)
                    end

                elseif s == 3 then
                    self:mountTrailer(
                        k.NachbarFelderWorker.vehiclesToLoad[1],
                        k.NachbarFelderWorker.vehiclesToLoad[2],
                        k.NachbarFelderWorker.vehiclesToLoad[3])
                    k.NachbarFelderWorker.status = 4
                    k.NachbarFelderWorker.needTimer = true

                elseif s == 33 then
                    self:attachObjectToCar(
                        k.NachbarFelderWorker.vehiclesToLoad[1],
                        k.NachbarFelderWorker.vehiclesToLoad[3], true)
                    k.NachbarFelderWorker.status = 3
                    k.NachbarFelderWorker.needTimer = true

                elseif s == 4 then
                    self:driveToField(vehicle, k.NachbarFelderWorker.fieldId,
                        k.NachbarFelderWorker.posX, k.NachbarFelderWorker.posY,
                        k.NachbarFelderWorker.posZ, k.NachbarFelderWorker.angle)

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
                    if k.NachbarFelderWorker.tempFarmland ~= nil then
                        k.NachbarFelderWorker.tempFarmland.farmId  = k.NachbarFelderWorker.origFarmlandId
                        k.NachbarFelderWorker.tempFarmland.isOwned = k.NachbarFelderWorker.origIsOwned
                        k.NachbarFelderWorker.tempFarmland = nil
                    end
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
    pcall(function()
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
    end)
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

    -- Feld-Cooldowns herunterzählen
    for fieldId, remaining in pairs(self.fieldCooldown) do
        if remaining <= 1 then
            self.fieldCooldown[fieldId] = nil
        else
            self.fieldCooldown[fieldId] = remaining - 1
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
    -- egal wie hoch trafficLimit stand). "Anzahl Arbeiter" begrenzt jetzt
    -- nur noch Feldarbeits-Helfer (Check in generateWorkMission).
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
                local created
                local _gtOk, _gtErr = pcall(function() created = self:generateTraffic(nil, overrideWp) end)
                if not _gtOk then
                    print("NachbarFelder: [TRAFFIC] Fehler in generateTraffic: " .. tostring(_gtErr))
                    break
                end
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

    -- Build 105: Feldarbeit wieder automatisch. generateWorkMission wurde nur
    -- noch von der Admin-Taste (Shift+Alt+N) und dem Konsolenbefehl gerufen -
    -- beim Umbau des Spawn-Takts auf den KI-Verkehr (Build 71) war der
    -- automatische Aufruf verschwunden. Seitdem gab es nur noch Verkehr.
    if (self.MAX_ASSISTANT_WORKERS or 0) > 0 then
        self.timeToNextFieldWork = (self.timeToNextFieldWork or 2) - 1
        if self.timeToNextFieldWork <= 0 then
            self.feldSpawnBlockiert = false
            local ok, created = pcall(function() return self:generateWorkMission() end)
            if not ok then
                print("NachbarFelder: Fehler in generateWorkMission: " .. tostring(created))
                created = false
            end
            if created then
                self.timeToNextFieldWork = math.random(math.max(3, self.spawnIntervalMin or 2),
                                                       math.max(6, self.spawnIntervalMax or 5))
            elseif self.feldSpawnBlockiert then
                -- Build 110: Feld gefunden, nur der Haendler-Platz war belegt
                -- (meist ein gerade gespawntes Verkehrsfahrzeug) - bald erneut.
                self.timeToNextFieldWork = 2
            else
                self.timeToNextFieldWork = 15   -- kein passendes Feld: seltener suchen
            end
        end
    end
end

function NachbarFelderManager:onMissionStarted(mission)
    if not g_currentMission:getIsServer() then return end
    if mission == nil or mission.getField == nil or mission:getField() == nil then return end
    local missionFarmland = mission:getField().farmland
    if missionFarmland == nil then return end

    -- Helfer suchen, der auf einem Feld dieses Farmlands arbeitet.
    -- WICHTIG: Über das Farmland-OBJEKT vergleichen - früher wurde
    -- farmland.id als fieldId-Key missbraucht und löschte bei
    -- Id-Kollisionen die Fahrzeuge eines FALSCHEN Helfers.
    for fieldId, entry in pairs(self.vehicleType) do
        -- Patrol-Einträge (negative IDs) haben kein echtes Feld → überspringen
        if entry.NachbarFelderWorker == nil or not entry.NachbarFelderWorker.isPatrol then
            local field = g_fieldManager:getFieldById(fieldId)
            if field ~= nil and field.farmland == missionFarmland then
                local worker = entry.NachbarFelderWorker
                print("NachbarFelder: Spieler-Vertrag auf Feld " .. tostring(fieldId) ..
                    " gestartet - Helfer wird entfernt")
                -- Feldbesitz wiederherstellen (falls gerade Feldarbeit läuft)
                if worker ~= nil and worker.tempFarmland ~= nil then
                    worker.tempFarmland.farmId  = worker.origFarmlandId
                    worker.tempFarmland.isOwned = worker.origIsOwned
                    worker.tempFarmland = nil
                end
                for _, veh in ipairs(entry.vehicleType) do
                    if self:getIsVehicleAlive(veh) then
                        self:stopAIJobSafely(veh)
                        veh:delete()
                    end
                end
                -- Eintrag SOFORT entfernen - sonst greifen update()/onMinuteChanged
                -- weiter auf die gelöschten Fahrzeuge zu (Lua-Fehler-Spam bis Neustart!)
                self.vehicleType[fieldId] = nil
                self.counter = self.counter - 1
                break
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
    pcall(function()
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
    end)

    if bestX ~= nil then
        self.spawnLookAt = { x = bestX, z = bestZ, quelle = "Werkstatt" }
        print(string.format("NachbarFelder: Spawn-Blickrichtung = Werkstatt bei x=%.1f z=%.1f (%.0f m entfernt)",
            bestX, bestZ, bestDist or 0))
        return self.spawnLookAt
    end

    -- Stufe 2: Senkrechte des Spawnplatzes (Vorgabe des Karten-Bauers)
    pcall(function()
        local place = self:getNfSpawnPlace()
        if place ~= nil and place.dirPerpX ~= nil and place.dirPerpZ ~= nil then
            local dx, dz = place.dirPerpX, place.dirPerpZ
            if math.abs(dx) > 0.0001 or math.abs(dz) > 0.0001 then
                -- 50 m in Blickrichtung reichen als Zielpunkt voellig aus.
                self.spawnLookAt = { x = spX + dx * 50, z = spZ + dz * 50, quelle = "Spawnplatz" }
            end
        end
    end)

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

        if loadingInfo.vehicleInfo ~= nil and loadingInfo.vehicleInfo.fileName ~= nil then
            for _, vehicle in ipairs(vehicles) do
                loadingInfo:callback(vehicle)
                break
            end
            return
        end

        for _, vehicle in ipairs(vehicles) do
            vehicle.isVehicleSaved = false
            self:applyServerDriverFigure(vehicle)   -- Build 95
            self:applyRueckwaertsPlanen(vehicle)    -- Build 108
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
                    pcall(function()
                        if vehicle.isAddedToPhysics then vehicle:removeFromPhysics() end
                    end)
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
                    pcall(function()
                        local zielX, zielZ = nil, nil
                        if istVerkehrS then
                            zielX, zielZ = nfWS.patrolTargetX, nfWS.patrolTargetZ
                        else
                            local field = g_fieldManager:getFieldById(loadingInfo.NachbarFelderWorker.fieldId)
                            if field ~= nil then zielX, zielZ = field.posX, field.posZ end
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
                        if istVerkehrS then
                            print(string.format("NachbarFelder: [TRAFFIC] %.0f m vom Shop-Platz auf die KI-Strasse" ..
                                " gesetzt (weg von der Wand)", rdist or 0))
                        else
                            print(string.format("NachbarFelder: Feldhelfer %.0f m vom Shop-Platz auf die KI-Strasse" ..
                                " gesetzt (weg von der Wand), Richtung Feld %s", rdist or 0,
                                tostring(loadingInfo.NachbarFelderWorker.fieldId)))
                        end
                    end)
                end
                local lookAt = self:getSpawnLookAt()
                if lookAt ~= nil and not aufStrasse then
                    pcall(function()
                        local spawnRotY = MathUtil.getYRotationFromDirection(
                            lookAt.x - x0, lookAt.z - z0)
                        g_currentMission:teleportVehicle(vehicle, x0, z0, spawnRotY)
                    end)
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

            local cap = 100000
            if loadingInfo.NachbarFelderWorker.mission.type.name ~= "harvestMission" then
                self:setFillCapacity(vehicle, cap)
            end
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
--- Genau so macht es das Spiel fuer Zusatzgeraete (AttacherJoints.lua:3076-3078
--- und 3141-3146): Position = localToWorld(jointTransform, jointOrigOffsetComponent),
--- Drehung aus der x-Achse des Kupplungspunkts, mindestens 5 cm ueber dem Boden.
function NachbarFelderManager:setzeGeraetAnKupplung(attacher, attacherJointIndex, implement, inputJointIndex)
    pcall(function()
        local aj = attacher:getAttacherJoints()[attacherJointIndex]
        local ij = implement:getInputAttacherJoints()[inputJointIndex]
        if aj ~= nil and aj.jointTransform ~= nil and ij ~= nil then
            local offset = ij.jointOrigOffsetComponent or { 0, 0, 0 }
            local x, y, z = localToWorld(aj.jointTransform, unpack(offset))
            local dirX, _, dirZ = localDirectionToWorld(aj.jointTransform, 1, 0, 0)
            local yRot = MathUtil.getYRotationFromDirection(dirX, dirZ)
            local terrainY = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
            implement:setAbsolutePosition(x, math.max(y, terrainY + 0.05), z, 0, yRot, 0)
        end
    end)
    pcall(function()
        if not implement.isAddedToPhysics then implement:addToPhysics() end
    end)
end

function NachbarFelderManager:attachObjectToCar(vehicle, attachedVehicle, isBackSetting)
    local pendingInfo = self:attachObjects(vehicle, attachedVehicle, isBackSetting)
    if pendingInfo ~= nil then
        pendingInfo.attacherVehicle:attachImplement(
            pendingInfo.attachable, pendingInfo.attachableJointDescIndex,
            pendingInfo.attacherVehicleJointDescIndex, true, nil, false, true, true)
    end
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
    print(string.format("NachbarFelder: Ladeplatz x=%d z=%d taugt nicht (%s) - dauerhaft fuer diese Karte gesperrt" ..
        " (%d Plaetze gesperrt, Datei %s)", math.floor(sp.x), math.floor(sp.z), tostring(grund),
        #self.spawnPlatzSperre, tostring(self:getLadeplatzDatei())))
end

--- Auftrag an den Lohnunternehmer nach einem Fehlschlag am Ladeplatz neu einplanen (Build 143).
--- Der Platz ist dann gesperrt, der neue Anlauf laedt woanders. Hoechstens
--- AUFTRAG_MAX_NEUVERSUCHE je Feld und Sitzung; laeuft ueber die Warteschlange der
--- gespeicherten Auftraege (generateWorkMission -> NachbarFelderAuftrag.starteGespeichert).
NachbarFelderManager.AUFTRAG_MAX_NEUVERSUCHE = 2
function NachbarFelderManager:planeAuftragNeu(w, grund)
    if w == nil or w.isPatrol or not w.istAuftrag or w.fieldId == nil then return end
    self.auftragNeuversuche = self.auftragNeuversuche or {}
    local n = (self.auftragNeuversuche[w.fieldId] or 0) + 1
    self.auftragNeuversuche[w.fieldId] = n
    if n > NachbarFelderManager.AUFTRAG_MAX_NEUVERSUCHE then
        print(string.format("NachbarFelder: [AUFTRAG] Feld %s - %s, kein weiterer Versuch (%d Versuche)",
            tostring(w.fieldId), tostring(grund), n - 1))
        return
    end
    table.insert(self.loadVehiclesFromXML, { fieldId = w.fieldId, auftrag = true,
        auftragFarmId = w.auftragFarmId or 0 })
    print(string.format("NachbarFelder: [AUFTRAG] Feld %s - %s, Auftrag neu eingeplant (Versuch %d/%d)",
        tostring(w.fieldId), tostring(grund), n, NachbarFelderManager.AUFTRAG_MAX_NEUVERSUCHE))
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
    pcall(function()
        local xmlFile = XMLFile.loadIfExists("NachbarFelderLadeplaetze", pfad, lpXmlSchema)
        if xmlFile == nil then return end
        xmlFile:iterate(lpXmlKey .. ".platz", function(_, key)
            local x = xmlFile:getValue(key .. "#x")
            local z = xmlFile:getValue(key .. "#z")
            if x ~= nil and z ~= nil then
                table.insert(self.spawnPlatzSperre, { x, z, xmlFile:getValue(key .. "#grund") or "?" })
            end
        end)
        xmlFile:delete()
    end)
    if #self.spawnPlatzSperre > 0 then
        print(string.format("NachbarFelder: %d gesperrte Ladeplaetze geladen (%s)", #self.spawnPlatzSperre, pfad))
    end
end

function NachbarFelderManager:speichereLadeplatzSperre()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    local pfad = self:getLadeplatzDatei()
    if pfad == nil then return end
    pcall(function()
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
    end)
end

function NachbarFelderManager:getIstSpawnPlatzGesperrt(x, z)
    self:ladeLadeplatzSperre()
    for _, p in ipairs(self.spawnPlatzSperre or {}) do
        if MathUtil.vector2Length(x - p[1], z - p[2]) < 15 then return true end
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
function NachbarFelderManager:getFahrbahnHoehe(x, z, splineH)
    local gelaende = getTerrainHeightAtWorldPos(g_terrainNode, x, 0, z)
    local h = nil
    pcall(function()
        local oben = math.max(gelaende, splineH or gelaende) + 3
        local maske = CollisionFlag.TERRAIN + CollisionFlag.ROAD + CollisionFlag.STATIC_OBJECT + CollisionFlag.BUILDING
        local hit, _, hitY = RaycastUtil.raycastClosest(x, oben, z, 0, -1, 0, 10, maske)
        if hit and hitY ~= nil then h = hitY end
    end)
    return h or gelaende
end

--- Ist die Flaeche fuer ein Gespann frei? (Build 128)
--- Kasten laenge x breite, der Traktor steht vorn am Punkt (x, z), das Gespann reicht
--- nach hinten (gegen ry). Unterkante 0,3 m ueber der Fahrbahnhoehe h, 2 m hoch.
--- Maske wie AISystem.lua:1216; Strassen und Kollisionen ohne Filter ignoriert wie
--- AISystem.lua:1235/1242. Synchron ausgewertet wie PlaceablePlacement.lua:398-408.
function NachbarFelderManager:getIstSpawnFlaecheFrei(x, h, z, ry, laenge, breite)
    local frei = false
    pcall(function()
        local fx, fz = math.sin(ry), math.cos(ry)
        local mx = x - fx * (laenge * 0.5 - 3)
        local mz = z - fz * (laenge * 0.5 - 3)
        local ziel = { treffer = nil }
        ziel.nfUeberlappung = function(target, nodeId)
            if nodeId == nil or nodeId == 0 then return true end
            if getCollisionFilterMask(nodeId) == 1 then return true end
            if CollisionFlag.getHasGroupFlagSet(nodeId, CollisionFlag.ROAD) then return true end
            target.treffer = nodeId
            return false
        end
        local maske = CollisionMask.ALL - CollisionFlag.TERRAIN - CollisionFlag.TERRAIN_DELTA
                      - CollisionFlag.TERRAIN_DISPLACEMENT - CollisionFlag.TRIGGER - CollisionFlag.FILLABLE
        overlapBox(mx, h + 1.3, mz, 0, ry, 0, breite * 0.5, 1.0, laenge * 0.5,
            "nfUeberlappung", ziel, maske, true, true, true, true)
        frei = ziel.treffer == nil
    end)
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
            pcall(function()
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
            end)
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
        pcall(function()
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
            local zielX, zielZ = nil, nil
            if w.isPatrol then
                zielX, zielZ = w.patrolTargetX, w.patrolTargetZ
            else
                local field = g_fieldManager:getFieldById(entry.fieldId)
                if field ~= nil then zielX, zielZ = field.posX, field.posZ end
            end
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
        end)
    end
    local sp = w.spawnStrasse
    if sp == false or sp == nil then return false end

    local index = #(entry.vehicleType or {}) + 1
    local hinten = 0
    if index >= 2 then hinten = 9 + (index - 2) * 7 end
    local x = sp.x - math.sin(sp.ry) * hinten
    local z = sp.z - math.cos(sp.ry) * hinten
    local ok = pcall(function()
        local modellDrehung = (data.rotation ~= nil and data.rotation[2]) or 0
        -- Build 127: Fahrbahnhoehe statt Gelaendehoehe - Strassen liegen als Objekte
        -- ueber dem Gelaende; darin geladen rutschte das Fahrzeug seitlich heraus.
        -- Build 128: an der Ladestelle (Traktor bzw. Geraet dahinter) gemessene Fahrbahnhoehe
        local y = self:getFahrbahnHoehe(x, z, sp.h) + 0.15
        data:setPosition(x, y, z)
        data:setRotation(0, sp.ry + modellDrehung, 0)
    end)
    if ok and index == 1 then
        w.spawnAufStrasse = true
        local wer = w.isPatrol and "[TRAFFIC] Fahrzeug" or ("Feldhelfer fuer Feld " .. tostring(entry.fieldId))
        if sp.spawnpunktIdx ~= nil then
            print(string.format("NachbarFelder: %s wird am Spawnpunkt WP%d geladen", wer, sp.spawnpunktIdx))
        else
            print(string.format("NachbarFelder: %s wird direkt an der KI-Strasse geladen (%.0f m vom Shop-Platz," ..
                " freier Platz, Stufe %s, %d Stellen geprueft)", wer, sp.dist or 0, tostring(sp.stufe or "?"),
                sp.geprueft or 0))
        end
    end
    return ok
end

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

--- Taugt der Strassenpunkt als Ladeplatz? (Build 143, kartenunabhaengig)
--- Immer: nicht gesperrt, hinten noch Strasse, voraus kein Fahrzeug, Kasten 17 x 4 m frei.
--- streng zusaetzlich: Strasse laeuft 20 m vor und hinter dem Punkt gerade weiter
--- (keine Hofecke, keine Kurve), Fahrbahn eben, Kasten 30 x 5 m frei (Platz zum Losfahren).
function NachbarFelderManager:getIstLadeplatzGut(sp, rx, rz, ry, h, streng)
    if self:getIstSpawnPlatzGesperrt(rx, rz) then return false end   -- Build 129/142
    local dx, dz = sp[3], sp[4]
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

    local dynamicVeh = false
    if #NachbarFelderWorker.vehicleType >= 3 then
        dynamicVeh = string.sub(NachbarFelderWorker.vehicleType[3].typeName, 1, string.len("dynamic")) == "dynamic"
    end
    self.vehicleType[NachbarFelderWorker.fieldId].NachbarFelderWorker.status = 1
    self.vehicleType[NachbarFelderWorker.fieldId].NachbarFelderWorker.needTimer = true

    if NachbarFelderWorker.mission.type.name == "harvestMission" and
       #NachbarFelderWorker.vehicleType >= 3 and dynamicVeh then
        local x, y, z = getWorldTranslation(NachbarFelderWorker.vehicleType[3].rootNode)
        local dirX, _, dirZ = localDirectionToWorld(NachbarFelderWorker.vehicleType[3].rootNode, 0, 0, 1)
        g_currentMission:teleportVehicle(vehicle, x + dirX * 10, z + dirZ * 10, 0)
        NachbarFelderWorker.vehicleType[3]:forceDynamicMountPendingObjects(false)
        local pendingInfo = self:attachObjects(vehicle, NachbarFelderWorker.vehicleType[3], true)
        if pendingInfo ~= nil then
            pendingInfo.attacherVehicle:attachImplement(
                pendingInfo.attachable, pendingInfo.attachableJointDescIndex,
                pendingInfo.attacherVehicleJointDescIndex, true, nil, false, true, true)
        end
    else
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
            if pendingInfo ~= nil then   -- Build 125: Feldhelfer und Verkehr gleich
                -- Build 116: Feldhelfer - wie das Spiel an die Kupplung setzen, angehoben kuppeln
                self:setzeGeraetAnKupplung(pendingInfo.attacherVehicle, pendingInfo.attacherVehicleJointDescIndex,
                    pendingInfo.attachable, pendingInfo.attachableJointDescIndex)
                pendingInfo.attacherVehicle:attachImplement(
                    pendingInfo.attachable, pendingInfo.attachableJointDescIndex,
                    pendingInfo.attacherVehicleJointDescIndex, true, nil, false, true, true)
            elseif implement ~= nil then
                pcall(function()
                    if not implement.isAddedToPhysics then implement:addToPhysics() end
                end)
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
            pcall(function()
                attached = impl ~= nil and impl.getAttacherVehicle ~= nil
                    and impl:getAttacherVehicle() ~= nil
            end)
            if impl ~= nil and not attached then
                local fname = impl.configFileName or ""
                local base  = string.match(fname, "[^/\\]+$") or fname
                print("NachbarFelder: [TRAFFIC] Anbaugeraet nicht kuppelbar (" .. base ..
                    ") - entfernt, Fahrzeug faehrt solo.")
                pcall(function() impl:delete() end)
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
        pcall(function()
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
        end)
    end
end

function NachbarFelderManager:mountTrailer(vehicle, cutter, trailer)
    local x, y, z = getWorldTranslation(trailer.rootNode)
    local dirX, _, dirZ = localDirectionToWorld(trailer.rootNode, 0, 0, 1)
    local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
    g_currentMission:teleportVehicle(cutter, x + dirX * 1, z, angle)
end

function NachbarFelderManager:attachedCutterToTrailer(trailer)
    local spec = trailer.spec_dynamicMountAttacher
    local mountingIsAllowed = trailer:getAllowDynamicMountObjects()
    if mountingIsAllowed ~= spec.lastMountingIsAllowed or not spec.dynamicMountAttacherStateChangeMount then
        spec.lastMountingIsAllowed = mountingIsAllowed
        if mountingIsAllowed then
            for object, _ in pairs(spec.pendingDynamicMountObjects) do
                if spec.dynamicMountedObjects[object] == nil then
                    local doAttach = false
                    local objectRoot
                    if object.components ~= nil then
                        if object.getCanBeMounted ~= nil then doAttach = object:getCanBeMounted() end
                        objectRoot = object.components[1].node
                    end
                    if object.nodeId ~= nil then
                        if object.getCanBeMounted ~= nil then doAttach = object:getCanBeMounted() end
                        objectRoot = object.nodeId
                    end
                    local trigger = spec.dynamicMountAttacherTrigger
                    local objectJoint = createTransformGroup("dynamicMountObjectJoint")
                    link(trigger.jointNode, objectJoint)
                    setWorldTranslation(objectJoint, getWorldTranslation(objectRoot))
                    local couldMount = object:mountDynamic(trailer, trigger.rootNode, objectJoint,
                        trigger.mountType, trigger.forceAcceleration)
                    if couldMount then
                        object.additionalDynamicMountJointNode = objectJoint
                        trailer:addDynamicMountedObject(object)
                    end
                end
            end
        end
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
}

local function nfAIMessageName(msg)
    if msg == nil then return nil end
    for _, n in ipairs(NF_AI_MSG_CLASSES) do
        local cls = _G[n]
        if cls ~= nil then
            local ok, res = pcall(function() return msg.isa ~= nil and msg:isa(cls) end)
            if ok and res then return n end
        end
    end
    return "AIMessageUnbekannt"
end

-- ============================================================
-- driveToField: GOTO-Job zum Feld oder zurück zum Shop
-- WICHTIG: farmId darf NICHT 0 (Spectator) sein – der Engine
-- lehnt solche Jobs sofort ab → onAIJobFinished nach 5ms!
-- ============================================================
function NachbarFelderManager:driveToField(vehicle, fieldId, x, y, z, angleSD)
    local field = g_fieldManager:getFieldById(fieldId)
    if x == nil then
        x = field.posX
        z = field.posZ
    end

    -- Patrol-GOTO (fieldId < 0) = Straßennavigation zwischen WPs.
    -- Für Patrol wird KEIN createAgent/Feldarbeit-Setup ausgeführt:
    -- Vanilla "Freie Fahrt" macht das auch nicht. AIJobGoTo ruft
    -- createAgent intern auf – ein vorheriger Aufruf korrumpiert den Agent-State.
    local isPatrolGoto = fieldId ~= nil and fieldId < 0

    local helper = g_helperManager:getRandomHelper()

    if not isPatrolGoto then
        if vehicle.createAgent ~= nil then
            vehicle:createAgent(helper.index)
        end
        if vehicle.updateAIAgentAttachments ~= nil then
            vehicle:updateAIAgentAttachments()
        end

        local chainAttachments = vehicle.spec_aiDrivable ~= nil and vehicle.spec_aiDrivable.attachmentChains ~= nil
                                 and vehicle.spec_aiDrivable.attachmentChains[1]
        if chainAttachments then
            for i = 1, #chainAttachments do
                chainAttachments[i].hasCollision = false
            end
        end
        if vehicle.updateAIAgentAttachmentOffsetData ~= nil then
            vehicle:updateAIAgentAttachmentOffsetData()
        end

        local dynamicVeh = false
        if self.vehicleType[fieldId] ~= nil and
           #self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad >= 3 then
            dynamicVeh = string.sub(
                self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad[3].typeName,
                1, string.len("dynamic")) == "dynamic"
        end
        if dynamicVeh and vehicle.spec_aiDrivable ~= nil then
            vehicle.spec_aiDrivable.attachmentsMaxWidth = 2
            vehicle.spec_aiDrivable.agentInfo.length = math.min(1, vehicle.spec_aiDrivable.agentInfo.length / 4)
        end
    end

    -- prepareForAIDriving für alle (Patrol+Feldarbeit), aber OHNE createAgent für Patrol.
    if vehicle.prepareForAIDriving ~= nil then
        vehicle:prepareForAIDriving()
    end

    -- Anbaugeräte für Straßenfahrt falten (auch für Patrol sinnvoll).
    pcall(function()
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
    end)

    -- Build 122: nicht eingeklappte Geraete loggen und in 10 s nachpruefen
    pcall(function()
        if vehicle.getAttachedImplements == nil then return end
        for _, att in ipairs(vehicle:getAttachedImplements()) do
            local impl = att.object
            if self:getIstEingeklappt(impl) == false then
                print("NachbarFelder: [KLAPP] Einklappbefehl gegeben, noch offen: " .. self:getKlappText(impl))
                self.klappPruefung = self.klappPruefung or {}
                table.insert(self.klappPruefung, { impl = impl, at = g_time + 10000 })
            end
        end
    end)

    -- Motor sicherstellen (nach fehlgeschlagener Feldarbeit kann Motor aus sein)
    pcall(function()
        if vehicle.startMotor ~= nil and not vehicle:getIsMotorStarted() then
            vehicle:startMotor(true)
        end
    end)

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
    pcall(function() vehicle:setOwnerFarmId(self.farmId) end)
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

    -- Build 100: Zustand direkt NACH dem Start. Nur so ist zu sehen, warum ein
    -- Auftrag ohne Fehlermeldung anlaeuft und das Fahrzeug trotzdem steht.
    if nfW ~= nil and nfW.isPatrol then
        print("NachbarFelder: [TRAFFIC][DIAG] nach Start: " .. self:getVehicleAiDiag(vehicle))
    end
end

-- ============================================================
-- Feldarbeit starten
-- ============================================================
--- Zielpunkt fuer die Anfahrt eines Feldhelfers (Build 118).
---
--- Bisher: Feldmitte (field.posX/posZ) mit Winkel 0. AIJobGoTo:setValues macht
--- aus dem Winkel die geforderte ENDAUSRICHTUNG (AIJobGoTo.lua:154-156,
--- AIParameterPositionAngle:setAngle in Radiant) - der Helfer sollte also in der
--- Feldmitte genau nach Norden zeigen. Ohne Rueckwaertsfahren ist das oft nicht
--- planbar; Feld 69 scheiterte dreimal nach 7-19 s Wegsuche.
---
--- Jetzt: von der KI-Strasse, die der Feldmitte am naechsten liegt, in 4-m-Schritten
--- Richtung Mitte gehen bis zum ersten Punkt auf dem Feld (FieldState gueltig,
--- gleiches Farmland), dann 12 m weiter hinein. Ankunftsrichtung = Strasse -> Mitte,
--- also so, wie ein Fahrzeug von der Strasse aufs Feld faehrt.
--- Ohne Strasse/Feldpunkt: Feldmitte mit Richtung Fahrzeug -> Mitte.
--- @return number x, number z, number winkel (rad)
--- Soll der Stillstand-Waechter eines Feldhelfers eingreifen? (Build 124)
--- Nach 25 s, wenn ein anderes Fahrzeug naeher als 15 m steht (max. 3x je Helfer,
--- setzt w.feldWdHindernis), sonst nach 60 s.
function NachbarFelderManager:getFeldWdAusloesen(w, x, z, veh)
    local stehtMs = g_time - (w.feldWdSince or g_time)
    w.feldWdHindernis = nil
    w.feldWdSekunden  = math.floor(stehtMs / 1000)
    if stehtMs > 25000 and (w.feldHindernisPlanungen or 0) < 3 then
        local d, name = self:getNaechstesFremdfahrzeug(x, z, veh)
        if d ~= nil and d < 15 then
            w.feldWdHindernis = { d = d, name = name or "?" }
            return true
        end
    end
    return stehtMs > 60000
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

function NachbarFelderManager:getFeldZielpunkt(fieldId, vehicle)
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil or field.posX == nil then return nil, nil, nil end
    local cx, cz = field.posX, field.posZ
    local zx, zz, zw = cx, cz, nil
    local quelle = "Feldmitte"

    pcall(function()
        if vehicle ~= nil and vehicle.rootNode ~= nil then
            local vx, _, vz = getWorldTranslation(vehicle.rootNode)
            if MathUtil.vector2Length(cx - vx, cz - vz) > 1 then
                zw = MathUtil.getYRotationFromDirection(cx - vx, cz - vz)
            end
        end
    end)

    -- Build 141: Feldrand mit dem kuerzesten FREIEN Weg von einer KI-Strasse.
    -- Die KI faehrt uebers Strassennetz bis zum naechsten Punkt am Ziel und von
    -- dort gerade hin. Bisher: Strassenpunkt naechst der FELDMITTE, gerade Linie
    -- zur Mitte - dazwischen lagen oft fremde Felder oder Weiden (Feld 47:
    -- 124 m querfeldein). Jetzt wird der Feldumriss abgetastet; gewonnen hat
    -- die Randstelle mit der naechsten Strasse, deren Weg dorthin weder ein
    -- fremdes Feld noch eine Weide kreuzt. Ohne Umriss: alte Logik unten.
    local gefunden = false
    pcall(function()
        local rx, rz, rw, weg, frei = self:getFeldZugang(field)
        if rx == nil then return end
        zx, zz, zw = rx, rz, rw
        quelle = string.format("Feldrand nahe KI-Strasse (%.0f m von der Strasse, %s)", weg,
            frei and "Weg frei" or "kein freier Weg - Weg kreuzt fremdes Feld/Weide")
        gefunden = true
    end)

    pcall(function()
        if gefunden then return end
        if self.getNearestRoadPoint == nil or FieldState == nil or FieldState.new == nil then return end
        local rx, rz = self:getNearestRoadPoint(cx, cz, 500, 0)
        if rx == nil then return end
        local dx, dz = cx - rx, cz - rz
        local len = math.sqrt(dx * dx + dz * dz)
        if len < 8 then return end
        dx, dz = dx / len, dz / len
        local farmlandId = field.farmland ~= nil and field.farmland.id or nil
        local function aufFeld(px, pz)
            local probe = FieldState.new()
            probe:update(px, pz)
            return probe.isValid and (farmlandId == nil or probe.farmlandId == farmlandId)
        end
        for d = 0, len, 4 do
            local px, pz = rx + dx * d, rz + dz * d
            if aufFeld(px, pz) then
                local tief = math.min(12, math.max(len - d, 0))
                local tx, tz = px + dx * tief, pz + dz * tief
                if not aufFeld(tx, tz) then tx, tz = px, pz end
                zx, zz = tx, tz
                zw = MathUtil.getYRotationFromDirection(dx, dz)
                quelle = string.format("Feldrand zur Strasse (%.0f m von der Strasse)", d + tief)
                return
            end
        end
    end)

    print(string.format("NachbarFelder: Anfahrt Feld %s -> %s x=%.0f z=%.0f Richtung %.0f Grad",
        tostring(fieldId), quelle, zx, zz, math.deg(zw or 0)))
    return zx, zz, zw
end

-- Build 141: Zugang zum Feld von der KI-Strasse
NachbarFelderManager.ZUGANG_RAND_SCHRITT  = 8      -- m, Abstand der Pruefstellen am Feldrand
NachbarFelderManager.ZUGANG_MAX_STRASSE   = 250    -- m, so weit darf die Strasse hoechstens weg sein
NachbarFelderManager.ZUGANG_KANDIDATEN    = 120    -- so viele naechste Randstellen auf freien Weg pruefen
NachbarFelderManager.ZUGANG_TIEFE         = 10     -- m, Ziel so weit hinter dem Rand im Feld

--- Randstelle eines Felds, die von einer KI-Strasse aus auf kuerzestem Weg
--- erreichbar ist, ohne fremde Felder oder Weiden zu kreuzen (Build 141).
--- @return number|nil zx, number zz Ziel (ZUGANG_TIEFE im Feld), number zw Ankunftsrichtung,
---         number weg Abstand Strasse -> Feldrand, boolean frei Weg kreuzt nichts Fremdes
function NachbarFelderManager:getFeldZugang(field)
    local poly = self:getFeldPolygon(field)
    if poly == nil or poly.n < 3 or self.getNearestRoadPoint == nil then
        return nil
    end
    local inPoly, randAbst = self.nfPunktInPolygon, self.nfRandAbstand
    local farmlandId = field.farmland ~= nil and field.farmland.id or nil

    -- fremdes Feld (anderes Farmland) oder Weide an diesem Punkt?
    local function fremd(px, pz)
        if self:isPunktInWeide(px, pz) then
            return true
        end
        if FieldState == nil or FieldState.new == nil then
            return false
        end
        local probe = FieldState.new()
        probe:update(px, pz)
        return probe.isValid and farmlandId ~= nil and probe.farmlandId ~= farmlandId
    end
    local function wegFrei(rx, rz, px, pz)
        local len = MathUtil.vector2Length(px - rx, pz - rz)
        for d = 2, len - 2, 4 do
            local t = d / len
            if fremd(rx + (px - rx) * t, rz + (pz - rz) * t) then
                return false
            end
        end
        return true
    end

    -- Feldrand abtasten, je Stelle die naechste KI-Strasse
    local kandidaten = {}
    local schritt = NachbarFelderManager.ZUGANG_RAND_SCHRITT
    local j = poly.n
    for i = 1, poly.n do
        local ax, az, bx, bz = poly.x[j], poly.z[j], poly.x[i], poly.z[i]
        local len = MathUtil.vector2Length(bx - ax, bz - az)
        local n = math.max(1, math.floor(len / schritt))
        for k = 0, n - 1 do
            local px, pz = ax + (bx - ax) * k / n, az + (bz - az) * k / n
            local rx, rz, _, d = self:getNearestRoadPoint(px, pz, NachbarFelderManager.ZUGANG_MAX_STRASSE, 0)
            if rx ~= nil then
                table.insert(kandidaten, { px = px, pz = pz, rx = rx, rz = rz, d = d or 0 })
            end
        end
        j = i
    end
    if #kandidaten == 0 then
        return nil
    end
    table.sort(kandidaten, function(a, b) return a.d < b.d end)

    -- Ankunftsrichtung und Ziel ein Stueck im Feld, damit die KI nicht auf der
    -- Grenze haelt. nil, wenn es an dieser Stelle nicht ins Feld geht (Ecke, Spitze).
    local tiefen = { NachbarFelderManager.ZUGANG_TIEFE, 6, 3 }
    local function zielAn(c)
        local dx, dz = c.px - c.rx, c.pz - c.rz
        local len = math.sqrt(dx * dx + dz * dz)
        if len < 1 and field.posX ~= nil then
            -- Strasse beruehrt den Rand: Richtung Feldmitte
            dx, dz = field.posX - c.px, field.posZ - c.pz
            len = math.sqrt(dx * dx + dz * dz)
        end
        if len < 0.01 then
            return nil
        end
        dx, dz = dx / len, dz / len
        for _, tief in ipairs(tiefen) do
            local tx, tz = c.px + dx * tief, c.pz + dz * tief
            if inPoly(tx, tz, poly) and randAbst(tx, tz, poly) >= 2 then
                return tx, tz, dx, dz
            end
        end
        return nil
    end

    -- naechste Randstelle mit freiem Weg und Ziel im Feld; sonst die naechste mit Ziel
    local notX, notZ, notDx, notDz, notC = nil, nil, nil, nil, nil
    local anzahl = math.min(#kandidaten, NachbarFelderManager.ZUGANG_KANDIDATEN)
    for idx = 1, anzahl do
        local c = kandidaten[idx]
        local tx, tz, dx, dz = zielAn(c)
        if tx ~= nil then
            if wegFrei(c.rx, c.rz, c.px, c.pz) then
                return tx, tz, MathUtil.getYRotationFromDirection(dx, dz), c.d, true
            end
            if notX == nil then
                notX, notZ, notDx, notDz, notC = tx, tz, dx, dz, c
            end
        end
    end
    if notX == nil then
        return nil
    end
    return notX, notZ, MathUtil.getYRotationFromDirection(notDx, notDz), notC.d, false
end

function NachbarFelderManager:setAIOnField(NachbarFelderWorker)
    if NachbarFelderWorker.isPatrol then return end  -- Patrol hat keine Feldarbeit

    -- Fahrzeug aus vehiclesToLoad[1] holen (wie in update() auch)
    local vehicle = NachbarFelderWorker.vehiclesToLoad and NachbarFelderWorker.vehiclesToLoad[1]
    if vehicle == nil then
        vehicle = NachbarFelderWorker.vehicleType and NachbarFelderWorker.vehicleType[1]
    end
    if vehicle == nil then
        local vtLen = NachbarFelderWorker.vehicleType and #NachbarFelderWorker.vehicleType or "nil"
        local vlLen = NachbarFelderWorker.vehiclesToLoad and #NachbarFelderWorker.vehiclesToLoad or "nil"
        print("NachbarFelder: FEHLER setAIOnField - kein Fahrzeug! vehicleType#=" ..
            tostring(vtLen) .. " vehiclesToLoad#=" .. tostring(vlLen))
        return
    end
    local fieldId = NachbarFelderWorker.fieldId
    -- Feld-Zustand loggen, damit klar ist ob Feldarbeit überhaupt sinnvoll ist
    local dbgField = g_fieldManager:getFieldById(fieldId)
    local dbgFruitName = "?"
    local dbgPlowLevel = "?"
    local dbgGroundType = "?"
    local dbgWeedState = "?"
    local dbgSprayLevel = "?"
    local dbgGrowState = "?"
    if dbgField ~= nil then
        local dbgState = dbgField:getFieldState()
        if dbgState ~= nil then
            local dbgFruit = g_fruitTypeManager:getFruitTypeByIndex(dbgState.fruitTypeIndex)
            dbgFruitName  = dbgFruit ~= nil and dbgFruit.name or "leer"
            dbgPlowLevel  = tostring(dbgState.plowLevel  or "?")
            dbgGroundType = self:getBodenName(dbgState.groundType)   -- Build 111
            dbgWeedState  = tostring(dbgState.weedState  or "?")
            dbgSprayLevel = tostring(dbgState.sprayLevel or "?")
            dbgGrowState  = tostring(dbgState.growthState or "?")
        end
    end
    -- Feldgröße (field.areaHa, verifiziert) zur Info im Start-Log.
    local dbgArea = "?"
    pcall(function()
        if dbgField ~= nil and type(dbgField.areaHa) == "number" then
            dbgArea = string.format("%.2fha", dbgField.areaHa)
        end
    end)
    print("NachbarFelder: Feldarbeit Start " .. tostring(NachbarFelderWorker.mission.type.name) ..
        " Feld " .. tostring(fieldId) ..
        " | Groesse=" .. dbgArea ..
        " Frucht=" .. dbgFruitName ..
        " Wachstum=" .. dbgGrowState ..
        " Pflug=" .. dbgPlowLevel ..
        " Boden=" .. dbgGroundType ..
        " Unkraut=" .. dbgWeedState ..
        " Duenger=" .. dbgSprayLevel)

    -- Fülltyp je nach Mission bestimmen
    local forceFill = nil
    local missionTypeName = NachbarFelderWorker.mission and NachbarFelderWorker.mission.type and NachbarFelderWorker.mission.type.name
    if missionTypeName == "herbicideMission" then
        forceFill = "HERBICIDE"
    elseif missionTypeName == "fertilizeMission" then
        forceFill = "LIQUIDFERTILIZER"
    elseif missionTypeName == "sowMission" then
        forceFill = "SEEDS"
    end

    local vehs = vehicle:getChildVehicles()
    for _, veh in pairs(vehs) do
        self:setFillCapacity(veh, 100000, forceFill)
        if veh.changeSeedIndex ~= nil and veh.spec_sowingMachine ~= nil then
            -- Fruchtfolge-Saatwahl (Build 68): bewertet statt gewuerfelt
            self:chooseBestSeed(veh, fieldId)
        end
        if veh.setIsTurnedOn ~= nil then
            veh:setIsTurnedOn(true)
        end
    end

    local dynamicVeh = false
    if #self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad >= 3 then
        dynamicVeh = string.sub(
            self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad[3].typeName,
            1, string.len("dynamic")) == "dynamic"
    end
    if dynamicVeh then
        self:removeAttacher(self.vehicleType[fieldId].NachbarFelderWorker)
    end

    -- ---------------------------------------------------------------
    -- Implement-Kompatibilitätsprüfung VOR dem Job-Start
    -- Verhindert 17ms-Scheitern durch inkompatible Fahrzeug-Kombination.
    -- Spec-Mapping: welche spec wird für welchen Missionstyp benötigt?
    -- ---------------------------------------------------------------
    local implSpecRequired = nil
    if missionTypeName == "plowMission" then
        implSpecRequired = "spec_plow"
    elseif missionTypeName == "cultivateMission" then
        implSpecRequired = "spec_cultivator"
    elseif missionTypeName == "sowMission" then
        implSpecRequired = "spec_sowingMachine"
    elseif missionTypeName == "herbicideMission" or missionTypeName == "fertilizeMission" then
        implSpecRequired = "spec_sprayer"
    end

    if implSpecRequired ~= nil then
        local specFound = false
        local allVehs = vehicle:getChildVehicles()
        table.insert(allVehs, vehicle)
        for _, v in ipairs(allVehs) do
            if v[implSpecRequired] ~= nil then
                specFound = true
                break
            end
        end
        if not specFound then
            print("NachbarFelder: INKOMPATIBLES FAHRZEUG fuer " .. tostring(missionTypeName) ..
                " - brauche " .. tostring(implSpecRequired) .. " (Feld " .. tostring(fieldId) ..
                ") - Fahrzeug faehrt zurueck, kein Feldcooldown")
            -- Kein Feldcooldown (Feld ist ok, nur das Fahrzeug passt nicht)
            -- Direkt Rückfahrt ohne Feld zu bestrafen
            if NachbarFelderWorker.tempFarmland ~= nil then
                NachbarFelderWorker.tempFarmland.farmId  = NachbarFelderWorker.origFarmlandId
                NachbarFelderWorker.tempFarmland.isOwned = NachbarFelderWorker.origIsOwned
                NachbarFelderWorker.tempFarmland = nil
            end
            NachbarFelderWorker.status = 60
            NachbarFelderWorker.needTimer = true
            NachbarFelderWorker.gotoStartedAt = nil
            return
        end
    end

    -- fertilize: NUR flächige Ausbringer (Gülle/Flüssigdünger/Mist/Gärrest)
    -- zulassen. Mineralische Festdünger-Streuer behandelt Precision Farming
    -- mit variabler Rate (bedarfsgesteuert) → kaum Ausbringung → 15s-
    -- Kurzeinsatz (wie Herbizid). User-Entscheidung: solche aussortieren.
    if missionTypeName == "fertilizeMission" then
        local flaechig = false
        pcall(function()
            local okTypes = {"LIQUIDFERTILIZER", "LIQUIDMANURE", "MANURE", "DIGESTATE"}
            local checkVehs = vehicle:getChildVehicles()
            table.insert(checkVehs, vehicle)
            for _, v in ipairs(checkVehs) do
                if v.getFillUnits ~= nil then
                    for _, fu in ipairs(v:getFillUnits()) do
                        if fu.supportedFillTypes ~= nil then
                            for _, ftName in ipairs(okTypes) do
                                local idx = g_fillTypeManager:getFillTypeIndexByName(ftName)
                                if idx ~= nil and fu.supportedFillTypes[idx] then
                                    flaechig = true
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end)
        if not flaechig then
            print("NachbarFelder: Festduenger-Streuer fuer fertilize aussortiert " ..
                "(Precision Farming = variable Rate, nur Kurzeinsatz) - faehrt zurueck (Feld " ..
                tostring(fieldId) .. ")")
            -- Implement fuer fertilize sperren → kuenftig nur noch Guelle/Fluessig
            local implVeh = NachbarFelderWorker.vehiclesToLoad and NachbarFelderWorker.vehiclesToLoad[2]
            local implFile = implVeh ~= nil and (implVeh.configFileName or implVeh.typeName) or nil
            if implFile ~= nil then
                self.vehicleImplBlacklist["fertilizeMission"] = self.vehicleImplBlacklist["fertilizeMission"] or {}
                self.vehicleImplBlacklist["fertilizeMission"][implFile] =
                    (self.vehicleImplBlacklist["fertilizeMission"][implFile] or 0) + 1
            end
            if NachbarFelderWorker.tempFarmland ~= nil then
                NachbarFelderWorker.tempFarmland.farmId  = NachbarFelderWorker.origFarmlandId
                NachbarFelderWorker.tempFarmland.isOwned = NachbarFelderWorker.origIsOwned
                NachbarFelderWorker.tempFarmland = nil
            end
            NachbarFelderWorker.status = 60
            NachbarFelderWorker.needTimer = true
            NachbarFelderWorker.gotoStartedAt = nil
            return
        end
    end

    self.vehicleType[fieldId].NachbarFelderWorker.status = 2
    local field = g_fieldManager:getFieldById(fieldId)

    -- Fahrzeug-Besitzer auf echte Farm setzen (nicht Spectator 0!)
    -- Damit vehicle:getAIJobFarmId() die richtige ID zurückgibt.
    vehicle:setOwnerFarmId(self.farmId)

    -- KRITISCH: Feldbesitz VOR generateSteeringFieldCourse setzen!
    -- generateSteeringFieldCourse sucht intern das Feld per findClosestField.
    -- findClosestField prüft farmland.isOwned → schlägt fehl wenn noch false.
    -- Deshalb Besitz zuerst setzen, damit der Course korrekt generiert wird.
    local farmland = field ~= nil and field.farmland or nil
    local origFarmlandId = farmland ~= nil and farmland.farmId or nil
    local origIsOwned    = farmland ~= nil and farmland.isOwned or nil
    if farmland ~= nil then
        farmland.farmId  = self.farmId
        farmland.isOwned = true
    end

    vehicle:setAIModeSelection(AIModeSelection.MODE.WORKER)
    self.fieldCourseSettings, self.implementData = FieldCourseSettings.generate(vehicle)
    -- generateSteeringFieldCourse wieder aktiv (Test widerlegt: Entfernung
    -- machte die Arbeit nicht laenger, eher kuerzer → war nicht die Ursache).
    -- Zurueck zum referenz-konformen Zustand (FarmerWorkingAssistant).
    vehicle:generateSteeringFieldCourse(field.posX, field.posZ, FieldCourseSettings.generate(vehicle))

    local vehsFill = self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad
    for _, workVehicle in ipairs(vehsFill) do
        self:setFillCapacity(workVehicle, 100000, forceFill)
    end

    -- KRITISCH: Feld für die AI-Lenkung ERKENNEN.
    -- FieldCourse.findClosestField registriert das Feld intern in der FieldCourse-
    -- Steuerung (Seiteneffekt!). Ohne diesen Aufruf hat der FIELDWORK-Job kein Feld
    -- und endet sofort nach ~17ms. Der Aufruf respektiert den getIsMissionWorkAllowed-
    -- Hook → akzeptiert auch fremde Felder (farmId 2).
    -- Verifiziert in der funktionierenden Referenz-Mod FarmerWorkingAssistant
    -- (MissionInfo:setAIOnField). NICHT wieder durch "direktes Setzen" ersetzen –
    -- genau das war der Grund für die 17ms-Sofortabbrüche.
    self.fieldDetectionX, self.fieldDetectionZ = nil, nil
    pcall(function()
        self.fieldDetectionX, self.fieldDetectionZ = FieldCourse.findClosestField(
            nil, nil, nil, nil, vehicle:getAIJobFarmId(), vehicle, 2, self.fieldCourseSettings)
    end)
    if self.fieldDetectionX == nil then
        self.fieldDetectionX = field.posX
        self.fieldDetectionZ = field.posZ
        print("NachbarFelder: WARNUNG - findClosestField nil, nutze Feldmitte (Feld " ..
            tostring(fieldId) .. ")")
    end
    -- HINWEIS: setAIAutomaticSteeringEnabled() wurde ENTFERNT.
    -- Das aktiviert den GPS-Spurführungs-Modus (eine gerade Bahn, kein
    -- automatisches Abfahren des Feldes in Reihen) und überschrieb den
    -- FIELDWORK-Worker-Modus → Helfer fuhr nur ein kurzes Stück und war
    -- "fertig" (Spritze: ausklappen/kurz fahren/einklappen; Pflug: stand).
    -- Der reine FIELDWORK-Job (AIDriveStrategyFieldCourse) fährt das ganze
    -- Feld selbst ab. Falls der Helfer danach gar nicht losfährt, ist
    -- generateSteeringFieldCourse der nächste Verdächtige.

    -- Precision Farming: Ganzfeldbehandlung erzwingen
    -- Bekannte PF-Specs (aus Diagnose): spec_FS25_precisionFarming.weedSpotSpray
    --   → nur einzelne Unkrautflecken spritzen statt ganzes Feld → muss deaktiviert werden
    -- spec_FS25_precisionFarming.extendedSprayer
    --   → variable Ausbringungsrate nach Bodenanalyse → muss deaktiviert werden
    local pfVehicles = vehicle:getChildVehicles()
    table.insert(pfVehicles, vehicle)
    for _, pfVeh in pairs(pfVehicles) do
        pcall(function()
            local weedSpec = pfVeh["spec_FS25_precisionFarming.weedSpotSpray"]
            if weedSpec ~= nil then
                if weedSpec.isActive           ~= nil then weedSpec.isActive           = false end
                if weedSpec.isEnabled          ~= nil then weedSpec.isEnabled          = false end
                if weedSpec.enabled            ~= nil then weedSpec.enabled            = false end
                if weedSpec.active             ~= nil then weedSpec.active             = false end
                if weedSpec.isSpotSprayActive  ~= nil then weedSpec.isSpotSprayActive  = false end
                if weedSpec.spotSprayActive    ~= nil then weedSpec.spotSprayActive    = false end
                if weedSpec.activated          ~= nil then weedSpec.activated          = false end
                if weedSpec.setIsActive        ~= nil then weedSpec:setIsActive(false)         end
                if weedSpec.setEnabled         ~= nil then weedSpec:setEnabled(false)          end
                if weedSpec.setActive          ~= nil then weedSpec:setActive(false)           end
                if weedSpec.setIsSpotSprayActive ~= nil then weedSpec:setIsSpotSprayActive(false) end
            end
        end)
        pcall(function()
            local extSpray = pfVeh["spec_FS25_precisionFarming.extendedSprayer"]
            if extSpray ~= nil then
                if extSpray.sprayAmountAutoMode ~= nil then extSpray.sprayAmountAutoMode = false end
                if extSpray.setSprayAmountAutoMode ~= nil then
                    pcall(function() extSpray:setSprayAmountAutoMode(false, true) end)
                end
                if extSpray.sprayAmountManual ~= nil and extSpray.sprayAmountManualMax ~= nil then
                    extSpray.sprayAmountManual = extSpray.sprayAmountManualMax
                end
                if extSpray.setSprayAmountManual ~= nil then
                    pcall(function() extSpray:setSprayAmountManual(extSpray.sprayAmountManualMax or 45, true) end)
                end
                if extSpray.isDoingMissionWork ~= nil then extSpray.isDoingMissionWork = true end
                if extSpray.setIsDoingMissionWork ~= nil then
                    pcall(function() extSpray:setIsDoingMissionWork(true, true) end)
                end
                if extSpray.spotSprayEnabled  ~= nil then extSpray.spotSprayEnabled  = false end
                if extSpray.isSpotSprayActive ~= nil then extSpray.isSpotSprayActive = false end
                if extSpray.spotSprayIsActive ~= nil then extSpray.spotSprayIsActive = false end
                if extSpray.setSpotSprayEnabled ~= nil then
                    pcall(function() extSpray:setSpotSprayEnabled(false, true) end)
                end
            end
        end)
    end

    local helper = g_helperManager:getRandomHelper()
    if vehicle.createAgent ~= nil then
        vehicle:createAgent(helper.index)
    end

    if not vehicle:getIsAIActive() then
        vehicle:toggleAIVehicle()
    end

    local job = g_currentMission.aiJobTypeManager:createJob(AIJobType.FIELDWORK)
    -- Kostenneutral (Build 91) - siehe Begruendung bei AIJobType.GOTO.
    if job ~= nil then
        job.getPricePerMs = function() return 0 end
    end
    if job == nil then
        print("NachbarFelder: FEHLER - AIJobType.FIELDWORK konnte nicht erstellt werden!")
        -- Feldbesitz wiederherstellen
        if farmland ~= nil then
            farmland.farmId  = origFarmlandId
            farmland.isOwned = origIsOwned
        end
        return
    end
    -- Job-Setup exakt wie in der funktionierenden Referenz (FarmerWorkingAssistant:
    -- setAIOnField): KEIN manuelles setPosition. applyCurrentState + setValues
    -- ermitteln die Feldposition aus dem zuvor per findClosestField erkannten Feld.
    -- Das frühere manuelle Forcen der Position kollidierte mit dieser internen
    -- Erkennung und war Teil des Sofortabbruch-Problems.
    job.positionAngleParameter:setAngle(0)
    if job.applyCurrentState ~= nil then
        job:applyCurrentState(vehicle, g_currentMission, self.farmId, true)
    end
    job.vehicleParameter:setVehicle(vehicle)
    job:setValues()

    -- ALLE Geräte als Helfer markieren BEVOR der Job startet, damit der
    -- erste getIsMissionWorkAllowed-Aufruf der Spritze/des Pflugs durchgeht.
    self:markVehiclesAsHelper(vehicle)

    self.vehicleType[fieldId].NachbarFelderWorker.fieldWorkStartedAt = g_time

    -- Build 141: Abbruchgrund der Feldarbeit merken (wie beim GOTO in driveToField) -
    -- nur job:stop sieht die AIMessage. Feld 47 endete nach 0 s ohne erkennbaren Grund.
    local nfWFeld = self.vehicleType[fieldId].NachbarFelderWorker
    nfWFeld.lastFieldStopMsg = nil
    if job.stop ~= nil then
        local origStop = job.stop
        job.stop = function(jSelf, aiMessage)
            nfWFeld.lastFieldStopMsg = nfAIMessageName(aiMessage)
            return origStop(jSelf, aiMessage)
        end
    end
    -- Wo steht das Gespann beim Start, und wo hat findClosestField das Feld erkannt?
    local startInfo = ""
    pcall(function()
        local vx, _, vz = getWorldTranslation(vehicle.rootNode)
        local poly = self:getFeldPolygon(field)
        local imFeld = "?"
        if poly ~= nil then
            imFeld = self.nfPunktInPolygon(vx, vz, poly) and "ja" or
                string.format("nein, %.0f m vom Rand", self.nfRandAbstand(vx, vz, poly))
        end
        startInfo = string.format(" | Gespann x=%.0f z=%.0f im Feld: %s | Felderkennung x=%.0f z=%.0f",
            vx, vz, imFeld, self.fieldDetectionX or 0, self.fieldDetectionZ or 0)
    end)

    g_currentMission.aiSystem:startJob(job, self.farmId)
    print("NachbarFelder: FIELDWORK Feld=" .. tostring(fieldId) .. " (" .. tostring(missionTypeName) .. ")" .. startInfo)

    -- Feldbesitz NICHT sofort zurücksetzen!
    -- Die KI prüft während der Arbeit wiederholt FieldCourse.findClosestField →
    -- würde das Feld sonst nicht mehr finden und nach ~30s stoppen.
    -- Originalwerte im Worker speichern, werden in onAIFieldWorkerEnd wiederhergestellt.
    if farmland ~= nil then
        self.vehicleType[fieldId].NachbarFelderWorker.origFarmlandId  = origFarmlandId
        self.vehicleType[fieldId].NachbarFelderWorker.origIsOwned     = origIsOwned
        self.vehicleType[fieldId].NachbarFelderWorker.tempFarmland    = farmland
    end

    self:markVehiclesAsHelper(vehicle)
end

function NachbarFelderManager:removeAttacher(tt)
    local trailer = tt.vehiclesToLoad[3]
    trailer:forceUnmountDynamicMountedObjects()
    tt.removeVehicleInfo.fileName = trailer.configFileName
    tt.removeVehicleInfo.configurations = trailer.configurations
    tt.removeVehicleInfo.fieldId = tt.fieldId
    trailer:delete()

    local x, y, z = getWorldTranslation(tt.vehiclesToLoad[1].rootNode)
    local dirX, dirY, dirZ = localDirectionToWorld(tt.vehiclesToLoad[1].rootNode, 0, 0, 1)
    local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
    g_currentMission:teleportVehicle(tt.vehiclesToLoad[2], x + dirX * 9, z + dirZ * 9, angle)
    self:attachObjectToCar(tt.vehiclesToLoad[1], tt.vehiclesToLoad[2])
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

-- ============================================================
-- Feldauswahl
-- ============================================================

--- Felder, auf denen wirklich etwas steht (Build 137).
---
--- Manche Karten stellen Weiden, Stallgebaeude oder Hallen auf Flaechen, die
--- noch zum Verkauf stehen. Fuer den FieldManager ist das weiterhin ein
--- unbewirtschaftetes Feld, also schickt die Mod einen Helfer hin - der dann
--- mitten im Gebaeude landet.
---
--- Bis Build 136 galt dafuer ein ganzes Farmland als bebaut, sobald
--- IRGENDEIN Placeable mit seinem rootNode darauf stand. Bergisch Land hat
--- 968 Karten-Placeables (456 Laub-/Naesse-Effekte, 217 Deko, 36 Zaeune ...)
--- an den Feldraendern: 119 Farmlands und 83 von 138 Feldern fielen weg, die
--- Feldarbeit fand kein einziges Feld. Offline gegen die Feldumrisse der
--- map.i3d gerechnet (Bergisch Land, Beuren, Krebach): kein rootNode liegt in
--- einem Feld, die tiefste Grundflaeche (Schweinestall) ragt 0,5 m hinein.
---
--- Jetzt zaehlt ein Feld nur noch als bebaut, wenn ein Hindernis-Punkt
--- mindestens BEBAUT_MIN_TIEFE Meter innerhalb des Feldumrisses liegt. Die
--- Punkte je Placeable liefert getPlaceableHindernis: rootNode, Raster ueber
--- jede Grundflaeche (placement.testAreas) und bei Zaeunen, Hecken und
--- Weiden die Zaunlinie. Placeables ohne Kollision (Effekte, Decals) zaehlen
--- nicht, ebenso das Schienennetz.
---
--- Verifiziert:
---   field.polygonPoints = Knoten des Feldumrisses (Field.lua:36/82)
---   spec_placement.testAreas[i].startNode/endNode, endNode ist direktes Kind
---     von startNode (PlaceablePlacement.lua:145-165)
---   placeable.pickObjects = alle Knoten mit RigidBody (Placeable.lua:246,
---     gefuellt in finalizePlacement Zeile 742 ueber collectPickObjects)
---   spec_newFence / spec_fence / spec_trainSystem (PlaceableNewFence.lua:88,
---     PlaceableFence.lua:151, PlaceableTrainSystem.lua:119); getFence() bei
---     newFence und husbandryFence (PlaceableNewFence.lua:30,
---     PlaceableHusbandryFence.lua:34), beide Fence.new -> getSegments()
---   localToLocal / localToWorld (PlaceablePlacement.lua:168, DebugUtil.lua:172)
---   placeable:getName() (Placeable.lua:1219), configFileNameClean (Zeile 258)
NachbarFelderManager.BEBAUT_MIN_TIEFE = 1.0   -- m, so weit muss ein Hindernis ins Feld ragen
-- Build 139: Messpunkte fuer den Feldzustand (getFeldAktion) muessen so weit
-- im Feldumriss liegen - am Rand liegen Vorgewende, Grasnarbe, Nachbarflaechen.
NachbarFelderManager.MESSPUNKT_RANDABSTAND = 2.0
-- Build 142: Hochachse des Traktors zeigt weniger als so weit nach oben (cos ~72 Grad) = umgekippt
NachbarFelderManager.KIPP_GRENZE = 0.3
NachbarFelderManager.BEBAUT_RASTER    = 8.0   -- m, max. Punktabstand auf Grundflaechen/Zaeunen
NachbarFelderManager.BEBAUT_ZELLE     = 50    -- m, Kantenlaenge des Suchrasters

--- Punkt im Polygon {x={}, z={}, n=} (Ray-Casting wie isPunktInWeide).
local function nfPunktInPolygon(x, z, poly)
    local px, pz, n = poly.x, poly.z, poly.n
    local drin = false
    local j = n
    for i = 1, n do
        if (pz[i] > z) ~= (pz[j] > z) then
            local schnittX = px[i] + (z - pz[i]) / (pz[j] - pz[i]) * (px[j] - px[i])
            if x < schnittX then
                drin = not drin
            end
        end
        j = i
    end
    return drin
end

--- Kleinster Abstand eines Punktes zum Rand des Polygons (m).
local function nfRandAbstand(x, z, poly)
    local px, pz, n = poly.x, poly.z, poly.n
    local best = math.huge
    local j = n
    for i = 1, n do
        local ax, az = px[j], pz[j]
        local dx, dz = px[i] - ax, pz[i] - az
        local l2 = dx * dx + dz * dz
        local t = 0
        if l2 > 0 then
            t = ((x - ax) * dx + (z - az) * dz) / l2
            if t < 0 then
                t = 0
            elseif t > 1 then
                t = 1
            end
        end
        local ex, ez = x - (ax + t * dx), z - (az + t * dz)
        local d = ex * ex + ez * ez
        if d < best then
            best = d
        end
        j = i
    end
    return math.sqrt(best)
end

-- Build 139: fuer NachbarFelderAuftrag.lua (Feld an der Spielerposition).
-- Als Tabellenfelder, damit sie auch nach dem zweiten Laden dieser Datei
-- (addSpecialization) ueber die Manager-Instanz erreichbar sind.
NachbarFelderManager.nfPunktInPolygon = nfPunktInPolygon
NachbarFelderManager.nfRandAbstand    = nfRandAbstand

--- Feldumriss als Polygon (Build 137). Felder bewegen sich nicht, also
--- einmal je Feld gelesen.
--- @return table|nil {x={}, z={}, n=, minX=, maxX=, minZ=, maxZ=}
function NachbarFelderManager:getFeldPolygon(field)
    if field == nil then
        return nil
    end
    self.feldPolygone = self.feldPolygone or {}
    local poly = self.feldPolygone[field]
    if poly == nil then
        poly = false
        pcall(function()
            local knoten = field.polygonPoints
            if type(knoten) ~= "table" or #knoten < 3 then
                return
            end
            local px, pz = {}, {}
            local minX, maxX = math.huge, -math.huge
            local minZ, maxZ = math.huge, -math.huge
            for i, node in ipairs(knoten) do
                local x, _, z = getWorldTranslation(node)
                px[i], pz[i] = x, z
                minX = math.min(minX, x)
                maxX = math.max(maxX, x)
                minZ = math.min(minZ, z)
                maxZ = math.max(maxZ, z)
            end
            poly = { x = px, z = pz, n = #px, minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
        end)
        self.feldPolygone[field] = poly
    end
    if poly == false then
        return nil
    end
    return poly
end

--- Hindernis-Punkte eines Placeables in Weltkoordinaten (Build 137).
--- Placeables bewegen sich nicht, die Punkte werden je Objekt gemerkt
--- (schwache Schluessel: verkaufte Placeables fallen von selbst heraus).
--- @return table|nil {x={}, z={}, n=, name=} oder nil = kein Hindernis
function NachbarFelderManager:getPlaceableHindernis(p)
    if p == nil or p.rootNode == nil then
        return nil
    end
    if self.hindernisCache == nil then
        self.hindernisCache = setmetatable({}, { __mode = "k" })
    end
    local h = self.hindernisCache[p]
    if h ~= nil then
        if h == false then
            return nil
        end
        return h
    end

    h = false
    pcall(function()
        -- Schienennetz: rootNode im Ursprung, die Strecke laeuft ueber die
        -- ganze Karte und kreuzt Felder nicht
        if p.spec_trainSystem ~= nil then
            return
        end

        local raster = NachbarFelderManager.BEBAUT_RASTER or 8.0
        local px, pz = {}, {}
        local function add(x, z)
            if x ~= nil and z ~= nil then
                px[#px + 1] = x
                pz[#pz + 1] = z
            end
        end

        -- Zaeune, Hecken, Weiden: die Zaunlinie selbst. Deren rootNode liegt
        -- oft im Kartenursprung (Krebach: Zaeune und Hecken auf Feld 49).
        local istZaun = p.spec_newFence ~= nil or p.spec_fence ~= nil
        if p.getFence ~= nil and (istZaun or p.spec_husbandryFence ~= nil) then
            pcall(function()
                local fence = p:getFence()
                if fence == nil or fence.getSegments == nil then
                    return
                end
                for _, seg in ipairs(fence:getSegments() or {}) do
                    if seg.startPosX ~= nil and seg.startPosZ ~= nil
                            and seg.endPosX ~= nil and seg.endPosZ ~= nil then
                        local dx, dz = seg.endPosX - seg.startPosX, seg.endPosZ - seg.startPosZ
                        local schritte = math.max(1, math.ceil(math.sqrt(dx * dx + dz * dz) / raster))
                        for k = 0, schritte do
                            add(seg.startPosX + dx * k / schritte, seg.startPosZ + dz * k / schritte)
                        end
                    end
                end
            end)
        end

        -- Ohne Kollision kein Hindernis: Laub, Pfuetzen, Decals ...
        local hatKollision = not (type(p.pickObjects) == "table" and next(p.pickObjects) == nil)

        if not istZaun and hatKollision then
            local x, _, z = getWorldTranslation(p.rootNode)
            if math.abs(x) > 1 or math.abs(z) > 1 then
                add(x, z)
            end

            -- Grundflaeche: Raster mit hoechstens BEBAUT_RASTER m Abstand,
            -- Ecken und Kanten immer dabei
            local sp = p.spec_placement
            if sp ~= nil and type(sp.testAreas) == "table" then
                for _, area in ipairs(sp.testAreas) do
                    if area.startNode ~= nil and area.endNode ~= nil then
                        pcall(function()
                            local ox, _, oz = localToLocal(area.endNode, area.startNode, 0, 0, 0)
                            local nx = math.min(6, math.max(1, math.ceil(math.abs(ox) / raster)))
                            local nz = math.min(6, math.max(1, math.ceil(math.abs(oz) / raster)))
                            for i = 0, nx do
                                for j = 0, nz do
                                    local wx, _, wz = localToWorld(area.startNode, ox * i / nx, 0, oz * j / nz)
                                    add(wx, wz)
                                end
                            end
                        end)
                    end
                end
            end
        end

        if #px == 0 then
            return
        end

        local name = nil
        pcall(function()
            name = p:getName()
        end)
        if name == nil or name == "" then
            name = p.configFileNameClean or p.typeName or "?"
        end
        h = { x = px, z = pz, n = #px, name = tostring(name) }
    end)

    self.hindernisCache[p] = h
    if h == false then
        return nil
    end
    return h
end

--- Welche Felder sind bebaut? (Build 137, ersetzt getBebauteFarmlands)
--- @return table field -> Name des Hindernisses (nur bebaute Felder)
function NachbarFelderManager:getBebauteFelder()
    local jetzt = g_currentMission ~= nil and g_currentMission.time or 0

    -- Alle 5 Spielminuten neu einlesen: der Spieler kann jederzeit bauen.
    if self.bebauteFelder ~= nil
            and self.bebauteFelderZeit ~= nil
            and jetzt - self.bebauteFelderZeit < 300000 then
        return self.bebauteFelder
    end

    local treffer   = {}
    local liste     = {}
    local anzahl    = 0
    local hindernis = 0
    local ohne      = 0
    local minTiefe  = NachbarFelderManager.BEBAUT_MIN_TIEFE or 1.0
    local zelle     = NachbarFelderManager.BEBAUT_ZELLE or 50

    pcall(function()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil or g_fieldManager == nil or g_fieldManager.getFields == nil then
            return
        end

        -- Alle Hindernis-Punkte in ein 50-m-Raster, damit jedes Feld nur die
        -- Punkte in seiner Naehe prueft.
        local raster = {}
        for _, p in ipairs(ps.placeables or {}) do
            local h = self:getPlaceableHindernis(p)
            if h ~= nil then
                hindernis = hindernis + 1
                for k = 1, h.n do
                    local key = math.floor(h.x[k] / zelle) .. ":" .. math.floor(h.z[k] / zelle)
                    local c = raster[key]
                    if c == nil then
                        c = {}
                        raster[key] = c
                    end
                    c[#c + 1] = { h.x[k], h.z[k], h }
                end
            else
                ohne = ohne + 1
            end
        end

        for id, field in pairs(g_fieldManager:getFields() or {}) do
            pcall(function()
                local poly = self:getFeldPolygon(field)
                if poly == nil then
                    return
                end
                local fund = nil
                local cx1, cx2 = math.floor(poly.minX / zelle), math.floor(poly.maxX / zelle)
                local cz1, cz2 = math.floor(poly.minZ / zelle), math.floor(poly.maxZ / zelle)
                for cx = cx1, cx2 do
                    for cz = cz1, cz2 do
                        local c = raster[cx .. ":" .. cz]
                        if c ~= nil then
                            for _, pt in ipairs(c) do
                                local x, z = pt[1], pt[2]
                                if x >= poly.minX and x <= poly.maxX and z >= poly.minZ and z <= poly.maxZ
                                        and nfPunktInPolygon(x, z, poly)
                                        and nfRandAbstand(x, z, poly) >= minTiefe then
                                    fund = pt[3].name
                                    break
                                end
                            end
                        end
                        if fund ~= nil then
                            break
                        end
                    end
                    if fund ~= nil then
                        break
                    end
                end
                if fund ~= nil then
                    treffer[field] = fund
                    anzahl = anzahl + 1
                    if #liste < 12 then
                        table.insert(liste, "Feld " .. tostring(self:getFeldNummer(field, id)) .. " (" .. fund .. ")")
                    end
                end
            end)
        end
    end)

    self.bebauteFelder     = treffer
    self.bebauteFelderZeit = jetzt

    -- Beim ersten Mal und wenn sich die Zahl aendert (Spieler baut/verkauft)
    if self.bebauteGemeldet ~= anzahl then
        self.bebauteGemeldet = anzahl
        print(string.format("NachbarFelder: %d Felder bebaut (Hindernis mind. %.0f m im Feld) - werden ausgelassen%s" ..
              " [%d Placeables mit Hindernis-Punkten, %d ohne Kollision/uebersprungen]",
              anzahl, minTiefe, (#liste > 0 and (": " .. table.concat(liste, ", ")) or ""), hindernis, ohne))
    end

    return treffer
end

--- Eingezaeunte Weiden als Polygone (Build 82).
---
--- Bis Build 136 pruefte getBebauteFarmlands() nur den rootNode eines
--- Placeables, also die Mitte des Stallgebaeudes. Der Weidezaun eines
--- Kuhstalls reicht aber viel weiter als das Gebaeude und laeuft regelmaessig
--- auf ein Nachbar-Farmland hinueber. Fuer den FieldManager ist das dortige
--- Feld frei, der rootNode liegt aber auf einer anderen Flaeche - also griff
--- der Farmland-Filter nicht und der Helfer landete mitten in der Kuhweide.
---
--- Diese Liste sammelt die Zaunverlaeufe selbst ein, damit der Punkt-Test in
--- isPunktInWeide() unabhaengig von Farmland-Grenzen arbeitet. Seit Build 137
--- faengt getBebauteFelder() Zaunlinien, die ins Feld laufen; dieser Test
--- bleibt fuer Felder, die ganz innerhalb einer Weide liegen.
---
--- Verifiziert: PlaceableHusbandryFence:getFence() liefert das Fence-Objekt
--- (PlaceableHusbandryFence.lua:655), fence:getSegments() die Segmentliste
--- (dort Zeile 252/258/279 verwendet), FenceSegment traegt die Weltkoordinaten
--- startPosX/Y/Z und endPosX/Y/Z (FenceSegment.lua:362, readStream ab 383).
--- @return table Liste von {minX=,maxX=,minZ=,maxZ=,punkte={{x=,z=},...}}
function NachbarFelderManager:getWeideBereiche()
    local jetzt = g_currentMission ~= nil and g_currentMission.time or 0

    -- Alle 5 Spielminuten neu einlesen: der Spieler kann jederzeit bauen.
    if self.weideBereiche ~= nil
            and self.weideBereicheZeit ~= nil
            and jetzt - self.weideBereicheZeit < 300000 then
        return self.weideBereiche
    end

    local bereiche = {}

    pcall(function()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil then
            return
        end

        for _, p in ipairs(ps.placeables or {}) do
            -- NUR Tierweiden, nicht jeder Zaun! getFence() registrieren
            -- sowohl PlaceableHusbandryFence (Zeile 34) als auch
            -- PlaceableNewFence (Zeile 30) - ohne die Spec-Pruefung gilt
            -- jede umzaeunte Flaeche als Weide und alle Felder darin werden
            -- gesperrt (Build 82 hatte genau diesen Fehler: die Helfer
            -- bekamen kein Feld mehr und standen).
            if p ~= nil and p.spec_husbandryFence ~= nil and p.getFence ~= nil then
                pcall(function()
                    local fence = p:getFence()
                    if fence == nil or fence.getSegments == nil then
                        return
                    end

                    local punkte = {}
                    local minX, maxX = math.huge, -math.huge
                    local minZ, maxZ = math.huge, -math.huge

                    for _, seg in ipairs(fence:getSegments() or {}) do
                        -- Die Segmente sind verkettet (start = end des
                        -- Vorgaengers), die Endpunkte ergeben also den
                        -- Umlauf der Weide.
                        if seg.endPosX ~= nil and seg.endPosZ ~= nil then
                            if #punkte == 0 and seg.startPosX ~= nil then
                                table.insert(punkte, {x = seg.startPosX, z = seg.startPosZ})
                            end
                            table.insert(punkte, {x = seg.endPosX, z = seg.endPosZ})
                        end
                    end

                    if #punkte < 3 then
                        return
                    end

                    for _, pt in ipairs(punkte) do
                        minX = math.min(minX, pt.x)
                        maxX = math.max(maxX, pt.x)
                        minZ = math.min(minZ, pt.z)
                        maxZ = math.max(maxZ, pt.z)
                    end

                    table.insert(bereiche, {
                        minX = minX, maxX = maxX,
                        minZ = minZ, maxZ = maxZ,
                        punkte = punkte,
                    })
                end)
            end
        end
    end)

    self.weideBereiche     = bereiche
    self.weideBereicheZeit = jetzt

    if self.weideGemeldet ~= true then
        self.weideGemeldet = true
        print("NachbarFelder: " .. tostring(#bereiche) ..
              " eingezaeunte Weiden erkannt - dort wird nicht gearbeitet")
    end

    return bereiche
end

--- Liegt der Punkt in einer eingezaeunten Weide? (Build 82)
--- Bounding-Box als schneller Vorfilter, danach Punkt-in-Polygon
--- (Ray-Casting nach Westen).
--- @param number x Weltkoordinate
--- @param number z Weltkoordinate
--- @return boolean
function NachbarFelderManager:isPunktInWeide(x, z)
    if x == nil or z == nil then
        return false
    end

    for _, w in ipairs(self:getWeideBereiche()) do
        if x >= w.minX and x <= w.maxX and z >= w.minZ and z <= w.maxZ then
            local drin = false
            local n = #w.punkte
            local j = n
            for i = 1, n do
                local pi, pj = w.punkte[i], w.punkte[j]
                if (pi.z > z) ~= (pj.z > z) then
                    local schnittX = pi.x + (z - pi.z) / (pj.z - pi.z) * (pj.x - pi.x)
                    if x < schnittX then
                        drin = not drin
                    end
                end
                j = i
            end
            if drin then
                return true
            end
        end
    end

    return false
end

--- Feld dauerhaft aussperren (Konsole: nachbarFelderSperre <Nr>).
--- Notausgang fuer Faelle, die die automatische Erkennung nicht abdeckt.
function NachbarFelderManager:sperreFeld(fieldId, an)
    self.feldSperre = self.feldSperre or {}
    if an == false then
        self.feldSperre[fieldId] = nil
        return false
    end
    self.feldSperre[fieldId] = true
    return true
end

-- ============================================================
-- Feldnummer (Build 139)
-- Es gibt nur EINE Feldnummer: field:getId(). Das ist die Nummer auf der
-- Karte und in den Vertragsmeldungen, und genau sie erwartet getFieldById -
-- das Spiel speichert Felder mit getId() und laedt sie mit getFieldById
-- (FieldManager:saveToXMLFile/loadFromXMLFile, AbstractFieldMission).
-- Der Listenplatz in getFields() ist KEINE Feldnummer: Die Nummern folgen
-- den Farmlands und koennen Luecken haben. Alle Schluessel der Mod
-- (vehicleType, feldSperre, fieldCooldown, Spielstand) sind diese Nummer.
-- ============================================================
--- Feldnummer eines Feld-Objekts: field:getId(), sonst field.fieldId/field.id,
--- zuletzt der Listenplatz (nur falls getId in einer anderen Spielversion fehlt).
--- @param listIndex optional, Schluessel aus pairs(getFields())
--- @return number|nil
function NachbarFelderManager:getFeldNummer(field, listIndex)
    if field == nil then return nil end
    local nr = nil
    if field.getId ~= nil then
        pcall(function()
            nr = field:getId()
        end)
    end
    if type(nr) ~= "number" then
        nr = field.fieldId or field.id or listIndex
    end
    return nr
end

--- Nummern aller Felder aus der echten Feldliste - Grundlage der Zufallswahl.
--- Bewusst NICHT math.random(1, #getFields()): das waere ein Listenplatz.
function NachbarFelderManager:getFeldNummern()
    local liste = {}
    for idx, field in pairs(g_fieldManager:getFields() or {}) do
        local nr = self:getFeldNummer(field, idx)
        if nr ~= nil then
            table.insert(liste, nr)
        end
    end
    return liste
end

function NachbarFelderManager:isFieldUseful(fieldId)
    -- Manuell gesperrt?
    if self.feldSperre ~= nil and self.feldSperre[fieldId] then return nil end
    if self.vehicleType[fieldId] ~= nil then return nil end
    -- Cooldown: Feld hat kürzlich gescheitert → überspringen
    if self.fieldCooldown[fieldId] ~= nil and self.fieldCooldown[fieldId] > 0 then return nil end
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil or field.farmland == nil or field.farmland.isOwned then return nil end
    -- Build 106: nur das Feld ueberspringen, auf dem wirklich ein Vertrag
    -- liegt. Bisher wurde "farmland.id == fieldId" verglichen - eine
    -- Farmland-Nummer mit einer Feld-Nummer - und dazu JEDES Feld gesperrt,
    -- sobald irgendein Vertragsfeld einen Besitzer hatte.
    for v = 1, #g_missionManager.missions do
        local mission = g_missionManager.missions[v]
        if type(mission.getField) == "function" and self:getIstVertragAktiv(mission) then
            local mf = mission:getField()
            if mf ~= nil and (mf == field or (mf.farmland ~= nil and mf.farmland == field.farmland)) then
                return nil
            end
        end
    end

    -- Ragt ein Stall, eine Halle oder ein Zaun ins Feld? Dann ist das Feld
    -- zwar formal frei, praktisch aber bebaut - der Helfer wuerde mitten
    -- hineinfahren. Build 137: je Feld nach Umriss statt je Farmland.
    local bebaut = self:getBebauteFelder()
    if bebaut ~= nil and bebaut[field] ~= nil then
        return nil
    end

    -- Liegt das Feld in einer eingezaeunten Weide? Der Farmland-Test oben
    -- greift nur, wenn der Stall-rootNode auf derselben Flaeche steht - eine
    -- Weide, die auf ein Nachbar-Farmland hinueberreicht, rutscht durch.
    if self:isPunktInWeide(field.posX, field.posZ) then
        if self.weideSkip == nil then self.weideSkip = {} end
        if self.weideSkip[fieldId] == nil then
            self.weideSkip[fieldId] = true
            print("NachbarFelder: Feld " .. tostring(fieldId) ..
                  " liegt in einer eingezaeunten Weide - wird ausgelassen")
        end
        return nil
    end

    -- Winzige Felder ueberspringen: < 0.3 ha (3000 m²). Dort ist der
    -- generierte Field Course zu klein/leer → der fieldWorkTask scheitert
    -- sofort (~446ms, belegt bei Feld 54 = 0.14ha) statt zu arbeiten, und
    -- das Implement landet faelschlich auf der Sperrliste. Verifiziert:
    -- field.areaHa (Krebach: 0.14-1.22ha). Bodengeraete (plow/sow) arbeiten
    -- auf >=0.9ha-Feldern nachweislich das ganze Feld ab.
    if field.areaHa ~= nil and field.areaHa < 0.3 then
        return nil
    end

    -- Build 105/107/111: nur fremde Felder, die abgeerntet, verdorrt oder als
    -- Stoppel leer sind, und nur Pfluegen oder Grubbern. Die Entscheidung
    -- trifft getFeldAktion (mehrere Messpunkte, siehe dort).
    if field.grassMissionOnly then return nil end
    local aktion, grund, info = self:getFeldAktion(field)
    if aktion == 3 and not (self.missionHelper[3] ~= nil and self.missionHelper[3].active) then
        aktion = 4
    end
    if aktion == 4 and not (self.missionHelper[4] ~= nil and self.missionHelper[4].active) then
        return nil
    end
    if aktion ~= nil then
        self.letzteFeldWahl = { fieldId = fieldId, grund = grund, info = info }
    end
    return aktion
end

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
    pcall(function()
        if g_currentMission.terrainSize ~= nil then
            halfSize = g_currentMission.terrainSize * 0.34
        end
    end)

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
        pcall(StoreItemUtil.loadSpecsFromXML, item)
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
    pcall(function()
        if item.specs ~= nil and item.specs.weight ~= nil
           and Vehicle ~= nil and Vehicle.getSpecValueWeight ~= nil then
            t = Vehicle.getSpecValueWeight(item, nil, nil, nil, true, false)
        end
    end)
    t = tonumber(t)
    return (t ~= nil and t > 0) and (t * 1000) or nil
end

-- Motorleistung laut Shop (specs.power, Motorized.lua:97/3747), nil wenn unbekannt.
local function nfGetItemPower(item)
    nfLoadSpecs(item)
    local p = nil
    pcall(function()
        if item.specs ~= nil then p = tonumber(item.specs.power) end
    end)
    return (type(p) == "number" and p > 0) and p or nil
end

-- Leistungsbedarf eines Geraets (specs.neededPower.base, PowerConsumer.lua:502/538).
-- Gleiche Einheit wie specs.power - beides steht so in den Store-Daten.
local function nfGetItemNeededPower(item)
    nfLoadSpecs(item)
    local p = nil
    pcall(function()
        local np = item.specs ~= nil and item.specs.neededPower or nil
        if type(np) == "table" then p = tonumber(np.base) else p = tonumber(np) end
    end)
    return (type(p) == "number" and p > 0) and p or nil
end

-- Nutzlast aus StoreItem-Specs (in Litern, nil wenn nicht verfügbar).
local function nfGetItemCapacity(item)
    local cap = nil
    pcall(function()
        if item.specs ~= nil then
            cap = tonumber(item.specs.maxCapacity) or tonumber(item.specs.capacity)
        end
    end)
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
-- Auch innerhalb der leichten Kategorien gibt es Brocken: ein 8-m-Schwader
-- zaehlt als RAKES, ist aber breiter als der halbe Feldweg. Die Arbeitsbreite
-- steht nicht in den StoreItem-Specs (nur item.specs.weight ist dort belegt),
-- deshalb dient das Leergewicht als Ersatzmass.
local NF_ENG_MAX_IMPL_WEIGHT_KG = 3000

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
    pcall(function() allItems = g_storeManager:getItems() end)

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

    for _, item in pairs(allItems) do
        if item ~= nil and item.xmlFilename ~= nil
           and activeCats[item.categoryName] == true
           and not nfIsWaterVehicle(item.xmlFilename)
           and not (self.trafficVehicleBlacklist and self.trafficVehicleBlacklist[item.xmlFilename]) then
            local w = nfGetItemWeight(item)
            -- Build 105: unbekanntes Gewicht wird nicht mehr durchgewunken.
            if w ~= nil and w <= maxGewicht then
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
        " (%d ohne lesbares Gewicht)", #self.trafficVehicleList,
        NF_KLEIN_MAX_VEH_WEIGHT_KG / 1000, #ohneGewicht))
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
    return true
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
    pcall(function() allItems = g_storeManager:getItems() end)

    local eng = (self.engeMap ~= false)

    for _, item in pairs(allItems) do
        -- Build 105: erst die Kategorie pruefen, dann Werte laden - das Laden
        -- liest pro Artikel eine XML-Datei.
        if item ~= nil and item.xmlFilename ~= nil and lightCats[item.categoryName]
           and not nfIsWaterVehicle(item.xmlFilename) then
            local w   = nfGetItemWeight(item)
            local cap = nfGetItemCapacity(item)
            if (cap == nil or cap == 0) and w ~= nil and w <= NF_ENG_MAX_IMPL_WEIGHT_KG then
                table.insert(self.trafficImplListLight, {
                    filename  = item.xmlFilename,
                    gewichtKg = w,
                    bedarf    = nfGetItemNeededPower(item),
                })
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
-- Fruchtfolge-Saatwahl (Build 68)
-- Statt Zufallsfrucht (mit Gras-Risiko wie bei der Konkurrenz)
-- waehlt der Saeh-Helfer fruchtfolge-plausibel: Vorfrucht des
-- Feldes merken (fieldLastFruit, im Savegame persistiert) und
-- die Saatgutliste der Maschine danach bewerten. Gras und
-- Zwischenfruechte nur als letzte Wahl.
-- ============================================================

-- Fruchtfolge-Familien (Namen aus FruitTypeDesc.name, map-uebliche Namen
-- abgedeckt; unbekannte Fruechte zaehlen als eigene Familie "OTHER")
local NF_FRUIT_CATEGORY = {
    -- Getreide
    WHEAT = "CEREAL", WINTERWHEAT = "CEREAL", BARLEY = "CEREAL", OAT = "CEREAL",
    RYE = "CEREAL", TRITICALE = "CEREAL", SPELT = "CEREAL", SORGHUM = "CEREAL",
    RICE = "CEREAL", RICELONGGRAIN = "CEREAL",
    -- Mais (eigene Familie: Getreide->Mais gilt als echter Wechsel)
    MAIZE = "MAIZE",
    -- Oelfruechte
    CANOLA = "OILSEED", SUNFLOWER = "OILSEED",
    -- Leguminosen
    SOYBEAN = "LEGUME", PEA = "LEGUME", GREENBEAN = "LEGUME",
    CHICKPEA = "LEGUME", LENTIL = "LEGUME",
    -- Hack-/Wurzelfruechte und Gemuese
    POTATO = "ROOT", SUGARBEET = "ROOT", BEETROOT = "ROOT", CARROT = "ROOT",
    PARSNIP = "ROOT", ONION = "ROOT", SPINACH = "ROOT", CABBAGE = "ROOT",
    REDCABBAGE = "ROOT",
    -- Gras & Zwischenfruechte: fuer KI-Nachbarn unattraktiv (Anti-Gras-Bias)
    GRASS = "GRASS", MEADOW = "GRASS", OILSEEDRADISH = "GRASS",
}

-- Bewertung einer Saat-Kandidatin gegen die Vorfrucht.
-- Hoeherer Score = bessere Wahl. Basis 10, Abzuege/Boni:
--   Gras/Zwischenfrucht -8 (nur waehlen wenn sonst nichts geht)
--   gleiche Frucht wie Vorfrucht -4 (Monokultur vermeiden)
--   gleiche Familie -1 | echter Familienwechsel +3
--   Leguminose nach Getreide/Mais +1 (klassische Fruchtfolge)
function NachbarFelderManager:scoreSeedChoice(fruitName, prevFruitName)
    local score = 10
    local cat = NF_FRUIT_CATEGORY[fruitName or "?"] or "OTHER"
    if cat == "GRASS" then
        score = score - 8
    end
    if prevFruitName ~= nil then
        local prevCat = NF_FRUIT_CATEGORY[prevFruitName] or "OTHER"
        if fruitName == prevFruitName then
            score = score - 4
        elseif cat == prevCat then
            score = score - 1
        else
            score = score + 3
        end
        if cat == "LEGUME" and (prevCat == "CEREAL" or prevCat == "MAIZE") then
            score = score + 1
        end
    end
    return score
end

-- Beste pflanzbare Frucht fuer die Saemaschine waehlen.
-- Ersetzt die alte Zufallsschleife (inkl. des hartcodierten Index-25-
-- Ausschlusses - der ist jetzt der GRASS-Malus per Namens-Check).
-- Bei mehreren gleich guten Kandidaten entscheidet der Zufall (Vielfalt).
function NachbarFelderManager:chooseBestSeed(veh, fieldId)
    local spec  = veh.spec_sowingMachine
    local seeds = spec ~= nil and spec.seeds or nil
    if seeds == nil or #seeds == 0 then return end

    local prevFruit = self.fieldLastFruit ~= nil and self.fieldLastFruit[fieldId] or nil
    local best, bestScore = {}, nil
    for idx = 1, #seeds do
        local fruitDesc = g_fruitTypeManager:getFruitTypeByIndex(seeds[idx])
        if fruitDesc ~= nil then
            local plantable = false
            pcall(function()
                plantable = fruitDesc:getIsPlantableInPeriod(
                    g_currentMission.missionInfo.growthMode,
                    g_currentMission.environment.currentPeriod)
            end)
            if plantable then
                local sc = self:scoreSeedChoice(fruitDesc.name, prevFruit)
                if bestScore == nil or sc > bestScore then
                    bestScore = sc
                    best = { idx }
                elseif sc == bestScore then
                    table.insert(best, idx)
                end
            end
        end
    end

    if bestScore == nil then
        -- Nichts pflanzbar (sollte isFieldUseful nie durchlassen):
        -- Zufall wie frueher, damit der Ablauf nicht haengt.
        veh:changeSeedIndex(math.random(1, #seeds))
        return
    end

    local chosenIdx = best[math.random(#best)]
    veh:changeSeedIndex(chosenIdx)
    local fd = g_fruitTypeManager:getFruitTypeByIndex(seeds[spec.currentSeed or chosenIdx])
    print("NachbarFelder: [SAAT] Feld " .. tostring(fieldId) ..
        ": Vorfrucht=" .. tostring(prevFruit or "unbekannt") ..
        " -> gesaet=" .. tostring(fd ~= nil and fd.name or "?") ..
        " (Score " .. tostring(bestScore) .. ", " ..
        tostring(#best) .. " Kandidat(en))")
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

    pcall(function()
        if veh.getLastSpeed ~= nil then
            add(string.format("%.1f km/h", veh:getLastSpeed()))
        end
    end)
    pcall(function()
        if veh.getIsMotorStarted ~= nil then
            add("Motor " .. (veh:getIsMotorStarted() and "an" or "AUS"))
        end
    end)
    pcall(function()
        if veh.getIsAIReadyToDrive ~= nil then
            add("fahrbereit " .. tostring(veh:getIsAIReadyToDrive()))
        end
        if veh.getIsAIPreparingToDrive ~= nil then
            add("bereitet vor " .. tostring(veh:getIsAIPreparingToDrive()))
        end
    end)
    pcall(function()
        local spec = veh.spec_aiDrivable
        if spec ~= nil then
            add("Agent " .. (spec.agentId ~= nil and "ja" or "NEIN"))
            if spec.agentInfo ~= nil then
                add("AgentInfo " .. tostring(spec.agentInfo.isValid))
            end
        end
    end)
    pcall(function()
        if veh.getCanStartAIVehicle ~= nil then
            add("startbar " .. tostring(veh:getCanStartAIVehicle()))
        end
    end)
    pcall(function()
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
    end)
    pcall(function()
        if veh.getDamageAmount ~= nil then
            add(string.format("Schaden %.0f%%", (veh:getDamageAmount() or 0) * 100))
        end
    end)
    pcall(function()
        local job = veh.getJob ~= nil and veh:getJob() or nil
        add("Job " .. (job ~= nil and tostring(ClassUtil.getClassNameByObject(job)) or "keiner"))
    end)

    return table.concat(t, " | ")
end

function NachbarFelderManager:getEffectiveTrafficLimit()
    local limit = self.trafficLimit or 4
    if self.dayRhythm == false then return limit end
    local hour = 12
    pcall(function()
        if g_currentMission ~= nil and g_currentMission.environment ~= nil
           and g_currentMission.environment.currentHour ~= nil then
            hour = g_currentMission.environment.currentHour
        end
    end)
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
    local ok = pcall(function()
        g_currentMission:teleportVehicle(veh, rx, rz, rry or 0)
    end)
    if ok then
        print(string.format("NachbarFelder: [TRAFFIC] steckte fest - %.0f m weiter auf die KI-Strasse gesetzt",
            rdist or 0))
    end
    return ok
end

--- Naechstes Fahrzeug zu (x, z), das nicht zum eigenen Gespann gehoert (Build 107).
--- @return number|nil Abstand in m, string|nil Dateiname des Fahrzeugs
function NachbarFelderManager:getNaechstesFremdfahrzeug(x, z, eigenes)
    local bestD, bestName = nil, nil
    pcall(function()
        local list = (g_currentMission.vehicleSystem ~= nil and g_currentMission.vehicleSystem.vehicles)
                     or g_currentMission.vehicles
        for _, v in pairs(list or {}) do
            if v ~= nil and v ~= eigenes and v.isDeleted ~= true
               and v.rootNode ~= nil and v.rootNode ~= 0 then
                local root = v
                if v.getRootVehicle ~= nil then
                    local ok, r = pcall(function() return v:getRootVehicle() end)
                    if ok and r ~= nil then root = r end
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
    end)
    return bestD, bestName
end

function NachbarFelderManager:isSpotBlockedByAnyVehicle(x, z, radius, excludeVeh)
    if x == nil or z == nil then return false end
    local blocked = false
    pcall(function()
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
                        local ok2, root = pcall(function() return veh:getRootVehicle() end)
                        if ok2 and root == excludeVeh then isOwn = true end
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
    end)
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
    end

    -- Build 103: nicht zu mehreren am selben Fleck einschlafen. Am 12.09.
    -- standen vier Fahrzeuge in Reihe an derselben Sackgasse: jedes strandete
    -- dort, schlief an Ort und Stelle ein (Build 93) und wurde beim Aufwecken
    -- sofort wieder abgewiesen. Ist der Platz belegt, kommt das Fahrzeug
    -- vorher auf einen freien Strassenpunkt 25-150 m weiter.
    pcall(function()
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
    end)

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
    pcall(function()
        local x, _, z = getWorldTranslation(tractor.rootNode)
        restX, restZ = x, z
    end)
    if restX == nil then return false end

    -- Motor aus: schlafende Fahrzeuge stehen still am Strassenrand
    pcall(function()
        if tractor.stopMotor ~= nil and tractor.getIsMotorStarted ~= nil
           and tractor:getIsMotorStarted() then
            tractor:stopMotor()
        end
    end)

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
    pcall(function()
        local x, _, z = getWorldTranslation(tractor.rootNode)
        sx, sz = x, z
    end)
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
        vehInfo = { filename = forcedVehicleXML, category = "" }
        for _, v in ipairs(self.trafficVehicleList) do
            if v.filename == forcedVehicleXML then vehInfo = v; break end
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
        (trailerAdded and " + Anbaugeraet" or "") ..
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

function NachbarFelderManager:generateWorkMission(manuell)
    -- Nur auf Server ausführen
    if not g_currentMission:getIsServer() then
        print("NachbarFelder: generateWorkMission ignoriert (kein Server)")
        return false
    end

    -- "Anzahl Arbeiter" (Settings): begrenzt Feldarbeits-Helfer.
    -- Patrol-/Verkehrsfahrzeuge zaehlen hier NICHT (eigenes trafficLimit).
    local fieldWorkers = 0
    for _, k in pairs(self.vehicleType) do
        local w = k.NachbarFelderWorker
        if w ~= nil and not w.isPatrol and w.status ~= 100 and w.status ~= 9999 then
            fieldWorkers = fieldWorkers + 1
        end
    end
    if fieldWorkers >= (self.MAX_ASSISTANT_WORKERS or 12) then
        print("NachbarFelder: Max. Arbeiter erreicht (" .. tostring(fieldWorkers) ..
            "/" .. tostring(self.MAX_ASSISTANT_WORKERS) .. ") - kein neuer Feldarbeits-Helfer")
        return false
    end

    -- Build 132: Spawnpunkte vorhanden, aber alle belegt -> diesen Takt auslassen
    if self:getHatSpawnpunkte() and self:waehleSpawnpunkt(true) == nil then
        return false
    end

    print("NF: generateWorkMission")
    self.counter = self.counter + 1

    if #self.loadVehiclesFromXML > 0 then
        local eintrag = self.loadVehiclesFromXML[1]
        local created, verworfen
        local feldDa = false
        pcall(function()
            feldDa = eintrag.fieldId ~= nil and g_fieldManager:getFieldById(eintrag.fieldId) ~= nil
        end)
        if not feldDa then
            -- Build 139: Nummer trifft kein Feld (alter Spielstand, andere Karte) -> verwerfen
            print("NachbarFelder: Gespeicherter Auftrag verworfen - Feld " .. tostring(eintrag.fieldId) ..
                " gibt es auf dieser Karte nicht")
            created, verworfen = false, true
        elseif eintrag.auftrag and NachbarFelderAuftrag ~= nil then
            -- Build 139: Auftrag eines Spielers - eigenes Feld ist erlaubt,
            -- isFieldUseful wuerde es als "gehoert einer Farm" verwerfen
            created, verworfen = NachbarFelderAuftrag.starteGespeichert(self, eintrag)
        else
            created, verworfen = self:startSavedMission(eintrag.fieldId, eintrag.missionType)
        end
        -- Build 126: auch verworfene Auftraege entfernen, sonst Endlosschleife
        if created or verworfen then table.remove(self.loadVehiclesFromXML, 1) end
        return created
    end

    -- Build 139: zufaelliger Eintrag der echten Feldliste und dessen Nummer
    -- (getFeldNummer). Frueher math.random(1, #getFields()) - ein Listenplatz:
    -- Felder mit hoeherer Nummer als die Anzahl der Felder kamen nie dran,
    -- Nummern ohne Feld waren Fehlversuche.
    local feldNummern = self:getFeldNummern()
    if #feldNummern == 0 then
        print("NachbarFelder: keine Felder auf der Karte gefunden")
        return false
    end
    local randomFieldId = feldNummern[math.random(#feldNummern)]
    local actionOnField = self:isFieldUseful(randomFieldId)
    local missionHelper
    if actionOnField ~= nil then
        missionHelper = self.missionHelper[actionOnField]
        if missionHelper == nil or not missionHelper.active then actionOnField = nil end
    end

    local count = math.max(50, #feldNummern * 3)
    while actionOnField == nil do
        if count <= 0 then
            print("NF: no useful field found")
            self:logFeldStatistik(manuell)
            return false
        end
        randomFieldId = feldNummern[math.random(#feldNummern)]
        actionOnField = self:isFieldUseful(randomFieldId)
        if actionOnField ~= nil then
            missionHelper = self.missionHelper[actionOnField]
            if missionHelper == nil or not missionHelper.active then actionOnField = nil end
        end
        count = count - 1
    end
    if actionOnField == nil then
        print("NF: no action on field")
        return false
    end

    -- Build 111: Grund der Feldwahl ins Log
    local fw = self.letzteFeldWahl
    local bodenName = "?"
    pcall(function()
        local fsx = g_fieldManager:getFieldById(randomFieldId):getFieldState()
        bodenName = self:getBodenName(fsx.groundType)
    end)
    local fwGrund, fwInfo = "?", ""
    if fw ~= nil and fw.fieldId == randomFieldId then
        fwGrund, fwInfo = tostring(fw.grund), tostring(fw.info or "")
    end
    print(string.format("NachbarFelder: Feld %d gewaehlt fuer %s - Grund: %s, Boden Mitte %s | %s",
        randomFieldId, tostring(self.missionHelper[actionOnField] and self.missionHelper[actionOnField].name),
        fwGrund, bodenName, fwInfo))
    return self:createMission(randomFieldId, self.missionHelper[actionOnField])
end

--- Name eines Bodentyps fuer das Log (Build 111). FieldGroundType ist in der
--- Engine definiert, die Zuordnung Zahl -> Name steht in keiner Datei.
function NachbarFelderManager:getBodenName(gt)
    if gt == nil then return "?" end
    local name = nil
    pcall(function()
        for k, v in pairs(FieldGroundType or {}) do
            if v == gt and type(k) == "string" and k == string.upper(k) then
                name = k
                break
            end
        end
    end)
    return name ~= nil and (name .. "(" .. tostring(gt) .. ")") or tostring(gt)
end

--- Fruchtzustand an einem Messpunkt (Build 111):
--- "leer", "abgeerntet", "verdorrt", "erntereif" oder "waechst".
--- Nutzt die in FruitTypeDesc.lua sichtbaren Felder (cutStates/cutState :306-308,
--- witheredState :315, min/maxHarvestingGrowthState :291-295) statt der im
--- Spielcode nicht einsehbaren getIsCut/getIsWithered.
function NachbarFelderManager:getFruchtZustand(fs)
    if fs == nil or fs.fruitTypeIndex == nil or fs.fruitTypeIndex == FruitType.UNKNOWN then
        return "leer"
    end
    local fruit = g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex)
    local gs = fs.growthState or 0
    if fruit == nil or gs == 0 then return "leer" end
    if (fruit.cutStates ~= nil and fruit.cutStates[gs]) or gs == fruit.cutState then
        return "abgeerntet"
    end
    if fruit.witheredState ~= nil and gs == fruit.witheredState then
        return "verdorrt"
    end
    if (fruit.minHarvestingGrowthState or 0) > 0 and gs >= fruit.minHarvestingGrowthState
       and gs <= (fruit.maxHarvestingGrowthState or fruit.minHarvestingGrowthState) then
        return "erntereif"
    end
    return "waechst"
end

--- Was soll auf diesem fremden Feld passieren? (Build 111, verschaerft in Build 112)
--- @return integer|nil 3 = pfluegen, 4 = grubbern, nil = nichts
--- @return string Grund ("abgeerntet", "verdorrt", "stoppel", "frucht", "bearbeitet", "unklar", "ungueltig")
--- @return string Messwerte fuers Log
--- @return string|nil Frucht und Zustand am Messpunkt mit Frucht, z.B. "GRASS waechst" (Build 139)
---
--- Build 111 entschied nach einem einzelnen "abgeerntet"-Punkt. Am 13.09. 13:54
--- wurden so Feld 69 (Boden Mitte HARVEST_READY) und Feld 64 (Boden Mitte SOWN)
--- gewaehlt. Feld 64 war laut User aber WIRKLICH abgeerntet - der Bodentyp bleibt
--- nach der Ernte auf dem Wert der Aussaat stehen. Der Bodentyp kann erntereif
--- und abgeerntet also NICHT unterscheiden, nur die Frucht selbst. Deshalb:
---   * Mitte + 16 Punkte auf zwei Ringen (zweiter um 22,5 Grad versetzt; eine
---     Fahrgasse ohne Frucht trifft so nicht alle Punkte - Feld 53),
---   * JEDER Punkt mit wachsender oder erntereifer Frucht macht das Feld tabu,
---   * freigegeben wird nur, wenn mindestens die HAELFTE der gueltigen Punkte
---     abgeerntet/verdorrt ist oder leer mit Stoppelboden (mindestens 3 Punkte);
---     ein einzelner abgeernteter Punkt auf einer Nachbarflaeche reicht nicht,
---   * "leer auf Frucht-Bodentyp" (Fahrgasse u. ae.) zaehlt weder dafuer noch
---     dagegen und steht nur im Log.
---
--- Build 139: Die Ringpunkte zaehlen nur, wenn sie im Feldumriss liegen und
--- mindestens MESSPUNKT_RANDABSTAND vom Rand entfernt sind. Vorher genuegte
--- "gleiches Farmland" - bei langen, schmalen oder verwinkelten Feldern lagen
--- Punkte auf Wiesen-/Grasstreifen neben dem Feld, Gras zaehlt als wachsende
--- Frucht -> Feld galt faelschlich als "Frucht steht" (Auftrag Feld 54).
function NachbarFelderManager:getFeldAktion(field)
    local fs = field ~= nil and field:getFieldState() or nil
    if fs == nil or not fs.isValid then return nil, "ungueltig", "" end

    if self.fruchtBoeden == nil then
        self.fruchtBoeden = {}
        local bodenNamen = { "SOWN", "DIRECT_SOWN", "PLANTED", "HARVEST_READY",
                             "HARVEST_READY_OTHER", "GRASS", "GRASS_CUT", "ROLLER_LINES" }
        for _, name in ipairs(bodenNamen) do
            local v = FieldGroundType ~= nil and FieldGroundType[name] or nil
            if v ~= nil then
                self.fruchtBoeden[v] = true
            end
        end
    end

    local punkte = {}   -- je Punkt: { Fruchtzustand, Bodentyp, Fruchtname }
    local function hatFrucht(pt)
        return pt[1] == "waechst" or pt[1] == "erntereif"
    end
    -- Name der Frucht an einem Messpunkt (fuers Log und die Auftrags-Meldung)
    local function fruchtName(state)
        local name = "?"
        pcall(function()
            local ft = g_fruitTypeManager:getFruitTypeByIndex(state.fruitTypeIndex)
            if ft ~= nil and ft.name ~= nil then
                name = ft.name
            end
        end)
        return name
    end

    punkte[1] = { self:getFruchtZustand(fs), fs.groundType, fruchtName(fs) }
    if hatFrucht(punkte[1]) then
        return nil, "frucht", "Mitte " .. punkte[1][1] .. "/" .. self:getBodenName(punkte[1][2]) ..
            " (" .. punkte[1][3] .. ")", punkte[1][3] .. " " .. punkte[1][1]
    end

    -- Build 139: Feldumriss fuer die Ringpunkte (nil = kein Umriss -> wie bisher nur Farmland)
    local poly = self:getFeldPolygon(field)
    local randMin = NachbarFelderManager.MESSPUNKT_RANDABSTAND
    local ausserhalb = 0

    local fruchtPunkt = nil
    pcall(function()
        if FieldState == nil or FieldState.new == nil or field.posX == nil then return end
        local seite = math.sqrt(math.max(field.areaHa or 0.3, 0.1) * 10000)
        local farmlandId = field.farmland ~= nil and field.farmland.id or nil
        for ring, anteil in ipairs({ 0.2, 0.42 }) do
            local r = seite * anteil
            for n = 0, 7 do
                local a = (n + (ring - 1) * 0.5) * math.pi / 4
                local px, pz = field.posX + math.cos(a) * r, field.posZ + math.sin(a) * r
                local imFeld = poly == nil or (nfPunktInPolygon(px, pz, poly) and nfRandAbstand(px, pz, poly) >= randMin)
                if not imFeld then
                    ausserhalb = ausserhalb + 1
                end
                local probe = FieldState.new()
                if imFeld then
                    probe:update(px, pz)
                end
                if imFeld and probe.isValid and (farmlandId == nil or probe.farmlandId == farmlandId) then
                    local pt = { self:getFruchtZustand(probe), probe.groundType, fruchtName(probe) }
                    punkte[#punkte + 1] = pt
                    if hatFrucht(pt) then
                        fruchtPunkt = pt
                        return
                    end
                end
            end
        end
    end)

    local nAbgeerntet, nVerdorrt, nStoppel, nLeerFruchtboden = 0, 0, 0, 0
    local stoppelTyp = FieldGroundType ~= nil and FieldGroundType.STUBBLE_TILLAGE or nil
    for _, pt in ipairs(punkte) do
        if pt[1] == "abgeerntet" then
            nAbgeerntet = nAbgeerntet + 1
        elseif pt[1] == "verdorrt" then
            nVerdorrt = nVerdorrt + 1
        elseif stoppelTyp ~= nil and pt[2] == stoppelTyp then
            nStoppel = nStoppel + 1
        elseif pt[2] ~= nil and self.fruchtBoeden[pt[2]] then
            nLeerFruchtboden = nLeerFruchtboden + 1   -- Fahrgasse o. ae.: nur Info
        end
    end
    local info = string.format("%d Messpunkte: abgeerntet %d, verdorrt %d, Stoppel %d, leer auf Fruchtboden %d" ..
        " (%d ausserhalb des Feldumrisses verworfen)",
        #punkte, nAbgeerntet, nVerdorrt, nStoppel, nLeerFruchtboden, ausserhalb)

    if fruchtPunkt ~= nil then
        return nil, "frucht", info .. ", Frucht an Messpunkt (" .. fruchtPunkt[1] .. "/" ..
            self:getBodenName(fruchtPunkt[2]) .. ", " .. fruchtPunkt[3] .. ")", fruchtPunkt[3] .. " " .. fruchtPunkt[1]
    end
    if #punkte < 3 then
        return nil, "unklar", info
    end
    if (nAbgeerntet + nVerdorrt + nStoppel) * 2 < #punkte then
        return nil, "bearbeitet", info
    end

    local grund
    if nAbgeerntet > 0 and nAbgeerntet >= nVerdorrt and nAbgeerntet >= nStoppel then
        grund = "abgeerntet"
    elseif nVerdorrt > 0 and nVerdorrt >= nStoppel then
        grund = "verdorrt"
    else
        grund = "stoppel"
    end

    if grund ~= "stoppel" then
        local maxPlow = nil
        pcall(function()
            maxPlow = g_currentMission.fieldGroundSystem:getMaxValue(FieldDensityMap.PLOW_LEVEL)
        end)
        if maxPlow ~= nil and (fs.plowLevel or 0) < maxPlow then
            return 3, grund, info
        end
    end
    return 4, grund, info
end

--- Laeuft dieser Vertrag gerade, oder wird er nur angeboten? (Build 109)
---
--- g_missionManager.missions enthaelt auch die nur ANGEBOTENEN Vertraege
--- (MissionStatus.CREATED, MissionManager.lua:327). Bisher sperrte jeder davon
--- sein Feld - nach der Ernte bietet das Spiel aber gerade auf den abgeernteten
--- Feldern Pflug- und Grubbervertraege an (Statistik 13.09.: 19-21 Felder "mit
--- Vertrag"). Gesperrt wird jetzt nur, was ein Spieler angenommen hat:
--- AbstractMission:getIsInProgress() = PREPARING oder RUNNING (AbstractMission.lua:790).
function NachbarFelderManager:getIstVertragAktiv(mission)
    if mission == nil then return false end
    local aktiv = true
    pcall(function()
        if mission.getIsInProgress ~= nil then
            aktiv = mission:getIsInProgress() == true
        elseif MissionStatus ~= nil and mission.status ~= nil then
            aktiv = mission.status == MissionStatus.PREPARING or mission.status == MissionStatus.RUNNING
        end
    end)
    return aktiv
end

--- Position und Name des Zugfahrzeugs eines Workers (Build 109).
function NachbarFelderManager:getWorkerPos(w)
    local veh = w ~= nil and w.vehiclesToLoad ~= nil and w.vehiclesToLoad[1] or nil
    if veh == nil or veh.rootNode == nil then return nil, nil end
    local x, z = nil, nil
    pcall(function()
        local vx, _, vz = getWorldTranslation(veh.rootNode)
        x, z = vx, vz
    end)
    return x, z
end

function NachbarFelderManager:getWorkerName(w)
    local veh = w ~= nil and w.vehiclesToLoad ~= nil and w.vehiclesToLoad[1] or nil
    local f = veh ~= nil and veh.configFileName or ""
    return string.match(f, "[^/\\]+$") or "?"
end

--- Warum findet die Feldarbeit nichts? (Build 106)
--- Zaehlt alle Felder nach dem ersten Grund, aus dem sie ausscheiden - in
--- derselben Reihenfolge wie isFieldUseful. Hoechstens alle 30 Minuten.
function NachbarFelderManager:logFeldStatistik(sofort)
    -- Build 109: bei manueller Suche (Shift+Alt+N / Konsole) immer ausgeben
    if not sofort and self.feldStatistikAt ~= nil
       and g_time - self.feldStatistikAt < 30 * 60 * 1000 then
        return
    end
    self.feldStatistikAt = g_time

    local z = { gesamt = 0, belegt = 0, besitzer = 0, vertrag = 0, bebaut = 0, weide = 0,
                klein = 0, gruenland = 0, ungueltig = 0, waechst = 0, bearbeitet = 0,
                geeignet = 0, verdorrt = 0, angeboten = 0 }
    local bebaut = self:getBebauteFelder() or {}
    local vertragsFlaechen = {}
    pcall(function()
        for _, m in ipairs(g_missionManager.missions or {}) do
            if type(m.getField) == "function" then
                local mf = m:getField()
                if mf ~= nil and mf.farmland ~= nil then
                    -- Build 109: true = Vertrag laeuft, false = nur angeboten
                    if self:getIstVertragAktiv(m) then
                        vertragsFlaechen[mf.farmland] = true
                    elseif vertragsFlaechen[mf.farmland] == nil then
                        vertragsFlaechen[mf.farmland] = false
                    end
                end
            end
        end
    end)
    local maxPlow = nil
    pcall(function()
        maxPlow = g_currentMission.fieldGroundSystem:getMaxValue(FieldDensityMap.PLOW_LEVEL)
    end)

    for id, field in pairs(g_fieldManager:getFields() or {}) do
        z.gesamt = z.gesamt + 1
        pcall(function()
            local fid = self:getFeldNummer(field, id)   -- Build 139: nicht der Listenplatz
            if self.vehicleType[fid] ~= nil
               or (self.feldSperre ~= nil and self.feldSperre[fid])
               or ((self.fieldCooldown[fid] or 0) > 0) then
                z.belegt = z.belegt + 1; return
            end
            if field.farmland == nil or field.farmland.isOwned then z.besitzer = z.besitzer + 1; return end
            if vertragsFlaechen[field.farmland] == true then z.vertrag = z.vertrag + 1; return end
            if vertragsFlaechen[field.farmland] == false then z.angeboten = z.angeboten + 1 end
            if bebaut[field] ~= nil then z.bebaut = z.bebaut + 1; return end
            if self:isPunktInWeide(field.posX, field.posZ) then z.weide = z.weide + 1; return end
            if field.areaHa ~= nil and field.areaHa < 0.3 then z.klein = z.klein + 1; return end
            local fs = field:getFieldState()
            -- Build 107: Gruenland getrennt zaehlen - am 13.09. waren 42 von 95
            -- Feldern "ungueltig", ohne dass zu sehen war, warum.
            if field.grassMissionOnly then z.gruenland = z.gruenland + 1; return end
            if fs == nil or not fs.isValid then
                z.ungueltig = z.ungueltig + 1; return
            end
            -- Build 111: dieselbe Entscheidung wie die Feldwahl
            local aktion, grund = self:getFeldAktion(field)
            if aktion ~= nil then
                z.geeignet = z.geeignet + 1
                if grund == "verdorrt" then z.verdorrt = z.verdorrt + 1 end
            elseif grund == "frucht" or grund == "waechst" or grund == "erntereif" then
                z.waechst = z.waechst + 1
            else
                z.bearbeitet = z.bearbeitet + 1
            end
        end)
    end

    print(string.format("NachbarFelder: Feldarbeit-Statistik - %d Felder: %d belegt/gesperrt," ..
        " %d gehoeren einer Farm, %d mit laufendem Vertrag, %d bebaut, %d Weide, %d unter 0,3 ha," ..
        " %d Gruenland, %d Zustand ungueltig, %d mit stehender Frucht, %d schon bearbeitet/kein Stoppel," ..
        " %d geeignet (davon %d verdorrt) - Vertrag nur angeboten (zaehlt mit): %d",
        z.gesamt, z.belegt, z.besitzer, z.vertrag, z.bebaut, z.weide, z.klein,
        z.gruenland, z.ungueltig, z.waechst, z.bearbeitet, z.geeignet, z.verdorrt, z.angeboten))
end

function NachbarFelderManager:startSavedMission(fieldId, missionHelperName)
    -- Build 126: gespeicherte Auftraege muessen dieselbe Pruefung bestehen wie die
    -- Feldsuche (Frucht, Vertrag, Besitzer, Weide ...). Server 14.09.: Feld 72 mit
    -- Karotten (Wachstum 7, HARVEST_READY_OTHER) wurde aus einem alten Auftrag gepfluegt.
    -- Die Arbeitsart kommt aus der aktuellen Pruefung, nicht aus dem Spielstand.
    local aktion = self:isFieldUseful(fieldId)
    if aktion == nil or self.missionHelper[aktion] == nil or not self.missionHelper[aktion].active then
        print("NachbarFelder: Gespeicherter Auftrag " .. tostring(missionHelperName) .. " auf Feld " ..
            tostring(fieldId) .. " verworfen - Feld ist nicht (mehr) geeignet")
        return false, true
    end
    return self:createMission(fieldId, self.missionHelper[aktion]), false
end

function NachbarFelderManager:createMission(fieldId, missionHelper)
    -- hoe/weed bleiben gesperrt (deaktivierte Missionstypen). harvest ist
    -- jetzt freigegeben - der Mähdrescher-Ablauf (Schneidwerk mounten,
    -- Korntank leeren) ist vollständig implementiert.
    -- herbicide vorerst deaktiviert: macht mit Precision Farming nur Spot-Spray
    -- (einzelne Unkrautflecken statt Flaeche) → unschoene ~30s-Kurzeinsaetze.
    -- Pfluegen/Saeen/Duengen/Ernten/Grubbern laufen sauber.
    -- Build 125: nur noch Pfluegen und Grubbern - auch gespeicherte Auftraege aelterer
    -- Builds (Saeen, Duengen, Ernten ...) werden nicht mehr gestartet.
    if missionHelper == nil or
       NachbarFelderManager.FELD_GERAETE_KATEGORIEN[missionHelper.name] == nil or
       missionHelper.name == "hoeMission" or missionHelper.name == "weedMission" or
       missionHelper.name == "herbicideMission" then
        print("NachbarFelder: Auftrag wird uebersprungen " ..
            tostring(missionHelper ~= nil and missionHelper.name or "nil"))
        return false
    end

    -- Farm-ID sicherstellen: NIEMALS Spectator-Farm (0) verwenden!
    -- AI-Jobs mit farmId=0 werden von der Engine sofort abgewiesen.
    self:getEffectiveFarmId()
    print("NachbarFelder: Verwende Farm-ID " .. tostring(self.farmId) .. " fuer Feld " .. tostring(fieldId))

    local missionGame = g_currentMission
    local tx, tz = self:getShopPosition()   -- Build 94: Original-Shop

    for v, k in pairs(self.vehicleType) do
        -- Steckengebliebene oder bereits zu löschende Fahrzeuge nicht als Blocker zählen.
        -- ws=60 = rückkehrendes Fahrzeug: fährt vom Feld zum Shop → kein Blocker für neuen Spawn.
        local ws = k.NachbarFelderWorker and k.NachbarFelderWorker.status or 0
        if ws ~= 9999 and ws ~= 100 and ws ~= 60 then
            for _, veh in ipairs(k.vehicleType) do
                if self:getIsVehicleAlive(veh) then
                    local x, _, z = getWorldTranslation(veh.rootNode)
                    if MathUtil.vector2Length(x - tx, z - tz) < 50 then
                        print("NachbarFelder: Spawn blockiert durch Fahrzeug auf Feld " .. tostring(v) ..
                            " (Status=" .. tostring(ws) ..
                            " Pos=" .. tostring(math.floor(x)) .. "/" .. tostring(math.floor(z)) .. ")")
                        self.feldSpawnBlockiert = true   -- Build 110
                        return false
                    end
                end
            end
        end
    end

    print("Start Mission on Field " .. fieldId)
    local field = g_fieldManager:getFieldById(fieldId)

    -- Vorfrucht-Gedaechtnis (Build 68): steht (noch) eine Frucht auf dem
    -- Feld, jetzt merken - Grundlage fuer die Fruchtfolge-Wahl beim Saeen.
    pcall(function()
        local fs = field ~= nil and field:getFieldState() or nil
        local fruit = fs ~= nil and g_fruitTypeManager:getFruitTypeByIndex(fs.fruitTypeIndex) or nil
        if fruit ~= nil and fruit.name ~= nil then
            self.fieldLastFruit[fieldId] = fruit.name
        end
    end)

    local mission = missionHelper.class.new(true, g_client ~= nil)
    local missionType = g_missionManager.missionTypes[missionHelper.id]
    mission:setField(field)
    mission.type = missionType
    mission.vehiclesToLoad, mission.vehicleGroupIdentifier = self:getRandomVehicles(mission)
    if mission.vehiclesToLoad == nil or #mission.vehiclesToLoad == 0 then
        print("NF: no vehicles available for mission on field " .. fieldId)
        return false
    end

    if not mission:isSpawnSpaceAvailable() then
        print("NF: spawn space blocked for field " .. fieldId)
        self.feldSpawnBlockiert = true   -- Build 110
        return false
    end

    -- Zusaetzlich zur Engine-Pruefung: steht noch ein eigener Helfer am
    -- Haendler? Auf engen Karten ist das der haeufigere Fall - die Engine sieht
    -- den Platz als frei an, physisch steht dort aber noch das vorige Gespann.
    if self:istSpawnBereichBelegt() then
        print("NF: Spawn-Bereich noch belegt (Feld " .. fieldId ..
              ") - naechster Versuch spaeter")
        self.feldSpawnBlockiert = true   -- Build 110
        return false
    end

    self.vehicleType[fieldId] = {}
    self.vehicleType[fieldId].vehiclesToLoad = mission.vehiclesToLoad
    self.vehicleType[fieldId].saveVehicleToLoad = mission.vehiclesToLoad
    self.vehicleType[fieldId].mission = mission
    self.vehicleType[fieldId].status = 1
    self.vehicleType[fieldId].fieldId = fieldId
    self.vehicleType[fieldId].vehicleType = {}
    self.vehicleType[fieldId].NachbarFelderWorker = NachbarFelderWorker.new({}, mission, status, fieldId)
    self:loadVehicles(self.vehicleType[fieldId])
    self.countWorkers = self.countWorkers + 1
    return true
end

function NachbarFelderManager:getVariant(mission)
    if mission.type.name == "harvestMission" then
        local fruitTypeIndex = mission.field:getFieldState().fruitTypeIndex
        local fruit = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
        for k, v in pairs(self.vehicleHarvestVariant) do
            for _, b in ipairs(v) do
                if fruit.name == b then return k end
            end
        end
        return "GRAIN"
    end
    return mission:getVehicleVariant()
end

--- Ist ein Anbaugeraet starr (ohne Klappteile) und breiter als eine Fahrspur? (Build 113)
---
--- Build 112 klappt Geraete vor der Fahrt ein - das hilft nur Geraeten, die
--- klappen KOENNEN. Die Amazone Cenio 4000 hat keine foldingParts und ist
--- 4,05 m breit (vehicle.base.size#width, Vehicle.lua:367); ihre Transport-
--- stellung sieht aus wie ausgeklappt, und sie bleibt auf Dorfstrassen haengen.
--- Grenze 3,05 m: laesst 3-m-Geraete durch, sperrt Cenio 4000 (4,05),
--- ecoCultivator300 (3,2), Crossmax 300 (3,65), Kredo (3,15), K-Force 400 (4,0).
--- Ergebnis je Datei gecacht; nicht lesbare Dateien gelten als unkritisch.
NachbarFelderManager.STARR_MAX_BREITE = 3.05   -- Feld statt local: Hauptchunk hat viele locals

function NachbarFelderManager:getIstStarrUndBreit(filename)
    if filename == nil then return false end
    self.starrBreitCache = self.starrBreitCache or {}
    local c = self.starrBreitCache[filename]
    if c ~= nil then return c end
    local starrBreit, breite, klappt, agent = false, nil, nil, nil
    pcall(function()
        local xml = loadXMLFile("nfBreite", filename)
        if xml == nil or xml == 0 then return end
        breite = getXMLFloat(xml, "vehicle.base.size#width")
        klappt = hasXMLProperty(xml, "vehicle.foldable.foldingConfigurations.foldingConfiguration(0).foldingParts.foldingPart(0)")
              or hasXMLProperty(xml, "vehicle.foldable.foldingParts.foldingPart(0)")
        -- Build 123: Breite, mit der die KI-Wegsuche plant (bei klappbaren Geraeten
        -- die Transportbreite). JD Cultivator 980: foldingParts bewegen nur die Achse,
        -- agentAttachment width=4.45 - er klappt nicht.
        local aw = getXMLFloat(xml, "vehicle.ai.agentAttachment#width")
        if aw ~= nil then
            agent = aw
        elseif getXMLBool(xml, "vehicle.ai.agentAttachment#useSize") == true then
            agent = breite
        end
        delete(xml)
    end)
    if agent ~= nil then
        if agent > NachbarFelderManager.STARR_MAX_BREITE then
            starrBreit = true
            print(string.format("NachbarFelder: Anbaugeraet [%s] faehrt %.2f m breit (KI-Planungsbreite)" ..
                " - nicht fuer Feldhelfer", tostring(filename), agent))
        end
    elseif breite ~= nil and klappt == false and breite > NachbarFelderManager.STARR_MAX_BREITE then
        starrBreit = true
        print(string.format("NachbarFelder: Anbaugeraet [%s] ist starr und %.2f m breit - nicht fuer Feldhelfer",
            tostring(filename), breite))
    end
    self.starrBreitCache[filename] = starrBreit
    return starrBreit
end

--- Kupplungsarten eines Fahrzeugs aus seiner XML (Build 115).
--- eingang=false: attacherJoints des Traktors; fehlt jointType, gilt "implement"
---   (AttacherJoints.lua:128). Pfad auch in attacherJointConfigurations
---   (AttacherJoints.lua:4469), dort nur die erste Konfiguration.
--- eingang=true: inputAttacherJoints des Geraets (<attachable>, Attachable.lua:264).
--- @return table { [jointType] = true }, gecacht
function NachbarFelderManager:getXmlKupplungen(filename, eingang)
    self.kupplungCache = self.kupplungCache or {}
    local key = (eingang and "E|" or "A|") .. tostring(filename)
    if self.kupplungCache[key] ~= nil then return self.kupplungCache[key] end
    local typen = {}
    pcall(function()
        local xml = loadXMLFile("nfKupplung", filename)
        if xml == nil or xml == 0 then return end
        local basen
        if eingang then
            basen = { "vehicle.attachable.inputAttacherJoints.inputAttacherJoint",
                      "vehicle.attachable.inputAttacherJointConfigurations.inputAttacherJointConfiguration(0).inputAttacherJoints.inputAttacherJoint",
                      "vehicle.attachable.inputAttacherJointConfigurations.inputAttacherJointConfiguration(0).inputAttacherJoint" }
        else
            basen = { "vehicle.attacherJoints.attacherJoint",
                      "vehicle.attacherJoints.attacherJointConfigurations.attacherJointConfiguration(0).attacherJoint" }
        end
        for _, b in ipairs(basen) do
            for i = 0, 19 do
                local k = string.format("%s(%d)", b, i)
                if not hasXMLProperty(xml, k) then break end
                local jt = getXMLString(xml, k .. "#jointType")
                if jt == nil and not eingang then jt = "implement" end
                if jt ~= nil then typen[jt] = true end
            end
        end
        delete(xml)
    end)
    self.kupplungCache[key] = typen
    return typen
end

--- Passt ein Feldgeraet zum Kleintraktor? (Build 123)
--- Wie getPasstGeraetZuTraktor, aber der Leistungsbedarf darf bis 130 % der
--- Motorleistung betragen. Ohne Toleranz bleibt fuer Kleintraktoren bis 7 t kein
--- schmal klappbarer Grubber (Smaragd 180 PS, Prolander 190 PS, Ares XL 150 PS ...).
NachbarFelderManager.FELD_LEISTUNG_TOLERANZ = 1.05   -- Build 124: 1.3 war zu viel (Crystal 150 PS + Smaragd 180 PS kroch)

function NachbarFelderManager:getPasstFeldGeraetZuTraktor(traktor, geraet)
    if traktor == nil or geraet == nil then return false end
    local ps, bedarf = traktor.leistung, geraet.bedarf
    if ps ~= nil and bedarf ~= nil then
        if bedarf > ps * NachbarFelderManager.FELD_LEISTUNG_TOLERANZ then return false end
    elseif bedarf ~= nil then
        if bedarf > 80 then return false end
    elseif (geraet.gewichtKg or 0) > 1500 then
        return false
    end
    if traktor.gewichtKg ~= nil and geraet.gewichtKg ~= nil
       and geraet.gewichtKg > traktor.gewichtKg * 0.5 then
        return false
    end
    return true
end

--- Feldhelfer-Gespann (Traktor + Geraet) fuer die Session sperren (Build 120).
function NachbarFelderManager:sperreFeldGespann(traktorFile, geraetFile)
    if traktorFile == nil then return end
    self.feldGespannSperre = self.feldGespannSperre or {}
    self.feldGespannSperre[string.lower(tostring(traktorFile)) .. "|" .. string.lower(tostring(geraetFile or ""))] = true
end

function NachbarFelderManager:getIstFeldGespannGesperrt(traktorFile, geraetFile)
    if self.feldGespannSperre == nil or traktorFile == nil then return false end
    return self.feldGespannSperre[string.lower(tostring(traktorFile)) .. "|" .. string.lower(tostring(geraetFile or ""))] == true
end

NachbarFelderManager.FELD_MIN_ARBEITSBREITE = 2.0   -- Build 121, Meter

NachbarFelderManager.FELD_GERAETE_KATEGORIEN = {
    plowMission      = { PLOWS = true },
    cultivateMission = { CULTIVATORS = true, DISCHARROWS = true },
}

--- Eigenes Feldgespann: Kleintraktor + passendes Geraet (Build 115).
---
--- Die Vertragslisten des Spiels haben fuer Grubbern auch in "small" nur
--- schwere Zugmaschinen (Log 13.09. 14:55: T8000, Fastrac, Puma 7,3 t, MT655).
--- Wunsch des Users: keine mittleren/grossen Maschinen, Geraet passend zum
--- Traktor. Deshalb hier selbst kombinieren:
---   * Traktor aus der Verkehrsliste (TRACTORSS bis 7 t, buildTrafficVehicleList),
---   * Geraet aus dem Shop in der Kategorie des Auftrags, freigeschaltet, nicht
---     gesperrt, nicht starr-und-breit (getIstStarrUndBreit),
---   * Leistung/Gewicht passend (getPasstGeraetZuTraktor),
---   * gemeinsame Kupplungsart laut XML (getXmlKupplungen).
--- Erst wird das Geraet gleichverteilt gewaehlt, dann ein Traktor dazu - sonst
--- gewaennen Kleinstgeraete, die an jeden Traktor passen.
--- @return table|nil Fahrzeugliste im Format von getRandomVehicleGroup
function NachbarFelderManager:getEigenesFeldGespann(missionTypeName)
    local kats = NachbarFelderManager.FELD_GERAETE_KATEGORIEN[missionTypeName]
    if kats == nil then return nil end
    if self.trafficVehicleList == nil then self:buildTrafficVehicleList() end
    local traktoren = self.trafficVehicleList or {}
    if #traktoren == 0 then return nil end

    local sperre = (self.vehicleImplBlacklist ~= nil and self.vehicleImplBlacklist[missionTypeName]) or {}
    local allItems = {}
    pcall(function() allItems = g_storeManager:getItems() end)

    local geraete = {}
    for _, item in pairs(allItems) do
        if item ~= nil and item.xmlFilename ~= nil and kats[item.categoryName]
           and (sperre[item.xmlFilename] or 0) < 1 then
            local frei = true
            pcall(function() frei = g_storeManager:getIsItemUnlocked(item) end)
            if frei and not self:getIstStarrUndBreit(item.xmlFilename) then
                local bedarf = nfGetItemNeededPower(item)
                local gewicht = nfGetItemWeight(item)
                -- Build 121: Mindest-Arbeitsbreite (specs.workingWidth = {width, minWidth})
                local breite = nil
                pcall(function()
                    local ww = item.specs ~= nil and item.specs.workingWidth or nil
                    if type(ww) == "table" then
                        breite = tonumber(ww.width)
                    else
                        breite = tonumber(ww)
                    end
                end)
                if breite ~= nil and breite < NachbarFelderManager.FELD_MIN_ARBEITSBREITE then
                    self.schmalGemeldet = self.schmalGemeldet or {}
                    if not self.schmalGemeldet[item.xmlFilename] then
                        self.schmalGemeldet[item.xmlFilename] = true
                        print(string.format("NachbarFelder: Anbaugeraet [%s] arbeitet nur %.1f m breit" ..
                            " - nicht fuer Feldhelfer", tostring(item.xmlFilename), breite))
                    end
                elseif bedarf == nil then
                    -- Build 127: ohne Leistungsangabe ist "passt zum Traktor" nicht pruefbar
                    -- (LIZARD MT, 13 m, landete am TK4.80 mit 75 PS)
                    self.ohnePsGemeldet = self.ohnePsGemeldet or {}
                    if not self.ohnePsGemeldet[item.xmlFilename] then
                        self.ohnePsGemeldet[item.xmlFilename] = true
                        print("NachbarFelder: Anbaugeraet [" .. tostring(item.xmlFilename) ..
                            "] hat keine Leistungsangabe - nicht fuer Feldhelfer")
                    end
                else
                    geraete[#geraete + 1] = { filename = item.xmlFilename, bedarf = bedarf, gewichtKg = gewicht }
                end
            end
        end
    end

    local proGeraet, geraeteMitPartner, nPaare = {}, {}, 0
    for _, g in ipairs(geraete) do
        local ein = self:getXmlKupplungen(g.filename, true)
        for _, t in ipairs(traktoren) do
            if self:getPasstFeldGeraetZuTraktor(t, g)   -- Build 123: 130 % Leistung
               and not self:getIstFeldGespannGesperrt(t.filename, g.filename) then   -- Build 120
                local aus = self:getXmlKupplungen(t.filename, false)
                for jt, _ in pairs(ein) do
                    if aus[jt] then
                        if proGeraet[g] == nil then
                            proGeraet[g] = {}
                            geraeteMitPartner[#geraeteMitPartner + 1] = g
                        end
                        table.insert(proGeraet[g], t)
                        nPaare = nPaare + 1
                        break
                    end
                end
            end
        end
    end

    local function kurz(f) return string.match(tostring(f), "[^/\\]+$") or tostring(f) end
    if #geraeteMitPartner == 0 then
        print(string.format("NachbarFelder: Kein eigenes Feldgespann fuer %s - %d Kleintraktoren, %d Geraete," ..
            " keine Kombination passt (Leistung/Gewicht/Kupplung)", tostring(missionTypeName), #traktoren, #geraete))
        return nil
    end
    local g = geraeteMitPartner[math.random(#geraeteMitPartner)]
    local t = proGeraet[g][math.random(#proGeraet[g])]
    print(string.format("NachbarFelder: Eigenes Feldgespann fuer %s: %s (%s PS, %s t) + %s (Bedarf %s PS)" ..
        " - Auswahl aus %d Geraeten, %d Kombinationen",
        tostring(missionTypeName), kurz(t.filename), tostring(t.leistung or "?"),
        t.gewichtKg ~= nil and string.format("%.1f", t.gewichtKg / 1000) or "?",
        kurz(g.filename), tostring(g.bedarf or "?"), #geraeteMitPartner, nPaare))
    return { { filename = t.filename }, { filename = g.filename } }
end

--- Ist die Zugmaschine einer Vertrags-Fahrzeuggruppe zu gross? (Build 114)
---
--- Der Verkehr faehrt seit Build 105 nur Kleintraktoren bis 7 t. Die Feldhelfer
--- nehmen ihre Gespanne aber aus den Vertragslisten des Spiels
--- (MissionManager:getRandomVehicleGroup, MissionManager.lua:925), und dort steht
--- auch in der Gruppe "small" z.B. ein New Holland T8000 (Highlands-DLC) mit
--- 5,5-m-Grubber. Auf dem engen Shop-Platz verkeilte sich das beim Ausrichten.
--- Gleiche Grenze wie beim Verkehr: Leergewicht hoechstens 7 t, nie TRACTORSL.
--- Unbekanntes Store-Item oder Gewicht: nur die Kategorie entscheidet.
function NachbarFelderManager:getIstZugmaschineZuGross(filename)
    if filename == nil then return false end
    self.zugmaschineCache = self.zugmaschineCache or {}
    local c = self.zugmaschineCache[filename]
    if c ~= nil then return c end
    local zuGross, gewicht, kat = false, nil, nil
    pcall(function()
        local item = g_storeManager:getItemByXMLFilename(filename)
        if item == nil then return end
        kat = item.categoryName
        gewicht = nfGetItemWeight(item)
    end)
    if kat == "TRACTORSL" or (gewicht ~= nil and gewicht > NF_KLEIN_MAX_VEH_WEIGHT_KG) then
        zuGross = true
        print(string.format("NachbarFelder: Zugmaschine [%s] (%s, %s) zu gross - nicht fuer Feldhelfer",
            tostring(filename), tostring(kat or "?"),
            gewicht ~= nil and string.format("%.1f t", gewicht / 1000) or "Gewicht ?"))
    end
    self.zugmaschineCache[filename] = zuGross
    return zuGross
end

function NachbarFelderManager:isVehicleGroupBlacklisted(veh, missionTypeName)
    -- Build 114: nur kleine Zugmaschinen
    if veh ~= nil and veh[1] ~= nil and self:getIstZugmaschineZuGross(veh[1].filename) then
        return true
    end
    -- Build 113: starre, breite Geraete in der Gruppe -> Gruppe verwerfen
    for i = 2, #(veh or {}) do
        if veh[i] ~= nil and self:getIstStarrUndBreit(veh[i].filename) then
            return true
        end
    end
    -- Prüft ob das Implement (veh[2]) für diesen Missionstyp gesperrt ist
    if self.vehicleImplBlacklist == nil then return false end
    local blacklist = self.vehicleImplBlacklist[missionTypeName]
    if blacklist == nil then return false end
    -- veh[2] ist das Anbaugerät (Index 2 = erster Anhänger hinter dem Traktor)
    if veh[2] ~= nil and veh[2].filename ~= nil then
        local fails = blacklist[veh[2].filename] or 0
        if fails >= 1 then
            print("NachbarFelder: Implement [" .. tostring(veh[2].filename) .. "] fuer " ..
                tostring(missionTypeName) .. " gesperrt (" .. fails .. "x) - neue Gruppe wird gesucht")
            return true
        end
    end
    return false
end

--- Fahrzeuggroesse der Mission, auf engen Karten gedeckelt.
---
--- AbstractFieldMission:getVehicleSize() (AbstractFieldMission.lua:519) leitet
--- "small"/"medium"/"large" allein aus der Feldflaeche ab. Auf einer engen
--- Karte nuetzt das nichts: auch ein grosses Feld liegt dort hinter schmalen
--- Wegen, und das Gespann bleibt auf dem Weg dorthin haengen.
---
--- Mit engeMap bekommt jede Mission die KLEINSTE Gruppe. Nicht wegen der Wege -
--- mittelgrosse Gespanne kommen dort durch -, sondern wegen des Haendlers: auf
--- der Beuren teilen sich zwei Spawn-Plaetze 35 laufende Meter, und ein
--- Gespann aus Mitteltraktor und Anbaugeraet belegt davon die Haelfte. Zwei
--- davon gleichzeitig, und die Fahrzeuge stehen ineinander.
--- Kleine Gruppen sind kurze Gruppen - Kleintraktor mit Wender oder Schwader.
function NachbarFelderManager:getMissionVehicleSize(mission)
    local size = "small"
    pcall(function()
        if mission ~= nil and mission.getVehicleSize ~= nil then
            size = mission:getVehicleSize() or "small"
        end
    end)
    -- Build 105: auf jeder Karte nur die kleine Gruppe. Die Missions-Fahrzeug-
    -- listen des Spiels paaren Traktor und Geraet selbst - die passen zueinander.
    return "small"
end

--- Steht noch ein eigenes Fahrzeug am Haendler?
---
--- isSpawnSpaceAvailable() fragt die Engine nach freien Shop-Plaetzen, aber die
--- Belegung (usedStorePlaces) wird nach dem Laden wieder aufgehoben. Ein
--- Helfer, der noch auf seinen Job wartet, steht also physisch im Weg, ohne
--- dass die Engine den Platz als belegt kennt - genau daraus entsteht das
--- Ineinanderstehen. Diese Pruefung schaut deshalb selbst nach, ob im Umkreis
--- des Spawn-Platzes noch etwas von uns herumsteht.
--- @return boolean true = belegt, jetzt nicht spawnen
function NachbarFelderManager:istSpawnBereichBelegt()
    local radius = self.spawnBereichRadius or 25
    local sx, sz = self:getShopPosition()
    if sx == 0 and sz == 0 then
        return false        -- kein Spawn-Platz bekannt: nicht blockieren
    end

    local belegt = false

    for _, eintrag in pairs(self.vehicleType or {}) do
        if belegt then break end
        local fahrzeuge = eintrag ~= nil and eintrag.vehicleType or nil
        for _, veh in ipairs(fahrzeuge or {}) do
            pcall(function()
                if veh ~= nil and veh.rootNode ~= nil and entityExists(veh.rootNode) then
                    local x, _, z = getWorldTranslation(veh.rootNode)
                    if MathUtil.vector2Length(x - sx, z - sz) < radius then
                        belegt = true
                    end
                end
            end)
            if belegt then break end
        end
    end

    return belegt
end

function NachbarFelderManager:getRandomVehicles(mission)
    -- Build 125: Pfluegen/Grubbern NUR mit eigenen Gespannen (Kleintraktor bis 7 t,
    -- Leistung max. 5 % drueber, Arbeitsbreite ab 2 m, Planungsbreite bis 3,05 m).
    -- Die Vertragslisten des Spiels lieferten TK4.80 (75 PS) + Servo 25 (85 PS, 1,2 m)
    -- und einen MB Trac mit langem Pflug, der am Start in die Luft flog.
    if mission ~= nil and mission.type ~= nil
       and NachbarFelderManager.FELD_GERAETE_KATEGORIEN[mission.type.name] ~= nil then
        local eigen = self:getEigenesFeldGespann(mission.type.name)
        if eigen ~= nil then
            return eigen, 1
        end
        print("NachbarFelder: Kein passendes Kleintraktor-Gespann fuer " .. tostring(mission.type.name) ..
            " - kein Helfer")
        return {}, 1
    end
    local variant = self:getVariant(mission)
    -- Bis zu 10 Versuche, eine nicht-gesperrte Fahrzeuggruppe zu finden
    local veh, iden

    -- EINMAL bestimmen und ueberall verwenden. Wuerde der Fallback unten
    -- wieder mission:getVehicleSize() fragen, griffe er auf die Ersatzliste
    -- einer anderen Groessenklasse zu als die Abfrage oben - das Gespann waere
    -- dann doch wieder gross.
    local groesse = self:getMissionVehicleSize(mission)

    for attempt = 1, 25 do   -- Build 113: mehr Versuche, weil starre breite Geraete wegfallen
        veh, iden = g_missionManager:getRandomVehicleGroup(mission.type.name, groesse, variant)
        veh = veh or {}   -- Build 114: das Spiel liefert nil, wenn es keine Gruppe gibt
        if #veh > 0 and not self:isVehicleGroupBlacklisted(veh, mission.type.name) then
            break  -- Gute Kombination gefunden
        end
        if #veh == 0 then break end  -- Kein Fahrzeug verfügbar
        veh = {}  -- Gesperrte Gruppe verwerfen, nächster Versuch
    end

    -- Build 115: keine passende Spielgruppe -> eigenes Kleintraktor-Gespann
    if #veh == 0 then
        local eigen = self:getEigenesFeldGespann(mission.type.name)
        if eigen ~= nil then
            return eigen, 1
        end
    end

    if #veh == 0 then
        -- Ersatzliste aus frueheren Laeufen. Sie ist beim ersten Mal noch leer
        -- (vehicleMission wird nur im else-Zweig gefuellt), und mit gedeckelter
        -- Groesse kann auch eine andere Klasse gefuellt sein als die gesuchte -
        -- deshalb hier pruefen statt blind indizieren.
        local proTyp = vehicleMission[mission.type.name]
        local liste  = proTyp ~= nil and proTyp[groesse] or nil
        if liste == nil or #liste == 0 then
            print("NachbarFelder: Keine Fahrzeuggruppe (" .. tostring(mission.type.name) ..
                ", Groesse " .. tostring(groesse) .. ") verfuegbar")
            return {}, iden
        end
        local randomInt = math.random(1, #liste)
        veh = liste[randomInt]
        table.remove(liste, randomInt)
        local obj = {}
        for k, v in ipairs(veh) do obj[k] = v end
        table.insert(liste, obj)
    else
        if vehicleMission[mission.type.name] == nil then vehicleMission[mission.type.name] = {} end
        if vehicleMission[mission.type.name][groesse] == nil then
            vehicleMission[mission.type.name][groesse] = {}
        end
        local obj = {}
        for k, v in ipairs(veh) do obj[k] = v end
        table.insert(vehicleMission[mission.type.name][groesse], obj)
    end
    return veh, iden
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
    -- Patrol-Einträge haben keine Feldarbeit, keinen Feld-Zustand und keine sowMission-Logik
    local w = self.vehicleType[fieldId] and self.vehicleType[fieldId].NachbarFelderWorker
    if w ~= nil and w.isPatrol then
        self.vehicleType[fieldId] = nil
        self.counter = self.counter - 1
        return
    end

    self:finishFieldState(fieldId, status)

    if self.vehicleType[fieldId].NachbarFelderWorker.mission.type.name == "sowMission" then
        local veh = self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad[2]
        if veh ~= nil and veh.spec_sowingMachine ~= nil then
            local field = g_fieldManager:getFieldById(fieldId)
            local seedsFruitType = veh.spec_sowingMachine.seeds[veh.spec_sowingMachine.currentSeed]
            -- Gesaete Frucht als neue Vorfrucht merken (Build 68)
            pcall(function()
                local fd = g_fruitTypeManager:getFruitTypeByIndex(seedsFruitType)
                if fd ~= nil and fd.name ~= nil then
                    self.fieldLastFruit[fieldId] = fd.name
                end
            end)
            local fieldUpdateTask = FieldUpdateTask.new()
            fieldUpdateTask:setField(field)
            fieldUpdateTask:setArea(field:getDensityMapPolygon())
            fieldUpdateTask:setFruit(seedsFruitType, 1)
            fieldUpdateTask:setGroundAngle(field:getAngle())
            fieldUpdateTask:setRollerLevel(1)
            fieldUpdateTask:enqueue(true)
        end
    end
    self.vehicleType[fieldId] = nil
    self.counter = self.counter - 1
end

function NachbarFelderManager:finishFieldState(fieldId, status)
    -- Nur bei abgeschlossener Feldarbeit (Status 2) den Feldstatus aktualisieren
    if status ~= 2 then return end
    -- Patrol-Einträge haben negative fieldId und kein echtes Feld
    if fieldId == nil or fieldId < 0 then return end
    local field = g_fieldManager:getFieldById(fieldId)
    if field == nil then return end
    local fieldUpdateTask = FieldUpdateTask.new()
    fieldUpdateTask:setField(field)
    fieldUpdateTask:setArea(field:getDensityMapPolygon())
    fieldUpdateTask:setGroundAngle(field:getAngle())

    local missionName = self.vehicleType[fieldId].NachbarFelderWorker.mission.type.name
    local fieldState = field:getFieldState()

    -- Build 111: Pfluegen/Grubbern setzt unten das GANZE Feld auf den Zielzustand.
    -- Steht dort noch Frucht (Feld 53 am 13.09.: reifer Raps), wird nichts
    -- ueberschrieben - sonst waere eine Fehlentscheidung auf dem ganzen Feld wirksam.
    if missionName == "plowMission" or missionName == "cultivateMission" then
        local _, grund, info = self:getFeldAktion(field)
        if grund == "frucht" or grund == "waechst" or grund == "erntereif" then
            print("NachbarFelder: Feld " .. tostring(fieldId) .. " - nach der Arbeit steht dort noch Frucht (" ..
                tostring(info) .. "), Feldzustand wird NICHT ueberschrieben")
            return
        end
    end

    if missionName == "sowMission" then
        local veh = self.vehicleType[fieldId].NachbarFelderWorker.vehiclesToLoad[2]
        if veh ~= nil and veh.spec_sowingMachine ~= nil then
            local seedsFruitType = veh.spec_sowingMachine.seeds[veh.spec_sowingMachine.currentSeed]
            fieldUpdateTask:setFruit(seedsFruitType, 1)
            fieldUpdateTask:setGroundType(FieldGroundType.SOWN)
            fieldUpdateTask:setRollerLevel(1)
            -- Gesaete Frucht als neue Vorfrucht merken (Build 68)
            pcall(function()
                local fd = g_fruitTypeManager:getFruitTypeByIndex(seedsFruitType)
                if fd ~= nil and fd.name ~= nil then
                    self.fieldLastFruit[fieldId] = fd.name
                end
            end)
        end
    elseif missionName == "plowMission" then
        fieldUpdateTask:setGroundType(FieldGroundType.PLOWED)
        fieldUpdateTask:setWeedState(0)
        fieldUpdateTask:setFruit(FruitType.UNKNOWN, 1)
        fieldUpdateTask:setRollerLevel(0)
    elseif missionName == "cultivateMission" then
        fieldUpdateTask:setGroundType(FieldGroundType.CULTIVATED)
        fieldUpdateTask:setFruit(FruitType.UNKNOWN, 1)
        fieldUpdateTask:setRollerLevel(0)
    elseif missionName == "harvestMission" then
        local fruit = g_fruitTypeManager:getFruitTypeByIndex(fieldState.fruitTypeIndex)
        for k, v in pairs(fruit.growthStateToName) do
            if v == "harvested" then
                fieldUpdateTask:setFruit(fieldState.fruitTypeIndex, k)
            end
        end
        fieldUpdateTask:setGroundType(FieldGroundType.STUBBLE_TILLAGE)
    elseif missionName == "hoeMission" then
        fieldUpdateTask:setGroundType(FieldGroundType.CULTIVATED)
        fieldUpdateTask:setWeedState(0)
    elseif missionName == "weedMission" then
        fieldUpdateTask:setWeedState(0)
    elseif missionName == "herbicideMission" then
        -- Herbizid entfernt Unkraut - es erhöht NICHT den Düngerlevel
        fieldUpdateTask:setSprayType(SprayType.HERBICIDE)
        fieldUpdateTask:setWeedState(0)
    elseif missionName == "fertilizeMission" then
        fieldUpdateTask:setSprayType(SprayType.FERTILIZER)
        fieldUpdateTask:setSprayLevel(fieldState.sprayLevel + 1)
    end

    fieldUpdateTask:enqueue(true)
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
    pcall(function()
        local ps = g_currentMission and g_currentMission.placeableSystem
        if ps == nil then return end
        for _, p in pairs(ps.placeables or {}) do
            if p.spec_vehicleShop ~= nil and p.rootNode ~= nil then
                local x, _, z = getWorldTranslation(p.rootNode)
                bx, bz = x, z
                return
            end
        end
    end)
    -- Versuch 2: g_currentMission.vehicleShops (einige Maps/FS25-Versionen)
    if bx == nil then
        pcall(function()
            for _, s in pairs(g_currentMission.vehicleShops or {}) do
                local nd = s.rootNode
                if nd ~= nil then
                    local x, _, z = getWorldTranslation(nd)
                    bx, bz = x, z
                    return
                end
            end
        end)
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
    local path = g_currentMission.missionInfo.savegameDirectory
    if path == nil then return end
    local modSaveDir = path .. "/NachbarFelder.xml"
    local xmlFile = XMLFile.create("NachbarFelder", modSaveDir, baseXmlKey, xmlSchema)
    local baseKey = baseXmlKey .. ".worker"
    local i = 0
    if g_NachbarFelderManager.vehicleType ~= nil then
        for v, k in pairs(g_NachbarFelderManager.vehicleType) do
            if k.NachbarFelderWorker.status < 3 and not k.NachbarFelderWorker.isPatrol then
                local key = ("%s(%d)"):format(baseKey, i)
                xmlFile:setInt(key .. "#fieldId", k.NachbarFelderWorker.fieldId)
                xmlFile:setString(key .. "#missionType", k.NachbarFelderWorker.mission.type.name)
                -- Build 139: Auftrag eines Spielers als solchen merken
                if k.NachbarFelderWorker.istAuftrag then
                    xmlFile:setBool(key .. "#auftrag", true)
                    xmlFile:setInt(key .. "#auftragFarmId", k.NachbarFelderWorker.auftragFarmId or 0)
                end
                i = i + 1
            end
        end
        -- Settings-Block (Build 67): kompletter Einstellungs-Stand ins
        -- Savegame - server-autoritativ, ueberlebt Neustarts.
        pcall(function()
            local st = g_NachbarFelderManager:getSettingsState()
            xmlFile:setBool(baseXmlKey .. ".settings#active",             st.active)
            xmlFile:setInt( baseXmlKey .. ".settings#maxWorkers",         st.maxWorkers)
            xmlFile:setInt( baseXmlKey .. ".settings#trafficLimit",       st.trafficLimit)
            xmlFile:setInt( baseXmlKey .. ".settings#trafficTrailerSize", st.trafficTrailerSize)
            xmlFile:setBool(baseXmlKey .. ".settings#engeMap",            st.engeMap)
            local j = 0
            for mName, mActive in pairs(st.missions) do
                local mKey = ("%s.settings.mission(%d)"):format(baseXmlKey, j)
                xmlFile:setString(mKey .. "#type",   mName)
                xmlFile:setBool(  mKey .. "#active", mActive)
                j = j + 1
            end
        end)
        -- Vorfrucht-Gedaechtnis (Build 68) mitspeichern
        pcall(function()
            local j = 0
            local lastFruits = g_NachbarFelderManager.fieldLastFruit or {}
            for fId, fName in pairs(lastFruits) do
                local fKey = ("%s.fieldFruits.field(%d)"):format(baseXmlKey, j)
                xmlFile:setInt(   fKey .. "#id",    fId)
                xmlFile:setString(fKey .. "#fruit", fName)
                j = j + 1
            end
        end)
        xmlFile:save(false, false)
        xmlFile:delete()
    end
end

function NachbarFelderManager:loadFromXML()
    local path = g_currentMission.missionInfo.savegameDirectory
    if path == nil then return end
    local modSaveDir = path .. "/NachbarFelder.xml"
    local xmlFile = XMLFile.loadIfExists("NachbarFelder", modSaveDir, xmlSchema)
    if xmlFile == nil then return end
    local itKey = baseXmlKey .. ".worker"
    xmlFile:iterate(itKey, function(_, key)
        local fieldId = xmlFile:getValue(key .. "#fieldId")
        local missionType = xmlFile:getValue(key .. "#missionType")
        local auftrag = xmlFile:getValue(key .. "#auftrag")
        local auftragFarmId = xmlFile:getValue(key .. "#auftragFarmId")
        self:loadedSettings(fieldId, missionType, auftrag, auftragFarmId)
    end)
    -- Settings-Block lesen (Build 67). NICHT sofort anwenden - erst
    -- nach loadServerConfig() (in loadMap), damit die Savegame-Werte
    -- die Konfig-Datei-Werte ueberschreiben und nicht umgekehrt.
    pcall(function()
        local sgActive = xmlFile:getValue(baseXmlKey .. ".settings#active")
        if sgActive ~= nil then
            local st = {
                active             = sgActive,
                maxWorkers         = xmlFile:getValue(baseXmlKey .. ".settings#maxWorkers"),
                trafficLimit       = xmlFile:getValue(baseXmlKey .. ".settings#trafficLimit"),
                trafficTrailerSize = xmlFile:getValue(baseXmlKey .. ".settings#trafficTrailerSize"),
                engeMap            = xmlFile:getValue(baseXmlKey .. ".settings#engeMap"),
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
    end)
    -- Vorfrucht-Gedaechtnis laden (Build 68)
    pcall(function()
        xmlFile:iterate(baseXmlKey .. ".fieldFruits.field", function(_, fKey)
            local fId   = xmlFile:getValue(fKey .. "#id")
            local fName = xmlFile:getValue(fKey .. "#fruit")
            if fId ~= nil and fName ~= nil then
                self.fieldLastFruit[fId] = fName
            end
        end)
    end)
    xmlFile:delete()
end

function NachbarFelderManager:loadedSettings(fieldId, missionType, auftrag, auftragFarmId)
    table.insert(self.loadVehiclesFromXML, {fieldId = fieldId, missionType = missionType,
        auftrag = auftrag == true, auftragFarmId = auftragFarmId or 0})
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
    local ok, err = pcall(function()
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
    end)
    if not ok then
        print("NachbarFelder: [MAP] NFWaypointHotspot Definition fehlgeschlagen: " .. tostring(err))
    end
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
        -- pcall(fn) aufrufen - kein Closure-/String-Müll pro Frame (GC-Ruckler).
        -- Nummern-Strings werden in updateWpHotspots vorberechnet (hs._nfLabel).
        local function nfDrawWpNumbers()
            local hss = mgr._wpMapHotspots
            for i = 1, #hss do
                local hs = hss[i]
                local sx, sy = hs:getLastScreenPosition()
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
        pcall(function()
            InGameMenuMapFrame.draw = Utils.appendedFunction(InGameMenuMapFrame.draw,
            function(frame)
                if mgr._wpHotspotsEnabled == false then return end
                local hss = mgr._wpMapHotspots
                if hss == nil or #hss == 0 then return end
                pcall(nfDrawWpNumbers)
            end)
        end)
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
    pcall(function()
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
    end)
end

function NachbarFelderManager:saveClientPrefs()
    pcall(function()
        createFolder(modSettingDirectory)
        local path = modSettingDirectory .. "NachbarFelderClient.xml"
        local xf = createXMLFile("nfClient", path, "nachbarFelderClient")
        if xf == nil or xf == 0 then return end
        setXMLBool(xf, "nachbarFelderClient.showWpOnMap", self._wpHotspotsEnabled ~= false)
        saveXMLFile(xf)
        delete(xf)
    end)
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
                pcall(function() g_currentMission:removeMapHotspot(hs) end)
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
        local ok, hs = pcall(function() return NFWaypointHotspot_cls.new(wp.x, wp.z) end)
        if ok and hs ~= nil then
            -- vorberechnet für den Draw-Hook (kein Müll pro Frame); Spawnpunkte mit "S"
            hs._nfLabel = self:getIstSpawnpunkt(wp) and (tostring(i) .. " S") or tostring(i)
            pcall(function() g_currentMission:addMapHotspot(hs) end)
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
        pcall(function()
            g_server:broadcastEvent(NachbarFelderWaypointSyncEvent.new(self.userTrafficWaypoints))
        end)
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
        pcall(function()
            xmlFile:setString(wpXmlKey .. "#uebernommenFuer", nfGetKartenKennung() or "?")
            xmlFile:save(false, false)
        end)
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
        "NachbarFelder: Zeit bis zum naechsten Start anzeigen",
        "consoleCommandNachbarFelderTimer", self)
    addConsoleCommand("nachbarFelderEntfernen",
        "NachbarFelder: alle aktiven Fahrzeuge entfernen",
        "consoleCommandNachbarFelderEntfernen", self)
    addConsoleCommand("nachbarFelderStart",
        "NachbarFelder: naechsten Auftrag starten",
        "consoleCommandNachbarFelderStart", self)
    addConsoleCommand("nachbarFelderTrafficStop",
        "NachbarFelder: alle Traffic-Fahrzeuge entfernen und neue sperren",
        "consoleCommandNachbarFelderTrafficStop", self)
    addConsoleCommand("nachbarFelderTrafficStart",
        "NachbarFelder: Traffic-Fahrzeuge wieder erlauben",
        "consoleCommandNachbarFelderTrafficStart", self)
    addConsoleCommand("nachbarFelderSperre",
        "NachbarFelder: Feld aussperren/freigeben: nachbarFelderSperre <Feldnummer wie auf der Karte> [aus]",
        "consoleCommandNachbarFelderSperre", self)
end

--- Feld von der Bearbeitung ausschliessen.
--- Die Doppelpunkt-Form macht self implizit; feldNr ist damit wirklich das
--- erste Nutzer-Argument (anders als bei der Punkt-Form, siehe ErtragsFaktor).
function NachbarFelderManager:consoleCommandNachbarFelderSperre(feldNr, aus)
    if not g_currentMission:getIsServer() then
        return "NachbarFelder: nur auf Server/SP verfuegbar!"
    end

    local nr = tonumber(feldNr)
    if nr == nil then
        local liste = {}
        for id in pairs(self.feldSperre or {}) do
            table.insert(liste, tostring(id))
        end
        table.sort(liste)
        return "NachbarFelder: gesperrte Felder: " ..
               (#liste > 0 and table.concat(liste, ", ") or "keine") ..
               "  |  Aufruf: nachbarFelderSperre <Feldnummer wie auf der Karte> [aus]"
    end
    local an = not (aus ~= nil and (aus == "aus" or aus == "off" or aus == "0"))
    -- Build 139: Die Nummer auf der Karte ist field:getId() und damit genau der
    -- Schluessel von feldSperre/getFieldById - keine Umrechnung noetig. Beim
    -- Sperren pruefen, ob es das Feld gibt; Freigeben geht immer (alte Eintraege).
    if an and g_fieldManager:getFieldById(nr) == nil then
        return string.format("NachbarFelder: Feld %d gibt es nicht - Feldnummer wie auf der Karte angeben", nr)
    end
    self:sperreFeld(nr, an)

    return string.format("NachbarFelder: Feld %d %s", nr,
        an and "gesperrt - wird nicht mehr bearbeitet" or "wieder freigegeben")
end

function NachbarFelderManager:consoleCommandNachbarFelderStart()
    if not g_currentMission:getIsServer() then
        print("NachbarFelder: nachbarFelderStart nur auf Server/SP verfuegbar!")
        return
    end
    local created = self:generateWorkMission(true)
    if created then
        print("NachbarFelder: Neuer Auftrag gestartet!")
    else
        print("NachbarFelder: Kein Auftrag moeglich")
    end
end

function NachbarFelderManager:consoleCommandNachbarFelderTimer()
    print("NachbarFelder: naechster Auftrag in " .. tostring(self.timeToNextStart))
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

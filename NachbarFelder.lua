local modDirectory = g_currentModDirectory
g_currentModName = "FS25_NachbarFelder"
local modName = g_currentModName

-- ============================================================
-- Network-Events: Client → Server
-- ============================================================
NachbarFelderDeleteEvent = {}
NachbarFelderDeleteEvent_mt = Class(NachbarFelderDeleteEvent, Event)
InitEventClass(NachbarFelderDeleteEvent, "NachbarFelderDeleteEvent")

function NachbarFelderDeleteEvent.emptyNew()
    return Event.new(NachbarFelderDeleteEvent_mt)
end
function NachbarFelderDeleteEvent.new()
    return NachbarFelderDeleteEvent.emptyNew()
end
function NachbarFelderDeleteEvent:readStream(streamId, connection)
    if g_currentMission:getIsServer() then
        -- nur Admin-Verbindungen (Build 75)
        if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Delete-Event abgelehnt - Absender ist kein Admin")
            return
        end
        -- Admin-Aktion: aktive Fahrzeuge UND Pool-Fahrzeuge entfernen
        if g_NachbarFelderManager.deleteAllVehiclesAndPool ~= nil then
            g_NachbarFelderManager:deleteAllVehiclesAndPool()
        else
            g_NachbarFelderManager:deleteAllVehicles()
        end
        print("NachbarFelder: Fahrzeuge durch Client-Event geloescht")
    end
end
function NachbarFelderDeleteEvent:writeStream(streamId, connection)
end

-- Client → Server: Wegpunkt-Änderung (Setzen/Löschen/Typ/Fahrzeugkategorien).
-- WICHTIG: Auf dem Dedi ist der SERVER Besitzer der Wegpunkt-Datei. Clientseitige
-- Änderungen liefen früher nur lokal und wurden vom nächsten Sync überschrieben
-- ("Wegpunkte werden nicht gespeichert").
NachbarFelderWaypointEditEvent = {}
NachbarFelderWaypointEditEvent_mt = Class(NachbarFelderWaypointEditEvent, Event)
InitEventClass(NachbarFelderWaypointEditEvent, "NachbarFelderWaypointEditEvent")

NachbarFelderWaypointEditEvent.OP_ADD        = 1
NachbarFelderWaypointEditEvent.OP_REMOVELAST = 2
NachbarFelderWaypointEditEvent.OP_DELETE     = 3
NachbarFelderWaypointEditEvent.OP_SETCAT     = 4
NachbarFelderWaypointEditEvent.OP_VEHCAT     = 5
-- Build 134: wie OP_ADD, der neue Punkt ist aber gleich ein Spawnpunkt (Button
-- "Spawnpunkt hier setzen") - kein zweites SETCAT-Event mit geratenem Index
NachbarFelderWaypointEditEvent.OP_ADD_SPAWN  = 6

function NachbarFelderWaypointEditEvent.emptyNew()
    return Event.new(NachbarFelderWaypointEditEvent_mt)
end
function NachbarFelderWaypointEditEvent.new(op, a, b, c)
    local self = NachbarFelderWaypointEditEvent.emptyNew()
    self.op = op or 0
    self.a  = a or 0
    self.b  = b or 0
    self.c  = c or 0
    return self
end
function NachbarFelderWaypointEditEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.op or 0)
    streamWriteFloat32(streamId, self.a or 0)
    streamWriteFloat32(streamId, self.b or 0)
    streamWriteFloat32(streamId, self.c or 0)
end
function NachbarFelderWaypointEditEvent:readStream(streamId, connection)
    self.op = streamReadUInt8(streamId)
    self.a  = streamReadFloat32(streamId)
    self.b  = streamReadFloat32(streamId)
    self.c  = streamReadFloat32(streamId)
    if g_currentMission:getIsServer() and g_NachbarFelderManager ~= nil then
        -- nur Admin-Verbindungen (Build 75); Stream ist zu diesem Zeitpunkt
        -- bereits vollstaendig gelesen (Pflicht vor dem Abbruch!)
        if g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Wegpunkt-Edit abgelehnt - Absender ist kein Admin")
            return
        end
        pcall(function()
            g_NachbarFelderManager:applyWaypointEdit(self.op, self.a, self.b, self.c)
        end)
    end
end

-- ============================================================
-- Network-Events: Settings-Sync (Build 67)
-- Gleiche Architektur wie das Wegpunkt-Editing: Client schickt
-- eine Aenderung, der SERVER ist autoritativ (wendet an, merkt
-- fuers Savegame vor) und broadcastet den kompletten Stand an
-- alle Clients zurueck.
-- ============================================================

-- Client → Server: eine Einstellung aendern (name + Zahlwert; bool = 0/1)
NachbarFelderSettingsEditEvent = {}
NachbarFelderSettingsEditEvent_mt = Class(NachbarFelderSettingsEditEvent, Event)
InitEventClass(NachbarFelderSettingsEditEvent, "NachbarFelderSettingsEditEvent")

function NachbarFelderSettingsEditEvent.emptyNew()
    return Event.new(NachbarFelderSettingsEditEvent_mt)
end
function NachbarFelderSettingsEditEvent.new(settingName, value)
    local self = NachbarFelderSettingsEditEvent.emptyNew()
    self.settingName = settingName or ""
    self.value       = value or 0
    return self
end
function NachbarFelderSettingsEditEvent:writeStream(streamId, connection)
    streamWriteString( streamId, self.settingName or "")
    streamWriteFloat32(streamId, self.value or 0)
end
function NachbarFelderSettingsEditEvent:readStream(streamId, connection)
    self.settingName = streamReadString( streamId)
    self.value       = streamReadFloat32(streamId)
    if g_currentMission:getIsServer() and g_NachbarFelderManager ~= nil then
        -- nur Admin-Verbindungen (Build 75); Stream vorher komplett lesen!
        if g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Settings-Edit abgelehnt - Absender ist kein Admin")
            return
        end
        pcall(function()
            g_NachbarFelderManager:applySettingEdit(self.settingName, self.value)
        end)
    end
end

-- Server → Client: kompletter Einstellungs-Stand
NachbarFelderSettingsSyncEvent = {}
NachbarFelderSettingsSyncEvent_mt = Class(NachbarFelderSettingsSyncEvent, Event)
InitEventClass(NachbarFelderSettingsSyncEvent, "NachbarFelderSettingsSyncEvent")

function NachbarFelderSettingsSyncEvent.emptyNew()
    return Event.new(NachbarFelderSettingsSyncEvent_mt)
end
function NachbarFelderSettingsSyncEvent.new(state)
    local self = NachbarFelderSettingsSyncEvent.emptyNew()
    self.state = state or {}
    return self
end
function NachbarFelderSettingsSyncEvent:writeStream(streamId, connection)
    local st = self.state or {}
    -- bools als UInt8 0/1 (robust, gleiche Technik wie Waypoint-Sync)
    streamWriteUInt8(streamId, (st.active ~= false) and 1 or 0)
    streamWriteUInt8(streamId, math.max(0, math.min(30, st.maxWorkers or 12)))
    streamWriteUInt8(streamId, math.max(0, math.min(12, st.trafficLimit or 4)))
    streamWriteUInt8(streamId, math.max(0, math.min(3,  st.trafficTrailerSize or 2)))
    streamWriteUInt8(streamId, (st.engeMap ~= false) and 1 or 0)
    local missions = st.missions or {}
    local count = 0
    for _ in pairs(missions) do count = count + 1 end
    streamWriteUInt8(streamId, count)
    for mName, mActive in pairs(missions) do
        streamWriteString(streamId, mName)
        streamWriteUInt8( streamId, (mActive == true) and 1 or 0)
    end
end
function NachbarFelderSettingsSyncEvent:readStream(streamId, connection)
    local state = {}
    state.active             = streamReadUInt8(streamId) == 1
    state.maxWorkers         = streamReadUInt8(streamId)
    state.trafficLimit       = streamReadUInt8(streamId)
    state.trafficTrailerSize = streamReadUInt8(streamId)
    state.engeMap            = streamReadUInt8(streamId) == 1
    state.missions = {}
    local count = streamReadUInt8(streamId)
    for _ = 1, count do
        local mName   = streamReadString(streamId)
        local mActive = streamReadUInt8(streamId) == 1
        state.missions[mName] = mActive
    end
    if g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager ~= nil then
        pcall(function()
            g_NachbarFelderManager:applySettingsState(state)
        end)
        print("NachbarFelder: [SETTINGS] Stand vom Server empfangen (maxWorkers=" ..
            tostring(state.maxWorkers) .. " trafficLimit=" .. tostring(state.trafficLimit) .. ")")
    end
end

-- ============================================================
-- Network-Events: Server → Client (Waypoint-Sync)
-- ============================================================

-- Client → Server: "Schick mir deine Wegpunkte"
NachbarFelderWaypointRequestEvent = {}
NachbarFelderWaypointRequestEvent_mt = Class(NachbarFelderWaypointRequestEvent, Event)
InitEventClass(NachbarFelderWaypointRequestEvent, "NachbarFelderWaypointRequestEvent")

function NachbarFelderWaypointRequestEvent.emptyNew()
    return Event.new(NachbarFelderWaypointRequestEvent_mt)
end
function NachbarFelderWaypointRequestEvent.new()
    return NachbarFelderWaypointRequestEvent.emptyNew()
end
function NachbarFelderWaypointRequestEvent:writeStream(streamId, connection)
end
function NachbarFelderWaypointRequestEvent:readStream(streamId, connection)
    if not g_currentMission:getIsServer() then return end
    local wps = (g_NachbarFelderManager ~= nil) and g_NachbarFelderManager.userTrafficWaypoints or {}
    connection:sendEvent(NachbarFelderWaypointSyncEvent.new(wps))
    print("NachbarFelder: [SYNC] " .. tostring(#wps) .. " Wegpunkte an Client gesendet")
    -- Settings gleich mitschicken (Build 67): der joinende Client bekommt
    -- den aktuellen server-autoritativen Einstellungs-Stand.
    if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.getSettingsState ~= nil then
        pcall(function()
            connection:sendEvent(NachbarFelderSettingsSyncEvent.new(
                g_NachbarFelderManager:getSettingsState()))
        end)
        print("NachbarFelder: [SETTINGS] Stand an Client gesendet")
    end
end

-- Server → Client: Wegpunkt-Liste
NachbarFelderWaypointSyncEvent = {}
NachbarFelderWaypointSyncEvent_mt = Class(NachbarFelderWaypointSyncEvent, Event)
InitEventClass(NachbarFelderWaypointSyncEvent, "NachbarFelderWaypointSyncEvent")

function NachbarFelderWaypointSyncEvent.emptyNew()
    return Event.new(NachbarFelderWaypointSyncEvent_mt)
end
function NachbarFelderWaypointSyncEvent.new(waypoints)
    local self = NachbarFelderWaypointSyncEvent.emptyNew()
    self.waypoints = waypoints or {}
    return self
end
function NachbarFelderWaypointSyncEvent:writeStream(streamId, connection)
    local wps = self.waypoints or {}
    streamWriteUInt16(streamId, #wps)
    for _, wp in ipairs(wps) do
        streamWriteFloat32(streamId, wp.x   or 0)
        streamWriteFloat32(streamId, wp.z   or 0)
        streamWriteFloat32(streamId, wp.ry  or 0)
        streamWriteUInt8(  streamId, wp.cat or 0)
        streamWriteString( streamId, wp.label or "")
    end
    -- Fahrzeugkategorien mitsyncen (Build 71): sonst zeigt die Client-GUI
    -- nach einem Rejoin wieder die Defaults statt der Server-Werte
    local c = (g_NachbarFelderManager ~= nil and g_NachbarFelderManager.vehicleCatEnabled) or {}
    streamWriteUInt8(streamId, (c.TRACTORSS           ~= false) and 1 or 0)
    streamWriteUInt8(streamId, (c.TRACTORSM           ~= false) and 1 or 0)
    streamWriteUInt8(streamId, (c.TRACTORSL           ~= false) and 1 or 0)
    streamWriteUInt8(streamId, (c.WHEELLOADERVEHICLES ~= false) and 1 or 0)
    streamWriteUInt8(streamId, (c.TELELOADERVEHICLES  ~= false) and 1 or 0)
end
function NachbarFelderWaypointSyncEvent:readStream(streamId, connection)
    if g_currentMission:getIsServer() then return end
    local count = streamReadUInt16(streamId)
    local wps = {}
    for i = 1, count do
        local x     = streamReadFloat32(streamId)
        local z     = streamReadFloat32(streamId)
        local ry    = streamReadFloat32(streamId)
        local cat   = streamReadUInt8(  streamId)
        local label = streamReadString( streamId)
        table.insert(wps, { x=x, z=z, ry=ry, cat=cat, label=label })
    end
    -- Fahrzeugkategorien (Build 71)
    local cats = {
        TRACTORSS           = streamReadUInt8(streamId) == 1,
        TRACTORSM           = streamReadUInt8(streamId) == 1,
        TRACTORSL           = streamReadUInt8(streamId) == 1,
        WHEELLOADERVEHICLES = streamReadUInt8(streamId) == 1,
        TELELOADERVEHICLES  = streamReadUInt8(streamId) == 1,
    }
    if g_NachbarFelderManager ~= nil then
        g_NachbarFelderManager.userTrafficWaypoints = wps
        g_NachbarFelderManager.vehicleCatEnabled    = cats
        pcall(function() g_NachbarFelderManager:updateWpHotspots() end)
        if g_NachbarFelderWaypointPage ~= nil then
            pcall(function() g_NachbarFelderWaypointPage:refreshWpInfo() end)
        end
        print("NachbarFelder: [SYNC] " .. tostring(#wps) .. " Wegpunkte vom Server empfangen")
    end
end

-- ============================================================
-- Input-Events: Nur Admin darf steuern
-- ============================================================
local function addPlayerActionEvents(self, superFunc, ...)
    superFunc(self, ...)

    -- Die Engine ruft das bei JEDEM Input-Kontextwechsel auf (Fahrzeug rein/
    -- raus, Menüs) - teils im Sekundentakt. Registrieren müssen wir jedes Mal
    -- (der Kontext wird vorher geleert), aber LOGGEN nur beim ersten Mal,
    -- sonst flutet es log.txt (Build 76).
    local logOnce = g_NachbarFelderManager ~= nil
        and g_NachbarFelderManager._inputLoggedOnce ~= true

    if logOnce then
        print("NachbarFelder: [INPUT] addPlayerActionEvents aufgerufen" ..
            " | player=" .. tostring(self.player ~= nil) ..
            " | isOwner=" .. tostring(self.player ~= nil and self.player.isOwner) ..
            " | g_client=" .. tostring(g_client ~= nil) ..
            " | NF_Action=" .. tostring(InputAction.NF_DELETE_HELPER ~= nil))
    end

    if self.player == nil or not self.player.isOwner then
        if logOnce then
            print("NachbarFelder: [INPUT] Abbruch – kein lokaler Owner-Spieler")
        end
        return
    end

    -- Auf dem reinen Dedicated-Server-Prozess gibt es kein lokales Input-System.
    -- g_client == nil bedeutet: dieser Prozess ist kein Client (nur Server).
    if g_client == nil then
        if logOnce then
            print("NachbarFelder: [INPUT] Abbruch – kein Client (Dedicated Server)")
        end
        return
    end

    -- InputActions müssen geladen sein (werden auf Dedicated Server nicht geladen)
    if InputAction.NF_DELETE_HELPER == nil then
        if logOnce then
            print("NachbarFelder: [INPUT] Abbruch – InputActions nicht geladen")
        end
        return
    end

    -- Kein isAdmin-Check: In Dedicated-MP ist isMasterUser auf dem Client-Prozess
    -- nicht gesetzt, obwohl der Nutzer der Server-Besitzer ist.
    -- isOwner=true (Zeile 128) reicht als Schutz – nur der lokale Spieler triggert Events.

    -- Lokalen Spieler speichern – g_currentMission.player ist in FS25 nil,
    -- aber hier haben wir ihn direkt über den PlayerInputComponent.
    g_NachbarFelderManager.localPlayer = self.player
    if logOnce then
        print("NachbarFelder: [INPUT] Registriere Action-Events...")
    end

    pcall(function()
        -- NF_DELETE_HELPER = Admin-Vollreinigung: aktive Fahrzeuge + Pool
        local _, idDel = g_inputBinding:registerActionEvent(
            InputAction.NF_DELETE_HELPER, g_NachbarFelderManager,
            g_NachbarFelderManager.deleteAllVehiclesAndPool, false, true, false, true)
        if idDel ~= nil then
            g_inputBinding:setActionEventTextVisibility(idDel, false)
        end
    end)

    if InputAction.NF_ADD_WAYPOINT ~= nil then
        local ok, err = pcall(function()
            local _, idAdd = g_inputBinding:registerActionEvent(
                InputAction.NF_ADD_WAYPOINT, g_NachbarFelderManager,
                g_NachbarFelderManager.onInputAddWaypoint, false, true, false, true)
            if idAdd ~= nil then
                g_inputBinding:setActionEventTextVisibility(idAdd, false)
                if logOnce then
                    -- Build 134: keine Taste nennen - die Belegung steht im Spielerprofil
                    -- und weicht oft vom modDesc-Standard ab
                    print("NachbarFelder: [INPUT] NF_ADD_WAYPOINT registriert")
                end
            else
                print("NachbarFelder: [INPUT] NF_ADD_WAYPOINT registerActionEvent gab nil zurueck")
            end
        end)
        if not ok then
            print("NachbarFelder: [INPUT] NF_ADD_WAYPOINT Fehler: " .. tostring(err))
        end
    elseif logOnce then
        print("NachbarFelder: [INPUT] InputAction.NF_ADD_WAYPOINT ist nil!")
    end

    if InputAction.NF_REMOVE_WAYPOINT ~= nil then
        pcall(function()
            local _, idRem = g_inputBinding:registerActionEvent(
                InputAction.NF_REMOVE_WAYPOINT, g_NachbarFelderManager,
                g_NachbarFelderManager.onInputRemoveWaypoint, false, true, false, true)
            if idRem ~= nil then
                g_inputBinding:setActionEventTextVisibility(idRem, false)
            end
        end)
    end

    if InputAction.NF_MANAGE_WAYPOINTS ~= nil then
        pcall(function()
            local _, idMgr = g_inputBinding:registerActionEvent(
                InputAction.NF_MANAGE_WAYPOINTS, g_NachbarFelderManager,
                g_NachbarFelderManager.onInputManageWaypoints, false, true, false, true)
            if idMgr ~= nil then
                g_inputBinding:setActionEventTextVisibility(idMgr, false)
            end
        end)
    end

    if logOnce then
        print("NachbarFelder: [INPUT] Registrierung abgeschlossen")
        if g_NachbarFelderManager ~= nil then
            g_NachbarFelderManager._inputLoggedOnce = true
        end
    end
end

-- ============================================================
-- initialize(): Wird auf Client via OWN_PLAYER_ENTERED gerufen.
-- Im Dedicated-MP übernimmt der Server (loadMap) die Logik.
-- Hier nur: Settings-Seite für den Spieler anzeigen.
-- ============================================================
local function initialize(nachbarFelder)
    local isAdmin = g_currentMission ~= nil and
        (g_currentMission:getIsServer() or g_currentMission.isMasterUser)

    if isAdmin then
        print("NachbarFelder: Admin-Client erkannt (OWN_PLAYER_ENTERED)")
    else
        print("NachbarFelder: Kein Admin, nur UI wird geladen")
    end

    -- Settings-Seite immer initialisieren (auch für Nicht-Admin)
    if g_NachbarFelderManager.initializeSettingsPage ~= nil then
        g_NachbarFelderManager:initializeSettingsPage()
    end

    -- Wegpunkt-Seite als eigenen Settings-Tab einbetten
    if NachbarFelderWaypointPage ~= nil then
        local wpPage = NachbarFelderWaypointPage.new(g_NachbarFelderManager)
        g_NachbarFelderWaypointPage = wpPage
        wpPage:registerAndInject()
    end

    -- Karten Draw-Hook installieren: InGameMenuMapFrame erst nach OWN_PLAYER_ENTERED verfügbar
    if g_NachbarFelderManager.setupMapDrawHook ~= nil then
        g_NachbarFelderManager:setupMapDrawHook()
    end

    -- Im Dedicated-MP: Wegpunkte vom Server anfordern (Server ist autoritativ).
    -- In SP / Local-Host: getIsServer()=true → loadWaypoints() lief schon in loadMap().
    if not g_currentMission:getIsServer() then
        pcall(function()
            g_client:getServerConnection():sendEvent(NachbarFelderWaypointRequestEvent.new())
        end)
    end
end

-- ============================================================
-- init(): Modul-Einstieg
-- ============================================================
local function init()
    source(modDirectory .. "NachbarFelderManager.lua")
    source(modDirectory .. "NachbarFelderWorker.lua")
    source(modDirectory .. "NachbarFelderSettingsPage.lua")
    source(modDirectory .. "NachbarFelderUIHelper.lua")
    source(modDirectory .. "NachbarFelderWaypointPage.lua")

    g_localTest = nil

    local nachbarFelder = NachbarFelderManager.new()
    g_NachbarFelderManager = nachbarFelder

    -- Mod-Event-Listener JETZT registrieren (nicht erst in initialize),
    -- damit loadMap/update/deleteMap auch auf dem Dedicated-Server feuern!
    addModEventListener(nachbarFelder)

    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, addPlayerActionEvents)

    g_specializationManager:addSpecialization(
        "NachbarFelderManager",
        "NachbarFelderManager",
        Utils.getFilename("NachbarFelderManager.lua", modDirectory),
        nil
    )

    g_specializationManager:addSpecialization(
        "NachbarFelderWorker",
        "NachbarFelderWorker",
        Utils.getFilename("NachbarFelderWorker.lua", modDirectory),
        nil
    )

    local allVehicleTypes = g_vehicleTypeManager:getTypes()
    for typeName, typeEntry in pairs(allVehicleTypes) do
        if SpecializationUtil.hasSpecialization(AIVehicle, typeEntry.specializations) then
            g_vehicleTypeManager:addSpecialization(typeName, g_currentModName .. ".NachbarFelderWorker")
        end
    end

    -- OWN_PLAYER_ENTERED: für Client-seitige UI (Settings-Seite)
    g_messageCenter:subscribeOneshot(MessageType.OWN_PLAYER_ENTERED, initialize, g_NachbarFelderManager)
end

init()

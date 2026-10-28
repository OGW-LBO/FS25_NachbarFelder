local modDirectory = g_currentModDirectory
local modName = g_currentModName

-- ============================================================
-- Debug-Log
-- ============================================================
-- Alle Log-Ausgaben laufen ueber NachbarFelderLog.print. Ohne Debug-Log
-- kommen nur Zeilen durch, die einen der Begriffe aus NF_LOG_IMMER enthalten
-- (Warnungen, Fehler, Startzeile). Umschaltbar in den Einstellungen (Admin,
-- wird synchronisiert) oder per logLevel=2 in der Server-Konfig.
NachbarFelderLog = { debug = false }
local NF_LOG_IMMER = { "WARNUNG", "Warnung", "Fehler", "FEHLER", "fehlgeschlagen",
                       "nicht verfuegbar", "loadMap auf", "Debug-Log" }
function NachbarFelderLog.print(msg)
    if NachbarFelderLog.debug then
        print(msg)
        return
    end
    local text = tostring(msg)
    for i = 1, #NF_LOG_IMMER do
        if string.find(text, NF_LOG_IMMER[i], 1, true) ~= nil then
            print(text)
            return
        end
    end
end
local print = NachbarFelderLog.print

-- Alter Mod-Name FS25_NachbarFelder: fehlt eine Datei im eigenen modSettings-Ordner,
-- wird sie aus dem alten gelesen. Gespeichert wird immer im eigenen Ordner.
local NF_EIGENER_ORDNER = g_currentModSettingsDirectory
local NF_ALTER_ORDNERNAME = "FS25_NachbarFelder"
function NachbarFelderLesePfad(pfad)
    if pfad == nil or NF_EIGENER_ORDNER == nil or fileExists(pfad) then return pfad end
    if string.sub(pfad, 1, #NF_EIGENER_ORDNER) ~= NF_EIGENER_ORDNER then return pfad end
    local basis = string.match(NF_EIGENER_ORDNER, "^(.*[/\\])[^/\\]+[/\\]$")
    if basis == nil then return pfad end
    local alt = basis .. NF_ALTER_ORDNERNAME .. "/" .. string.sub(pfad, #NF_EIGENER_ORDNER + 1)
    if alt ~= pfad and fileExists(alt) then
        print("NachbarFelder: " .. alt .. " aus dem alten Ordner gelesen")
        return alt
    end
    return pfad
end

-- ============================================================
-- Network-Events: Client an Server
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
        -- nur von Admin-Verbindungen annehmen
        if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Delete-Event abgelehnt - Absender ist kein Admin")
            return
        end
        -- aktive Fahrzeuge und Pool-Fahrzeuge entfernen
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

-- Client an Server: Wegpunkt-Änderung (Setzen/Löschen/Typ/Fahrzeugkategorien).
-- Auf dem Dedi gehört die Wegpunkt-Datei dem Server; rein lokale Änderungen am
-- Client würden beim nächsten Sync überschrieben.
NachbarFelderWaypointEditEvent = {}
NachbarFelderWaypointEditEvent_mt = Class(NachbarFelderWaypointEditEvent, Event)
InitEventClass(NachbarFelderWaypointEditEvent, "NachbarFelderWaypointEditEvent")

NachbarFelderWaypointEditEvent.OP_ADD        = 1
NachbarFelderWaypointEditEvent.OP_REMOVELAST = 2
NachbarFelderWaypointEditEvent.OP_DELETE     = 3
NachbarFelderWaypointEditEvent.OP_SETCAT     = 4
NachbarFelderWaypointEditEvent.OP_VEHCAT     = 5
-- wie OP_ADD, setzt den Punkt aber direkt als Spawnpunkt; spart ein zweites
-- SETCAT-Event, dessen Index der Client nicht sicher kennt
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
        -- nur Admin-Verbindungen; der Stream muss vor dem Abbruch
        -- vollstaendig gelesen sein
        if g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Wegpunkt-Edit abgelehnt - Absender ist kein Admin")
            return
        end
        g_NachbarFelderManager:applyWaypointEdit(self.op, self.a, self.b, self.c)
    end
end

-- ============================================================
-- Network-Events: Settings-Sync
-- ============================================================
-- Wie beim Wegpunkt-Editing: der Client schickt die Aenderung, der Server
-- wendet sie an, merkt sie fuers Savegame vor und verteilt den kompletten
-- Stand an alle Clients.

-- Client an Server: eine Einstellung aendern (Name + Zahlwert, bool als 0/1)
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
        -- nur Admin-Verbindungen; Stream ist bereits komplett gelesen
        if g_NachbarFelderManager.getIsConnectionAdmin ~= nil
           and not g_NachbarFelderManager:getIsConnectionAdmin(connection) then
            print("NachbarFelder: [ADMIN] Settings-Edit abgelehnt - Absender ist kein Admin")
            return
        end
        g_NachbarFelderManager:applySettingEdit(self.settingName, self.value)
    end
end

-- Server an Client: kompletter Einstellungs-Stand
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
    -- bools als UInt8 0/1; Reihenfolge muss zu readStream passen
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
    -- Helfer-Farm, damit Clients die Kartensymbole der Nachbarn ausblenden; 0 = unbekannt
    streamWriteUInt8(streamId, math.max(0, math.min(255, st.helferFarmId or 0)))
    streamWriteUInt8(streamId, (st.debugLog == true) and 1 or 0)
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
    state.helferFarmId = streamReadUInt8(streamId)
    state.debugLog     = streamReadUInt8(streamId) == 1
    if g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager ~= nil then
        g_NachbarFelderManager:applySettingsState(state)
        print("NachbarFelder: [SETTINGS] Stand vom Server empfangen (maxWorkers=" ..
            tostring(state.maxWorkers) .. " trafficLimit=" .. tostring(state.trafficLimit) .. ")")
    end
end

-- ============================================================
-- Network-Events: Wegpunkt-Sync
-- ============================================================

-- Client an Server: Wegpunkte anfordern
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
    -- beim Join gleich auch die Einstellungen des Servers mitschicken
    if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.getSettingsState ~= nil then
        connection:sendEvent(NachbarFelderSettingsSyncEvent.new(
            g_NachbarFelderManager:getSettingsState()))
        print("NachbarFelder: [SETTINGS] Stand an Client gesendet")
    end
end

-- Server an Client: Wegpunkt-Liste und Fahrzeugkategorien
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
    -- Fahrzeugkategorien mitsenden, sonst zeigt die Client-GUI nach einem
    -- Rejoin die Standardwerte statt der Server-Werte
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
        if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.updateWpHotspots ~= nil then g_NachbarFelderManager:updateWpHotspots() end
        if g_NachbarFelderWaypointPage ~= nil then
            if g_NachbarFelderWaypointPage ~= nil and g_NachbarFelderWaypointPage.refreshWpInfo ~= nil then g_NachbarFelderWaypointPage:refreshWpInfo() end
        end
        print("NachbarFelder: [SYNC] " .. tostring(#wps) .. " Wegpunkte vom Server empfangen")
    end
end

-- ============================================================
-- Input-Events
-- ============================================================
local function addPlayerActionEvents(self, superFunc, ...)
    superFunc(self, ...)

    -- Die Engine ruft das bei jedem Input-Kontextwechsel auf (Fahrzeug, Menüs),
    -- teils im Sekundentakt. Registriert wird jedes Mal, da der Kontext vorher
    -- geleert wird; geloggt nur beim ersten Aufruf.
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

    -- reiner Dedicated-Server-Prozess: kein lokales Input-System
    if g_client == nil then
        if logOnce then
            print("NachbarFelder: [INPUT] Abbruch – kein Client (Dedicated Server)")
        end
        return
    end

    -- InputActions fehlen, wenn die modDesc-Actions nicht geladen wurden (Dedi)
    if InputAction.NF_DELETE_HELPER == nil then
        if logOnce then
            print("NachbarFelder: [INPUT] Abbruch – InputActions nicht geladen")
        end
        return
    end

    -- Bewusst kein isAdmin-Check: im Dedicated-MP ist isMasterUser auf dem Client
    -- hier noch nicht gesetzt. Die Rechte prüft der Server beim Empfang der Events.

    -- g_currentMission.player ist in FS25 nil, daher den Spieler hier merken
    g_NachbarFelderManager.localPlayer = self.player
    if logOnce then
        print("NachbarFelder: [INPUT] Registriere Action-Events...")
    end

    -- entfernt aktive Fahrzeuge und Pool
    local _, idDel = g_inputBinding:registerActionEvent(
        InputAction.NF_DELETE_HELPER, g_NachbarFelderManager,
        g_NachbarFelderManager.deleteAllVehiclesAndPool, false, true, false, true)
    if idDel ~= nil then
        g_inputBinding:setActionEventTextVisibility(idDel, false)
    end

    if InputAction.NF_ADD_WAYPOINT ~= nil then
        local function schritt()
            local _, idAdd = g_inputBinding:registerActionEvent(
                InputAction.NF_ADD_WAYPOINT, g_NachbarFelderManager,
                g_NachbarFelderManager.onInputAddWaypoint, false, true, false, true)
            if idAdd ~= nil then
                g_inputBinding:setActionEventTextVisibility(idAdd, false)
                if logOnce then
                    -- keine Taste nennen: die Belegung steht im Spielerprofil
                    -- und weicht oft vom modDesc-Standard ab
                    print("NachbarFelder: [INPUT] NF_ADD_WAYPOINT registriert")
                end
            else
                print("NachbarFelder: [INPUT] NF_ADD_WAYPOINT registerActionEvent gab nil zurueck")
            end
        end
        schritt()
    elseif logOnce then
        print("NachbarFelder: [INPUT] InputAction.NF_ADD_WAYPOINT ist nil!")
    end

    if InputAction.NF_REMOVE_WAYPOINT ~= nil then
        local _, idRem = g_inputBinding:registerActionEvent(
            InputAction.NF_REMOVE_WAYPOINT, g_NachbarFelderManager,
            g_NachbarFelderManager.onInputRemoveWaypoint, false, true, false, true)
        if idRem ~= nil then
            g_inputBinding:setActionEventTextVisibility(idRem, false)
        end
    end

    if InputAction.NF_MANAGE_WAYPOINTS ~= nil then
        local _, idMgr = g_inputBinding:registerActionEvent(
            InputAction.NF_MANAGE_WAYPOINTS, g_NachbarFelderManager,
            g_NachbarFelderManager.onInputManageWaypoints, false, true, false, true)
        if idMgr ~= nil then
            g_inputBinding:setActionEventTextVisibility(idMgr, false)
        end
    end

    if logOnce then
        print("NachbarFelder: [INPUT] Registrierung abgeschlossen")
        if g_NachbarFelderManager ~= nil then
            g_NachbarFelderManager._inputLoggedOnce = true
        end
    end
end

-- ============================================================
-- Client-Initialisierung
-- ============================================================
-- Läuft über OWN_PLAYER_ENTERED und baut nur die UI auf; die Spiellogik
-- startet serverseitig in loadMap.
local function initialize(nachbarFelder)
    local isAdmin = g_currentMission ~= nil and
        (g_currentMission:getIsServer() or g_currentMission.isMasterUser)

    if isAdmin then
        print("NachbarFelder: Admin-Client erkannt (OWN_PLAYER_ENTERED)")
    else
        print("NachbarFelder: Kein Admin, nur UI wird geladen")
    end

    -- auch für Nicht-Admins (Controls sind dann gesperrt)
    if g_NachbarFelderManager.initializeSettingsPage ~= nil then
        g_NachbarFelderManager:initializeSettingsPage()
    end

    -- Wegpunkt-Seite als eigener Tab im Ingame-Menü
    if NachbarFelderWaypointPage ~= nil then
        local wpPage = NachbarFelderWaypointPage.new(g_NachbarFelderManager)
        g_NachbarFelderWaypointPage = wpPage
        wpPage:registerAndInject()
    end

    -- InGameMenuMapFrame existiert erst nach OWN_PLAYER_ENTERED
    if g_NachbarFelderManager.setupMapDrawHook ~= nil then
        g_NachbarFelderManager:setupMapDrawHook()
    end

    -- Reiner Client: Wegpunkte beim Server anfordern. In SP und beim Host
    -- wurden sie bereits in loadMap geladen.
    if not g_currentMission:getIsServer() then
        g_client:getServerConnection():sendEvent(NachbarFelderWaypointRequestEvent.new())
    end
end

-- ============================================================
-- Modul-Einstieg
-- ============================================================
local function init()
    source(modDirectory .. "NachbarFelderManager.lua")
    NachbarFelderManager.modDirectory = modDirectory   -- fuer help/helpLine.xml
    source(modDirectory .. "NachbarFelderWorker.lua")
    source(modDirectory .. "NachbarFelderSettingsPage.lua")
    source(modDirectory .. "NachbarFelderUIHelper.lua")
    source(modDirectory .. "NachbarFelderWaypointPage.lua")

    g_localTest = nil

    local nachbarFelder = NachbarFelderManager.new()
    g_NachbarFelderManager = nachbarFelder

    -- hier registrieren, nicht erst in initialize: OWN_PLAYER_ENTERED kommt auf
    -- dem Dedicated Server nie, loadMap/update/deleteMap muessen dort aber laufen
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

    -- clientseitige UI erst, wenn der eigene Spieler da ist
    g_messageCenter:subscribeOneshot(MessageType.OWN_PLAYER_ENTERED, initialize, g_NachbarFelderManager)
end

init()

NachbarFelderWorker = {}

-- Normale Ausgaben nur im Debug-Log, Warnungen/Fehler immer (siehe NachbarFelder.lua)
local print = NachbarFelderLog.print

local NachbarFelderWorker_class = Class(NachbarFelderWorker)

function NachbarFelderWorker.new(vehiclesToLoad, mission, status, fieldId, x, y, z, angle)
    local self = setmetatable({}, NachbarFelderWorker_class)
    self.vehiclesToLoad = vehiclesToLoad
    self.mission = mission
    self.status = status
    self.fieldId = fieldId
    self.posX = x
    self.posY = y
    self.posZ = z
    self.angle = angle
    self.removeVehicleInfo = {}
    self.needTimer = false
    self.isBlocked = 1
    self.lastKnownPos = 0
    return self
end

function NachbarFelderWorker.prerequisitesPresent(specializations)
    return true
end

function NachbarFelderWorker.registerEventListeners(vehicleType)
    SpecializationUtil.registerEventListener(vehicleType, "onTargetReached",    NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onAIJobFinished",    NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onAIJobVehicleBlock",NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onDelete",           NachbarFelderWorker)
end

-- ============================================================
-- Standort-Rettung
-- Abweisung und "nicht erreichbar" haben meist dieselbe Ursache:
-- der Standort taugt nicht, nicht das Ziel. Setzt das Fahrzeug auf
-- den naechsten Punkt der KI-Strasse (Radius 150 m), sonst zum Shop.
-- ============================================================
local function nfRoadSnap(tt, mgr, veh0)
    local vx, _, vz = getWorldTranslation(veh0.rootNode)
    -- Mindestens 25 m versetzen: der naechste Strassenpunkt hilft oft nicht,
    -- wenn der Platz selbst eine Sackgasse fuer die Pfadsuche ist.
    -- Am Parkpunkt steht das Fahrzeug absichtlich neben der Strasse,
    -- dort reicht der naechste Strassenpunkt.
    local minAbstand = 25
    if mgr.getIsParkpunkt ~= nil
       and mgr:getIsParkpunkt(tt, tt.waypointIdx) then
        minAbstand = 0
    end
    -- KI-Strassen sind Einbahn-Splines: Spur in Richtung Ziel waehlen. Ein um
    -- 180 Grad gedrehtes Fahrzeug steht gegen die Fahrtrichtung und wird sofort
    -- wieder abgewiesen.
    local wdx = (tt.patrolTargetX or vx) - vx
    local wdz = (tt.patrolTargetZ or vz) - vz
    local rx, rz, rry, rdist = mgr:getRoadPointInRichtung(vx, vz, 150, minAbstand, wdx, wdz)
    local wohin = "weiter vorn auf die KI-Strasse"
    if rx == nil then
        rx, rz = mgr:getShopPosition()
        rry    = mgr:getNfSpawnRotY()
        rdist  = MathUtil.vector2Length(vx - rx, vz - rz)
        wohin  = "zurueck zum Shop"
    end
    if rx == nil then return end
    if mgr:isSpotBlockedByAnyVehicle(rx, rz, 8, veh0) then
        print(string.format("NachbarFelder: [TRAFFIC] GOTO kommt nicht weg, Ausweichplatz %.0f m" ..
            " weiter ist belegt - bleibt stehen", rdist))
        return
    end
    local ry = rry or 0
    g_currentMission:teleportVehicle(veh0, rx, rz, ry)
    tt.roadSnapped = true
    -- rdist ist der Versatz, nicht der Abstand zur Strasse
    print(string.format("NachbarFelder: [TRAFFIC] GOTO kommt nicht weg - Fahrzeug" ..
        " %.0f m %s gesetzt", rdist, wohin))
end

-- Naechsten Wegpunkt (bis 30 m) als ungeeigneten Startplatz vormerken.
-- Nicht am Shop, der muss als Spawnplatz nutzbar bleiben.
local function nfMarkStartPlaceBad(tt, mgr, veh)
    if veh == nil or veh.rootNode == nil or mgr.registerWaypointStartFail == nil then
        return
    end
    local vx, _, vz = getWorldTranslation(veh.rootNode)
    local sX, sZ = mgr:getShopPosition()
    if MathUtil.vector2Length(vx - sX, vz - sZ) < 15 then
        return
    end
    local nahIdx, nahDist = nil, nil
    for idx, w in ipairs(tt.waypoints or {}) do
        local d = MathUtil.vector2Length(vx - (w[1] or 0), vz - (w[2] or 0))
        if nahDist == nil or d < nahDist then
            nahIdx, nahDist = idx, d
        end
    end
    if nahIdx ~= nil and nahDist < 30 then
        mgr:registerWaypointStartFail(nahIdx)
    end
end

-- ============================================================
-- onAIJobFinished: GOTO beendet, Folgezustand bestimmen (nur Server)
-- ============================================================
function NachbarFelderWorker:onAIJobFinished(...)
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager == nil then return end

    local tt = g_NachbarFelderManager:getCorrectobject(self)
    if tt == nil or tt.vehiclesToLoad == nil then
        -- fremdes KI-Fahrzeug
        return
    end

    local vehicle = tt.vehiclesToLoad[1]
    tt.vehicle = vehicle

    if tt.status == 60 then
        -- Status 60 = Rueckfahrt. gotoStartedAt == nil heisst: GOTO noch nicht
        -- gestartet (onAIFieldWorkerEnd), das uebernimmt update().
        if tt.gotoStartedAt ~= nil then
            local dist = 99999
            -- Shop-Spawnplatz des Spiels (bei Filiallieferungen der Lieferort)
            local shopX, shopZ = g_NachbarFelderManager:getShopPosition()
            local veh = tt.vehiclesToLoad[1]
            if veh ~= nil and veh.rootNode ~= nil then
                local x, _, z = getWorldTranslation(veh.rootNode)
                dist = MathUtil.vector2Length(x - shopX, z - shopZ)
            end
            tt.gotoStartedAt = nil

            if dist < 60 then
                print("NachbarFelder: Helfer am Shop angekommen, wird entfernt (Feld " ..
                    tostring(tt.fieldId) .. ")")
                tt.gotoRetryCount = nil
                tt.lastReturnDist = nil
                tt.status = 100
                tt.needTimer = true
            else
                -- Die KI hangelt sich oft ueber mehrere GOTOs vom Feld auf die
                -- Strasse. Weiterfahren, solange sie mehr als 5 m naeher kommt;
                -- ohne Fortschritt oder nach 8 Versuchen an Ort und Stelle entfernen.
                tt.gotoRetryCount = (tt.gotoRetryCount or 0) + 1
                local fortschritt = (tt.lastReturnDist == nil) or (dist < tt.lastReturnDist - 5)
                tt.lastReturnDist = dist
                if fortschritt and tt.gotoRetryCount < 8 then
                    print("NachbarFelder: Rueckfahrt laeuft - noch " .. tostring(math.floor(dist)) ..
                        "m zum Shop (Versuch " .. tostring(tt.gotoRetryCount) .. ", Feld " ..
                        tostring(tt.fieldId) .. ") - faehrt weiter")
                    -- Status bleibt 60, update() startet die naechste Rueckfahrt
                    tt.needTimer = true
                else
                    print("NachbarFelder: Rueckfahrt steckt bei " .. tostring(math.floor(dist)) ..
                        "m fest (Versuch " .. tostring(tt.gotoRetryCount) ..
                        ") - Helfer wird an Ort und Stelle entfernt (Feld " .. tostring(tt.fieldId) .. ")")
                    -- Kein Teleport zum Shop: das Fahrzeug wird ohnehin gleich entfernt.
                    tt.gotoRetryCount = nil
                    tt.lastReturnDist = nil
                    tt.status = 100
                    tt.needTimer = true
                end
            end
        end

    elseif tt.status == 2 then
        -- parkt, Park-Timer laeuft in Manager:update

    elseif tt.status >= 3 and tt.status ~= 60 then
        if tt.vehiclesToLoad ~= nil and tt.status < 99 then
            tt.status = 100
            tt.needTimer = true
        end

    elseif tt.status == 1 then
        -- Abschlussgrund ueber die AIMessage bestimmen (driveToField merkt sie
        -- per job.stop-Wrapper in tt.lastStopMsg). Ohne Message zaehlt die Laufzeit.
        local stopMsg = tt.lastStopMsg
        tt.lastStopMsg = nil

        -- Von der Mod selbst gestoppt (Watchdog, Cleanup, Admin-Taste): der Stopper
        -- setzt den Folgezustand. Hier zu klassifizieren gaebe falsche WP-Strafen
        -- und eine doppelte Zielwahl.
        if stopMsg == "AIMessageSuccessStoppedByUser" then
            tt.fieldGotoStartedAt = nil
            return
        end

        local msgSuccess  = stopMsg == "AIMessageSuccessFinishedJob"
        local msgPathFail = stopMsg == "AIMessageErrorNoPathFound"
                         or stopMsg == "AIMessageErrorNotReachable"

        -- Sollte nicht vorkommen: getPricePerMs() = 0, AIJob:updateCost() bucht
        -- nichts ab und prueft keinen Kontostand. Falls doch, wie Abbruch behandeln.
        if stopMsg == "AIMessageErrorOutOfMoney" then
            print("NachbarFelder: GOTO wegen Geldmangel gestoppt (unerwartet - " ..
                "Jobs sind kostenfrei) - Fahrzeug wird entfernt (Feld " ..
                tostring(tt.fieldId) .. ")")
            tt.status    = 100
            tt.needTimer = true
            return
        end

        local gotoOk = true
        if tt.fieldGotoStartedAt ~= nil then
            local gotoElapsed = g_time - tt.fieldGotoStartedAt
            -- instantReject: Job sofort abgewiesen, die Pfadsuche hat nie begonnen
            -- pathFail:      Pfadsuche lief und fand keinen Weg zum Ziel
            local instantReject = false
            local pathFail      = false
            if msgSuccess then
                -- angekommen, auch bei kurzer Fahrt (nahes Ziel)
            elseif msgPathFail then
                -- Auch mit Message entscheidet die Laufzeit: eine echte Pfadsuche
                -- dauert eine bis mehrere Sekunden. NotReachable nach ~50-70 ms heisst,
                -- an der Fahrzeugposition liegt kein Navmesh-Knoten.
                instantReject = gotoElapsed < 1500
                pathFail      = not instantReject
            elseif gotoElapsed < 5000 then
                -- keine verwertbare Message, nur die Laufzeit
                instantReject = gotoElapsed < 1500
                pathFail      = not instantReject
            end
            if instantReject or pathFail then
                gotoOk = false
                local msgInfo = stopMsg ~= nil and (", " .. stopMsg) or ""
                if tt.isPatrol then
                    if instantReject then
                        -- Sofort abgewiesen (< 1500 ms). Fahrzeug bleibt stehen und
                        -- bekommt ein neues Ziel. Nach drei Abweisungen in Folge liegt
                        -- es am Standort: Startplatz vormerken, an Ort und Stelle in den Pool.
                        -- Diagnose: Position und Anbaugeraet loggen, um Gelaende- und
                        -- Gespann-Probleme zu unterscheiden.
                        local v0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                        local impl = tt.vehiclesToLoad and tt.vehiclesToLoad[2]
                        local vx, vz = 0, 0
                        if v0 ~= nil and v0.rootNode ~= nil then
                            local x, _, z = getWorldTranslation(v0.rootNode)
                            vx, vz = x, z
                        end
                        local nahIdx, nahDist = nil, nil
                        for i, w in ipairs(tt.waypoints or {}) do
                            local d = math.sqrt((vx - (w[1] or 0))^2 + (vz - (w[2] or 0))^2)
                            if nahDist == nil or d < nahDist then
                                nahIdx, nahDist = i, d
                            end
                        end
                        local implName = "ohne Anbaugeraet"
                        if impl ~= nil then
                            local f = impl.configFileName or ""
                            implName = "mit " .. (string.match(f, "[^/\\]+$") or f)
                        end

                        -- Zustand des Gespanns, um Unterschiede zu einem von Hand
                        -- gestarteten Fahrauftrag zu erkennen
                        local zusatz = ""
                        local nImpl = 0
                        if v0 ~= nil and v0.getAttachedImplements ~= nil then
                            nImpl = #v0:getAttachedImplements()
                        end
                        local aw, al = 0, 0
                        if v0 ~= nil and v0.getAIAgentSize ~= nil then
                            aw, al = v0:getAIAgentSize()
                        end
                        local hatAgent = "Agent-nein"
                        if v0 ~= nil and v0.spec_aiDrivable ~= nil
                           and v0.spec_aiDrivable.agentId ~= nil then
                            hatAgent = "Agent-ja"
                        end
                        zusatz = (" | angehaengt %d | Agent %.1fx%.1fm %s")
                            :format(nImpl, aw or 0, al or 0, hatAgent)
                        -- Abweisung dem Ladeplatz und dem Anbaugeraet anrechnen
                        -- (Geraetesperre erst nach 3x an 2 Stellen, siehe Manager)
                        if g_NachbarFelderManager ~= nil and g_NachbarFelderManager.merkeSpawnFehlschlag ~= nil then
                            g_NachbarFelderManager:merkeSpawnFehlschlag(tt, vx, vz, "Verkehr sofort abgewiesen")
                        end
                        if impl ~= nil and impl.configFileName ~= nil and g_NachbarFelderManager ~= nil
                           and g_NachbarFelderManager.merkeVerkehrGeraetAbweisung ~= nil then
                            g_NachbarFelderManager:merkeVerkehrGeraetAbweisung(impl.configFileName, vx, vz)
                        end
                        print(("NachbarFelder: [TRAFFIC][DIAG] GOTO-Abweisung bei x=%d z=%d" ..
                            " | naechster WP%s (%sm) | Ziel WP%s | %s | %dms%s%s"):format(
                            math.floor(vx), math.floor(vz),
                            tostring(nahIdx or "?"),
                            nahDist ~= nil and tostring(math.floor(nahDist)) or "?",
                            tostring(tt.patrolDestIdx or "?"),
                            implName, math.floor(gotoElapsed), msgInfo, zusatz))

                        -- Keine Ziel-Strafe bei Sofort-Abweisung: ein Fahrzeug neben der
                        -- KI-Strasse wuerde sonst nacheinander alle Wegpunkte sperren.
                        -- Ziele sperrt nur der pathFail-Zweig.
                        tt.gotoRejects = (tt.gotoRejects or 0) + 1
                        local mgr  = g_NachbarFelderManager
                        local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]

                        -- Schon beim ersten Fehlschlag auf die KI-Strasse versetzen;
                        -- vom alten Standort aus klappt ein neuer Versuch selten.
                        if tt.gotoRejects >= 1 and not tt.roadSnapped
                           and veh0 ~= nil and veh0.rootNode ~= nil
                           and mgr.getNearestRoadPoint ~= nil then
                            nfRoadSnap(tt, mgr, veh0)
                        end

                        if tt.gotoRejects < 3 and tt.waypoints ~= nil and #tt.waypoints >= 2 then
                            local oldDest = tt.patrolDestIdx or 1
                            local newDest = oldDest
                            if mgr.pickPatrolWaypoint ~= nil then
                                -- Bezugspunkt ist das Fahrzeug, nicht das unerreichte Ziel
                                newDest = mgr:pickPatrolWaypoint(tt.waypoints, oldDest, mgr:getWorkerPos(tt)) or oldDest
                            end
                            print("NachbarFelder: [TRAFFIC] Ziel WP" .. tostring(oldDest) ..
                                " sofort abgewiesen - Fahrzeug bleibt stehen, neues Ziel WP" ..
                                tostring(newDest) .. " (Versuch " .. tostring(tt.gotoRejects) .. "/3, " ..
                                mgr:getWorkerName(tt) .. ")")
                            local wp = tt.waypoints[newDest]
                            tt.patrolDestIdx = newDest
                            tt.patrolTargetX = wp[1]
                            tt.patrolTargetZ = wp[2]
                            tt.fieldGotoStartedAt = nil
                            tt.patrolWdLastX      = nil
                            tt.patrolWdStage      = nil
                            tt.status    = 1
                            tt.needTimer = true
                            return
                        end

                        -- Drei Ziele in Folge abgewiesen: der Standort taugt nicht.
                        local veh = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                        nfMarkStartPlaceBad(tt, mgr, veh)
                        if veh ~= nil then
                            local fname = veh.configFileName or ""
                            local base  = string.match(fname, "[^/\\]+$") or fname
                            print("NachbarFelder: [TRAFFIC] " .. base ..
                                " - drei Ziele in Folge sofort abgewiesen, Fahrzeug geht an Ort und" ..
                                " Stelle in den Pool (bei vollem Pool: entfernt).")
                        end
                        -- Pool statt Loeschen: jedes neu geladene Modell kostet den Server
                        -- mehrere hundert Millisekunden. sleepPatrolEntry laesst das
                        -- Fahrzeug stehen, wo es ist.
                        tt.gotoRejects        = nil
                        tt.roadSnapped        = nil
                        tt.fieldGotoStartedAt = nil
                        tt.status             = 100
                        tt.needTimer          = true
                        return
                    else
                        -- Pfadsuche lief, fand keinen Weg. Jede Suche kostet viel CPU;
                        -- scheitern mehrere Ziele hintereinander, ist der Standort schuld.
                        local mgr  = g_NachbarFelderManager
                        local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                        tt.pathFails = (tt.pathFails or 0) + 1

                        -- Ziel nur beim ersten Fehlschlag in Folge bestrafen (2x = Sperre
                        -- fuer die Session), sonst sperrt ein festsitzendes Fahrzeug
                        -- Wegpunkte fuer alle anderen.
                        if tt.pathFails == 1 and mgr.registerWaypointFail ~= nil then
                            mgr:registerWaypointFail(tt.patrolDestIdx)
                        end

                        if tt.pathFails == 2 and not tt.roadSnapped
                           and veh0 ~= nil and veh0.rootNode ~= nil
                           and mgr.getNearestRoadPoint ~= nil then
                            nfRoadSnap(tt, mgr, veh0)
                        end

                        if tt.pathFails >= 3 then
                            nfMarkStartPlaceBad(tt, mgr, veh0)
                            print("NachbarFelder: [TRAFFIC] drei Ziele in Folge nicht erreichbar (" ..
                                mgr:getWorkerName(tt) .. ") - Fahrzeug geht in den Pool" ..
                                " statt weitere Ziele durchzuprobieren.")
                            tt.pathFails          = nil
                            tt.roadSnapped        = nil
                            tt.fieldGotoStartedAt = nil
                            tt.status             = 100
                            tt.needTimer          = true
                            return
                        end

                        local nWps = tt.waypoints ~= nil and #tt.waypoints or 0
                        if nWps >= 1 then
                            local oldDest = tt.patrolDestIdx or 1
                            local newDest = oldDest
                            if g_NachbarFelderManager.pickPatrolWaypoint ~= nil then
                                newDest = g_NachbarFelderManager:pickPatrolWaypoint(tt.waypoints, oldDest,
                                    g_NachbarFelderManager:getWorkerPos(tt)) or oldDest
                            end
                            print("NachbarFelder: [TRAFFIC] WP" .. tostring(oldDest) ..
                                " nicht erreichbar (" .. tostring(math.floor(gotoElapsed)) .. "ms" ..
                                msgInfo .. ") - neues Ziel WP" .. tostring(newDest) ..
                                " (Versuch " .. tostring(tt.pathFails) .. "/3, " ..
                                g_NachbarFelderManager:getWorkerName(tt) .. ")")
                            local wp = tt.waypoints[newDest]
                            tt.patrolDestIdx = newDest
                            tt.patrolTargetX = wp[1]
                            tt.patrolTargetZ = wp[2]
                            tt.parkSecs      = g_NachbarFelderManager:scaleParkSecs(math.random(20, 60))
                            tt.fieldGotoStartedAt = nil
                            tt.status   = 1
                            tt.needTimer = true
                            return
                        end
                    end
                end
                -- GOTO kam nie vom Shop-Spawn weg: keine Rueckfahrt, direkt loeschen
                tt.status = 100
                tt.needTimer = true
                tt.gotoStartedAt = nil
                tt.fieldGotoStartedAt = nil
                return
            end
        end
        -- Zaehler gelten nur fuer Fehlschlaege in Folge
        tt.fieldGotoStartedAt = nil
        tt.gotoRejects        = nil
        tt.pathFails          = nil
        tt.roadSnapped        = nil   -- Strassen-Korrektur hoechstens einmal je Fahrt

        if tt.isPatrol then
            -- Am Ziel einfach stehen lassen, wie die KI angehalten hat: sie steht dann
            -- in Fahrtrichtung auf der Strasse. Ein Teleport auf die WP-Koordinate
            -- stellt das Gespann in Kurven quer, bewegt das Anbaugeraet nicht mit
            -- und zieht das Fahrzeug von der befahrbaren Flaeche.
            local secs = tt.parkSecs or g_NachbarFelderManager:scaleParkSecs(math.random(60, 180))
            tt.parkUntil = g_time + secs * 1000
            tt.status    = 2
            return
        end

        -- Eintraege ohne Patrol werden aufgeraeumt
        tt.status = 100
        tt.needTimer = true
    end
end

-- ============================================================
-- Weitere Event-Listener
-- ============================================================
function NachbarFelderWorker:onTargetReached()
    -- Auswertung laeuft ueber onAIJobFinished
end

function NachbarFelderWorker:onAIJobVehicleBlock()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager == nil then return end
    local tt = g_NachbarFelderManager:getCorrectobject(self)
    if tt ~= nil then
        tt.isBlocked = (tt.isBlocked or 0) + 10
    end
end

-- Beim Loeschen vom Spielverkehr abmelden, falls die Mod das Fahrzeug dort angemeldet hat
function NachbarFelderWorker:onDelete()
    if self.nf_spielverkehrNode == nil or g_NachbarFelderManager == nil then return end
    g_NachbarFelderManager:meldeBeimSpielverkehrAb(self)
end

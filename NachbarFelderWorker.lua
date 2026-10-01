NachbarFelderWorker = {}

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
    SpecializationUtil.registerEventListener(vehicleType, "onAIFieldWorkerEnd", NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onTargetReached",    NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onAIJobFinished",    NachbarFelderWorker)
    SpecializationUtil.registerEventListener(vehicleType, "onAIJobVehicleBlock",NachbarFelderWorker)
end

-- ============================================================
-- Standort-Rettung (Build 131): aus dem Abweisungs-Zweig ausgelagert,
-- damit auch "nicht erreichbar" sie nutzen kann. Beide Fehlerbilder
-- haben meist dieselbe Ursache: der STANDORT taugt nicht, nicht das Ziel.
-- Setzt das Fahrzeug auf den naechsten Punkt der KI-Strasse
-- (Radius 150 m, mind. 25 m weit), sonst zurueck zum Shop.
-- ============================================================
local function nfRoadSnap(tt, mgr, veh0)
    local vx, _, vz = getWorldTranslation(veh0.rootNode)
    -- Build 102: Mindestens 25 m weit versetzen. Der
    -- naechstgelegene Strassenpunkt hilft nicht - auf
    -- x=190 z=-52 stand die nSeries direkt auf der
    -- Strasse und kam trotzdem nie weg (12.09., vier
    -- Aufweck-Versuche, jedes Mal 3 Abweisungen). Der
    -- Platz ist die Sackgasse, nicht der Abstand.
    -- Build 105: Steht das Fahrzeug an einem Parkpunkt,
    -- ist es absichtlich neben der Strasse - dann reicht
    -- der naechste Strassenpunkt statt 25 m Mindestabstand.
    local minAbstand = 25
    if mgr.getIsParkpunkt ~= nil
       and mgr:getIsParkpunkt(tt, tt.waypointIdx) then
        minAbstand = 0
    end
    -- Build 136: Spur Richtung Ziel waehlen statt die Richtung um 180 Grad zu drehen -
    -- KI-Strassen sind Einbahn-Splines, gedreht stand das Fahrzeug gegen die
    -- Fahrtrichtung und wurde gleich wieder abgewiesen (Manager:getRoadPointInRichtung)
    local wdx = (tt.patrolTargetX or vx) - vx
    local wdz = (tt.patrolTargetZ or vz) - vz
    local rx, rz, rry, rdist = mgr:getRoadPointInRichtung(vx, vz, 150, minAbstand, wdx, wdz)
    local wohin = "weiter vorn auf die KI-Strasse"
    if rx == nil then
        -- Keine Strasse in Reichweite: zurueck zum Shop.
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
    -- Build 136: rdist ist der Versatz (mind. 25 m), nicht der Abstand zur Strasse
    print(string.format("NachbarFelder: [TRAFFIC] GOTO kommt nicht weg - Fahrzeug" ..
        " %.0f m %s gesetzt", rdist, wohin))
end

-- Naechsten Wegpunkt (bis 30 m) als ungeeigneten Startplatz vormerken -
-- nicht am Shop, der muss als Spawnplatz nutzbar bleiben (Build 131 ausgelagert).
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
-- onAIJobFinished: GOTO abgeschlossen → Feldarbeit starten
-- Nur auf dem Server verarbeiten (Logik liegt beim Server)
-- ============================================================
function NachbarFelderWorker:onAIJobFinished(...)
    -- Im Dedicated-MP: Logik nur auf Server
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager == nil then return end

    local tt = g_NachbarFelderManager:getCorrectobject(self)
    if tt == nil or tt.vehiclesToLoad == nil then
        -- Nicht unser Fahrzeug (anderes AI-Fahrzeug hat Job beendet)
        return
    end

    local vehicle = tt.vehiclesToLoad[1]
    tt.vehicle = vehicle

    if tt.status == 60 then
        -- Status=60 kann bedeuten:
        -- (A) Rückfahrt-GOTO abgeschlossen (normal) → gotoStartedAt gesetzt, ausreichend Zeit vergangen
        -- (B) Rückfahrt-GOTO sofort fehlgeschlagen (Pfad nicht gefunden) → gotoStartedAt gesetzt, < 1000ms
        -- (C) onAIFieldWorkerEnd hat status=60 gesetzt, GOTO noch nicht gestartet → gotoStartedAt = nil
        if tt.gotoStartedAt ~= nil then
            -- Rueckfahrt-GOTO ist beendet. Distanz zum Shop bestimmen.
            local dist = 99999
            -- Shop-Spawnplatz des Spiels (Build 96: mit Filiallieferungen = Lieferort)
            local shopX, shopZ = g_NachbarFelderManager:getShopPosition()
            pcall(function()
                local veh = tt.vehiclesToLoad[1]
                if veh ~= nil and veh.rootNode ~= nil then
                    local x, _, z = getWorldTranslation(veh.rootNode)
                    dist = MathUtil.vector2Length(x - shopX, z - shopZ)
                end
            end)
            tt.gotoStartedAt = nil

            if dist < 60 then
                -- Wirklich am Shop angekommen
                print("NachbarFelder: Helfer am Shop angekommen, wird entfernt (Feld " ..
                    tostring(tt.fieldId) .. ")")
                tt.gotoRetryCount = nil
                tt.lastReturnDist = nil
                tt.status = 100
                tt.needTimer = true
            else
                -- Noch nicht am Shop. Hat sich der Helfer seit dem letzten Versuch
                -- dem Shop genaehert (>5m)? Dann weiter fahren lassen - er
                -- "hangelt" sich oft ueber mehrere GOTOs vom Feld auf die Strasse.
                -- Steht er fest (kein Fortschritt) oder zu viele Versuche →
                -- erst dann aufgeben und den Helfer entfernen (Notnagel).
                tt.gotoRetryCount = (tt.gotoRetryCount or 0) + 1
                local fortschritt = (tt.lastReturnDist == nil) or (dist < tt.lastReturnDist - 5)
                tt.lastReturnDist = dist
                if fortschritt and tt.gotoRetryCount < 8 then
                    print("NachbarFelder: Rueckfahrt laeuft - noch " .. tostring(math.floor(dist)) ..
                        "m zum Shop (Versuch " .. tostring(tt.gotoRetryCount) .. ", Feld " ..
                        tostring(tt.fieldId) .. ") - faehrt weiter")
                    -- status bleibt 60, gotoStartedAt=nil → update() startet neue Rueckfahrt
                    tt.needTimer = true
                else
                    print("NachbarFelder: Rueckfahrt steckt bei " .. tostring(math.floor(dist)) ..
                        "m fest (Versuch " .. tostring(tt.gotoRetryCount) ..
                        ") - Helfer wird an Ort und Stelle entfernt (Feld " .. tostring(tt.fieldId) .. ")")
                    -- Build 97: kein Teleport zum Shop mehr. Das Fahrzeug wird
                    -- mit status 100 gleich danach entfernt - der Sprung quer
                    -- ueber die Karte war nur sichtbar, aber zu nichts nuetze.
                    tt.gotoRetryCount = nil
                    tt.lastReturnDist = nil
                    tt.status = 100
                    tt.needTimer = true
                end
            end
        -- else: GOTO noch nicht gestartet, update() kümmert sich drum
        end

    elseif tt.status == 2 then
        -- Feldarbeit-Job wurde beendet (normal oder frühzeitig).
        -- onAIFieldWorkerEnd übernimmt die Verarbeitung.

    elseif tt.status >= 3 and tt.status ~= 60 then
        -- Spezialfall: Status ≥ 3 (aber nicht 60, das oben behandelt wird) → aufräumen
        if tt.vehiclesToLoad ~= nil and tt.status < 99 then
            tt.status = 100
            tt.needTimer = true
        end

    elseif tt.status == 1 then
        -- GOTO beendet. Abschlussgrund primär über die echte AIMessage
        -- klassifizieren (driveToField merkt sie via job.stop-Wrapper in
        -- tt.lastStopMsg). Die Zeit-Heuristik ist nur noch Fallback ohne Message.
        local stopMsg = tt.lastStopMsg
        tt.lastStopMsg = nil

        -- Von UNS gestoppt (Watchdog Stufe1/2, Cleanup, Admin-Taste): Der Stopper
        -- setzt den Folgezustand selbst. Hier NICHT klassifizieren - sonst
        -- falsche WP-Strafen ("nicht erreichbar" obwohl nur festgefahren)
        -- und doppelte Neuziel-Wahl.
        if stopMsg == "AIMessageSuccessStoppedByUser" then
            tt.fieldGotoStartedAt = nil
            return
        end

        local msgSuccess  = stopMsg == "AIMessageSuccessFinishedJob"
        local msgPathFail = stopMsg == "AIMessageErrorNoPathFound"
                         or stopMsg == "AIMessageErrorNotReachable"

        -- Geldmangel kann seit Build 91 nicht mehr auftreten: die Jobs laufen
        -- mit getPricePerMs() = 0, also bucht AIJob:updateCost() nichts ab und
        -- prueft auch keinen Kontostand. Kommt die Meldung wider Erwarten doch,
        -- wird sie wie ein normaler Abbruch behandelt (kein Auffuellen mehr).
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
            -- ZWEI Fehlerklassen:
            -- instantReject = Job sofort abgewiesen → Gespann/Startposition ungeeignet.
            --                 NICHT das Feld bestrafen, sondern das Implement sperren.
            -- pathFail      = Pfadfindung lief, fand keinen Weg → Ziel-Problem
            --                 (z.B. Krebach-Feld 8/29 ohne Zufahrt) → Feld/WP sperren.
            local instantReject = false
            local pathFail      = false
            if msgSuccess then
                -- angekommen - auch wenn die Fahrt kurz war (nahes Ziel)
            elseif msgPathFail then
                -- Die Zeit entscheidet AUCH mit Message (Build 84): eine echte
                -- Pfadsuche ueber die Karte braucht Zeit (belegt: 1216/2041/
                -- 3235/4235 ms). Kommt NotReachable schon nach ~50-70 ms
                -- zurueck, hat die Suche nie begonnen - der Job wurde sofort
                -- abgewiesen, weil an der FAHRZEUGPOSITION kein Navmesh-Knoten
                -- liegt. Dann darf nicht das Ziel bestraft werden, sonst sperrt
                -- sich die Mod nach und nach alle Wegpunkte weg, obwohl die
                -- Ziele in Ordnung sind (Log 2026-09-10: 8 von 17 WPs in drei
                -- Minuten gesperrt, kein Fahrzeug ist je gefahren).
                -- Build 97: fuer Patrol-Fahrzeuge so nicht haltbar - die meisten
                -- Sofort-Abweisungen kommen vom Ziel. Die Behandlung im Patrol-
                -- Block unten bestraft das Ziel, schuetzt aber vor dem Fall von
                -- oben: nach drei Abweisungen in Folge ist Schluss, eine Sperre
                -- braucht zwei Fehlpunkte - ein schlechter Standort allein sperrt
                -- also kein Ziel.
                instantReject = gotoElapsed < 1500
                pathFail      = not instantReject
            elseif gotoElapsed < 5000 then
                -- keine verwertbare Message → alte Zeit-Heuristik
                instantReject = gotoElapsed < 1500
                pathFail      = not instantReject
            end
            if instantReject or pathFail then
                gotoOk = false
                local m = g_NachbarFelderManager
                local msgInfo = stopMsg ~= nil and (", " .. stopMsg) or ""
                if instantReject then
                    -- Patrol: Meldung/Handling im Patrol-Block weiter unten (Positionsproblem).
                    -- Build 117: Feldhelfer - eine Sofort-Abweisung ist ein Problem der
                    -- STARTPOSITION (kein Navmesh fuer das lange Gespann am engen Shop),
                    -- nicht des Geraets. Deshalb einmal mind. 40 m weiter auf die
                    -- KI-Strasse setzen, Richtung Feld ausrichten und neu versuchen.
                    -- Erst eine zweite Sofort-Abweisung sperrt das Geraet (unten).
                    if not tt.isPatrol and not tt.feldRettungVersucht and m ~= nil
                       and m.getNearestRoadPoint ~= nil then
                        tt.feldRettungVersucht = true
                        local versetzt = false
                        pcall(function()
                            local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                            if veh0 == nil or veh0.rootNode == nil then return end
                            local vx, _, vz = getWorldTranslation(veh0.rootNode)
                            if m.merkeSpawnFehlschlag ~= nil then   -- Build 129
                                m:merkeSpawnFehlschlag(tt, vx, vz, "Feldhelfer sofort abgewiesen")
                            end
                            -- Build 136: Spur Richtung Feld waehlen statt 180-Grad-Drehung (Einbahn-Splines)
                            local field = g_fieldManager:getFieldById(tt.fieldId)
                            local wdx, wdz = nil, nil
                            if field ~= nil and field.posX ~= nil then
                                wdx, wdz = field.posX - vx, field.posZ - vz
                            end
                            local rx, rz, rry, rdist = m:getRoadPointInRichtung(vx, vz, 200, 40, wdx, wdz)
                            if rx ~= nil and m:isSpotBlockedByAnyVehicle(rx, rz, 12, veh0) then
                                rx, rz, rry, rdist = m:getRoadPointInRichtung(vx, vz, 250, 80, wdx, wdz)
                                if rx ~= nil and m:isSpotBlockedByAnyVehicle(rx, rz, 12, veh0) then
                                    rx = nil
                                end
                            end
                            if rx == nil then return end
                            local ry = rry or 0
                            g_currentMission:teleportVehicle(veh0, rx, rz, ry)
                            versetzt = true
                            print(string.format("NachbarFelder: GOTO sofort abgewiesen (%dms%s) - Gespann %s" ..
                                " %.0f m weiter auf die KI-Strasse gesetzt, neuer Versuch zu Feld %s",
                                math.floor(gotoElapsed), msgInfo, tostring(m:getWorkerName(tt)),
                                rdist or 0, tostring(tt.fieldId)))
                        end)
                        if versetzt then
                            tt.fieldGotoStartedAt = nil
                            tt.status    = 1
                            tt.needTimer = true
                            return
                        end
                    end
                    if not tt.isPatrol then
                        print("NachbarFelder: GOTO sofort abgewiesen (" ..
                            tostring(math.floor(gotoElapsed)) .. "ms" .. msgInfo ..
                            ") - Gespann ungeeignet fuer Feld " ..
                            tostring(tt.fieldId) .. ", Fahrzeug wird am Shop entfernt")
                        if m ~= nil and tt.mission ~= nil and tt.mission.type ~= nil then
                            local mName = tt.mission.type.name
                            local implVeh = tt.vehiclesToLoad and tt.vehiclesToLoad[2]
                            local implFile = implVeh ~= nil and (implVeh.configFileName or implVeh.typeName) or nil
                            if mName ~= nil and implFile ~= nil then
                                m.vehicleImplBlacklist[mName] = m.vehicleImplBlacklist[mName] or {}
                                m.vehicleImplBlacklist[mName][implFile] =
                                    (m.vehicleImplBlacklist[mName][implFile] or 0) + 1
                                print("NachbarFelder: Implement [" .. tostring(implFile) ..
                                    "] fuer " .. tostring(mName) .. " gesperrt (GOTO-Abweisung)")
                            end
                        end
                    end
                else
                    -- Build 120: Feldhelfer ist GEFAHREN (>= 20 s) und unterwegs haengen
                    -- geblieben - das ist ein Problem des Gespanns/der Stelle, nicht des Felds.
                    if not tt.isPatrol and m ~= nil and gotoElapsed >= 20000 then
                        local vx, vz, kmh = 0, 0, 0
                        local tFile, iFile = nil, nil
                        pcall(function()
                            local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                            local impl = tt.vehiclesToLoad and tt.vehiclesToLoad[2]
                            if veh0 ~= nil and veh0.rootNode ~= nil then
                                local x, _, z = getWorldTranslation(veh0.rootNode)
                                vx, vz = x, z
                                if veh0.getLastSpeed ~= nil then kmh = veh0:getLastSpeed() end
                                tFile = veh0.configFileName
                            end
                            if impl ~= nil then iFile = impl.configFileName end
                        end)
                        if m.merkeSpawnFehlschlag ~= nil then   -- Build 129
                            m:merkeSpawnFehlschlag(tt, vx, vz, "Anfahrt abgebrochen")
                        end
                        if not tt.feldNeuplanung then
                            tt.feldNeuplanung = true
                            print(string.format("NachbarFelder: Anfahrt Feld %s nach %d s abgebrochen (%s) bei x=%d z=%d," ..
                                " %.1f km/h - %s hing unterwegs, neuer Anlauf von hier",
                                tostring(tt.fieldId), math.floor(gotoElapsed / 1000), tostring(stopMsg),
                                math.floor(vx), math.floor(vz), kmh, tostring(m:getWorkerName(tt))))
                            tt.fieldGotoStartedAt = nil
                            tt.status    = 1
                            tt.needTimer = true
                            return
                        end
                        if m.sperreFeldGespann ~= nil then
                            m:sperreFeldGespann(tFile, iFile)
                        end
                        print(string.format("NachbarFelder: Anfahrt Feld %s erneut abgebrochen nach %d s bei x=%d z=%d" ..
                            " - Gespann %s + %s fuer diese Session gesperrt, Feld wird NICHT bestraft," ..
                            " Fahrzeug wird entfernt", tostring(tt.fieldId), math.floor(gotoElapsed / 1000),
                            math.floor(vx), math.floor(vz), tostring(m:getWorkerName(tt)),
                            tostring(iFile ~= nil and (string.match(iFile, "[^/\\]+$") or iFile) or "-")))
                        tt.status = 100
                        tt.needTimer = true
                        tt.gotoStartedAt = nil
                        tt.fieldGotoStartedAt = nil
                        return
                    end
                    -- Build 146: kein Pfad zu diesem Feldrand -> naechsten Zugang probieren
                    -- (andere Seite, andere Wegklasse, zuletzt die alte Zielwahl), hoechstens
                    -- ZUGANG_MAX_VERSUCHE mal. Vorher wurde der Helfer sofort entfernt.
                    local maxZugang = (NachbarFelderManager ~= nil and NachbarFelderManager.ZUGANG_MAX_VERSUCHE) or 3
                    if not tt.isPatrol and m ~= nil and tt.zugangZiel ~= nil
                       and (tt.zugangVersuche or 0) < maxZugang then
                        tt.zugangVersuche = (tt.zugangVersuche or 0) + 1
                        tt.zugangAusschluss = tt.zugangAusschluss or {}
                        table.insert(tt.zugangAusschluss, tt.zugangZiel)
                        print(string.format("NachbarFelder: GOTO kein Pfad (%dms%s) zu Feld %s bei x=%.0f z=%.0f" ..
                            " - anderer Zugang wird versucht (%d/%d)", math.floor(gotoElapsed), msgInfo,
                            tostring(tt.fieldId), tt.zugangZiel[1], tt.zugangZiel[2], tt.zugangVersuche, maxZugang))
                        tt.zugangZiel = nil
                        tt.fieldGotoStartedAt = nil
                        tt.status    = 1
                        tt.needTimer = true
                        return
                    end
                    if not tt.isPatrol then
                        print("NachbarFelder: GOTO kein Pfad (" ..
                            tostring(math.floor(gotoElapsed)) .. "ms" .. msgInfo .. ") zu Feld " ..
                            tostring(tt.fieldId) .. " -> Fahrzeug wird am Shop entfernt")
                    end
                    -- Patrol: keine Feld-Cooldowns auf negativen Pseudo-Keys
                    if not tt.isPatrol and m ~= nil then
                        m.fieldPathFails = m.fieldPathFails or {}
                        m.fieldPathFails[tt.fieldId] = (m.fieldPathFails[tt.fieldId] or 0) + 1
                        if m.fieldPathFails[tt.fieldId] >= 2 then
                            m.fieldCooldown[tt.fieldId] = 999999
                            print("NachbarFelder: Feld " .. tostring(tt.fieldId) ..
                                " fuer diese Session gesperrt (2x kein Pfad)")
                        else
                            m.fieldCooldown[tt.fieldId] = 60
                        end
                    end
                end
                -- Patrol: nach Fehlerklasse unterscheiden
                if tt.isPatrol then
                    if instantReject then
                        -- GOTO sofort abgewiesen (< 1500 ms).
                        --
                        -- Build 97: KEIN Teleport mehr. Bis Build 96 wurde das
                        -- Fahrzeug dann zum Shop gesetzt - quer ueber die Karte -,
                        -- weil die Abweisung als Problem der Startposition galt.
                        -- Die Logs widerlegen das: am 10.09. und 11.09. wurde das
                        -- Ziel danach fast immer AUCH vom Shop aus abgewiesen
                        -- (WP2/3/6/7/8/11/29 ...), die Abweisung kommt also vom
                        -- ZIEL. Darum bleibt das Fahrzeug stehen, das Ziel bekommt
                        -- einen Fehlpunkt (2x = fuer die Session gesperrt) und es
                        -- gibt ein neues Ziel. Erst wenn drei Ziele hintereinander
                        -- von derselben Stelle abgewiesen werden, liegt es am
                        -- Standort: Startplatz vormerken, an Ort und Stelle in den Pool.
                        -- Diagnose (Build 85): festhalten, WO das Fahrzeug
                        -- stand und WAS es zog. Nur so ist zu unterscheiden,
                        -- ob der Wegpunkt abseits befahrbaren Gelaendes liegt
                        -- oder ob das Anbaugeraet den GOTO blockiert.
                        pcall(function()
                            local v0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                            local impl = tt.vehiclesToLoad and tt.vehiclesToLoad[2]
                            local vx, vz = 0, 0
                            if v0 ~= nil and v0.rootNode ~= nil then
                                local x, _, z = getWorldTranslation(v0.rootNode)
                                vx, vz = x, z
                            end
                            -- naechstgelegener Wegpunkt zur Fahrzeugposition
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

                            -- Build 89: Zustandsdaten mitschreiben. Ein von Hand
                            -- gesetzter Fahrauftrag laeuft auf dieser Karte
                            -- ueberall - also unterscheidet sich der Zustand,
                            -- den die Mod erzeugt, von dem eines normalen
                            -- Fahrzeugs. Diese Werte zeigen worin.
                            local zusatz = ""
                            pcall(function()
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
                            end)
                            -- Build 119: Abweisung dem Anbaugeraet anrechnen (Sperre erst
                            -- nach 3x an 2 verschiedenen Stellen, siehe Manager)
                            -- Build 129: Abweisung am eigenen Ladeplatz -> Platz sperren
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
                        end)

                        -- Build 99: KEINE Ziel-Strafe mehr bei einer Sofort-Abweisung.
                        -- Beleg Log 12.09.: ein Fahrzeug stand auf x=124 z=-93 und
                        -- bekam dort rund 30 verschiedene Ziele nacheinander in je
                        -- ~52 ms abgewiesen. Am Ende waren alle 38 Wegpunkte als Ziel
                        -- gesperrt und kein Verkehr mehr unterwegs. Nicht das Ziel ist
                        -- schuld, sondern der Standort - das Fahrzeug steht neben der
                        -- KI-Strasse. Ziele sperrt nur noch der pathFail-Zweig unten
                        -- (echte Pfadsuche, > 1500 ms).
                        tt.gotoRejects = (tt.gotoRejects or 0) + 1
                        local mgr  = g_NachbarFelderManager
                        local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]

                        -- Zweiter Fehlschlag: Standort reparieren statt weiter Ziele
                        -- durchzuprobieren. Die Strassen-Stuetzpunkte (Build 98)
                        -- liefern den naechsten Punkt der KI-Strasse; dorthin wird das
                        -- Fahrzeug gesetzt, in Strassenrichtung.
                        --
                        -- Build 101: Suchradius 40 m -> 150 m. Gestrandete Fahrzeuge
                        -- liegen weiter ab, als gedacht: der Puma stand am 12.09. ab
                        -- 18:04 auf x=-918 z=358, 117 m vom naechsten Wegpunkt. Die
                        -- 40-m-Rettung fand dort nichts, und nach jedem Aufwecken
                        -- scheiterte er sofort wieder - dauerhaft totes Fahrzeug.
                        -- Findet sich auch in 150 m keine KI-Strasse, geht es zurueck
                        -- zum Shop-Spawn. Das ist ein sichtbarer Sprung, aber die
                        -- Alternative ist ein Fahrzeug, das nie wieder faehrt.
                        if tt.gotoRejects == 2 and not tt.roadSnapped
                           and veh0 ~= nil and veh0.rootNode ~= nil
                           and mgr.getNearestRoadPoint ~= nil then
                            pcall(nfRoadSnap, tt, mgr, veh0)
                        end

                        if tt.gotoRejects < 3 and tt.waypoints ~= nil and #tt.waypoints >= 2 then
                            local oldDest = tt.patrolDestIdx or 1
                            local newDest = oldDest
                            if mgr.pickPatrolWaypoint ~= nil then
                                -- Build 109: Bezug ist das Fahrzeug, nicht das unerreichte Ziel
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
                        -- Den naechsten Wegpunkt (bis 30 m) als Startplatz vormerken -
                        -- nicht am Shop, der muss als Spawnplatz nutzbar bleiben.
                        local veh = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                        pcall(nfMarkStartPlaceBad, tt, mgr, veh)
                        if veh ~= nil then
                            local fname = veh.configFileName or ""
                            local base  = string.match(fname, "[^/\\]+$") or fname
                            print("NachbarFelder: [TRAFFIC] " .. base ..
                                " - drei Ziele in Folge sofort abgewiesen, Fahrzeug geht an Ort und" ..
                                " Stelle in den Pool (bei vollem Pool: entfernt).")
                        end
                        -- Build 93: Pool statt Loeschen - jedes neu geladene Modell
                        -- kostet den Server mehrere hundert Millisekunden Stillstand.
                        -- sleepPatrolEntry laesst das Fahrzeug stehen, wo es ist.
                        tt.gotoRejects        = nil
                        tt.roadSnapped        = nil
                        tt.fieldGotoStartedAt = nil
                        tt.status             = 100
                        tt.needTimer          = true
                        return
                    else
                        -- Pfadfindung lief, fand keinen Weg.
                        -- Build 131: Fehlschlaege in Folge zaehlen. Beleg Test
                        -- 17.09.: series6C probierte von 10:19 bis 10:32 nacheinander
                        -- 17 Ziele durch, jede Pfadsuche 20-30 s CPU - und sperrte
                        -- dabei gute Wegpunkte fuer ALLE Fahrzeuge. Scheitern
                        -- mehrere Ziele hintereinander, ist der Standort schuld.
                        local mgr  = g_NachbarFelderManager
                        local veh0 = tt.vehiclesToLoad and tt.vehiclesToLoad[1]
                        tt.pathFails = (tt.pathFails or 0) + 1

                        -- Ziel nur beim ERSTEN Fehlschlag in Folge bestrafen
                        -- (2x → Session-Sperre). Ab dem zweiten gilt der Standort
                        -- als Ursache - sonst vergiftet ein festsitzendes
                        -- Fahrzeug das WP-Netz aller anderen.
                        if tt.pathFails == 1 and mgr.registerWaypointFail ~= nil then
                            mgr:registerWaypointFail(tt.patrolDestIdx)
                        end

                        -- Zweiter Fehlschlag: Standort auf die KI-Strasse setzen
                        if tt.pathFails == 2 and not tt.roadSnapped
                           and veh0 ~= nil and veh0.rootNode ~= nil
                           and mgr.getNearestRoadPoint ~= nil then
                            pcall(nfRoadSnap, tt, mgr, veh0)
                        end

                        -- Dritter Fehlschlag: aufgeben, Startplatz vormerken, Pool
                        if tt.pathFails >= 3 then
                            pcall(nfMarkStartPlaceBad, tt, mgr, veh0)
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
                                -- Build 109: Bezug ist das Fahrzeug, nicht das unerreichte Ziel
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
                -- Fahrzeug steht noch am Shop-Spawn (GOTO kam nie weg) -
                -- keine sinnlose "Rueckfahrt" Shop->Shop, direkt loeschen.
                tt.status = 100
                tt.needTimer = true
                tt.gotoStartedAt = nil
                tt.fieldGotoStartedAt = nil
                return
            end
        end
        tt.fieldGotoStartedAt = nil
        tt.gotoRejects        = nil   -- Build 97: zaehlt nur Abweisungen in Folge
        tt.pathFails          = nil   -- Build 131: zaehlt nur "nicht erreichbar" in Folge
        tt.roadSnapped        = nil   -- Build 99: Strassen-Korrektur je Fahrt einmal


        -- Traffic: statt Feldarbeit → Fahrzeug parkt am Zielort.
        -- Kein teleportVehicle (wuerde Terrain-Y neu berechnen + Anbaugeraet nicht mitbewegen).
        -- Anbaugeraet wird beim Spawn bereits gefaltet (Manager status 0→1), bleibt gefaltet.
        if tt.isPatrol then
            -- Build 90: KEIN Einparken mehr am Ziel-WP.
            --
            -- Frueher wurde das Fahrzeug bei Ankunft auf die exakte
            -- WP-Koordinate samt einer berechneten Richtung geschnappt. Beide
            -- Richtungsquellen taugen dafuer nicht:
            --   * die gespeicherte ry ist die Blickrichtung beim Setzen des
            --     Punktes (zu Fuss am Strassenrand = quer zur Fahrbahn),
            --   * die Luftlinie zum naechsten WP (Build 84) trifft die
            --     Strassenrichtung nur auf geraden Strecken - in Ortsdurch-
            --     fahrten und Kurven stellt sie das Gespann quer ueber die
            --     Fahrbahn (belegt per Screenshot vom 2026-09-10).
            --
            -- Die KI kennt die Strasse dagegen genau: sie faehrt darauf und
            -- haelt in Fahrtrichtung an. Also bleibt das Fahrzeug einfach
            -- stehen, wo und wie es angekommen ist. Das spart obendrein den
            -- Teleport, der es von der befahrbaren Flaeche herunterzog und
            -- den naechsten GOTO scheitern liess.
            local secs = tt.parkSecs or g_NachbarFelderManager:scaleParkSecs(math.random(60, 180))
            tt.parkUntil = g_time + secs * 1000
            tt.status    = 2
            return
        end

        if tt:isSpecialHarvestMission() then
            local trailer = tt.vehiclesToLoad[3]
            trailer:forceUnmountDynamicMountedObjects()
            tt.removeVehicleInfo.fileName = trailer.configFileName
            tt.removeVehicleInfo.configurations = trailer.configurations
            tt.removeVehicleInfo.fieldId = tt.fieldId
            trailer:delete()

            local x, y, z = getWorldTranslation(tt.vehiclesToLoad[1].rootNode)
            local dirX, dirY, dirZ = localDirectionToWorld(tt.vehiclesToLoad[1].rootNode, 0, 0, 1)
            local angle = MathUtil.getYRotationFromDirection(dirX, dirZ)
            g_currentMission:teleportVehicle(tt.vehiclesToLoad[2], x + dirX * 10, z + dirZ * 10, angle)
            g_NachbarFelderManager:attachObjectToCar(tt.vehiclesToLoad[1], tt.vehiclesToLoad[2])
        end

        tt.status = 2
        tt.needTimer = true
    end
end

-- ============================================================
-- onAIFieldWorkerEnd: Feldarbeit beendet → Rückfahrt
-- ============================================================
function NachbarFelderWorker:onAIFieldWorkerEnd()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager == nil then return end

    local tt = g_NachbarFelderManager:getCorrectobject(self)
    if tt == nil or tt.vehiclesToLoad == nil then
        print("NachbarFelder: onAIFieldWorkerEnd - kein Worker gefunden fuer Fahrzeug " .. tostring(self.typeName or "?"))
        return
    end
    if tt.isPatrol then return end
    if tt.status >= 3 then return end

    -- Build 141: Abbruchgrund der KI (setAIOnField merkt ihn per job.stop-Wrapper)
    print("NachbarFelder: Feldarbeit beendet Feld " .. tostring(tt.fieldId) ..
        " (Laufzeit: " .. tostring(g_time and tt.fieldWorkStartedAt and
        math.floor((g_time - tt.fieldWorkStartedAt) / 1000) or "?") .. "s, Grund: " ..
        tostring(tt.lastFieldStopMsg or "unbekannt") .. ")")

    -- Zu früh beendet?
    if tt.status == 2 and tt.fieldWorkStartedAt ~= nil and g_time ~= nil then
        local elapsed = g_time - tt.fieldWorkStartedAt
        if elapsed < 5000 then
            -- < 5s: Feldarbeit sofort gescheitert
            -- Implement auf Sperrliste setzen (inkompatibles Fahrzeug, nicht Feldproblem)
            local mName = tt.mission and tt.mission.type and tt.mission.type.name
            local implVeh = tt.vehiclesToLoad and tt.vehiclesToLoad[2]
            if g_NachbarFelderManager ~= nil and mName ~= nil and implVeh ~= nil then
                local implFile = implVeh.configFileName or (implVeh.typeName or "?")
                if g_NachbarFelderManager.vehicleImplBlacklist[mName] == nil then
                    g_NachbarFelderManager.vehicleImplBlacklist[mName] = {}
                end
                local failCount = (g_NachbarFelderManager.vehicleImplBlacklist[mName][implFile] or 0) + 1
                g_NachbarFelderManager.vehicleImplBlacklist[mName][implFile] = failCount
                print("NachbarFelder: Implement [" .. tostring(implFile) .. "] fuer " ..
                    tostring(mName) .. " gesperrt (" .. failCount .. "x gescheitert in " ..
                    tostring(math.floor(elapsed)) .. "ms)")
            end
            -- Nur Feldcooldown wenn Implement schon 3x gescheitert (dann vielleicht wirklich Feldproblem)
            local cooldownMinutes = 0
            if g_NachbarFelderManager ~= nil and mName ~= nil and implVeh ~= nil then
                local implFile = implVeh.configFileName or (implVeh.typeName or "?")
                local fails = g_NachbarFelderManager.vehicleImplBlacklist[mName] and
                    g_NachbarFelderManager.vehicleImplBlacklist[mName][implFile] or 0
                if fails >= 3 then cooldownMinutes = 20 end
            end
            print("NachbarFelder: Feldarbeit gescheitert auf Feld " .. tostring(tt.fieldId) ..
                " (" .. tostring(math.floor(elapsed)) .. "ms)" ..
                (cooldownMinutes > 0 and (" - Cooldown " .. cooldownMinutes .. " Spielmin.") or " - kein Feldcooldown") ..
                ", Fahrzeug faehrt zurueck")
            if g_NachbarFelderManager ~= nil and cooldownMinutes > 0 then
                g_NachbarFelderManager.fieldCooldown[tt.fieldId] = cooldownMinutes
            end
            if tt.tempFarmland ~= nil then
                tt.tempFarmland.farmId  = tt.origFarmlandId
                tt.tempFarmland.isOwned = tt.origIsOwned
                tt.tempFarmland = nil
            end
            tt.status = 60
            tt.needTimer = true
            tt.gotoStartedAt = nil
            tt.isBlocked = 1
            return
        elseif elapsed < 15000 then
            -- 5s–15s: kurze Arbeit (Feld fast fertig) → kurzen Cooldown setzen + zurückfahren
            print("NachbarFelder: Feldarbeit kurz beendet (" .. tostring(math.floor(elapsed / 1000)) ..
                "s) - Fahrzeug faehrt zurueck zum Shop (Feld " .. tostring(tt.fieldId) .. ")")
            if g_NachbarFelderManager ~= nil then
                g_NachbarFelderManager.fieldCooldown[tt.fieldId] = 10  -- 10 Spielminuten Cooldown
            end
            -- Feldbesitz wiederherstellen
            if tt.tempFarmland ~= nil then
                tt.tempFarmland.farmId  = tt.origFarmlandId
                tt.tempFarmland.isOwned = tt.origIsOwned
                tt.tempFarmland = nil
            end
            tt.status = 60
            tt.needTimer = true
            tt.gotoStartedAt = nil
            return
        end
    end

    local vehicle = tt.vehiclesToLoad[1]

    -- Ernte-Spezialfall: Mähdrescher wieder zusammenbauen
    if tt.removeVehicleInfo.fileName ~= nil then
        local object = tt.vehiclesToLoad[2]
        if object ~= nil and object.isDetachAllowed ~= nil then
            local detachAllowed = object:isDetachAllowed()
            if detachAllowed then object:startDetachProcess() end
        end
        local data = VehicleLoadingData.new()
        data:setFilename(tt.removeVehicleInfo.fileName)
        if data.isValid then
            if tt.removeVehicleInfo.configurations ~= nil then
                data:setConfigurations(tt.removeVehicleInfo.configurations)
            end
            local x, y, z = getWorldTranslation(vehicle.rootNode)
            local rx, ry, rz = getWorldRotation(vehicle.rootNode)
            data:setPosition(x, y, z)
            data:setRotation(rx, ry, rz)
            data:setPropertyState(VehiclePropertyState.MISSION)
            data:setOwnerFarmId(g_NachbarFelderManager.farmId)
            local loadingInfo = {loadingData = data, vehicleInfo = tt.removeVehicleInfo}
            data:load(tt.onSpawnedVehicle, tt, loadingInfo)
        end
    else
        -- Feldarbeit erfolgreich (>= 15s) → Feld-Zustand aktualisieren
        if g_NachbarFelderManager ~= nil then
            pcall(function()
                g_NachbarFelderManager:finishFieldState(tt.fieldId, 2)
            end)
        end
        if tt.tempFarmland ~= nil then
            tt.tempFarmland.farmId  = tt.origFarmlandId
            tt.tempFarmland.isOwned = tt.origIsOwned
            tt.tempFarmland = nil
        end
        tt.status = 60
        tt.needTimer = true
        tt.gotoStartedAt = nil
        print("NachbarFelder: Rueckfahrt Feld " .. tostring(tt.fieldId))
    end

    tt.isBlocked = 1
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================
function NachbarFelderWorker:isSpecialHarvestMission()
    local dynamicVeh = false
    if self.vehiclesToLoad ~= nil and #self.vehiclesToLoad >= 3 then
        dynamicVeh = string.sub(self.vehiclesToLoad[3].typeName, 1, string.len("dynamic")) == "dynamic"
    end
    return self.mission ~= nil and self.mission.type ~= nil and
        self.mission.type.name == "harvestMission" and
        self.vehiclesToLoad ~= nil and #self.vehiclesToLoad >= 3 and dynamicVeh
end

function NachbarFelderWorker:onTargetReached()
    -- Wird von GOTO genutzt; Logik läuft über onAIJobFinished
end

function NachbarFelderWorker:onAIJobVehicleBlock()
    if g_currentMission == nil or not g_currentMission:getIsServer() then return end
    if g_NachbarFelderManager == nil then return end
    local tt = g_NachbarFelderManager:getCorrectobject(self)
    if tt ~= nil then
        tt.isBlocked = (tt.isBlocked or 0) + 10
    end
end

function NachbarFelderWorker:onSpawnedVehicle(vehicles, vehicleLoadState, loadingInfo)
    if vehicleLoadState == VehicleLoadingState.OK then
        if loadingInfo.vehicleInfo ~= nil and loadingInfo.vehicleInfo.fileName ~= nil then
            for _, trailer in ipairs(vehicles) do
                self.vehiclesToLoad[3] = trailer
                trailer.isVehicleSaved = false
                self.status = 33
                self.needTimer = true
            end
        end
    end
end

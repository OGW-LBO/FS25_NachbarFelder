-- ============================================================
-- NachbarFelderWaypointDialog
-- Zeigt Wegpunkte einzeln mit Vor/Zurueck-Navigation.
-- Shift+Alt+W oeffnet den Dialog.
-- ============================================================
-- Build 158: sichtbare Texte aus l10n (ModHub verlangt DE und EN).
local function nfDialogText(key, ...)
    local s = key
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        s = g_i18n:getText(key)
    end
    if select("#", ...) > 0 then
        s = string.format(s, ...)
    end
    return s
end


NachbarFelderWaypointDialog = {}
local NachbarFelderWaypointDialog_mt = Class(NachbarFelderWaypointDialog, DialogElement)

local modDirectory = g_currentModDirectory

function NachbarFelderWaypointDialog.new(target, custom_mt)
    local self = DialogElement.new(target, custom_mt or NachbarFelderWaypointDialog_mt)
    self.selectedIdx = 1
    return self
end

function NachbarFelderWaypointDialog.registerDialog()
    local path = modDirectory .. "gui/NachbarFelderWaypointDialog.xml"
    g_gui:loadGui(path, "NachbarFelderWaypointDialog",
        NachbarFelderWaypointDialog.new(nil, NachbarFelderWaypointDialog_mt))
end

-- ============================================================
-- Hilfsfunktion: aktuelle Wegpunkte
-- ============================================================
function NachbarFelderWaypointDialog:getWaypoints()
    local m = g_NachbarFelderManager
    if m ~= nil and m.userTrafficWaypoints ~= nil then
        return m.userTrafficWaypoints
    end
    return {}
end

-- ============================================================
-- Dialog oeffnen
-- ============================================================
function NachbarFelderWaypointDialog:onOpen()
    DialogElement.onOpen(self)
    self.selectedIdx = 1
    self:refreshDisplay()
end

-- ============================================================
-- Anzeige aktualisieren
-- ============================================================
function NachbarFelderWaypointDialog:refreshDisplay()
    local function schritt()
        local wps   = self:getWaypoints()
        local count = #wps
        local cElem = self:getDescendantByName("counterText")
        local iElem = self:getDescendantByName("wpInfoText")

        if count == 0 then
            if cElem ~= nil then cElem:setText(nfDialogText("NF_msg_keineWpVorhanden")) end
            if iElem ~= nil then iElem:setText(nfDialogText("NF_msg_wpSetzenHinweis")) end
            return
        end

        -- Index einschraenken
        if self.selectedIdx < 1     then self.selectedIdx = count end
        if self.selectedIdx > count then self.selectedIdx = 1     end

        local wp = wps[self.selectedIdx]
        if cElem ~= nil then
            cElem:setText(nfDialogText("NF_msg_wpVonCount", self.selectedIdx, count))
        end
        if iElem ~= nil then
            local lbl = (wp.label ~= nil and wp.label ~= "") and ("  [" .. wp.label .. "]") or ""
            iElem:setText(string.format("x = %d     z = %d%s",
                math.floor(wp.x), math.floor(wp.z), lbl))
        end
    end
    schritt()
end

-- ============================================================
-- Navigation
-- ============================================================
function NachbarFelderWaypointDialog:onClickPrev()
    self.selectedIdx = self.selectedIdx - 1
    self:refreshDisplay()
end

function NachbarFelderWaypointDialog:onClickNext()
    self.selectedIdx = self.selectedIdx + 1
    self:refreshDisplay()
end

-- ============================================================
-- Teleportieren
-- ============================================================
function NachbarFelderWaypointDialog:onClickTeleport()
    local function schritt()
        local wps = self:getWaypoints()
        local wp  = wps[self.selectedIdx]
        if wp == nil then return end

        local x, z = wp.x, wp.z
        local y = 0
        if g_currentMission ~= nil and g_currentMission.terrainRootNode ~= nil then
            y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z) + 1
        end

        local m  = g_NachbarFelderManager
        local lp = (m ~= nil) and m.localPlayer or nil
        if lp ~= nil then
            local vehicle = lp.currentVehicle or lp.controlledVehicle
            if vehicle ~= nil and vehicle.rootNode ~= nil and vehicle.rootNode ~= 0 then
                setTranslation(vehicle.rootNode, x, y, z)
            elseif lp.rootNode ~= nil and lp.rootNode ~= 0 then
                setTranslation(lp.rootNode, x, y, z)
            end
        end
        print("NachbarFelder: [WP-Dialog] Teleport zu WP" .. self.selectedIdx ..
              " x=" .. tostring(math.floor(x)) .. " z=" .. tostring(math.floor(z)))
    end
    schritt()
    self:onClickClose()
end

-- ============================================================
-- Loeschen
-- ============================================================
function NachbarFelderWaypointDialog:onClickDelete()
    local function schritt()
        local m   = g_NachbarFelderManager
        local wps = self:getWaypoints()
        if wps[self.selectedIdx] == nil then return end

        local wp = wps[self.selectedIdx]
        print("NachbarFelder: [WP-Dialog] Loesche WP" .. self.selectedIdx ..
              " x=" .. tostring(math.floor(wp.x)) .. " z=" .. tostring(math.floor(wp.z)))
        table.remove(wps, self.selectedIdx)
        if m ~= nil then m:saveWaypoints() end

        local count = #wps
        if count == 0 then
            self.selectedIdx = 1
        elseif self.selectedIdx > count then
            self.selectedIdx = count
        end
    end
    schritt()
    self:refreshDisplay()
end

-- ============================================================
-- Schliessen
-- ============================================================
function NachbarFelderWaypointDialog:onClickClose()
    if g_gui ~= nil and g_gui.closeDialog ~= nil then g_gui:closeDialog(self) end
end

-- Escape-Taste
function NachbarFelderWaypointDialog:onClickBack()
    self:onClickClose()
end

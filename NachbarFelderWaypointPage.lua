-- ============================================================
-- NachbarFelderWaypointPage
-- Eigener Reiter für den Wegpunkt-Manager unter ESC > Allgemeine Einstellungen.
-- Aufbau angelehnt an FS25_additionalGameSettings.
-- ============================================================

--- Text aus der l10n holen, optional mit string.format-Argumenten; fehlt der Schlüssel, kommt er selbst zurück.
local function nfPageText(key, ...)
    local s = key
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText(key) then
        s = g_i18n:getText(key)
    end
    if select("#", ...) > 0 then
        s = string.format(s, ...)
    end
    return s
end

-- Fallback nur, falls der Schlüssel in der modDesc fehlt.
local function nfTabTitel()
    if g_i18n ~= nil and g_i18n.hasText ~= nil and g_i18n:hasText("NF_wpPage_tabTitle") then
        return g_i18n:getText("NF_wpPage_tabTitle")
    end
    return (g_languageShort == "de") and "Wegpunkte" or "Waypoints"
end


-- Wegpunkt-Kategorie -> l10n-Schlüssel (0 Normal, 1 Kurz, 2 Lang, 3 Durchfahrt, 4 Spawnpunkt).
-- Unbekannte Werte gelten als Normal.
local NF_CAT_KEYS = { [0]="NF_wpCat_normal", [1]="NF_wpCat_kurz", [2]="NF_wpCat_lang",
                      [3]="NF_wpCat_durchfahrt", [4]="NF_wpArt_spawn" }
local function nfCatKey(cat)
    return NF_CAT_KEYS[cat or 0] or "NF_wpCat_normal"
end

-- Nur aufrufen, wenn das Element es unterstützt: ein Fehler im Menü-Update
-- reißt sonst den ganzen Frame mit.
local function nfSetDisabled(elem, disabled)
    if elem ~= nil and elem.setDisabled ~= nil then
        elem:setDisabled(disabled)
    end
end

-- Setzt den Zustand nur, wenn das Element eine BinaryOption ist.
local function nfSetOptionState(elem, state)
    if elem ~= nil and elem.setState ~= nil then
        elem.texts = { nfPageText("NF_ui_nein"), nfPageText("NF_ui_ja") }
        elem:setState(state)
    end
end

NachbarFelderWaypointPage = {}

-- Log-Ausgaben nur im Debug-Log (Warnungen/Fehler immer), siehe NachbarFelder.lua
local print = NachbarFelderLog.print
local NachbarFelderWaypointPage_mt = Class(NachbarFelderWaypointPage, FrameElement)
local modDirectory = g_currentModDirectory

-- Globale Referenz für die GUI-Callbacks
g_NachbarFelderWaypointPage = nil

-- Beschriftung der Aktions-Buttons (l10n-Schlüssel). Der Typ-Button zeigt
-- stattdessen die aktuelle Kategorie (refreshWpInfo).
NachbarFelderWaypointPage.BUTTON_TEXT = {
    nfWpPrev         = "NF_wpBtn_prev",
    nfWpNext         = "NF_wpBtn_next",
    nfWpTeleport     = "NF_wpBtn_teleport",
    nfWpDelete       = "NF_wpBtn_delete",
    nfWpAddHere      = "NF_wpBtn_set",
    nfWpAddSpawnHere = "NF_wpBtn_set",
}

function NachbarFelderWaypointPage.new(manager)
    local self = FrameElement.new(nil, NachbarFelderWaypointPage_mt)
    self.manager    = manager
    self.currentIdx = 1
    return self
end

-- ============================================================
-- Laden + Einbetten in InGameMenuSettingsFrame
-- ============================================================
function NachbarFelderWaypointPage:registerAndInject()
    -- Eigene GUI-Profile müssen vor loadGui geladen sein. Bereits vorhandene
    -- Profilnamen überschreibt das Spiel nicht (Gui:loadProfileSet).
    if not NachbarFelderWaypointPage._profileGeladen then
        NachbarFelderWaypointPage._profileGeladen = true
        if g_gui ~= nil and g_gui.loadProfiles ~= nil then
            g_gui:loadProfiles(Utils.getFilename("gui/NachbarFelderGuiProfiles.xml", modDirectory))
        else
            print("LivingRoads: [WP-PAGE] loadProfiles nicht verfuegbar")
        end
    end

    if g_gui == nil or g_gui.loadGui == nil then
        print("LivingRoads: [WP-PAGE] loadGui nicht verfuegbar")
        return
    end
    -- loadGui legt nfWpPage, nfWpTab und die übrigen nfWp*-IDs als Felder auf self an
    g_gui:loadGui(
        Utils.getFilename("gui/NachbarFelderWaypointPage.xml", modDirectory),
        "NachbarFelderWaypointPage",
        self
    )

    local function schritt()
        local settingsFrame = g_inGameMenu and g_inGameMenu.pageSettings
        if settingsFrame == nil then
            print("LivingRoads: [WP-PAGE] pageSettings nicht verfügbar")
            return
        end

        local wpPage = self.nfWpPage
        local wpTab  = self.nfWpTab
        if wpPage == nil or wpTab == nil then
            print("LivingRoads: [WP-PAGE] nfWpPage/nfWpTab nicht gefunden (XML-Fehler?)")
            return
        end

        -- $l10n_ löst der C++-Parser auf, bevor Mod-Texte greifen,
        -- daher den Titel nach loadGui selbst setzen.
        local title = nfTabTitel()
        if wpTab.setText ~= nil then wpTab:setText(title) end

        -- Prefabs dienen nur als Klonvorlagen
        if self.nfWpBoolPrefab    ~= nil then self.nfWpBoolPrefab:setVisible(false)    end
        if self.nfWpActionPrefab  ~= nil then self.nfWpActionPrefab:setVisible(false)  end
        if self.nfWpSectionPrefab ~= nil then self.nfWpSectionPrefab:setVisible(false) end

        -- Abwechselnde Zeilenhintergründe; nach jedem Hinzufügen von Zeilen erneut aufrufen.
        local function updateAlternating(layout)
            local colors = InGameMenuSettingsFrame.COLOR_ALTERNATING
            if colors == nil then return end
            local isAlt = true
            if layout == nil or layout.elements == nil then return end
            for _, container in ipairs(layout.elements) do
                if container.name == "sectionHeader" then
                    isAlt = true   -- nach jeder Sektion zurücksetzen
                elseif container.getIsVisibleNonRec == nil
                    or container:getIsVisibleNonRec() then
                    -- Nicht jedes Layout-Kind ist eine Bitmap; ohne die Prüfung
                    -- bricht setImageColor = nil den Beitritt zum Server ab.
                    if container.setImageColor ~= nil and colors[isAlt] ~= nil then
                        container:setImageColor(nil, unpack(colors[isAlt]))
                    end
                    isAlt = not isAlt
                end
            end
            if layout ~= nil and layout.invalidateLayout ~= nil then layout:invalidateLayout() end
        end
        self._updateAlternating = updateAlternating

        -- Zeilen per Klonen der Prefabs anlegen (wie FS25_additionalGameSettings)
        if self.nfWpBoolPrefab ~= nil and self.nfWpLayout ~= nil then
            local self_ref = self

            local function addRow(id, labelKey, callbackName, tooltipKey, isAction)
                -- Aktion: nfWpActionPrefab (Button), Schalter: nfWpBoolPrefab (BinaryOption)
                local prefab = isAction and self_ref.nfWpActionPrefab or self_ref.nfWpBoolPrefab
                if prefab == nil then return end
                local box = prefab:clone(self_ref.nfWpLayout)
                if box == nil then return end
                box:setVisible(true)
                NachbarFelderUIHelper.updateFocusIds(box)
                box.id = id .. "Box"
                local opt = box.elements[1]
                if opt ~= nil then
                    opt.id = id
                    opt.focusOnHighlight = true
                    opt.target = self_ref
                    opt:setCallback("onClickCallback", callbackName)
                    opt:setDisabled(false)
                    self_ref[id] = opt
                    -- Tooltip ins erste Kind mit setText. BinaryOption: der Text selbst,
                    -- Button: das Kind nach dem Rahmen (ThreePartBitmap hat kein setText).
                    local tt = tooltipKey and g_i18n:getText(tooltipKey) or ""
                    for _, kind in ipairs(opt.elements or {}) do
                        if kind.setText ~= nil then
                            if kind ~= nil and kind.setText ~= nil then kind:setText(tt) end
                            break
                        end
                    end
                    if isAction then
                        local key = NachbarFelderWaypointPage.BUTTON_TEXT[id]
                        if key ~= nil then
                            if opt ~= nil and opt.setText ~= nil then opt:setText(g_i18n:getText(key)) end
                        end
                    end
                end
                -- Label links in der Zeile
                local labelEl = box.elements[2]
                if labelEl ~= nil then
                    labelEl:setVisible(true)
                    labelEl:setText(g_i18n:getText(labelKey))
                end
            end

            local function addSection(titleKey)
                local prefab = self_ref.nfWpSectionPrefab
                if prefab == nil then return end
                local h = prefab:clone(self_ref.nfWpLayout)
                if h == nil then return end
                h:setVisible(true)
                h:setText(g_i18n:getText(titleKey))
                h.focusId = FocusManager:serveAutoFocusId()
            end

            addRow("nfWpPrev",     "NF_wpPrev_short",     "onNFWpPrev",     "NF_wpPrev_long",     true)
            addRow("nfWpNext",     "NF_wpNext_short",     "onNFWpNext",     "NF_wpNext_long",     true)
            addSection("NF_wpActions_title")
            addRow("nfWpTeleport",      "NF_wpTeleport_short",      "onNFWpTeleport",      "NF_wpTeleport_long",      true)
            addRow("nfWpType",          "NF_wpType_short",          "onNFWpType",          "NF_wpType_long",          true)
            addRow("nfWpDelete",        "NF_wpDelete_short",        "onNFWpDelete",        "NF_wpDelete_long",        true)
            -- Punkt direkt aus dem Menü setzen, unabhängig von der Tastenbelegung
            addSection("NF_wpNew_section_title")
            addRow("nfWpAddHere",       "NF_wpAddHere_short",       "onNFWpAddHere",       "NF_wpAddHere_long",       true)
            addRow("nfWpAddSpawnHere",  "NF_wpAddSpawnHere_short",  "onNFWpAddSpawnHere",  "NF_wpAddSpawnHere_long",  true)
            addSection("NF_wpMap_section_title")
            addRow("nfWpMapShow",       "NF_wpMapShow_short",       "onNFWpMapShow",       "NF_wpMapShow_long",       false)
            addSection("NF_wpVehicles_section_title")
            addRow("nfWpCatTractorS",   "NF_wpCatTractorS_short",   "onNFWpCatTractorS",   "NF_wpCatTractorS_long",   false)
            addRow("nfWpCatTractorM",   "NF_wpCatTractorM_short",   "onNFWpCatTractorM",   "NF_wpCatTractorM_long",   false)
            addRow("nfWpCatTractorL",   "NF_wpCatTractorL_short",   "onNFWpCatTractorL",   "NF_wpCatTractorL_long",   false)
            addRow("nfWpCatLoader",     "NF_wpCatLoader_short",     "onNFWpCatLoader",     "NF_wpCatLoader_long",     false)
            addRow("nfWpCatTeleLoader", "NF_wpCatTeleLoader_short", "onNFWpCatTeleLoader", "NF_wpCatTeleLoader_long", false)

            -- FocusManager erwartet den Namen des Ziel-Frames auf dem target-Objekt
            self.name = settingsFrame.name

            -- Prefabs werden nicht mehr gebraucht
            if self.nfWpBoolPrefab ~= nil then
                self.nfWpBoolPrefab:delete()
                self.nfWpBoolPrefab = nil
            end
            if self.nfWpActionPrefab ~= nil then
                self.nfWpActionPrefab:delete()
                self.nfWpActionPrefab = nil
            end
            if self.nfWpSectionPrefab ~= nil then
                self.nfWpSectionPrefab:delete()
                self.nfWpSectionPrefab = nil
            end

            updateAlternating(self.nfWpLayout)
            if self.nfWpLayout ~= nil and self.nfWpLayout.invalidateLayout ~= nil then self.nfWpLayout:invalidateLayout() end
        else
            print("LivingRoads: [WP-PAGE] nfWpBoolPrefab nicht gefunden – Rows fehlen")
        end

        -- Hinter den vorhandenen Sub-Kategorien einhängen
        local position = #settingsFrame.subCategoryPages + 1

        local function addAtPosition(element, target, pos)
            if element.parent ~= nil then
                element.parent:removeElement(element)
            end
            table.insert(target.elements, pos, element)
            element.parent = target
        end

        addAtPosition(wpPage, settingsFrame.subCategoryPages[1].parent, position)
        addAtPosition(wpTab,  settingsFrame.subCategoryBox, position)

        table.insert(settingsFrame.subCategoryPages, position, wpPage)
        table.insert(settingsFrame.subCategoryTabs,  position, wpTab)

        -- Am Ende angehängt, daher verschieben sich keine vorhandenen IDs
        InGameMenuSettingsFrame.SUB_CATEGORY.NF_WAYPOINTS = position

        -- HEADER_SLICES geht an OverlayManager:createOverlay, das "prefix.sliceId"
        -- am Punkt zerlegt. Ein leerer String erzeugt beim Öffnen die Warnung
        -- "Identifier '' does not contain prefix or slice ID", daher das Symbol
        -- eines Basisspiel-Tabs übernehmen.
        local slices = InGameMenuSettingsFrame.HEADER_SLICES
        local slice  = ""
        for _, vorhanden in ipairs(slices) do
            if type(vorhanden) == "string"
                    and string.find(vorhanden, ".", 1, true) ~= nil then
                slice = vorhanden
                break
            end
        end
        if slice == "" then
            Logging.info("LivingRoads: [WP-PAGE] Kein gültiger Header-Slice gefunden - Kopfzeile bleibt ohne Symbol.")
        end

        table.insert(slices, position, slice)
        -- HEADER_TITLES löst der Frame jeden Frame über g_i18n:getText auf, und zwar
        -- ohne Mod-Umgebung, also nur gegen die Basisspiel-Texte. Ein Mod-Schlüssel
        -- erzeugt im Entwicklermodus laufend "DevWarning: Missing ... in l10n_de.xml"
        -- (ein ModHub-Prüfpunkt), im normalen Log fällt das nicht auf.
        -- Daher den Schlüssel eines Basisspiel-Tabs eintragen. Sichtbar wird er nie,
        -- der update-Hook unten überschreibt die Kopfzeile, solange unser Tab offen ist.
        local titles = InGameMenuSettingsFrame.HEADER_TITLES
        local titel  = "NF_wpPage_tabTitle"
        for _, vorhanden in ipairs(titles) do
            if type(vorhanden) == "string" and vorhanden ~= "" then
                titel = vorhanden
                break
            end
        end
        table.insert(titles, position, titel)

        settingsFrame:updateAbsolutePosition()

        -- Seite und Tab beim FocusManager registrieren (wie additionalGameSettings)
        local currentGui     = FocusManager.currentGui
        local getDescendants = settingsFrame.getDescendants

        settingsFrame.getDescendants = function() return wpPage:getDescendants() end
        settingsFrame:exposeControlsAsFields(settingsFrame.name)
        settingsFrame.getDescendants = getDescendants

        wpPage:setTarget(settingsFrame, wpPage.target)
        wpTab:setTarget(settingsFrame,  wpTab.target)

        FocusManager:setGui(settingsFrame.name)
        FocusManager:removeElement(wpPage)
        FocusManager:removeElement(wpTab)
        FocusManager:loadElementFromCustomValues(wpPage)
        FocusManager:loadElementFromCustomValues(wpTab)
        FocusManager:setGui(currentGui)

        local self_ref = self
        settingsFrame.onFrameOpen = Utils.appendedFunction(
            settingsFrame.onFrameOpen,
            function(sf)
                if self_ref.nfWpLayout ~= nil and self_ref.nfWpLayout.invalidateLayout ~= nil then
                    self_ref.nfWpLayout:invalidateLayout()
                end
            end
        )

        -- InGameMenuSettingsFrame.update() setzt die Kopfzeile jeden Frame aus
        -- HEADER_TITLES neu, daher hier wieder unseren Titel eintragen.
        local nfTabIdx = position
        settingsFrame.update = Utils.appendedFunction(
            settingsFrame.update,
            function(sf, dt)
                local paging = sf.subCategoryPaging
                if paging ~= nil and paging.state == nfTabIdx then
                    if sf.categoryHeaderText ~= nil and sf.categoryHeaderText.setText ~= nil then
                        local title = nfTabTitel()
                        sf.categoryHeaderText:setText(title)
                    end
                end
            end
        )

        -- Beim Wechsel auf unseren Tab: Kopfzeile, Scrollbar und Fokus-Links setzen
        settingsFrame.subCategoryPaging.onClickCallback = Utils.overwrittenFunction(
            settingsFrame.subCategoryPaging.onClickCallback,
            function(pagingElem, superFunc, state)
                local ret = superFunc(pagingElem, state)
                local val = pagingElem.texts and pagingElem.texts[state]
                if val ~= nil and tonumber(val) == InGameMenuSettingsFrame.SUB_CATEGORY.NF_WAYPOINTS then
                    local sf = g_inGameMenu and g_inGameMenu.pageSettings
                    if sf ~= nil then
                        local title = nfTabTitel()
                        local hdrKeys = {"subCategoryHeaderText","subCategoryHeader","categoryTitle","headerTitle","pageTitle","subCategoryTitle","headerText","categoryHeaderText"}
                        for _, name in ipairs(hdrKeys) do
                            if sf[name] ~= nil and sf[name].setText ~= nil then
                                sf[name]:setText(title)
                            end
                        end
                    end
                    self_ref:onTabOpen(settingsFrame)
                end
                return ret
            end
        )

        print("LivingRoads: [WP-PAGE] Wegpunkt-Tab eingefügt (pos=" .. position .. ")")

        -- BetterContracts ermittelt seinen Tab bei jedem Öffnen als letzten Paging-
        -- Eintrag und würde damit unsere Seite öffnen. Unser Hook hängt hinter dem
        -- von BC und setzt dessen modState auf den Paging-State mit BCs Seitennummer.
        local bcIdx = InGameMenuSettingsFrame.SUB_CATEGORY ~= nil
            and InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS or nil
        if bcIdx ~= nil then
            settingsFrame.onFrameOpen = Utils.appendedFunction(settingsFrame.onFrameOpen,
                function(sf)
                    local function schritt()
                        local bc = BetterContracts
                        if bc == nil then
                            local env = _G["FS25_BetterContracts"]
                            if env ~= nil then bc = env.BetterContracts end
                        end
                        if bc == nil or bc.settingsMgr == nil then return end
                        local target = InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS
                        local paging = sf.subCategoryPaging
                        if target == nil or paging == nil or paging.texts == nil then return end
                        for st, txt in ipairs(paging.texts) do
                            if tonumber(txt) == target then
                                bc.settingsMgr.modState = st
                                break
                            end
                        end
                    end
                    schritt()
                end)
            print("LivingRoads: [WP-PAGE] BetterContracts-Kompatibilität aktiv (modState-Korrektur)")
        end
    end
    schritt()
end

function NachbarFelderWaypointPage:onTabOpen(settingsFrame)
    if settingsFrame ~= nil then
        if settingsFrame.updateAbsolutePosition ~= nil then settingsFrame:updateAbsolutePosition() end
        local title = nfTabTitel()
        local sfHdrKeys = {"categoryHeaderText","subCategoryHeaderText","subCategoryHeader","categoryTitle","headerTitle","pageTitle","subCategoryTitle","headerText"}
        for _, name in ipairs(sfHdrKeys) do
            if settingsFrame[name] ~= nil and settingsFrame[name].setText ~= nil then
                settingsFrame[name]:setText(title)
            end
        end
        if self.nfWpLayout ~= nil and self.nfWpLayout.invalidateLayout ~= nil then
            self.nfWpLayout:invalidateLayout()
        end
    end
    self:refreshWpInfo()
    if self.nfWpLayout ~= nil and self._updateAlternating ~= nil then
        self._updateAlternating(self.nfWpLayout)
    end
    if settingsFrame ~= nil and settingsFrame.settingsSlider ~= nil and self.nfWpLayout ~= nil
       and settingsFrame.settingsSlider.setDataElement ~= nil then
        settingsFrame.settingsSlider:setDataElement(self.nfWpLayout)
    end
    if settingsFrame ~= nil and self.nfWpLayout ~= nil and settingsFrame.subCategoryPaging ~= nil
       and self.nfWpLayout.findFirstFocusable ~= nil and self.nfWpLayout.elements ~= nil then
        local layout = self.nfWpLayout
        local first  = layout:findFirstFocusable(true)
        local last   = layout.elements[#layout.elements]
        if first ~= nil then
            FocusManager:linkElements(settingsFrame.subCategoryPaging, FocusManager.BOTTOM, first)
        end
        if last ~= nil then
            FocusManager:linkElements(settingsFrame.subCategoryPaging, FocusManager.TOP, last)
        end
    end
end

-- ============================================================
-- Info-Anzeige aktualisieren
-- ============================================================
function NachbarFelderWaypointPage:refreshWpInfo()
    local mgr   = self.manager
    local wps   = (mgr ~= nil) and mgr.userTrafficWaypoints or {}
    local count = #wps
    local jetzt = g_time or 0

    -- Nach "hier setzen" zum neuen Punkt springen, sobald er in der Liste steht.
    -- Auf MP-Clients erst nach dem Server-Sync, daher mit Frist.
    if self._springeZuNeuemBis ~= nil then
        if count > (self._anzahlVorNeu or 0) then
            self.currentIdx = count
            self._springeZuNeuemBis = nil
        elseif jetzt > self._springeZuNeuemBis then
            self._springeZuNeuemBis = nil
        end
    end

    if count > 0 and (self.currentIdx == nil or self.currentIdx < 1) then
        self.currentIdx = 1
    end
    if self.currentIdx ~= nil and self.currentIdx > count then
        self.currentIdx = count > 0 and count or nil
    end

    if self.nfWpInfoText ~= nil then
        local text
        -- Meldungen aus "hier setzen" stehen in der Infozeile, weil das Menü
        -- Ingame-Benachrichtigungen verdeckt.
        if self._hinweisText ~= nil and jetzt > (self._hinweisBis or 0) then
            self._hinweisText = nil
        end
        if self._hinweisText ~= nil then
            text = self._hinweisText
        elseif count == 0 then
            text = g_i18n:getText("NF_wpNone")
        else
            local idx = self.currentIdx or 1
            local wp  = wps[idx]
            -- Punkte ohne gültige Koordinaten (z. B. aus einem fehlerhaften
            -- Server-Sync) nicht formatieren, sonst bricht der Beitritt ab.
            if wp ~= nil and tonumber(wp.x) ~= nil and tonumber(wp.z) ~= nil then
                text = string.format("WP %d / %d     x = %d     z = %d     [%s]",
                    idx, count, math.floor(wp.x), math.floor(wp.z), nfPageText(nfCatKey(wp.cat)))
            else
                text = nfPageText("NF_msg_wpGespeichert", count)
            end
        end
        if self.nfWpInfoText.setText ~= nil then
            self.nfWpInfoText:setText(text)
        end
    end

    for id, key in pairs(NachbarFelderWaypointPage.BUTTON_TEXT) do
        local elem = self[id]
        if elem ~= nil and elem.setText ~= nil then
            elem:setText(nfPageText(key))
        end
    end

    -- Typ-Button zeigt die aktuelle Kategorie, ein Klick schaltet weiter
    if self.nfWpType ~= nil and self.nfWpType.setText ~= nil then
        local wp      = (count > 0 and self.currentIdx ~= nil) and wps[self.currentIdx] or nil
        local catName = (wp ~= nil) and nfPageText(nfCatKey(wp.cat)) or "-"
        self.nfWpType:setText(catName)
    end

    if self.nfWpMapShow ~= nil and mgr ~= nil then
        local STATE_YES_V = BinaryOptionElement ~= nil and BinaryOptionElement.STATE_RIGHT or 2
        local mapState  = (mgr._wpHotspotsEnabled ~= false) and STATE_YES_V or 1
        nfSetOptionState(self.nfWpMapShow, mapState)
    end

    if mgr ~= nil then
        local STATE_YES_V = BinaryOptionElement ~= nil and BinaryOptionElement.STATE_RIGHT or 2
        local cats = mgr.vehicleCatEnabled or {}
        local catRows = {
            { elem = self.nfWpCatTractorS,   key = "TRACTORSS"           },
            { elem = self.nfWpCatTractorM,   key = "TRACTORSM"           },
            { elem = self.nfWpCatTractorL,   key = "TRACTORSL"           },
            { elem = self.nfWpCatLoader,     key = "WHEELLOADERVEHICLES" },
            { elem = self.nfWpCatTeleLoader, key = "TELELOADERVEHICLES"  },
        }
        for _, r in ipairs(catRows) do
            if r.elem ~= nil then
                local enabled = cats[r.key] ~= false
                nfSetOptionState(r.elem, enabled and STATE_YES_V or 1)
            end
        end
    end

    -- Eingreifende Aktionen nur für Admins; Blättern und Karten-Schalter für alle.
    local isAdmin = self.manager ~= nil and self.manager.getIsLocalAdmin ~= nil
                    and self.manager:getIsLocalAdmin()
    local hasWp = count > 0 and self.currentIdx ~= nil
    nfSetDisabled(self.nfWpTeleport, not hasWp or not isAdmin)
    nfSetDisabled(self.nfWpType,     not hasWp or not isAdmin)
    nfSetDisabled(self.nfWpDelete,   not hasWp or not isAdmin)
    nfSetDisabled(self.nfWpAddHere,      not isAdmin)
    nfSetDisabled(self.nfWpAddSpawnHere, not isAdmin)
    nfSetDisabled(self.nfWpPrev,     count == 0)
    nfSetDisabled(self.nfWpNext,     count == 0)
    local catIds = { "nfWpCatTractorS", "nfWpCatTractorM", "nfWpCatTractorL",
                     "nfWpCatLoader", "nfWpCatTeleLoader" }
    for _, catId in ipairs(catIds) do
        local ctl = self[catId]
        nfSetDisabled(ctl, not isAdmin)
    end

    if self.nfWpLayout ~= nil then
        if self.nfWpLayout ~= nil and self.nfWpLayout.invalidateLayout ~= nil then self.nfWpLayout:invalidateLayout() end
    end
end

-- ============================================================
-- Callbacks (vom GUI-System auf der Seiten-Instanz aufgerufen)
-- ============================================================
local function getPage()
    return g_NachbarFelderWaypointPage
end

local STATE_YES = function()
    return BinaryOptionElement ~= nil and BinaryOptionElement.STATE_RIGHT or 2
end

function NachbarFelderWaypointPage:onClickNFWpTab()
    local page = getPage()
    if page == nil then return end
    local function schritt()
        local sf = g_inGameMenu and g_inGameMenu.pageSettings
        if sf == nil then return end
        -- setState erwartet den Paging-State, nicht die Seitennummer. Bei
        -- ausgeblendeten Sub-Kategorien weichen beide ab, daher den passenden State suchen.
        local target = InGameMenuSettingsFrame.SUB_CATEGORY.NF_WAYPOINTS
        local state  = target
        local paging = sf.subCategoryPaging
        if paging ~= nil and paging.texts ~= nil then
            for st, txt in ipairs(paging.texts) do
                if tonumber(txt) == target then
                    state = st
                    break
                end
            end
        end
        sf.subCategoryPaging:setState(state, true)
        -- setState löst onClickCallback nicht zuverlässig aus
        page:onTabOpen(sf)
    end
    schritt()
end

function NachbarFelderWaypointPage:onNFWpPrev(state, elem)
    local page = getPage()
    if page == nil then return end
    page._hinweisText = nil
    local count = #(page.manager.userTrafficWaypoints or {})
    if count == 0 then page:refreshWpInfo() return end
    page.currentIdx = ((page.currentIdx or 1) - 2) % count + 1
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpNext(state, elem)
    local page = getPage()
    if page == nil then return end
    page._hinweisText = nil
    local count = #(page.manager.userTrafficWaypoints or {})
    if count == 0 then page:refreshWpInfo() return end
    page.currentIdx = ((page.currentIdx or 0) % count) + 1
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpTeleport(state, elem)
    local page = getPage()
    if page == nil then return end
    -- Admin-Prüfung inline, requireAdmin ist erst weiter unten definiert
    local mgr = page.manager
    if mgr ~= nil and mgr.getIsLocalAdmin ~= nil and not mgr:getIsLocalAdmin() then
        if mgr.notifyAdminRequired ~= nil then mgr:notifyAdminRequired() end
        return
    end
    local wp = (page.manager.userTrafficWaypoints or {})[page.currentIdx or 0]
    if wp ~= nil then page.manager:_teleportToWp(wp) end
    page:refreshWpInfo()
end

-- Auf MP-Clients gehen Änderungen als Event an den Server. Der Server besitzt die
-- Wegpunktdatei, lokale Änderungen würde der nächste Sync überschreiben.
local function isMpClient()
    return g_currentMission ~= nil and not g_currentMission:getIsServer() and g_client ~= nil
end

-- Absicherung, falls ein Control trotz Ausgrauen ausgelöst wird.
-- Der Server prüft zusätzlich selbst.
local function requireAdmin(page)
    local mgr = page ~= nil and page.manager or nil
    if mgr ~= nil and mgr.getIsLocalAdmin ~= nil and not mgr:getIsLocalAdmin() then
        if mgr.notifyAdminRequired ~= nil then mgr:notifyAdminRequired() end
        return false
    end
    return true
end

function NachbarFelderWaypointPage:onNFWpType(state, elem)
    local page = getPage()
    if page == nil then return end
    if not requireAdmin(page) then return end
    local idx = page.currentIdx or 0
    local wp = (page.manager.userTrafficWaypoints or {})[idx]
    if wp ~= nil then
        -- Normal -> Kurz -> Lang -> Spawnpunkt -> Normal
        local naechsterTyp = { [0] = 1, [1] = 2, [2] = 4, [4] = 0 }
        local newCat = naechsterTyp[wp.cat or 0] or 0
        wp.cat = newCat  -- sofort lokal anzeigen; Server-Sync bestätigt
        if isMpClient() then
            g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                NachbarFelderWaypointEditEvent.OP_SETCAT, idx, newCat))
        else
            page.manager:saveWaypoints()
            -- Kartenbeschriftung ("12 S" für Spawnpunkte) sofort aktualisieren
            if page.manager ~= nil and page.manager.updateWpHotspots ~= nil then page.manager:updateWpHotspots() end
        end
    end
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpDelete(state, elem)
    local page = getPage()
    if page == nil then return end
    if not requireAdmin(page) then return end
    local mgr = page.manager
    local idx = page.currentIdx
    local wps = mgr.userTrafficWaypoints or {}
    if idx ~= nil and wps[idx] ~= nil then
        local wp = wps[idx]
        if isMpClient() then
            g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                NachbarFelderWaypointEditEvent.OP_DELETE, idx))
            page.currentIdx = nil  -- Server-Sync liefert die neue Liste
            if g_currentMission ~= nil then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    nfPageText("NF_msg_wpLoeschungGesendet", idx))
            end
        else
            table.remove(wps, idx)
            mgr:saveWaypoints()
            mgr:updateWpHotspots()
            local count = #wps
            page.currentIdx = (count == 0) and nil or math.min(idx, count)
            if g_currentMission ~= nil then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    nfPageText("NF_msg_wpGeloescht",
                        idx, math.floor(wp.x), math.floor(wp.z), count))
            end
        end
    end
    page:refreshWpInfo()
end

-- Punkt an der eigenen Position setzen, wie die Taste "Wegpunkt setzen"
-- (im Fahrzeug Fahrtrichtung, zu Fuß Blickrichtung).
local function setzePunktHier(cat)
    local page = getPage()
    if page == nil or page.manager == nil or page.manager.addWaypointAtPlayer == nil then return end
    if not requireAdmin(page) then return end
    page._hinweisText = nil
    local vorher = #(page.manager.userTrafficWaypoints or {})
    local gesetzt, grund = false, nil
    if page.manager.addWaypointAtPlayer ~= nil then
        gesetzt, grund = page.manager:addWaypointAtPlayer(cat)
    else
        print("LivingRoads: [WP-PAGE] addWaypointAtPlayer fehlt")
    end
    if gesetzt then
        -- Auf MP-Clients ist der Punkt erst nach dem Server-Sync in der Liste
        page._anzahlVorNeu      = vorher
        page._springeZuNeuemBis = (g_time or 0) + 10000
    else
        page._hinweisText = grund or nfPageText("NF_msg_nichtGesetzt")
        page._hinweisBis  = (g_time or 0) + 8000
    end
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpAddHere(state, elem)
    setzePunktHier(0)
end

function NachbarFelderWaypointPage:onNFWpAddSpawnHere(state, elem)
    setzePunktHier(NachbarFelderManager.WP_CAT_SPAWN or 4)
end

function NachbarFelderWaypointPage:onNFWpMapShow(state, elem)
    local page = getPage()
    if page == nil then return end
    -- setWpHotspotsVisible baut die Hotspots auch neu auf bzw. entfernt sie;
    -- nur das Flag zu setzen reicht nicht.
    page.manager:setWpHotspotsVisible(state == STATE_YES())
end

local VEHCAT_IDX = {
    TRACTORSS = 1, TRACTORSM = 2, TRACTORSL = 3,
    WHEELLOADERVEHICLES = 4, TELELOADERVEHICLES = 5,
}

local function setCatEnabled(catKey, state)
    local page = getPage()
    if page == nil then return end
    if not requireAdmin(page) then
        if page ~= nil and page.refreshWpInfo ~= nil then page:refreshWpInfo() end  -- Schalter zurücksetzen
        return
    end
    local mgr = page.manager
    local enabled = (state == STATE_YES())
    mgr.vehicleCatEnabled = mgr.vehicleCatEnabled or {}
    mgr.vehicleCatEnabled[catKey] = enabled  -- lokal für sofortige Anzeige
    mgr.trafficVehicleList = nil  -- Liste beim nächsten Spawn neu aufbauen
    if isMpClient() then
        g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
            NachbarFelderWaypointEditEvent.OP_VEHCAT,
            VEHCAT_IDX[catKey] or 0, enabled and 1 or 0))
    else
        if mgr ~= nil and mgr.saveWaypoints ~= nil then mgr:saveWaypoints() end
    end
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpCatTractorS(state, elem)   setCatEnabled("TRACTORSS",           state) end
function NachbarFelderWaypointPage:onNFWpCatTractorM(state, elem)   setCatEnabled("TRACTORSM",           state) end
function NachbarFelderWaypointPage:onNFWpCatTractorL(state, elem)   setCatEnabled("TRACTORSL",           state) end
function NachbarFelderWaypointPage:onNFWpCatLoader(state, elem)     setCatEnabled("WHEELLOADERVEHICLES", state) end
function NachbarFelderWaypointPage:onNFWpCatTeleLoader(state, elem) setCatEnabled("TELELOADERVEHICLES",  state) end

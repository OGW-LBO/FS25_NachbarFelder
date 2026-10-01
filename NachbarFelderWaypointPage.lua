-- ============================================================
-- NachbarFelderWaypointPage
-- Eigener Sub-Kategorie-Tab in ESC → Allgemeine Einstellungen
-- für den Wegpunkt-Manager.
-- Muster: FS25_additionalGameSettings (Rockstar)
-- ============================================================
NachbarFelderWaypointPage = {}
local NachbarFelderWaypointPage_mt = Class(NachbarFelderWaypointPage, FrameElement)
local modDirectory = g_currentModDirectory

-- Globale Referenz für Callbacks (Sicherheit, analog additionalGameSettings)
g_NachbarFelderWaypointPage = nil

-- Build 135: Beschriftung der Aktions-Buttons (l10n-Keys). Der Typ-Button zeigt
-- stattdessen die aktuelle Kategorie (refreshWpInfo).
NachbarFelderWaypointPage.BUTTON_TEXT = {
    nfWpPrev         = "NF_wpBtn_prev",
    nfWpNext         = "NF_wpBtn_next",
    nfWpTeleport     = "NF_wpBtn_teleport",
    nfWpDelete       = "NF_wpBtn_delete",
    nfWpAddHere      = "NF_wpBtn_set",
    nfWpAddSpawnHere = "NF_wpBtn_set",
    nfAuftragHier    = "NF_auftragBtn",   -- Build 139
    nfAuftragSpawnHier = "NF_wpBtn_set",  -- Build 148
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
    -- g_i18n.getText Wrapper: externe l10n-Dateien greifen erst nach vollem Spielneustart.
    -- Dieser Fallback liefert den Text sofort (FS25 uppercased den Key intern → "NF_WPPAGE_TABTITLE").
    if g_i18n and g_i18n.getText and not g_i18n._nfWpTabTitleFixed then
        local origGetText = g_i18n.getText
        g_i18n.getText = function(self_i18n, key, ...)
            if key ~= nil and string.upper(tostring(key)) == "NF_WPPAGE_TABTITLE" then
                local lang = g_languageShort or "en"
                return (lang == "de") and "Wegpunkte" or "Waypoints"
            end
            return origGetText(self_i18n, key, ...)
        end
        g_i18n._nfWpTabTitleFixed = true
    end

    -- Build 135: eigene GUI-Profile (Aktions-Button) vor dem loadGui laden -
    -- Gui:loadProfiles(xmlFilename), Muster wie FS25_EasyDevControls.
    -- Schon vorhandene Profilnamen ueberschreibt das Spiel nicht (Gui:loadProfileSet).
    if not NachbarFelderWaypointPage._profileGeladen then
        NachbarFelderWaypointPage._profileGeladen = true
        local okP, errP = pcall(function()
            g_gui:loadProfiles(Utils.getFilename("gui/NachbarFelderGuiProfiles.xml", modDirectory))
        end)
        if not okP then
            print("NachbarFelder: [WP-PAGE] loadProfiles Fehler: " .. tostring(errP))
        end
    end

    local ok, err = pcall(function()
        -- XML laden — setzt self.nfWpPage, self.nfWpTab, self.nfWp* als Felder
        g_gui:loadGui(
            Utils.getFilename("gui/NachbarFelderWaypointPage.xml", modDirectory),
            "NachbarFelderWaypointPage",
            self
        )
    end)
    if not ok then
        print("NachbarFelder: [WP-PAGE] loadGui Fehler: " .. tostring(err))
        return
    end

    ok, err = pcall(function()
        local settingsFrame = g_inGameMenu and g_inGameMenu.pageSettings
        if settingsFrame == nil then
            print("NachbarFelder: [WP-PAGE] pageSettings nicht verfügbar")
            return
        end

        local wpPage = self.nfWpPage
        local wpTab  = self.nfWpTab
        if wpPage == nil or wpTab == nil then
            print("NachbarFelder: [WP-PAGE] nfWpPage/nfWpTab nicht gefunden (XML-Fehler?)")
            return
        end

        -- Tab-Titel direkt setzen: $l10n_ wird vom C++-Parser vor dem Lua-Wrapper aufgeloest,
        -- daher setText nach loadGui als zuverlaessiger Fallback.
        pcall(function()
            local lang  = g_languageShort or "en"
            local title = (lang == "de") and "Wegpunkte" or "Waypoints"
            if wpTab.setText ~= nil then wpTab:setText(title) end
        end)

        -- Prefabs nach loadGui ausblenden (bleiben als Klonvorlagen, sollen nicht sichtbar sein)
        if self.nfWpBoolPrefab    ~= nil then self.nfWpBoolPrefab:setVisible(false)    end
        if self.nfWpActionPrefab  ~= nil then self.nfWpActionPrefab:setVisible(false)  end
        if self.nfWpSectionPrefab ~= nil then self.nfWpSectionPrefab:setVisible(false) end

        -- Alternating-Hintergründe aktualisieren (Muster: FS25_additionalGameSettings)
        -- Muss nach jedem Hinzufügen von Rows aufgerufen werden.
        local function updateAlternating(layout)
            local colors = InGameMenuSettingsFrame.COLOR_ALTERNATING
            if colors == nil then return end
            local isAlt = true
            for _, container in ipairs(layout.elements) do
                pcall(function()
                    if container.name == "sectionHeader" then
                        isAlt = true   -- nach jeder Sektion zurücksetzen
                    elseif container.getIsVisibleNonRec == nil
                        or container:getIsVisibleNonRec() then
                        container:setImageColor(nil, unpack(colors[isAlt]))
                        isAlt = not isAlt
                    end
                end)
            end
            pcall(function() layout:invalidateLayout() end)
        end
        -- Referenz für spätere Aufrufe in onTabOpen speichern
        self._updateAlternating = updateAlternating

        -- Rows per Klonen anlegen — Muster identisch zu FS25_additionalGameSettings
        if self.nfWpBoolPrefab ~= nil and self.nfWpLayout ~= nil then
            local self_ref = self

            local function addRow(id, labelKey, callbackName, tooltipKey, isAction)
                -- Aktions-Zeilen: nfWpActionPrefab (Button, Build 135 - vorher MultiTextOption)
                -- Toggle-Zeilen:  nfWpBoolPrefab   (BinaryOption, Nein/Ja)
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
                    -- Tooltip: erstes Kind mit setText. BinaryOption: der Text selbst;
                    -- Button: nach dem Rahmen (ThreePartBitmap hat kein setText).
                    local tt = tooltipKey and g_i18n:getText(tooltipKey) or ""
                    for _, kind in ipairs(opt.elements or {}) do
                        if kind.setText ~= nil then
                            pcall(function() kind:setText(tt) end)
                            break
                        end
                    end
                    -- Aktions-Zeilen: Beschriftung des Buttons (refreshWpInfo erneuert sie)
                    if isAction then
                        local key = NachbarFelderWaypointPage.BUTTON_TEXT[id]
                        if key ~= nil then
                            pcall(function() opt:setText(g_i18n:getText(key)) end)
                        end
                    end
                end
                -- Label immer sichtbar – zeigt Beschriftung der Zeile in weiß links.
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
            -- Build 134: neuer Punkt direkt aus dem Menue - ohne Taste (deren Belegung
            -- im Spielerprofil abweichen kann) und ohne Typ-Durchklicken
            addSection("NF_wpNew_section_title")
            addRow("nfWpAddHere",       "NF_wpAddHere_short",       "onNFWpAddHere",       "NF_wpAddHere_long",       true)
            addRow("nfWpAddSpawnHere",  "NF_wpAddSpawnHere_short",  "onNFWpAddSpawnHere",  "NF_wpAddSpawnHere_long",  true)
            -- Build 139: Auftrag an den Lohnunternehmer - das Feld an der eigenen Position
            addSection("NF_auftrag_section_title")
            addRow("nfAuftragHier",     "NF_auftragHier_short",     "onNFAuftragHier",     "NF_auftragHier_long",     true)
            -- Build 148: Spawnpunkt gleich hier setzen - zuverlaessiger als die automatische Platzsuche
            addRow("nfAuftragSpawnHier", "NF_wpAddSpawnHere_short", "onNFWpAddSpawnHere", "NF_auftragSpawnHier_long", true)
            addSection("NF_wpMap_section_title")
            addRow("nfWpMapShow",       "NF_wpMapShow_short",       "onNFWpMapShow",       "NF_wpMapShow_long",       false)
            addSection("NF_wpVehicles_section_title")
            addRow("nfWpCatTractorS",   "NF_wpCatTractorS_short",   "onNFWpCatTractorS",   "NF_wpCatTractorS_long",   false)
            addRow("nfWpCatTractorM",   "NF_wpCatTractorM_short",   "onNFWpCatTractorM",   "NF_wpCatTractorM_long",   false)
            addRow("nfWpCatTractorL",   "NF_wpCatTractorL_short",   "onNFWpCatTractorL",   "NF_wpCatTractorL_long",   false)
            addRow("nfWpCatLoader",     "NF_wpCatLoader_short",     "onNFWpCatLoader",     "NF_wpCatLoader_long",     false)
            addRow("nfWpCatTeleLoader", "NF_wpCatTeleLoader_short", "onNFWpCatTeleLoader", "NF_wpCatTeleLoader_long", false)

            -- FocusManager braucht passenden Zielobjekt-Namen auf dem target-Objekt
            self.name = settingsFrame.name

            -- Prefabs löschen (analog BC SettingsManager Zeilen 71-74)
            pcall(function()
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
            end)

            -- Alternating-Hintergründe initial setzen
            updateAlternating(self.nfWpLayout)
            pcall(function() self.nfWpLayout:invalidateLayout() end)
        else
            print("NachbarFelder: [WP-PAGE] nfWpBoolPrefab nicht gefunden – Rows fehlen")
        end

        -- Am Ende der vorhandenen Sub-Kategorien einfügen
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

        -- SUB_CATEGORY-ID registrieren (am Ende, keine ID-Verschiebung nötig)
        InGameMenuSettingsFrame.SUB_CATEGORY.NF_WAYPOINTS = position

        -- HEADER_SLICES landet in OverlayManager:createOverlay, das den
        -- Identifier als "prefix.sliceId" am ersten Punkt zerlegt. Ein leerer
        -- String ergibt dort prefix == nil und beim Öffnen des Tabs die
        -- Warnung "Identifier '' does not contain prefix or slice ID"
        -- (OverlayManager.lua:159). Deshalb das Symbol eines vorhandenen
        -- Basisspiel-Tabs übernehmen.
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
            Logging.info("NachbarFelder: [WP-PAGE] Kein gültiger Header-Slice gefunden - Kopfzeile bleibt ohne Symbol.")
        end

        table.insert(slices, position, slice)
        -- Key stammt aus externer l10n-Datei (l10n/l10n_de.xml) → in globalem g_i18n verfügbar
        table.insert(InGameMenuSettingsFrame.HEADER_TITLES, position, "NF_wpPage_tabTitle")

        settingsFrame:updateAbsolutePosition()

        -- FocusManager-Registrierung (analog additionalGameSettings)
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
                pcall(function()
                    if self_ref.nfWpLayout ~= nil then
                        self_ref.nfWpLayout:invalidateLayout()
                    end
                end)
            end
        )

        -- update()-Hook: Header jeden Frame korrigieren wenn unser Tab aktiv ist.
        -- Nötig weil InGameMenuSettingsFrame.update() den Header aus HEADER_TITLES
        -- neu setzt und unser externer l10n-Schlüssel dabei "MISSING" liefert.
        local nfTabIdx = position
        settingsFrame.update = Utils.appendedFunction(
            settingsFrame.update,
            function(sf, dt)
                pcall(function()
                    local paging = sf.subCategoryPaging
                    if paging ~= nil and paging.state == nfTabIdx then
                        if sf.categoryHeaderText ~= nil and sf.categoryHeaderText.setText ~= nil then
                            local title = (g_languageShort == "de") and "Wegpunkte" or "Waypoints"
                            sf.categoryHeaderText:setText(title)
                        end
                    end
                end)
            end
        )

        -- Paging-Callback: Scrollbar + Fokus-Links + Header-Fix wenn Tab gewählt wird
        settingsFrame.subCategoryPaging.onClickCallback = Utils.overwrittenFunction(
            settingsFrame.subCategoryPaging.onClickCallback,
            function(pagingElem, superFunc, state)
                local ret = superFunc(pagingElem, state)
                local val = pagingElem.texts and pagingElem.texts[state]
                if val ~= nil and tonumber(val) == InGameMenuSettingsFrame.SUB_CATEGORY.NF_WAYPOINTS then
                    -- Header-Text direkt überschreiben (superFunc hat MISSING gesetzt)
                    local sf = g_inGameMenu and g_inGameMenu.pageSettings
                    pcall(function()
                        if sf ~= nil then
                            local lang = g_languageShort or "en"
                            local title = (lang == "de") and "Wegpunkte" or "Waypoints"
                            local hdrKeys = {"subCategoryHeaderText","subCategoryHeader","categoryTitle","headerTitle","pageTitle","subCategoryTitle","headerText","categoryHeaderText"}
                            for _, name in ipairs(hdrKeys) do
                                if sf[name] ~= nil and sf[name].setText ~= nil then
                                    sf[name]:setText(title)
                                end
                            end
                        end
                    end)
                    self_ref:onTabOpen(settingsFrame)
                end
                return ret
            end
        )

        print("NachbarFelder: [WP-PAGE] Wegpunkt-Tab eingefügt (pos=" .. position .. ")")

        -- BetterContracts-Kompatibilität: BC berechnet bei JEDEM Menü-Öffnen
        -- seinen Tab-Index als "letzter Paging-Eintrag" (Annahme im BC-Code:
        -- "our mod button should always be the last one"). Seit unser
        -- Wegpunkte-Tab dahinter hängt, öffnete BCs Tab-Klick UNSERE Seite.
        -- Fix: Wir hängen uns NACH BCs onFrameOpen-Hook (unsere Injection
        -- läuft später → appended-Kette: Vanilla → BC → wir) und setzen
        -- BCs modState auf den Paging-State, dessen Wert BCs Seitennummer ist.
        local bcIdx = InGameMenuSettingsFrame.SUB_CATEGORY ~= nil
            and InGameMenuSettingsFrame.SUB_CATEGORY.BCONTRACTS or nil
        if bcIdx ~= nil then
            settingsFrame.onFrameOpen = Utils.appendedFunction(settingsFrame.onFrameOpen,
                function(sf)
                    pcall(function()
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
                    end)
                end)
            print("NachbarFelder: [WP-PAGE] BetterContracts-Kompatibilität aktiv (modState-Korrektur)")
        end
    end)
    if not ok then
        print("NachbarFelder: [WP-PAGE] inject Fehler: " .. tostring(err))
    end
end

function NachbarFelderWaypointPage:onTabOpen(settingsFrame)
    pcall(function()
        if settingsFrame ~= nil then
            settingsFrame:updateAbsolutePosition()
            -- Header-Text direkt überschreiben (HEADER_TITLES-Lookup uppercased intern)
            local lang = g_languageShort or "en"
            local title = (lang == "de") and "Wegpunkte" or "Waypoints"
            local sfHdrKeys = {"categoryHeaderText","subCategoryHeaderText","subCategoryHeader","categoryTitle","headerTitle","pageTitle","subCategoryTitle","headerText"}
            for _, name in ipairs(sfHdrKeys) do
                if settingsFrame[name] ~= nil and settingsFrame[name].setText ~= nil then
                    settingsFrame[name]:setText(title)
                end
            end
            if self.nfWpLayout ~= nil then
                self.nfWpLayout:invalidateLayout()
            end
        end
    end)
    self:refreshWpInfo()
    -- Alternating-Hintergründe auffrischen (analog AGS onFrameOpen)
    pcall(function()
        if self.nfWpLayout ~= nil and self._updateAlternating ~= nil then
            self._updateAlternating(self.nfWpLayout)
        end
    end)
    -- Scrollbar auf unseren Layout zeigen
    pcall(function()
        if settingsFrame ~= nil and settingsFrame.settingsSlider ~= nil and self.nfWpLayout ~= nil then
            settingsFrame.settingsSlider:setDataElement(self.nfWpLayout)
        end
        if settingsFrame ~= nil and self.nfWpLayout ~= nil then
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
    end)
end

-- ============================================================
-- Info-Anzeige aktualisieren
-- ============================================================
function NachbarFelderWaypointPage:refreshWpInfo()
    local mgr   = self.manager
    local wps   = (mgr ~= nil) and mgr.userTrafficWaypoints or {}
    local count = #wps
    local jetzt = g_time or 0

    -- Build 134: nach "hier setzen" zum neuen Punkt springen, sobald er in der
    -- Liste ist (MP-Client: erst mit dem Sync vom Server, deshalb Frist)
    if self._springeZuNeuemBis ~= nil then
        if count > (self._anzahlVorNeu or 0) then
            self.currentIdx = count
            self._springeZuNeuemBis = nil
        elseif jetzt > self._springeZuNeuemBis then
            self._springeZuNeuemBis = nil
        end
    end

    -- Index korrigieren
    if count > 0 and (self.currentIdx == nil or self.currentIdx < 1) then
        self.currentIdx = 1
    end
    if self.currentIdx ~= nil and self.currentIdx > count then
        self.currentIdx = count > 0 and count or nil
    end

    -- Info-Text
    if self.nfWpInfoText ~= nil then
        local text
        -- Build 134: Hinweis aus "hier setzen" (z.B. zu nah an WP 12) - Ingame-
        -- Meldungen verdeckt das Menue, deshalb hier in der Infozeile
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
            if wp ~= nil then
                local catNames = { [0]="Normal", [1]="Kurz", [2]="Lang", [4]="Spawnpunkt" }
                local catName  = catNames[wp.cat or 0] or "Normal"
                text = string.format("WP %d / %d     x = %d     z = %d     [%s]",
                    idx, count, math.floor(wp.x), math.floor(wp.z), catName)
            else
                text = count .. " Wegpunkte gespeichert"
            end
        end
        self.nfWpInfoText:setText(text)
    end

    -- Aktions-Buttons (Build 135: echte Buttons) - Beschriftung auffrischen
    for id, key in pairs(NachbarFelderWaypointPage.BUTTON_TEXT) do
        local elem = self[id]
        if elem ~= nil and elem.setText ~= nil then
            pcall(function() elem:setText(g_i18n:getText(key)) end)
        end
    end

    -- Typ-Button: zeigt die aktuelle Kategorie, Klick schaltet weiter
    if self.nfWpType ~= nil and self.nfWpType.setText ~= nil then
        local catNames = { [0]="Normal", [1]="Kurz", [2]="Lang", [4]="Spawnpunkt" }
        local wp       = (count > 0 and self.currentIdx ~= nil) and wps[self.currentIdx] or nil
        local catName  = wp ~= nil and (catNames[wp.cat or 0] or "Normal") or "-"
        pcall(function() self.nfWpType:setText(catName) end)
    end

    -- Map-Toggle: BinaryOption, Nein/Ja + Zustand korrekt setzen
    if self.nfWpMapShow ~= nil and mgr ~= nil then
        local STATE_YES_V = BinaryOptionElement ~= nil and BinaryOptionElement.STATE_RIGHT or 2
        local mapState  = (mgr._wpHotspotsEnabled ~= false) and STATE_YES_V or 1
        pcall(function()
            self.nfWpMapShow.texts = {"Nein", "Ja"}
            self.nfWpMapShow:setState(mapState)
        end)
    end

    -- Fahrzeugkategorie-Toggles
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
                pcall(function()
                    r.elem.texts = {"Nein", "Ja"}
                    r.elem:setState(enabled and STATE_YES_V or 1)
                end)
            end
        end
    end

    -- Buttons aktivieren/deaktivieren.
    -- Eingreifende Aktionen (Teleport/Typ/Loeschen/Kategorien) nur fuer
    -- Admins (Build 75); Blaettern und Karten-Schalter bleiben fuer alle.
    local isAdmin = self.manager ~= nil and self.manager.getIsLocalAdmin ~= nil
                    and self.manager:getIsLocalAdmin()
    local hasWp = count > 0 and self.currentIdx ~= nil
    if self.nfWpTeleport ~= nil then pcall(function() self.nfWpTeleport:setDisabled(not hasWp or not isAdmin) end) end
    if self.nfWpType     ~= nil then pcall(function() self.nfWpType:setDisabled(not hasWp or not isAdmin)     end) end
    if self.nfWpDelete   ~= nil then pcall(function() self.nfWpDelete:setDisabled(not hasWp or not isAdmin)   end) end
    if self.nfWpAddHere      ~= nil then pcall(function() self.nfWpAddHere:setDisabled(not isAdmin)      end) end
    if self.nfWpAddSpawnHere ~= nil then pcall(function() self.nfWpAddSpawnHere:setDisabled(not isAdmin) end) end
    if self.nfAuftragSpawnHier ~= nil then pcall(function() self.nfAuftragSpawnHier:setDisabled(not isAdmin) end) end
    if self.nfWpPrev     ~= nil then pcall(function() self.nfWpPrev:setDisabled(count == 0)    end) end
    if self.nfWpNext     ~= nil then pcall(function() self.nfWpNext:setDisabled(count == 0)    end) end
    local catIds = { "nfWpCatTractorS", "nfWpCatTractorM", "nfWpCatTractorL",
                     "nfWpCatLoader", "nfWpCatTeleLoader" }
    for _, catId in ipairs(catIds) do
        local ctl = self[catId]
        if ctl ~= nil then pcall(function() ctl:setDisabled(not isAdmin) end) end
    end

    -- Layout neu berechnen
    if self.nfWpLayout ~= nil then
        pcall(function() self.nfWpLayout:invalidateLayout() end)
    end
end

-- ============================================================
-- Callbacks — werden vom GUI-System auf der Seiten-Instanz aufgerufen
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
    pcall(function()
        local sf = g_inGameMenu and g_inGameMenu.pageSettings
        if sf == nil then return end
        -- setState erwartet den PAGING-STATE, nicht die Seitennummer. Bei
        -- ausgeblendeten Sub-Kategorien weichen beide voneinander ab →
        -- den State suchen, dessen Text-Wert unsere Seitennummer ist.
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
        -- Direkt aufrufen — setState löst onClickCallback nicht immer aus
        page:onTabOpen(sf)
    end)
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
    -- Nur Admins (Build 75); inline statt requireAdmin (steht weiter unten)
    local mgr = page.manager
    if mgr ~= nil and mgr.getIsLocalAdmin ~= nil and not mgr:getIsLocalAdmin() then
        if mgr.notifyAdminRequired ~= nil then mgr:notifyAdminRequired() end
        return
    end
    local wp = (page.manager.userTrafficWaypoints or {})[page.currentIdx or 0]
    if wp ~= nil then page.manager:_teleportToWp(wp) end
    page:refreshWpInfo()
end

-- Dedi-MP-Client: Änderungen als Event an den Server schicken - der Server
-- ist Besitzer der WP-Datei; lokale Änderungen würde der nächste Sync überschreiben.
local function isMpClient()
    return g_currentMission ~= nil and not g_currentMission:getIsServer() and g_client ~= nil
end

-- Zweite Verteidigungslinie (Build 75): Handler-Guard, falls ein Control
-- trotz Ausgrauen ausgeloest wird. Der Server prueft zusaetzlich selbst.
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
        -- Normal -> Kurz -> Lang -> Spawnpunkt (4, Build 132) -> Normal
        local naechsterTyp = { [0] = 1, [1] = 2, [2] = 4, [4] = 0 }
        local newCat = naechsterTyp[wp.cat or 0] or 0
        wp.cat = newCat  -- sofort lokal anzeigen; Server-Sync bestätigt
        if isMpClient() then
            pcall(function()
                g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                    NachbarFelderWaypointEditEvent.OP_SETCAT, idx, newCat))
            end)
        else
            page.manager:saveWaypoints()
            -- Karten-Beschriftung ("12 S" fuer Spawnpunkte) sofort nachziehen
            pcall(function() page.manager:updateWpHotspots() end)
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
            pcall(function()
                g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                    NachbarFelderWaypointEditEvent.OP_DELETE, idx))
            end)
            page.currentIdx = nil  -- Server-Sync liefert die neue Liste
            if g_currentMission ~= nil then
                g_currentMission:addIngameNotification(
                    FSBaseMission.INGAME_NOTIFICATION_OK,
                    string.format("NachbarFelder: WP%d Löschung an Server gesendet", idx))
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
                    string.format("NachbarFelder: WP%d geloescht (x=%d z=%d). Noch %d WP.",
                        idx, math.floor(wp.x), math.floor(wp.z), count))
            end
        end
    end
    page:refreshWpInfo()
end

-- Build 134: Punkt an der eigenen Position setzen - dieselbe Logik wie die Taste
-- "NachbarFelder: Wegpunkt setzen" (Fahrzeug: Fahrtrichtung, zu Fuss: Blickrichtung).
local function setzePunktHier(cat)
    local page = getPage()
    if page == nil or page.manager == nil or page.manager.addWaypointAtPlayer == nil then return end
    if not requireAdmin(page) then return end
    page._hinweisText = nil
    local vorher = #(page.manager.userTrafficWaypoints or {})
    local ok, gesetzt, grund = pcall(function()
        return page.manager:addWaypointAtPlayer(cat)
    end)
    if not ok then
        print("NachbarFelder: [WP-PAGE] Punkt setzen fehlgeschlagen: " .. tostring(gesetzt))
        grund = "Fehler beim Setzen (siehe log.txt)"
        gesetzt = false
    end
    if gesetzt then
        -- zum neuen Punkt springen, sobald er da ist (MP: nach dem Server-Sync)
        page._anzahlVorNeu      = vorher
        page._springeZuNeuemBis = (g_time or 0) + 10000
    else
        page._hinweisText = grund or "Nicht gesetzt"
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

-- Build 139: Auftrag an den Lohnunternehmer. Kein Admin-Zwang: eigene Felder
-- darf jeder mit dem Recht "Helfer einstellen" beauftragen - das prueft der Server.
-- Das Ergebnis steht danach in der Infozeile (NachbarFelderAuftrag.zeigeAntwort).
function NachbarFelderWaypointPage:onNFAuftragHier(state, elem)
    local page = getPage()
    if page == nil or page.manager == nil or NachbarFelderAuftrag == nil then return end
    local ok, err = pcall(NachbarFelderAuftrag.anfordern, page.manager)
    if not ok then
        print("NachbarFelder: [WP-PAGE] Auftrag fehlgeschlagen: " .. tostring(err))
    end
end

function NachbarFelderWaypointPage:onNFWpMapShow(state, elem)
    local page = getPage()
    if page == nil then return end
    -- setWpHotspotsVisible setzt das Flag UND baut die Hotspots neu auf /
    -- entfernt sie - nur das Flag zu setzen ließ vorhandene Punkte sichtbar.
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
        pcall(function() page:refreshWpInfo() end)  -- Schalter zuruecksetzen
        return
    end
    local mgr = page.manager
    local enabled = (state == STATE_YES())
    mgr.vehicleCatEnabled = mgr.vehicleCatEnabled or {}
    mgr.vehicleCatEnabled[catKey] = enabled  -- lokal für sofortige Anzeige
    mgr.trafficVehicleList = nil  -- Liste beim naechsten Spawn neu aufbauen
    if isMpClient() then
        pcall(function()
            g_client:getServerConnection():sendEvent(NachbarFelderWaypointEditEvent.new(
                NachbarFelderWaypointEditEvent.OP_VEHCAT,
                VEHCAT_IDX[catKey] or 0, enabled and 1 or 0))
        end)
    else
        pcall(function() mgr:saveWaypoints() end)
    end
    page:refreshWpInfo()
end

function NachbarFelderWaypointPage:onNFWpCatTractorS(state, elem)   setCatEnabled("TRACTORSS",           state) end
function NachbarFelderWaypointPage:onNFWpCatTractorM(state, elem)   setCatEnabled("TRACTORSM",           state) end
function NachbarFelderWaypointPage:onNFWpCatTractorL(state, elem)   setCatEnabled("TRACTORSL",           state) end
function NachbarFelderWaypointPage:onNFWpCatLoader(state, elem)     setCatEnabled("WHEELLOADERVEHICLES", state) end
function NachbarFelderWaypointPage:onNFWpCatTeleLoader(state, elem) setCatEnabled("TELELOADERVEHICLES",  state) end

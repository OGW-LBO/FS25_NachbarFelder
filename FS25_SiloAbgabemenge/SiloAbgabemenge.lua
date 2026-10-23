-- ============================================================
-- FS25_SiloAbgabemenge
--
-- Begrenzt die Menge, die ein Silo (bzw. jede Ladestation mit
-- LoadTrigger) beim Befuellen eines Fahrzeugs abgibt.
--
-- Bedienung: Nach "Start" im Silo-Dialog des Spiels erscheint ein
-- zweites Fenster mit der Menge:
--   "Eigene Menge ..."  -> Eingabefeld (TextInputDialog des Spiels)
--   2.000 / 4.000 / 6.000 / 8.000 / 10.000 l, danach 5.000-l-Schritte
--   "Alles (x l)"       -> volle moegliche Menge (Siloinhalt bzw. freier
--                          Platz im Fahrzeug, je nachdem was kleiner ist)
-- Mehr als moeglich geht nicht: dann wird eben die Restmenge geladen.
--
-- Ablauf (Original-Code LoadTrigger.lua, FS25):
--   Client: toggleLoading -> SiloDialog -> onFillTypeSelection
--           -> setIsLoading(true) -> LoadTriggerSetIsLoadingEvent
--   Server: startLoading, danach update(dt) fuellt mit
--           fillLitersPerMS * dt ueber source:addFillLevelToFillableObject
--
-- Die Mod faengt onFillTypeSelection ab, zeigt den Mengen-Dialog und
-- schickt nach "Start" die Menge VOR dem Start-Event an den Server
-- (gleiche Verbindung, gleiche Reihenfolge). Der Server merkt sie sich
-- beim Start des Ladevorgangs, drosselt in update() die Fuellrate auf
-- den Rest und stoppt bei Erreichen der Menge.
--
-- KI-Helfer (aiStartLoadingFromTrigger) laufen nicht ueber
-- onFillTypeSelection und werden daher nie begrenzt.
-- ============================================================

local modName = g_currentModName
local modDirectory = g_currentModDirectory

SiloAbgabemenge = {}
-- Vorgaben in der Liste: feine Schritte bis 10.000 l, danach 5.000-l-Schritte
SiloAbgabemenge.FEINE_SCHRITTE = { 2000, 4000, 6000, 8000, 10000 }
SiloAbgabemenge.GROBER_SCHRITT = 5000
SiloAbgabemenge.MAX_LISTE      = 200000  -- groesste Vorgabe in der Liste
SiloAbgabemenge.PENDING_MS     = 10000   -- so lange gilt eine gesendete Menge
SiloAbgabemenge.DIALOG_NAME    = "SiloAbgabemengeDialog"
SiloAbgabemenge.EIGENE         = -1      -- Listen-Eintrag "Eigene Menge ..."

SiloAbgabemenge.letzteMenge  = 0         -- zuletzt gewaehlte Menge, 0 = Alles
SiloAbgabemenge.letzteEigene = nil       -- zuletzt eingegebene eigene Menge
SiloAbgabemenge.offenerDialog = nil      -- vorgemerkter Mengen-Dialog (naechster Frame)
SiloAbgabemenge.offeneEingabe = nil      -- vorgemerktes Eingabefeld (naechster Frame)

local function log(msg)
    print("[SiloAbgabemenge] " .. tostring(msg))
end

local function jetzt()
    if g_time ~= nil then
        return g_time
    end
    return 0
end

local function text(name, fallback)
    if g_i18n ~= nil and g_i18n.getText ~= nil then
        local ok, t = pcall(g_i18n.getText, g_i18n, name)
        if ok and t ~= nil and t ~= "" and string.find(t, "Missing", 1, true) == nil then
            return t
        end
    end
    return fallback
end

local function formatLiter(liter)
    if g_i18n ~= nil and g_i18n.formatVolume ~= nil then
        local ok, t = pcall(g_i18n.formatVolume, g_i18n, liter, 0)
        if ok and t ~= nil then
            return t
        end
    end
    return string.format("%d l", math.floor(liter + 0.5))
end

local function hinweis(meldung)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, meldung)
    end
end

-- ============================================================
-- Network-Event: Client -> Server (gewuenschte Menge fuer einen LoadTrigger)
-- ============================================================
SiloAbgabemengeEvent = {}
SiloAbgabemengeEvent_mt = Class(SiloAbgabemengeEvent, Event)
InitEventClass(SiloAbgabemengeEvent, "SiloAbgabemengeEvent")

function SiloAbgabemengeEvent.emptyNew()
    return Event.new(SiloAbgabemengeEvent_mt)
end

function SiloAbgabemengeEvent.new(loadTrigger, limit)
    local self = SiloAbgabemengeEvent.emptyNew()
    self.loadTrigger = loadTrigger
    self.limit = limit or 0
    return self
end

function SiloAbgabemengeEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.loadTrigger)
    streamWriteInt32(streamId, math.max(0, math.floor(self.limit or 0)))
end

function SiloAbgabemengeEvent:readStream(streamId, connection)
    self.loadTrigger = NetworkUtil.readNodeObject(streamId)
    self.limit = streamReadInt32(streamId)
    -- Stream ist vollstaendig gelesen, erst jetzt auswerten
    if g_currentMission ~= nil and g_currentMission:getIsServer() and self.loadTrigger ~= nil then
        SiloAbgabemenge.setPending(self.loadTrigger, self.limit)
    end
end

-- ============================================================
-- Mengen-Dialog (Muster: MessageDialog wie in FS25_UsedPlus)
-- ============================================================
SiloAbgabemengeDialog = {}
local SiloAbgabemengeDialog_mt = Class(SiloAbgabemengeDialog, MessageDialog)

function SiloAbgabemengeDialog.new(target, customMt)
    local self = MessageDialog.new(target, customMt or SiloAbgabemengeDialog_mt)
    self.mengen = {}
    self.onAuswahl = nil
    return self
end

-- onAuswahl(menge) wird bei "Start" gerufen: Liter, 0 = Alles, EIGENE = Eingabefeld
function SiloAbgabemengeDialog:setData(titel, info, mengen, texte, startIndex, onAuswahl)
    self.titel = titel
    self.info = info
    self.mengen = mengen
    self.texte = texte
    self.startIndex = startIndex
    self.onAuswahl = onAuswahl
end

function SiloAbgabemengeDialog:onOpen()
    SiloAbgabemengeDialog:superClass().onOpen(self)

    if self.dialogTitleElement ~= nil and self.titel ~= nil then
        self.dialogTitleElement:setText(self.titel)
    end
    if self.infoText ~= nil then
        self.infoText:setText(self.info or "")
    end
    if self.amountOption ~= nil then
        self.amountOption:setTexts(self.texte or {})
        self.amountOption:setState(self.startIndex or 1)
    end
    if self.startButton ~= nil then
        self.startButton:setText(text("SA_start", "Start"))
    end
end

function SiloAbgabemengeDialog:onAmountChanged()
end

function SiloAbgabemengeDialog:onClickStart()
    local menge = 0
    if self.amountOption ~= nil then
        local state = self.amountOption:getState()
        if state ~= nil and self.mengen[state] ~= nil then
            menge = self.mengen[state]
        end
    end
    local onAuswahl = self.onAuswahl
    self.onAuswahl = nil
    self:close()
    if onAuswahl ~= nil then
        onAuswahl(menge)
    end
end

function SiloAbgabemengeDialog:onClickCancel()
    self.onAuswahl = nil
    self:close()
end

function SiloAbgabemenge.ladeDialog()
    if g_gui == nil then
        return false
    end
    if g_gui.guis ~= nil and g_gui.guis[SiloAbgabemenge.DIALOG_NAME] ~= nil then
        return true
    end
    local ok, err = pcall(function()
        g_gui:loadGui(modDirectory .. "gui/SiloAbgabemengeDialog.xml", SiloAbgabemenge.DIALOG_NAME,
            SiloAbgabemengeDialog.new())
    end)
    if not ok then
        log("Dialog konnte nicht geladen werden: " .. tostring(err))
        return false
    end
    if g_gui.guis == nil or g_gui.guis[SiloAbgabemenge.DIALOG_NAME] == nil then
        log("Dialog konnte nicht geladen werden (XML)")
        return false
    end
    return true
end

-- Vorgaben unterhalb der moeglichen Menge
function SiloAbgabemenge.getVorgaben(moeglich)
    local liste = {}
    local groesste = 0
    for _, m in ipairs(SiloAbgabemenge.FEINE_SCHRITTE) do
        if m < moeglich - 0.5 then
            table.insert(liste, m)
        end
        groesste = math.max(groesste, m)
    end
    local m = groesste + SiloAbgabemenge.GROBER_SCHRITT
    while m < moeglich - 0.5 and m <= SiloAbgabemenge.MAX_LISTE do
        table.insert(liste, m)
        m = m + SiloAbgabemenge.GROBER_SCHRITT
    end
    return liste
end

-- Liste fuer den Dialog: "Eigene Menge ...", Vorgaben, "Alles (x l)".
-- Rueckgabe: mengen, texte, startIndex
function SiloAbgabemenge.baueListe(moeglich)
    local mengen = { SiloAbgabemenge.EIGENE }
    local texte = { text("SA_eigene", "Eigene Menge ...") }

    for _, m in ipairs(SiloAbgabemenge.getVorgaben(moeglich)) do
        table.insert(mengen, m)
        table.insert(texte, formatLiter(m))
    end

    table.insert(mengen, 0)
    if moeglich < math.huge then
        table.insert(texte, string.format("%s (%s)", text("SA_alles", "Alles"), formatLiter(moeglich)))
    else
        table.insert(texte, text("SA_alles", "Alles"))
    end

    -- Vorauswahl: zuletzt gewaehlter Eintrag, sonst "Alles"
    local startIndex = #mengen
    local letzte = SiloAbgabemenge.letzteMenge or 0
    if letzte ~= 0 then
        for i, m in ipairs(mengen) do
            if m == letzte then
                startIndex = i
                break
            end
        end
    end
    return mengen, texte, startIndex
end

-- Eingabe "1.500", "1500 l", "1,5" (wird als 15 gelesen) -> nur Ziffern zaehlen
function SiloAbgabemenge.leseEingabe(eingabe)
    if type(eingabe) ~= "string" then
        return nil
    end
    local ziffern = string.gsub(eingabe, "%D", "")
    if ziffern == "" then
        return nil
    end
    local menge = tonumber(ziffern)
    if menge == nil or menge <= 0 then
        return nil
    end
    return menge
end

-- Moegliche Menge = min(Siloinhalt dieser Fruchtart, freier Platz im Fahrzeug)
function SiloAbgabemenge.getMoeglicheMenge(loadTrigger, fillType)
    local moeglich = math.huge

    if not loadTrigger.hasInfiniteCapacity and loadTrigger.source ~= nil
       and loadTrigger.source.getAllFillLevels ~= nil and g_currentMission ~= nil then
        local ok, levels = pcall(loadTrigger.source.getAllFillLevels, loadTrigger.source, g_currentMission:getFarmId())
        if ok and levels ~= nil and levels[fillType] ~= nil then
            moeglich = math.min(moeglich, levels[fillType])
        end
    end

    local object = loadTrigger.validFillableObject
    local fillUnitIndex = loadTrigger.validFillableFillUnitIndex
    if object ~= nil and fillUnitIndex ~= nil and object.getFillUnitFreeCapacity ~= nil then
        local ok, frei = pcall(object.getFillUnitFreeCapacity, object, fillUnitIndex, nil, nil)
        if ok and frei ~= nil then
            moeglich = math.min(moeglich, frei)
        end
    end

    return moeglich
end

local function getFillTypeTitel(fillType)
    if g_fillTypeManager ~= nil and g_fillTypeManager.getFillTypeByIndex ~= nil then
        local ok, ft = pcall(g_fillTypeManager.getFillTypeByIndex, g_fillTypeManager, fillType)
        if ok and ft ~= nil and ft.title ~= nil then
            return ft.title
        end
    end
    return ""
end

-- ============================================================
-- Server-Seite
-- ============================================================
function SiloAbgabemenge.setPending(loadTrigger, limit)
    loadTrigger.saPending = { limit = math.max(0, limit or 0), zeit = jetzt() }
end

local function getFuellstand(object, fillUnitIndex)
    if object ~= nil and fillUnitIndex ~= nil and object.getFillUnitFillLevel ~= nil then
        local ok, level = pcall(object.getFillUnitFillLevel, object, fillUnitIndex)
        if ok then
            return level
        end
    end
    return nil
end

function SiloAbgabemenge.triggerStartLoading(self, superFunc, fillType, fillableObject, fillUnitIndex)
    local warAktiv = self.isLoading
    superFunc(self, fillType, fillableObject, fillUnitIndex)

    if self.isServer and not warAktiv and self.isLoading then
        local pending = self.saPending
        self.saPending = nil
        self.saLimit = nil
        self.saGeladen = 0
        if pending ~= nil and pending.limit > 0
           and (jetzt() - pending.zeit) <= SiloAbgabemenge.PENDING_MS then
            self.saLimit = pending.limit
        end
    end
end

function SiloAbgabemenge.triggerStopLoading(self, superFunc)
    local warAktiv = self.isLoading
    superFunc(self)

    if warAktiv and not self.isLoading then
        self.saLimit = nil
        self.saGeladen = 0
    end
end

function SiloAbgabemenge.triggerUpdate(self, superFunc, dt)
    local limit = self.saLimit
    if not self.isServer or not self.isLoading or limit == nil or limit <= 0
       or self.currentFillableObject == nil then
        return superFunc(self, dt)
    end

    local rest = limit - (self.saGeladen or 0)
    if rest <= 0.001 then
        self:setIsLoading(false)
        self:raiseActive()
        return
    end

    local object = self.currentFillableObject
    local fillUnitIndex = self.fillUnitIndex
    local vorher = getFuellstand(object, fillUnitIndex)

    -- Fuellrate fuer diesen Frame auf den Rest drosseln, danach zuruecksetzen
    local origSpeed = self.fillLitersPerMS
    if origSpeed ~= nil and dt ~= nil and dt > 0 then
        self.fillLitersPerMS = math.min(origSpeed, rest / dt)
    end
    local ok, err = pcall(superFunc, self, dt)
    self.fillLitersPerMS = origSpeed
    if not ok then
        log("Fehler in LoadTrigger.update: " .. tostring(err))
        return
    end

    local nachher = getFuellstand(object, fillUnitIndex)
    if vorher ~= nil and nachher ~= nil and nachher > vorher then
        self.saGeladen = (self.saGeladen or 0) + (nachher - vorher)
    elseif vorher == nil or nachher == nil then
        -- Fuellstand nicht lesbar: hoechstens die gedrosselte Menge annehmen
        self.saGeladen = (self.saGeladen or 0) + math.min(rest, (origSpeed or 0) * (dt or 0))
    end

    if self.isLoading and limit - (self.saGeladen or 0) <= 0.001 then
        self:setIsLoading(false)
    end
end

-- ============================================================
-- Client-Seite
-- ============================================================
function SiloAbgabemenge.sendeLimit(loadTrigger, limit)
    if g_currentMission:getIsServer() then
        SiloAbgabemenge.setPending(loadTrigger, limit)
    elseif NetworkUtil.getObjectId(loadTrigger) ~= nil then
        g_client:getServerConnection():sendEvent(SiloAbgabemengeEvent.new(loadTrigger, limit))
    else
        log("LoadTrigger ohne Netzwerk-ID - Menge wird nicht begrenzt")
    end
end

function SiloAbgabemenge.triggerOnFillTypeSelection(self, superFunc, fillType)
    -- nur Spieler-Auswahl aus dem Silo-Dialog; autoStart (ohne Dialog) unveraendert.
    -- automaticFilling wird bewusst NICHT geprueft: auch dann zeigt toggleLoading den Silo-Dialog.
    local objekt = self.validFillableObject
    if g_client == nil or self.autoStart or fillType == nil or fillType == FillType.UNKNOWN
       or objekt == nil or not self:getAllowsActivation(objekt) then
        log(string.format("Auswahl ohne Mengen-Dialog: client=%s autoStart=%s fillType=%s fahrzeug=%s",
            tostring(g_client ~= nil), tostring(self.autoStart), tostring(fillType), tostring(objekt ~= nil)))
        return superFunc(self, fillType)
    end

    local moeglich = SiloAbgabemenge.getMoeglicheMenge(self, fillType)
    log(string.format("Fruchtart %s gewaehlt, moeglich %s l", tostring(fillType), tostring(math.floor(moeglich))))
    if moeglich < 1 then
        -- weniger als 1 l moeglich: nichts zu waehlen, das Spiel stoppt von selbst
        SiloAbgabemenge.sendeLimit(self, 0)
        return superFunc(self, fillType)
    end
    if not SiloAbgabemenge.ladeDialog() then
        log("Mengen-Dialog nicht verfuegbar - lade ohne Begrenzung")
        SiloAbgabemenge.sendeLimit(self, 0)
        return superFunc(self, fillType)
    end

    local trigger = self
    local function starte(limit)
        log("Menge gewaehlt: " .. (limit > 0 and tostring(limit) .. " l" or "Alles"))
        SiloAbgabemenge.sendeLimit(trigger, limit)
        superFunc(trigger, fillType)
    end

    local function onAuswahl(menge)
        if menge == SiloAbgabemenge.EIGENE then
            SiloAbgabemenge.letzteMenge = SiloAbgabemenge.EIGENE
            SiloAbgabemenge.offeneEingabe = { moeglich = moeglich, starte = starte }
            return
        end
        SiloAbgabemenge.letzteMenge = menge
        starte(menge)
    end

    local mengen, texte, startIndex = SiloAbgabemenge.baueListe(moeglich)
    local info = string.format("%s: %s", getFillTypeTitel(fillType), text("SA_info", "Wie viel soll geladen werden?"))
    -- erst im naechsten Frame oeffnen, damit sich der Silo-Dialog vorher schliessen kann
    SiloAbgabemenge.offenerDialog = {
        titel = text("SA_titel", "Abgabemenge"), info = info,
        mengen = mengen, texte = texte, startIndex = startIndex, onAuswahl = onAuswahl
    }
end

function SiloAbgabemenge.oeffneMengenDialog(d)
    local guiDialog = g_gui.guis[SiloAbgabemenge.DIALOG_NAME]
    local dialog = guiDialog ~= nil and (guiDialog.target or guiDialog) or nil
    if dialog == nil or dialog.setData == nil then
        log("Dialog nicht verfuegbar - lade ohne Begrenzung")
        d.onAuswahl(0)
        return
    end
    dialog:setData(d.titel, d.info, d.mengen, d.texte, d.startIndex, d.onAuswahl)
    g_gui:showDialog(SiloAbgabemenge.DIALOG_NAME)
    log("Mengen-Dialog geoeffnet (" .. tostring(#d.mengen) .. " Eintraege)")
end

-- Eingabefeld des Spiels (TextInputDialog, Muster aus FS25_UsedPlus)
function SiloAbgabemenge.oeffneEingabe(e)
    local moeglich = e.moeglich
    local function fertig(...)
        -- Argumente robust lesen: erster String = Text, erster Boolean = bestaetigt
        local eingabe, bestaetigt = nil, nil
        for i = 1, select("#", ...) do
            local v = select(i, ...)
            if eingabe == nil and type(v) == "string" then
                eingabe = v
            elseif bestaetigt == nil and type(v) == "boolean" then
                bestaetigt = v
            end
        end
        if bestaetigt == false then
            log("Eigene Menge abgebrochen")
            return
        end
        local menge = SiloAbgabemenge.leseEingabe(eingabe)
        if menge == nil then
            hinweis(text("SA_ungueltig", "Ungültige Menge - bitte eine Zahl in Litern eingeben."))
            return
        end
        SiloAbgabemenge.letzteEigene = math.min(menge, moeglich)
        if menge >= moeglich - 0.5 then
            -- mehr als moeglich: es wird eben die Restmenge geladen
            e.starte(0)
        else
            e.starte(menge)
        end
    end

    local ok, err = pcall(function()
        local dialog = g_gui:showDialog("TextInputDialog")
        if dialog == nil or dialog.target == nil then
            error("TextInputDialog nicht gefunden")
        end
        local maxText = moeglich < math.huge and formatLiter(moeglich) or "-"
        dialog.target:setText(string.format(text("SA_eingabeText", "Menge in Litern (höchstens %s):"), maxText))
        local vorgabe = SiloAbgabemenge.letzteEigene ~= nil and tostring(math.floor(SiloAbgabemenge.letzteEigene)) or ""
        dialog.target:setCallback(fertig, nil, vorgabe)
    end)
    if not ok then
        log("Eingabefeld nicht verfuegbar: " .. tostring(err))
        hinweis(text("SA_keineEingabe", "Eingabefeld nicht verfügbar - bitte eine Menge aus der Liste wählen."))
    end
end

-- Mod-Event-Listener: vorgemerkte Fenster im naechsten Frame oeffnen
function SiloAbgabemenge:update(dt)
    local d = SiloAbgabemenge.offenerDialog
    if d ~= nil then
        SiloAbgabemenge.offenerDialog = nil
        SiloAbgabemenge.oeffneMengenDialog(d)
        return
    end
    local e = SiloAbgabemenge.offeneEingabe
    if e ~= nil then
        SiloAbgabemenge.offeneEingabe = nil
        SiloAbgabemenge.oeffneEingabe(e)
    end
end

-- ============================================================
-- Hooks installieren
-- ============================================================
local function init()
    if LoadTrigger == nil or LoadTrigger.update == nil or LoadTrigger.startLoading == nil
       or LoadTrigger.stopLoading == nil or LoadTrigger.onFillTypeSelection == nil then
        log("FEHLER: LoadTrigger nicht gefunden - Mod inaktiv")
        return
    end

    LoadTrigger.onFillTypeSelection = Utils.overwrittenFunction(LoadTrigger.onFillTypeSelection, SiloAbgabemenge.triggerOnFillTypeSelection)
    LoadTrigger.startLoading = Utils.overwrittenFunction(LoadTrigger.startLoading, SiloAbgabemenge.triggerStartLoading)
    LoadTrigger.stopLoading = Utils.overwrittenFunction(LoadTrigger.stopLoading, SiloAbgabemenge.triggerStopLoading)
    LoadTrigger.update = Utils.overwrittenFunction(LoadTrigger.update, SiloAbgabemenge.triggerUpdate)

    addModEventListener(SiloAbgabemenge)
    log("geladen (" .. tostring(modName) .. ", Version mit Mengen-Dialog und eigener Menge)")
end

init()

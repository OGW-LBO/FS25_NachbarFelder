-- ============================================================
-- FS25_SiloAbgabemenge
--
-- Begrenzt die Menge, die ein Silo (bzw. jede Ladestation mit
-- LoadTrigger) beim Befuellen eines Fahrzeugs abgibt.
--
-- Bedienung: Nach "Start" im Silo-Dialog des Spiels erscheint ein
-- zweites Fenster mit der Menge in 5.000-l-Schritten. Der letzte
-- Eintrag ist immer die volle moegliche Menge (Siloinhalt bzw. freier
-- Platz im Fahrzeug, je nachdem was kleiner ist) - also die Restmenge,
-- wenn es keine vollen 5.000 l mehr sind.
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
SiloAbgabemenge.SCHRITT_LITER  = 5000    -- Schrittweite
SiloAbgabemenge.MAX_EINTRAEGE  = 40      -- hoechstens 40 Schritte (200.000 l) in der Liste
SiloAbgabemenge.PENDING_MS     = 10000   -- so lange gilt eine gesendete Menge
SiloAbgabemenge.DIALOG_NAME    = "SiloAbgabemengeDialog"

SiloAbgabemenge.letzteMenge = 0          -- zuletzt gewaehlte Menge, 0 = Alles
SiloAbgabemenge.offenerDialog = nil      -- vorgemerkter Mengen-Dialog (naechster Frame)

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
    self.onStart = nil
    return self
end

-- onStart(limit) wird bei "Start" gerufen, limit 0 = Alles
function SiloAbgabemengeDialog:setData(titel, info, mengen, texte, startIndex, onStart)
    self.titel = titel
    self.info = info
    self.mengen = mengen
    self.texte = texte
    self.startIndex = startIndex
    self.onStart = onStart
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
    local limit = 0
    if self.amountOption ~= nil then
        local state = self.amountOption:getState()
        if state ~= nil and self.mengen[state] ~= nil then
            limit = self.mengen[state]
        end
    end
    local onStart = self.onStart
    self.onStart = nil
    self:close()
    if onStart ~= nil then
        onStart(limit)
    end
end

function SiloAbgabemengeDialog:onClickCancel()
    self.onStart = nil
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

-- Liste der Mengen: 5.000, 10.000, ... unter der moeglichen Menge,
-- als letzter Eintrag die volle moegliche Menge (Limit 0 = Alles).
-- Rueckgabe: mengen, texte, startIndex
function SiloAbgabemenge.baueListe(moeglich)
    local schritt = SiloAbgabemenge.SCHRITT_LITER
    local mengen, texte = {}, {}
    local maxK = SiloAbgabemenge.MAX_EINTRAEGE
    local k = 1
    while k * schritt < moeglich - 0.5 and k <= maxK do
        table.insert(mengen, k * schritt)
        table.insert(texte, formatLiter(k * schritt))
        k = k + 1
    end
    table.insert(mengen, 0)
    if moeglich < math.huge and k <= SiloAbgabemenge.MAX_EINTRAEGE then
        table.insert(texte, string.format("%s (%s)", text("SA_alles", "Alles"), formatLiter(moeglich)))
    else
        table.insert(texte, text("SA_alles", "Alles"))
    end

    -- Vorauswahl: zuletzt gewaehlte Menge, sonst "Alles"
    local startIndex = #mengen
    local letzte = SiloAbgabemenge.letzteMenge or 0
    if letzte > 0 then
        for i, m in ipairs(mengen) do
            if m == letzte then
                startIndex = i
                break
            end
        end
    end
    return mengen, texte, startIndex
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
    -- nur Spieler-Auswahl aus dem Silo-Dialog; autoStart/automatisches Befuellen unveraendert
    if g_client == nil or self.autoStart or self.automaticFilling
       or fillType == nil or fillType == FillType.UNKNOWN
       or self.validFillableObject == nil or not self:getAllowsActivation(self.validFillableObject) then
        return superFunc(self, fillType)
    end

    local moeglich = SiloAbgabemenge.getMoeglicheMenge(self, fillType)
    if moeglich <= SiloAbgabemenge.SCHRITT_LITER or not SiloAbgabemenge.ladeDialog() then
        -- 5.000 l oder weniger moeglich: es gibt nur die Restmenge, ohne Rueckfrage laden
        SiloAbgabemenge.sendeLimit(self, 0)
        return superFunc(self, fillType)
    end

    local mengen, texte, startIndex = SiloAbgabemenge.baueListe(moeglich)
    local trigger = self
    local function onStart(limit)
        SiloAbgabemenge.letzteMenge = limit
        SiloAbgabemenge.sendeLimit(trigger, limit)
        superFunc(trigger, fillType)
    end

    local info = string.format("%s: %s", getFillTypeTitel(fillType), text("SA_info", "Wie viel soll geladen werden?"))
    -- erst im naechsten Frame oeffnen, damit sich der Silo-Dialog vorher schliessen kann
    SiloAbgabemenge.offenerDialog = {
        titel = text("SA_titel", "Abgabemenge"), info = info,
        mengen = mengen, texte = texte, startIndex = startIndex, onStart = onStart
    }
end

-- Mod-Event-Listener: vorgemerkten Mengen-Dialog oeffnen
function SiloAbgabemenge:update(dt)
    local d = SiloAbgabemenge.offenerDialog
    if d == nil then
        return
    end
    SiloAbgabemenge.offenerDialog = nil

    local guiDialog = g_gui.guis[SiloAbgabemenge.DIALOG_NAME]
    local dialog = guiDialog ~= nil and (guiDialog.target or guiDialog) or nil
    if dialog == nil or dialog.setData == nil then
        log("Dialog nicht verfuegbar - lade ohne Begrenzung")
        d.onStart(0)
        return
    end
    dialog:setData(d.titel, d.info, d.mengen, d.texte, d.startIndex, d.onStart)
    g_gui:showDialog(SiloAbgabemenge.DIALOG_NAME)
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
    log("geladen (" .. tostring(modName) .. ")")
end

init()

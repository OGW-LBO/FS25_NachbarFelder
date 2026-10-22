-- ============================================================
-- FS25_SiloAbgabemenge
--
-- Begrenzt die Menge, die ein Silo (bzw. jede Ladestation mit
-- LoadTrigger) beim Befuellen eines Fahrzeugs abgibt. Einstellbar
-- in 5.000-l-Schritten per Taste; "Alles" = Verhalten des Basisspiels.
-- Hat das Silo weniger oder passt weniger ins Fahrzeug, wird eben die
-- Restmenge geladen (das Basisspiel stoppt dann von selbst).
--
-- Ablauf (Original-Code LoadTrigger.lua, FS25):
--   Client: toggleLoading -> SiloDialog -> onFillTypeSelection
--           -> setIsLoading(true) -> LoadTriggerSetIsLoadingEvent
--   Server: startLoading, danach update(dt) fuellt mit
--           fillLitersPerMS * dt ueber source:addFillLevelToFillableObject
--
-- Die Mod schickt in onFillTypeSelection VOR dem Start-Event die
-- gewuenschte Menge an den Server (gleiche Verbindung, gleiche
-- Reihenfolge). Der Server merkt sie sich beim Start des Ladevorgangs,
-- drosselt in update() die Fuellrate auf den Rest und stoppt bei
-- Erreichen der Menge.
--
-- KI-Helfer (aiStartLoadingFromTrigger) laufen nicht ueber
-- onFillTypeSelection und werden daher nie begrenzt.
-- ============================================================

local modName = g_currentModName

SiloAbgabemenge = {}
SiloAbgabemenge.SCHRITT_LITER = 5000   -- Schrittweite
SiloAbgabemenge.MAX_STUFE     = 40     -- 40 x 5.000 l = 200.000 l
SiloAbgabemenge.PENDING_MS    = 10000  -- so lange gilt eine gesendete Menge
SiloAbgabemenge.ANZEIGE_MS    = 500    -- Tasten im F1-Fenster nur nahe einer Ladestation

SiloAbgabemenge.stufe = 0              -- 0 = Alles, sonst stufe * SCHRITT_LITER
SiloAbgabemenge.eventIds = {}
SiloAbgabemenge.zuletztAmSilo = -100000

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
        if ok and t ~= nil and t ~= "" then
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

-- gewaehlte Menge in Litern, 0 = Alles
function SiloAbgabemenge.getLimit()
    return SiloAbgabemenge.stufe * SiloAbgabemenge.SCHRITT_LITER
end

function SiloAbgabemenge.getMengenText()
    local limit = SiloAbgabemenge.getLimit()
    if limit <= 0 then
        return text("SA_alles", "Alles")
    end
    return formatLiter(limit)
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
function SiloAbgabemenge.triggerOnFillTypeSelection(self, superFunc, fillType)
    if g_client ~= nil and fillType ~= nil and fillType ~= FillType.UNKNOWN
       and self.validFillableObject ~= nil and self:getAllowsActivation(self.validFillableObject) then
        local limit = SiloAbgabemenge.getLimit()
        if g_currentMission:getIsServer() then
            SiloAbgabemenge.setPending(self, limit)
        elseif NetworkUtil.getObjectId(self) ~= nil then
            g_client:getServerConnection():sendEvent(SiloAbgabemengeEvent.new(self, limit))
        else
            log("LoadTrigger ohne Netzwerk-ID - Menge wird nicht begrenzt")
        end
    end
    return superFunc(self, fillType)
end

-- Text der Aktion "Befuellen starten" um die gewaehlte Menge ergaenzen
function SiloAbgabemenge.activatableGetIsActivatable(self, superFunc)
    local aktiv = superFunc(self)
    local trigger = self.loadTrigger
    if aktiv and trigger ~= nil then
        SiloAbgabemenge.zuletztAmSilo = jetzt()
        if not trigger.isLoading and trigger.startFillText ~= nil then
            self.activateText = string.format("%s (%s)", trigger.startFillText, SiloAbgabemenge.getMengenText())
        end
    end
    return aktiv
end

function SiloAbgabemenge.setStufe(stufe)
    stufe = math.max(0, math.min(SiloAbgabemenge.MAX_STUFE, stufe))
    SiloAbgabemenge.stufe = stufe
    SiloAbgabemenge.aktualisiereTastenText()

    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format("%s: %s", text("SA_abgabemenge", "Abgabemenge"), SiloAbgabemenge.getMengenText()))
    end
end

function SiloAbgabemenge:onInputPlus()
    SiloAbgabemenge.setStufe(SiloAbgabemenge.stufe + 1)
end

function SiloAbgabemenge:onInputMinus()
    SiloAbgabemenge.setStufe(SiloAbgabemenge.stufe - 1)
end

function SiloAbgabemenge.aktualisiereTastenText()
    if g_inputBinding == nil then
        return
    end
    local menge = SiloAbgabemenge.getMengenText()
    local idPlus = SiloAbgabemenge.eventIds.plus
    local idMinus = SiloAbgabemenge.eventIds.minus
    if idPlus ~= nil then
        g_inputBinding:setActionEventText(idPlus, string.format("%s (%s)", text("SA_tasteMehr", "Abgabemenge +"), menge))
    end
    if idMinus ~= nil then
        g_inputBinding:setActionEventText(idMinus, string.format("%s (%s)", text("SA_tasteWeniger", "Abgabemenge -"), menge))
    end
end

local function registerActionEvents(self, superFunc, ...)
    superFunc(self, ...)

    if self.player == nil or not self.player.isOwner or g_client == nil then
        return
    end
    if InputAction.SA_MENGE_PLUS == nil or InputAction.SA_MENGE_MINUS == nil then
        return
    end

    local _, idPlus = g_inputBinding:registerActionEvent(InputAction.SA_MENGE_PLUS, SiloAbgabemenge,
        SiloAbgabemenge.onInputPlus, false, true, false, true)
    local _, idMinus = g_inputBinding:registerActionEvent(InputAction.SA_MENGE_MINUS, SiloAbgabemenge,
        SiloAbgabemenge.onInputMinus, false, true, false, true)

    SiloAbgabemenge.eventIds.plus = idPlus
    SiloAbgabemenge.eventIds.minus = idMinus
    SiloAbgabemenge.eventIds.sichtbar = nil
    SiloAbgabemenge.aktualisiereTastenText()
    SiloAbgabemenge.setTastenSichtbar(false)
end

function SiloAbgabemenge.setTastenSichtbar(sichtbar)
    if SiloAbgabemenge.eventIds.sichtbar == sichtbar then
        return
    end
    SiloAbgabemenge.eventIds.sichtbar = sichtbar
    local ids = { SiloAbgabemenge.eventIds.plus, SiloAbgabemenge.eventIds.minus }
    for _, id in pairs(ids) do
        if id ~= nil then
            g_inputBinding:setActionEventTextVisibility(id, sichtbar)
        end
    end
end

-- Mod-Event-Listener: Tasten im F1-Fenster nur zeigen, solange eine
-- Ladestation die Aktion "Befuellen starten" anbietet
function SiloAbgabemenge:update(dt)
    if g_client == nil or g_inputBinding == nil then
        return
    end
    SiloAbgabemenge.setTastenSichtbar((jetzt() - SiloAbgabemenge.zuletztAmSilo) <= SiloAbgabemenge.ANZEIGE_MS)
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

    if LoadTriggerActivatable ~= nil and LoadTriggerActivatable.getIsActivatable ~= nil then
        LoadTriggerActivatable.getIsActivatable = Utils.overwrittenFunction(LoadTriggerActivatable.getIsActivatable,
            SiloAbgabemenge.activatableGetIsActivatable)
    else
        log("Warnung: LoadTriggerActivatable nicht gefunden - Menge wird an der Station nicht angezeigt")
    end

    if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
        PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.overwrittenFunction(
            PlayerInputComponent.registerGlobalPlayerActionEvents, registerActionEvents)
    else
        log("Warnung: PlayerInputComponent nicht gefunden - Tasten nicht verfuegbar")
    end

    addModEventListener(SiloAbgabemenge)
    log("geladen (" .. tostring(modName) .. ")")
end

init()

-- ============================================================
-- FS25_SiloUnloadAmount
--
-- Begrenzt die Menge, die ein Silo (bzw. jede Ladestation mit
-- LoadTrigger) beim Befuellen eines Fahrzeugs abgibt.
--
-- Bedienung: Nach "Start" im Silo-Dialog des Spiels oeffnet sich das
-- Eingabefeld des Spiels (TextInputDialog). Dort die Menge in Litern
-- eingeben. Leer lassen = alles. Mehr als moeglich (Siloinhalt bzw.
-- freier Platz im Fahrzeug) geht nicht - dann wird die Restmenge geladen.
--
-- Ablauf (Original-Code LoadTrigger.lua, FS25):
--   Client: toggleLoading -> SiloDialog -> onFillTypeSelection
--           -> setIsLoading(true) -> LoadTriggerSetIsLoadingEvent
--   Server: startLoading, danach update(dt) fuellt mit
--           fillLitersPerMS * dt ueber source:addFillLevelToFillableObject
--
-- Die Mod faengt onFillTypeSelection ab, zeigt das Eingabefeld und
-- schickt nach der Eingabe die Menge VOR dem Start-Event an den Server
-- (gleiche Verbindung, gleiche Reihenfolge). Der Server merkt sie sich
-- beim Start des Ladevorgangs, drosselt in update() die Fuellrate auf
-- den Rest und stoppt bei Erreichen der Menge.
--
-- KI-Helfer (aiStartLoadingFromTrigger) laufen nicht ueber
-- onFillTypeSelection und werden daher nie begrenzt.
-- ============================================================

SiloUnloadAmount = {}
SiloUnloadAmount.PENDING_MS = 10000      -- so lange gilt eine gesendete Menge

SiloUnloadAmount.letzteMenge = nil       -- zuletzt eingegebene Menge (Vorgabe im Eingabefeld)
SiloUnloadAmount.offeneEingabe = nil     -- vorgemerktes Eingabefeld (naechster Frame)

local function log(msg)
    print("[SiloUnloadAmount] " .. tostring(msg))
end

local function jetzt()
    if g_time ~= nil then
        return g_time
    end
    return 0
end

local function text(name)
    return g_i18n:getText(name)
end

local function hinweis(meldung)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_CRITICAL, meldung)
    end
end

-- ============================================================
-- Network-Event: Client -> Server (gewuenschte Menge fuer einen LoadTrigger)
-- ============================================================
SiloUnloadAmountEvent = {}
SiloUnloadAmountEvent_mt = Class(SiloUnloadAmountEvent, Event)
InitEventClass(SiloUnloadAmountEvent, "SiloUnloadAmountEvent")

function SiloUnloadAmountEvent.emptyNew()
    return Event.new(SiloUnloadAmountEvent_mt)
end

function SiloUnloadAmountEvent.new(loadTrigger, limit)
    local self = SiloUnloadAmountEvent.emptyNew()
    self.loadTrigger = loadTrigger
    self.limit = limit or 0
    return self
end

function SiloUnloadAmountEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.loadTrigger)
    streamWriteInt32(streamId, math.max(0, math.floor(self.limit or 0)))
end

function SiloUnloadAmountEvent:readStream(streamId, connection)
    self.loadTrigger = NetworkUtil.readNodeObject(streamId)
    self.limit = streamReadInt32(streamId)
    -- Stream ist vollstaendig gelesen, erst jetzt auswerten
    if g_currentMission ~= nil and g_currentMission:getIsServer() and self.loadTrigger ~= nil then
        SiloUnloadAmount.setPending(self.loadTrigger, self.limit)
    end
end

-- ============================================================
-- Hilfsfunktionen
-- ============================================================

-- Eingabe lesen: "1.500", "1500 l" -> 1500 (nur Ziffern zaehlen).
-- Rueckgabe: Menge in Litern, 0 = leer (alles), nil = ungueltig
function SiloUnloadAmount.leseEingabe(eingabe)
    if eingabe == nil then
        return 0
    end
    if type(eingabe) ~= "string" then
        return nil
    end
    if string.find(eingabe, "%S") == nil then
        return 0
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
function SiloUnloadAmount.getMoeglicheMenge(loadTrigger, fillType)
    local moeglich = math.huge

    local source = loadTrigger.source
    if not loadTrigger.hasInfiniteCapacity and source ~= nil and source.getAllFillLevels ~= nil then
        local levels = source:getAllFillLevels(g_currentMission:getFarmId())
        if levels ~= nil and levels[fillType] ~= nil then
            moeglich = math.min(moeglich, levels[fillType])
        end
    end

    local object = loadTrigger.validFillableObject
    local fillUnitIndex = loadTrigger.validFillableFillUnitIndex
    if object ~= nil and fillUnitIndex ~= nil and object.getFillUnitFreeCapacity ~= nil then
        local frei = object:getFillUnitFreeCapacity(fillUnitIndex, nil, nil)
        if frei ~= nil then
            moeglich = math.min(moeglich, frei)
        end
    end

    return moeglich
end

local function getFillTypeTitel(fillType)
    local ft = g_fillTypeManager:getFillTypeByIndex(fillType)
    if ft ~= nil and ft.title ~= nil then
        return ft.title
    end
    return ""
end

-- ============================================================
-- Server-Seite
-- ============================================================
function SiloUnloadAmount.setPending(loadTrigger, limit)
    loadTrigger.suaPending = { limit = math.max(0, limit or 0), zeit = jetzt() }
end

local function getFuellstand(object, fillUnitIndex)
    if object ~= nil and fillUnitIndex ~= nil and object.getFillUnitFillLevel ~= nil then
        return object:getFillUnitFillLevel(fillUnitIndex)
    end
    return nil
end

function SiloUnloadAmount.triggerStartLoading(self, superFunc, fillType, fillableObject, fillUnitIndex)
    local warAktiv = self.isLoading
    superFunc(self, fillType, fillableObject, fillUnitIndex)

    if self.isServer and not warAktiv and self.isLoading then
        local pending = self.suaPending
        self.suaPending = nil
        self.suaLimit = nil
        self.suaGeladen = 0
        if pending ~= nil and pending.limit > 0
           and (jetzt() - pending.zeit) <= SiloUnloadAmount.PENDING_MS then
            self.suaLimit = pending.limit
        end
    end
end

function SiloUnloadAmount.triggerStopLoading(self, superFunc)
    local warAktiv = self.isLoading
    superFunc(self)

    if warAktiv and not self.isLoading then
        self.suaLimit = nil
        self.suaGeladen = 0
    end
end

function SiloUnloadAmount.triggerUpdate(self, superFunc, dt)
    local limit = self.suaLimit
    if not self.isServer or not self.isLoading or limit == nil or limit <= 0
       or self.currentFillableObject == nil then
        return superFunc(self, dt)
    end

    local rest = limit - (self.suaGeladen or 0)
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
    superFunc(self, dt)
    self.fillLitersPerMS = origSpeed

    local nachher = getFuellstand(object, fillUnitIndex)
    if vorher ~= nil and nachher ~= nil then
        if nachher > vorher then
            self.suaGeladen = (self.suaGeladen or 0) + (nachher - vorher)
        end
    else
        -- Fuellstand nicht lesbar: hoechstens die gedrosselte Menge annehmen
        self.suaGeladen = (self.suaGeladen or 0) + math.min(rest, (origSpeed or 0) * (dt or 0))
    end

    if self.isLoading and limit - (self.suaGeladen or 0) <= 0.001 then
        self:setIsLoading(false)
    end
end

-- ============================================================
-- Client-Seite
-- ============================================================
function SiloUnloadAmount.sendeLimit(loadTrigger, limit)
    if g_currentMission:getIsServer() then
        SiloUnloadAmount.setPending(loadTrigger, limit)
    elseif NetworkUtil.getObjectId(loadTrigger) ~= nil then
        g_client:getServerConnection():sendEvent(SiloUnloadAmountEvent.new(loadTrigger, limit))
    else
        log("Warnung: LoadTrigger ohne Netzwerk-ID - Menge wird nicht begrenzt")
    end
end

function SiloUnloadAmount.triggerOnFillTypeSelection(self, superFunc, fillType)
    -- nur Spieler-Auswahl aus dem Silo-Dialog; autoStart (ohne Dialog) unveraendert.
    -- automaticFilling wird bewusst NICHT geprueft: auch dann zeigt toggleLoading den Silo-Dialog.
    local objekt = self.validFillableObject
    if g_client == nil or g_gui == nil or self.autoStart or fillType == nil or fillType == FillType.UNKNOWN
       or objekt == nil or not self:getAllowsActivation(objekt) then
        return superFunc(self, fillType)
    end

    local moeglich = SiloUnloadAmount.getMoeglicheMenge(self, fillType)
    if moeglich < 1 then
        -- weniger als 1 l moeglich: nichts einzugeben, das Spiel stoppt von selbst
        SiloUnloadAmount.sendeLimit(self, 0)
        return superFunc(self, fillType)
    end

    local trigger = self
    local function starte(limit)
        SiloUnloadAmount.sendeLimit(trigger, limit)
        superFunc(trigger, fillType)
    end

    -- erst im naechsten Frame oeffnen, damit sich der Silo-Dialog vorher schliessen kann
    SiloUnloadAmount.offeneEingabe = { moeglich = moeglich, fillType = fillType, starte = starte }
end

-- Eingabefeld des Spiels (TextInputDialog, Muster aus FS25_UsedPlus)
function SiloUnloadAmount.oeffneEingabe(e)
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
            return
        end
        local menge = SiloUnloadAmount.leseEingabe(eingabe)
        if menge == nil then
            hinweis(text("SUA_ungueltig"))
            return
        end
        if menge == 0 or menge >= moeglich - 0.5 then
            -- leer oder mehr als moeglich: alles bzw. die Restmenge laden
            e.starte(0)
        else
            SiloUnloadAmount.letzteMenge = menge
            e.starte(menge)
        end
    end

    local dialog = g_gui:showDialog("TextInputDialog")
    local ziel = dialog ~= nil and dialog.target or nil
    if ziel == nil or ziel.setText == nil or ziel.setCallback == nil then
        log("Warnung: TextInputDialog nicht verfuegbar - lade ohne Begrenzung")
        hinweis(text("SUA_keineEingabe"))
        e.starte(0)
        return
    end

    local maxText = "-"
    if moeglich < math.huge then
        maxText = g_i18n:formatVolume(moeglich, 0)
    end
    ziel:setText(string.format(text("SUA_eingabeText"), getFillTypeTitel(e.fillType), maxText))

    local vorgabe = ""
    if SiloUnloadAmount.letzteMenge ~= nil and SiloUnloadAmount.letzteMenge < moeglich then
        vorgabe = tostring(math.floor(SiloUnloadAmount.letzteMenge))
    end
    ziel:setCallback(fertig, nil, vorgabe)
end

-- Mod-Event-Listener: vorgemerktes Eingabefeld im naechsten Frame oeffnen
function SiloUnloadAmount:update(dt)
    local e = SiloUnloadAmount.offeneEingabe
    if e ~= nil then
        SiloUnloadAmount.offeneEingabe = nil
        SiloUnloadAmount.oeffneEingabe(e)
    end
end

-- ============================================================
-- Hooks installieren
-- ============================================================
local function init()
    if LoadTrigger == nil or LoadTrigger.update == nil or LoadTrigger.startLoading == nil
       or LoadTrigger.stopLoading == nil or LoadTrigger.onFillTypeSelection == nil then
        log("Fehler: LoadTrigger nicht gefunden - Mod inaktiv")
        return
    end

    LoadTrigger.onFillTypeSelection = Utils.overwrittenFunction(LoadTrigger.onFillTypeSelection, SiloUnloadAmount.triggerOnFillTypeSelection)
    LoadTrigger.startLoading = Utils.overwrittenFunction(LoadTrigger.startLoading, SiloUnloadAmount.triggerStartLoading)
    LoadTrigger.stopLoading = Utils.overwrittenFunction(LoadTrigger.stopLoading, SiloUnloadAmount.triggerStopLoading)
    LoadTrigger.update = Utils.overwrittenFunction(LoadTrigger.update, SiloUnloadAmount.triggerUpdate)

    addModEventListener(SiloUnloadAmount)
end

init()

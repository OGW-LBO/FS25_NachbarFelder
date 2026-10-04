NachbarFelderSettingsPage = {}

-- Build 165: Log-Ausgaben nur im Debug-Log (Warnungen/Fehler immer), siehe NachbarFelder.lua
local print = NachbarFelderLog.print
local NachbarFelderSettingsPage_mt = Class(NachbarFelderSettingsPage, FrameElement)


local modSettingDirectory = g_currentModSettingsDirectory
local modName = g_currentModName
local xmlSchema = XMLSchema.new("NachbarFelderSettingSchema")
local baseXmlKey = "NachbarFelderSetting"
local modSaveDir = modSettingDirectory .. "NachbarFelderSetting.xml"


function NachbarFelderSettingsPage.new(NachbarFelderManager)
	local self = FrameElement.new(nil, NachbarFelderSettingsPage_mt)
	self.settings = {}  		-- list of all setting objects 
	self.settingsByName = {}  	-- contains setting objects by name 
	self.controls = {}
	self.NachbarFelderManager = NachbarFelderManager


	self.settings["active"] = NachbarFelderManager.active
	self.settings["MAX_ASSISTANT_WORKERS"] = NachbarFelderManager.MAX_ASSISTANT_WORKERS
	self.settings["trafficLimit"] = NachbarFelderManager.trafficLimit
	self.settings["trafficTrailerSize"] = NachbarFelderManager.trafficTrailerSize
	self.settings["engeMap"] = NachbarFelderManager.engeMap
	self.settings["debugLog"] = NachbarFelderManager.debugLog == true   -- Build 165

	createFolder(modSettingDirectory)
    xmlSchema:register(XMLValueType.BOOL, baseXmlKey .. ".mod#active", "Mod_active")
    xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".worker#max", "MaxWorker")
    xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".worker#value", "MaxWorker")
    xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".trafficLimit#value", "TrafficLimit")
    xmlSchema:register(XMLValueType.INT, baseXmlKey .. ".trafficTrailerSize#value", "TrafficTrailerSize")
    xmlSchema:register(XMLValueType.BOOL, baseXmlKey .. ".engeMap#value", "EngeMap")
	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".mission(?)#type", "Missionname")
	xmlSchema:register(XMLValueType.BOOL, baseXmlKey .. ".mission(?)#skip", "skipMission")
	xmlSchema:register(XMLValueType.STRING, baseXmlKey .. ".mission(?)#active", "use Mission")
	return self
end

function NachbarFelderSettingsPage:init()
	print("init Settings page")
	local controlProperties = {
		{ name = "active", autoBind = true, nillable = false },
		{ name = "trafficLimit", autoBind = true, min = 1, max = 8, step = 1, nillable = false, value = self.settings["trafficLimit"]},
		{ name = "trafficTrailerSize", autoBind = true, min = 0, max = 3, step = 1, nillable = false, value = self.settings["trafficTrailerSize"]},
		{ name = "engeMap", autoBind = true, nillable = false },
		{ name = "debugLog", autoBind = true, nillable = false },   -- Build 165
    }

	-- Build 150: Feldarbeit entfernt - keine Regler mehr fuer "Anzahl Arbeiter" und die
	-- Arbeitsarten. Die Werte bleiben in Speicherdatei und Sync, wirken aber nicht mehr.

	controlProperties = self:loadSettingsFromXML(controlProperties)

	settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
	NachbarFelderUIHelper.createControlsDynamically(settingsPage, "NF_setting_title", self, controlProperties, "NF_")
    NachbarFelderUIHelper.setupAutoBindControls(self, self.settings, NachbarFelderSettingsPage.onSettingsChange)

    self:updateUiElements()

    InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, function()
        self:updateUiElements(true)
    end)
end

function NachbarFelderSettingsPage:onSettingsChange(a, b, c)
	-- MP-Sync (Build 67), gleiche Architektur wie das Wegpunkt-Editing:
	-- Dedi-Client: Aenderung an den Server schicken (der ist autoritativ,
	--   speichert im Savegame und synct an alle Clients zurueck).
	--   Lokal wird trotzdem sofort angewendet (fluessiges UI); der
	--   Server-Sync bestaetigt bzw. korrigiert direkt danach.
	-- Server (SP/Host): direkt anwenden + an Clients broadcasten.
	local isServer = g_currentMission ~= nil and g_currentMission:getIsServer()
	if not isServer and g_client ~= nil and NachbarFelderSettingsEditEvent ~= nil then
		local num = b
		if type(num) == "boolean" then num = num and 1 or 0 end
			g_client:getServerConnection():sendEvent(
				NachbarFelderSettingsEditEvent.new(a.name, num))
	end

	if a.name == "debugLog" then
		-- Build 165: ueber den Setter, damit das Log-Filter mitschaltet
		self.NachbarFelderManager:setDebugLog(b == true)
	elseif self.NachbarFelderManager[a.name] ~= nil then
		self.NachbarFelderManager[a.name] = b
		-- Trailer-Cache invalidieren wenn Größeneinstellung geändert wurde
		if a.name == "trafficTrailerSize" then
			self.NachbarFelderManager.trafficTrailerList = nil
		end
	else
		for k,v in pairs(self.NachbarFelderManager.missionHelper) do
			if v.name == a.name then
				v.active = b
			end
		end
	end

	if isServer then
		local m = self.NachbarFelderManager
		-- Live-Stand ist ab jetzt autoritativ (landet im Savegame)
		m.settingsFromSavegame = true
		if m.broadcastSettingsToClients ~= nil then
			m:broadcastSettingsToClients()
		end
	end
    self:updateUiElements()
end

-- Controls aus dem Manager-Stand neu befuellen (Build 67).
-- Wird von applySettingsState() gerufen, wenn ein Settings-Sync vom
-- Server eintrifft - die GUI zeigt dann sofort die Server-Werte.
-- setState() der Elemente feuert dabei KEINE onClick-Callbacks,
-- es entsteht also keine Event-Schleife.
function NachbarFelderSettingsPage:refreshFromManager()
	local m = self.NachbarFelderManager
	self.settings["active"]                = m.active ~= false
	self.settings["MAX_ASSISTANT_WORKERS"] = m.MAX_ASSISTANT_WORKERS or 12
	self.settings["trafficLimit"]          = m.trafficLimit or 4
	self.settings["trafficTrailerSize"]    = m.trafficTrailerSize or 2
	self.settings["engeMap"]               = m.engeMap ~= false
	self.settings["debugLog"] = m.debugLog == true   -- Build 165
	for _, v in pairs(m.missionHelper or {}) do
		if not v.skip then
			self.settings[v.name] = v.active == true
		end
	end
	if self.populateAutoBindControls ~= nil then
		self.populateAutoBindControls()
	end
end

function NachbarFelderSettingsPage:updateUiElements(skipAutoBindControls)
    if not skipAutoBindControls then
        self.populateAutoBindControls()
    end

	local isAdmin = g_currentMission:getIsServer() or g_currentMission.isMasterUser

	for _, control in ipairs(self.controls) do
		control:setDisabled(not isAdmin)
	end
	
    -- Update the focus manager
    local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
    settingsPage.generalSettingsLayout:invalidateLayout()

	self:saveToXML()

end

function NachbarFelderSettingsPage:loadSettingsFromXML(properties)
	-- Savegame/Server ist autoritativ (Build 67): Wurden die Settings
	-- bereits aus dem Savegame geladen, gilt der Manager-Stand - die
	-- lokale NachbarFelderSetting.xml wuerde ihn sonst ueberschreiben.
	-- (Lokale Datei bleibt Fallback fuer Savegames ohne settings-Block.)
	if self.NachbarFelderManager.settingsFromSavegame then
		local m = self.NachbarFelderManager
		self.settings["active"]                = m.active ~= false
		self.settings["MAX_ASSISTANT_WORKERS"] = m.MAX_ASSISTANT_WORKERS or 12
		self.settings["trafficLimit"]          = m.trafficLimit or 4
		self.settings["trafficTrailerSize"]    = m.trafficTrailerSize or 2
		self.settings["engeMap"]               = m.engeMap ~= false
		self.settings["debugLog"] = m.debugLog == true   -- Build 165
		for _, v in pairs(properties) do
			if v.name == "MAX_ASSISTANT_WORKERS" then
				v.value = self.settings["MAX_ASSISTANT_WORKERS"]
			elseif v.name == "trafficLimit" then
				v.value = self.settings["trafficLimit"]
			elseif v.name == "trafficTrailerSize" then
				v.value = self.settings["trafficTrailerSize"]
			end
		end
		-- Mission-Toggles: die properties SIND die missionHelper-Eintraege,
		-- deren .active traegt bereits den Savegame-Stand.
		for _, v in pairs(m.missionHelper or {}) do
			if not v.skip then
				self.settings[v.name] = v.active == true
			end
		end
		print("NachbarFelder: [SETTINGS] GUI nutzt Savegame-Stand (lokale Datei ignoriert)")
		return properties
	end

	local xmlFile = XMLFile.loadIfExists("NachbarFelderSettings", modSaveDir, xmlSchema)
    if xmlFile == nil then
        return properties
    end


	local modActive = xmlFile:getValue(baseXmlKey .. ".mod#active")
	self.settings["active"] = modActive
	self.NachbarFelderManager.active = modActive

	local maxWorkerVal = xmlFile:getValue(baseXmlKey .. ".worker#value")
	self.settings["MAX_ASSISTANT_WORKERS"] = maxWorkerVal
	self.NachbarFelderManager.MAX_ASSISTANT_WORKERS = maxWorkerVal
	for k,v in pairs(properties) do
		if v.name == "MAX_ASSISTANT_WORKERS" then
			v.max = xmlFile:getValue(baseXmlKey .. ".worker#max", 30)
			v.value = maxWorkerVal
			break
		end
	end

	local tlVal = xmlFile:getInt(baseXmlKey .. ".trafficLimit#value", 4)
	tlVal = math.max(1, math.min(8, tlVal))
	self.settings["trafficLimit"] = tlVal
	self.NachbarFelderManager.trafficLimit = tlVal
	for k,v in pairs(properties) do
		if v.name == "trafficLimit" then
			v.value = tlVal
			break
		end
	end

	local ttsVal = xmlFile:getInt(baseXmlKey .. ".trafficTrailerSize#value", 2)
	ttsVal = math.max(0, math.min(3, ttsVal))
	self.settings["trafficTrailerSize"] = ttsVal
	self.NachbarFelderManager.trafficTrailerSize = ttsVal
	self.NachbarFelderManager.trafficTrailerList = nil  -- Cache invalidieren bei geänderter Größe
	for k,v in pairs(properties) do
		if v.name == "trafficTrailerSize" then
			v.value = ttsVal
			break
		end
	end

	local engVal = xmlFile:getBool(baseXmlKey .. ".engeMap#value")
	if engVal ~= nil and engVal ~= (self.NachbarFelderManager.engeMap ~= false) then
		self.NachbarFelderManager.engeMap = engVal
		-- Beide Caches weg: Fahrzeugliste haengt an den Kategorien,
		-- Geraeteliste am Gewichtslimit.
		self.NachbarFelderManager.trafficVehicleList = nil
		self.NachbarFelderManager.trafficTrailerList = nil
	end
	self.settings["engeMap"] = self.NachbarFelderManager.engeMap ~= false
	self.settings["debugLog"] = self.NachbarFelderManager.debugLog == true   -- Build 165

	print("loadFromXml")
	
    local itKey = baseXmlKey .. ".mission"
    xmlFile:iterate(itKey, function(_, key)
        local type = xmlFile:getValue(key .. "#type")
        local skip = xmlFile:getBool(key .. "#skip")
		local active = xmlFile:getBool(key .. "#active")

		self.settings[type] = active

		for k,v in pairs(self.NachbarFelderManager.missionHelper) do
			if v.name == type then
				v.active = active
				v.skip = skip
			end
		end
		for k,v in pairs(properties) do			
			if v.name == type then
				v.skip = skip
				v.active = active
				break
			end
		end        
    end)
	-- harvestMission (missionHelper[6]) wird NICHT mehr zwangsdeaktiviert -
	-- Ernte ist freigegeben und über die Settings-Seite schaltbar.
	if self.NachbarFelderManager.missionHelper[7] ~= nil then
		local hoeName = self.NachbarFelderManager.missionHelper[7].name
		self.settings[hoeName] = false
		self.NachbarFelderManager.missionHelper[7].active = false
		self.NachbarFelderManager.missionHelper[7].skip = true
		for _, property in pairs(properties) do
			if property.name == hoeName then
				property.active = false
				property.skip = true
				break
			end
		end
	end
	if self.NachbarFelderManager.missionHelper[8] ~= nil then
		local weedName = self.NachbarFelderManager.missionHelper[8].name
		self.settings[weedName] = false
		self.NachbarFelderManager.missionHelper[8].active = false
		self.NachbarFelderManager.missionHelper[8].skip = true
		for _, property in pairs(properties) do
			if property.name == weedName then
				property.active = false
				property.skip = true
				break
			end
		end
	end
    xmlFile:delete()
	return properties
end

function NachbarFelderSettingsPage:saveToXML() 
	local xmlFile = XMLFile.create("NachbarFelderSettings", modSaveDir, baseXmlKey, xmlSchema)
    if xmlFile == nil then
        return
    end
    xmlFile:setBool(baseXmlKey .. ".mod#active", self.NachbarFelderManager.active)
    xmlFile:setInt(baseXmlKey .. ".worker#max", 30)
    xmlFile:setInt(baseXmlKey .. ".worker#value", self.NachbarFelderManager["MAX_ASSISTANT_WORKERS"])
    xmlFile:setInt(baseXmlKey .. ".trafficLimit#value", self.NachbarFelderManager.trafficLimit or 2)
    xmlFile:setInt(baseXmlKey .. ".trafficTrailerSize#value", self.NachbarFelderManager.trafficTrailerSize or 2)
    xmlFile:setBool(baseXmlKey .. ".engeMap#value", self.NachbarFelderManager.engeMap ~= false)

    local baseKey = baseXmlKey .. ".mission"
    local i = 0
    for k,v in pairs(self.NachbarFelderManager.missionHelper) do			
        local key = ("%s(%d)"):format(baseKey, i)
		xmlFile:setString(key .. "#type", v.name)
		xmlFile:setBool(key .. "#skip", v.skip)
		local bool = v.active
		if type(bool) == "string" then
			bool = bool:lower()
			bool = bool == "true"			
		end
		xmlFile:setBool(key .. "#active", bool)
		i = i + 1
    end
    xmlFile:save(false, false)
    xmlFile:delete()
end


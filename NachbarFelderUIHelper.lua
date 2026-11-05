-- This class allows easier creation of configuration options in the general settings page.
-- Originally created by Farmsim Tim based on discoveries made by Shad0wlife
-- Feel free to use this class in your own mods. You may change anything except for the first three lines of this file.
-- version 1.2
-- Changelog:
-- v1.1: Fixed choice controls when using string values
-- v1.2: Choice controls can now be nillable, too
-- v1.3: Fix bool elements which can have invalid slider positions
-- @class NachbarFelderUIHelper
NachbarFelderUIHelper = {}

-- Creates a new section with the given title
-- generalSettingsPage: The general settings page of the base game
-- i18nTitleId: The I18N ID of the title to be displayed
-- liefert The created section element
function NachbarFelderUIHelper.createSection(generalSettingsPage, i18nTitleId)
	local sectionTitle = nil
	local layoutElems = generalSettingsPage.generalSettingsLayout.elements
	for _, elem in ipairs(layoutElems) do
		if elem.name == "sectionHeader" then
			sectionTitle = elem:clone(generalSettingsPage.generalSettingsLayout)
			sectionTitle:setText(g_i18n:getText(i18nTitleId))
			break
		end
	end
	if sectionTitle then
		sectionTitle.focusId = FocusManager:serveAutoFocusId()
		table.insert(generalSettingsPage.controlsList, sectionTitle)
	end
	return sectionTitle
end

-- Sets the focusId properties of the element and any children to a new unique ID each
-- element: the element
function NachbarFelderUIHelper.updateFocusIds(element)
	if not element then
		return
	end
	element.focusId = FocusManager:serveAutoFocusId()
	for _, child in pairs(element.elements) do
		NachbarFelderUIHelper.updateFocusIds(child)
	end
end

local function createElement(generalSettingsPage, template, id, i18nTextId, target, callbackFunc)
	local elementBox = template:clone(generalSettingsPage.generalSettingsLayout)
	-- Remove any existing focus IDs as they would not be unique and cause trouble later on
	NachbarFelderUIHelper.updateFocusIds(elementBox)

	elementBox.id = id .. "Box"
	-- Assign the object which shall receive change events
	local elementOption = elementBox.elements[1]
	elementOption.target = target
	elementOption:setCallback("onClickCallback", callbackFunc)
	-- WORKAROUND: The target serves two purposes:
	-- 1.) Any callback will be executed on the target object
	-- 2.) The focus manager will ignore anything which has a different target _name_ than the current UI
	-- => Since we want to allow any target for callbacks, we just copy the general settings page's name to the target
	target.name = generalSettingsPage.name
	-- Change generic values
	elementOption.id = id
	elementOption:setDisabled(false)
	-- Change the text element
	local textElement = elementBox.elements[2]
	textElement:setText(g_i18n:getText(i18nTextId .. "_short"))
	-- Change the tooltip
	local toolTip = elementOption.elements[1]
	toolTip:setText(g_i18n:getText(i18nTextId .. "_long"))

	table.insert(generalSettingsPage.controlsList, elementBox)
	return elementBox
end


-- Adds a simple yes/no switch to the UI
-- generalSettingsPage: The base game object for the settings page
-- id: The unique ID of the new element
-- i18nTextId: The key in the internationalization XML (must be two keys with a _short and _long suffix)
-- target: The object which contains the callback func
-- callbackFunc: The name of the function to call when the value changes
-- liefert The created object
function NachbarFelderUIHelper.createBoolElement(generalSettingsPage, id, i18nTextId, target, callbackFunc)
	return createElement(generalSettingsPage, generalSettingsPage.checkWoodHarvesterAutoCutBox, id, i18nTextId, target, callbackFunc)
end

-- Creates an element which allows choosing one out of several text values
-- generalSettingsPage: The base game object for the settings page
-- id: The unique ID of the new element
-- i18nTextId: The key in the internationalization XML (must be two keys with a _short and _long suffix)
-- i18nValueMap: An map of values containing translation IDs for the possible values
-- target: The object which contains the callback func
-- callbackFunc: The name of the function to call when the value changes
-- nillable: If set to true, the first entry will mean the setting has no effect. The text value will be "-".
-- liefert The created object
function NachbarFelderUIHelper.createChoiceElement(generalSettingsPage, id, i18nTextId, i18nValueMap, target, callbackFunc, nillable)
	local choiceElementBox = createElement(generalSettingsPage, generalSettingsPage.multiVolumeVoiceBox, id, i18nTextId, target, callbackFunc)

	local choiceElement = choiceElementBox.elements[1]
	local texts = {}

	if nillable then
		table.insert(texts, "-")
	end
	for _, valueEntry in pairs(i18nValueMap) do
		local value
		if type(valueEntry) == "number" then
			value = tostring(valueEntry)
		elseif type(valueEntry) == "string" then
			value = g_i18n:getText(valueEntry)
			choiceElementBox.hasStrings = true
		else
			-- legacy syntax
			value = g_i18n:getText(valueEntry.i18nTextId)
			choiceElementBox.hasStrings = true
		end
		table.insert(texts, value)
	end
	choiceElement:setTexts(texts)

	return choiceElementBox
end

-- Creates an element which allows choosing one out of several integer values
-- generalSettingsPage: The base game object for the settings page
-- id: The unique ID of the new element
-- i18nTextId: The key in the internationalization XML (must be two keys with a _short and _long suffix)
-- minValue: The first value which can be selected
-- maxValue: The last value which can be selected
-- step: The difference between any two values. Make sure this matches max value
-- unit: The unit to be displayed (may be empty)
-- target: The object which contains the callback func
-- callbackFunc: The name of the function to call when the value changes
-- nillable: If set to true, the first entry will mean the setting has no effect. The text value will be "-".
-- liefert The created object
function NachbarFelderUIHelper.createRangeElement(generalSettingsPage, id, i18nTextId, minValue, maxValue, step, unit, target, callbackFunc, nillable)
	local rangeElementBox = createElement(generalSettingsPage, generalSettingsPage.multiVolumeVoiceBox, id, i18nTextId, target, callbackFunc)

	local rangeElement = rangeElementBox.elements[1]
	local texts = {}

	if nillable then
		table.insert(texts, "-")
	end

	local digits = 0
	local tmpStep = step
	while tmpStep < 1 do
		digits = digits + 1
		tmpStep = tmpStep * 10
	end
	local formatTemplate = (".%df"):format(digits)
	for i = minValue, maxValue, step do
		local text = ("%" .. formatTemplate):format(i)
		if unit then
			text = ("%s %s"):format(text, unit)
		end
		table.insert(texts, text)
	end
	rangeElement:setTexts(texts)

	return rangeElementBox
end

-- Dynamically creates controls based on the controlProperties configuration table.
-- For bool values, supply just the name, for ranges, additionally supply min, max and step, and for choices, supply a values table in addition to the name
-- For choices, you can also set nillable to true to get a "-" item for base game behavior, for example.
-- For every control name, a <prefix>_<name>_long and _short text must exist in the l10n files.
-- The _short text will be the title of the setting, the _long" text will be its tool tip.
-- For each control, a on_<name>_changed callback will be called on change.
-- settingsPage: The general settings page
-- sectionTitle: The i18n key for the control section. The UI element will be available as <owningTable>.sectionTitle
-- owningTable: The table which owns the controls and will receive the callbacks. Every control name will be available as <owningTable>.<name> and will be added to <owningTable.controls>
-- controlProperties: A table comprised of entries as described above
-- prefix: An optional prefix for every control name. This will also be prepended to the i18n keys
function NachbarFelderUIHelper.createControlsDynamically(settingsPage, sectionTitle, owningTable, controlProperties, prefix)
	owningTable.sectionTitle = NachbarFelderUIHelper.createSection(settingsPage, sectionTitle)
	owningTable.controls[1] = owningTable.sectionTitle

	for _, controlProps in ipairs(controlProperties) do
		local uiControl
		local id = prefix .. controlProps.name
		local callback = "on_" .. controlProps.name .. "_changed"
		if controlProps.min ~= nil then
			-- number range control
			uiControl = NachbarFelderUIHelper.createRangeElement(
			settingsPage, id, id, 
			controlProps.min, controlProps.max, controlProps.step, controlProps.unit,
			owningTable, callback, controlProps.nillable)

			uiControl.min = controlProps.min
			uiControl.max = controlProps.max
			uiControl.step = controlProps.step
			uiControl.nillable = controlProps.nillable

		elseif controlProps.values ~= nil then
			-- enum control
			uiControl = NachbarFelderUIHelper.createChoiceElement(settingsPage, id, id, controlProps.values, owningTable, callback, controlProps.nillable)
			uiControl.values = controlProps.values -- for mapping values later on, if necessary
			uiControl.nillable = controlProps.nillable
		else
			-- bool switch
			uiControl = NachbarFelderUIHelper.createBoolElement(settingsPage, id, id, owningTable, callback)
		end

		uiControl.autoBind = controlProps.autoBind
		uiControl.name = controlProps.name
		uiControl.subTable = controlProps.subTable
		uiControl.propName = controlProps.propName
		table.insert(owningTable.controls, uiControl)
		owningTable[controlProps.name] = uiControl -- allow accessing the control by its name

		-- Allow mouse/keyboard selection of the settings
		NachbarFelderUIHelper.registerFocusControls(owningTable.controls)
		settingsPage.generalSettingsLayout:invalidateLayout()
	end
end


-- Hooks into the focus manager at just the right point in time to register any relevant controls.
-- Make sure you also supply your section headers here!
-- controls: A list of controls
function NachbarFelderUIHelper.registerFocusControls(controls)
	FocusManager.setGui = Utils.appendedFunction(FocusManager.setGui, function(_, gui)
		for _, control in ipairs(controls) do
			if not control.focusId or not FocusManager.currentFocusData.idToElementMapping[control.focusId] then
				if not FocusManager:loadElementFromCustomValues(control, nil, nil, false, false) then
					Logging.warning("Failed loading focus element for %s. Keyboard/controller menu navigation might be bugged.", control.id or control.name)
				end
			end
		end
		local settingsPage = g_gui.screenControllers[InGameMenu].pageSettings
		-- Invalidate the layout in order to relink items properly
		settingsPage.generalSettingsLayout:invalidateLayout()
	end)
end

-- Makes sure UI controls are being populated with data from targetTable when the settings frame gets opened, and updates the properties in targetTable when the user changes values.
-- If you need to populate the controls at additional points in time, you can call the "populateAutoBindControls" function in owningTable after calling this method.
-- Whenever a value changes, the updateFunc will be called, if it was supplied
-- owningTable: The table which owns the controls.
-- targetTable: The table which holds the settings. The name of the controls and the name of the settings must be identical
-- updateFunc: This function will be called whenever any auto-bound value changes
function NachbarFelderUIHelper.setupAutoBindControls(owningTable, targetTable, updateFunc)
	-- Define and store a function which is able to populate the automatically bound controls
	owningTable.populateAutoBindControls = function()
		for _, control in ipairs(owningTable.controls) do
			if control.autoBind then
				local value = NachbarFelderUIHelper.getAutoBoundValueFromTable(control, targetTable)
				NachbarFelderUIHelper.setControlValue(control, value)
			end
		end
	end
	-- Call the function when the settings frame is being opened
	InGameMenuSettingsFrame.onFrameOpen = Utils.appendedFunction(InGameMenuSettingsFrame.onFrameOpen, owningTable.populateAutoBindControls)
	-- Dynamically create callbacks
	for _, control in ipairs(owningTable.controls) do
		if control.autoBind then
			local callbackName = "on_autoBind_" .. control.name .. "_changed"
			owningTable[callbackName] = function(self, newState)
				local newValue = NachbarFelderUIHelper.getControlValue(control, newState)
				NachbarFelderUIHelper.setAutoBoundValueInTable(control, newValue, targetTable)
				if updateFunc then
					updateFunc(owningTable, control, newValue)
				end
			end
			-- Update the callback
			control.elements[1]:setCallback("onClickCallback", callbackName)
		end
	end
end

-- Reads the current value of an auto bound control from the settings object (rather than from the UI control's current state)
-- control: The UI control
-- targetTable: The table which is bound to the control
-- liefert The value
function NachbarFelderUIHelper.getAutoBoundValueFromTable(control, targetTable)
	if control.subTable == nil then
		return targetTable[control.propName or control.name]
	else
		return targetTable[control.subTable][control.propName or control.name]
	end
end

-- Writes the current value for an auto bound control to the settings object
-- control: The UI control
-- value: The value
-- targetTable: The table which is bound to the control
function NachbarFelderUIHelper.setAutoBoundValueInTable(control, value, targetTable)
	if control.subTable == nil then
		targetTable[control.propName or control.name or "ERROR"] = value
	else
		targetTable[control.subTable][control.propName or control.name] = value
	end
end

-- Sets a range control to the given value. The method will find the appropriate index for the value automatically.
-- control: The UI control
-- value: The value which shall be displayed to the user
function NachbarFelderUIHelper.setRangeValue(control, value)
	local valueIndex
	if control.nillable and value == nil then
		valueIndex = 1
	else
		valueIndex = math.floor(((value - control.min) / control.step + 1) + 0.5) -- floor(x+0.5) = round(x)
		if control.nillable then
			valueIndex = valueIndex + 1
		end
	end
	control.elements[1]:setState(valueIndex)
end

-- Retrieves the current value of a UI range control.
-- control: The UI control
-- controlState: The currently selected index
-- liefert The value which was selected by the user (rather than the index)
function NachbarFelderUIHelper.getRangeValue(control, controlState)
	if control.nillable and controlState == 1 then
		return nil
	else
		local offset = 1
		if control.nillable then
			offset = 2
		end
		return control.min + control.step * (controlState - offset)
	end
end

-- Sets a choice control to the given value. The method will find the appropriate index for the value automatically.
-- control: The UI control
-- value: The value which shall be displayed to the user, except for enums, where this is the index
function NachbarFelderUIHelper.setChoiceValue(control, value)
	if control.hasStrings then
		control.elements[1]:setState(value)
	else
		-- Find the index of the value which is being used
		for index, val in control.values do
			if val == value then
				control.elements[1]:setState(index)
			end
		end
	end
end

-- Retrieves the current value of a UI choice control.
-- control: The UI control
-- controlState: The currently selected index
-- liefert The value which was selected by the user (rather than the index, except for enums, where this will be the index)
function NachbarFelderUIHelper.getChoiceValue(control, controlState)
	if control.hasStrings then
		return controlState
	else
		return control.values[controlState]
	end
end

-- Sets the current value for a UI yes/no control.
-- control: The UI control
-- value: The value which shall be displayed to the user
function NachbarFelderUIHelper.setBoolValue(control, value)
	control.elements[1]:setState(value and BinaryOptionElement.STATE_RIGHT or BinaryOptionElement.STATE_LEFT)
end

-- Gets the current value of a UI yes/no control
-- controlState: The currently selected index of the control.
-- liefert The yes/no value as selected by the user
function NachbarFelderUIHelper.getBoolValue(controlState)
	return controlState == 2
end

-- Sets the given value for the given control. The function will automatically determine whether this is a yes/no, an enum or a number range value
-- control: The control
-- value: The value
function NachbarFelderUIHelper.setControlValue(control, value)
	if control.min ~= nil then
		NachbarFelderUIHelper.setRangeValue(control, value)
	elseif control.values ~= nil then
		NachbarFelderUIHelper.setChoiceValue(control, value)
	else
		NachbarFelderUIHelper.setBoolValue(control, value)
	end
end

-- Retrieves the value from the given control based on the control state (which is obtained from the callback function)
-- control: The UI control
-- controlState: The current index of the selected value
-- liefert The value of the control. This could be a boolean, a number value, an enum value or nil dependent on the type of control
function NachbarFelderUIHelper.getControlValue(control, controlState)
	if control.min ~= nil then
		return NachbarFelderUIHelper.getRangeValue(control, controlState)
	elseif control.values ~= nil then
		return NachbarFelderUIHelper.getChoiceValue(control, controlState)
	else
		return NachbarFelderUIHelper.getBoolValue(controlState)
	end
end

-- Bugfix the "slider" of Off/On elements which can sometimes go out of bounds
BinaryOptionElement.update = Utils.appendedFunction(BinaryOptionElement.update, function(element, _)
	if element.sliderState < 0 then
		element.sliderState = 0
		element.sliderElement:setPosition(0)
	end
end)
package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end

local stored
local failSave = false
PersistentDB = {
    GetStructuredData = function() return copy(stored) end,
    SetStructuredData = function(_, _, value)
        if failSave then return false end
        stored = copy(value)
        return true
    end,
    SetString = function() return true end,
}
Event = { Draw = { Unsubscribe = function() end } }
id = { Component = { TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP = "foreground" } }
local topLayer = { width = 900, height = 700 }

GameKey = { CONTROL = 1, SHIFT = 2 }
local Styles = require("src/styles")
local SavedStyles = require("src/saved_styles")
local UI = require("src/ui")

ui = {
    Hook = { ONRESIZE = 1 },
    AlignMode = { CENTRE = 1 },
    Interfaces = {
        GetComponent = function(_, component)
            equal("foreground", component, "style windows request the foreground layer")
            return topLayer
        end,
    },
    Rectangle = {
        new = function(parent)
            local swatch = {
                SetPos = function(self, x, y) self.x, self.y = x, y end,
                SetSize = function(self, width, height)
                    self.width, self.height = width, height
                end,
            }
            parent.swatch = swatch
            return swatch
        end,
    },
}

local function control(options)
    local widget = {
        content = {}, options = options, rows = {}, buttons = {}, texts = {},
        simpleButtons = {}, spriteButtons = {}, scrollY = 0,
        subscriptions = {},
    }
    widget.root = widget
    function widget:Subscribe(hook, callback) self.subscriptions[hook] = callback end
    function widget:Refresh() self.refreshed = true end
    function widget:SetTitle(title) self.title = title end
    function widget:SetScrollable(scrollable) self.scrollable = scrollable end
    function widget:AddText(value)
        local text = {
            content = type(value) == "table" and value.text or value,
            Destroy = function(self) self.destroyed = true end,
        }
        self.texts[#self.texts + 1] = text
        return text
    end
    function widget:AddPanel(panelOptions)
        local panel = control(panelOptions)
        self.rows[#self.rows + 1] = panel
        return panel
    end
    function widget:AddFancyButton(label, action)
        self.buttons[label] = { click = action }
    end
    function widget:AddSimpleButton(label, action)
        local button = { root = {}, click = action }
        self.simpleButtons[#self.simpleButtons + 1] = button
        if label ~= "" then self.buttons[label] = button end
        return button
    end
    function widget:AddSpriteButton(sprite, action, buttonOptions)
        local button = { click = action, disabled = false, options = buttonOptions }
        function button:SetDisabled(value) self.disabled = value end
        self.spriteButtons[sprite] = button
        return button
    end
    function widget:AddTextField(fieldOptions)
        local field = { value = fieldOptions.text or "", options = fieldOptions }
        function field:GetText() return self.value end
        if self.input == nil then
            self.input = field
        else
            self.labelInput = field
        end
        return field
    end
    function widget:AddColourPicker(pickerOptions)
        local picker = { value = pickerOptions.value, closed = false }
        function picker:GetValue() return self.value end
        function picker:SetValue(value) self.value = value end
        function picker:Close() self.closed = true end
        self.picker = picker
        return picker
    end
    function widget:AddCheckboxButton(entries)
        local checks = {}
        for _, item in ipairs(entries) do checks[item.value] = item.selected end
        function checks:IsSelected(value) return self[value] == true end
        function checks:SetSelected(value, selected) self[value] = selected end
        self.checks = checks
        return checks
    end
    function widget:SetScrollPosition(value) self.scrollY = value end
    function widget:Close()
        if self.options.onClose then self.options.onClose(self) end
        self.root = nil
    end
    function widget:Destroy()
        self.destroyed = true
        for _, row in ipairs(self.rows) do row:Destroy() end
        self.root = nil
    end
    return widget
end

local windowsCreated = 0
UI.prettyui = {
    Window = {
        new = function(parent, options)
            if options.title ~= "Tile customization" then
                equal(topLayer, parent, "style windows are above native interfaces")
            end
            windowsCreated = windowsCreated + 1
            local window = control(options)
            window.title = options.title
            return window
        end,
    },
    SimpleView = {
        new = function(parent, options)
            local view = control(options)
            view.parent = parent
            return view
        end,
    },
}
UI.styleHandlers = {
    list = function() return SavedStyles:list() end,
    get = function(id) return SavedStyles:get(id) end,
    create = function(...) return SavedStyles:create(...) end,
    update = function(...) return SavedStyles:update(...) end,
    delete = function(id) return SavedStyles:delete(id) end,
    maxStyles = SavedStyles.MAX_STYLES,
}
UI.currentStyle = Styles.fromColour(Styles.DEFAULT_OUTLINE)
UI.globalStyle = { fill = false, outlineCornersOnly = false }
UI.gameArea = { width = 900, height = 700 }
UI.recentColours = {}
UI.ensureMounted = function() return true end

local function currentRow(window, position)
    local visible = 0
    for _, row in ipairs(window.rows) do
        if not row.destroyed then
            visible = visible + 1
            if visible == position then return row end
        end
    end
    error("No live style row at position " .. position)
end

UI:mountContent({ width = 640, height = 480 })
local manageStyles = UI.contentView.spriteButtons.SETTINGS
assert(manageStyles, "content panel exposes a style-manager action")
topLayer = nil
manageStyles.click()
equal(nil, UI.styleManagerWindow, "missing foreground layer never opens a hidden manager")
topLayer = { width = 900, height = 700 }
manageStyles.click()
local manager = UI.styleManagerWindow
assert(manager, "content-panel action opens the manager")
local list = UI.styleManagerView
equal(manager.content, list.parent, "style list is inside the manager window")
equal(false, manager.scrollable, "only the current manager page scrolls")
equal(true, UI:isPromptOpen(), "manager suppresses tile context actions")
equal(6, #list.rows, "starter styles appear in management list")
equal(false, list.spriteButtons.PLUS.disabled, "initial capacity allows adding")
local originalDangerRow = list.rows[2]
local swatch = originalDangerRow.content.swatch
equal(0xFF4444FF, swatch.rgba, "manager previews the saved outline colour")
equal(4 + swatch.y, originalDangerRow.options.height - 4 - swatch.y - swatch.height,
    "style card has matching visual top and bottom padding")
assert(originalDangerRow.spriteButtons.PENCIL and originalDangerRow.spriteButtons.TRASH,
    "each starter style can be edited and deleted")
list.subscriptions[ui.Hook.ONRESIZE]()
equal(true, list.refreshed, "list refreshes when its window is resized")

local windowCount = windowsCreated
originalDangerRow.spriteButtons.PENCIL.click()
local form = UI.styleManagerView
equal(manager, UI.styleManagerWindow, "editing reuses the manager window")
equal(windowCount, windowsCreated, "editing does not open another window")
equal("Edit tile style", manager.title, "manager title reflects editing")
equal(true, list.destroyed, "the editor replaces the style list")
assert(form.spriteButtons.BACK, "editor has a top-left back button")
equal(nil, form.spriteButtons.PLUS, "edit view replaces add action")
equal("Danger", form.input.value, "edit form shows the stored name")
equal(0xFF4444FF, form.picker:GetValue(), "edit form loads the saved colour")
equal("", form.labelInput.value, "default tile label begins optional")
form.input.value = "  Hazard  "
form.labelInput.value = "  Avoid  "
form.picker:SetValue(0xAABBCC88)
form.checks:SetSelected("fill", false)
form.checks:SetSelected("corners", true)
form.buttons.Save.click()
equal(nil, UI.styleFormState, "save returns to the list")
equal("Tile styles", manager.title, "returning restores the manager title")
equal(true, form.picker.closed, "returning closes the colour picker")
equal(true, form.destroyed, "editor controls are released")
equal("Hazard", SavedStyles:get("style_2").name, "renamed starter is persisted")
equal("Avoid", SavedStyles:get("style_2").label,
    "edited style default label is persisted")
equal(0xAABBCC88, SavedStyles:get("style_2").outlineColour,
    "committed RGBA including opacity is persisted")
equal(false, SavedStyles:get("style_2").fill, "edited fill override is persisted")
equal(true, SavedStyles:get("style_2").outlineCornersOnly,
    "edited corners override is persisted")
equal(true, originalDangerRow.destroyed, "manager releases replaced rows")
local hazardRowWithLabel = currentRow(UI.styleManagerView, 2)
equal(originalDangerRow.options.height, hazardRowWithLabel.options.height,
    "default labels do not change style-card height")
equal(1, #hazardRowWithLabel.texts,
    "style list shows the name without repeating the default tile label")
hazardRowWithLabel.spriteButtons.PENCIL.click()
form = UI.styleManagerView
equal("Avoid", form.labelInput.value, "editing loads the saved default label")
form.labelInput.value = "Uncommitted"
form.spriteButtons.BACK.click()
equal(manager, UI.styleManagerWindow, "back returns within the same window")
equal(nil, UI.styleFormState, "back leaves edit mode")
equal(true, form.picker.closed, "back closes an open colour picker")
equal("Avoid", SavedStyles:get("style_2").label,
    "back discards uncommitted style changes")
currentRow(UI.styleManagerView, 2).spriteButtons.PENCIL.click()
form = UI.styleManagerView
form.labelInput.value = " "
form.buttons.Save.click()
equal(nil, SavedStyles:get("style_2").label,
    "an empty field removes the default label from an existing style")

UI.styleManagerView.spriteButtons.PLUS.click()
form = UI.styleManagerView
equal(windowCount, windowsCreated, "adding also stays within the manager window")
equal("Add tile style", manager.title, "manager title reflects creation")
form.input.value = "Hazard"
form.buttons.Save.click()
equal(true, form.texts[#form.texts].content:find("already exists", 1, true) ~= nil,
    "duplicate names surface a validation error")
equal(form, UI.styleManagerView, "failed save retains editable fields")
form.input.value = "Route one"
form.labelInput.value = "  Exit  "
form.picker:SetValue(0x224466C0)
form.checks:SetSelected("fill", true)
form.buttons.Save.click()
equal(7, #SavedStyles:list(), "new style appears alongside starter styles")
equal(0x224466C0, SavedStyles:list()[7].outlineColour, "new style keeps alpha")
equal(true, SavedStyles:list()[7].fill, "new style captures explicit fill")
equal("Exit", SavedStyles:list()[7].label, "new style captures a default label")
for index = 8, 10 do
    UI.styleManagerView.spriteButtons.PLUS.click()
    form = UI.styleManagerView
    form.input.value = "Route " .. index
    form.buttons.Save.click()
end
equal(10, #SavedStyles:list(), "manager reaches ten styles")
equal(true, UI.styleManagerView.spriteButtons.PLUS.disabled,
    "add is disabled at the limit")
equal(false, UI:openStyleForm(), "the limit is enforced even via direct form request")
list = UI.styleManagerView
list:SetScrollPosition(72)
currentRow(list, 2).spriteButtons.PENCIL.click()
UI.styleManagerView.spriteButtons.BACK.click()
equal(72, UI.styleManagerView.scrollY,
    "back returns to the scrolled list position")

local hazardRow = currentRow(UI.styleManagerView, 2)
hazardRow.spriteButtons.TRASH.click()
equal(true, UI.styleDeleteWindow ~= nil, "deletion needs confirmation")
UI.styleDeleteWindow.buttons.Cancel.click()
equal("Hazard", SavedStyles:get("style_2").name, "cancel leaves the style unchanged")
hazardRow.spriteButtons.TRASH.click()
failSave = true
UI.styleDeleteWindow.buttons.Delete.click()
equal(true, UI.styleDeleteWindow.texts[2].content:find("Could not", 1, true) ~= nil,
    "storage failures remain visible in the confirmation")
equal(true, UI.styleDeleteWindow ~= nil, "failed delete retains the confirmation")
equal("Hazard", SavedStyles:get("style_2").name, "failed delete keeps the style")
failSave = false
UI.styleDeleteWindow.buttons.Delete.click()
equal(nil, SavedStyles:get("style_2"), "confirmed delete removes the style")
equal(false, UI.styleManagerView.spriteButtons.PLUS.disabled,
    "deletion restores capacity")

UI.styleManagerView.spriteButtons.PLUS.click()
form = UI.styleManagerView
manager:Close()
equal(nil, UI.styleManagerWindow, "manager close releases its window")
equal(nil, UI.styleFormState, "manager close leaves edit mode")
equal(true, form.picker.closed, "manager close releases nested picker")
equal(true, form.destroyed, "manager close releases editor controls")
equal(false, UI:isPromptOpen(), "menu actions resume after manager closes")

UI:mountContent({ width = 260, height = 480 })
assert(UI.contentView.spriteButtons.SETTINGS,
    "narrow content panels retain style management")
local cancelledCustomization = false
local confirmedLabel
equal(true, UI:promptForCustomization("Original", 0x123456FF, false, false, {
    preview = function() end,
    confirm = function(label) confirmedLabel = label end,
    cancel = function() cancelledCustomization = true end,
}), "tile customization opens")
local tilePrompt = UI.colourPromptWindow
UI.colourPromptLabelInput.value = "Pending"
UI.colourPromptLabelInput.options.onChange()
tilePrompt.buttons["Manage tile styles"].click()
assert(UI.styleManagerWindow, "tile customization opens style management")
equal(tilePrompt, UI.colourPromptWindow,
    "opening style management preserves the customization dialog")
equal("Pending", UI.colourPromptLabelInput:GetText(),
    "uncommitted tile label remains in the customization dialog")
equal(false, cancelledCustomization,
    "opening style management does not cancel a tile preview")
UI.styleManagerWindow:Close()
equal(tilePrompt, UI.colourPromptWindow,
    "closing management returns to the same customization dialog")
tilePrompt.buttons.Confirm.click()
equal("Pending", confirmedLabel, "returning to customization can commit its edits")
equal(false, cancelledCustomization, "manager close does not cancel customization")
equal(true, UI:openStyleManager(), "manager can remount")
UI.styleManagerView.rows[1].spriteButtons.TRASH.click()
UI:destroy()
equal(nil, UI.styleManagerWindow, "game teardown releases manager")
equal(nil, UI.styleDeleteWindow, "game teardown releases pending delete")

print("test_style_ui: ok")

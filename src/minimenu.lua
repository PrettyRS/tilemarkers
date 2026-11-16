local RegionBindings = require("src/region_bindings")
local Tiles = require("src/tiles")
local UI = require("src/ui")

local Minimenu = {}

local EVENT_ID = "tileMarker"
local STYLE_PARENT_LABEL = "Apply tile style"
local STYLE_PARENT_PREFIX = STYLE_PARENT_LABEL .. " "
local MENU_CURSOR_DEAD_ZONE_SQUARED = 16

local menuHover = nil
local suppressedMousePosition = nil
local started = false
local actions = {}

local function hoveredTile()
    if not Mouse.IsAvailable() then
        return nil
    end

    local mousePosition = Mouse.GetPosition()
    if mousePosition == nil then
        return nil
    end

    if suppressedMousePosition ~= nil then
        local deltaX = mousePosition.x - suppressedMousePosition.x
        local deltaY = mousePosition.y - suppressedMousePosition.y
        if deltaX * deltaX + deltaY * deltaY
                <= MENU_CURSOR_DEAD_ZONE_SQUARED then
            return nil
        end
        suppressedMousePosition = nil
    end

    return ScreenConvert.ScreenToCoordGrid(mousePosition)
end

local function moveMenuEntry(miniMenu, label, targetIndex, actionType, prefix)
    for foundIndex, entry in ipairs(miniMenu.entries) do
        local overrideText = entry.overrideText
        if (actionType ~= nil and entry.actionType == actionType)
                or overrideText == label
                or entry.fullText == label
                or entry.verbText == label
                or (prefix ~= nil and type(overrideText) == "string"
                    and overrideText:sub(1, #prefix) == prefix) then
            local index = foundIndex
            while index < targetIndex do
                miniMenu:Swap(index, index + 1)
                index = index + 1
            end
            while index > targetIndex do
                miniMenu:Swap(index, index - 1)
                index = index - 1
            end
            return true
        end
    end
    return false
end

local function placeTileActions(miniMenu, primaryLabel, secondaryLabel, hasStyleMenu)
    local cancelAtBottom = moveMenuEntry(
        miniMenu, "Cancel", 1, MiniMenuActionType.CANCEL)
    local nextIndex = cancelAtBottom and 2 or 1
    if hasStyleMenu then
        moveMenuEntry(miniMenu, STYLE_PARENT_LABEL, nextIndex, nil, STYLE_PARENT_PREFIX)
        nextIndex = nextIndex + 1
    end
    if secondaryLabel ~= nil then
        moveMenuEntry(miniMenu, secondaryLabel, nextIndex)
        nextIndex = nextIndex + 1
    end
    moveMenuEntry(miniMenu, primaryLabel, nextIndex)
end

local function moveAboveNativeBottom(miniMenu, nativeEntryCount, customCount)
    if nativeEntryCount < 1 or customCount < 1 then return end
    for index = customCount + 1, 2, -1 do
        miniMenu:Swap(index, index - 1)
    end
end

local function isWorldMapText(value)
    if type(value) ~= "string" then
        return false
    end
    local plainText = value:gsub("<.->", ""):match("^%s*(.-)%s*$")
    return plainText:lower() == "world map"
end

local function appendWorldMapAction(miniMenu)
    for _, entry in ipairs(miniMenu.entries) do
        if isWorldMapText(entry.overrideText)
                or isWorldMapText(entry.fullText)
                or isWorldMapText(entry.verbText) then
            local nativeEntryCount = miniMenu.entryCount
            local customCount = 0
            if actions.clearVisible ~= nil then
                miniMenu:Add("Clear Visible Tilemarkers", actions.clearVisible)
                customCount = customCount + 1
            end
            if actions.createVisiblePreset ~= nil then
                miniMenu:Add(
                    "New Preset from Visible Markers",
                    actions.createVisiblePreset)
                customCount = customCount + 1
            end
            if actions.importPreset ~= nil then
                miniMenu:Add("Import Tilemarkers Preset", actions.importPreset)
                customCount = customCount + 1
            end
            moveAboveNativeBottom(miniMenu, nativeEntryCount, customCount)
            return true
        end
    end
    return false
end

local function setTileMarked(store, source, marked)
    if UI:isKeybindCapturing() then return end
    if not marked then
        store:remove(source)
        return
    end

    local style = UI:getStyle()
    store:add(source, {
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
        outlineCornersOnly = style.outlineCornersOnly,
    })
    UI:rememberColour(style.outlineColour)
end

local function customizeTile(store, source)
    local currentLabel = store:getLabel(source) or ""
    local currentColour = store:getColour(source) or UI:getStyle().outlineColour
    local currentFill = store:getFill(source)
    local currentOutlineCornersOnly = store:getOutlineCornersOnly(source)
    UI:promptForCustomization(
        currentLabel,
        currentColour,
        currentFill,
        currentOutlineCornersOnly,
        {
            preview = function(label, colour, fill, outlineCornersOnly)
                store:previewCustomization(
                    source, label, colour, fill, outlineCornersOnly)
            end,
            confirm = function(label, colour, fill, outlineCornersOnly)
                store:setCustomization(
                    source, label, colour, fill, outlineCornersOnly)
            end,
            cancel = function()
                store:cancelCustomizationPreview(source)
            end,
        })
end

local function applyTileStyle(store, source, styleID)
    if UI:isKeybindCapturing() or not store:contains(source) then return end
    local style = actions.getStyle and actions.getStyle(styleID) or nil
    if style == nil then return end

    store:setCustomization(
        source,
        style.label or store:getLabel(source) or "",
        style.outlineColour,
        style.fill,
        style.outlineCornersOnly)
    UI:rememberColour(style.outlineColour)
end

local function styleMenuChildren(store, source)
    local children = {}
    for _, style in ipairs(actions.listStyles and actions.listStyles() or {}) do
        local escapedName = style.name:gsub("[<>]", {
            ["<"] = "<lt>",
            [">"] = "<gt>",
        })
        children[#children + 1] = {
            label = string.format(
                "<col=%06X>%s</col>",
                (style.outlineColour >> 8) & 0xFFFFFF,
                escapedName),
            action = applyTileStyle,
            arguments = { store, source, style.id },
        }
    end
    return children
end

local function onReady(miniMenuReadyEvent)
    local miniMenu = miniMenuReadyEvent.miniMenu
    local editStore = actions.editStore and actions.editStore() or nil
    if editStore == nil and appendWorldMapAction(miniMenu) then
        menuHover = nil
        suppressedMousePosition = nil
        return
    end

    if not UI:isMarkingKeybindDown() or UI:isPromptOpen() then
        menuHover = nil
        suppressedMousePosition = nil
        return
    end

    local target = hoveredTile()
    if target == nil then
        menuHover = nil
        return
    end
    menuHover = target

    local source = RegionBindings.toSource(target)
    local store = editStore or Tiles
    local preset = editStore == nil
        and actions.findPresetAt ~= nil
        and actions.findPresetAt(source)
        or nil

    local primaryLabel, secondaryLabel
    local marked = store:contains(source)
    if preset ~= nil and actions.startPresetEdit ~= nil then
        primaryLabel = "Edit in preset"
        miniMenu:Add(
            primaryLabel,
            actions.startPresetEdit,
            preset.id,
            preset.name)
    elseif marked then
        primaryLabel = editStore and "Remove from preset" or "Unmark tile"
        miniMenu:Add(
            primaryLabel,
            setTileMarked,
            store,
            source,
            false)
        secondaryLabel = "Customize Tile"
        miniMenu:Add(secondaryLabel, customizeTile, store, source)
    else
        primaryLabel = editStore and "Add to preset" or "Mark tile"
        miniMenu:Add(
            primaryLabel,
            setTileMarked,
            store,
            source,
            true)
    end

    local hasStyleMenu = false
    if preset == nil and marked then
        local children = styleMenuChildren(store, source)
        if #children > 0 then
            UI.prettyui.MiniMenu.AddSubmenu(
                miniMenu, STYLE_PARENT_LABEL, children, {
                    title = "Tile styles",
                    position = "bottom",
                })
            hasStyleMenu = true
        end
    end
    -- AddSubmenu can rebuild the native entries; place actions after every Add.
    placeTileActions(miniMenu, primaryLabel, secondaryLabel, hasStyleMenu)
end

local function onClosed()
    menuHover = nil
    local mousePosition = Mouse.IsAvailable() and Mouse.GetPosition() or nil
    suppressedMousePosition = mousePosition and {
        x = mousePosition.x,
        y = mousePosition.y,
    } or nil
end

function Minimenu.getHover()
    if UI:isKeybindCapturing() then return nil end
    local menuOpen = MiniMenu.IsOpen()
    local modifiersDown = UI:isMarkingKeybindDown()
    if not menuOpen and not modifiersDown then
        suppressedMousePosition = nil
    end

    if menuOpen then
        return menuHover
    end
    if modifiersDown and UI:isHoverPreviewEnabled() then
        return hoveredTile()
    end
    return nil
end

function Minimenu.reset()
    menuHover = nil
    suppressedMousePosition = nil
end

function Minimenu.start(menuActions)
    actions = menuActions or {}
    if started then
        return
    end
    started = true
    Event.MiniMenuReady.Subscribe(EVENT_ID, onReady)
    Event.MiniMenuClosed.Subscribe(EVENT_ID, onClosed)
end

function Minimenu.shutdown()
    if not started then
        return
    end
    started = false
    Event.MiniMenuReady.Unsubscribe(EVENT_ID)
    Event.MiniMenuClosed.Unsubscribe(EVENT_ID)
    actions = {}
    Minimenu.reset()
end

return Minimenu

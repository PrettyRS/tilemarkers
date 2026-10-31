package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local callbacks = {}
local function event(name)
    return {
        Subscribe = function(id, callback)
            equal("tileMarker", id, name .. " subscription ID")
            callbacks[name] = callback
        end,
        Unsubscribe = function() end,
    }
end

Event = {
    Draw = event("Draw"),
    Logic = event("Logic"),
    RegionCreated = event("RegionCreated"),
    RegionUpdated = event("RegionUpdated"),
    MiniMenuReady = event("MiniMenuReady"),
    MiniMenuClosed = event("MiniMenuClosed"),
    GameStateChanged = event("GameStateChanged"),
}

local hover = {
    name = "target", level = 0, x = 10, z = 10,
    ToPacked = function() return 123 end,
}
local cursorHover = hover
local mousePosition = { x = 100, y = 100 }
local source = { name = "source", level = 0, x = 3300, z = 3301 }
local playerCoord = { name = "player", level = 0, x = 10, z = 10 }
local playerPosition = { x = 10 * 512 + 256, y = 0, z = 10 * 512 + 256 }
local controlDown = false
local shiftDown = false
local keyboardBlocked = false
local customKeyDown = false
local capturingKeybind = false
GameKey = { CONTROL = 82, SHIFT = 81, K = 55 }

Keyboard = {
    IsAvailable = function() return true end,
    IsBlocked = function() return keyboardBlocked end,
    IsGameKeyDown = function(key)
        if key == GameKey.CONTROL then return controlDown end
        if key == GameKey.SHIFT then return shiftDown end
        if key == GameKey.K then return customKeyDown end
        return false
    end,
}
Mouse = {
    IsAvailable = function() return true end,
    GetPosition = function() return mousePosition end,
}
CoordGrid = {
    new = function(level, mapX, mapZ, localX, localZ)
        return {
            level = level,
            x = mapX * 64 + localX,
            z = mapZ * 64 + localZ,
        }
    end,
}

ScreenConvert = {
    ScreenToCoordGrid = function() return cursorHover end,
}
Player = {
    IsAvailable = function() return true end,
    GetEntity = function()
        return setmetatable({
            isValid = true, coordGrid = playerCoord, position = playerPosition,
        }, {
            __index = function(_, key)
                error("Unsupported PlayerEntity property: " .. key)
            end,
        })
    end,
}
World = {
    GetMapSquareBounds = function() return { x = 0, y = 0, width = 2, height = 2 } end,
}
MiniMenuActionType = {
    WALK = 23,
    CANCEL = 1006,
    OP_LOC1 = 3,
    OP_LOC2 = 4,
}
GameState = { GAME = 1 }
local miniMenuOpen = false
MiniMenu = {
    IsOpen = function() return miniMenuOpen end,
}

local marked = false
local existingLabel = "Existing label"
local existingColour = 0x12345678
local recolouredSource
local recolouredValue
local addedSource
local removedSource
local addedMetadata
local labelledSource
local labelledText
local existingFill = false
local recolouredFill
local existingOutlineCornersOnly = false
local recolouredOutlineCornersOnly
local previewedSource
local previewedLabel
local previewedColour
local previewedFill
local previewedOutlineCornersOnly
local cancelledPreviewSource
local queriedTiles = {}
local queriedCoord
local queriedDistance
local clearedSources
local exportedCoords
local visibleExportTiles = {
    { x = 3200, z = 3201, level = 0 },
}
local directOverlapTiles
local allExportTiles = {
    { x = 3000, z = 3001, level = 0 },
}
local batchRemoveSucceeds = true
local Tiles = {
    query = function(_, coord, distance)
        queriedCoord = coord
        queriedDistance = distance
        if marked then return { [hover] = { text = "Direct marker" } } end
        return queriedTiles
    end,
    contains = function(_, coord)
        equal(source, coord, "mark state uses canonical source coordinate")
        return marked
    end,
    add = function(_, coord, metadata)
        marked = true
        addedSource = coord
        addedMetadata = metadata
    end,
    remove = function(_, coord)
        marked = false
        removedSource = coord
    end,
    getLabel = function(_, coord)
        equal(source, coord, "existing label uses canonical source coordinate")
        return existingLabel
    end,
    setLabel = function(_, coord, text)
        labelledSource = coord
        labelledText = text
        existingLabel = text ~= "" and text or nil
    end,
    getColour = function(_, coord)
        equal(source, coord, "existing colour uses canonical source coordinate")
        return existingColour
    end,
    getFill = function(_, coord)
        equal(source, coord, "existing fill uses canonical source coordinate")
        return existingFill
    end,
    getOutlineCornersOnly = function(_, coord)
        equal(source, coord, "existing corner outline uses canonical source coordinate")
        return existingOutlineCornersOnly
    end,
    setColour = function(_, coord, colour, fill, outlineCornersOnly)
        recolouredSource = coord
        recolouredValue = colour
        recolouredFill = fill
        recolouredOutlineCornersOnly = outlineCornersOnly
        existingColour = colour
        existingFill = fill
        existingOutlineCornersOnly = outlineCornersOnly
    end,
    previewCustomization = function(_, coord, label, colour, fill, outlineCornersOnly)
        previewedSource = coord
        previewedLabel = label
        previewedColour = colour
        previewedFill = fill
        previewedOutlineCornersOnly = outlineCornersOnly
    end,
    cancelCustomizationPreview = function(_, coord)
        cancelledPreviewSource = coord
        previewedSource = nil
        previewedLabel = nil
        previewedColour = nil
        previewedFill = nil
        previewedOutlineCornersOnly = nil
    end,
    setCustomization = function(_, coord, label, colour, fill, outlineCornersOnly)
        labelledSource = coord
        labelledText = label
        existingLabel = label ~= "" and label or nil
        recolouredSource = coord
        recolouredValue = colour
        recolouredFill = fill
        recolouredOutlineCornersOnly = outlineCornersOnly
        existingColour = colour
        existingFill = fill
        existingOutlineCornersOnly = outlineCornersOnly
    end,
    removeAll = function(_, coords)
        clearedSources = coords
        if not batchRemoveSucceeds then return false, 0 end
        for _, coord in ipairs(coords) do
            if coord == source then marked = false end
        end
        return true, #coords
    end,
    export = function()
        return allExportTiles
    end,
    exportCoords = function(_, coords)
        exportedCoords = coords
        if coords[1] and coords[1].x == nil then return visibleExportTiles end
        return directOverlapTiles or {}
    end,
    save = function() return true end,
}

local createdPresetName
local createdPresetTiles
local createdPresetActive
local deletedPresetID
local excludedPresetID
local updatedPresetID
local updatedPresetTiles
local presetAtSource
local startedPresetEditID
local startedPresetEditName
local presetSaveSucceeds = true
local updateCount = 0
local editablePreset = {
    id = "preset_1",
    name = "Editable",
    tiles = {},
}
local Presets = {
    list = function() return {} end,
    isActive = function() return false end,
    setActive = function() return true end,
    create = function(_, name, tiles, active)
        createdPresetName = name
        createdPresetTiles = tiles
        createdPresetActive = active
        return true, { id = "preset_test", name = name }
    end,
    rename = function() return true end,
    delete = function(_, id)
        deletedPresetID = id
        return true
    end,
    export = function() return true, "TM2token" end,
    import = function() return true end,
    query = function(_, _, _, _, excludedID)
        excludedPresetID = excludedID
        return {}
    end,
    findActiveAt = function(_, coord)
        equal(source, coord, "preset lookup uses canonical source coordinate")
        return presetAtSource
    end,
    get = function(_, id)
        return id == editablePreset.id and editablePreset or nil
    end,
    updateTiles = function(_, id, tiles)
        updatedPresetID = id
        updatedPresetTiles = tiles
        updateCount = updateCount + 1
        if presetSaveSucceeds then editablePreset.tiles = tiles end
        return presetSaveSucceeds, presetSaveSucceeds and "Saved" or "Could not save."
    end,
}
local editActive = false
local editMarked = false
local editAddedSource
local editRemovedSource
local editAddedMetadata
local editStyledSource
local editStyledLabel
local editStyledColour
local editStyledFill
local editStyledCorners
local pendingTransfer = {}
local PresetEditor = {
    revision = 0,
    presetID = nil,
    isActive = function() return editActive end,
    begin = function(self, preset, sourceTiles)
        equal(Tiles, sourceTiles, "editor receives the standalone tile store")
        editActive = true
        self.presetID = preset.id
        self.revision = self.revision + 1
        return true
    end,
    cancel = function(self)
        editActive = false
        self.presetID = nil
        self.revision = self.revision + 1
        pendingTransfer = {}
    end,
    export = function()
        return { { x = 3300, z = 3301, level = 0 } }
    end,
    transferCoords = function() return pendingTransfer end,
    query = function()
        return { [hover] = { text = "Working copy" } }
    end,
    contains = function() return editMarked end,
    add = function(_, coord, metadata)
        editMarked = true
        editAddedSource = coord
        editAddedMetadata = metadata
        if marked then pendingTransfer = { coord } end
    end,
    remove = function(_, coord)
        editMarked = false
        editRemovedSource = coord
        pendingTransfer = {}
    end,
    getLabel = function() return "Preset label" end,
    getColour = function() return 0x102030FF end,
    getFill = function() return true end,
    getOutlineCornersOnly = function() return false end,
    setCustomization = function(_, coord, label, colour, fill, corners)
        editStyledSource = coord
        editStyledLabel = label
        editStyledColour = colour
        editStyledFill = fill
        editStyledCorners = corners
    end,
    previewCustomization = function() end,
    cancelCustomizationPreview = function() end,
}
local RegionBindings = {
    resolveArea = function() return nil end,
    toSource = function(coord)
        equal(hover, coord, "hover is converted to source coordinate")
        return source
    end,
    clear = function() end,
}

local drawnHover
local drawnTiles
local promptOpen = false
local hoverPreviewEnabled = true
local promptedInitialLabel
local promptedInitialColour
local promptedInitialFill
local promptedInitialOutlineCornersOnly
local rememberedColour
local promptedCustomizationActions
local promptedClearCount
local clearConfirmation
local initializedPresetHandlers
local promptedPresetCreationVisible
local submenuRegistration
local savedStyles = {
    {
        id = "danger",
        label = "Watch out",
        name = "Danger",
        outlineColour = 0xEE4433FF,
        fillColour = 0xBE36298C,
        fill = true,
        outlineCornersOnly = false,
    },
    {
        id = "escape",
        name = "Escape <now>",
        outlineColour = 0x44CC99FF,
        fillColour = 0x36A37A8C,
        fill = false,
        outlineCornersOnly = true,
    },
}
local SavedStyles = {
    MAX_STYLES = 10,
    list = function() return savedStyles end,
    get = function(_, id)
        for _, style in ipairs(savedStyles) do
            if style.id == id then return style end
        end
    end,
}
local promptedPresetImport = false
local actualUI = require("src/ui")
local UI = {
    markingKeybind = {},
    prettyui = {
        KeybindField = {
            IsCapturing = function() return capturingKeybind end,
            IsDown = function(value)
                if capturingKeybind or #value == 0 then return false end
                for _, key in ipairs(value) do
                    if not Keyboard.IsGameKeyDown(key) then return false end
                end
                return true
            end,
        },
        MiniMenu = {
            AddSubmenu = function(menu, label, children, options)
                submenuRegistration = {
                    label = label,
                    children = children,
                    options = options,
                }
                menu:Add(label, function() end)
                menu.entries[menu.lastAddedIndex].overrideText =
                    label .. " <col=ffffff><gt></col>"
                if menu.resetSwapsOnAdd then return end
                local index = menu.lastAddedIndex
                local target = options.position == "top" and #menu.entries - 1
                    or options.position == "bottom" and 2
                    or #menu.entries - options.position + 1
                while index < target do
                    menu:Swap(index, index + 1)
                    index = index + 1
                end
                while index > target do
                    menu:Swap(index, index - 1)
                    index = index - 1
                end
            end,
        },
    },
    isMarkingKeybindDown = actualUI.isMarkingKeybindDown,
    isKeybindCapturing = actualUI.isKeybindCapturing,
    init = function(_, handlers)
        initializedPresetHandlers = handlers
    end,
    ensureMounted = function() return true end,
    syncMarkers = function(_, tiles, tile)
        drawnTiles = tiles
        drawnHover = tile
    end,
    drawLabels = function() end,
    getStyle = function()
        return {
            outlineColour = 0x12345678,
            fillColour = 0x0E2A4542,
        }
    end,
    isPromptOpen = function() return promptOpen end,
    isHoverPreviewEnabled = function() return hoverPreviewEnabled end,
    promptForCustomization = function(
        _, initialLabel, initialColour, initialFill, initialOutlineCornersOnly, actions)
        promptedInitialLabel = initialLabel
        promptedInitialColour = initialColour
        promptedInitialFill = initialFill
        promptedInitialOutlineCornersOnly = initialOutlineCornersOnly
        promptedCustomizationActions = actions
    end,
    promptForClear = function(_, tileCount, callback)
        promptedClearCount = tileCount
        clearConfirmation = callback
        return true
    end,
    promptForPresetCreation = function(_, visibleOnly)
        promptedPresetCreationVisible = visibleOnly
        return true
    end,
    promptForPresetImport = function()
        promptedPresetImport = true
        return true
    end,
    startPresetEdit = function(_, id, name)
        startedPresetEditID = id
        startedPresetEditName = name
        return initializedPresetHandlers.startEdit(id)
    end,
    rememberColour = function(_, colour)
        rememberedColour = colour
    end,
    destroySettings = function() end,
    destroyContent = function() end,
    destroy = function() end,
    shutdown = function() end,
}

package.loaded["src/tiles"] = Tiles
package.loaded["src/presets"] = Presets
package.loaded["src/preset_editor"] = PresetEditor
package.loaded["src/saved_styles"] = SavedStyles
package.loaded["src/region_bindings"] = RegionBindings
package.loaded["src/ui"] = UI
prettyui = {}
log = function() end

dofile("main.lua")

local function frame()
    callbacks.Logic()
    callbacks.Draw()
end

frame()
equal(nil, drawnHover, "hover is hidden without both modifiers")
controlDown = true
shiftDown = true
frame()
equal(hover, drawnHover, "Ctrl+Shift lights the hovered tile")
hoverPreviewEnabled = false
frame()
equal(nil, drawnHover, "disabled hover preview stays hidden with modifiers")
hoverPreviewEnabled = true
keyboardBlocked = true
frame()
equal(nil, drawnHover, "blocked keyboard input hides the hover")
keyboardBlocked = false

local addedEntry
local function readyMenu(entries, appendEntries, resetSwapsOnAdd)
    entries = entries or {
        { actionType = MiniMenuActionType.CANCEL, label = "Cancel" },
        { actionType = MiniMenuActionType.WALK, label = "Walk here" },
    }
    local insertionOrder = { table.unpack(entries) }
    local menu = {
        entryCount = #entries,
        entries = entries,
        resetSwapsOnAdd = resetSwapsOnAdd,
        Add = function(self, label, action, ...)
            addedEntry = {
                label = label,
                overrideText = label,
                action = action,
                args = table.pack(...),
            }
            local insertionIndex = appendEntries and #insertionOrder + 1 or 1
            table.insert(insertionOrder, insertionIndex, addedEntry)
            self.lastAddedIndex = insertionIndex
            if resetSwapsOnAdd then
                self.entries = { table.unpack(insertionOrder) }
            else
                table.insert(self.entries, insertionIndex, addedEntry)
            end
            self.entryCount = #self.entries
        end,
        Swap = function(self, left, right)
            self.entries[left], self.entries[right]
                = self.entries[right], self.entries[left]
        end,
    }
    callbacks.MiniMenuReady({ miniMenu = menu })
    return menu
end


local function findMenuEntry(menu, label)
    for _, entry in ipairs(menu.entries) do
        if entry.label == label then return entry end
    end
    return nil
end

UI.markingKeybind = { GameKey.K }
frame()
equal(nil, drawnHover, "custom keybind replaces Ctrl+Shift for preview")
equal(nil, findMenuEntry(readyMenu(), "Mark tile"),
    "custom keybind replaces Ctrl+Shift for menu actions")
customKeyDown = true
frame()
submenuRegistration = nil
local customMark = findMenuEntry(readyMenu(), "Mark tile")
equal(nil, submenuRegistration, "an unmarked tile has no style submenu")
assert(customMark, "single-key override enables tile marking")
UI.markingKeybind = { GameKey.CONTROL, GameKey.K }
controlDown = false
frame()
equal(nil, drawnHover, "partial custom chord does not preview")
equal(nil, findMenuEntry(readyMenu(), "Mark tile"),
    "partial custom chord does not enable marking")
controlDown = true
frame()
equal(hover, drawnHover, "complete custom chord enables preview")
assert(findMenuEntry(readyMenu(), "Mark tile"), "complete custom chord enables marking")
miniMenuOpen = true
capturingKeybind = true
frame()
equal(nil, drawnHover, "capture hides an existing menu hover")
customMark.action(table.unpack(customMark.args, 1, customMark.args.n))
equal(false, marked, "capture blocks marking from a previously opened menu")
equal(nil, findMenuEntry(readyMenu(), "Mark tile"),
    "capture suppresses new marking menu actions")
submenuRegistration = nil
readyMenu()
equal(nil, submenuRegistration, "capturing a shortcut suppresses the style submenu")
miniMenuOpen = false
capturingKeybind = false
UI.markingKeybind = {}
customKeyDown = false
frame()
equal(hover, drawnHover, "cleared override restores Ctrl+Shift preview")
assert(findMenuEntry(readyMenu(), "Mark tile"), "cleared override restores default menu binding")

local visibleSourceA = { name = "visible A" }
local visibleSourceB = { name = "visible B" }
queriedTiles = {
    [visibleSourceA] = {},
    [visibleSourceB] = {},
}
controlDown = false
shiftDown = false
addedEntry = nil
readyMenu({
    {
        actionType = MiniMenuActionType.CANCEL,
        label = "Unrelated interface action",
        fullText = "Unrelated interface action",
    },
})
equal(nil, addedEntry, "unrelated targets do not get the clear action")

local worldMapMenu = readyMenu({
    {
        actionType = MiniMenuActionType.CANCEL,
        label = "Cancel",
        fullText = "Cancel",
    },
    {
        label = "Open map settings",
        fullText = "Open map settings",
    },
    {
        label = "World Map",
        fullText = "World Map",
    },
})
local clearEntry = findMenuEntry(worldMapMenu, "Clear Visible Tilemarkers")
local createVisibleEntry = findMenuEntry(
    worldMapMenu,
    "New Preset from Visible Markers")
local importEntry = findMenuEntry(worldMapMenu, "Import Tilemarkers Preset")
equal(true, clearEntry ~= nil, "world map gets the clear action")
equal(true, createVisibleEntry ~= nil, "world map gets visible preset creation")
equal(true, importEntry ~= nil, "world map gets preset import")
clearEntry.action()
equal(playerCoord, queriedCoord, "clear action queries around the player")
equal(30, queriedDistance, "clear action uses the drawing distance")
equal(2, promptedClearCount, "clear action prompts with the visible marker count")
equal(nil, clearedSources, "markers remain until the prompt is confirmed")
clearConfirmation()
equal(2, #clearedSources, "confirmation removes every visible editable marker")
local cleared = {}
for _, coord in ipairs(clearedSources) do cleared[coord] = true end
equal(true, cleared[visibleSourceA], "clear action includes the first visible marker")
equal(true, cleared[visibleSourceB], "clear action includes the second visible marker")

equal(
    true,
    initializedPresetHandlers.create("Blank route"),
    "preset UI creation handler succeeds")
equal("Blank route", createdPresetName, "preset UI creation keeps submitted name")
equal(nil, next(createdPresetTiles), "preset UI creation starts with no tiles")
equal(true, createdPresetActive, "new blank preset is active while being edited")

createVisibleEntry.action()
equal(true, promptedPresetCreationVisible, "world map action opens visible preset popup")
importEntry.action()
equal(true, promptedPresetImport, "world map import action opens import popup")
clearedSources = nil
equal(
    true,
    initializedPresetHandlers.createVisible("Visible route"),
    "visible preset handler succeeds")
equal("Visible route", createdPresetName, "visible preset keeps submitted name")
equal(visibleExportTiles, createdPresetTiles, "visible preset uses coordinate export")
equal(2, #exportedCoords, "visible preset exports every visible marker")
equal(2, #clearedSources, "visible preset removes only exported source markers")

addedEntry = nil
readyMenu({
    {
        label = "World Map",
        verbText = "World Map",
    },
})

queriedTiles = {}
controlDown = true
shiftDown = true

submenuRegistration = nil
local orderedMenu = readyMenu()
local selectedEntry = findMenuEntry(orderedMenu, "Mark tile")
assert(selectedEntry, "unmarked tile retains its quick mark action")
equal(nil, submenuRegistration, "style submenu is reserved for marked tiles")
equal("Walk here", orderedMenu.entries[#orderedMenu.entries].label,
    "native top action keeps left-click priority")
local appendedMarkMenu = readyMenu(nil, true)
equal("Cancel", appendedMarkMenu.entries[1].label,
    "Cancel stays last when native Add appends tile actions")
equal("Mark tile", appendedMarkMenu.entries[2].label,
    "appended Mark tile remains above Cancel")
equal("Walk here", appendedMarkMenu.entries[#appendedMarkMenu.entries].label,
    "appended Mark tile does not take left-click priority")
local movedHover = { name = "tile behind menu" }
miniMenuOpen = true
cursorHover = movedHover
mousePosition = { x = 240, y = 180 }
controlDown = false
frame()
equal(hover, drawnHover, "open menu keeps the tile that created its entries highlighted")
controlDown = true
miniMenuOpen = false
callbacks.MiniMenuClosed({})
frame()
equal(nil, drawnHover, "menu selection position is not previewed as another marker")
addedEntry = nil
readyMenu()
equal(nil, addedEntry, "menu selection position does not create a follow-up tile action")
mousePosition = { x = 245, y = 180 }
frame()
equal(movedHover, drawnHover, "moving away from the menu selection restores live highlighting")
cursorHover = hover
selectedEntry.action(table.unpack(selectedEntry.args, 1, selectedEntry.args.n))
equal(source, addedSource, "mark action stores the canonical tile")
equal(0x12345678, addedMetadata.outlineColour, "mark action stores selected outline")
equal(0x0E2A4542, addedMetadata.fillColour, "mark action stores derived fill")
equal(0x12345678, rememberedColour, "mark action records its colour as recent")
equal(nil, labelledSource, "mark action does not open customization")
local markedMenu = readyMenu()
local colourEntry = findMenuEntry(markedMenu, "Customize Tile")
assert(submenuRegistration, "marked tiles expose saved styles")
equal(2, #submenuRegistration.children, "submenu contains the saved styles")
equal("<col=EE4433>Danger</col>", submenuRegistration.children[1].label,
    "style name uses its outline RGB")
equal("<col=44CC99>Escape <lt>now<gt></col>",
    submenuRegistration.children[2].label,
    "style names cannot inject colour tags into the menu")
equal("Cancel", markedMenu.entries[1].label, "Cancel remains the last menu row")
equal("Apply tile style", markedMenu.entries[2].label,
    "style submenu is immediately above Cancel")
equal("Walk here", markedMenu.entries[#markedMenu.entries].label,
    "saved styles cannot displace native left-click")
local appendedMarkedMenu = readyMenu(nil, true)
equal("Cancel", appendedMarkedMenu.entries[1].label,
    "Cancel stays last with two appended tile actions")
equal("Apply tile style", appendedMarkedMenu.entries[2].label,
    "style submenu stays above Cancel with appended tile actions")
equal("Customize Tile", appendedMarkedMenu.entries[3].label,
    "Customize Tile remains above the style submenu")
equal("Unmark tile", appendedMarkedMenu.entries[4].label,
    "Unmark tile remains above customization")
equal("Walk here", appendedMarkedMenu.entries[#appendedMarkedMenu.entries].label,
    "appended actions preserve the native left-click action")
local rebuiltMenu = readyMenu(nil, false, true)
equal("Cancel", rebuiltMenu.entries[1].label,
    "Cancel stays last when submenu registration rebuilds the menu")
equal("Apply tile style", rebuiltMenu.entries[2].label,
    "final placement survives the submenu parent's addition")
equal("Customize Tile", rebuiltMenu.entries[3].label,
    "customization stays above the style submenu after a rebuild")
equal("Unmark tile", rebuiltMenu.entries[4].label,
    "unmark stays above customization after a rebuild")
equal("Walk here", rebuiltMenu.entries[#rebuiltMenu.entries].label,
    "menu rebuild preserves native left-click priority")
local locMenu = readyMenu({
    { actionType = MiniMenuActionType.CANCEL, label = "Cancel" },
    { actionType = MiniMenuActionType.WALK, label = "Walk here" },
    { actionType = MiniMenuActionType.OP_LOC2, label = "Examine" },
    { actionType = MiniMenuActionType.OP_LOC1, label = "Open" },
})
equal("Apply tile style", locMenu.entries[2].label,
    "style submenu stays directly above Cancel on location menus")
equal("Open", locMenu.entries[#locMenu.entries].label,
    "submenu does not displace native location left-click priority")
local appendedLocMenu = readyMenu({
    { actionType = MiniMenuActionType.CANCEL, label = "Cancel" },
    { actionType = MiniMenuActionType.WALK, label = "Walk here" },
    { actionType = MiniMenuActionType.OP_LOC2, label = "Examine" },
    { actionType = MiniMenuActionType.OP_LOC1, label = "Open" },
}, true)
equal("Cancel", appendedLocMenu.entries[1].label,
    "Cancel stays last on location menus with appended tile actions")
equal("Apply tile style", appendedLocMenu.entries[2].label,
    "style submenu stays above Cancel on appended location menus")
equal("Open", appendedLocMenu.entries[#appendedLocMenu.entries].label,
    "appended tile actions preserve native location priority")
local unmarkEntry = findMenuEntry(markedMenu, "Unmark tile")
colourEntry.action(table.unpack(colourEntry.args, 1, colourEntry.args.n))
equal("Existing label", promptedInitialLabel, "customization starts from tile label")
equal(0x12345678, promptedInitialColour, "colour prompt starts from tile colour")
equal(false, promptedInitialFill, "colour prompt starts from tile fill state")
equal(
    false,
    promptedInitialOutlineCornersOnly,
    "colour prompt starts from tile corner outline state")
promptedCustomizationActions.preview("Preview label", 0xAABBCCDD, true, true)
equal(source, previewedSource, "customization preview targets the marked canonical tile")
equal("Preview label", previewedLabel, "label changes reach the live preview")
equal(0xAABBCCDD, previewedColour, "colour changes reach the live preview")
equal(true, previewedFill, "fill changes reach the live preview")
equal(true, previewedOutlineCornersOnly, "corner changes reach the live preview")
promptedCustomizationActions.cancel()
equal(source, cancelledPreviewSource, "cancel clears the marked tile preview")
equal("Existing label", existingLabel, "cancel preserves the pre-edit label")
equal(0x12345678, existingColour, "cancel preserves the pre-edit colour")
equal(false, existingFill, "cancel preserves the pre-edit fill state")
equal(false, existingOutlineCornersOnly, "cancel preserves pre-edit corners")

colourEntry.action(table.unpack(colourEntry.args, 1, colourEntry.args.n))
promptedCustomizationActions.preview("Updated label", 0x445566FF, true, true)
promptedCustomizationActions.confirm("Updated label", 0x445566FF, true, true)
equal(source, recolouredSource, "colour action targets the marked canonical tile")
equal(source, labelledSource, "customization label targets the marked canonical tile")
equal("Updated label", labelledText, "confirmed customization stores its label")
equal(0x445566FF, recolouredValue, "confirmed tile colour is stored")
equal(true, recolouredFill, "confirmed fill state is stored")
equal(true, recolouredOutlineCornersOnly, "confirmed corner outline is stored")
local dangerChild = submenuRegistration.children[1]
local escapeChild = submenuRegistration.children[2]
dangerChild.action(table.unpack(dangerChild.arguments))
equal(source, recolouredSource, "applying to a marked tile targets its source")
equal("Watch out", labelledText, "style default label overrides existing tile label")
equal(0xEE4433FF, recolouredValue, "style overrides tile outline colour")
equal(true, recolouredFill, "style explicitly overrides global fill")
equal(false, recolouredOutlineCornersOnly, "style explicitly overrides global corner mode")
equal(0xEE4433FF, rememberedColour, "applied colour is available as recent")
escapeChild.action(table.unpack(escapeChild.arguments))
equal("Watch out", labelledText, "unlabeled style preserves the customized label")
equal(0x44CC99FF, recolouredValue, "second style changes a marked tile")
unmarkEntry.action(table.unpack(unmarkEntry.args, 1, unmarkEntry.args.n))
equal(source, removedSource, "unmark action removes the canonical tile")
submenuRegistration = nil
readyMenu()
equal(nil, submenuRegistration, "an unmarked tile has no style submenu")
escapeChild.action(table.unpack(escapeChild.arguments))
equal(false, marked, "stale submenu selection cannot mark an unmarked tile")
equal(0x44CC99FF, existingColour, "stale selection cannot change tile colour")
local previousStyles = savedStyles
marked = true
savedStyles = {}
submenuRegistration = nil
readyMenu()
equal(nil, submenuRegistration, "no submenu appears after all saved styles are deleted")
local colourBeforeStaleSelection = existingColour
escapeChild.action(table.unpack(escapeChild.arguments))
equal(colourBeforeStaleSelection, existingColour,
    "a style removed while the menu is open cannot recolour a marked tile")
savedStyles = previousStyles

presetAtSource = {
    id = "preset_1",
    name = "Editable",
}
local presetMarkedMenu = readyMenu()
submenuRegistration = nil
readyMenu()
equal(nil, submenuRegistration, "preset-owned tiles must be edited in their preset")
local editPresetEntry = findMenuEntry(presetMarkedMenu, "Edit in preset")
editPresetEntry.action(table.unpack(editPresetEntry.args, 1, editPresetEntry.args.n))
equal("preset_1", startedPresetEditID, "preset tile opens its owning preset")
equal("Editable", startedPresetEditName, "preset edit overlay receives the preset name")
equal(true, editActive, "preset tile action immediately enters edit mode")
equal(true, initializedPresetHandlers.cancelEdit(), "preset tile edit can be cancelled")
equal(false, editActive, "cancel leaves preset edit mode")
presetAtSource = nil

addedEntry = nil
promptOpen = true
readyMenu()
equal(nil, addedEntry, "customization prompt suppresses tile menu entries")

promptOpen = false
equal(true, initializedPresetHandlers.startEdit("preset_1"), "preset edit handler starts")
frame()
equal("preset_1", excludedPresetID, "draw excludes the saved copy of the edited preset")
equal("Working copy", drawnTiles[hover].text, "draw includes the preset working copy")
editMarked = false
submenuRegistration = nil
local editAddMenu = readyMenu()
local editAddEntry = findMenuEntry(editAddMenu, "Add to preset")
assert(editAddEntry, "an unmarked preset tile retains its add action")
equal(nil, submenuRegistration, "an unmarked preset tile has no style submenu")
editAddEntry.action(table.unpack(editAddEntry.args, 1, editAddEntry.args.n))
equal(source, editAddedSource, "edit add targets the canonical source tile")
local editMarkedMenu = readyMenu()
assert(findMenuEntry(editMarkedMenu, "Remove from preset"),
    "marked preset tile retains its remove action")
local escapeEditChild = submenuRegistration.children[2]
escapeEditChild.action(table.unpack(escapeEditChild.arguments))
equal(source, editStyledSource, "style works on a marked preset tile")
equal("Preset label", editStyledLabel, "preset tile label survives a style change")
equal(0x44CC99FF, editStyledColour, "preset tile outline is overridden")
equal(false, editStyledFill, "preset fill is explicitly overridden")
equal(true, editStyledCorners, "preset corners are explicitly overridden")
local editRemoveMenu = readyMenu()
local editRemoveEntry = findMenuEntry(editRemoveMenu, "Remove from preset")
editRemoveEntry.action(table.unpack(editRemoveEntry.args, 1, editRemoveEntry.args.n))
equal(source, editRemovedSource, "edit remove targets the canonical source tile")
equal(true, initializedPresetHandlers.saveEdit(), "save handler commits preset edits")
equal("preset_1", updatedPresetID, "save targets the edited preset")
equal(3300, updatedPresetTiles[1].x, "save commits the working tile set")
equal(false, editActive, "successful save leaves preset edit mode")

marked = true
editMarked = false
equal(true, initializedPresetHandlers.startEdit("preset_1"), "existing direct tile can enter edit mode")
local transferEntry = findMenuEntry(readyMenu(), "Add to preset")
transferEntry.action(table.unpack(transferEntry.args, 1, transferEntry.args.n))
equal(source, pendingTransfer[1], "editor tracks the direct source for transfer")
equal(true, marked, "editing does not remove the source marker before save")
equal(true, initializedPresetHandlers.cancelEdit(), "cancel abandons the transfer")
equal(true, marked, "cancel preserves the standalone marker")
equal(0, #pendingTransfer, "cancel drops pending transfer")

equal(true, initializedPresetHandlers.startEdit("preset_1"), "editor can retry a transfer")
editMarked = false
transferEntry = findMenuEntry(readyMenu(), "Add to preset")
transferEntry.action(table.unpack(transferEntry.args, 1, transferEntry.args.n))
presetSaveSucceeds = false
clearedSources = nil
equal(false, initializedPresetHandlers.saveEdit(), "failed preset save reports failure")
equal(nil, clearedSources, "failed preset save does not remove source")
equal(true, marked, "failed save leaves standalone tile intact")
equal(true, editActive, "failed save keeps editor active for retry")
presetSaveSucceeds = true
batchRemoveSucceeds = false
local savedBeforeTransfer = editablePreset.tiles
local updatesBeforeRollback = updateCount
equal(false, initializedPresetHandlers.saveEdit(), "failed source removal reports failure")
equal(updatesBeforeRollback + 2, updateCount,
    "failed source removal restores previous preset tiles")
equal(savedBeforeTransfer, editablePreset.tiles,
    "failed transfer restores the previously saved preset content")
equal(true, marked, "failed source removal keeps original marker")
equal(true, editActive, "failed transfer keeps editor active")
batchRemoveSucceeds = true
equal(true, initializedPresetHandlers.saveEdit(), "successful edit transfers direct marker")
equal(source, clearedSources[1], "transfer removes canonical direct marker")
equal(false, marked, "deactivating saved preset cannot expose a direct duplicate")
equal(false, editActive, "successful transfer ends editing")
equal(true, initializedPresetHandlers.setActive("preset_1", false),
    "saved preset can be deactivated")
frame()
equal(nil, drawnTiles[hover],
    "deactivated preset tile does not reappear as a direct marker")

directOverlapTiles = { { level = 0, x = 3300, z = 3301 } }
clearedSources = nil
equal(true, initializedPresetHandlers.startEdit("preset_1"),
    "legacy overlap can be reviewed in the editor")
equal(true, initializedPresetHandlers.saveEdit(), "saving legacy overlap succeeds")
equal(3300, clearedSources[1].x, "matching legacy direct marker transfers on explicit save")
directOverlapTiles = { {
    level = 0, x = 3300, z = 3301, outlineColour = 0x123456FF,
} }
clearedSources = nil
equal(true, initializedPresetHandlers.startEdit("preset_1"),
    "separately customized direct marker can be reviewed")
equal(true, initializedPresetHandlers.saveEdit(), "saving distinct overlap succeeds")
equal(nil, clearedSources, "differently styled direct marker remains independent")
directOverlapTiles = nil

-- Exercise the actual label renderer through main's Draw subscription, using
-- PlayerEntity's native position/coordGrid contract (there is no coordFine).
UI.drawLabels = dofile("src/ui.lua").drawLabels
UI.renderDistance = 30 * 512
UI.labelSize = 19
UI.markerLabels = {
    {
        coord = { level = 0 },
        fine = { level = 0, position = { x = 10 * 512 + 256, y = 0, z = 10 * 512 + 256 } },
        text = "Marker label",
        config = {},
    },
}
local renderedLabel
UI.canvas = {
    xyGlobal = { x = 0, y = 0 },
    Clear = function() renderedLabel = nil end,
    AddText = function(_, x, y, _, _, text)
        renderedLabel = { x = x, y = y, text = text }
    end,
}
local screenX = 150
ScreenConvert.CoordFineToScreen = function() return { x = screenX, y = 80 } end
callbacks.Draw()
equal("Marker label", renderedLabel and renderedLabel.text, "native player properties allow label rendering")
screenX = 175
callbacks.Draw()
equal(75, renderedLabel.x, "frame projection tracks camera movement")
playerCoord.level = 1
callbacks.Draw()
equal(nil, renderedLabel, "changing the player's floor clears the label")
playerCoord.level = 0
playerPosition.x = playerPosition.x + 30 * 512 + 256
callbacks.Draw()
equal("Marker label", renderedLabel and renderedLabel.text, "label renders at the fine-position distance boundary")
playerPosition.x = playerPosition.x + 1
callbacks.Draw()
equal(nil, renderedLabel, "sub-tile player movement past the boundary hides the label")

print("test_interaction: ok")

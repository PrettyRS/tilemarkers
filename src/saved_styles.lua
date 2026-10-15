local Styles = require("src/styles")

local STORAGE_KEY = "tileSavedStyles"
local STORAGE_VERSION = 1
local MAX_STYLES = 10
local MAX_NAME_LENGTH = 32
local MAX_LABEL_LENGTH = 32

local function trim(value)
    if type(value) ~= "string" then return "" end
    return value:match("^%s*(.-)%s*$") or ""
end

local function normalizedLabel(value)
    local label = trim(trim(value):sub(1, MAX_LABEL_LENGTH))
    return label ~= "" and label or nil
end

local function copy(record)
    return {
        id = record.id,
        name = record.name,
        label = record.label,
        outlineColour = record.outlineColour,
        fillColour = record.fillColour,
        fill = record.fill,
        outlineCornersOnly = record.outlineCornersOnly,
    }
end

local function record(id, name, colour, fill, corners, label)
    local style = Styles.fromColour(colour, fill, corners)
    return {
        id = id,
        name = name,
        label = label,
        outlineColour = style.outlineColour,
        fillColour = style.fillColour,
        fill = style.fill,
        outlineCornersOnly = style.outlineCornersOnly,
    }
end

local function defaults()
    return {
        record("style_1", "Standard", 0xC864FFFF, false, false),
        record("style_2", "Danger", 0xFF4444FF, true, true),
        record("style_3", "Safe", 0x42D67AFF, true, false),
        record("style_4", "Surge", 0x5CBEFFFF, false, true, "Surge"),
        record("style_5", "Dive", 0xFBEF1EFF, false, true, "Dive"),
        record("style_6", "Escape", 0x3E7031FF, false, true, "Escape"),
    }
end

local function savedColour(value)
    local numeric = tonumber(value)
    if type(value) == "number" or type(value) == "string" then
        if numeric ~= nil and numeric == numeric
            and numeric >= -0x80000000 and numeric <= 0xFFFFFFFF then
            return value
        end
        if type(value) == "string" and (value:match("^#?%x%x%x%x%x%x%x%x$")
            or value:match("^0[xX]%x%x%x%x%x%x%x%x$")) then
            return value
        end
    end
    return nil
end

local function nextId(value)
    local number = tonumber(value)
    if number == nil or number < 1 or number > 0x1FFFFFFFFFFFFE
        or number ~= number then
        return 1
    end
    return math.floor(number)
end

local function normalize(data)
    if data == nil then return { nextId = 7, styles = defaults() } end
    if type(data) ~= "table" then return { nextId = 1, styles = {} } end

    local normalized = { nextId = nextId(data.nextId), styles = {} }
    local rawStyles = type(data.styles) == "table" and data.styles or {}
    local indexes = {}
    for index in pairs(rawStyles) do
        if type(index) == "number" and index >= 1 and index % 1 == 0 then
            indexes[#indexes + 1] = index
        end
    end
    table.sort(indexes)
    local reserved = {}
    for _, index in ipairs(indexes) do
        local raw = rawStyles[index]
        if type(raw) == "table" then
            local id = trim(raw.id)
            if id ~= "" then
                reserved[id] = true
                local number = tonumber(id:match("^style_(%d+)$"))
                if number ~= nil and number <= 0x1FFFFFFFFFFFFE then
                    normalized.nextId = math.max(normalized.nextId, number + 1)
                end
            end
        end
    end

    local seenIds, seenNames = {}, {}
    for _, index in ipairs(indexes) do
        local raw = rawStyles[index]
        if type(raw) == "table" and #normalized.styles < MAX_STYLES then
            local name = trim(raw.name):sub(1, MAX_NAME_LENGTH)
            local id = trim(raw.id)
            if name ~= "" and not seenNames[name:lower()] and not seenIds[id] then
                if id == "" then
                    repeat
                        id = "style_" .. tostring(normalized.nextId)
                        normalized.nextId = normalized.nextId + 1
                    until not reserved[id]
                    reserved[id] = true
                end
                local style = Styles.normalize({
                    outlineColour = savedColour(raw.outlineColour),
                    fillColour = savedColour(raw.fillColour),
                    fill = raw.fill,
                    outlineCornersOnly = raw.outlineCornersOnly,
                })
                normalized.styles[#normalized.styles + 1] = {
                    id = id,
                    name = name,
                    outlineColour = style.outlineColour,
                    label = normalizedLabel(raw.label),
                    fillColour = style.fillColour,
                    fill = style.fill,
                    outlineCornersOnly = style.outlineCornersOnly,
                }
                seenIds[id] = true
                seenNames[name:lower()] = true
            end
        end
    end
    return normalized
end

local function storageData(data)
    local stored = {
        version = STORAGE_VERSION,
        nextId = data.nextId,
        styles = {},
    }
    for index, style in ipairs(data.styles) do
        stored.styles[index] = {
            id = style.id,
            name = style.name,
            label = style.label,
            outlineColour = Styles.encodeColour(style.outlineColour),
            fillColour = Styles.encodeColour(style.fillColour),
            fill = style.fill,
            outlineCornersOnly = style.outlineCornersOnly,
        }
    end
    return stored
end

local function save(data)
    return PersistentDB:SetStructuredData(STORAGE_KEY, storageData(data)) == true
end

local stored = PersistentDB:GetStructuredData(STORAGE_KEY)
local data = normalize(stored)
local SavedStyles = { MAX_STYLES = MAX_STYLES }


function SavedStyles:list()
    local result = {}
    for index, style in ipairs(data.styles) do
        result[index] = copy(style)
    end
    return result
end

function SavedStyles:get(id)
    for _, style in ipairs(data.styles) do
        if style.id == id then return copy(style) end
    end
    return nil
end

local function validName(styles, name, exceptId)
    name = trim(name)
    if name == "" then return nil, "Enter a style name." end
    if #name > MAX_NAME_LENGTH then
        return nil, "Style names must be 32 characters or fewer."
    end
    for _, style in ipairs(styles) do
        if style.id ~= exceptId and style.name:lower() == name:lower() then
            return nil, "A style with that name already exists."
        end
    end
    return name
end

local function validLabel(label)
    if label ~= nil and type(label) ~= "string" then
        return nil, "Style labels must be text."
    end
    label = trim(label)
    if #label > MAX_LABEL_LENGTH then
        return nil, "Style labels must be 32 characters or fewer."
    end
    return label ~= "" and label or nil
end


function SavedStyles:create(name, colour, fill, corners, label)
    local styles = data.styles
    local normalizedName, message = validName(styles, name)
    if normalizedName == nil then return false, message end
    if #styles >= MAX_STYLES then return false, "You can save at most 10 styles." end
    local normalizedLabelValue, labelMessage = validLabel(label)
    if labelMessage ~= nil then return false, labelMessage end

    local id = "style_" .. tostring(data.nextId)
    local created = record(id, normalizedName, colour, fill, corners, normalizedLabelValue)
    local changed = { nextId = data.nextId + 1, styles = {} }
    for index, style in ipairs(styles) do changed.styles[index] = style end
    changed.styles[#changed.styles + 1] = created
    if not save(changed) then return false, "Could not save the style." end
    data = changed
    return true, copy(created)
end

function SavedStyles:update(id, name, colour, fill, corners, label)
    local styles = data.styles
    local selected
    for index, style in ipairs(styles) do
        if style.id == id then selected = index; break end
    end
    if selected == nil then return false, "No style selected." end
    local normalizedName, message = validName(styles, name, id)
    if normalizedName == nil then return false, message end
    local normalizedLabelValue, labelMessage = validLabel(label)
    if labelMessage ~= nil then return false, labelMessage end

    local updated = record(id, normalizedName, colour, fill, corners, normalizedLabelValue)
    local changed = { nextId = data.nextId, styles = {} }
    for index, style in ipairs(styles) do changed.styles[index] = style end
    changed.styles[selected] = updated
    if not save(changed) then return false, "Could not save the style." end
    data = changed
    return true, copy(updated)
end

function SavedStyles:delete(id)
    local styles = data.styles
    local changed = { nextId = data.nextId, styles = {} }
    local found = false
    for _, style in ipairs(styles) do
        if style.id == id then
            found = true
        else
            changed.styles[#changed.styles + 1] = style
        end
    end
    if not found then return false, "No style selected." end
    if not save(changed) then return false, "Could not delete the style." end
    data = changed
    return true, "Style deleted."
end

return SavedStyles

package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local function clone(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = clone(child) end
    return result
end

local stored
local saveSucceeds = true
local keys = {}
PersistentDB = {
    GetStructuredData = function(_, key)
        keys[#keys + 1] = key
        return clone(stored)
    end,
    SetStructuredData = function(_, key, value)
        equal(keys[1], key, "saved styles use their own storage key")
        if not saveSucceeds then return false end
        stored = clone(value)
        return true
    end,
}

local function reload()
    package.loaded["src/saved_styles"] = nil
    return require("src/saved_styles")
end

local Styles = require("src/styles")
local SavedStyles = reload()
equal(10, SavedStyles.MAX_STYLES, "style limit")
equal(6, #SavedStyles:list(), "first use seeds six styles")
equal(nil, stored, "enabling the plugin must not write to the client database")
equal(6, #reload():list(), "unsaved starters remain available on reload")
equal("Standard", SavedStyles:list()[1].name, "default ordering")
local distinct = {}
for _, style in ipairs(SavedStyles:list()) do
    equal(0xFF, style.outlineColour & 0xFF, "starter colour is opaque RGBA")
    assert(not distinct[style.outlineColour], "starter colours must be distinct")
    distinct[style.outlineColour] = true
    equal(Styles.fromColour(style.outlineColour).fillColour, style.fillColour,
        "starter fill derives from its outline")
end

local list = SavedStyles:list()
list[1].name = "Modified copy"
list[1] = nil
local got = SavedStyles:get("style_1")
local firstOutline = got.outlineColour
got.outlineColour = 0
equal("Standard", SavedStyles:get("style_1").name, "list does not expose live data")
equal(firstOutline, SavedStyles:get("style_1").outlineColour,
    "get does not expose live data")

local ok, edited = SavedStyles:update(
    "style_1", "  Plain  ", 0x12345678, true, true, "  Caution  ")
equal(true, ok, "editing a starter style")
equal("Plain", edited.name, "edited name is trimmed")
equal("Caution", edited.label, "default label is trimmed")
equal(0x12345678, edited.outlineColour, "alpha is retained")
equal(Styles.fromColour(0x12345678).fillColour, edited.fillColour,
    "edited fill derives from outline")
equal(true, edited.fill, "edited fill option")
equal(true, edited.outlineCornersOnly, "edited corners option")
equal(1, stored.version, "editing first writes the collection")
equal(7, stored.nextId, "starter IDs remain stable after the first edit")
equal("12345678", stored.styles[1].outlineColour, "outline stored as eight hex digits")
equal("Caution", stored.styles[1].label, "default label is stored")
equal(Styles.encodeColour(edited.fillColour), stored.styles[1].fillColour,
    "fill stored as eight hex digits")
equal("Plain", reload():get("style_1").name, "edited starter does not reseed")
equal("Caution", reload():get("style_1").label,
    "default label survives reloading the collection")
ok, edited = SavedStyles:update("style_1", "Plain", 0x12345678, true, true, "")
equal(true, ok, "empty default label can be saved")
equal(nil, edited.label, "clearing a label removes it from the style")
equal(nil, reload():get("style_1").label, "cleared label stays cleared")
equal(false, SavedStyles:update("style_1", "Plain", 0x12345678, true,
    true, string.rep("X", 33)), "overlong label is rejected")
equal(nil, SavedStyles:get("style_1").label,
    "rejected label does not change the saved style")

SavedStyles = reload()
equal(false, SavedStyles:create(" pLaIn ", 0xAABBCCFF),
    "case-insensitive duplicate is rejected")
equal(false, SavedStyles:create("   ", 0xAABBCCFF), "empty name is rejected")
equal(false, SavedStyles:create(string.rep("X", 33), 0xAABBCCFF),
    "overlong name is rejected")
equal(false, SavedStyles:update("style_2", "plain", 0xAABBCCFF),
    "update rejects duplicate names")
equal(false, SavedStyles:delete("style_999"), "missing style cannot be deleted")
equal(nil, SavedStyles:get("style_999"), "missing style cannot be retrieved")

local original = SavedStyles:get("style_2")
saveSucceeds = false
equal(false, SavedStyles:update("style_2", "Changed", 0x01020304),
    "failed edit reports failure")
equal(original.name, SavedStyles:get("style_2").name,
    "failed edit retains in-memory style")
equal(false, SavedStyles:delete("style_2"), "failed delete reports failure")
equal(original.name, SavedStyles:get("style_2").name,
    "failed delete retains in-memory style")
equal(false, SavedStyles:create("New", 0x01020304),
    "failed create reports failure")
equal(6, #SavedStyles:list(), "failed create does not change list")
saveSucceeds = true
ok, edited = SavedStyles:create("New", 0x01020304, false, false, "  Jump here  ")
equal(true, ok, "create after failed writes")
equal("style_7", edited.id, "failed creates do not consume IDs")
equal(0x01020304, SavedStyles:get(edited.id).outlineColour,
    "create retains RGBA alpha")
equal("Jump here", reload():get(edited.id).label,
    "created default labels survive reload")

for i = 8, 10 do
    ok, edited = SavedStyles:create("Added " .. i, 0x112233FF)
    equal(true, ok, "style can be created up to the limit")
    equal("style_" .. i, edited.id, "IDs remain ordered")
end
equal(10, #SavedStyles:list(), "maximum of ten styles")
equal(false, SavedStyles:create("Too many", 0x112233FF),
    "style number eleven is rejected")

equal(true, SavedStyles:delete("style_1"), "starter style can be deleted")
equal(nil, SavedStyles:get("style_1"), "deleted starter is absent")
SavedStyles = reload()
equal(nil, SavedStyles:get("style_1"), "deleted starter stays deleted on reload")
equal("style_2", SavedStyles:list()[1].id, "deletion preserves remaining order")
ok, edited = SavedStyles:create("Replacement", 0x112233FF)
equal(true, ok, "deletion makes room for a replacement")
equal("style_11", edited.id, "deleted IDs are not reused")

for _, style in ipairs(SavedStyles:list()) do
    equal(true, SavedStyles:delete(style.id), "all styles can be deleted")
end
equal(0, #reload():list(), "an intentionally empty collection never reseeds")
equal(12, stored.nextId, "empty collection keeps next ID")

stored = {
    version = 1,
    nextId = 1,
    styles = {
        { id = "style_9", name = "  Repair  ", outlineColour = "DEADBEEF",
            label = string.rep("L", 40), fill = true, outlineCornersOnly = true },
        { id = "style_9", name = "Duplicate ID" },
        { id = "style_2", name = "repair" },
        { name = "Valid", outlineColour = "BAD DATA" },
        false,
        { id = "style_4", name = "" },
    },
}
SavedStyles = reload()
equal(2, #SavedStyles:list(), "malformed and duplicate records are skipped")
equal("style_9", SavedStyles:list()[1].id, "valid record keeps its ID")
equal("Repair", SavedStyles:list()[1].name, "stored name is trimmed")
equal(string.rep("L", 32), SavedStyles:list()[1].label,
    "oversized persisted labels are safely normalized")
equal(0xDEADBEEF, SavedStyles:list()[1].outlineColour, "stored colour decodes")
equal(Styles.fromColour(0xDEADBEEF).fillColour,
    SavedStyles:list()[1].fillColour, "missing stored fill derives safely")
equal("style_10", SavedStyles:list()[2].id, "missing ID is assigned above existing IDs")
equal(Styles.DEFAULT_OUTLINE, SavedStyles:list()[2].outlineColour,
    "invalid stored colour uses default outline")
ok, edited = SavedStyles:create("After repair", 0xAABBCCFF)
equal(true, ok, "normalized collection remains editable")
equal("style_11", edited.id, "new ID does not collide with normalized IDs")

stored = {
    version = 1,
    nextId = 4,
    styles = {
        [1] = false,
        [3] = { id = "style_3", name = "Sparse",
            outlineColour = 1e300, fillColour = -1e300 },
    },
}
SavedStyles = reload()
equal(1, #SavedStyles:list(), "later records survive missing array entries")
equal("style_3", SavedStyles:list()[1].id, "sparse record retains its ID")
equal(Styles.DEFAULT_OUTLINE, SavedStyles:list()[1].outlineColour,
    "out-of-range stored outline uses default")
equal(Styles.DEFAULT_FILL, SavedStyles:list()[1].fillColour,
    "out-of-range stored fill derives from default outline")

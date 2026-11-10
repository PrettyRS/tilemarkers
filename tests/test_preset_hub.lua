package.path = './?.lua;' .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format('%s: expected %s, got %s',
        context, tostring(expected), tostring(actual)))
end

local saveSucceeds = true
PersistentDB = {
    GetStructuredData = function() return nil end,
    SetStructuredData = function() return saveSucceeds end,
}
local Codec = require('src/preset_codec')
local Presets = require('src/presets')
local Hub = require('src/preset_hub')
ui = { AlignMode = { CENTRE = 1 }, Rectangle = {} }

local function control(options)
    local widget = { options = options, content = {}, texts = {}, buttons = {}, scrollY = 0 }
    widget.root = widget
    function widget:AddText(value)
        local text = { content = value.text, y = #self.texts * 24, height = value.height }
        self.texts[#self.texts + 1] = text
        return text
    end
    function widget:AddSimpleButton(label, action, buttonOptions)
        local button = { click = action, disabled = buttonOptions.disabled == true }
        function button:SetDisabled(disabled) self.disabled = disabled end
        self.buttons[#self.buttons + 1] = button
        return button
    end
    widget.AddSpriteButton = widget.AddSimpleButton
    function widget:AddTextField(fieldOptions) return { options = fieldOptions } end
    function widget:AddComboBox(comboOptions)
        return { options = comboOptions, SetEntries = function() end }
    end
    function widget:SetScrollable() end
    function widget:SetScrollPosition(value) self.scrollY = value end
    function widget:Show() end
    function widget:Destroy() self.root = nil end
    function widget:Close()
        if self.options.onClose then self.options.onClose() end
        self:Destroy()
    end
    return widget
end
local pretty = {
    Window = { new = function(_, options) return control(options) end },
    SimpleView = { new = function(_, options) return control(options) end },
    NewComponent = function()
        return { SetPos = function() end, SetSize = function() end, MoveToBack = function() end }
    end,
}

local token = assert(Codec.encode('Anachronia agility', { { level = 0, x = 3200, z = 3201 } }))
local function row(author, page)
    return { title = 'Anachronia agility', author = author, page = page or 'User:Wiki/Tilemarkers',
        token = token, tags = { 'skilling', 'agility' } }
end
local catalog = { loaded = true, loading = false, refreshAvailable = true,
    rows = { row('Jome'), row('Voijehna (RS Reddit)') } }
function catalog:open(callback) self.listener = callback; callback() end
function catalog:detach() self.listener = nil end
function catalog:refresh(callback)
    local fresh = {}
    -- Refresh can return new Lua records in a different order.
    for index = #self.rows, 1, -1 do
        local previous = self.rows[index]
        fresh[#fresh + 1] = {
            title = previous.title, author = previous.author, page = previous.page, token = previous.token,
            tags = previous.tags,
        }
    end
    self.rows = fresh
    self.listener = callback
    callback()
    return true
end
local hub = Hub.new(pretty, catalog, function(source) return Presets:import(source) end)
assert(hub:open({}))
local function buttonFor(author)
    for index, button in ipairs(hub.results.buttons) do
        if hub.results.texts[index * 2].content == 'By ' .. author then return button end
    end
    error('No visible submission for ' .. author)
end

local first = buttonFor('Jome')
hub.results:SetScrollPosition(56)
first.click()
equal(1, #Presets:list(), 'first submission is saved')
equal(true, buttonFor('Jome').disabled, 'imported submission is disabled')
equal(false, buttonFor('Voijehna (RS Reddit)').disabled,
    'another author with the same name and token remains importable')
equal(56, hub.results.scrollY, 'import retains the browsing position')
first.click()
equal(1, #Presets:list(), 'stale action cannot import the same submission twice')

hub.refreshButton.click()
equal(true, buttonFor('Jome').disabled, 'refresh preserves the imported submission identity')
equal(false, buttonFor('Voijehna (RS Reddit)').disabled,
    'refresh does not merge independent submissions')
local agilityTag
for id, tag in pairs(hub.tagIDs) do
    if tag == 'agility' then agilityTag = id end
end
hub.tagCombo.options.onChange(nil, agilityTag)
equal(2, #hub.results.buttons, 'a tag includes matching submissions from different authors')
buttonFor('Voijehna (RS Reddit)').click()
equal(2, #Presets:list(), 'second submission can be independently saved')
local saved = Presets:list()
assert(saved[1].id ~= saved[2].id, 'independent imports have distinct saved preset IDs')
assert(Presets:isActive(saved[1].id) and Presets:isActive(saved[2].id), 'both imported presets are enabled')
hub.tagCombo.options.onChange(nil, 0)
equal(true, buttonFor('Jome').disabled, 'clearing the filter retains the first import')
equal(true, buttonFor('Voijehna (RS Reddit)').disabled, 'clearing the filter retains the second import')

local stale = buttonFor('Jome')
hub:close()
hub:open({})
equal(false, buttonFor('Jome').disabled, 'a new visit resets per-visit import state')
stale.click()
equal(2, #Presets:list(), 'a closed window action cannot import into a new visit')
saveSucceeds = false
buttonFor('Jome').click()
equal(2, #Presets:list(), 'failed save does not keep a preset')
equal(false, buttonFor('Jome').disabled, 'failed import remains retryable')
equal(false, buttonFor('Voijehna (RS Reddit)').disabled, 'failed import does not change another submission')
saveSucceeds = true
buttonFor('Jome').click()
equal(3, #Presets:list(), 'failed submission can be successfully retried')
equal(false, buttonFor('Voijehna (RS Reddit)').disabled, 'retry still leaves the other submission independent')
hub:close()

catalog.rows = { row('Same author', 'User:One'), row('Same author', 'User:Two') }
hub:open({})
hub.results.buttons[1].click()
equal(4, #Presets:list(), 'submission from a separate source page is saved')
equal(true, hub.results.buttons[1].disabled, 'selected source page is marked imported')
equal(false, hub.results.buttons[2].disabled, 'identical name, author and token from another page remain independent')
hub.results.buttons[2].click()
equal(5, #Presets:list(), 'both source pages are independently importable')
hub:shutdown()

-- Tag membership composes with search and pagination; untagged presets stay
-- visible in the unfiltered catalogue.
catalog.rows = {}
for index = 1, 31 do
    catalog.rows[index] = {
        title = string.format('Route %02d', index), author = index % 2 == 0 and 'Alice' or 'Bob',
        page = 'User:Tag presets', token = token,
        tags = index <= 26 and { 'skilling', index % 2 == 0 and 'agility' or 'crafting' } or {},
    }
end
local tagHub = Hub.new(pretty, catalog, function(source) return Presets:import(source) end)
tagHub:open({})
local function selectTag(name)
    if name == nil then
        tagHub.tagCombo.options.onChange(nil, 0)
        return
    end
    for id, tag in pairs(tagHub.tagIDs) do
        if tag == name then
            tagHub.tagCombo.options.onChange(nil, id)
            return
        end
    end
    error('Missing tag: ' .. name)
end
equal(25, #tagHub.results.buttons, 'the unfiltered first page remains bounded')
tagHub.nextButton.click()
equal(6, #tagHub.results.buttons, 'unfiltered catalogue includes five untagged entries on its last page')
selectTag('agility')
equal(1, tagHub.page, 'changing tags returns to the first page')
equal(13, #tagHub.results.buttons, 'membership selects exactly the agility entries')
for index = 1, 13 do
    equal(string.format('Route %02d', index * 2), tagHub.results.texts[index * 2 - 1].content,
        'tag results exclude crafting and untagged entries')
end
tagHub.searchField.options.onChange(nil, nil, 'route 02')
equal(1, #tagHub.results.buttons, 'text search narrows the selected tag')
tagHub.searchField.options.onChange(nil, nil, 'crafting')
equal(0, #tagHub.results.buttons, 'search does not bypass tag membership')
tagHub.searchField.options.onChange(nil, nil, 'SKILLING')
equal(13, #tagHub.results.buttons, 'text search also matches tags without case sensitivity')
tagHub.searchField.options.onChange(nil, nil, '')
selectTag('skilling')
equal(25, #tagHub.results.buttons, 'a larger tag is paginated')
tagHub.nextButton.click()
equal(1, #tagHub.results.buttons, 'tag pagination has the correct final remainder')
tagHub.refreshButton.click()
equal('skilling', tagHub.tag, 'refresh retains a selected tag which still exists')
equal(2, tagHub.page, 'refresh retains a valid page within the selected tag')
equal(1, #tagHub.results.buttons, 'refresh does not mix other tags into the final page')
selectTag('agility')
local importedTitle = tagHub.results.texts[1].content
tagHub.results.buttons[1].click()
equal(true, tagHub.results.buttons[1].disabled, 'tagged entry is marked imported')
for _, entry in ipairs(catalog.rows) do
    for _, tag in ipairs(entry.tags) do
        if tag == 'agility' then entry.tags = { 'pvm' }; break end
    end
end
tagHub.refreshButton.click()
equal(nil, tagHub.tag, 'a removed tag falls back to the full catalogue')
equal(1, tagHub.page, 'removing the selected tag resets pagination')
equal(25, #tagHub.results.buttons, 'fallback restores the full first page')
local retainedImport = false
for index, button in ipairs(tagHub.results.buttons) do
    if tagHub.results.texts[index * 2 - 1].content == importedTitle then
        retainedImport = button.disabled
    end
end
equal(true, retainedImport, 'editing wiki tags does not change submission import identity')
selectTag(nil)
tagHub:shutdown()

-- Use the real catalogue to exercise UI readiness across request transitions.
local logic
Event = { Logic = {
    Subscribe = function(_, callback) logic = callback end,
    Unsubscribe = function() logic = nil end,
} }
PluginPermissions = { httpAccess = 1 }
Plugin = { urls = { wiki = 'https://runescape.wiki' }, HasPermission = function() return true end }
local requests = {}
HTTPRequest = { new = function()
    local request = {}
    function request:AddHeader() end
    function request:Get(callback) self.callback = callback end
    function request:Cancel() end
    requests[#requests + 1] = request
    return request
end }
local networkCatalog = require('src/preset_catalog')
logic({ logicTick = 100 })
local networkHub = Hub.new(pretty, networkCatalog, function(source) return Presets:import(source) end)
networkHub:open({})
equal(true, networkHub.refreshButton.disabled, 'initial fetch disables Refresh')
equal(1, #requests, 'opening starts one request')
requests[1].successful = true
requests[1].responseCode = 200
requests[1].data = string.format(
    '{"bucket":[{"title":"Route","author":"Author","page_name":"User:Wiki","token":"%s"}]}', token)
requests[1].callback(requests[1])
equal(true, networkHub.refreshButton.disabled, 'completed fetch remains disabled during cooldown')
local view = networkHub.results
view:SetScrollPosition(112)
networkHub.refreshButton.click()
local message = networkCatalog.error
local _, messageEnd = networkHub.statusText.content:find(message, 1, true)
assert(messageEnd and not networkHub.statusText.content:find(message, messageEnd + 1, true),
    'the same catalogue error and refresh feedback must be displayed only once')
equal(1, #requests, 'stale refresh action cannot bypass cooldown')
logic({ logicTick = 15099 })
equal(true, networkHub.refreshButton.disabled, 'Refresh stays disabled until the final cooldown tick')
logic({ logicTick = 15100 })
equal(false, networkHub.refreshButton.disabled, 'Refresh re-enables at exactly five minutes')
equal(nil, networkCatalog.error, 'expired cooldown warning is cleared')
equal(nil, networkHub.feedback, 'expired refresh feedback is cleared')
equal(view, networkHub.results, 'cooldown expiry does not rebuild the list')
equal(112, networkHub.results.scrollY, 'cooldown expiry preserves browsing position')
equal(1, #requests, 'cooldown expiry never starts an automatic request')
logic({ logicTick = 15101 })
equal(1, #requests, 'subsequent ticks never poll the wiki')

networkHub.refreshButton.click()
equal(2, #requests, 'enabled Refresh starts a manual request')
equal(true, networkHub.refreshButton.disabled, 'pending manual request disables Refresh')
logic({ logicTick = 30101 })
equal(true, networkHub.refreshButton.disabled, 'a pending request stays disabled even after five minutes')
requests[2].successful = false
requests[2].responseCode = 503
requests[2].callback(requests[2])
equal(false, networkHub.refreshButton.disabled, 'long request completion re-enables Refresh after its interval')
equal(2, #requests, 'long request completion does not automatically retry')
networkHub.refreshButton.click()
equal(3, #requests, 'a long failed request can be manually retried')
requests[3].successful = false
requests[3].responseCode = 503
requests[3].callback(requests[3])
equal(true, networkHub.refreshButton.disabled, 'quick failure still consumes the five-minute interval')
local transportError = networkCatalog.error
networkHub.refreshButton.click()
assert(networkHub.statusText.content:find(transportError, 1, true),
    'a distinct transport error remains visible alongside cooldown feedback')
logic({ logicTick = 45101 })
equal(false, networkHub.refreshButton.disabled, 'failed requests also unlock after their interval')
equal(transportError, networkCatalog.error, 'cooldown expiry must not erase a distinct request failure')
equal(nil, networkHub.feedback, 'cooldown feedback must not outlive the interval')
assert(networkHub.statusText.content:find(transportError, 1, true), 'request failure remains visible')
equal(3, #requests, 'failed request cooldown does not automatically retry')

local savedBefore = #Presets:list()
networkHub.results.buttons[1].click()
equal(savedBefore + 1, #Presets:list(), 'cached presets remain importable after a refresh failure')
assert(networkHub.statusText.content:find(networkHub.feedback, 1, true)
    and networkHub.statusText.content:find(transportError, 1, true),
    'distinct import feedback and request failure must both remain visible')
networkHub.refreshButton.click()
equal(4, #requests, 'later manual refresh starts another request')
requests[4].successful = true
requests[4].responseCode = 200
requests[4].data = '{"bucket":[]}'
requests[4].callback(requests[4])
networkHub:close()
logic({ logicTick = 60101 })
equal(4, #requests, 'cooldown expiry while closed never fetches the wiki')
networkHub:open({})
equal(false, networkHub.refreshButton.disabled, 'reopening reflects elapsed cooldown')
equal(4, #requests, 'reopening loaded data still uses the cache')
networkHub:shutdown()
networkCatalog:shutdown()
equal(nil, logic, 'shutdown releases the cooldown subscription')

print('test_preset_hub: ok')

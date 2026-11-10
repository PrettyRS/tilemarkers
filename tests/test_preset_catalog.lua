package.path = "./?.lua;" .. package.path

local function equal(expected, actual, context)
    assert(expected == actual, string.format(
        "%s: expected %s, got %s", context, tostring(expected), tostring(actual)))
end

local subscribed
Event = { Logic = {
    Subscribe = function(_, callback) subscribed = callback end,
    Unsubscribe = function() subscribed = nil end,
} }
PluginPermissions = { httpAccess = "httpAccess" }
local permitted = true
Plugin = {
    urls = { wiki = "https://runescape.wiki" },
    HasPermission = function() return permitted end,
}

local requests = {}
local constructorError, getError, headerError
HTTPRequest = {
    new = function(base, path)
        if constructorError then error("construction failed") end
        local instance = { path = path, cancelled = false }
        function instance:AddHeader()
            if headerError then error("header rejected") end
        end
        function instance:Get(callback)
            if getError then error("GET failed") end
            self.callback = callback
        end
        function instance:Cancel() self.cancelled = true end
        requests[#requests + 1] = instance
        return instance
    end,
}

local function tick(value)
    assert(subscribed, "logic event remains registered")
    subscribed({ logicTick = value })
end

local function answer(request, body, status)
    request.successful = status == nil or status >= 200 and status < 300
    request.responseCode = status or 200
    request.data = body
    request.callback(request)
end

local function load()
    requests = {}
    constructorError, getError, headerError = nil, nil, nil
    permitted = true
    package.loaded["src/preset_catalog"] = nil
    local catalog = require("src/preset_catalog")
    equal(0, #requests, "loading catalog never fetches the wiki")
    return catalog
end

local sample = [[{"bucket":[{"page_name":"User:Tester/Tilemarkers","title":"Agility \uD83D\uDE80","author":"A\\B","token":"TM2:example","tags":[" SKILLING ","agility","SKILLING","",false,null,42,"  "]},{"title":42,"author":"Tester","page_name":"Bad","token":"TM2:bad"}]}]]
local catalog = load()
tick(37)
permitted = false
local updates = 0
catalog:open(function() updates = updates + 1 end)
equal(0, #requests, "permission refusal does not start HTTP")
assert(catalog.error:find("permission"), "permission refusal is visible")
local refused, permissionReason = catalog:refresh()
equal(false, refused, "refresh reports denied permission")
assert(permissionReason:find("permission"), "permission refusal includes reason")
permitted = true
local started = catalog:refresh()
equal(true, started, "refresh starts once permission granted")
equal(1, #requests, "permission refusal does not consume the request interval")
equal(true, catalog.loading, "request pending")
local oldUpdates = updates
local newUpdates = 0
catalog:open(function() newUpdates = newUpdates + 1 end)
local pending, pendingReason = catalog:refresh()
equal(false, pending, "single flight rejects concurrent refresh")
assert(pendingReason:find("in progress"), "concurrent refresh gives visible reason")
answer(requests[1], sample)
equal(oldUpdates, updates, "opening replaces old subscriber")
equal(true, catalog.loaded, "valid wiki response loads")
equal(false, catalog.loading, "request completed")
equal(1, #catalog.rows, "malformed row is skipped")
equal("Agility 🚀", catalog.rows[1].title, "surrogate pairs decode to UTF-8")
equal("A\\B", catalog.rows[1].author, "escaped backslash is preserved")
local tags = {}
for _, tag in ipairs(catalog.rows[1].tags) do tags[tag] = true end
equal(2, #catalog.rows[1].tags, "tag normalization removes blanks, invalid members and duplicates")
assert(tags.skilling and tags.agility, "whitespace and case variants match the same filter tags")
assert(catalog.error:find("Skipped 1"), "partial bad data remains visible")
local initialNotifications = newUpdates
catalog:detach()
catalog:open(function() newUpdates = newUpdates + 1 end)
equal(initialNotifications + 1, newUpdates, "cached catalog notifies a reopened view")
equal(1, #requests, "reopen uses cache without HTTP")
local refreshed, cooldown = catalog:refresh()
equal(false, refreshed, "throttled refresh reports suppression")
assert(cooldown:find("five minutes"), "refresh returns a visible cooldown reason")
equal(1, #requests, "refresh within interval is throttled")
tick(15036)
catalog:refresh()
equal(1, #requests, "interval is at least 15,000 ticks")
tick(15037)
equal(true, catalog:refresh(), "refresh reports a request started")
equal(2, #requests, "explicit refresh starts at exact interval")
requests[2].timedOut = true
requests[2].successful = false
requests[2].callback(requests[2])
equal(true, catalog.loaded, "timeout retains previously loaded status")
equal(1, #catalog.rows, "timeout retains previously loaded rows")
assert(catalog.error:find("timed out"), "timeout is visible")
catalog:open(function() end)
equal(2, #requests, "reopen does not retry a failed refresh")
catalog:refresh()
equal(2, #requests, "failed refresh does not auto-bypass cooldown")
tick(30037)
catalog:refresh()
answer(requests[3], [[{"bucket":[]}]])
equal(0, #catalog.rows, "valid empty array clears prior rows")
equal(nil, catalog.error, "successful refresh clears previous error")
tick(45037)
catalog:refresh()
answer(requests[4], [[{"bucket":{}}]])
equal(0, #catalog.rows, "valid empty object also means empty bucket")
catalog:shutdown()
equal(nil, subscribed, "shutdown unsubscribes tick handler")

-- Failures and malformed responses are explicit and never retry in the background.
for _, case in ipairs({
    { body = [[{"error":"Bucket unavailable"}]], fragment = "Bucket unavailable" },
    { body = [[{"bucket":{"wrong":"shape"}}]], fragment = "malformed preset bucket" },
    { body = [[{"bucket":[{"title":true}]}]], fragment = "malformed preset entries" },
    { body = [[{"unexpected":[]}]], fragment = "no preset bucket" },
    { body = [[{"bucket":null}]], fragment = "no preset bucket" },
    { body = [[{"bucket":[1,]}]], fragment = "Could not decode" },
    { body = [[{"bucket":[],"other":"\uD83D"}]], fragment = "Could not decode" },
    { body = [[{"bucket":[{"title":"a
b"}]}]], fragment = "Could not decode" },
}) do
    catalog = load()
    tick(12)
    catalog:open(function() end)
    answer(requests[1], case.body)
    equal(false, catalog.loaded, "invalid response is not an empty successful catalog")
    assert(catalog.error:find(case.fragment, 1, true), case.fragment)
    catalog:open(function() end)
    equal(1, #requests, "failed open cannot automatically retry inside interval")
    catalog:shutdown()
end

catalog = load()
tick(100)
catalog:open(function() end)
answer(requests[1], [[{"bucket":[{"title":"Old","author":"A","page_name":"User:Old","token":"TM2:old"}]}]])
tick(15100)
catalog:refresh()
answer(requests[2], [[{"error":"Wiki down"}]])
equal("Old", catalog.rows[1].title, "API failure retains stale successful data")
equal(true, catalog.loaded, "API failure preserves loaded status")
assert(catalog.error:find("Wiki down"), "API failure is displayed with cached data")
catalog:shutdown()

catalog = load()
tick(1)
catalog:open(function() end)
requests[1].successful = false
requests[1].responseCode = 503
requests[1].callback(requests[1])
assert(catalog.error:find("HTTP 503"), "HTTP errors explain status")
tick(15001)
catalog:refresh()
requests[2].successful = false
requests[2].failed = true
requests[2].errorInfo = "connection reset"
requests[2].callback(requests[2])
assert(catalog.error:find("connection reset"), "transport failures are visible")
catalog:shutdown()

for _, failure in ipairs({ "constructor", "get" }) do
    catalog = load()
    tick(20)
    if failure == "constructor" then constructorError = true end
    if failure == "get" then getError = true end
    catalog:open(function() end)
    equal(false, catalog.loading, failure .. " throw clears loading state")
    assert(catalog.error:find("Could not start wiki request"), failure .. " throw is visible")
    if failure == "get" then
        equal(true, requests[1].cancelled, failure .. " thrown request is cancelled")
    end
    catalog:open(function() end)
    equal(failure == "constructor" and 0 or 1, #requests,
        failure .. " error does not trigger automatic retry")
    catalog:shutdown()
end

catalog = load()
tick(20)
headerError = true
catalog:open(function() end)
equal(true, catalog.loading, "rejected optional User-Agent does not block request")
answer(requests[1], [[{"bucket":[]}]])
equal(true, catalog.loaded, "wiki request still succeeds without User-Agent")
catalog:shutdown()

catalog = load()
tick(1)
local closedUpdates = 0
catalog:open(function() closedUpdates = closedUpdates + 1 end)
local loadingRequest = requests[1]
catalog:detach()
local beforeDetach = closedUpdates
answer(loadingRequest, [[{"bucket":[{"title":"Cached","author":"A","page_name":"User:Cached","token":"TM2:cached"}]}]])
equal(beforeDetach, closedUpdates, "closed view is not notified by pending response")
equal(false, loadingRequest.cancelled, "closing the view keeps a cacheable request alive")
equal(true, catalog.loaded, "pending request fills cache after view closes")
catalog:open(function() closedUpdates = closedUpdates + 1 end)
equal(beforeDetach + 1, closedUpdates, "reopening displays completed background cache")
equal(1, #requests, "reopening does not issue a second request")
catalog:shutdown()

catalog = load()
tick(2)
local postShutdownNotifications = 0
catalog:open(function() postShutdownNotifications = postShutdownNotifications + 1 end)
local pending = requests[1]
catalog:shutdown()
equal(true, pending.cancelled, "shutdown cancels pending request")
local before = postShutdownNotifications
answer(pending, [[{"bucket":[]}]])
equal(before, postShutdownNotifications, "late callback cannot notify closed UI")
equal(false, catalog.loaded, "late callback cannot alter unloaded cache")
catalog:refresh(function() end)
equal(1, #requests, "shutdown prevents all future requests")

catalog = load()
tick(0)
catalog:open(function() end)
local rows = {}
for index = 1, 5000 do
    rows[index] = [[{"title":"T","author":"A","page_name":"User:Wiki","token":"TM2:t"}]]
end
answer(requests[1], '{"bucket":[' .. table.concat(rows, ',') .. ']}')
equal(5000, #catalog.rows, "catalog receives the maximum bounded response")
equal(true, catalog.truncated, "limit hit exposes truncation")
assert(catalog.truncationMessage:find("5,000", 1, true), "truncation message is usable by UI")
rows[5001] = rows[1]
tick(15000)
catalog:refresh()
answer(requests[2], '{"bucket":[' .. table.concat(rows, ',') .. ']}')
equal(5000, #catalog.rows, "oversized result cannot overwrite cached catalog")
assert(catalog.error:find("more than the 5,000"), "oversized result reports an error")
catalog:shutdown()

local Json = require("src/json")
local unicode = Json.decode([["\uD834\uDD1E"]])
equal("𝄞", unicode, "Unicode surrogate pair decoded")
for _, invalid in ipairs({
    [["\uDE80"]], [["\uD800"]], [["\uD800\u0001"]],
    '[\"' .. string.char(0xC3, 0x28) .. '\"]',
    string.rep("[", 34) .. "0" .. string.rep("]", 34),
    "1e9999",
}) do
    local value, reason = Json.decode(invalid)
    equal(nil, value, "malformed JSON rejected")
    assert(type(reason) == "string", "malformed JSON has a useful reason")
end

print("test_preset_catalog: ok")

local Json = require("src/json")

local Catalog = {
    rows = {},
    loading = false,
    loaded = false,
    error = nil,
    truncated = false,
    truncationMessage = nil,
    refreshAvailable = true,
}

local QUERY = "bucket('tilemarkerpreset').select('page_name','title','author','token','tags').limit(5000).run()"
local REQUEST_PATH = "/api.php?action=bucket&format=json&query="
    .. QUERY:gsub("([^A-Za-z0-9_.~%-])", function(character)
        return string.format("%%%02X", character:byte())
    end)
local MIN_REQUEST_INTERVAL_TICKS = 15000
local COOLDOWN_MESSAGE = "Please wait five minutes between wiki requests."
local LIMIT = 5000
local listener
local request
local lastAttemptTick
local currentTick = 0
local stopped = false

local function notify()
    Catalog.refreshAvailable = not stopped and not Catalog.loading
        and (lastAttemptTick == nil or currentTick - lastAttemptTick >= MIN_REQUEST_INTERVAL_TICKS)
    if listener then listener() end
end

Event.Logic.Subscribe("tilemarkers_preset_catalog_tick", function(event)
    currentTick = event.logicTick
    if not Catalog.refreshAvailable and not Catalog.loading and lastAttemptTick
        and currentTick - lastAttemptTick >= MIN_REQUEST_INTERVAL_TICKS then
        if Catalog.error == COOLDOWN_MESSAGE then Catalog.error = nil end
        notify()
    end
end)

local function cleanMessage(value)
    return value:gsub("<[^>]*>", ""):sub(1, 240)
end

local function normalizeTags(value)
    local tags, seen = {}, {}
    if type(value) == "table" and value ~= Json.null then
        for _, tag in ipairs(value) do
            if type(tag) == "string" then
                tag = tag:match("^%s*(.-)%s*$"):lower()
                if tag ~= "" and not seen[tag] then
                    seen[tag] = true
                    tags[#tags + 1] = tag
                end
            end
        end
    end
    table.sort(tags)
    return tags
end

local function parseResponse(body)
    local decoded, parseError = Json.decode(body)
    if decoded == nil then
        return nil, "Could not decode wiki response: " .. parseError
    end
    if type(decoded) ~= "table" or decoded == Json.null then
        return nil, "Wiki returned an unexpected response."
    end
    if decoded.error ~= nil then
        local apiError = decoded.error
        if type(apiError) == "table" and apiError ~= Json.null then
            apiError = apiError.info or apiError.code
        end
        if type(apiError) ~= "string" then apiError = "Unknown API error" end
        return nil, "Wiki API error: " .. cleanMessage(apiError)
    end

    local bucket = decoded.bucket
    if type(bucket) ~= "table" or bucket == Json.null then
        return nil, "Wiki response has no preset bucket."
    end
    local count = #bucket
    if count > LIMIT then
        return nil, "Wiki returned more than the 5,000 requested presets."
    end
    -- An empty [] or {} is a valid empty result. A nonempty object is not a
    -- list: accepting it would report a malformed response as an empty catalog.
    for key in pairs(bucket) do
        if type(key) ~= "number" or key < 1 or key > count or key % 1 ~= 0 then
            return nil, "Wiki returned a malformed preset bucket."
        end
    end

    local rows = {}
    local invalid = 0
    for _, entry in ipairs(bucket) do
        if type(entry) == "table" and entry ~= Json.null
            and type(entry.title) == "string" and entry.title ~= ""
            and type(entry.author) == "string"
            and type(entry.page_name) == "string" and entry.page_name ~= ""
            and type(entry.token) == "string" and entry.token ~= "" then
            rows[#rows + 1] = {
                title = entry.title,
                author = entry.author,
                page = entry.page_name,
                token = entry.token,
                tags = normalizeTags(entry.tags),
            }
        else
            invalid = invalid + 1
        end
    end
    if invalid > 0 and #rows == 0 then
        return nil, "Wiki returned " .. invalid .. " malformed preset entries."
    end
    local warning
    if invalid > 0 then
        warning = "Skipped " .. invalid .. " malformed wiki preset entries."
    end
    return rows, warning, count == LIMIT
end

local function complete(finishedRequest)
    if stopped or request ~= finishedRequest then return end
    request = nil
    Catalog.loading = false
    if finishedRequest.successful and (not finishedRequest.responseCode
        or finishedRequest.responseCode >= 200 and finishedRequest.responseCode < 300) then
        local rows, responseError, truncated = parseResponse(finishedRequest.data)
        if rows then
            Catalog.rows = rows
            Catalog.loaded = true
            Catalog.truncated = truncated
            Catalog.truncationMessage = truncated
                and "Wiki returned the 5,000-preset limit; more presets may exist."
                or nil
            Catalog.error = responseError
        else
            -- A failed refresh must not destroy a previously usable catalog.
            Catalog.error = responseError
        end
    elseif finishedRequest.timedOut then
        Catalog.error = "Wiki request timed out. Please try again later."
    elseif finishedRequest.responseCode and finishedRequest.responseCode >= 400 then
        Catalog.error = "Wiki request failed (HTTP " .. finishedRequest.responseCode .. ")."
    elseif finishedRequest.failed then
        local info = finishedRequest.errorInfo
        Catalog.error = "Wiki request failed"
            .. (type(info) == "string" and info ~= "" and ": " .. cleanMessage(info) or ".")
    else
        Catalog.error = "Wiki request did not complete. Please try again later."
    end
    notify()
end

local function startRequest()
    if stopped then return false, "Wiki catalog is unavailable." end
    if Catalog.loading then return false, "Wiki request is already in progress." end
    if not Plugin.HasPermission(PluginPermissions.httpAccess) then
        Catalog.error = "Wiki presets require the optional HTTP access permission."
        notify()
        return false, Catalog.error
    end
    if lastAttemptTick and currentTick - lastAttemptTick < MIN_REQUEST_INTERVAL_TICKS then
        if not Catalog.error then
            Catalog.error = COOLDOWN_MESSAGE
        end
        notify()
        return false, COOLDOWN_MESSAGE
    end

    lastAttemptTick = currentTick
    Catalog.loading = true
    Catalog.error = nil
    notify()
    -- A state listener can close the plugin or request another refresh.
    if stopped or not Catalog.loading then return false, "Wiki catalog is unavailable." end

    local ok, result = pcall(function()
        local created = HTTPRequest.new(Plugin.urls.wiki, REQUEST_PATH)
        request = created
        -- Identification is courteous but must not prevent requests on clients
        -- which disallow overriding the User-Agent header.
        pcall(function()
            created:AddHeader("User-Agent", "Tile Markers RuneScape plugin (plugins@j3.gg)")
        end)
        created:Get(complete)
    end)
    if not ok and not stopped and Catalog.loading then
        local failedRequest = request
        request = nil
        if failedRequest then pcall(function() failedRequest:Cancel() end) end
        Catalog.loading = false
        Catalog.error = "Could not start wiki request: " .. cleanMessage(tostring(result))
        notify()
        return false, Catalog.error
    end
    return true
end

function Catalog:open(onChange)
    if stopped then return end
    listener = onChange
    if self.loaded or self.loading then
        notify()
    else
        startRequest()
    end
end

function Catalog:refresh(onChange)
    if stopped then return false, "Wiki catalog is unavailable." end
    if onChange ~= nil then listener = onChange end
    return startRequest()
end

function Catalog:detach()
    listener = nil
end

function Catalog:shutdown()
    if stopped then return end
    stopped = true
    listener = nil
    local pending = request
    request = nil
    self.loading = false
    self.refreshAvailable = false
    Event.Logic.Unsubscribe("tilemarkers_preset_catalog_tick")
    if pending then pcall(function() pending:Cancel() end) end
end

return Catalog

local Hub = {}
Hub.__index = Hub

local PAGE_SIZE = 25
local ROW_HEIGHT = 88
local RESULTS_HEIGHT = 336
local ROW_COLOURS = { 0x24211EFF, 0x2E2825FF }
local TITLE_COLOUR = 0xEED6A0FF
local MUTED_COLOUR = 0xAAA397FF
local PILL_HEIGHT = 22
local PILL_GAP = 6
local PILL_PADDING = 10

local FALLBACK_TAG_STYLES = {
    { 0x365C48FF, 0xF2EEE7FF }, { 0x703E42FF, 0xF2EEE7FF },
    { 0x715735FF, 0xF2EEE7FF }, { 0x51436EFF, 0xF2EEE7FF },
    { 0x345C73FF, 0xF2EEE7FF }, { 0x356361FF, 0xF2EEE7FF },
}
local DARK_TAG_TEXT = 0x101010FF
local TAG_STYLES = {
    agility = { 0x464F83FF, 0xFFFFFFFF },
    archaeology = { 0x202020FF, 0xFFFFFFFF },
    attack = { 0x8B0000FF, 0xFFFFFFFF },
    constitution = { 0xF8F8FFFF, DARK_TAG_TEXT },
    construction = { 0xD2B48CFF, DARK_TAG_TEXT },
    cooking = { 0x800080FF, 0xFFFFFFFF },
    crafting = { 0x8B4513FF, 0xFFFFFFFF },
    defence = { 0x6495EDFF, DARK_TAG_TEXT },
    divination = { 0x713684FF, 0xFFFFFFFF },
    dungeoneering = { 0x704214FF, 0xFFFFFFFF },
    farming = { 0x006400FF, 0xFFFFFFFF },
    firemaking = { 0xBA8556FF, DARK_TAG_TEXT },
    fishing = { 0x87CEFAFF, DARK_TAG_TEXT },
    fletching = { 0x008080FF, 0xFFFFFFFF },
    herblore = { 0x44724AFF, 0xFFFFFFFF },
    hunter = { 0x808000FF, DARK_TAG_TEXT },
    invention = { 0xD2B244FF, DARK_TAG_TEXT },
    magic = { 0x4C5D96FF, 0xFFFFFFFF },
    mining = { 0x2F4F4FFF, 0xFFFFFFFF },
    necromancy = { 0x76558DFF, 0xFFFFFFFF },
    prayer = { 0xFFFAFAFF, DARK_TAG_TEXT },
    ranged = { 0x556B2FFF, 0xFFFFFFFF },
    runecrafting = { 0xFFFFE0FF, DARK_TAG_TEXT },
    slayer = { 0xB22222FF, 0xFFFFFFFF },
    smithing = { 0x808080FF, DARK_TAG_TEXT },
    strength = { 0x79A572FF, DARK_TAG_TEXT },
    summoning = { 0xE0FFFFFF, DARK_TAG_TEXT },
    thieving = { 0xBA55D3FF, DARK_TAG_TEXT },
    woodcutting = { 0xA0522DFF, 0xFFFFFFFF },
    boss = FALLBACK_TAG_STYLES[2],
    pvm = FALLBACK_TAG_STYLES[2],
    skilling = FALLBACK_TAG_STYLES[5],
}
local pillStrips = {}
local tagTextConfigs = {}

-- Cache the rounded cap scanlines once; every entry uses a single canvas,
-- rather than allocating background and text components for each tag.
for y = 0, PILL_HEIGHT - 1 do
    local radius = PILL_HEIGHT / 2
    local inset = math.floor(radius - math.sqrt(radius * radius - (y + 0.5 - radius) ^ 2) + 0.5)
    local previous = pillStrips[#pillStrips]
    if previous and previous.inset == inset then
        previous.height = previous.height + 1
    else
        pillStrips[#pillStrips + 1] = { inset = inset, y = y, height = 1 }
    end
end
local SUCCESS_COLOUR = 0xA5CC92FF
local WARNING_COLOUR = 0xF2C66DFF

local function plainText(value)
    return (tostring(value or ""):gsub("<[^>]*>", ""):gsub("[<>]", ""))
end

local function displayTag(tag)
    return (plainText(tag):gsub("^%l", string.upper))
end

local function tagStyle(tag)
    local key = tag:lower()
    local style = TAG_STYLES[key]
    if style ~= nil then return style end
    local hash = 0
    for index = 1, #key do hash = (hash * 31 + key:byte(index)) % #FALLBACK_TAG_STYLES end
    return FALLBACK_TAG_STYLES[hash + 1]
end

local function layoutTagRows(rows, first, last, width)
    local layouts, totalHeight = {}, 0
    for index = first, last do
        local pills, x, y = {}, 0, 0
        for _, tag in ipairs(rows[index].tags or {}) do
            local label = displayTag(tag)
            if label ~= "" then
                local pillWidth = math.min(width,
                    config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth(label, false) + PILL_PADDING * 2)
                if x > 0 and x + pillWidth > width then
                    x, y = 0, y + PILL_HEIGHT + PILL_GAP
                end
                local style = tagStyle(label)
                pills[#pills + 1] = {
                    label = label, colour = style[1], textColour = style[2], x = x, y = y, width = pillWidth,
                }
                x = x + pillWidth + PILL_GAP
            end
        end
        local pillHeight = #pills > 0 and y + PILL_HEIGHT or 0
        local height = ROW_HEIGHT + math.max(0, pillHeight - PILL_HEIGHT)
        layouts[index] = { pills = pills, pillHeight = pillHeight, height = height }
        totalHeight = totalHeight + height
    end
    return layouts, totalHeight
end

local function drawTags(pretty, view, layout, y)
    if #layout.pills == 0 then return end
    local canvas = pretty.NewComponent(ui.Canvas, view.content)
    canvas:SetPos(12, y)
    canvas:SetSize(view.contentWidth - 24, layout.pillHeight)
    canvas.clickthrough = true
    for _, pill in ipairs(layout.pills) do
        local textConfig = tagTextConfigs[pill.textColour]
        if textConfig == nil then
            textConfig = ui.TextDataConfig.new()
            textConfig.font = id.Font.MUSEO_SANS_15PT_REGULAR
            textConfig.alignHorizontal = ui.AlignMode.CENTRE
            textConfig.alignVertical = ui.AlignMode.CENTRE
            textConfig.maxLines = 1
            textConfig.rgba = pill.textColour
            tagTextConfigs[pill.textColour] = textConfig
        end
        for _, strip in ipairs(pillStrips) do
            canvas:AddRectangle(pill.x + strip.inset, pill.y + strip.y,
                pill.width - strip.inset * 2, strip.height, pill.colour)
        end
        canvas:AddText(pill.x + PILL_PADDING, pill.y, pill.width - PILL_PADDING * 2,
            PILL_HEIGHT, pill.label, textConfig)
    end
end

local function entryKey(row)
    -- Different wiki submissions may contain exactly the same encoded tiles.
    -- Quoted fields keep the identity unambiguous and stable across refreshes.
    return string.format("%q:%q:%q:%q", row.page, row.author, row.title, row.token)
end

local function matches(row, search)
    if search == "" then return true end
    if tostring(row.title or ""):lower():find(search, 1, true) ~= nil
        or tostring(row.author or ""):lower():find(search, 1, true) ~= nil
        or tostring(row.page or ""):lower():find(search, 1, true) ~= nil then
        return true
    end
    for _, tag in ipairs(row.tags or {}) do
        if tag:find(search, 1, true) then return true end
    end
    return false
end

local function hasTag(row, selectedTag)
    if selectedTag == nil then return true end
    for _, tag in ipairs(row.tags or {}) do
        if tag == selectedTag then return true end
    end
    return false
end

local function orderRows(left, right)
    local a, b = tostring(left.title or ""):lower(), tostring(right.title or ""):lower()
    if a ~= b then return a < b end
    a, b = tostring(left.author or ""):lower(), tostring(right.author or ""):lower()
    if a ~= b then return a < b end
    a, b = tostring(left.page or ""), tostring(right.page or "")
    if a ~= b then return a < b end
    return tostring(left.token or "") < tostring(right.token or "")
end

function Hub.new(prettyui, catalog, importFn, onImported)
    return setmetatable({
        prettyui = prettyui,
        catalog = catalog,
        importFn = importFn,
        onImported = onImported,
        window = nil,
        page = 1,
        search = "",
        tag = nil,
        tagIDs = {},
        importedEntries = {},
    }, Hub)
end

function Hub:_release(window)
    if self.window ~= window then return end
    self.window = nil
    self.catalog:detach()
    for _, field in ipairs({ "results", "controls", "footer" }) do
        local view = self[field]
        self[field] = nil
        if view ~= nil then view:Destroy() end
    end
    self.searchField = nil
    self.tagCombo = nil
    self.tagRows = nil
    self.statusText = nil
    self.refreshButton = nil
    self.pageText = nil
    self.prevButton = nil
    self.nextButton = nil
end

function Hub:close()
    local window = self.window
    if window == nil then return end
    window:Close()
end

function Hub:shutdown()
    self:close()
end

function Hub:_updateTags()
    if self.tagRows == self.catalog.rows then return end
    local tags, entries = {}, { { label = "All tags", id = 0 } }
    for _, row in ipairs(self.catalog.rows) do
        for _, tag in ipairs(row.tags or {}) do tags[tag] = true end
    end
    local sorted = {}
    for tag in pairs(tags) do sorted[#sorted + 1] = tag end
    table.sort(sorted)
    self.tagIDs = {}
    local selected = 0
    local usedLabels = { ["All tags"] = true }
    for index, tag in ipairs(sorted) do
        local display = displayTag(tag)
        if display == "" then display = "(unnamed tag)" end
        local label = display
        local suffix = 2
        while usedLabels[label] do
            label = display .. " (" .. suffix .. ")"
            suffix = suffix + 1
        end
        usedLabels[label] = true
        entries[#entries + 1] = { label = label, id = index }
        self.tagIDs[index] = tag
        if self.tag == tag then selected = index end
    end
    if selected == 0 then
        self.tag = nil
        self.page = 1
    end
    self.updatingTags = true
    self.tagCombo:SetEntries(entries, selected)
    self.tagRows = self.catalog.rows
    self.updatingTags = false
end

function Hub:_updateStatus()
    local catalog = self.catalog
    if self.refreshFeedback and catalog.refreshAvailable then
        self.feedback = nil
        self.refreshFeedback = nil
    end
    local status, colour = nil, MUTED_COLOUR
    if self.feedback then
        status, colour = self.feedback, self.feedbackColour
        local errorText = catalog.error and plainText(catalog.error)
        if errorText and errorText ~= status then status = status .. " " .. errorText end
    elseif catalog.loading then
        status = catalog.loaded and "Refreshing catalogue. Your cached presets are still available."
            or "Loading community presets..."
    elseif catalog.error ~= nil then
        status, colour = plainText(catalog.error), WARNING_COLOUR
        if catalog.loaded then status = status .. " Showing cached results." end
    elseif catalog.loaded then
        status = "Community presets from the RuneScape Wiki"
    else
        status = "Open the hub with HTTP access enabled to browse community presets."
    end
    if catalog.truncated then
        status = status .. " " .. plainText(catalog.truncationMessage
            or "Only the first 5,000 wiki presets are shown.")
    end
    self.statusText.content = status
    self.statusText.rgba = colour
    self.refreshButton:SetDisabled(not catalog.refreshAvailable)
end

function Hub:_import(window, row)
    local key = entryKey(row)
    if self.window ~= window or self.importedEntries[key] then return end
    self.refreshFeedback = nil
    local success, result = self.importFn(row.token)
    if success then
        self.importedEntries[key] = true
        self.feedback = "Imported " .. plainText(result and result.name or row.title) .. "."
        self.feedbackColour = SUCCESS_COLOUR
        self:_updateStatus()
        local scrollY = self.results and self.results.scrollY or 0
        self:_render()
        self.results:SetScrollPosition(scrollY)
        if self.onImported ~= nil then self.onImported(result) end
    else
        self.feedback = "Import failed: " .. plainText(result or "Could not save this preset.")
        self.feedbackColour = WARNING_COLOUR
        self:_updateStatus()
    end
end

function Hub:_render()
    local window = self.window
    if window == nil then return end
    local filtered = {}
    local search = self.search:lower()
    for _, row in ipairs(self.catalog.rows) do
        if hasTag(row, self.tag) and matches(row, search) then
            filtered[#filtered + 1] = row
        end
    end
    table.sort(filtered, orderRows)
    local pageCount = math.max(1, math.ceil(#filtered / PAGE_SIZE))
    self.page = math.max(1, math.min(self.page, pageCount))
    local first = (self.page - 1) * PAGE_SIZE + 1
    local last = math.min(#filtered, first + PAGE_SIZE - 1)
    self.pageText.content = string.format("%d-%d of %d",
        #filtered == 0 and 0 or first, last, #filtered)
    self.prevButton:SetDisabled(self.page == 1)
    self.nextButton:SetDisabled(self.page == pageCount)

    if self.results ~= nil then self.results:Destroy() end
    local view = self.prettyui.SimpleView.new(window.content, {
        categoryID = "auto",
        x = 12, y = 138, width = -24, widthAnchor = 1, height = RESULTS_HEIGHT,
        contentHeight = math.max(0, last - first + 1) * ROW_HEIGHT,
        scrollStep = ROW_HEIGHT,
        layout = { startY = 8, paddingLeft = 12, paddingRight = 12, paddingBottom = 8, rowGap = 0 },
    })
    self.results = view
    if #filtered == 0 then
        local empty = self.catalog.loading and not self.catalog.loaded
            and "Loading wiki presets..."
            or (self.catalog.loaded and #self.catalog.rows == 0 and "No wiki presets available."
                or (self.catalog.loaded and "No presets match these filters."
                    or "No wiki presets to show."))
        view:AddText({
            text = empty, height = 48, marginTop = 110,
            alignHorizontal = ui.AlignMode.CENTRE, colour = MUTED_COLOUR,
        })
        return
    end

    local tagWidth = view.contentWidth - 24
    local tagLayouts, totalHeight = layoutTagRows(filtered, first, last, tagWidth)
    view:SetContentHeight(totalHeight)
    if view.contentWidth - 24 ~= tagWidth then
        tagLayouts, totalHeight = layoutTagRows(filtered, first, last, view.contentWidth - 24)
        view:SetContentHeight(totalHeight)
    end

    for index = first, last do
        local row = filtered[index]
        local title = plainText(row.title)
        local author = plainText(row.author)
        local details = "By " .. (author ~= "" and author or "unknown")
        local tagLayout = tagLayouts[index]
        local imported = self.importedEntries[entryKey(row)] == true
        local titleText = view:AddText({
            text = title ~= "" and title or "(untitled preset)",
            height = 24, width = -124, widthAnchor = 1, maxLines = 1,
            marginBottom = 0, colour = TITLE_COLOUR,
        })
        view:AddSimpleButton(imported and "Added" or "Import",
            function() self:_import(window, row) end, {
                inline = true, x = -100, xAnchor = 1, width = 88, height = 24,
                marginBottom = 0,
                tooltip = imported and "Already imported during this visit" or "Import " .. title,
                disabled = imported, disabledColour = SUCCESS_COLOUR,
            })
        local authorText = view:AddText({
            text = details, height = 20, width = -24, widthAnchor = 1,
            maxLines = 1, marginBottom = tagLayout.height - 44, colour = MUTED_COLOUR,
        })
        drawTags(self.prettyui, view, tagLayout, authorText.y + authorText.height + PILL_GAP)
        -- SimpleView has no framed row-background host. Keep the bands on its
        -- scrolling content, using guarded IDs and the actual text geometry.
        local background = self.prettyui.NewComponent(ui.Rectangle, view.content)
        background:SetPos(0, titleText.y - 8)
        background:SetSize(0, tagLayout.height, 1, 0)
        background.fill = true
        background.rgba = ROW_COLOURS[(index - first) % #ROW_COLOURS + 1]
        background.clickthrough = true
        background:MoveToBack()
    end
end

function Hub:open(parent)
    if self.window ~= nil then
        self.window:Show()
        return true
    end
    if parent == nil then return false end
    self.page = 1
    self.search = ""
    self.tag = nil
    self.feedback = nil
    self.refreshFeedback = nil
    self.tagRows = nil
    self.importedEntries = {}
    local window
    window = self.prettyui.Window.new(parent, {
        title = "TileMarker Preset hub",
        x = -300, y = -280, xAnchor = 0.5, yAnchor = 0.5,
        width = 600, height = 560, resizable = false,
        destroyOnClose = true,
        onClose = function() self:_release(window) end,
    })
    self.window = window
    window:SetScrollable(false)
    self.controls = self.prettyui.SimpleView.new(window.content, {
        x = 8, y = 8, width = -16, widthAnchor = 1, height = 112,
        scrollable = false,
        layout = { startY = 0, paddingLeft = 4, paddingRight = 4, paddingBottom = 0, rowGap = 8 },
    })
    self.statusText = self.controls:AddText({
        text = "", height = 36, maxLines = 2, marginBottom = 8, colour = MUTED_COLOUR,
        alignHorizontal = ui.AlignMode.CENTRE, alignVertical = ui.AlignMode.CENTRE,
    })
    self.searchField = self.controls:AddTextField({
        placeholder = "Search presets...",
        maxLength = 120,
        onChange = function(_, _, text)
            if self.window ~= window then return end
            self.search = text or ""
            self.page = 1
            self:_render()
        end,
    })
    self.tagCombo = self.controls:AddComboBox({
        entries = { { label = "All tags", id = 0 } },
        selectedID = 0,
        width = -112, widthAnchor = 1,
        onChange = function(_, tagID)
            if self.window ~= window or self.updatingTags then return end
            self.tag = self.tagIDs[tagID]
            self.page = 1
            self:_render()
        end,
    })
    self.refreshButton = self.controls:AddSimpleButton("Refresh", function()
        if self.window ~= window then return end
        self.feedback = nil
        self.refreshFeedback = nil
        local started, reason = self.catalog:refresh(function()
            if self.window ~= window then return end
            local rowsChanged = self.tagRows ~= self.catalog.rows
            self:_updateTags()
            self:_updateStatus()
            if rowsChanged or not self.catalog.loaded then self:_render() end
        end)
        if self.window == window then
            if not started then
                self.feedback = plainText(reason or "Could not refresh wiki presets.")
                self.refreshFeedback = true
                self.feedbackColour = WARNING_COLOUR
            end
            self:_updateStatus()
        end
    end, {
        inline = true, x = -100, xAnchor = 1, width = 96, height = 30,
        tooltip = "Refresh the wiki catalogue (five-minute request limit)",
    })

    self.footer = self.prettyui.SimpleView.new(window.content, {
        x = 8, y = 482, width = -16, widthAnchor = 1, height = 32,
        scrollable = false,
        layout = { startY = 0, paddingLeft = 4, paddingRight = 4, paddingBottom = 0 },
    })
    self.pageText = self.footer:AddText({
        text = "", height = 27, x = -72, xAnchor = 0.5, width = 144,
        maxLines = 1, alignHorizontal = ui.AlignMode.CENTRE, alignVertical = ui.AlignMode.CENTRE,
    })
    self.prevButton = self.footer:AddSpriteButton("ARROW_LEFT", function()
        if self.window ~= window or self.page <= 1 then return end
        self.page = self.page - 1
        self:_render()
    end, { inline = true, x = -104, xAnchor = 0.5, size = 24, offsetY = 2, tooltip = "Previous page" })
    self.nextButton = self.footer:AddSpriteButton("ARROW_RIGHT", function()
        if self.window ~= window then return end
        self.page = self.page + 1
        self:_render()
    end, { inline = true, x = 80, xAnchor = 0.5, size = 24, offsetY = 2, tooltip = "Next page" })
    self:_updateTags()
    self:_updateStatus()
    self:_render()
    self.catalog:open(function()
        if self.window ~= window then return end
        local rowsChanged = self.tagRows ~= self.catalog.rows
        self:_updateTags()
        self:_updateStatus()
        if rowsChanged or not self.catalog.loaded then self:_render() end
    end)
    return true
end

return Hub

-- The ledger window (Summary, Items, Categories, Profit and Compare tabs), the minimap button and the addon
-- compartment entry. The window is built on first use.

local OAL = OpcowsLedger
local WIDTH, HEIGHT = 760, 560
local ROW_HEIGHT = 20
local ICON = "Interface\\Icons\\INV_Misc_Coin_01"
local RECENT = 200  -- how many of the latest sales and purchases the Summary tab lists

local win
local minimapButton
local state = { tab = "summary", period = "all", from = "all", sort = "sg", desc = true, who = "all" }

-- widget helpers ---------------------------------------------------------------------------------

local function Label(parent, text, font)
    local fs = parent:CreateFontString(nil, "ARTWORK", font or "GameFontNormal")
    fs:SetText(text)
    fs:SetJustifyH("LEFT")
    return fs
end

local function Button(parent, text, width, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

-- text can be a function of the widget, for tooltips that describe the current state
local function Tooltip(widget, title, text)
    widget:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        local t = type(text) == "function" and text(self) or text
        if t then GameTooltip:AddLine(t, 1, 1, 1, true) end
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function EditBox(parent, width)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(width, 20)
    e:SetAutoFocus(false)
    return e
end

local function Box(parent, bg)
    local b = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    b:SetBackdrop({
        bgFile = bg or "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    if not bg then b:SetBackdropColor(0, 0, 0, 0.5) end
    b:SetBackdropBorderColor(0.6, 0.6, 0.6)
    return b
end

local function Step(list, current, dir)
    local at = 1
    for i, v in ipairs(list) do
        if v == current then at = i end
    end
    return list[(at - 1 + dir) % #list + 1]
end

-- A scrolling table with clickable column headers.
-- cols = { { title, width, justify, sort = key } }; the first column has the row's icon unless
-- opts.noIcon. opts: remove (rows get an X), onDrop (something dropped from the cursor),
-- onSort(key) (a header with a sort key was clicked).
local function Table(parent, width, height, cols, opts)
    opts = opts or {}
    local t = CreateFrame("Frame", nil, parent)
    t:SetSize(width, height)
    local box = Box(t)
    box:SetPoint("TOPLEFT", 0, -18)
    box:SetPoint("BOTTOMRIGHT")
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 4, -4)
    sf:SetPoint("BOTTOMRIGHT", -26, 4)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(width - 30, 1)
    sf:SetScrollChild(child)
    t.rows, t.headers = {}, {}

    -- shown when there are no rows
    t.empty = Label(box, "", "GameFontDisableSmall")
    t.empty:SetPoint("TOPLEFT", 12, -12)
    t.empty:SetPoint("RIGHT", box, "RIGHT", -12, 0)
    t.empty:SetWordWrap(true)

    local iconWidth = opts.noIcon and 4 or 22
    local x = 0
    for c, col in ipairs(cols) do
        local inset = c == 1 and iconWidth or 0
        local h = CreateFrame("Button", nil, t)
        h:SetSize(col.width - inset - 4, 18)
        h:SetPoint("TOPLEFT", 4 + x + inset, 0)
        h.text = h:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        h.text:SetAllPoints()
        h.text:SetJustifyH(col.justify or "LEFT")
        h.text:SetText(col.title)
        h.sort = col.sort
        if col.sort and opts.onSort then
            h:SetScript("OnClick", function() opts.onSort(col.sort) end)
            Tooltip(h, col.title, "Click to sort by this. Click again to reverse.")
        end
        t.headers[c] = h
        x = x + col.width
    end

    -- the sorted column's header is white
    function t:MarkSort(key)
        for _, h in ipairs(self.headers) do
            h.text:SetFontObject(h.sort and h.sort == key and "GameFontHighlightSmall" or "GameFontNormalSmall")
        end
    end

    local function Droppable(f)
        if not opts.onDrop then return end
        f:EnableMouse(true)
        f:SetScript("OnReceiveDrag", function() opts.onDrop() end)
        f:HookScript("OnMouseUp", function() if GetCursorInfo() then opts.onDrop() end end)
    end
    Droppable(box)
    Droppable(sf)

    local function NewRow(i)
        local row = CreateFrame("Button", nil, child)
        row:SetHeight(ROW_HEIGHT)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("RIGHT", child, "RIGHT")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.sel = row:CreateTexture(nil, "BACKGROUND")
        row.sel:SetAllPoints()
        row.sel:SetColorTexture(1, 0.82, 0, 0.25)
        if not opts.noIcon then
            row.icon = row:CreateTexture(nil, "ARTWORK")
            row.icon:SetSize(16, 16)
            row.icon:SetPoint("LEFT", 2, 0)
        end
        row.cells = {}
        local cx = 0
        for c, col in ipairs(cols) do
            local inset = c == 1 and iconWidth or 0
            local fs = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", row, "LEFT", cx + inset, 0)
            fs:SetWidth(col.width - inset - 4)
            fs:SetJustifyH(col.justify or "LEFT")
            fs:SetWordWrap(false)
            row.cells[c] = fs
            cx = cx + col.width
        end
        if opts.remove then
            row.remove = CreateFrame("Button", nil, row, "UIPanelCloseButton")
            row.remove:SetSize(20, 20)
            row.remove:SetPoint("RIGHT", 0, 0)
            row.remove:SetScript("OnClick", function() row.data.onRemove() end)
            Tooltip(row.remove, "Remove", opts.removeText)
        end
        row:SetScript("OnClick", function(self)
            if GetCursorInfo() and opts.onDrop then
                opts.onDrop()
            elseif self.data.onClick then
                self.data.onClick()
            end
        end)
        if opts.onDrop then row:SetScript("OnReceiveDrag", function() opts.onDrop() end) end
        row:SetScript("OnEnter", function(self)
            local d = self.data
            if not d.id and not d.lines then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if d.id and d.id > 0 and GameTooltip.SetItemByID then
                GameTooltip:SetItemByID(d.id)
            else
                GameTooltip:SetText(d.title or "")
            end
            for _, line in ipairs(d.lines or {}) do
                if type(line) == "table" then
                    GameTooltip:AddDoubleLine(line[1], line[2], 1, 0.82, 0, 1, 1, 1)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        t.rows[i] = row
        return row
    end

    -- rows = { { cells = { text, ... }, icon, id, title, lines, selected, onClick, onRemove }, ... }
    function t:SetRows(rows, emptyText)
        for i, data in ipairs(rows) do
            local row = self.rows[i] or NewRow(i)
            row.data = data
            if row.icon then row.icon:SetTexture(data.icon) end
            for c, fs in ipairs(row.cells) do
                fs:SetText(data.cells[c] or "")
            end
            row.sel:SetShown(data.selected and true or false)
            if row.remove then row.remove:SetShown(data.onRemove ~= nil) end
            row:Show()
        end
        for i = #rows + 1, #self.rows do
            self.rows[i]:Hide()
        end
        child:SetHeight(math.max(1, #rows * ROW_HEIGHT))
        self.empty:SetText(#rows == 0 and emptyText or "")
    end

    return t
end

-- the edit box of a StaticPopup, whatever this client calls it
local function PopupBox(popup)
    return popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox())
end

local function PopupEnter(self)
    local popup = self:GetParent()
    local accept = popup.button1 or (popup.GetButton1 and popup:GetButton1())
    if accept then accept:Click() end
end

-- shared pieces ----------------------------------------------------------------------------------

local function Count(n)
    return n > 0 and (BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)) or ""
end

local function Avg(g, n)
    return n > 0 and OAL.Money(g / n) or ""
end

-- tooltip lines for an item's totals
local function ItemLines(it)
    local lines = {}
    if it.sn > 0 then
        lines[#lines + 1] = { "Sold " .. it.sn, OAL.Money(it.sg) }
        lines[#lines + 1] = { "  each, on average", OAL.Money(it.sg / it.sn) }
    end
    if it.bn > 0 then
        lines[#lines + 1] = { "Bought " .. it.bn, OAL.Money(it.bg) }
        lines[#lines + 1] = { "  each, on average", OAL.Money(it.bg / it.bn) }
    end
    local cats = OAL.CategoriesOf(it.name)
    if cats ~= "" then lines[#lines + 1] = "Categories: " .. cats end
    return lines
end

-- the From filter in the middle of a sentence: "vendor", "auction house", "COD mail"
local function FromText()
    return (OAL.SOURCE_TEXT[state.from]:gsub("^%u%l", string.lower))
end

local function SelectedCategory()
    for _, cat in ipairs(OAL.DB().cats) do
        if cat == state.cat then return cat end
    end
    state.cat = OAL.Categories()[1]
    return state.cat
end

-- popups -----------------------------------------------------------------------------------------

StaticPopupDialogs.OPCOWS_AUCTION_LEDGER_NEW = {
    text = "Name the new category, ex: Mining.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnAccept = function(self)
        local box = PopupBox(self)
        local cat, err = OAL.AddCategory(box and box:GetText() or "")
        if cat then
            state.cat = cat
            OAL.Changed()
        else
            OAL.Print(err)
        end
    end,
    EditBoxOnEnterPressed = PopupEnter,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs.OPCOWS_AUCTION_LEDGER_RENAME = {
    text = "Rename the category %s.",
    button1 = ACCEPT or "Accept",
    button2 = CANCEL or "Cancel",
    hasEditBox = true,
    maxLetters = 40,
    OnShow = function(self, cat)
        local box = PopupBox(self)
        if box and cat then
            box:SetText(cat.name)
            box:HighlightText()
        end
    end,
    OnAccept = function(self, cat)
        local box = PopupBox(self)
        local ok, err = OAL.RenameCategory(cat, box and box:GetText() or "")
        if not ok then OAL.Print(err) end
    end,
    EditBoxOnEnterPressed = PopupEnter,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs.OPCOWS_AUCTION_LEDGER_DELETE = {
    text = "Delete the category %s?\nThe sales and purchases of its items stay in the ledger.",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function(_, cat) OAL.DeleteCategory(cat) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

StaticPopupDialogs.OPCOWS_AUCTION_LEDGER_CLEAR = {
    text = "Delete all of %s's sales, purchases and crafts from the ledger?\nThis can't be undone.",
    button1 = DELETE or "Delete",
    button2 = CANCEL or "Cancel",
    OnAccept = function() OAL.Clear() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

function OAL.ConfirmClear()
    StaticPopup_Show("OPCOWS_AUCTION_LEDGER_CLEAR", OAL.CharName())
end

-- Summary tab ------------------------------------------------------------------------------------

local SUMMARY_PERIODS = { "today", "7", "30", "all" }

local function SummaryPanel(p)
    local earnedHead = Label(p, "Earned")
    earnedHead:SetPoint("TOPLEFT", 160, -4)
    local spentHead = Label(p, "Spent")
    spentHead:SetPoint("TOPLEFT", 400, -4)
    p.lines = {}
    for i, period in ipairs(SUMMARY_PERIODS) do
        local y = -4 - i * 20
        local name = Label(p, OAL.PERIOD_TEXT[period], "GameFontNormal")
        name:SetPoint("TOPLEFT", 4, y)
        local earned = Label(p, "", "GameFontHighlight")
        earned:SetPoint("TOPLEFT", 160, y)
        local spent = Label(p, "", "GameFontHighlight")
        spent:SetPoint("TOPLEFT", 400, y)
        p.lines[i] = { period = period, earned = earned, spent = spent }
    end

    local recentHead = Label(p, "Latest sales and purchases")
    recentHead:SetPoint("TOPLEFT", 4, -118)
    p.recent = Table(p, WIDTH - 28, 300, {
        { title = "Item", width = 190 },
        { title = "Count", width = 44, justify = "RIGHT" },
        { title = "", width = 60 },
        { title = "Amount", width = 116, justify = "RIGHT" },
        { title = "From", width = 104 },
        { title = "When", width = 104 },
    })
    p.recent:SetPoint("TOPLEFT", 0, -136)

    function p:Refresh()
        for _, line in ipairs(self.lines) do
            local earned, spent, sales, buys = OAL.Totals(OAL.Since(line.period), state.from)
            line.earned:SetText(OAL.Money(earned) .. "  |cff999999(" .. sales .. (sales == 1 and " sale)" or " sales)") .. "|r")
            line.spent:SetText(OAL.Money(spent) .. "  |cff999999(" .. buys .. (buys == 1 and " purchase)" or " purchases)") .. "|r")
        end
        local log, rows = OAL.Char().log, {}
        for i = #log, 1, -1 do
            local e = log[i]
            local src = OAL.Source(e)
            if state.from == "all" or src == state.from then
                local sold = e.k == "s"
                local from = OAL.SOURCE_TEXT[src] or src
                rows[#rows + 1] = {
                    cells = {
                        e.name, Count(e.n or 1), sold and "|cff40ff40Sold|r" or "|cffff7070Bought|r",
                        OAL.Money(e.g), from .. (e.who and ("|cff999999: " .. e.who .. "|r") or ""),
                        date("%b %d, %H:%M", e.t),
                    },
                    icon = OAL.ItemIcon(e.name, e.id),
                    id = OAL.ItemID(e.name, e.id),
                    title = e.name,
                    lines = { { sold and "Sold" or "Bought", from .. (e.who and (", " .. e.who) or "") } },
                }
                if #rows >= RECENT then break end
            end
        end
        self.recent:SetRows(rows, state.from ~= "all" and ("No " .. FromText() .. " sales or purchases yet.")
            or ("Nothing yet. Auction house sales count when you take their gold from the mail, and "
            .. "purchases when you take the item. Selling to and buying from vendors counts, trades count "
            .. "when gold changes hands, and COD mail counts when it's paid for."))
    end
end

-- Items tab --------------------------------------------------------------------------------------

local function SortItems(list)
    local key, desc = state.sort, state.desc
    local function Value(it)
        if key == "sa" then return it.sn > 0 and it.sg / it.sn or 0 end
        if key == "ba" then return it.bn > 0 and it.bg / it.bn or 0 end
        return it[key]
    end
    table.sort(list, function(a, b)
        if key ~= "name" then
            local va, vb = Value(a), Value(b)
            if va ~= vb then
                if desc then return va > vb end
                return va < vb
            end
        end
        if key == "name" and desc then return a.name:lower() > b.name:lower() end
        return a.name:lower() < b.name:lower()
    end)
end

local function ItemsPanel(p)
    p.table = Table(p, WIDTH - 28, HEIGHT - 82 - 14 - 22, {
        { title = "Item", width = 180, sort = "name" },
        { title = "Sold", width = 46, justify = "RIGHT", sort = "sn" },
        { title = "Earned", width = 96, justify = "RIGHT", sort = "sg" },
        { title = "Each", width = 84, justify = "RIGHT", sort = "sa" },
        { title = "Bought", width = 50, justify = "RIGHT", sort = "bn" },
        { title = "Spent", width = 96, justify = "RIGHT", sort = "bg" },
        { title = "Each", width = 70, justify = "RIGHT", sort = "ba" },
    }, {
        onSort = function(key)
            if state.sort == key then
                state.desc = not state.desc
            else
                state.sort, state.desc = key, key ~= "name"
            end
            p:Refresh()
        end,
    })
    p.table:SetPoint("TOPLEFT")
    p.total = Label(p, "", "GameFontHighlightSmall")
    p.total:SetPoint("BOTTOMLEFT", 4, 4)

    function p:Refresh()
        local since = OAL.Since(state.period)
        local list = {}
        for _, it in pairs(OAL.Items(since, state.from)) do list[#list + 1] = it end
        SortItems(list)
        local rows = {}
        for _, it in ipairs(list) do
            rows[#rows + 1] = {
                cells = {
                    it.name, Count(it.sn), it.sn > 0 and OAL.Money(it.sg) or "", Avg(it.sg, it.sn),
                    Count(it.bn), it.bn > 0 and OAL.Money(it.bg) or "", Avg(it.bg, it.bn),
                },
                icon = OAL.ItemIcon(it.name, it.id),
                id = OAL.ItemID(it.name, it.id),
                title = it.name,
                lines = ItemLines(it),
            }
        end
        self.table:MarkSort(state.sort)
        self.table:SetRows(rows, "No " .. (state.from == "all" and "" or (FromText() .. " ")) .. "sales or purchases "
            .. (state.period == "all" and "yet." or "in this time."))
        local earned, spent = OAL.Totals(since, state.from)
        self.total:SetText("Earned " .. OAL.Money(earned) .. ", spent " .. OAL.Money(spent) .. ".  "
            .. "|cff999999\"Each\" is the average price of one.|r")
    end
end

-- Categories tab ---------------------------------------------------------------------------------

local function ItemPicker(parent)
    local p = Box(parent, "Interface\\DialogFrame\\UI-DialogBox-Background")
    p:SetSize(260, 420)
    p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:Hide()
    local title = Label(p, "Items you've sold or bought")
    title:SetPoint("TOPLEFT", 12, -12)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    local hint = Label(p, "Click one to add it to the category.", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 12, -30)
    p.table = Table(p, 236, 360, { { title = "Item", width = 206 } })
    p.table:SetPoint("TOPLEFT", 12, -46)

    function p:Refresh()
        local cat = SelectedCategory()
        if not cat then self:Hide() return end
        local list = {}
        for name, it in pairs(OAL.Items()) do
            if not cat.items[name] then list[#list + 1] = it end
        end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
        local rows = {}
        for _, it in ipairs(list) do
            rows[#rows + 1] = {
                cells = { it.name },
                icon = OAL.ItemIcon(it.name, it.id),
                id = OAL.ItemID(it.name, it.id),
                title = it.name,
                onClick = function() OAL.AddToCategory(cat, it.name, it.id) end,
            }
        end
        self.table:SetRows(rows, "Every item you've sold or bought is in this category already.")
    end
    p:SetScript("OnShow", function(self) self:Refresh() end)
    return p
end

-- finds items in your bags and bank with the game's bag search, to tick and add to the category
local function FindPanel(parent)
    local p = Box(parent, "Interface\\DialogFrame\\UI-DialogBox-Background")
    p:SetSize(290, 440)
    p:SetPoint("TOPLEFT", parent, "TOPRIGHT", 2, 0)
    p:SetFrameStrata("DIALOG")
    p:EnableMouse(true)
    p:SetClampedToScreen(true)
    p:Hide()
    local title = Label(p, "Find in your bags and bank")
    title:SetPoint("TOPLEFT", 12, -12)
    local close = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local word = EditBox(p, 170)
    word:SetPoint("TOPLEFT", 18, -36)
    Tooltip(word, "Look for", "Works like the search box on your bags, ex: mining, skinning, leather, herb, cloth.")
    local search = Button(p, "Search", 80, function() p:Run(word:GetText()) end)
    search:SetPoint("LEFT", word, "RIGHT", 6, 0)
    word:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        p:Run(self:GetText())
    end)
    word:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    p.status = Label(p, "", "GameFontHighlightSmall")
    p.status:SetPoint("TOPLEFT", 12, -62)
    p.status:SetWidth(266)
    p.status:SetWordWrap(true)

    p.table = Table(p, 266, 284, {
        { title = "Item", width = 168 },
        { title = "Where", width = 68 },
    })
    p.table:SetPoint("TOPLEFT", 12, -112)

    p.results, p.ticked = {}, {}
    local function Shown()
        local cat, list = SelectedCategory(), {}
        for _, r in ipairs(p.results) do
            if cat and not cat.items[r.name] then list[#list + 1] = r end
        end
        return list
    end

    local all = Button(p, "All", 50, function()
        for _, r in ipairs(Shown()) do p.ticked[r.name] = true end
        p:Refresh()
    end)
    all:SetPoint("BOTTOMLEFT", 12, 12)
    local none = Button(p, "None", 50, function()
        wipe(p.ticked)
        p:Refresh()
    end)
    none:SetPoint("LEFT", all, "RIGHT", 2, 0)
    local add = Button(p, "Add ticked", 110, function()
        local cat = SelectedCategory()
        if not cat then return end
        for _, r in ipairs(Shown()) do
            if p.ticked[r.name] then OAL.AddToCategory(cat, r.name, r.id) end
        end
    end)
    add:SetPoint("BOTTOMRIGHT", -12, 12)
    p.add = add

    function p:Open()
        local cat = SelectedCategory()
        if not cat then return end
        self:Show()
        word:SetText(cat.name)
        self:Run(cat.name)
    end

    function p:Run(text)
        text = OAL.Trim(text)
        if text == "" or self.searching then return end
        self.word = text
        self.searching = true
        wipe(self.results)
        self:Refresh()
        OAL.Find(text, function(results, gameSearch)
            self.searching = false
            self.results = results
            self.gameSearch = gameSearch
            wipe(self.ticked)
            for _, r in ipairs(results) do self.ticked[r.name] = true end
            self:Refresh()
        end)
    end

    function p:Refresh()
        local list = Shown()
        local rows, ticked = {}, 0
        for _, r in ipairs(list) do
            local on = self.ticked[r.name] and true or false
            if on then ticked = ticked + 1 end
            rows[#rows + 1] = {
                cells = { (on and "" or "|cff808080") .. r.name .. (on and "" or "|r"), r.where },
                icon = OAL.ItemIcon(r.name, r.id),
                id = OAL.ItemID(r.name, r.id),
                title = r.name,
                lines = { { "You have", tostring(r.n) } },
                selected = on,
                onClick = function()
                    self.ticked[r.name] = not on or nil
                    self:Refresh()
                end,
            }
        end
        local bank = OAL.BankState()
        local bankNote = bank == "open" and "" or bank == "remembered" and " The bank is as it was at your last visit."
            or " Visit your bank once so it can be searched too."
        if self.searching then
            self.status:SetText("Searching...")
        elseif not self.word then
            self.status:SetText("")
        elseif #list == 0 then
            self.status:SetText("Nothing " .. (#self.results > 0 and "new " or "") .. "matches \"" .. self.word
                .. "\"." .. bankNote)
        else
            self.status:SetText(#list .. " found. Click an item to untick or tick it." .. bankNote
                .. (self.gameSearch and "" or " |cffff8080(Matched by name and type only.)|r"))
        end
        self.table:SetRows(rows, "")
        self.add:SetEnabled(ticked > 0)
    end
    return p
end

local function CategoriesPanel(p)
    local LEFT = 204
    local right = WIDTH - 28 - LEFT - 8

    p.list = Table(p, LEFT, HEIGHT - 82 - 14 - 28, { { title = "Categories", width = LEFT - 30 } },
        { noIcon = true })
    p.list:SetPoint("TOPLEFT")
    local new = Button(p, "New...", 62, function() StaticPopup_Show("OPCOWS_AUCTION_LEDGER_NEW") end)
    new:SetPoint("BOTTOMLEFT", 0, 0)
    local rename = Button(p, "Rename...", 76, function()
        local cat = SelectedCategory()
        if cat then StaticPopup_Show("OPCOWS_AUCTION_LEDGER_RENAME", cat.name, nil, cat) end
    end)
    rename:SetPoint("LEFT", new, "RIGHT", 2, 0)
    local delete = Button(p, "Delete", 62, function()
        local cat = SelectedCategory()
        if cat then StaticPopup_Show("OPCOWS_AUCTION_LEDGER_DELETE", cat.name, nil, cat) end
    end)
    delete:SetPoint("LEFT", rename, "RIGHT", 2, 0)
    p.rename, p.delete = rename, delete

    local none = Label(p, "Make a category with New..., ex: Mining, then add the items you sell or buy: "
        .. "ore, bars, stone. An item can be in as many categories as you like.", "GameFontHighlight")
    none:SetPoint("TOPLEFT", LEFT + 16, -30)
    none:SetWidth(right - 24)
    none:SetWordWrap(true)
    p.none = none

    local side = CreateFrame("Frame", nil, p)
    side:SetPoint("TOPLEFT", LEFT + 8, 0)
    side:SetPoint("BOTTOMRIGHT")
    p.side = side

    side.name = Label(side, "", "GameFontNormalLarge")
    side.name:SetPoint("TOPLEFT", 4, -2)
    side.totals = Label(side, "", "GameFontHighlight")
    side.totals:SetPoint("TOPLEFT", 4, -24)

    local function DropItem()
        local cat = SelectedCategory()
        local kind, id, link = GetCursorInfo()
        if not cat or kind ~= "item" then return end
        local name, itemID = OAL.ParseItem(link or tostring(id))
        ClearCursor()
        if name then OAL.AddToCategory(cat, name, itemID or id) end
    end

    side.table = Table(side, right, HEIGHT - 82 - 14 - 50 - 54, {
        { title = "Item", width = 190 },
        { title = "Earned", width = 100, justify = "RIGHT" },
        { title = "Spent", width = 100, justify = "RIGHT" },
    }, { remove = true, removeText = "Take this item out of the category.", onDrop = DropItem })
    side.table:SetPoint("TOPLEFT", 0, -50)

    local addLabel = Label(side, "Add an item:", "GameFontNormalSmall")
    addLabel:SetPoint("BOTTOMLEFT", 4, 34)
    local addBox = EditBox(side, 170)
    addBox:SetPoint("LEFT", addLabel, "RIGHT", 10, 0)
    local function AddTyped()
        local cat = SelectedCategory()
        local name, id = OAL.ParseItem(addBox:GetText())
        if cat and name then
            OAL.AddToCategory(cat, name, id)
            addBox:SetText("")
        end
        addBox:ClearFocus()
    end
    addBox:SetScript("OnEnterPressed", AddTyped)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    Tooltip(addBox, "Add an item", "Type the item's name, or click here and Shift-click the item in your "
        .. "bags, then press Enter.")
    win.addBox = addBox
    local add = Button(side, "Add", 50, AddTyped)
    add:SetPoint("LEFT", addBox, "RIGHT", 4, 0)
    local picker = ItemPicker(win)
    p.picker = picker
    local finder = FindPanel(win)
    p.finder = finder
    local fromLedger = Button(side, "From the ledger...", 130, function()
        finder:Hide()
        picker:SetShown(not picker:IsShown())
        if picker:IsShown() then picker:Refresh() end
    end)
    fromLedger:SetPoint("LEFT", add, "RIGHT", 4, 0)
    Tooltip(fromLedger, "From the ledger", "Pick from the items you've sold or bought.")
    local find = Button(side, "Find in bags...", 130, function()
        picker:Hide()
        if finder:IsShown() then finder:Hide() else finder:Open() end
    end)
    find:SetPoint("BOTTOMRIGHT", 0, 2)
    Tooltip(find, "Find in your bags and bank", "Search your bags and bank the way the bags' search box does, "
        .. "ex: mining, skinning, leather. It starts with the category's name. Tick what you want and add it.")
    local dropHint = Label(side, "You can also drag an item from your bags onto the list.", "GameFontDisableSmall")
    dropHint:SetPoint("BOTTOMLEFT", 4, 8)

    function p:Refresh()
        local cat = SelectedCategory()
        local items = OAL.Items(OAL.Since(state.period), state.from)
        local rows = {}
        for _, c in ipairs(OAL.Categories()) do
            rows[#rows + 1] = {
                cells = { c.name },
                selected = c == cat,
                onClick = function()
                    state.cat = c
                    OAL.Changed()
                end,
            }
        end
        self.list:SetRows(rows, "No categories yet.")
        self.rename:SetEnabled(cat ~= nil)
        self.delete:SetEnabled(cat ~= nil)
        self.none:SetShown(cat == nil)
        self.side:SetShown(cat ~= nil)
        if not cat then
            self.picker:Hide()
            self.finder:Hide()
            return
        end

        side.name:SetText(cat.name)
        local earned, spent, sn, bn = OAL.CategoryTotals(cat, items)
        side.totals:SetText("Earned " .. OAL.Money(earned) .. " |cff999999(" .. sn .. " sold)|r     Spent "
            .. OAL.Money(spent) .. " |cff999999(" .. bn .. " bought)|r")
        local list = {}
        for name, id in pairs(cat.items) do
            list[#list + 1] = items[name] or { name = name, id = id, sn = 0, sg = 0, bn = 0, bg = 0 }
        end
        table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
        local itemRows = {}
        for _, it in ipairs(list) do
            local stored = cat.items[it.name]
            local id = OAL.ItemID(it.name, it.id or (stored ~= 0 and stored or nil))
            itemRows[#itemRows + 1] = {
                cells = { it.name, it.sn > 0 and OAL.Money(it.sg) or "", it.bn > 0 and OAL.Money(it.bg) or "" },
                icon = OAL.ItemIcon(it.name, id),
                id = id,
                title = it.name,
                lines = ItemLines(it),
                onRemove = function() OAL.RemoveFromCategory(cat, it.name) end,
            }
        end
        side.table:SetRows(itemRows, "No items yet. Add the items this category covers: type a name below, "
            .. "Shift-click one into the box, drag one here from your bags, pick from the ledger, or find "
            .. "them in your bags.")
        if self.picker:IsShown() then self.picker:Refresh() end
        if self.finder:IsShown() then self.finder:Refresh() end
    end
end

-- Profit tab -------------------------------------------------------------------------------------

-- gold that can be less than nothing, green or red
local function Signed(copper)
    if math.floor(copper + 0.5) == 0 then return "0" end
    if copper < 0 then return "|cffff6060-|r" .. OAL.Money(-copper) end
    return OAL.Money(copper)
end

local function Margin(profit, g)
    if g <= 0 then return "" end
    local m = math.floor(profit / g * 100 + 0.5)
    return (m < 0 and "|cffff6060" or "|cff40ff40") .. m .. "%|r"
end

local function ProfitLines(it)
    local lines = {
        { "Sold " .. it.n, OAL.Money(it.g) },
        { "Cost", OAL.Money(it.cost) },
        { "Profit", Signed(it.g - it.cost) },
    }
    if it.n > 0 then lines[#lines + 1] = { "  each, on average", Signed((it.g - it.cost) / it.n) } end
    if it.free > 0 then
        lines[#lines + 1] = "|cff999999" .. it.free .. " of them weren't bought (gathered, looted, crafted from "
            .. "those, or from before the ledger), so they cost their market value.|r"
    end
    return lines
end

local CHART_TEXT = { hour = "%H:00", day = "%b %d", week = "Week of %b %d" }

-- bars of profit over time, green up and red down from the zero line
local function Chart(parent, width, height)
    local c = Box(parent)
    c:SetSize(width, height)
    local plot = CreateFrame("Frame", nil, c)
    plot:SetPoint("TOPLEFT", 8, -8)
    plot:SetPoint("BOTTOMRIGHT", -8, 20)
    c.zero = plot:CreateTexture(nil, "ARTWORK")
    c.zero:SetColorTexture(0.6, 0.6, 0.6, 0.8)
    c.zero:SetHeight(1)
    c.top = Label(c, "", "GameFontDisableSmall")
    c.top:SetPoint("TOPLEFT", 10, -8)
    c.first = Label(c, "", "GameFontDisableSmall")
    c.first:SetPoint("BOTTOMLEFT", 10, 6)
    c.last = Label(c, "", "GameFontDisableSmall")
    c.last:SetPoint("BOTTOMRIGHT", -10, 6)
    c.last:SetJustifyH("RIGHT")
    c.empty = Label(c, "", "GameFontDisableSmall")
    c.empty:SetPoint("CENTER")
    c.bars = {}

    local function Bar(i)
        local b = CreateFrame("Frame", nil, plot)
        b:EnableMouse(true)
        b.tex = b:CreateTexture(nil, "ARTWORK")
        b.hl = b:CreateTexture(nil, "BACKGROUND")
        b.hl:SetAllPoints()
        b.hl:SetColorTexture(1, 1, 1, 0.08)
        b.hl:Hide()
        b:SetScript("OnEnter", function(self)
            self.hl:Show()
            local d = self.data
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(date(CHART_TEXT[c.unit], d.from))
            GameTooltip:AddDoubleLine("Sold " .. d.n, OAL.Money(d.g), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Cost", OAL.Money(d.cost), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:AddDoubleLine("Profit", Signed(d.g - d.cost), 1, 0.82, 0, 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function(self)
            self.hl:Hide()
            GameTooltip:Hide()
        end)
        c.bars[i] = b
        return b
    end

    -- series = OAL.ProfitSeries's
    function c:Set(series, title)
        local buckets = series.buckets
        self.unit = series.unit
        local hi, lo, any = 0, 0, false
        for _, d in ipairs(buckets) do
            local p = d.g - d.cost
            hi, lo = math.max(hi, p), math.min(lo, p)
            if d.n > 0 then any = true end
        end
        local w, h = plot:GetWidth(), plot:GetHeight()
        if w <= 0 then w, h = width - 16, height - 28 end
        local span = hi - lo
        if span <= 0 then span = 1 end
        local zeroY = (-lo / span) * h  -- from the bottom
        self.zero:ClearAllPoints()
        self.zero:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", 0, zeroY)
        self.zero:SetPoint("RIGHT", plot, "RIGHT")
        local step = w / #buckets
        for i, d in ipairs(buckets) do
            local b = self.bars[i] or Bar(i)
            b.data = d
            b:ClearAllPoints()
            b:SetPoint("BOTTOMLEFT", plot, "BOTTOMLEFT", (i - 1) * step, 0)
            b:SetSize(step, h)
            local p = d.g - d.cost
            local bh = math.abs(p) / span * h
            b.tex:ClearAllPoints()
            b.tex:SetWidth(math.max(1, step - math.max(1, math.floor(step * 0.2))))
            b.tex:SetHeight(math.max(1, bh))
            if p >= 0 then
                b.tex:SetPoint("BOTTOM", b, "BOTTOM", 0, zeroY)
                b.tex:SetColorTexture(0.25, 0.8, 0.25, 0.9)
            else
                b.tex:SetPoint("TOP", b, "BOTTOM", 0, zeroY)
                b.tex:SetColorTexture(0.9, 0.3, 0.3, 0.9)
            end
            b.tex:SetShown(d.n > 0)
            b:Show()
        end
        for i = #buckets + 1, #self.bars do self.bars[i]:Hide() end
        self.top:SetText((title or "Profit") .. " by the " .. self.unit .. (hi > 0 and ("  |cff999999best: "
            .. OAL.Money(hi) .. "|r") or "") .. (lo < 0 and ("  |cff999999worst: " .. Signed(lo) .. "|r") or ""))
        self.first:SetText(date(CHART_TEXT[self.unit], buckets[1].from))
        self.last:SetText(date(CHART_TEXT[self.unit], buckets[#buckets].from))
        self.empty:SetText(any and "" or "No sales in this time.")
    end
    return c
end

local function ProfitPanel(p)
    state.psort, state.pdesc, state.view = "p", true, "item"

    p.total = Label(p, "", "GameFontHighlight")
    p.total:SetPoint("TOPLEFT", 4, -4)

    local whoButton = Button(p, "", 120, function()
        state.who = state.who == "all" and OAL.CharName() or "all"
        p:Refresh()
    end)
    whoButton:SetPoint("TOPRIGHT", 0, 0)
    Tooltip(whoButton, "Characters", "Count the sales of all your characters, or only this one's. The cost of "
        .. "an item is worked out from all your characters either way, since items get mailed between them.")
    local viewButton = Button(p, "", 100, function()
        state.view = state.view == "item" and "category" or "item"
        state.pick = nil
        p:Refresh()
    end)
    viewButton:SetPoint("RIGHT", whoButton, "LEFT", -4, 0)
    p.viewButton, p.whoButton = viewButton, whoButton
    Tooltip(viewButton, "By item or by category", "List the profit of each item, or of each of your categories.")

    p.table = Table(p, WIDTH - 28, 210, {
        { title = "Item", width = 210, sort = "name" },
        { title = "Sold", width = 56, justify = "RIGHT", sort = "n" },
        { title = "Revenue", width = 104, justify = "RIGHT", sort = "g" },
        { title = "Cost", width = 104, justify = "RIGHT", sort = "cost" },
        { title = "Profit", width = 110, justify = "RIGHT", sort = "p" },
        { title = "Margin", width = 66, justify = "RIGHT", sort = "m" },
    }, {
        onSort = function(key)
            if state.psort == key then
                state.pdesc = not state.pdesc
            else
                state.psort, state.pdesc = key, key ~= "name"
            end
            p:Refresh()
        end,
    })
    p.table:SetPoint("TOPLEFT", 0, -28)

    p.chart = Chart(p, WIDTH - 28, 160)
    p.chart:SetPoint("TOPLEFT", 0, -244)

    local note = Label(p, "Cost is the average paid for the item by any of your characters. Items not bought "
        .. "cost their market value: their recent price in the ledger, else the vendor's. Crafted items cost "
        .. "what went into them. Click a row to chart only it.", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 4, 0)
    note:SetPoint("RIGHT", p, "RIGHT", -4, 0)
    note:SetWordWrap(true)

    local function Sort(list)
        local key, desc = state.psort, state.pdesc
        local function Value(it)
            if key == "p" then return it.g - it.cost end
            if key == "m" then return it.g > 0 and (it.g - it.cost) / it.g or -math.huge end
            return it[key]
        end
        table.sort(list, function(a, b)
            if key ~= "name" then
                local va, vb = Value(a), Value(b)
                if va ~= vb then
                    if desc then return va > vb end
                    return va < vb
                end
            end
            if key == "name" and desc then return a.name:lower() > b.name:lower() end
            return a.name:lower() < b.name:lower()
        end)
    end

    function p:Refresh()
        local since = OAL.Since(state.period)
        local items = OAL.ProfitItems(since, state.from, state.who)
        local byCat = state.view == "category"
        local list = {}
        if byCat then
            local inOne = {}
            for _, cat in ipairs(OAL.Categories()) do
                local sum = OAL.ProfitSum(items, cat)
                sum.name, sum.cat = cat.name, cat
                list[#list + 1] = sum
                for name in pairs(cat.items) do inOne[name] = true end
            end
            local rest = { n = 0, g = 0, cost = 0, free = 0, name = "(Not in a category)", rest = inOne }
            for name, it in pairs(items) do
                if not inOne[name] then
                    rest.n, rest.g, rest.cost, rest.free = rest.n + it.n, rest.g + it.g, rest.cost + it.cost,
                        rest.free + it.free
                end
            end
            if rest.n > 0 then list[#list + 1] = rest end
        else
            for _, it in pairs(items) do list[#list + 1] = it end
        end
        Sort(list)

        -- the row whose sales the chart shows, if one was clicked
        local pick = state.pick
        local rows = {}
        for _, it in ipairs(list) do
            local key = byCat and (it.cat or "rest") or it.name
            local profit = it.g - it.cost
            local row = {
                cells = { it.name, Count(it.n), OAL.Money(it.g), OAL.Money(it.cost), Signed(profit), Margin(profit, it.g) },
                title = it.name,
                lines = ProfitLines(it),
                selected = pick == key,
                onClick = function()
                    state.pick = state.pick ~= key and key or nil
                    p:Refresh()
                end,
            }
            if not byCat then
                row.icon = OAL.ItemIcon(it.name, it.id)
                row.id = OAL.ItemID(it.name, it.id)
            end
            rows[#rows + 1] = row
        end
        self.table.headers[1].text:SetText(byCat and "Category" or "Item")
        self.table:MarkSort(state.psort)
        self.table:SetRows(rows, byCat and #OAL.Categories() == 0 and "No categories yet. Make them on the "
            .. "Categories tab." or ("No " .. (state.from == "all" and "" or (FromText() .. " ")) .. "sales "
            .. (state.period == "all" and "yet." or "in this time.")))

        local sum = OAL.ProfitSum(items)
        local profit = sum.g - sum.cost
        self.total:SetText("Sold " .. OAL.Money(sum.g) .. "   Cost " .. OAL.Money(sum.cost) .. "   Profit "
            .. Signed(profit) .. (sum.g > 0 and ("  " .. Margin(profit, sum.g)) or ""))
        viewButton:SetText(byCat and "By category" or "By item")
        whoButton:SetText(state.who == "all" and "All characters" or "This character")

        -- the chart: everything, or the clicked row's
        local match, title
        if pick and byCat then
            if pick == "rest" then
                local inOne = {}
                for _, cat in ipairs(OAL.Categories()) do
                    for name in pairs(cat.items) do inOne[name] = true end
                end
                match = function(name) return not inOne[name] end
                title = "Profit of items not in a category"
            else
                match = function(name) return pick.items[name] ~= nil end
                title = "Profit of " .. pick.name
            end
        elseif pick then
            match = function(name) return name == pick end
            title = "Profit of " .. pick
        end
        self.chart:Set(OAL.ProfitSeries(state.period, state.from, state.who, match), title)
    end
end

-- Compare tab ------------------------------------------------------------------------------------

-- the category a Sell/Buy button shows, still there, or the nth one
local function PickedCategory(key, nth)
    local cats = OAL.Categories()
    for _, cat in ipairs(cats) do
        if cat == state[key] then return cat end
    end
    state[key] = cats[math.min(nth, #cats)]
    return state[key]
end

local function StepCategory(key, nth, dir)
    local cats = OAL.Categories()
    if #cats == 0 then return end
    state[key] = Step(cats, PickedCategory(key, nth), dir)
end

local function ComparePanel(p)
    local half = (WIDTH - 28 - 8) / 2

    local function CatButton(key, nth, text, tip)
        local label = Label(p, text, "GameFontNormal")
        local b = Button(p, "", 170, nil)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            StepCategory(key, nth, button == "RightButton" and -1 or 1)
            p:Refresh()
        end)
        b:SetPoint("LEFT", label, "RIGHT", 6, 0)
        Tooltip(b, text:gsub(":", ""), tip .. " Click for the next category, right-click for the one before.")
        return label, b
    end
    local sellLabel, sellButton = CatButton("sellCat", 1, "Sell:", "The category whose sales pay for the other, "
        .. "ex: Mining.")
    sellLabel:SetPoint("TOPLEFT", 4, -4)
    local buyLabel, buyButton = CatButton("buyCat", 2, "Buy:", "The category you buy instead of gathering, "
        .. "ex: Leather.")
    buyLabel:SetPoint("LEFT", sellButton, "RIGHT", 24, 0)
    p.sellButton, p.buyButton = sellButton, buyButton

    local whoButton = Button(p, "", 120, function()
        state.who = state.who == "all" and OAL.CharName() or "all"
        p:Refresh()
    end)
    whoButton:SetPoint("TOPRIGHT", 0, 0)
    Tooltip(whoButton, "Characters", "Count all your characters, or only this one.")

    p.lines = {}
    for i = 1, 4 do
        local l = Label(p, "", "GameFontHighlight")
        l:SetPoint("TOPLEFT", 4, -14 - i * 20)
        l:SetPoint("RIGHT", p, "RIGHT", -4, 0)
        l:SetWordWrap(false)
        p.lines[i] = l
    end

    local tableHeight = HEIGHT - 82 - 14 - 122 - 30
    p.sold = Table(p, half, tableHeight, {
        { title = "Sold", width = 130 },
        { title = "Count", width = 44, justify = "RIGHT" },
        { title = "Earned", width = 86, justify = "RIGHT" },
        { title = "Profit", width = 76, justify = "RIGHT" },
    })
    p.sold:SetPoint("TOPLEFT", 0, -122)
    p.bought = Table(p, half, tableHeight, {
        { title = "Bought", width = 140 },
        { title = "Count", width = 46, justify = "RIGHT" },
        { title = "Spent", width = 90, justify = "RIGHT" },
        { title = "Used", width = 60, justify = "RIGHT" },
    })
    p.bought:SetPoint("TOPRIGHT", 0, -122)

    local note = Label(p, "What you did in the time Show picks: the gold selling one category brought in, "
        .. "against the gold buying the other cost. \"Used\" is how many went into your crafts.",
        "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 4, 0)
    note:SetPoint("RIGHT", p, "RIGHT", -4, 0)
    note:SetWordWrap(true)

    local function Sorted(items, key)
        local list = {}
        for _, it in pairs(items) do
            if it[key] > 0 then list[#list + 1] = it end
        end
        table.sort(list, function(a, b)
            local ga, gb = key == "sn" and a.sg or a.bg, key == "sn" and b.sg or b.bg
            if ga ~= gb then return ga > gb end
            if a[key] ~= b[key] then return a[key] > b[key] end
            return a.name:lower() < b.name:lower()
        end)
        return list
    end

    function p:Refresh()
        local sell, buy = PickedCategory("sellCat", 1), PickedCategory("buyCat", 2)
        sellButton:SetText(sell and sell.name or "(no categories)")
        buyButton:SetText(buy and buy.name or "(no categories)")
        whoButton:SetText(state.who == "all" and "All characters" or "This character")
        local since = OAL.Since(state.period)
        local sItems, s = OAL.CompareSide(sell, since, state.from, state.who)
        local bItems, b = OAL.CompareSide(buy, since, state.from, state.who)

        local L = self.lines
        if not sell or not buy then
            L[1]:SetText("Make two categories on the Categories tab, ex: Mining and Leather, to compare selling")
            L[2]:SetText("one to buying the other.")
            L[3]:SetText("")
            L[4]:SetText("")
        else
            local profit = s.sg - s.scost
            L[1]:SetText("Selling " .. sell.name .. " earned " .. OAL.Money(s.sg) .. " |cff999999(" .. s.sn
                .. " sold)|r, " .. Signed(profit) .. " over what it cost.")
            L[2]:SetText("Buying " .. buy.name .. " cost " .. OAL.Money(b.bg) .. " |cff999999(" .. b.bn
                .. " bought)|r.")
            local net = s.sg - b.bg
            local paid = b.bg > 0 and ("  Selling " .. sell.name .. " paid for " .. math.floor(s.sg / b.bg * 100 + 0.5)
                .. "% of the " .. buy.name .. " you bought.") or ""
            L[3]:SetText("Left over: " .. Signed(net) .. "." .. paid)
            if b.un > 0 then
                local gathered = b.ufree > 0 and (", " .. b.ufree .. " not bought (gathered, or from before the "
                    .. "ledger), worth " .. OAL.Money(b.ufreeCost) .. " to buy") or ", all of them bought"
                L[4]:SetText("Your crafts used " .. b.un .. " " .. buy.name .. gathered .. ".")
            else
                L[4]:SetText("|cff999999No " .. buy.name .. " used in crafts in this time.|r")
            end
        end

        local rows = {}
        for _, it in ipairs(Sorted(sItems, "sn")) do
            rows[#rows + 1] = {
                cells = { it.name, Count(it.sn), OAL.Money(it.sg), Signed(it.sg - it.scost) },
                icon = OAL.ItemIcon(it.name, it.id),
                id = OAL.ItemID(it.name, it.id),
                title = it.name,
                lines = { { "Sold " .. it.sn, OAL.Money(it.sg) }, { "  each, on average", OAL.Money(it.sg / it.sn) },
                    { "Cost", OAL.Money(it.scost) } },
            }
        end
        self.sold:SetRows(rows, sell and ("No " .. sell.name .. " sold in this time.") or "")
        rows = {}
        for _, it in ipairs(Sorted(bItems, "bn")) do
            local lines = { { "Bought " .. it.bn, OAL.Money(it.bg) }, { "  each, on average", OAL.Money(it.bg / it.bn) } }
            if it.un > 0 then
                lines[#lines + 1] = { "Used in crafts", tostring(it.un) }
                if it.ufree > 0 then lines[#lines + 1] = { "  not bought", it.ufree .. " (" .. OAL.Money(it.ufreeCost) .. ")" } end
            end
            rows[#rows + 1] = {
                cells = { it.name, Count(it.bn), OAL.Money(it.bg), Count(it.un) },
                icon = OAL.ItemIcon(it.name, it.id),
                id = OAL.ItemID(it.name, it.id),
                title = it.name,
                lines = lines,
            }
        end
        self.bought:SetRows(rows, buy and ("No " .. buy.name .. " bought in this time.") or "")
    end
end

-- the window -------------------------------------------------------------------------------------

local TABS = { { "summary", "Summary" }, { "items", "Items" }, { "categories", "Categories" }, { "profit", "Profit" },
    { "compare", "Compare" } }

local function CreateWindow()
    local f = CreateFrame("Frame", "OpcowsLedgerWindow", UIParent, "BasicFrameTemplateWithInset")
    win = f
    f:SetSize(WIDTH, HEIGHT)
    f:SetPoint("CENTER")
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    table.insert(UISpecialFrames, "OpcowsLedgerWindow")

    local title = f.TitleText
    if not title then
        title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        title:SetPoint("TOP", 0, -5)
    end
    title:SetText("Opcow's Ledger")

    local who = Label(f, "", "GameFontHighlightSmall")
    who:SetPoint("TOPLEFT", 16, -32)

    f.panels, f.tabs = {}, {}
    for i, tab in ipairs(TABS) do
        local key = tab[1]
        local b = Button(f, tab[2], 78, function()
            state.tab = key
            f:Refresh()
        end)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 80, -50)
        f.tabs[key] = b
        local p = CreateFrame("Frame", nil, f)
        p:SetPoint("TOPLEFT", 14, -82)
        p:SetPoint("BOTTOMRIGHT", -14, 14)
        p:Hide()
        f.panels[key] = p
    end

    local period = Button(f, "", 120, nil)
    period:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    period:SetScript("OnClick", function(_, button)
        state.period = Step(OAL.PERIODS, state.period, button == "RightButton" and -1 or 1)
        f:Refresh()
    end)
    period:SetPoint("TOPRIGHT", -14, -50)
    Tooltip(period, "Show", "Which sales and purchases the totals count. Click for the next choice, "
        .. "right-click for the one before.")
    local periodLabel = Label(f, "Show:", "GameFontNormalSmall")
    periodLabel:SetPoint("RIGHT", period, "LEFT", -6, 0)

    local from = Button(f, "", 110, nil)
    from:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    from:SetScript("OnClick", function(_, button)
        state.from = Step(OAL.SOURCES, state.from, button == "RightButton" and -1 or 1)
        f:Refresh()
    end)
    from:SetPoint("TOPRIGHT", -190, -50)
    Tooltip(from, "From", "Which sales and purchases to count: all of them, or only the auction house's, "
        .. "vendors', trades' or COD mail's. Click for the next choice, right-click for the one before.")
    local fromLabel = Label(f, "From:", "GameFontNormalSmall")
    fromLabel:SetPoint("RIGHT", from, "LEFT", -6, 0)

    SummaryPanel(f.panels.summary)
    ItemsPanel(f.panels.items)
    CategoriesPanel(f.panels.categories)
    ProfitPanel(f.panels.profit)
    ComparePanel(f.panels.compare)

    function f:Refresh()
        who:SetText(OAL.CharName())
        for key, p in pairs(self.panels) do
            p:SetShown(key == state.tab)
            if key == state.tab then
                self.tabs[key]:LockHighlight()
            else
                self.tabs[key]:UnlockHighlight()
            end
        end
        if state.tab ~= "categories" then
            self.panels.categories.picker:Hide()
            self.panels.categories.finder:Hide()
        end
        period:SetText(OAL.PERIOD_TEXT[state.period])
        from:SetText(OAL.SOURCE_TEXT[state.from])
        period:SetShown(state.tab ~= "summary")
        periodLabel:SetShown(state.tab ~= "summary")
        self.panels[state.tab]:Refresh()
    end

    f:SetScript("OnShow", function(self) self:Refresh() end)
    return f
end

function OAL.RefreshWindow()
    if win and win:IsShown() then win:Refresh() end
end

function OAL.ToggleWindow()
    win = win or CreateWindow()
    win:SetShown(not win:IsShown())
end

-- Shift-clicking an item while the "Add an item" box has focus puts the item's link in it
local function OnInsertLink(link)
    local box = win and win.addBox
    if box and box:IsVisible() and box:HasFocus() and type(link) == "string" and link:find("item:") then
        box:SetText(link)
    end
end
if type(ChatEdit_InsertLink) == "function" then hooksecurefunc("ChatEdit_InsertLink", OnInsertLink) end
if ChatFrameUtil and type(ChatFrameUtil.InsertLink) == "function" then
    hooksecurefunc(ChatFrameUtil, "InsertLink", OnInsertLink)
end

-- addon compartment (the addons button by the minimap) -------------------------------------------

function OpcowsLedger_OnAddonCompartmentClick()
    OAL.ToggleWindow()
end

function OpcowsLedger_OnAddonCompartmentEnter(_, button)
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("Opcow's Ledger")
    GameTooltip:AddLine("Click: open the ledger", 1, 1, 1)
    local earned, spent = OAL.Totals(OAL.Since("today"))
    GameTooltip:AddLine("Today: earned " .. OAL.Money(earned) .. ", spent " .. OAL.Money(spent), 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

function OpcowsLedger_OnAddonCompartmentLeave()
    GameTooltip:Hide()
end

-- minimap button, drag to move it around the minimap ---------------------------------------------

local function PlaceMinimapButton()
    local angle = math.rad(OAL.DB().minimap.angle or 220)
    -- on the edge of the minimap, whatever size it is
    local w, h = Minimap:GetWidth() / 2 + 5, Minimap:GetHeight() / 2 + 5
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * w, math.sin(angle) * h)
end

local function CreateMinimapButton()
    local b = CreateFrame("Button", "OpcowsLedgerMinimapButton", Minimap)
    -- same layout as LibDBIcon so it matches other addons' buttons
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetPoint("CENTER")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetTexture(ICON)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetPoint("CENTER")
    -- round it off, or the square icon's corners show outside the border
    if b.CreateMaskTexture then
        local mask = b:CreateMaskTexture()
        mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(icon)
        icon:AddMaskTexture(mask)
    end
    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function() OpcowsLedger_OnAddonCompartmentClick() end)
    b:SetScript("OnEnter", function(self) OpcowsLedger_OnAddonCompartmentEnter(nil, self) end)
    b:SetScript("OnLeave", OpcowsLedger_OnAddonCompartmentLeave)
    b:SetScript("OnDragStart", function(self)
        GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            OAL.DB().minimap.angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
            PlaceMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    return b
end

function OAL.UpdateMinimap()
    if not Minimap then return end
    local hide = OAL.DB().minimap.hide
    if hide and not minimapButton then return end
    minimapButton = minimapButton or CreateMinimapButton()
    PlaceMinimapButton()
    minimapButton:SetShown(not hide)
end

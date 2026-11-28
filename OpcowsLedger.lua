-- Opcow's Ledger: keeps what each character makes selling and spends buying, per item and
-- per category the player sets up. Each entry says where it happened (e.src):
--   "ah"     the auction house (old entries have no src and are this)
--   "vendor" a merchant: selling, buying, buying back
--   "trade"  a trade window with another player, only when gold changed hands
--   "cod"    cash-on-delivery mail: paying for one, or the payment for one you sent
--
-- Auction house sales and purchases are read from its mail. A sale counts when its gold is taken
-- from the "Auction successful" mail (net, after the auction house's cut), and a purchase when its
-- item is taken from the "Auction won" mail. Taking is caught by hooking TakeInboxMoney,
-- TakeInboxItem and AutoLootMailItem, so it works with Blizzard's mailbox and with mail addons.
-- Vendor and trade entries are described where they're read, further down.

OpcowsLedger = OpcowsLedger or {}
local OAL = OpcowsLedger

local DAY = 24 * 60 * 60
-- the periods the window can show, in the order its button cycles through them
OAL.PERIODS = { "all", "30", "7", "today" }
OAL.PERIOD_TEXT = { all = "All time", ["30"] = "Last 30 days", ["7"] = "Last 7 days", today = "Today" }
-- where a sale or purchase happened, in the order the window's "From" button cycles through them
OAL.SOURCES = { "all", "ah", "vendor", "trade", "cod" }
OAL.SOURCE_TEXT = { all = "Everywhere", ah = "Auction house", vendor = "Vendor", trade = "Trade", cod = "COD mail" }

-- an entry's source; entries from before sources were kept are the auction house's
function OAL.Source(e)
    return e.src or "ah"
end

-- does an entry count for a source filter ("all" or nil: everything)
local function FromSource(e, src)
    return not src or src == "all" or OAL.Source(e) == src
end

local db    -- OpcowsLedgerDB: { chars = { [key] = { log } }, cats, minimap, debug }
local char  -- this character's part of it
local charKey

function OAL.Print(msg)
    print("|cff33ff99Ledger:|r " .. msg)
end

function OAL.Debug(msg)
    if db and db.debug then OAL.Print("|cff999999" .. msg .. "|r") end
end

function OAL.DB() return db end
function OAL.Char() return char end
function OAL.CharName() return charKey end

-- the window refreshes itself when the data changes; it replaces this when it's built
function OAL.Changed()
    if OAL.RefreshWindow then OAL.RefreshWindow() end
end

local function Trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end
OAL.Trim = Trim

-- money ------------------------------------------------------------------------------------------

local GOLD, SILVER, COPPER = "|cffffd700", "|cffc7c7cf", "|cffeda55f"

-- copper as "12g 3s 40c", leaving out the parts that are 0
function OAL.Money(copper)
    copper = math.floor((copper or 0) + 0.5)
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then
        parts[#parts + 1] = (BreakUpLargeNumbers and BreakUpLargeNumbers(g) or tostring(g)) .. GOLD .. "g|r"
    end
    if s > 0 then parts[#parts + 1] = s .. SILVER .. "s|r" end
    if c > 0 then parts[#parts + 1] = c .. COPPER .. "c|r" end
    if #parts == 0 then return "0" end
    return table.concat(parts, " ")
end

-- items ------------------------------------------------------------------------------------------

local ids = {}  -- item name → id, learned from links and the item cache

local function IdFromLink(link)
    return link and tonumber(link:match("item:(%d+)"))
end
OAL.IdFromLink = IdFromLink

-- the item's id, or nil while the game doesn't know the name yet
function OAL.ItemID(name, id)
    if not name then return id end
    if id and id > 0 then
        ids[name] = id
        return id
    end
    if ids[name] then return ids[name] end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local found = instant and instant(name)
    if found then ids[name] = found end
    return found
end

function OAL.ItemIcon(name, id)
    id = OAL.ItemID(name, id)
    local icon = id and ((C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
        or (GetItemIcon and GetItemIcon(id)))
    return icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- an item's name and id from a link, an item id, or a typed name
function OAL.ParseItem(text)
    text = Trim(text)
    if text == "" then return nil end
    local id = IdFromLink(text)
    local name = text:match("%[(.-)%]")
    if not id and text:match("^%d+$") then id = tonumber(text) end
    if id and not name then
        local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
        name = info and info(id)
        if not name then return nil end
    end
    name = name or text
    return name, OAL.ItemID(name, id)
end

-- totals -----------------------------------------------------------------------------------------

-- the time a period starts, or nil for all time
function OAL.Since(period)
    if period == "today" then
        local t = date("*t")
        return time() - (t.hour * 3600 + t.min * 60 + t.sec)
    elseif period == "7" then
        return time() - 7 * DAY
    elseif period == "30" then
        return time() - 30 * DAY
    end
end

-- per item name since a time, from a source (nil: all): { [name] = { name, id, sn, sg, bn, bg } }
-- sn/sg: how many sold and the gold made, bn/bg: how many bought and the gold spent
function OAL.Items(since, src)
    local items = {}
    for _, e in ipairs(char.log) do
        if (not since or e.t >= since) and FromSource(e, src) then
            local it = items[e.name]
            if not it then
                it = { name = e.name, sn = 0, sg = 0, bn = 0, bg = 0 }
                items[e.name] = it
            end
            it.id = it.id or e.id
            if e.k == "s" then
                it.sn, it.sg = it.sn + (e.n or 1), it.sg + (e.g or 0)
            else
                it.bn, it.bg = it.bn + (e.n or 1), it.bg + (e.g or 0)
            end
        end
    end
    return items
end

-- the whole log's totals since a time, from a source (nil: all): earned, spent, sales, purchases
function OAL.Totals(since, src)
    local earned, spent, sales, buys = 0, 0, 0, 0
    for _, e in ipairs(char.log) do
        if (not since or e.t >= since) and FromSource(e, src) then
            if e.k == "s" then
                earned, sales = earned + (e.g or 0), sales + 1
            else
                spent, buys = spent + (e.g or 0), buys + 1
            end
        end
    end
    return earned, spent, sales, buys
end

-- a category's totals from OAL.Items: earned, spent, sold count, bought count
function OAL.CategoryTotals(cat, items)
    local earned, spent, sn, bn = 0, 0, 0, 0
    for name in pairs(cat.items) do
        local it = items[name]
        if it then
            earned, spent, sn, bn = earned + it.sg, spent + it.bg, sn + it.sn, bn + it.bn
        end
    end
    return earned, spent, sn, bn
end

-- categories -------------------------------------------------------------------------------------
-- db.cats = { { name = "Mining", items = { ["Copper Ore"] = 2770 or 0 } }, ... }, shared by all
-- characters. Items are kept by name because that's what the auction house's mail gives.

function OAL.Categories()
    local list = {}
    for _, cat in ipairs(db.cats) do list[#list + 1] = cat end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    return list
end

local function FindCategory(name)
    for _, cat in ipairs(db.cats) do
        if cat.name:lower() == name:lower() then return cat end
    end
end

-- returns the category, or nil and why not
function OAL.AddCategory(name)
    name = Trim(name)
    if name == "" then return nil, "Type a name for the category." end
    if FindCategory(name) then return nil, "There's already a category called " .. name .. "." end
    local cat = { name = name, items = {} }
    table.insert(db.cats, cat)
    OAL.Changed()
    return cat
end

function OAL.RenameCategory(cat, name)
    name = Trim(name)
    if name == "" then return nil, "Type a name for the category." end
    local other = FindCategory(name)
    if other and other ~= cat then return nil, "There's already a category called " .. name .. "." end
    cat.name = name
    OAL.Changed()
    return cat
end

function OAL.DeleteCategory(cat)
    for i, c in ipairs(db.cats) do
        if c == cat then table.remove(db.cats, i) break end
    end
    OAL.Changed()
end

function OAL.AddToCategory(cat, name, id)
    if not cat or not name then return end
    cat.items[name] = OAL.ItemID(name, id) or 0
    OAL.Changed()
end

function OAL.RemoveFromCategory(cat, name)
    cat.items[name] = nil
    OAL.Changed()
end

-- the categories an item is in, as "Mining, Bars"
function OAL.CategoriesOf(name)
    local names = {}
    for _, cat in ipairs(OAL.Categories()) do
        if cat.items[name] then names[#names + 1] = cat.name end
    end
    return table.concat(names, ", ")
end

-- the auction house's mail -----------------------------------------------------------------------

-- a mail subject format such as "Auction successful: %s" as a pattern that captures the %s
local function SubjectPattern(fmt)
    if type(fmt) ~= "string" then return nil end
    local p = fmt:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    return "^" .. p .. "$"
end
local SOLD = SubjectPattern(AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s")
local WON = SubjectPattern(AUCTION_WON_MAIL_SUBJECT or "Auction won: %s")
local COD_PAID = SubjectPattern(COD_PAYMENT or "COD Payment: %s")

-- "Copper Bar (58)" → "Copper Bar", 58
local function NameCount(text)
    local name, count = (text or ""):match("^(.-) %((%d+)%)$")
    if name then return name, tonumber(count) end
    return text, nil
end

-- names without the realm, to match a mail's sender with who a COD mail went to
local function SameName(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    return a:match("^[^%-]+"):lower() == b:match("^[^%-]+"):lower()
end

-- The COD mails this character sent, kept until their payment comes back (or a month goes by):
-- char.codSent = { { to, subject, g, t, items = { { name, id, n } } } }
local function FindCodSent(sender, subject)
    local list = char and char.codSent
    if not list then return end
    local bySubject
    for i, c in ipairs(list) do
        if c.subject == subject then
            if SameName(c.to, sender) then return c, i end
            bySubject = bySubject or i
        end
    end
    if bySubject then return list[bySubject], bySubject end
end

-- a COD mail you received with items: what's attached, { { name, id, n } }
local function MailItems(i)
    local items = {}
    for a = 1, ATTACHMENTS_MAX_RECEIVE or 16 do
        local name, itemID, _, count = GetInboxItem(i, a)
        if name then
            local id = (GetInboxItemLink and IdFromLink(GetInboxItemLink(i, a))) or tonumber(itemID)
            items[#items + 1] = { name = name, id = OAL.ItemID(name, id), n = tonumber(count) or 1 }
        end
    end
    return items
end

-- a mail that isn't the auction house's: a COD mail to pay for, or a COD payment
local function ReadCod(i, sender, subject, money, cod, hasItem, sig)
    if (cod or 0) > 0 and hasItem and GetInboxItem then
        local items = MailItems(i)
        if #items == 0 then return end
        return {
            k = "b", src = "cod", who = sender, name = items[1].name, id = items[1].id, n = items[1].n,
            items = items, g = cod, subject = subject, sig = sig, invoice = true,
        }
    end
    local rest = COD_PAID and subject:match(COD_PAID)
    if not rest then return end
    local m = { k = "s", src = "cod", who = sender, g = money or 0, subject = subject, sig = sig, invoice = true }
    local sent = FindCodSent(sender, rest)
    if sent then
        m.items, m.sent = sent.items, sent
        m.name, m.id, m.n = sent.items[1].name, sent.items[1].id, sent.items[1].n
    else
        -- not sent from here (or before this version): the subject is usually the item's name
        local name, n = NameCount(rest)
        if not name or name == "" then return end
        m.name, m.n = name, n or 1
        m.id = OAL.ItemID(name)
        m.invoice = false
    end
    return m
end

-- what an inbox mail is, if it's a sale or a purchase:
-- { k = "s" or "b", name, id, n, g, subject, sig, src, who, items }, with g the gold the mail holds
-- (sale) or paid (purchase). sig tells this mail apart from others while it stays in the inbox.
-- items, for COD mail, is every item the gold is for.
local function ReadMail(i)
    if not GetInboxHeaderInfo then return end
    local _, _, sender, subject, money, cod, daysLeft, hasItem = GetInboxHeaderInfo(i)
    if type(subject) ~= "string" then return end
    local sig = subject .. "|" .. tostring(money) .. "|" .. tostring(cod) .. "|" .. tostring(daysLeft)
    local invoiceType, itemName, bid, buyout, deposit, cut, count
    local raw
    if GetInboxInvoiceInfo then
        raw = { GetInboxInvoiceInfo(i) }
        invoiceType, itemName, bid, buyout, deposit, cut, count = raw[1], raw[2], raw[4], raw[5], raw[6], raw[7], raw[10]
    end
    local kind, rest
    rest = SOLD and subject:match(SOLD)
    if rest then
        kind = "s"
    else
        rest = WON and subject:match(WON)
        if rest then kind = "b" end
    end
    if invoiceType == "seller" then
        kind = "s"
    elseif invoiceType == "buyer" then
        kind = "b"
    elseif invoiceType then
        return  -- a "sale pending" note or an outbid refund, not a sale or a purchase
    end
    if not kind then return ReadCod(i, sender, subject, money, cod, hasItem, sig) end

    -- "Copper Bar (58)" in the subject is the stack's size. It goes first: on Forever the invoice's
    -- count said 1 for a stack of 58.
    local subjectName, subjectCount = NameCount(rest)
    if not subjectCount then subjectName = nil end
    local name = itemName or subjectName or rest
    if not name or name == "" then return end
    local n = subjectCount or tonumber(count) or 1
    if n < 1 then n = 1 end

    local g, id
    if kind == "s" then
        g = money or 0
        if g <= 0 and bid and bid > 0 then
            g = bid + (deposit or 0) - (cut or 0)
            if money then g = 0 end  -- the header says the gold is gone: it was taken already
        end
    else
        g = (bid and bid > 0 and bid) or buyout or 0
        id = GetInboxItemLink and IdFromLink(GetInboxItemLink(i, 1))
        -- the attached stack's size is surer than the invoice's count
        local attached = GetInboxItem and select(4, GetInboxItem(i, 1))
        if not subjectCount and tonumber(attached) and attached > 0 then n = attached end
    end
    id = OAL.ItemID(name, id)
    return {
        k = kind, src = "ah", name = name, id = id, n = n, g = g, subject = subject, sig = sig,
        invoice = invoiceType ~= nil,
        raw = raw,
    }
end
OAL.ReadMail = ReadMail

-- The inbox as it was at the last update: the hooks run after the take is sent, and if the client
-- already cleared the mail by then, this still has it.
local snapshot = {}
-- mails counted and not gone yet, [index] = sig, so a second click before the server answers
-- doesn't count them twice
local counted = {}
local lastCount

local function InboxCount()
    if not GetInboxNumItems then return 0, 0 end
    local shown, total = GetInboxNumItems()
    return shown or 0, total or shown or 0
end

local function Snapshot()
    local shown, total = InboxCount()
    if total ~= lastCount then
        wipe(counted)  -- mails came or went, so the indexes moved
    else
        for i, sig in pairs(counted) do
            local m = ReadMail(i)
            if not m or m.sig ~= sig then counted[i] = nil end
        end
    end
    lastCount = total
    wipe(snapshot)
    for i = 1, shown do
        snapshot[i] = ReadMail(i)
    end
end

-- an item's vendor price for one, or nil if the game doesn't know it (yet)
local function SellPrice(name, id)
    local info = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not info then return end
    local price = select(11, info(id or name))
    return tonumber(price)
end
OAL.SellPrice = SellPrice

-- How the gold of one sale or purchase is shared out when it was for several items: by their vendor
-- price when the game knows it for all of them, otherwise evenly. The same item twice is one entry.
-- items = { { name, id, n } }; returns { { name, id, n, g } }
local function Split(items, g)
    local list, byName = {}, {}
    for _, it in ipairs(items) do
        local e = byName[it.name]
        if e then
            e.n = e.n + (it.n or 1)
        else
            e = { name = it.name, id = it.id, n = it.n or 1 }
            byName[it.name] = e
            list[#list + 1] = e
        end
    end
    if #list == 1 then
        list[1].g = g
        return list
    end
    local weights, total = {}, 0
    for i, e in ipairs(list) do
        local price = SellPrice(e.name, e.id)
        if not price or price <= 0 then
            weights, total = nil, 0
            break
        end
        weights[i] = price * e.n
        total = total + weights[i]
    end
    local left = g
    for i, e in ipairs(list) do
        if i == #list then
            e.g = left  -- what rounding left over goes to the last one
        else
            e.g = math.floor(g * (weights and weights[i] / total or 1 / #list))
            left = left - e.g
        end
    end
    return list
end
OAL.Split = Split

local KIND_TEXT = { s = "Sold ", b = "Bought " }

-- puts a sale (k "s") or purchase (k "b") in the log: src, who (the other player or the vendor),
-- items = { { name, id, n } } and the gold for all of them. note goes on the debug line.
local function RecordItems(k, src, who, items, g, note)
    if not char or not items or #items == 0 then return end
    for _, it in ipairs(Split(items, g)) do
        local e = { t = time(), k = k, src = src, who = who, name = it.name, id = OAL.ItemID(it.name, it.id),
            n = it.n, g = it.g }
        table.insert(char.log, e)
        OAL.Debug(KIND_TEXT[k] .. it.name .. (it.n > 1 and (" x" .. it.n) or "") .. " for " .. OAL.Money(it.g)
            .. " (" .. OAL.SOURCE_TEXT[src] .. (who and (", " .. who) or "") .. ")" .. (note or ""))
    end
    OAL.Changed()
end
OAL.RecordItems = RecordItems

local function Record(m)
    RecordItems(m.k, m.src or "ah", m.who, m.items or { { name = m.name, id = m.id, n = m.n } }, m.g,
        not m.invoice and (m.src == "cod" and " (read from the subject)" or " (no invoice, read from the subject)"))
    if m.sent then
        for i, c in ipairs(char.codSent) do
            if c == m.sent then table.remove(char.codSent, i) break end
        end
    end
end

-- how: "money" (TakeInboxMoney), "item" (TakeInboxItem) or "all" (AutoLootMailItem)
local function OnTake(i, how)
    if type(i) ~= "number" or not char then return end
    local m = ReadMail(i)
    local s = snapshot[i]
    if s and (not m or (m.k == "s" and m.g <= 0 and s.subject == m.subject)) then m = s end
    if not m then return end
    if (m.k == "s" and how == "item") or (m.k == "b" and how == "money") then return end
    if m.k == "s" and m.g <= 0 then
        OAL.Debug("No gold left in the mail for " .. m.name .. ", not counted.")
        return
    end
    if counted[i] == m.sig then
        OAL.Debug(m.name .. " was counted already.")
        return
    end
    counted[i] = m.sig
    if m.k == "b" and m.g <= 0 then
        OAL.Debug("The price paid for " .. m.name .. " isn't in the mail, counted as 0.")
    end
    Record(m)
end

local function HookTakes()
    local takes = { TakeInboxMoney = "money", TakeInboxItem = "item", AutoLootMailItem = "all" }
    for fn, how in pairs(takes) do
        if type(_G[fn]) == "function" then
            hooksecurefunc(fn, function(i) OnTake(i, how) end)
        end
        -- newer clients may have them in C_Mail too; counted[] stops a mail counting twice
        if C_Mail and type(C_Mail[fn]) == "function" then
            hooksecurefunc(C_Mail, fn, function(i) OnTake(i, how) end)
        end
    end
end

-- sending a COD mail: remember what it holds, so the payment that comes back can name the items
local COD_KEEP = 31 * DAY

local function OnSendMail(to, subject)
    if not char or not GetSendMailCOD or not GetSendMailItem then return end
    local cod = tonumber(GetSendMailCOD()) or 0
    if cod <= 0 then return end
    -- SendMail and C_Mail.SendMail can both come through for one send
    local key = tostring(to) .. "|" .. tostring(subject) .. "@" .. GetTime()
    if OAL.lastSend == key then return end
    OAL.lastSend = key
    local items = {}
    for a = 1, ATTACHMENTS_MAX_SEND or 12 do
        local name, itemID, _, count = GetSendMailItem(a)
        if name then
            local id = (GetSendMailItemLink and IdFromLink(GetSendMailItemLink(a))) or tonumber(itemID)
            items[#items + 1] = { name = name, id = OAL.ItemID(name, id), n = tonumber(count) or 1 }
        end
    end
    if #items == 0 then return end
    char.codSent = char.codSent or {}
    table.insert(char.codSent, { to = to, subject = subject or "", g = cod, t = time(), items = items })
    OAL.Debug("Sent " .. items[1].name .. (#items > 1 and (" and " .. (#items - 1) .. " more") or "")
        .. " COD for " .. OAL.Money(cod) .. " to " .. tostring(to) .. ". It counts when the payment is taken.")
end

-- vendors ----------------------------------------------------------------------------------------
-- Buying (BuyMerchantItem), buying back (BuybackItem), selling (UseContainerItem while a merchant is
-- open) and selling junk are hooked; each leaves a note of what it was for. The gold it cost or made
-- comes from the money change (PLAYER_MONEY) that follows, so the price is what was really paid,
-- discounts and all. A money change with no note is something else, ex: a repair, and isn't counted.
-- Items bought with tokens or other items cost no gold and aren't counted.

local Vendor = { pending = {}, WAIT = 5 }
OAL.Vendor = Vendor

function Vendor.Note(k, name, id, n, expect, extra)
    if not name then return end
    local p = { k = k, name = name, id = id, n = n or 1, expect = expect, at = GetTime() }
    if extra then
        for key, v in pairs(extra) do p[key] = v end
    end
    table.insert(Vendor.pending, p)
end

local function MerchantInfo(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(index)
        if type(info) == "table" then return info.name, info.price, info.stackCount end
    end
    if GetMerchantItemInfo then
        local name, _, price, stack = GetMerchantItemInfo(index)
        return name, price, stack
    end
end

function Vendor.Buy(index, quantity)
    if not Vendor.open then return end
    local name, price, stack = MerchantInfo(index)
    price, stack = tonumber(price) or 0, tonumber(stack) or 1
    if not name or price <= 0 then return end  -- bought with tokens or items, not gold
    if stack < 1 then stack = 1 end
    local n = tonumber(quantity) or stack
    local link = GetMerchantItemLink and GetMerchantItemLink(index)
    Vendor.Note("b", name, IdFromLink(link), n, math.floor(price * n / stack + 0.5))
end

function Vendor.Buyback(index)
    if not Vendor.open or not GetBuybackItemInfo then return end
    local name, _, price, n = GetBuybackItemInfo(index)
    price = tonumber(price) or 0
    if not name or price <= 0 then return end
    local link = GetBuybackItemLink and GetBuybackItemLink(index)
    Vendor.Note("b", name, IdFromLink(link), tonumber(n) or 1, price, { buyback = true })
end

-- selling one bag slot's item: right-click at a merchant
function Vendor.Sell(bag, slot)
    if not Vendor.open or not C_Container or not C_Container.GetContainerItemInfo then return end
    -- the old name may call the new one, so one click can come through both hooks
    local key = tostring(bag) .. ":" .. tostring(slot) .. "@" .. GetTime()
    if Vendor.lastSell == key then return end
    Vendor.lastSell = key
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info or not info.hyperlink then return end
    local name = info.hyperlink:match("%[(.-)%]")
    local price = SellPrice(name, info.itemID)
    if price == 0 or info.hasNoValue then return end  -- the vendor won't pay for it
    local n = info.stackCount or 1
    Vendor.Note("s", name, info.itemID, n, price and price * n or nil)
end

-- the "sell all junk" button: every grey item in the bags
function Vendor.SellJunk()
    if not Vendor.open or not C_Container or not C_Container.GetContainerItemInfo then return end
    for bag = 0, NUM_BAG_SLOTS or 4 do
        local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
        for slot = 1, (ok and slots) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.quality == 0 and not info.hasNoValue then Vendor.Sell(bag, slot) end
        end
    end
end

-- a repair: the money change it makes isn't a purchase
function Vendor.Repair()
    if Vendor.open then
        table.insert(Vendor.pending, { k = "b", skip = true, at = GetTime() })
    end
end

-- a buyback undoes the sale it buys back: that sale comes out of the log, if it's there
local function UndoSale(p, g)
    for i = #char.log, math.max(1, #char.log - 50), -1 do
        local e = char.log[i]
        if e.k == "s" and e.src == "vendor" and e.name == p.name and e.g == g and (e.n or 1) == p.n then
            table.remove(char.log, i)
            OAL.Debug("Bought back " .. p.name .. ": its sale is taken out of the ledger.")
            OAL.Changed()
            return true
        end
    end
end

-- the money changed by delta; amount is matched with the oldest note of the same kind, or several
-- notes in a row when their prices add up to it (sales that came back as one money change)
function Vendor.Money(delta)
    local pending = Vendor.pending
    local now = GetTime()
    for i = #pending, 1, -1 do
        if now - pending[i].at > Vendor.WAIT then table.remove(pending, i) end
    end
    if delta == 0 or not char then return end
    local k, amount = delta > 0 and "s" or "b", math.abs(delta)
    local first
    for i, p in ipairs(pending) do
        if p.k == k then first = i break end
    end
    if not first then
        if Vendor.open then
            OAL.Debug("Money changed by " .. (delta < 0 and "-" or "") .. OAL.Money(amount)
                .. " at the vendor, not from buying or selling an item: not counted.")
        end
        return
    end
    local group, sum = { first }, pending[first].expect
    if sum and sum < amount then
        for i = first + 1, #pending do
            local p = pending[i]
            if p.k == k then
                if not p.expect then break end
                group[#group + 1] = i
                sum = sum + p.expect
                if sum >= amount then break end
            end
        end
    end
    if sum ~= amount then group = { first } end
    local taken = {}
    for j = #group, 1, -1 do
        table.insert(taken, 1, table.remove(pending, group[j]))
    end
    for _, p in ipairs(taken) do
        local g = #taken == 1 and amount or p.expect
        if p.skip then
            OAL.Debug("Repaired for " .. OAL.Money(g) .. ": not counted.")
        elseif not (p.buyback and UndoSale(p, g)) then
            RecordItems(k, "vendor", Vendor.who, { { name = p.name, id = p.id, n = p.n } }, g)
        end
    end
end

-- money --------------------------------------------------------------------------------------------

local lastMoney

local function MoneyChanged()
    local now = GetMoney and GetMoney()
    if type(now) ~= "number" then return end
    local delta = lastMoney and now - lastMoney or 0
    lastMoney = now
    if #Vendor.pending > 0 or Vendor.open then Vendor.Money(delta) end
end

-- trades -----------------------------------------------------------------------------------------
-- The trade window is read each time it changes. When the game says the trade is done, the gold
-- that changed hands decides what it was: more gold came to you than went, a sale of the items you
-- gave; more went, a purchase of the items you got. A trade where no gold changed hands (or the same
-- both ways) isn't counted, nor one of gold alone.

local Trade = {}
OAL.Trade = Trade

local function TradeItems(info, linkFn)
    local items = {}
    if not info then return items end
    for i = 1, MAX_TRADABLE_ITEMS or 6 do
        local name, _, n = info(i)
        if type(name) == "string" and name ~= "" then
            local id = linkFn and IdFromLink(linkFn(i))
            items[#items + 1] = { name = name, id = OAL.ItemID(name, id), n = tonumber(n) or 1 }
        end
    end
    return items
end

-- an empty window after a full one that someone accepted is the trade going through (the game may
-- clear it before it says the trade is done), so the full reading is kept.
function Trade.Read()
    local s = {
        who = Trade.who,
        giveMoney = tonumber(GetPlayerTradeMoney and GetPlayerTradeMoney()) or 0,
        getMoney = tonumber(GetTargetTradeMoney and GetTargetTradeMoney()) or 0,
        give = TradeItems(GetTradePlayerItemInfo, GetTradePlayerItemLink),
        get = TradeItems(GetTradeTargetItemInfo, GetTradeTargetItemLink),
    }
    local empty = s.giveMoney == 0 and s.getMoney == 0 and #s.give == 0 and #s.get == 0
    if empty and Trade.last and Trade.accepted then return end
    Trade.last = s
end

function Trade.Show()
    Trade.who = UnitName and UnitName("NPC") or nil
    Trade.last, Trade.accepted = nil, false
    Trade.Read()
end

-- TRADE_ACCEPT_UPDATE: 1 for each side that has accepted
function Trade.Accept(player, target)
    Trade.accepted = player == 1 or target == 1 or player == true or target == true
    Trade.Read()
end

-- UI_INFO_MESSAGE is (type, text) on newer clients, (text) on older ones
function Trade.Info(a, b)
    local done = ERR_TRADE_COMPLETE or "Trade complete."
    if a == done or b == done then Trade.Done() end
end

function Trade.Done()
    local s = Trade.last
    Trade.last = nil
    if not s or not char then return end
    local net = s.getMoney - s.giveMoney
    local who = s.who and (" with " .. s.who) or ""
    if net == 0 then
        OAL.Debug("Trade" .. who .. " done with no gold changing hands: not counted.")
        return
    end
    local k = net > 0 and "s" or "b"
    local items = net > 0 and s.give or s.get
    if #items == 0 then
        OAL.Debug("Trade" .. who .. " of gold only: not counted.")
        return
    end
    RecordItems(k, "trade", s.who, items, math.abs(net))
end

local TRADE_EVENTS = {
    TRADE_PLAYER_ITEM_CHANGED = true, TRADE_TARGET_ITEM_CHANGED = true, TRADE_MONEY_CHANGED = true,
    TRADE_ACCEPT_UPDATE = true, PLAYER_TRADE_MONEY = true,
}

local function HookVendor()
    local function Hook(fn, handler)
        if type(_G[fn]) == "function" then hooksecurefunc(fn, handler) end
    end
    Hook("BuyMerchantItem", Vendor.Buy)
    Hook("BuybackItem", Vendor.Buyback)
    Hook("RepairAllItems", Vendor.Repair)
    Hook("UseContainerItem", Vendor.Sell)
    Hook("SendMail", OnSendMail)
    if C_Container and type(C_Container.UseContainerItem) == "function" then
        hooksecurefunc(C_Container, "UseContainerItem", Vendor.Sell)
    end
    if C_MerchantFrame and type(C_MerchantFrame.SellAllJunkItems) == "function" then
        hooksecurefunc(C_MerchantFrame, "SellAllJunkItems", Vendor.SellJunk)
    end
    if C_Mail and type(C_Mail.SendMail) == "function" then
        hooksecurefunc(C_Mail, "SendMail", OnSendMail)
    end
end

-- forgets COD mails sent long ago, whose payment never came (returned, or taken before this version)
local function PruneCodSent()
    local list = char.codSent
    if not list then return end
    for i = #list, 1, -1 do
        if time() - (list[i].t or 0) > COD_KEEP then table.remove(list, i) end
    end
    if #list == 0 then char.codSent = nil end
end

-- searching your bags and bank -------------------------------------------------------------------
-- The game's own bag search (C_Container.SetItemSearch, the bag search box) marks each slot that
-- doesn't match as isFiltered. It knows more than the item data shows, ex: "mining" finds ore. The
-- bank can only be read while it's open, so its contents are remembered on each visit (char.bank)
-- and those are matched by name and item type.

local bankOpen

local function Container()
    return C_Container or {}
end

local function BagIDs()
    local list = {}
    for bag = 0, NUM_BAG_SLOTS or 4 do list[#list + 1] = bag end
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then list[#list + 1] = Enum.BagIndex.ReagentBag end
    return list
end
OAL.BagIDs = BagIDs

-- the bank's containers: the old bank and its bags, or the newer bank tabs
local function BankIDs()
    local list, seen = {}, {}
    local function Add(id)
        if type(id) == "number" and not seen[id] then
            seen[id] = true
            list[#list + 1] = id
        end
    end
    Add(BANK_CONTAINER or -1)
    local first = (NUM_BAG_SLOTS or 4) + 1
    for bag = first, first + (NUM_BANKBAGSLOTS or 7) - 1 do Add(bag) end
    if Enum and Enum.BagIndex then
        for key, id in pairs(Enum.BagIndex) do
            if type(key) == "string" and key:find("Bank") and not key:find("Account") then Add(id) end
        end
    end
    return list
end

-- calls fn(info) for each item in the containers, info being GetContainerItemInfo's table
local function EachItem(ids, fn)
    local C = Container()
    if not C.GetContainerNumSlots or not C.GetContainerItemInfo then return end
    for _, bag in ipairs(ids) do
        local ok, slots = pcall(C.GetContainerNumSlots, bag)
        for slot = 1, (ok and slots) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            if info and info.itemID then fn(info) end
        end
    end
end

local function LinkName(link)
    return link and link:match("%[(.-)%]")
end

-- remembers what's in the bank, [itemID] = { name, n }
local function RememberBank()
    if not bankOpen or not char then return end
    local bank = {}
    EachItem(BankIDs(), function(info)
        local name = LinkName(info.hyperlink)
        if name then
            local b = bank[info.itemID] or { name = name, n = 0 }
            b.n = b.n + (info.stackCount or 1)
            bank[info.itemID] = b
        end
    end)
    char.bank = bank
end

-- "open" at the bank, "remembered" after a visit, nil if never seen
function OAL.BankState()
    if bankOpen then return "open" end
    if char and char.bank then return "remembered" end
end

-- does the word match the item's name or type (ex: "Leather", "Metal & Stone", "Trade Goods")
local function NameMatch(word, name, id)
    word = word:lower()
    if name and name:lower():find(word, 1, true) then return true end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if instant and id then
        local _, itemType, subType = instant(id)
        for _, s in ipairs({ itemType, subType }) do
            if type(s) == "string" and s:lower():find(word, 1, true) then return true end
        end
    end
    return false
end

-- the text in Blizzard's bag search box, so it can be put back
local function CurrentSearch()
    local boxes = { _G.BagItemSearchBox, _G.BankItemSearchBox,
        _G.ContainerFrameCombinedBags and _G.ContainerFrameCombinedBags.SearchBox }
    for _, box in pairs(boxes) do
        if box and box.GetText then
            local text = box:GetText()
            if text and text ~= "" then return text end
        end
    end
    return ""
end

local searching       -- the frame waiting for the game's search, while one runs
local searchingPrev   -- the bag search box's text before it

-- Finds the items in your bags and bank that match a word, then calls
-- done(results, gameSearch) with results = { { name, id, n, where = "bags" / "bank" } } sorted by
-- name, gameSearch being whether the game's bag search worked.
function OAL.Find(word, done)
    word = Trim(word)
    if word == "" or searching then return end
    local C = Container()
    local found, gameWorked = {}, false

    local function Add(name, id, n, where)
        if not name then return end
        local r = found[name]
        if not r then
            r = { name = name, id = id, n = 0, where = where }
            found[name] = r
        elseif r.where ~= where then
            r.where = "bags, bank"
        end
        r.n = r.n + (n or 1)
    end

    local function Finish()
        if not searching then return end
        searching:UnregisterAllEvents()
        searching = nil
        local live = BagIDs()
        if bankOpen then
            for _, id in ipairs(BankIDs()) do live[#live + 1] = id end
        end
        local bankIDs = {}
        for _, id in ipairs(BankIDs()) do bankIDs[id] = true end
        for _, bag in ipairs(live) do
            EachItem({ bag }, function(info)
                local name = LinkName(info.hyperlink)
                local match = NameMatch(word, name, info.itemID)
                if info.isFiltered ~= nil then
                    gameWorked = true
                    match = match or not info.isFiltered
                end
                if match then Add(name, info.itemID, info.stackCount, bankIDs[bag] and "bank" or "bags") end
            end)
        end
        -- the bank as it was at the last visit
        if not bankOpen and char.bank then
            for id, b in pairs(char.bank) do
                if NameMatch(word, b.name, id) then Add(b.name, id, b.n, "bank") end
            end
        end
        if C.SetItemSearch then pcall(C.SetItemSearch, searchingPrev or "") end
        local results = {}
        for _, r in pairs(found) do
            OAL.ItemID(r.name, r.id)
            results[#results + 1] = r
        end
        table.sort(results, function(a, b) return a.name:lower() < b.name:lower() end)
        done(results, gameWorked)
    end

    searching = CreateFrame("Frame")
    searchingPrev = CurrentSearch()
    if C.SetItemSearch then
        pcall(C.SetItemSearch, word)
        -- the slots are marked once the game sends INVENTORY_SEARCH_UPDATE; the timer is in case
        -- it never comes
        searching:RegisterEvent("INVENTORY_SEARCH_UPDATE")
        searching:SetScript("OnEvent", function() C_Timer.After(0, Finish) end)
        C_Timer.After(0.5, Finish)
    else
        Finish()
    end
end

-- slash command ----------------------------------------------------------------------------------

local function Help()
    OAL.Print("/ol opens the ledger.")
    OAL.Print("/ol minimap shows or hides the minimap button.")
    OAL.Print("/ol debug prints each sale, purchase and craft as it's counted, and what isn't counted and why, until you reload.")
    OAL.Print("/ol search <word> lists the items in your bags and bank that match, ex: /ol search mining")
    OAL.Print("/ol mail lists the auction house and COD mail in your open mailbox and what it would count.")
    OAL.Print("/ol clear deletes this character's sales, purchases and crafts (it asks first).")
end

local function Slash(msg)
    local cmd, rest = Trim(msg):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "search" then
        if rest == "" then
            OAL.Print("Type what to look for, ex: /ol search mining")
            return
        end
        OAL.Find(rest, function(results, gameSearch)
            OAL.Print(#results .. " found for \"" .. rest .. "\""
                .. (gameSearch and " (with the game's bag search)" or " (by name and type only: the game's bag search didn't answer)")
                .. (bankOpen and "" or (char.bank and ", bank as at your last visit" or ", bank not seen yet")) .. ":")
            for _, r in ipairs(results) do
                OAL.Print("   " .. r.name .. " x" .. r.n .. " (" .. r.where .. ")")
            end
        end)
    elseif cmd == "" then
        OAL.ToggleWindow()
    elseif cmd == "minimap" then
        db.minimap.hide = not db.minimap.hide or nil
        OAL.UpdateMinimap()
        OAL.Changed()
    elseif cmd == "debug" then
        db.debug = not db.debug or nil
        OAL.Print(db.debug and "Debug messages on." or "Debug messages off.")
    elseif cmd == "mail" then
        local shown = InboxCount()
        if shown == 0 then
            OAL.Print("No mail to list. Open your mailbox first.")
            return
        end
        local any
        for i = 1, shown do
            local m = ReadMail(i)
            if m then
                any = true
                local what = m.name .. " x" .. m.n
                if m.items and #m.items > 1 then what = what .. " and " .. (#m.items - 1) .. " more" end
                OAL.Print(i .. ": " .. OAL.SOURCE_TEXT[m.src] .. " " .. (m.k == "s" and "sale of " or "purchase of ")
                    .. what .. ", " .. OAL.Money(m.g) .. (m.invoice and "" or " (read from the subject)"))
                if db.debug and m.raw then
                    local parts = {}
                    for n = 1, 11 do parts[n] = tostring(m.raw[n]) end
                    OAL.Print("   invoice: " .. table.concat(parts, ", "))
                end
            end
        end
        if not any then OAL.Print("No auction house or COD sales or purchases in the mailbox.") end
    elseif cmd == "clear" then
        OAL.ConfirmClear()
    else
        Help()
    end
end

-- loading ----------------------------------------------------------------------------------------

local function Load()
    OpcowsLedgerDB = OpcowsLedgerDB or {}
    db = OpcowsLedgerDB
    db.chars = db.chars or {}
    db.cats = db.cats or {}
    db.minimap = db.minimap or {}
    db.debug = nil -- debug lasts until a reload
    local name = UnitName("player") or "?"
    charKey = name .. " - " .. (GetRealmName() or "?")
    db.chars[charKey] = db.chars[charKey] or {}
    char = db.chars[charKey]
    char.log = char.log or {}
    for _, e in ipairs(char.log) do OAL.ItemID(e.name, e.id) end
    for _, cat in ipairs(db.cats) do
        for name, id in pairs(cat.items) do OAL.ItemID(name, id) end
    end
    PruneCodSent()
end

-- deletes this character's log
function OAL.Clear()
    wipe(char.log)
    if char.crafts then wipe(char.crafts) end
    OAL.Print("Deleted " .. charKey .. "'s sales, purchases and crafts.")
    OAL.Changed()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("MAIL_SHOW")
events:RegisterEvent("MAIL_INBOX_UPDATE")
events:RegisterEvent("MAIL_CLOSED")
events:RegisterEvent("BANKFRAME_OPENED")
events:RegisterEvent("BANKFRAME_CLOSED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("PLAYER_MONEY")
events:RegisterEvent("MERCHANT_SHOW")
events:RegisterEvent("MERCHANT_CLOSED")
events:RegisterEvent("TRADE_SHOW")
events:RegisterEvent("UI_INFO_MESSAGE")
for event in pairs(TRADE_EVENTS) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(self, event, arg, arg2)
    if event == "ADDON_LOADED" then
        if arg ~= "OpcowsLedger" then return end
        self:UnregisterEvent("ADDON_LOADED")
        Load()
        HookTakes()
        HookVendor()
        SLASH_OPCOWSLEDGER1 = "/ol"
        SLASH_OPCOWSLEDGER2 = "/oal"
        SlashCmdList.OPCOWSLEDGER = Slash
    elseif event == "PLAYER_LOGIN" then
        MoneyChanged()  -- the gold you start with, for working out what each change was
        OAL.UpdateMinimap()
    elseif event == "PLAYER_MONEY" then
        MoneyChanged()
    elseif event == "MERCHANT_SHOW" then
        Vendor.open = true
        Vendor.who = UnitName and UnitName("NPC") or nil
        MoneyChanged()
    elseif event == "MERCHANT_CLOSED" then
        Vendor.open = nil  -- notes already made still wait for their money change
    elseif event == "TRADE_SHOW" then
        Trade.Show()
    elseif event == "TRADE_ACCEPT_UPDATE" then
        Trade.Accept(arg, arg2)
    elseif TRADE_EVENTS[event] then
        Trade.Read()
    elseif event == "UI_INFO_MESSAGE" then
        Trade.Info(arg, arg2)
    elseif event == "MAIL_SHOW" or event == "MAIL_INBOX_UPDATE" then
        if char then Snapshot() end
    elseif event == "BANKFRAME_OPENED" then
        bankOpen = true
        RememberBank()
    elseif event == "BAG_UPDATE_DELAYED" then
        RememberBank()  -- only while the bank is open
    elseif event == "BANKFRAME_CLOSED" then
        bankOpen = nil
    elseif event == "MAIL_CLOSED" then
        wipe(snapshot)
        wipe(counted)
        lastCount = nil
    end
end)

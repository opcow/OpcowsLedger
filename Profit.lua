-- Profit: what sales made over what their items cost, worked out across all your characters, since
-- items get mailed between them. And crafting, so a crafted item carries the cost of what went in.
--
-- An item's cost is the average paid for it: every character's purchases of an item go into one
-- pool, and a sale takes its items out at the pool's average price. What the pool doesn't hold
-- (gathered, looted, or bought before the ledger) costs its market value: the average price the
-- item sold or was bought for in the ledger over the 30 days up to then, else the nearest price
-- the ledger has, else the vendor's. A craft takes its materials out of the pool the same way and
-- puts what it made in at their cost.
--
-- Crafts are seen in the bags: while a profession window is open, a cast that goes through is
-- followed by the bags changing. What went down was used, what went up was made.
-- char.crafts = { { t, used = { { name, id, n } }, made = { { name, id, n } } } }

local OAL = OpcowsLedger
local DAY = 24 * 60 * 60
local MARKET_DAYS = 30

local Profit = { dirty = true }
OAL.ProfitData = Profit

-- anything that changes the ledger changes the profit too
local changed = OAL.Changed
function OAL.Changed()
    Profit.dirty = true
    changed()
end

-- working it out ---------------------------------------------------------------------------------

-- the order things happened in; in the same second, purchases come before crafts before sales
local ORDER = { b = 1, c = 2, s = 3 }

-- [name] = { { t, n, g } } in time order, from every character's sales and purchases
local function Prices(events)
    local prices = {}
    for _, ev in ipairs(events) do
        local e = ev.e
        if e and (e.n or 1) > 0 and (e.g or 0) > 0 then
            local list = prices[e.name] or {}
            prices[e.name] = list
            list[#list + 1] = { t = e.t, n = e.n or 1, g = e.g }
        end
    end
    return prices
end

-- one item's market value at a time, in copper
local function Market(prices, name, id, t)
    local list = prices[name]
    if list then
        local n, g, before, after = 0, 0, nil, nil
        for _, p in ipairs(list) do
            if p.t <= t then
                before = p
                if p.t >= t - MARKET_DAYS * DAY then n, g = n + p.n, g + p.g end
            elseif not after then
                after = p
            end
        end
        if n > 0 then return g / n end
        local p = before or after
        if p then return p.g / p.n end
    end
    return OAL.SellPrice(name, id) or 0
end
OAL.Market = function(name, id, t)
    return Market(Profit.prices or {}, name, id, t or time())
end

local function Compute()
    local events = {}
    local db = OAL.DB()
    for key, c in pairs(db and db.chars or {}) do
        for i, e in ipairs(c.log or {}) do
            events[#events + 1] = { t = e.t, k = e.k == "s" and "s" or "b", e = e, who = key, i = i }
        end
        for i, cr in ipairs(c.crafts or {}) do
            events[#events + 1] = { t = cr.t, k = "c", craft = cr, who = key, i = i }
        end
    end
    table.sort(events, function(a, b)
        if a.t ~= b.t then return a.t < b.t end
        if a.k ~= b.k then return ORDER[a.k] < ORDER[b.k] end
        if a.who ~= b.who then return a.who < b.who end
        return a.i < b.i
    end)
    local prices = Prices(events)
    local pool, sales, crafts = {}, {}, {}

    -- takes n out of the pool: their cost, and how many the pool didn't have
    local function Take(name, id, n, t)
        local p, cost = pool[name], 0
        if p and p.n > 0 then
            local k = math.min(n, p.n)
            local c = p.g * k / p.n
            p.n, p.g = p.n - k, p.g - c
            cost, n = c, n - k
        end
        local freeCost = n > 0 and n * Market(prices, name, id, t) or 0
        return cost + freeCost, n, freeCost
    end

    local function Put(name, n, g)
        local p = pool[name] or { n = 0, g = 0 }
        pool[name] = p
        p.n, p.g = p.n + n, p.g + g
    end

    for _, ev in ipairs(events) do
        local e, t = ev.e, ev.t
        if ev.k == "b" then
            Put(e.name, e.n or 1, e.g or 0)
        elseif ev.k == "s" then
            local n = e.n or 1
            local cost, free = Take(e.name, e.id, n, t)
            sales[#sales + 1] = { t = t, who = ev.who, src = OAL.Source(e), name = e.name, id = e.id, n = n,
                g = e.g or 0, cost = cost, free = free }
        else
            local cr = ev.craft
            local cost, free, used = 0, 0, {}
            for _, u in ipairs(cr.used) do
                local c, f, fc = Take(u.name, u.id, u.n, t)
                cost, free = cost + c, free + f
                used[#used + 1] = { name = u.name, id = u.id, n = u.n, cost = c, free = f, freeCost = fc }
            end
            -- what it made shares the cost by market value, or evenly
            local weights, total = {}, 0
            for i, m in ipairs(cr.made) do
                weights[i] = Market(prices, m.name, m.id, t) * m.n
                total = total + weights[i]
            end
            for i, m in ipairs(cr.made) do
                local share = total > 0 and weights[i] / total or 1 / #cr.made
                Put(m.name, m.n, cost * share)
            end
            crafts[#crafts + 1] = { t = t, who = ev.who, used = used, made = cr.made, cost = cost, free = free }
        end
    end
    Profit.prices, Profit.sales, Profit.crafts, Profit.pool = prices, sales, crafts, pool
    Profit.dirty = false
end

local function Sales()
    if Profit.dirty or not Profit.sales then Compute() end
    return Profit.sales
end

-- the sales that count: since a time, from a source and by a character ("all" or nil: everyone),
-- and whose item match(name) says yes to
local function EachSale(since, src, who, match, fn)
    for _, s in ipairs(Sales()) do
        if (not since or s.t >= since) and (not src or src == "all" or s.src == src)
            and (not who or who == "all" or s.who == who) and (not match or match(s.name)) then
            fn(s)
        end
    end
end

-- per item: { [name] = { name, id, n, g, cost, free } }; g is what the sales made, free how many
-- weren't bought (so cost their market value)
function OAL.ProfitItems(since, src, who)
    local items = {}
    EachSale(since, src, who, nil, function(s)
        local it = items[s.name]
        if not it then
            it = { name = s.name, id = s.id, n = 0, g = 0, cost = 0, free = 0 }
            items[s.name] = it
        end
        it.id = it.id or s.id
        it.n, it.g, it.cost, it.free = it.n + s.n, it.g + s.g, it.cost + s.cost, it.free + s.free
    end)
    return items
end

-- totals of OAL.ProfitItems, or of the ones in a category
function OAL.ProfitSum(items, cat)
    local sum = { n = 0, g = 0, cost = 0, free = 0 }
    for name, it in pairs(items) do
        if not cat or cat.items[name] then
            sum.n, sum.g, sum.cost, sum.free = sum.n + it.n, sum.g + it.g, sum.cost + it.cost, sum.free + it.free
        end
    end
    return sum
end

-- One side of a comparison: what a category's items did since a time. Per item and in total:
-- sold (sn, sg, scost: what the sold ones cost), bought (bn, bg) and used in crafts (un, ucost; ufree:
-- how many of those weren't bought, ufreeCost: their market value). Purchases and sales follow the
-- From filter; crafts have no source, so they count whatever it is.
local function Blank(name, id)
    return { name = name, id = id, sn = 0, sg = 0, scost = 0, bn = 0, bg = 0, un = 0, ucost = 0, ufree = 0,
        ufreeCost = 0 }
end

function OAL.CompareSide(cat, since, src, who)
    local items, total = {}, Blank()
    if not cat then return items, total end
    local function Item(name, id)
        local it = items[name]
        if not it then
            it = Blank(name, id)
            items[name] = it
        end
        it.id = it.id or id
        return it
    end
    local function Ok(t, w) return (not since or t >= since) and (not who or who == "all" or w == who) end

    EachSale(since, src, who, function(name) return cat.items[name] ~= nil end, function(s)
        local it = Item(s.name, s.id)
        it.sn, it.sg, it.scost = it.sn + s.n, it.sg + s.g, it.scost + s.cost
    end)
    local db = OAL.DB()
    for key, c in pairs(db and db.chars or {}) do
        for _, e in ipairs(c.log or {}) do
            if e.k ~= "s" and cat.items[e.name] and Ok(e.t, key) and (not src or src == "all" or OAL.Source(e) == src) then
                local it = Item(e.name, e.id)
                it.bn, it.bg = it.bn + (e.n or 1), it.bg + (e.g or 0)
            end
        end
    end
    if Profit.dirty or not Profit.crafts then Compute() end
    for _, cr in ipairs(Profit.crafts) do
        if Ok(cr.t, cr.who) then
            for _, u in ipairs(cr.used) do
                if cat.items[u.name] then
                    local it = Item(u.name, u.id)
                    it.un, it.ucost, it.ufree = it.un + u.n, it.ucost + u.cost, it.ufree + u.free
                    it.ufreeCost = it.ufreeCost + (u.freeCost or 0)
                end
            end
        end
    end
    for _, it in pairs(items) do
        for k, v in pairs(it) do
            if type(v) == "number" and k ~= "id" then total[k] = total[k] + v end
        end
    end
    return items, total
end

-- Profit over time for the chart: { unit, buckets = { { from, to, g, cost, n } } }. Today is by
-- the hour, the last 7 and 30 days by the day, all time by the week (up to a year).
function OAL.ProfitSeries(period, src, who, match)
    local today = OAL.Since("today")
    local first, size, count, unit
    if period == "today" then
        first, size, count, unit = today, 3600, 24, "hour"
    elseif period == "7" then
        first, size, count, unit = today - 6 * DAY, DAY, 7, "day"
    elseif period == "30" then
        first, size, count, unit = today - 29 * DAY, DAY, 30, "day"
    else
        local monday = today - ((date("*t").wday + 5) % 7) * DAY
        local earliest = monday
        EachSale(nil, src, who, match, function(s) earliest = math.min(earliest, s.t) end)
        size, unit = 7 * DAY, "week"
        count = math.min(52, math.max(8, math.ceil((monday - earliest) / size) + 1))
        first = monday - (count - 1) * size
    end
    local buckets = {}
    for i = 1, count do
        buckets[i] = { from = first + (i - 1) * size, to = first + i * size, g = 0, cost = 0, n = 0 }
    end
    EachSale(first, src, who, match, function(s)
        local b = buckets[math.floor((s.t - first) / size) + 1]
        if b then b.g, b.cost, b.n = b.g + s.g, b.cost + s.cost, b.n + s.n end
    end)
    return { unit = unit, buckets = buckets }
end

-- crafting ---------------------------------------------------------------------------------------

local Craft = { windows = 0 }
OAL.Craft = Craft
local last  -- the bags' counts at the last bag update, while no craft is waiting

-- the bags' counts: [name] = { n, id }
local function Counts()
    local counts = {}
    local C = C_Container
    if not C or not C.GetContainerNumSlots or not C.GetContainerItemInfo then return counts end
    for _, bag in ipairs(OAL.BagIDs()) do
        local ok, slots = pcall(C.GetContainerNumSlots, bag)
        for slot = 1, (ok and slots) or 0 do
            local info = C.GetContainerItemInfo(bag, slot)
            local name = info and info.hyperlink and info.hyperlink:match("%[(.-)%]")
            if name then
                local c = counts[name] or { n = 0, id = info.itemID }
                counts[name] = c
                c.n = c.n + (info.stackCount or 1)
            end
        end
    end
    return counts
end

-- what changed since the craft began: used and made, { { name, id, n } } each
local function Diff(base, now)
    local used, made = {}, {}
    for name, c in pairs(now) do
        local before = base[name] and base[name].n or 0
        if c.n > before then made[#made + 1] = { name = name, id = c.id, n = c.n - before } end
    end
    for name, c in pairs(base) do
        local after = now[name] and now[name].n or 0
        if after < c.n then used[#used + 1] = { name = name, id = c.id, n = c.n - after } end
    end
    table.sort(used, function(a, b) return a.name < b.name end)
    table.sort(made, function(a, b) return a.name < b.name end)
    return used, made
end

local function List(items)
    local parts = {}
    for _, it in ipairs(items) do parts[#parts + 1] = it.name .. (it.n > 1 and (" x" .. it.n) or "") end
    return table.concat(parts, ", ")
end

-- Crafts in a row (Create All, or clicking fast) start the next cast before the bags show the last
-- one, so one wait covers them all: base is the bags before the first craft not yet seen, owed is
-- how many went through and aren't seen yet, casting is a cast under way. The base only moves
-- when a craft is seen (or given up on), so nothing between is lost; two seen at once are one entry.

-- base moved to now: done waiting unless something is still owed or casting
local function Rebase(p, now)
    p.base = now
    if p.owed <= 0 and not p.casting then
        Craft.pending = nil
        last = now
    end
end

-- a craft that both used and made something is recorded. final: the wait ran out.
function Craft.Check(final)
    local p = Craft.pending
    if not p or p.owed <= 0 then return end
    local now = Counts()
    local used, made = Diff(p.base, now)
    if #used > 0 and #made > 0 then
        p.owed = p.owed - 1
        Rebase(p, now)
        local char = OAL.Char()
        if not char then return end
        char.crafts = char.crafts or {}
        table.insert(char.crafts, { t = time(), used = used, made = made })
        OAL.Debug("Crafted " .. List(made) .. " from " .. List(used) .. ".")
        OAL.Changed()
    elseif final then
        p.owed = 0
        Rebase(p, now)
        if #used > 0 then OAL.Debug("Used " .. List(used) .. " with nothing made (ex: an enchant): not counted.") end
    end
end

local function Pending()
    if not Craft.pending then
        -- the bags as they were at the last update (an instant cast has no start)
        Craft.pending = { base = last or Counts(), owed = 0 }
    end
    return Craft.pending
end

-- a cast started or went through while a profession window is open
function Craft.Start()
    if Craft.windows <= 0 then return end
    local p = Pending()
    if p.owed <= 0 then p.base = Counts() end
    p.casting = true
end

function Craft.Succeeded()
    if Craft.windows <= 0 then return end
    local p = Pending()
    p.casting = false
    p.owed = p.owed + 1
    local serial = (p.serial or 0) + 1
    p.serial = serial
    Craft.Check(false)
    -- give up 3 s after the latest one if the bags never showed it
    C_Timer.After(3, function()
        if Craft.pending == p and p.serial == serial then Craft.Check(true) end
    end)
end

function Craft.Stopped()
    local p = Craft.pending
    if not p then return end
    p.casting = false
    if p.owed <= 0 then Craft.pending = nil end
end

function Craft.Bags()
    local p = Craft.pending
    if p then
        Craft.Check(false)
    else
        last = Counts()
    end
end

local frame = CreateFrame("Frame")
Craft.frame = frame
for _, event in ipairs({ "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "CRAFT_SHOW", "CRAFT_CLOSE",
    "BAG_UPDATE_DELAYED", "PLAYER_LOGIN" }) do
    pcall(frame.RegisterEvent, frame, event)
end
for _, event in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED" }) do
    if frame.RegisterUnitEvent then
        pcall(frame.RegisterUnitEvent, frame, event, "player")
    else
        pcall(frame.RegisterEvent, frame, event)
    end
end
-- which windows are open, so closing one of two doesn't stop crafts being seen
local openWindows = {}
frame:SetScript("OnEvent", function(_, event, unit)
    if event == "TRADE_SKILL_SHOW" or event == "CRAFT_SHOW" then
        openWindows[event] = true
    elseif event == "TRADE_SKILL_CLOSE" then
        openWindows.TRADE_SKILL_SHOW = nil
    elseif event == "CRAFT_CLOSE" then
        openWindows.CRAFT_SHOW = nil
    elseif event == "BAG_UPDATE_DELAYED" or event == "PLAYER_LOGIN" then
        Craft.Bags()
        return
    elseif not frame.RegisterUnitEvent and unit ~= "player" then
        return
    elseif event == "UNIT_SPELLCAST_START" then
        Craft.Start()
        return
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        Craft.Succeeded()
        return
    else
        Craft.Stopped()
        return
    end
    local n = 0
    for _ in pairs(openWindows) do n = n + 1 end
    Craft.windows = n
end)

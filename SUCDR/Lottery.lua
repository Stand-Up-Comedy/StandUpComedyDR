-- SUCDR - guildovní loterie
-- Pořádá a losuje jen guild master. Losy se platí předem tradem guild masterovi: addon
-- trade pozná a přidělí čísla losů (jen celé losy, přeplatek eviduje k vrácení).
-- Výhra = (100 - podíl) % z prodaných losů + bonus za dosažené mety prodeje. Bonus za metu
-- nesmí být vyšší než podíl banky z té mety, takže guildovní banka nikdy neprodělá.
-- Hráči vidí jen výhru, cenu, limit a svoje losy; procenta a bonusy vidí jen GM.
--
-- Zprávy: LOT "id;stav;výhra;cena;limit;hosté;výherce;číslo" (guild, kupujícím šeptem),
--         LOTT "id;rozsahy" (šeptem kupujícímu: jeho losy), LOTQ "" (guild: pošlete stav)
local _, ns = ...
local T = ns.T

local Lot = {}
ns.Lottery = Lot

local MAX_TICKETS = 1000000 -- víc /roll neumí
local MAX_LOG = 500
Lot.DEFAULTS = { price = 10000, limit = 20, step = 500000, bonus = 25000, bonusMax = 100000, share = 10, guests = true }

local function L() return ns.db.lottery end
local function isGM() return ns.Sync.IsGuildMaster() end

local function log(msg)
    local l = L()
    if not l then return end
    l.log[#l.log + 1] = date("%d.%m. %H:%M:%S") .. "  " .. msg
    if #l.log > MAX_LOG then table.remove(l.log, 1) end
end

---------------------------------------------------------------------------
-- Chat
---------------------------------------------------------------------------
local function sendChat(msg, channel, target)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, part in ipairs(ns.SplitChat(msg, 230)) do
        pcall(send, "[SUCDR] " .. part, channel, nil, target)
    end
end

-- Veřejné oznámení: guildovní chat a skupina (hosté losování sledují v raidu)
local function publish(msg)
    ns.Print(msg)
    if not ns.db.announce then return end
    if IsInGuild() then sendChat(msg, "GUILD") end
    local ch = ns.GroupChannel()
    if ch then sendChat(msg, ch) end
end

local function whisper(name, msg)
    sendChat(msg, "WHISPER", name)
end

---------------------------------------------------------------------------
-- Výpočty
---------------------------------------------------------------------------
-- Vrací: tržba, bonus, výhra, pro banku, kolik chybí do dalšího bonusu (nil = už žádný)
function Lot.Money(l)
    local sales = l.count * l.price
    local bonus = 0
    if l.step > 0 then bonus = math.min(l.bonusMax, math.floor(sales / l.step) * l.bonus) end
    local prize = math.floor(sales * (100 - l.share) / 100) + bonus
    local toNext
    if l.step > 0 and l.bonus > 0 and bonus < l.bonusMax then toNext = l.step - sales % l.step end
    return sales, bonus, prize, sales - prize, toNext
end

function Lot.CountOf(name)
    local n = 0
    for _, s in ipairs(L() and L().sales or {}) do
        if s.name == name then n = n + s.to - s.from + 1 end
    end
    return n
end

-- "1-5,11-12"
function Lot.Ranges(name)
    local t = {}
    for _, s in ipairs(L() and L().sales or {}) do
        if s.name == name then
            t[#t + 1] = (s.from == s.to) and tostring(s.from) or (s.from .. "-" .. s.to)
        end
    end
    return table.concat(t, ",")
end

-- Kupující v pořadí prvního nákupu
function Lot.Buyers()
    local list, seen = {}, {}
    for _, s in ipairs(L() and L().sales or {}) do
        if not seen[s.name] then
            seen[s.name] = true
            list[#list + 1] = s.name
        end
    end
    return list
end

function Lot.OwnerOf(number)
    for _, s in ipairs(L() and L().sales or {}) do
        if number >= s.from and number <= s.to then return s.name end
    end
end

-- Kolik zbývá vyplatit výherci
function Lot.PrizeLeft()
    local l = L()
    if not l or l.status ~= "drawn" then return 0 end
    local _, _, prize = Lot.Money(l)
    return math.max(0, prize - (l.paidOut or 0))
end

-- Loterie, která ještě není uzavřená se vším všudy
function Lot.Busy()
    local l = L()
    if not l then return false end
    if l.status == "open" or l.status == "closed" then return true end
    return Lot.PrizeLeft() > 0 or next(l.back) ~= nil or #l.pending > 0
end

---------------------------------------------------------------------------
-- Stav pro hráče
---------------------------------------------------------------------------
local function stateText(l)
    local _, _, prize = Lot.Money(l)
    return table.concat({ l.id, l.status, prize, l.price, l.limit, l.guests and 1 or 0, l.winner or "",
        l.number or "" }, ";")
end

local function sendTo(name)
    local l = L()
    ns.Send("LOT", stateText(l), "WHISPER", name)
    local ranges = Lot.Ranges(name)
    if ranges ~= "" then ns.Send("LOTT", l.id .. ";" .. ranges, "WHISPER", name) end
end

-- Po změně stavu: guildě, a když se změnil stav loterie, i kupujícím mimo guildu
local function broadcast(toBuyers)
    local l = L()
    ns.SendGuild("LOT", stateText(l))
    if toBuyers then
        for _, name in ipairs(Lot.Buyers()) do
            if name ~= l.host and not ns.Sync.IsGuildMember(name) then ns.Send("LOT", stateText(l), "WHISPER", name) end
        end
    end
    ns.RefreshUI()
end

---------------------------------------------------------------------------
-- Guild master
---------------------------------------------------------------------------
local function whole(v) return type(v) == "number" and v >= 0 and v == math.floor(v) end

-- Vrací nil, nebo klíč chybové hlášky
function Lot.Validate(o)
    for _, k in ipairs({ "price", "limit", "step", "bonus", "bonusMax", "share" }) do
        if not whole(o[k]) then return "lot_bad_values" end
    end
    if o.price < 1 or o.limit < 1 or o.share > 100 then return "lot_bad_values" end
    if o.bonus > 0 and o.bonusMax > 0 and (o.step < 1 or o.bonus * 100 > o.step * o.share) then
        return "lot_bad_bonus"
    end
    return nil
end

function Lot.Create(o)
    if not isGM() then
        ns.Print(T("lot_gm_only"))
        return false
    end
    if Lot.Busy() then
        ns.Print(T("lot_busy"))
        return false
    end
    local err = Lot.Validate(o)
    if err then
        ns.Print(T(err))
        return false
    end
    if ns.db.lottery then
        ns.db.lotteryHistory = ns.db.lotteryHistory or {}
        table.insert(ns.db.lotteryHistory, ns.db.lottery)
    end
    ns.db.lottery = {
        id = "L" .. time() .. math.random(100, 999), host = ns.Me(), status = "open", created = time(),
        price = o.price, limit = o.limit, step = o.step, bonus = o.bonus, bonusMax = o.bonusMax, share = o.share,
        guests = o.guests and true or false, count = 0, sales = {}, back = {}, pending = {}, log = {}, paidOut = 0,
    }
    ns.db.lotteryDefaults = { price = o.price, limit = o.limit, step = o.step, bonus = o.bonus,
        bonusMax = o.bonusMax, share = o.share, guests = o.guests and true or false }
    log(("Vyhlášeno: cena %d, limit %d, bonus %d za %d (max %d), banka %d %%, hosté %s"):format(o.price, o.limit,
        o.bonus, o.step, o.bonusMax, o.share, tostring(o.guests and true or false)))
    publish(T(o.guests and "lot_created" or "lot_created_guild", ns.Gold(o.price), o.limit, ns.Display(ns.Me())))
    broadcast()
    return true
end

local function owe(name, gold)
    if gold <= 0 then return end
    local l = L()
    l.back[name] = (l.back[name] or 0) + gold
    log(("K vrácení: %s %d"):format(name, gold))
    ns.Print(T("lot_give_back", ns.Display(name), ns.Gold(l.back[name])))
end

-- Přijatá platba za losy
function Lot.Sell(name, gold)
    local l = L()
    log(("Platba: %s %d"):format(name, gold))
    local n = 0
    if not isGM() then
        ns.Print(T("lot_gm_only"))
    elseif l.status ~= "open" then
        ns.Print(T("lot_closed_payment", ns.Display(name)))
    elseif not l.guests and not ns.Sync.IsGuildMember(name) then
        ns.Print(T("lot_no_guests", ns.Display(name)))
    else
        n = math.max(0, math.min(math.floor(gold / l.price), l.limit - Lot.CountOf(name), MAX_TICKETS - l.count))
    end
    if n > 0 then
        local from, to = l.count + 1, l.count + n
        l.sales[#l.sales + 1] = { name = name, from = from, to = to, t = time() }
        l.count = to
        log(("Losy: %s %d-%d"):format(name, from, to))
        local range = (from == to) and tostring(from) or (from .. "-" .. to)
        local _, _, prize = Lot.Money(l)
        ns.Print(T("lot_sold", ns.Display(name), n, range, ns.Gold(prize)))
        whisper(name, T("lot_sold_whisper", range, ns.Gold(prize)))
    end
    owe(name, gold - n * l.price)
    if n > 0 then sendTo(name) end
    broadcast()
    return n
end

-- Platba, u které není jasné, jestli jde o losy, nebo o splacení dluhu
function Lot.ResolvePending(index, asTickets)
    local l = L()
    local p = l and l.pending[index]
    if not p then return end
    table.remove(l.pending, index)
    if asTickets then
        Lot.Sell(p.name, p.gold)
    else
        local debt = math.min(p.gold, ns.Ledger.OwedBy(p.name))
        log(("Platba %s %d, z toho na splacení dluhu %d"):format(p.name, p.gold, debt))
        ns.Ledger.ApplyPayment(p.name, ns.Me(), debt)
        -- co je navíc nad dluh, jde na losy (zbytek k vrácení)
        if p.gold > debt then Lot.Sell(p.name, p.gold - debt) end
        ns.RefreshUI()
    end
end

function Lot.AskPending(index)
    local l = L()
    local p = l and l.pending[index]
    if not p or not ns.UI or not ns.UI.Confirm then return end
    local function resolve(asTickets)
        -- pořadí se mohlo změnit, najdu platbu znovu
        for i, q in ipairs(l.pending) do
            if q == p and L() == l then return Lot.ResolvePending(i, asTickets) end
        end
    end
    ns.UI.Confirm(T("lot_ask_pending", ns.Display(p.name), ns.Gold(p.gold)), {
        { T("lot_as_tickets"), function() resolve(true) end, true },
        { T("lot_as_debt"), function() resolve(false) end },
        { T("lot_later") },
    })
end

-- Volá Ledger po dokončeném tradu. got / gave = goldy přijaté / odevzdané.
-- Vrací, kolik z nich zbývá na splácení dluhů.
function Lot.OnTrade(partner, got, gave)
    if gave > 0 then Lot.paidTo[partner] = GetTime() end
    local l = L()
    if not l or l.host ~= ns.Me() then return got, gave end

    if gave > 0 then
        local back = l.back[partner]
        if back then
            local take = math.min(gave, back)
            gave = gave - take
            l.back[partner] = (back > take) and (back - take) or nil
            log(("Vráceno: %s %d"):format(partner, take))
            ns.Print(T("lot_returned", ns.Display(partner), ns.Gold(take)))
        end
        if l.status == "drawn" and partner == l.winner then
            local take = math.min(gave, Lot.PrizeLeft())
            if take > 0 then
                gave = gave - take
                l.paidOut = (l.paidOut or 0) + take
                log(("Vyplaceno z výhry: %s %d"):format(partner, take))
                ns.Print(T("lot_paid_out", ns.Display(partner), ns.Gold(take), ns.Gold(Lot.PrizeLeft())))
            end
        end
    end

    if got > 0 and isGM() then
        if l.status == "open" then
            if ns.Ledger.OwedBy(partner) > 0 then
                l.pending[#l.pending + 1] = { name = partner, gold = got, t = time() }
                log(("Nerozhodnutá platba (losy / dluh): %s %d"):format(partner, got))
                Lot.AskPending(#l.pending)
                got = 0
            elseif got >= l.price then
                Lot.Sell(partner, got)
                got = 0
            else
                ns.Print(T("lot_too_little", ns.Display(partner), ns.Gold(got)))
            end
        elseif l.status == "closed" and got >= l.price then
            ns.Print(T("lot_closed_payment", ns.Display(partner)))
        end
    end
    ns.RefreshUI()
    return got, gave
end

-- Zveřejní seznam losů (guildovní chat + skupina)
function Lot.PublishList()
    local l = L()
    if not l or l.count == 0 or not isGM() then return end
    local t = {}
    for _, name in ipairs(Lot.Buyers()) do
        t[#t + 1] = ns.Display(name) .. " " .. Lot.Ranges(name):gsub(",", ", ")
    end
    publish(T("lot_list", l.count, table.concat(t, "; ")))
end

function Lot.Close()
    local l = L()
    if not l or l.status ~= "open" or not isGM() then return false end
    if #l.pending > 0 then
        ns.Print(T("lot_resolve_first"))
        return false
    end
    if #Lot.Buyers() < 2 then
        ns.Print(T("lot_need_two"))
        return false
    end
    l.status = "closed"
    log(("Prodej uzavřen, losů %d"):format(l.count))
    publish(T("lot_closed"))
    Lot.PublishList()
    broadcast(true)
    return true
end

-- Losování: GM hodí /roll 1..počet losů (musí být ve skupině, ať hod vidí ostatní)
function Lot.Draw()
    local l = L()
    if not l or l.status ~= "closed" or not isGM() then return end
    if not ns.GroupChannel() then
        ns.Print(T("lot_need_group"))
        return
    end
    local g = ns.Game.state
    if g and g.phase == "running" then
        ns.Print(T("lot_game_running"))
        return
    end
    l.rolling = time()
    RandomRoll(1, l.count)
end

ns.On("CHAT_MSG_SYSTEM", function(msg)
    local l = L()
    if not l or l.status ~= "closed" or not l.rolling or time() - l.rolling > 30 then return end
    local name, roll, low, high = ns.Game.ParseRoll(msg)
    if name ~= ns.Me() or low ~= 1 or high ~= l.count then return end
    local winner = Lot.OwnerOf(roll)
    if not winner then return end
    l.rolling = nil
    l.status, l.winner, l.number, l.drawn = "drawn", winner, roll, time()
    local _, _, prize, bank = Lot.Money(l)
    log(("Výherce: %s, los %d, výhra %d, do banky %d"):format(winner, roll, prize, bank))
    publish(T("lot_winner", roll, ns.Display(winner), ns.Gold(prize)))
    whisper(winner, T("lot_winner_whisper", ns.Gold(prize)))
    ns.Print(T("lot_gm_summary", ns.Gold(prize), ns.Display(winner), ns.Gold(bank)))
    broadcast(true)
end)

function Lot.Cancel()
    local l = L()
    if not l or (l.status ~= "open" and l.status ~= "closed") or not isGM() then return end
    l.status, l.rolling = "cancelled", nil
    log("Loterie zrušena")
    publish(T("lot_cancelled"))
    for _, p in ipairs(l.pending) do owe(p.name, p.gold) end
    l.pending = {}
    for _, name in ipairs(Lot.Buyers()) do owe(name, Lot.CountOf(name) * l.price) end
    broadcast(true)
end

-- Ruční zápis, když se peníze předaly jinak než tradem (pošta)
function Lot.MarkReturned(name)
    local l = L()
    if not l or not l.back[name] then return end
    log(("Ručně označeno jako vrácené: %s %d"):format(name, l.back[name]))
    l.back[name] = nil
    ns.RefreshUI()
end

function Lot.MarkPaidOut()
    local l = L()
    local left = Lot.PrizeLeft()
    if left <= 0 then return end
    l.paidOut = (l.paidOut or 0) + left
    log(("Ručně označeno jako vyplacené: %s %d"):format(l.winner, left))
    ns.RefreshUI()
end

-- Text pro zálohu (ke zkopírování)
function Lot.Report()
    local l = L()
    if not l then return {} end
    local sales, bonus, prize, bank = Lot.Money(l)
    local lines = {
        ("Loterie %s, stav %s"):format(l.id, l.status),
        ("Cena %d, limit %d, losů %d, tržba %d, bonus %d, výhra %d, do banky %d"):format(l.price, l.limit, l.count,
            sales, bonus, prize, bank),
    }
    if l.winner then
        lines[#lines + 1] = ("Výherce %s, los %d, vyplaceno %d"):format(l.winner, l.number, l.paidOut or 0)
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Losy:"
    for _, name in ipairs(Lot.Buyers()) do
        lines[#lines + 1] = ("%s: %s (%d)"):format(name, Lot.Ranges(name), Lot.CountOf(name))
    end
    for name, gold in pairs(l.back) do lines[#lines + 1] = ("K vrácení %s: %d"):format(name, gold) end
    for _, p in ipairs(l.pending) do lines[#lines + 1] = ("Nerozhodnuto %s: %d"):format(p.name, p.gold) end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Záznam:"
    for _, s in ipairs(l.log) do lines[#lines + 1] = s end
    return lines
end

---------------------------------------------------------------------------
-- Hráči: co vím o loterii od guild mastera (db.lotterySeen)
---------------------------------------------------------------------------
Lot.paidTo = {} -- komu jsem právě dal goldy tradem (u hosta jen od něj přijmu stav)
local TRADE_TRUST = 600

local function trusted(sender)
    if ns.Sync.IsGuildMasterName(sender) then return true end
    -- kdokoli jiný z mojí guildy loterii pořádat nesmí
    if ns.Sync.IsGuildMember(sender) then return false end
    -- host z jiné guildy: jen pořadatel, kterému jsem sám poslal goldy
    local seen = ns.db.lotterySeen
    if seen and seen.host == sender then return true end
    local t = Lot.paidTo[sender]
    return t ~= nil and GetTime() - t < TRADE_TRUST
end

local STATUSES = { open = true, closed = true, drawn = true, cancelled = true }

ns.OnComm("LOT", function(sender, rest)
    local id, status, prize, price, limit, guests, winner, number = strsplit(";", rest)
    prize, price, limit = tonumber(prize), tonumber(price), tonumber(limit)
    if not id or id == "" or not STATUSES[status] or not prize or not price or not limit then return end
    if not trusted(sender) then return end
    local old = ns.db.lotterySeen
    local same = old and old.id == id
    ns.db.lotterySeen = {
        id = id, host = sender, status = status, prize = prize, price = price, limit = limit, guests = guests == "1",
        winner = (winner and winner ~= "") and winner or nil, number = tonumber(number),
        mine = same and old.mine or nil,
    }
    if status == "open" and not same then ns.Print(T("lot_notice", ns.Display(sender), ns.Gold(price))) end
    ns.RefreshUI()
end)

ns.OnComm("LOTT", function(sender, rest)
    local id, ranges = strsplit(";", rest)
    local seen = ns.db.lotterySeen
    if not seen or seen.id ~= id or seen.host ~= sender or not ranges or not ranges:match("^[%d,%-]+$") then return end
    seen.mine = ranges
    ns.RefreshUI()
end)

ns.OnComm("LOTQ", function(sender)
    local l = L()
    if l and l.host == ns.Me() and isGM() then sendTo(sender) end
end)

-- Bez čerstvého seznamu členů guildy nejde poznat guild master ani člen guildy
local function refreshRoster()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(20, refreshRoster)
    C_Timer.After(30, function() ns.SendGuild("LOTQ", "") end)
end)

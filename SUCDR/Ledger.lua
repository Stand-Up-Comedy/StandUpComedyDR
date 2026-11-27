-- SUCDR - historie her a dluhy
-- Dluh za zaplacený označuje jen věřitel (ten, komu se dluží), nebo se označí
-- automaticky po dokončeném tradu s dostatkem goldů.
local _, ns = ...

local L = {}
ns.Ledger = L

local SYNC_DAYS = 30

local function db() return ns.db end

---------------------------------------------------------------------------
-- Hry
---------------------------------------------------------------------------
function L.SerializeGame(g)
    return table.concat({ g.id, g.time, g.host, g.bet, g.mode, g.winner, table.concat(g.players, "/"),
        g.loser or "", g.don or "" }, ";")
end

function L.ParseGame(s)
    local id, t, host, bet, mode, winner, plist, loser, don = strsplit(";", s)
    if not plist or plist == "" or not id or id == "" then return nil end
    local g = {
        id = id, time = tonumber(t), host = host, bet = tonumber(bet),
        mode = mode, winner = winner, players = { strsplit("/", plist) },
        loser = (loser and loser ~= "") and loser or nil,
        don = (don and don ~= "") and don or nil,
    }
    if not g.bet or g.bet < 1 or not g.time or #g.players < 2 then return nil end
    if not tContains(g.players, g.winner) or (g.loser and not tContains(g.players, g.loser)) then return nil end
    return g
end

-- Hra přišla zprávou: sedí na hru, kterou jsme sami viděli ve skupině?
-- (stejný hostitel, sázka a hráči). Jinak jsou její dluhy jen "neověřené".
function L.Verify(g)
    local k = ns.Game.Known(g.id)
    if not k or k.host ~= g.host or k.bet ~= g.bet or k.count ~= #g.players then return false end
    for _, p in ipairs(g.players) do
        if not k.players[p] then return false end
    end
    return true
end

---------------------------------------------------------------------------
-- Double or nothing
---------------------------------------------------------------------------
-- Poražený duelu (v duelu platí ten, kdo není vítěz)
local function duelLoser(g)
    if g.mode ~= "duel" or #g.players ~= 2 then return nil end
    return (g.players[1] == g.winner) and g.players[2] or g.players[1]
end

-- Hra a před ní všechny odvety, které prohrál stejný hráč proti stejnému vítězi
local function donChain(g)
    local loser = duelLoser(g)
    local list, cur = { g }, g
    while cur.don and #list < 50 do
        local prev = db().games[cur.don]
        if not prev or prev.winner ~= g.winner or duelLoser(prev) ~= loser then break end
        list[#list + 1] = prev
        cur = prev
    end
    return list, loser
end

-- O kolik se hraje odveta po duelu g: všechno, co poražený z řetězu her dluží vítězi.
-- Jen když jsou všechny ty dluhy potvrzené a nezaplacené (ani částečně). Vrací sázku a poraženého.
-- anyPaid: při vyrovnání nevadí, že dluh už je zaplacený (PAID od věřitele může
-- dorazit dřív než záznam odvety)
function L.DonStake(g, anyPaid)
    if not g or g.unverified then return nil end
    local chain, loser = donChain(g)
    if not loser then return nil end
    local sum = 0
    for _, c in ipairs(chain) do
        local d = db().debts[c.id .. ":" .. loser]
        if not d or d.to ~= g.winner then return nil end
        if not anyPaid and (d.paid or d.unconfirmed or (d.partial or 0) > 0) then return nil end
        sum = sum + d.amount
    end
    return sum, loser
end

-- Dluh vyrovnaný odvetou: zaplaceno bez tradu. PAID rozešle jen věřitel (jen jemu ho ostatní věří).
local function settle(id)
    local d = db().debts[id]
    if not d or d.paid then return end
    d.settled = true
    L.SetPaid(id, d.to == ns.Me())
end

-- Odveta g skončila. Vyhrál-li ji poražený předchozí hry, dluhy z celého řetězu
-- i dluh z odvety se navzájem vyrovnají (sázka odvety = součet řetězu, ověří se).
local function settleDon(g)
    local prev = g.don and db().games[g.don]
    if not prev or (prev.test or false) ~= (g.test or false) then return end
    local stake, loser = L.DonStake(prev, true)
    if not stake or stake ~= g.bet or g.winner ~= loser or duelLoser(g) ~= prev.winner then return end
    for _, c in ipairs((donChain(prev))) do settle(c.id .. ":" .. loser) end
    settle(g.id .. ":" .. prev.winner)
    local me = ns.Me()
    if me == loser or me == prev.winner then
        ns.Print(ns.T("don_settled", ns.Display(loser), ns.Display(prev.winner)))
    end
end

-- Uloží hru a vytvoří dluhy: každý poražený dluží sázku vítězi.
-- V okruhu a rozdílu (g.loser) platí jen jediný hráč.
-- verified = false: hru jsme neviděli, dluhy se označí jako neověřené
-- (nepočítají se do součtů, dokud je hráč nepotvrdí).
function L.AddGame(g, verified)
    if not g.id or not g.bet or db().games[g.id] then return false end
    if not verified then g.unverified = true end
    db().games[g.id] = g
    for _, p in ipairs(g.players) do
        if p ~= g.winner and (not g.loser or p == g.loser) then
            local id = g.id .. ":" .. p
            if not db().debts[id] then
                db().debts[id] = {
                    id = id, game = g.id, from = p, to = g.winner,
                    amount = g.bet, time = g.time, paid = false, test = g.test,
                    unconfirmed = (not verified) or nil,
                }
            end
        end
    end
    if verified and g.don then settleDon(g) end
    ns.RefreshUI()
    return true
end

-- Ruční potvrzení neověřeného dluhu (jen ten, koho se týká)
function L.Confirm(id)
    local d = db().debts[id]
    if not d or not d.unconfirmed then return end
    d.unconfirmed = nil
    ns.RefreshUI()
end

-- Neověřený dluh, kde jsem dlužník, můžu odmítnout (smaže se jen u mě)
function L.Reject(id)
    local d = db().debts[id]
    if not d or not d.unconfirmed or d.from ~= ns.Me() then return end
    db().debts[id] = nil
    ns.RefreshUI()
end

function L.BroadcastGame(g)
    local s = L.SerializeGame(g)
    ns.SendGroup("GAME", s)
    ns.SendGuild("GAME", s)
end

ns.OnComm("GAME", function(sender, rest)
    local g = L.ParseGame(rest)
    if not g or g.host ~= sender then return end
    local verified = L.Verify(g)
    if L.AddGame(g, verified) then
        local me = ns.Me()
        local T = ns.T
        if not verified and tContains(g.players, me) then
            ns.Print(T("game_unverified", ns.Display(g.host)))
        elseif g.winner == me then
            ns.Print(g.loser and T("win_one", ns.Display(g.loser), ns.Gold(g.bet)) or T("win_all", ns.Gold(g.bet)))
        elseif g.loser == me or (not g.loser and tContains(g.players, me)) then
            ns.Print(T("lose", ns.Gold(g.bet), ns.Display(g.winner)))
        elseif g.loser and tContains(g.players, me) then
            ns.Print(T("safe"))
        end
    end
end)

---------------------------------------------------------------------------
-- Dluhy
---------------------------------------------------------------------------
function L.Remaining(d)
    return d.amount - (d.partial or 0)
end

function L.SetPaid(id, broadcast)
    local d = db().debts[id]
    if not d or d.paid then return end
    d.paid = true
    d.paidTime = time()
    if broadcast and not d.test then
        ns.SendGroup("PAID", id)
        ns.SendGuild("PAID", id)
    end
    ns.RefreshUI()
end

-- Zaplaceno smí ohlásit jen věřitel
ns.OnComm("PAID", function(sender, id)
    local d = db().debts[id]
    if d and d.to == sender then L.SetPaid(id, false) end
end)

-- Rozpočítá přijatou/odeslanou částku na nejstarší otevřené dluhy
function L.ApplyPayment(from, to, amount)
    if not from or not to or amount <= 0 then return end
    local list = {}
    for _, d in pairs(db().debts) do
        if not d.paid and not d.test and d.from == from and d.to == to then list[#list + 1] = d end
    end
    table.sort(list, function(a, b) return (a.time or 0) < (b.time or 0) end)
    local iAmCreditor = (to == ns.Me())
    for _, d in ipairs(list) do
        if amount <= 0 then break end
        local rem = L.Remaining(d)
        d.unconfirmed = nil -- skutečná platba dluh potvrzuje
        if amount >= rem then
            amount = amount - rem
            L.SetPaid(d.id, iAmCreditor)
            ns.Print(ns.T("trade_paid", ns.Display(d.from), ns.Display(d.to), ns.Gold(d.amount)))
        else
            d.partial = (d.partial or 0) + amount
            ns.Print(ns.T("trade_partial", ns.Gold(amount), ns.Gold(L.Remaining(d))))
            amount = 0
        end
    end
    ns.RefreshUI()
end

-- Detekce tradu
local trade = {}
local function updateTrade()
    trade.target = GetTargetTradeMoney() or 0
    trade.player = GetPlayerTradeMoney() or 0
end
---------------------------------------------------------------------------
-- Tlačítko Zaplatit: otevře trade s věřitelem a vyplní dlužnou částku.
-- Trade musí hráč sám potvrdit, addon nic neodesílá.
---------------------------------------------------------------------------
-- Kolik dlužím hráči (jen potvrzené nezaplacené dluhy)
function L.OwedTo(creditor)
    local me, sum = ns.Me(), 0
    for _, d in pairs(db().debts) do
        if not d.paid and not d.test and not d.unconfirmed and d.from == me and d.to == creditor then
            sum = sum + L.Remaining(d)
        end
    end
    return sum
end

local pendingPay
function L.Pay(creditor)
    local T = ns.T
    local amount = L.OwedTo(creditor)
    if amount <= 0 then return end
    if amount * 10000 > GetMoney() then
        ns.Print(T("pay_no_money", ns.Gold(amount)))
        return
    end
    local unit = ns.UnitByName(creditor)
    if not unit then
        ns.Print(T("pay_not_near", ns.Display(creditor)))
        return
    end
    pendingPay = { name = creditor, copper = amount * 10000, t = GetTime() }
    InitiateTrade(unit)
    ns.Print(T("pay_started", ns.Gold(amount), ns.Display(creditor)))
end

local function fillTradeMoney(copper)
    if TradePlayerInputMoneyFrame and MoneyInputFrame_SetCopper then
        pcall(MoneyInputFrame_SetCopper, TradePlayerInputMoneyFrame, copper)
    end
    if SetTradeMoney then pcall(SetTradeMoney, copper) end
end

ns.On("TRADE_SHOW", function()
    trade = { partner = ns.UnitFull("NPC"), target = 0, player = 0 }
    local p = pendingPay
    pendingPay = nil
    if p and p.name == trade.partner and GetTime() - p.t < 30 then
        C_Timer.After(0.2, function() fillTradeMoney(p.copper) end)
    end
end)
ns.On("TRADE_MONEY_CHANGED", updateTrade)
ns.On("TRADE_ACCEPT_UPDATE", updateTrade)
ns.On("UI_INFO_MESSAGE", function(_, msg)
    if ns.IsSecret(msg) or msg ~= ERR_TRADE_COMPLETE or not trade.partner then return end
    local me = ns.Me()
    L.ApplyPayment(trade.partner, me, math.floor((trade.target or 0) / 10000))
    L.ApplyPayment(me, trade.partner, math.floor((trade.player or 0) / 10000))
    trade = {}
end)

---------------------------------------------------------------------------
-- Synchronizace přes guildu
---------------------------------------------------------------------------
local function serDebt(d)
    return table.concat({ d.id, d.game, d.from, d.to, d.amount, d.time or 0, d.paid and 1 or 0 }, ";")
end

local function recent(d)
    if d.test then return false end -- testovací dluhy se nikdy neposílají
    return not d.paid or (d.paidTime or d.time or 0) > time() - SYNC_DAYS * 86400
end

-- Dluh od jiného hráče: věřit se dá jen tomu, co hlásí sám proti sobě.
-- Dlužník (from) potvrzuje, že dluží; věřitel (to) potvrzuje, že je zaplaceno.
-- Nový dluh od věřitele se uloží jen jako neověřený.
-- Dluh, který se mě netýká, jen aktualizuji (zaplaceno/potvrzeno), pokud ho už znám
-- (např. z hry viděné v raidu) - díky tomu nezůstávají u ostatních staré "cuplíky".
ns.OnComm("DEBT", function(sender, rest)
    local id, game, from, to, amount, t, paid = strsplit(";", rest)
    amount = tonumber(amount)
    if not paid or not amount or amount < 1 or from == to or (sender ~= from and sender ~= to) then return end
    if id ~= (game or "") .. ":" .. from then return end
    local me = ns.Me()
    local d = db().debts[id]
    if not d then
        if from ~= me and to ~= me then return end
        db().debts[id] = {
            id = id, game = game, from = from, to = to, amount = amount, time = tonumber(t),
            paid = (paid == "1" and sender == to),
            paidTime = (paid == "1" and sender == to) and time() or nil,
            unconfirmed = (sender ~= from) or nil,
        }
    else
        if d.from ~= from or d.to ~= to then return end
        if sender == from and d.unconfirmed then d.unconfirmed = nil end
        if paid == "1" and sender == to and not d.paid then
            d.paid = true
            d.paidTime = time()
        end
    end
    ns.RefreshUI()
end)

-- Po přihlášení: "pošlete mi dluhy, kde jsem já a vy"
ns.OnComm("HELLO", function(sender)
    local me = ns.Me()
    for _, d in pairs(db().debts) do
        if ((d.from == sender and d.to == me) or (d.to == sender and d.from == me)) and recent(d) then
            ns.Send("DEBT", serDebt(d), "WHISPER", sender)
        end
    end
end)

-- Tlačítko Synchronizovat: každý pošle dluhy, kde je věřitelem
ns.OnComm("SYNCALL", function(sender)
    local me = ns.Me()
    for _, d in pairs(db().debts) do
        if d.to == me and recent(d) then
            ns.Send("DEBT", serDebt(d), "WHISPER", sender)
        end
    end
end)

-- Smaže všechny testovací hry a dluhy
function L.ClearTest()
    local n = 0
    for id, g in pairs(db().games) do
        if g.test then db().games[id] = nil; n = n + 1 end
    end
    for id, d in pairs(db().debts) do
        if d.test then db().debts[id] = nil end
    end
    ns.Print(ns.T("test_cleared", n))
    ns.RefreshUI()
end

function L.RequestSync()
    if not IsInGuild() then
        ns.Print(ns.T("no_guild"))
        return
    end
    ns.SendGuild("SYNCALL", "")
    ns.Print(ns.T("sync_sent"))
end

-- Úklid uložených dat, ať SavedVariables nerostou donekonečna:
-- log hry se drží 14 dní, zaplacené dluhy 120 dní, hry (kvůli statistikám) rok,
-- pokud k nim nezůstal otevřený dluh.
local LOG_DAYS, DEBT_DAYS, GAME_DAYS = 14, 120, 365
function L.Prune(now)
    now = now or time()
    local logLimit, keepLimit = now - LOG_DAYS * 86400, now - DEBT_DAYS * 86400
    local gameLimit = now - GAME_DAYS * 86400
    local open = {}
    for id, d in pairs(db().debts) do
        if d.paid and (d.paidTime or d.time or 0) < keepLimit then
            db().debts[id] = nil
        elseif not d.paid and d.game then
            open[d.game] = true
        end
    end
    for id, g in pairs(db().games) do
        local t = g.time or 0
        if t < gameLimit and not open[id] then
            db().games[id] = nil
        elseif t < logLimit then
            g.log = nil
        end
    end
end

ns.OnInit(function() L.Prune() end)

---------------------------------------------------------------------------
-- Připomínky dluhů
---------------------------------------------------------------------------
-- Otevřené potvrzené dluhy seskupené podle protihráče:
-- { [jméno] = { owe = gold, owed = gold, oldest = time } }
function L.OpenByPlayer()
    local me, map = ns.Me(), {}
    for _, d in pairs(db().debts) do
        if not d.paid and not d.test and not d.unconfirmed and (d.from == me or d.to == me) then
            local other = (d.from == me) and d.to or d.from
            local e = map[other] or { owe = 0, owed = 0 }
            map[other] = e
            if d.from == me then e.owe = e.owe + L.Remaining(d) else e.owed = e.owed + L.Remaining(d) end
            if not e.oldest or (d.time or 0) < e.oldest then e.oldest = d.time or 0 end
        end
    end
    return map
end

local function daysAgo(t)
    return math.max(0, math.floor((time() - (t or time())) / 86400))
end

function L.Remind()
    local T = ns.T
    local owe, owed, oweSum, owedSum = {}, {}, 0, 0
    for name, e in pairs(L.OpenByPlayer()) do
        if e.owe > 0 then
            owe[#owe + 1] = T("remind_item", ns.Display(name), ns.Gold(e.owe), daysAgo(e.oldest))
            oweSum = oweSum + e.owe
        end
        if e.owed > 0 then
            owed[#owed + 1] = ("%s %s"):format(ns.Display(name), ns.Gold(e.owed))
            owedSum = owedSum + e.owed
        end
    end
    if oweSum > 0 then ns.Print(T("remind_owe", ns.Gold(oweSum), table.concat(owe, ", "))) end
    if owedSum > 0 then ns.Print(T("remind_owed", ns.Gold(owedSum), table.concat(owed, ", "))) end
end

-- Ve skupině se objevil hráč, se kterým mám otevřený dluh (jednou za přihlášení)
local notified = {}
ns.On("GROUP_ROSTER_UPDATE", function()
    if not ns.db.remind or not IsInGroup() then return end
    local open = L.OpenByPlayer()
    if not next(open) then return end
    local T = ns.T
    for _, name in ipairs(ns.GroupMembers()) do
        local e = open[name]
        if e and not notified[name] then
            notified[name] = true
            if e.owe > 0 then
                ns.Print(T("remind_in_group_owe", ns.Display(name), ns.Gold(e.owe)))
            elseif e.owed > 0 then
                ns.Print(T("remind_in_group_owed", ns.Display(name), ns.Gold(e.owed)))
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Statistiky a žebříček (z uložených her; testovací a neověřené se nepočítají)
---------------------------------------------------------------------------
-- since: čas (time()) od kdy, nebo nil = vše. Vrací { [jméno] = statistika }.
function L.Stats(since)
    local games = {}
    for _, g in pairs(db().games) do
        if not g.test and not g.unverified and g.winner and (g.time or 0) >= (since or 0) then
            games[#games + 1] = g
        end
    end
    table.sort(games, function(a, b) return (a.time or 0) < (b.time or 0) end)

    local stats = {}
    local function P(n)
        local p = stats[n]
        if not p then
            p = { name = n, games = 0, wins = 0, net = 0, best = 0, worst = 0, streak = 0, bestStreak = 0,
                lossStreak = 0, bestLossStreak = 0 }
            stats[n] = p
        end
        return p
    end
    for _, g in ipairs(games) do
        local payers = 0
        for _, n in ipairs(g.players) do
            local p = P(n)
            p.games = p.games + 1
            if n ~= g.winner and (not g.loser or n == g.loser) then
                payers = payers + 1
                p.net = p.net - g.bet
                if g.bet > p.worst then p.worst = g.bet end
                p.streak = 0 -- prohra sérii přeruší, "bez ztráty" v okruhu ne
                p.lossStreak = p.lossStreak + 1
                if p.lossStreak > p.bestLossStreak then p.bestLossStreak = p.lossStreak end
            end
        end
        local w = P(g.winner)
        local won = g.bet * payers
        w.wins = w.wins + 1
        w.net = w.net + won
        if won > w.best then w.best = won end
        w.streak = w.streak + 1
        if w.streak > w.bestStreak then w.bestStreak = w.streak end
        w.lossStreak = 0
    end
    return stats
end

-- Odznaky a tituly ze statistik za zvolené období.
-- High roller a Největší prohra má jen držitel rekordu (při shodě všichni se stejnou hodnotou).
local ICON = "Interface\\Icons\\"
L.BADGE_ICONS = {
    streak = ICON .. "Ability_Warrior_Rampage",
    unlucky = ICON .. "Ability_Mount_BlackPanther", -- černá kočka
    highroller = ICON .. "INV_Misc_Coin_02",
    bigloss = ICON .. "Ability_Rogue_FeignDeath",
    veteran10 = ICON .. "Achievement_Level_10",
    veteran50 = ICON .. "Achievement_Level_50",
    veteran100 = ICON .. "Achievement_Level_100",
    veteran500 = ICON .. "INV_Crown_02",
}
L.STREAK_BADGE = 5
L.VETERAN_TIERS = { 500, 100, 50, 10 } -- od nejvyššího

-- Vrací { [jméno] = { { key=, icon=, arg= }, ... } }
function L.Badges(stats)
    local top, bottom = 0, 0
    for _, p in pairs(stats) do
        if p.best > top then top = p.best end
        if p.worst > bottom then bottom = p.worst end
    end
    local out = {}
    for name, p in pairs(stats) do
        local list = {}
        local function add(key, icon, arg) list[#list + 1] = { key = key, icon = icon, arg = arg } end
        if top > 0 and p.best == top then add("highroller", L.BADGE_ICONS.highroller, p.best) end
        if p.bestStreak >= L.STREAK_BADGE then add("streak", L.BADGE_ICONS.streak, p.bestStreak) end
        if bottom > 0 and p.worst == bottom then add("bigloss", L.BADGE_ICONS.bigloss, p.worst) end
        if p.bestLossStreak >= L.STREAK_BADGE then add("unlucky", L.BADGE_ICONS.unlucky, p.bestLossStreak) end
        for _, tier in ipairs(L.VETERAN_TIERS) do
            if p.games >= tier then
                add("veteran" .. tier, L.BADGE_ICONS["veteran" .. tier], p.games)
                break
            end
        end
        if #list > 0 then out[name] = list end
    end
    return out
end

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(20, function() ns.SendGuild("HELLO", "") end)
    C_Timer.After(12, function()
        if ns.db.remind then L.Remind() end
    end)
end)

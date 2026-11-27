-- SUCDR - herní logika
-- Hru řídí hostitel (ten, kdo ji založil). Ověřuje skutečné /roll hody ze systémového
-- chatu a ostatním posílá stav. Hráči bez addonu můžou hrát přes "join" a /roll.
--
-- Režimy:
--   duel - 2 hráči, střídavé hody 1..předchozí výsledek, kdo hodí 1, platí druhému
--   mass - hromadný: každé kolo hází všichni najednou, každý od svého posledního
--          výsledku, kdo hodí 1, vypadává, poslední bere sázku od každého poraženého
--   ring - okruh: hází se po řadě (náhodné pořadí) se společným maximem, kdo hodí 1,
--          platí sázku hráči, který házel před ním, a hra končí
--   auto - volba při založení: 2 hráči = duel, víc = mass
--   diff - rozdíl: všichni hodí jednou 1..start, nejnižší platí nejvyššímu rozdíl hodů
--          (při shodě na nejvyšším nebo nejnižším hodu se hází znovu)
-- Double or nothing: po duelu může hostitel založit odvetu stejné dvojice o všechno,
-- co poražený dluží (s.don = id předchozí hry). Vyhraje-li poražený, dluhy se vyrovnají.
local _, ns = ...
local T = ns.T

local G = {}
ns.Game = G
G.state = nil

G.MODES = { "auto", "duel", "mass", "ring", "diff" }
function G.ModeName(m) return T("mode_" .. (m or "auto")) end
function G.ModeHelp(m) return T("help_" .. (m or "auto")) end

local timer
local seen = {}
local openedFor
local wasMyTurn = false
local notifiedGame
local lastRollClick = 0

local function isHost() return G.state ~= nil and G.state.isHost end

-- duel a ring se hrají na tahy, mass po kolech
local function turnBased(s) return s.mode == "duel" or s.mode == "ring" end
G.TurnBased = turnBased

-- Testovací režim (/sucdr test): hra jen lokálně, s boty, nic se neposílá ostatním
G.testMode = false

-- Podrobný log průběhu hry (vede ho jen hostitel, ukládá se do historie)
local MAX_LOG = 600
local function log(msg)
    local s = G.state
    if not s then return end
    s.log = s.log or {}
    if #s.log < MAX_LOG then
        s.log[#s.log + 1] = date("%H:%M:%S") .. "  " .. msg
    end
end

-- Testovací hry hlásíme jen do vlastního chatu
local function announce(msg)
    log("> " .. msg)
    if G.state and G.state.test then
        ns.Print("|cffaaaaaa[TEST]|r " .. msg)
    else
        ns.Announce(msg)
    end
end

local function playSound(kit)
    if ns.db.sound and kit then PlaySound(kit) end
end

function G.FindPlayer(name)
    local s = G.state
    if not s then return nil end
    for i, p in ipairs(s.players) do
        if p.name == name then return p, i end
    end
end

-- Systémová zpráva o hodu u hráčů z jiných (propojených) realmů realm neuvádí,
-- takže "Mathese" dostane náš realm. Pak hledáme podle jména bez realmu, ale jen
-- když je takový hráč ve hře jediný.
function G.FindRoller(name)
    local p, idx = G.FindPlayer(name)
    if p or not name or not G.state then return p, idx end
    local short, realm = name:match("^([^%-]+)%-(.*)$")
    if not short or realm ~= ns.Realm() then return nil end
    local found, foundIdx
    for i, q in ipairs(G.state.players) do
        if q.name:match("^([^%-]+)") == short then
            if found then return nil end -- víc hráčů se stejným jménem, nejde rozlišit
            found, foundIdx = q, i
        end
    end
    return found, foundIdx
end

local function alive()
    local t = {}
    for _, p in ipairs(G.state.players) do
        if p.state == "a" then t[#t + 1] = p end
    end
    return t
end

local function names(list)
    local t = {}
    for i, p in ipairs(list) do t[i] = ns.Display(p.name) end
    return table.concat(t, ", ")
end

---------------------------------------------------------------------------
-- Stav <-> text
---------------------------------------------------------------------------
local function serialize(s)
    local pl = {}
    for i, p in ipairs(s.players) do
        pl[i] = table.concat({ p.name, p.max or 0, p.last or "", p.state, p.rolled and 1 or 0 }, ",")
    end
    local remaining = s.deadline and math.max(0, math.floor(s.deadline - GetTime())) or -1
    return table.concat({
        s.id, s.host, s.phase, s.mode or "", s.bet, s.start, s.round or 0,
        s.curMax or 0, s.turn or 0, remaining, s.winner or "", table.concat(pl, "/"),
        s.choice or "auto", s.loser or "", s.limit or 0, s.created or 0, s.don or "",
    }, ";")
end

local PHASES = { lobby = true, running = true, done = true }
local PSTATES = { a = true, o = true, s = true, w = true }

local function deserialize(str)
    local id, host, phase, mode, bet, start, round, curMax, turn, remaining, winner, plist, choice, loser, limit,
        created, don = strsplit(";", str)
    if not plist or not PHASES[phase] or not id or id == "" or not host or host == "" then return nil end
    local s = {
        id = id, host = host, phase = phase, mode = (mode ~= "" and mode or nil),
        bet = tonumber(bet), start = tonumber(start), round = tonumber(round) or 0,
        curMax = tonumber(curMax), turn = tonumber(turn),
        winner = (winner ~= "" and winner or nil), players = {}, isHost = false,
        choice = choice or "auto", loser = (loser and loser ~= "") and loser or nil,
        limit = tonumber(limit), created = tonumber(created) or 0,
        don = (don and don ~= "") and don or nil,
    }
    if not s.bet or not s.start then return nil end
    remaining = tonumber(remaining)
    if remaining and remaining >= 0 then s.deadline = GetTime() + remaining end
    for entry in plist:gmatch("[^/]+") do
        local name, max, last, st, rolled = strsplit(",", entry)
        if name and name ~= "" and PSTATES[st] then
            s.players[#s.players + 1] = {
                name = name, max = tonumber(max), last = tonumber(last), state = st, rolled = (rolled == "1"),
            }
        end
    end
    return s
end

G.Serialize = serialize
G.Deserialize = deserialize

---------------------------------------------------------------------------
-- Můj hod
---------------------------------------------------------------------------
function G.MyRollMax()
    local s = G.state
    if not s or s.phase ~= "running" then return nil end
    local p, idx = G.FindPlayer(ns.Me())
    if not p or p.state ~= "a" then return nil end
    if turnBased(s) then
        if s.turn == idx then return s.curMax end
    elseif not p.rolled then
        return p.max
    end
    return nil
end

function G.CanRollNow()
    return G.MyRollMax() ~= nil and GetTime() - lastRollClick > 3
end

function G.Roll()
    local max = G.MyRollMax()
    if not max then
        ns.Print(T("not_your_turn"))
        return
    end
    if GetTime() - lastRollClick <= 3 then return end
    lastRollClick = GetTime()
    RandomRoll(1, max)
end

local function afterChange()
    local s = G.state
    -- Okno se otevře samo, jakmile jsem ve hře (poprvé za hru)
    if s and s.id ~= openedFor and G.FindPlayer(ns.Me()) then
        openedFor = s.id
        if ns.db.autoOpen and ns.UI and ns.UI.ShowSafe then ns.UI.ShowSafe() end
    end
    local myTurn = G.MyRollMax() ~= nil
    if myTurn and not wasMyTurn then
        playSound(SOUNDKIT.READY_CHECK)
        -- do chatu jen poprvé za hru, dál stačí zvuk a tlačítko
        if s.id ~= notifiedGame then
            notifiedGame = s.id
            ns.Print(T("your_turn"))
        end
    end
    wasMyTurn = myTurn
    ns.RefreshUI()
end

-- Boti v testovacím režimu hází sami po krátké náhodné pauze
local function scheduleBots()
    local s = G.state
    if not s or not s.test or s.phase ~= "running" then return end
    for idx, p in ipairs(s.players) do
        local needs = p.bot and p.state == "a" and not p.pending
            and ((turnBased(s) and s.turn == idx) or (not turnBased(s) and not p.rolled))
        if needs then
            p.pending = true
            local id = s.id
            C_Timer.After(0.5 + math.random() * 2, function()
                p.pending = nil
                local cur = G.state
                if not cur or cur.id ~= id or cur.phase ~= "running" or p.state ~= "a" then return end
                local max = turnBased(cur) and cur.curMax or p.max
                local roll = math.random(1, max)
                announce(T("bot_rolled", ns.Display(p.name), roll, max))
                G.OnRoll(p.name, roll, 1, max)
            end)
        end
    end
end

local function push()
    afterChange()
    if not isHost() then return end
    if G.state.test then
        scheduleBots()
    else
        G.state.lastSent = GetTime()
        ns.SendGroup("STATE", serialize(G.state), "state")
    end
end

---------------------------------------------------------------------------
-- Časovač (jen hostitel)
---------------------------------------------------------------------------
local function stopTimer()
    if timer then timer:Cancel() end
    timer = nil
    if G.state then G.state.deadline = nil end
end

local function setTimer(fn)
    stopTimer()
    local t = G.state.limit or 0
    if t > 0 then
        G.state.deadline = GetTime() + t
        timer = C_Timer.NewTimer(t, fn)
    end
end

---------------------------------------------------------------------------
-- Lobby (hostitel)
---------------------------------------------------------------------------
-- Startovní hod je vždy stejný jako sázka (max. 1 000 000, víc /roll neumí)
G.MAX_ROLL = 1000000
G.MAX_LIMIT = 600

local function roundLimit()
    return math.max(0, math.min(G.MAX_LIMIT, math.floor(ns.db.roundTime or 0)))
end

-- Nová lobby bez hráčů, nebo nil (a hláška), když ji teď nejde založit
local function newLobby(bet, test, choice)
    local start = bet and math.min(bet, G.MAX_ROLL)
    if not test and not ns.GroupChannel() then
        ns.Print(T("need_group"))
        return nil
    end
    if G.ForeignStale() then G.state = nil end
    if G.state and G.state.phase ~= "done" then
        ns.Print(T("game_exists"))
        return nil
    end
    if not bet or bet < 1 or not start or start < 2 then
        ns.Print(T("bad_bet"))
        return nil
    end
    G.state = {
        id = UnitName("player") .. time() .. math.random(100, 999),
        host = ns.Me(), isHost = true, phase = "lobby", choice = choice,
        bet = bet, start = start, round = 0, players = {}, test = test,
        limit = roundLimit(), created = time(),
    }
    seen[G.state.id] = true
    return G.state
end

function G.Create(bet)
    local test = G.testMode
    if not newLobby(bet, test, ns.db.mode or "auto") then return end
    local me, start = ns.Me(), G.state.start
    G.AddPlayer(me)
    if test then
        announce(T("test_created", G.ModeName(G.state.choice)))
        push()
        return
    end
    announce(T("created", ns.Display(me), G.ModeName(G.state.choice), ns.Gold(bet), start))
    push()
end

---------------------------------------------------------------------------
-- Double or nothing (hostitel, po skončeném duelu)
---------------------------------------------------------------------------
-- Jde po skončené hře nabídnout odvetu? Vrací sázku, poraženého, vítěze a záznam hry.
function G.DonOffer()
    local s = G.state
    if not isHost() or s.phase ~= "done" or s.mode ~= "duel" or not s.winner then return nil end
    local g = ns.db.games[s.id]
    if not g then return nil end
    local stake, loser = ns.Ledger.DonStake(g)
    if not stake or stake > G.MAX_ROLL then return nil end
    return stake, loser, g.winner, g
end

function G.DoubleOrNothing()
    local stake, loser, winner, g = G.DonOffer()
    if not stake then return end
    local test = g.test and true or false
    if not test then
        for _, n in ipairs({ loser, winner }) do
            if not ns.IsInMyGroup(n) then
                ns.Print(T("not_in_group", ns.Display(n)))
                return
            end
        end
    end
    local bots = {}
    for _, p in ipairs(G.state.players) do bots[p.name] = p.bot end
    local s = newLobby(stake, test, "duel")
    if not s then return end
    s.don = g.id
    for _, n in ipairs({ loser, winner }) do
        s.players[#s.players + 1] = { name = n, state = "a", max = s.start, rolled = false, bot = bots[n] }
    end
    announce(T("don_created", ns.Display(loser), ns.Display(winner), ns.Gold(stake)))
    push()
end

-- Změna režimu: uloží se jako výchozí, v lobby ho hostitel mění i pro aktuální hru
-- (kromě odvety double or nothing, ta je vždy duel)
function G.SetMode(mode)
    ns.db.mode = mode
    local s = G.state
    if isHost() and s.phase == "lobby" and not s.don then
        s.choice = mode
        announce(T("mode_changed", G.ModeName(mode)))
        push()
    else
        ns.RefreshUI()
    end
end

function G.AddPlayer(name)
    local s = G.state
    if not isHost() or s.phase ~= "lobby" or not name then return end
    if G.FindPlayer(name) or s.don then return end -- do odvety se nikdo nepřidává
    if not s.test and not ns.IsInMyGroup(name) then
        ns.Print(T("not_in_group", ns.Display(name)))
        return
    end
    if #s.players >= 40 then return end
    s.players[#s.players + 1] = { name = name, state = "a", max = s.start, rolled = false }
    if #s.players > 1 then
        announce(T("player_joined", ns.Display(name), #s.players))
    end
    push()
end

function G.RemovePlayer(name)
    local s = G.state
    if not isHost() or s.phase ~= "lobby" then return end
    local _, idx = G.FindPlayer(name)
    if not idx then return end
    table.remove(s.players, idx)
    announce(T("player_left", ns.Display(name), #s.players))
    push()
end

function G.AddBot()
    local s = G.state
    if not isHost() or not s.test or s.phase ~= "lobby" then return end
    local n = 1
    while G.FindPlayer("Bot" .. n .. "-Test") do n = n + 1 end
    G.AddPlayer("Bot" .. n .. "-Test")
    G.FindPlayer("Bot" .. n .. "-Test").bot = true
end

function G.AddTarget()
    if not UnitExists("target") or not UnitIsPlayer("target") then
        ns.Print(T("need_target"))
        return
    end
    G.AddPlayer(ns.UnitFull("target"))
end

function G.Join()
    local s = G.state
    if not s or s.phase ~= "lobby" then
        ns.Print(T("no_lobby"))
        return
    end
    if isHost() then G.AddPlayer(ns.Me()) else ns.SendGroup("JOIN", s.id) end
end

function G.Leave()
    local s = G.state
    if not s then return end
    if isHost() then G.RemovePlayer(ns.Me()) else ns.SendGroup("LEAVE", s.id) end
end

-- JOIN/LEAVE nesou id hry, ať se při dvou lobby naráz hráč nepřidá do obou
local function forMyGame(id) return isHost() and (id == "" or id == G.state.id) end
ns.OnComm("JOIN", function(sender, id) if forMyGame(id) then G.AddPlayer(sender) end end)
ns.OnComm("LEAVE", function(sender, id) if forMyGame(id) then G.RemovePlayer(sender) end end)

-- Hráči bez addonu se přidají napsáním "join" do party/raid chatu
local function onGroupChat(text, sender)
    if not isHost() or G.state.phase ~= "lobby" then return end
    if ns.IsSecret(text, sender) then return end
    if text:lower():match("^%s*join%s*$") then G.AddPlayer(ns.Normalize(sender)) end
end
for _, ev in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
    "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" }) do
    ns.On(ev, onGroupChat)
end

function G.Cancel()
    if not isHost() then return end
    stopTimer()
    announce(T("cancelled"))
    local id, test = G.state.id, G.state.test
    G.state = nil
    if not test then ns.SendGroup("CANCEL", id) end
    afterChange()
end

---------------------------------------------------------------------------
-- Průběh hry (hostitel)
---------------------------------------------------------------------------
local function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

function G.Start()
    local s = G.state
    if not isHost() or s.phase ~= "lobby" then return end
    local n = #s.players
    if n < 2 then
        ns.Print(T("need_two"))
        return
    end
    local mode = s.choice or "auto"
    if mode == "auto" then mode = (n == 2) and "duel" or "mass" end
    if mode == "duel" and n ~= 2 then
        ns.Print(T("duel_two"))
        return
    end
    if mode == "ring" and n == 2 then mode = "duel" end -- okruh pro 2 je duel

    s.phase, s.mode = "running", mode
    s.limit = roundLimit()
    if mode == "ring" then shuffle(s.players) end
    for _, p in ipairs(s.players) do
        p.state, p.max, p.last, p.rolled = "a", s.start, nil, false
    end
    log(("Start: verze=%s režim=%s sázka=%d start=%d limit=%ss test=%s jazyk=%s hráči: %s"):format(
        C_AddOns.GetAddOnMetadata("SUCDR", "Version") or "?", s.mode, s.bet, s.start,
        tostring(s.limit), tostring(s.test or false), ns.Lang(), names(s.players)))

    if s.don then
        announce(T("don_start", ns.Gold(s.bet)))
    end
    if mode == "duel" then
        s.curMax, s.turn, s.prev = s.start, 1, nil
        announce(T("duel_start", ns.Display(s.players[1].name), ns.Display(s.players[2].name), ns.Gold(s.bet),
            ns.Display(s.players[1].name), s.curMax))
        G.StartTurn()
    elseif mode == "ring" then
        s.curMax, s.turn, s.prev = s.start, 1, nil
        announce(T("ring_start", ns.Gold(s.bet), n, names(s.players)))
        announce(T("ring_first", ns.Display(s.players[1].name), s.curMax))
        G.StartTurn()
    elseif mode == "diff" then
        announce(T("diff_start", n, s.start))
        G.NextRound()
    else
        announce(T("mass_start", n, ns.Gold(s.bet), ns.Gold(s.bet * (n - 1))))
        G.NextRound()
    end
end

-- Hráč na tahu prohrál (hodil 1 nebo nehodil včas). Platí tomu, kdo házel před ním;
-- když ještě nikdo nehodil, platí poslednímu v pořadí.
local function loseTurn(idx)
    local s = G.state
    local n = #s.players
    local winnerIdx = s.prev or ((idx - 2) % n + 1)
    if s.mode == "duel" then
        G.Finish(s.players[winnerIdx].name)
    else
        G.Finish(s.players[winnerIdx].name, s.players[idx].name)
    end
end

function G.StartTurn()
    local s = G.state
    log(("Tah: %s, rozsah 1-%d"):format(ns.Display(s.players[s.turn].name), s.curMax))
    setTimer(function()
        local cur = G.state
        if not cur or cur.phase ~= "running" then return end
        announce(T("timeout_turn", ns.Display(cur.players[cur.turn].name)))
        loseTurn(cur.turn)
    end)
    push()
end

function G.NextRound()
    local s = G.state
    s.round = s.round + 1
    for _, p in ipairs(alive()) do
        p.rolled, p.last = false, nil
    end
    local ranges = {}
    for _, p in ipairs(alive()) do ranges[#ranges + 1] = ("%s 1-%d"):format(ns.Display(p.name), p.max or 0) end
    log(("Kolo %d, rozsahy: %s"):format(s.round, table.concat(ranges, ", ")))
    local limit = (s.limit or 0) > 0 and T("round_limit", s.limit) or ""
    announce(T("round_start", s.round, #alive(), limit))
    setTimer(function() G.ResolveRound() end)
    push()
end

-- Rozdíl: kdo nehodil včas, počítá se mu 1 (jinak by šlo počkat na hody ostatních a nehodit)
local function resolveDiff()
    local s = G.state
    local list, idle = alive(), {}
    for _, p in ipairs(list) do
        if not p.rolled then
            p.last = 1
            idle[#idle + 1] = p
        end
    end
    if #idle == #list then
        announce(T("nobody_rolled"))
        return G.Cancel()
    end
    if #idle > 0 then announce(T("diff_idle", names(idle))) end
    local hi, lo
    for _, p in ipairs(list) do
        if not hi or p.last > hi then hi = p.last end
        if not lo or p.last < lo then lo = p.last end
    end
    if hi == lo then
        announce(T("diff_draw", hi))
        return G.FinishDraw()
    end
    local top, bottom = {}, {}
    for _, p in ipairs(list) do
        if p.last == hi then top[#top + 1] = p end
        if p.last == lo then bottom[#bottom + 1] = p end
    end
    if #top > 1 or #bottom > 1 then
        announce(T("diff_tie", names(#top > 1 and top or bottom)))
        for _, p in ipairs(list) do p.max = s.start end
        return G.NextRound()
    end
    -- sázka hry = rozdíl: s ním jde konečný stav i záznam hry, takže dluh,
    -- statistiky i ověření sedí i u starších verzí addonu
    s.bet = hi - lo
    local loser = ns.Display(bottom[1].name)
    announce(T("diff_result", loser, lo, ns.Display(top[1].name), hi, loser, ns.Gold(s.bet)))
    G.Finish(top[1].name, bottom[1].name, true)
end

function G.ResolveRound()
    local s = G.state
    if not s or s.phase ~= "running" then return end
    stopTimer()
    local dbg = {}
    for _, p in ipairs(alive()) do
        dbg[#dbg + 1] = ("%s rolled=%s last=%s max=%s"):format(ns.Display(p.name), tostring(p.rolled),
            tostring(p.last), tostring(p.max))
    end
    log(("Vyhodnocení kola %d: %s"):format(s.round, table.concat(dbg, " | ")))
    if s.mode == "diff" then return resolveDiff() end
    local survivors, ones, idle = {}, {}, {}
    for _, p in ipairs(alive()) do
        if not p.rolled then
            idle[#idle + 1] = p
        elseif p.last == 1 then
            ones[#ones + 1] = p
        else
            survivors[#survivors + 1] = p
        end
    end
    for _, p in ipairs(idle) do p.state = "o" end
    if #idle > 0 then announce(T("timeout_round", names(idle))) end

    if #survivors >= 2 then
        for _, p in ipairs(ones) do p.state = "o" end
        if #ones > 0 then announce(T("ones_out", names(ones))) end
        for _, p in ipairs(survivors) do p.max = p.last end
        G.NextRound()
    elseif #survivors == 1 then
        for _, p in ipairs(ones) do p.state = "o" end
        G.Finish(survivors[1].name)
    elseif #ones >= 2 then
        announce(T("all_ones", names(ones)))
        for _, p in ipairs(ones) do p.max = s.start end
        G.NextRound()
    elseif #ones == 1 then
        G.Finish(ones[1].name)
    else
        announce(T("nobody_rolled"))
        G.Cancel()
    end
end

local function invalid(p, low, high, expected)
    announce(T("invalid_roll", ns.Display(p.name), low, high, expected))
end

function G.OnRoll(name, roll, low, high)
    local s = G.state
    if not isHost() or s.phase ~= "running" then return end
    local p, idx = G.FindRoller(name)
    if not p then return end
    name = p.name
    log(("Hod přijat: %s %d (%d-%d) [stav=%s rolled=%s max=%s curMax=%s turn=%s]"):format(
        ns.Display(name), roll or -1, low or -1, high or -1, tostring(p.state), tostring(p.rolled),
        tostring(p.max), tostring(s.curMax), tostring(s.turn)))
    if p.state ~= "a" then return end

    if turnBased(s) then
        if idx ~= s.turn then
            announce(T("not_on_turn", ns.Display(p.name)))
            return
        end
        if low ~= 1 or high ~= s.curMax then return invalid(p, low, high, s.curMax) end
        p.last = roll
        if roll == 1 then
            loseTurn(idx)
        else
            s.curMax = roll
            s.prev = idx
            s.turn = idx % #s.players + 1
            G.StartTurn()
        end
    else
        if p.rolled then
            announce(T("already_rolled", ns.Display(p.name)))
            return
        end
        if low ~= 1 or high ~= p.max then return invalid(p, low, high, p.max) end
        p.rolled, p.last = true, roll
        for _, q in ipairs(alive()) do
            if not q.rolled then
                push()
                return
            end
        end
        G.ResolveRound()
    end
end

-- Rozdíl bez vítěze (všichni hodili stejně): nikdo nic neplatí, hra se neukládá
function G.FinishDraw()
    local s = G.state
    stopTimer()
    s.phase, s.winner, s.loser = "done", nil, nil
    for _, p in ipairs(s.players) do p.state = "s" end
    log("Remíza, nikdo neplatí")
    push()
end

-- Výsledek odvety double or nothing do chatu (místo běžného oznámení vítěze)
local function announceDon(s, winnerName)
    local prev = ns.db.games[s.don]
    local stake, loser
    if prev then stake, loser = ns.Ledger.DonStake(prev) end
    if stake and winnerName == loser then
        announce(T("don_even", ns.Display(loser), ns.Display(prev.winner)))
    else
        local other = (s.players[1].name == winnerName) and s.players[2] or s.players[1]
        announce(T("don_double", ns.Display(other.name), ns.Gold((stake or s.bet) + s.bet), ns.Display(winnerName)))
    end
end

-- loserName: v okruhu a rozdílu, kde platí jediný hráč. Jinak platí všichni kromě vítěze.
-- quiet: výsledek už oznámil volající
function G.Finish(winnerName, loserName, quiet)
    local s = G.state
    stopTimer()
    s.phase, s.winner, s.loser = "done", winnerName, loserName
    local list = {}
    for i, p in ipairs(s.players) do
        if p.name == winnerName then
            p.state = "w"
        elseif not loserName or p.name == loserName then
            p.state = "o"
        else
            p.state = "s" -- v okruhu: neprohrál, nic neplatí
        end
        list[i] = p.name
    end
    if quiet then -- luacheck: ignore 542 (výsledek oznámil volající)
    elseif s.don then
        announceDon(s, winnerName)
    elseif loserName then
        announce(T("ring_lost", ns.Display(loserName), ns.Gold(s.bet), ns.Display(winnerName)))
    else
        local losers = #s.players - 1
        if losers == 1 then
            local loser = (s.players[1].name == winnerName) and s.players[2] or s.players[1]
            announce(T("winner_one", ns.Display(winnerName), ns.Display(loser.name), ns.Gold(s.bet)))
        else
            announce(T("winner_all", ns.Display(winnerName), losers, ns.Gold(s.bet), ns.Gold(s.bet * losers)))
        end
    end
    local g = { id = s.id, time = time(), host = s.host, bet = s.bet, mode = s.mode, winner = winnerName,
        loser = loserName, players = list, test = s.test or nil, log = s.log, don = s.don }
    ns.Ledger.AddGame(g, true)
    -- nejdřív konečný stav, pak záznam hry (ostatní si ho ověří podle stavu)
    push()
    if not s.test then ns.Ledger.BroadcastGame(g) end
end

---------------------------------------------------------------------------
-- Hody ze systémového chatu
---------------------------------------------------------------------------
-- Z lokalizovaného textu (např. "%s rolls %d (%d-%d)") udělá Lua pattern
local function BuildRollPattern()
    local p = RANDOM_ROLL_RESULT
    p = p:gsub("([%(%)%-%.%+%[%]%^%$%*%?])", "%%%1")
    p = p:gsub("%%s", "(.+)")
    p = p:gsub("%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local rollPattern
ns.OnInit(function() rollPattern = BuildRollPattern() end)

-- Vrátí jméno, hod, od, do; nebo nil, když zpráva není hod
function G.ParseRoll(msg)
    if not rollPattern or ns.IsSecret(msg) then return nil end
    local name, roll, low, high = msg:match(rollPattern)
    if not name then return nil end
    return ns.Normalize(name), tonumber(roll), tonumber(low), tonumber(high)
end

ns.On("CHAT_MSG_SYSTEM", function(msg)
    local name, roll, low, high = G.ParseRoll(msg)
    if name then G.OnRoll(name, roll, low, high) end
end)

---------------------------------------------------------------------------
-- Stav od hostitele (klienti)
---------------------------------------------------------------------------
-- Hry viděné ve skupině (jen v paměti): id -> { host, bet, players = {jméno = true}, count }.
-- Podle nich se ověřuje záznam hry (GAME), aby nešlo podvrhnout dluh z hry, která neproběhla.
local known = {}

local function remember(s)
    local set, n = {}, 0
    for _, p in ipairs(s.players) do
        if not set[p.name] then set[p.name], n = true, n + 1 end
    end
    known[s.id] = { host = s.host, bet = s.bet, players = set, count = n }
end
G.Remember = remember

function G.Known(id) return known[id] end
function G.Forget(id) known[id] = nil end

-- Dvě lobby ve stejné skupině: ustoupí ta mladší (při shodě rozhodne jméno hostitele).
-- Rozehraná hra má přednost před lobby. Dvě rozehrané hry už nejde smířit.
function G.ShouldYield(mine, other)
    if mine.phase ~= "lobby" then return false end
    if other.phase == "running" then return true end
    if other.phase ~= "lobby" then return false end
    local a, b = mine.created or 0, other.created or 0
    if a ~= b then return a > b end
    return mine.host > other.host
end

-- Mám v aktuální cizí hře zůstat, i když přišel stav jiné hry?
local function keepCurrent(cur, new)
    if not cur or cur.id == new.id or cur.phase == "done" then return false end
    if G.ForeignStale() then return false end
    local me = ns.Me()
    return G.FindPlayer(me) ~= nil
end

ns.OnComm("STATE", function(sender, rest)
    local s = deserialize(rest)
    if not s or s.host ~= sender then return end
    remember(s)
    local cur = G.state
    if cur and cur.isHost and cur.phase ~= "done" then
        if cur.test or cur.id == s.id or s.phase == "done" then return end
        if not G.ShouldYield(cur, s) then return end
        -- naše lobby ustoupí starší hře
        ns.Print(T("game_conflict", ns.Display(sender)))
        announce(T("cancelled"))
        stopTimer()
        ns.SendGroup("CANCEL", cur.id)
        G.state = nil
        cur = nil
    end
    if keepCurrent(cur, s) then return end
    if not seen[s.id] then
        seen[s.id] = true
        if s.phase == "lobby" then
            playSound(SOUNDKIT.IG_PLAYER_INVITE)
            ns.Print(T("lobby_notice", ns.Display(sender), G.ModeName(s.choice), ns.Gold(s.bet)))
        end
    end
    s.lastUpdate = GetTime()
    G.state = s
    afterChange()
end)

-- Cizí hra, jejíž hostitel odešel ze skupiny, dal reload nebo spadl.
-- Hostitel posílá stav aspoň každých HEARTBEAT s, takže dlouhé ticho znamená konec.
local HEARTBEAT = 15
local SILENCE = 50
local function foreignStale()
    local s = G.state
    if not s or s.isHost or s.phase == "done" then return false end
    if not ns.GroupChannel() or not ns.IsInMyGroup(s.host) then return true end
    return GetTime() - (s.lastUpdate or 0) > SILENCE
end
G.ForeignStale = foreignStale

local function dropStale()
    if foreignStale() then
        G.state = nil
        afterChange()
    end
end

-- Hostitel: odchod ze skupiny hru ukončí, z lobby vypadnou hráči, kteří ze skupiny odešli
local function hostRoster()
    local s = G.state
    if not isHost() or s.test or s.phase == "done" then return end
    if not ns.GroupChannel() then
        stopTimer()
        G.state = nil
        afterChange()
        return
    end
    if s.phase == "lobby" then
        for i = #s.players, 1, -1 do
            local name = s.players[i].name
            if name ~= s.host and not ns.IsInMyGroup(name) then G.RemovePlayer(name) end
        end
    end
end

ns.On("GROUP_ROSTER_UPDATE", function()
    dropStale()
    hostRoster()
end)

C_Timer.NewTicker(5, function()
    local s = G.state
    if not s or s.phase == "done" then return end
    if s.isHost then
        -- pravidelný stav: ostatní poznají, že hostitel žije, a dostanou ztracené změny
        if not s.test and GetTime() - (s.lastSent or 0) >= HEARTBEAT then
            s.lastSent = GetTime()
            ns.SendGroup("STATE", serialize(s), "state")
        end
    else
        dropStale()
    end
end)

ns.OnComm("CANCEL", function(sender, id)
    local s = G.state
    if s and not s.isHost and s.id == id and s.host == sender then
        G.state = nil
        afterChange()
    end
end)

-- Po reloadu nebo přihlášení hostitel nemá svou hru v paměti: řekne ostatním, ať ji zahodí
ns.OnComm("RESET", function(sender)
    local s = G.state
    if s and not s.isHost and s.host == sender and s.phase ~= "done" then
        ns.Print(T("host_reset", ns.Display(sender)))
        G.state = nil
        afterChange()
    end
end)

ns.On("PLAYER_ENTERING_WORLD", function(isLogin, isReload)
    if not (isLogin or isReload) then return end
    C_Timer.After(5, function()
        if ns.GroupChannel() and not G.state then ns.SendGroup("RESET", "") end
    end)
end)

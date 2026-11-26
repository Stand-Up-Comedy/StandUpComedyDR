-- SUCDR - samotest (/sucdr selftest)
-- Ověří bez druhého hráče: převod stavu hry a záznamu hry na text a zpět,
-- čtení hodů ze systémového chatu, dělení zpráv na části (UTF-8)
-- a skutečné poslání addon zpráv šeptem sám sobě přes frontu a throttle.
local _, ns = ...

local T = {}
ns.SelfTest = T

local run -- probíhající test: { id, expected = {case = data}, got = {}, timer }
local passed, failed

local function check(ok, label, detail)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        ns.Print(("|cffff4040%s|r %s%s"):format(ns.T("self_error"), label, detail and (": " .. detail) or ""))
    end
end

-- Testovací stav pro 40 hráčů s českými jmény (dlouhá zpráva přes víc částí)
local function sampleState()
    local s = {
        id = "Žofie1732190000123", host = "Žofie-Drakthul", phase = "running", mode = "ring",
        bet = 12345, start = 1000, round = 3, curMax = 777, turn = 5, winner = nil,
        choice = "ring", loser = nil, players = {}, deadline = GetTime() + 25, limit = 30, created = 1732190000,
    }
    local states = { "a", "o", "s", "w" }
    for i = 1, 40 do
        s.players[i] = {
            name = ("Hráčřčš%d-Drakthul"):format(i), max = 1000 - i * 7,
            last = (i % 3 == 0) and nil or (i * 11), state = states[i % 4 + 1], rolled = (i % 2 == 0),
        }
    end
    return s
end

local FIELDS = { "id", "host", "phase", "mode", "bet", "start", "round", "curMax", "turn", "winner", "choice", "loser",
    "limit", "created" }
local PFIELDS = { "name", "max", "last", "state", "rolled" }

local function testState()
    local a = sampleState()
    local text = ns.Game.Serialize(a)
    local b = ns.Game.Deserialize(text)
    check(b ~= nil, "Stav hry: rozbalení")
    if not b then return end
    for _, f in ipairs(FIELDS) do
        check(a[f] == b[f], "Stav hry: pole " .. f, ("%s ~= %s"):format(tostring(a[f]), tostring(b[f])))
    end
    check(#a.players == #b.players, "Stav hry: počet hráčů", #a.players .. " ~= " .. #b.players)
    for i, p in ipairs(a.players) do
        local q = b.players[i] or {}
        for _, f in ipairs(PFIELDS) do
            if p[f] ~= q[f] then
                check(false, ("Stav hry: hráč %d pole %s"):format(i, f), ("%s ~= %s"):format(tostring(p[f]), tostring(q[f])))
            end
        end
    end
    check(b.deadline and math.abs((b.deadline - GetTime()) - 25) <= 1.5, "Stav hry: zbývající čas")
end

local function testGame()
    local L = ns.Ledger
    local a = {
        id = "Žofie1732190000123", time = 1732190000, host = "Žofie-Drakthul", bet = 5000, mode = "ring",
        winner = "Řehoř-Drakthul", loser = "Čestmír-Drakthul",
        players = { "Žofie-Drakthul", "Řehoř-Drakthul", "Čestmír-Drakthul" },
    }
    local b = L.ParseGame(L.SerializeGame(a))
    check(b ~= nil, "Záznam hry: rozbalení")
    if not b then return end
    for _, f in ipairs({ "id", "time", "host", "bet", "mode", "winner", "loser" }) do
        check(a[f] == b[f], "Záznam hry: pole " .. f, ("%s ~= %s"):format(tostring(a[f]), tostring(b[f])))
    end
    check(table.concat(a.players, "/") == table.concat(b.players or {}, "/"), "Záznam hry: hráči")
    a.loser = nil
    b = L.ParseGame(L.SerializeGame(a))
    check(b and b.loser == nil, "Záznam hry bez platícího")
    a.winner = "Cizinec-Drakthul"
    check(L.ParseGame(L.SerializeGame(a)) == nil, "Záznam hry s vítězem mimo hráče se odmítne")
    check(ns.Game.Deserialize("x;y;neznama;;1;2;0;0;0;0;;A-B,1,,a,0") == nil, "Stav s neznámou fází se odmítne")
end

-- Ověření záznamu hry podle viděného stavu (proti podvrženým dluhům)
local function testVerify()
    local G, L = ns.Game, ns.Ledger
    local id = "SelfTestVerify" .. math.random(100000, 999999)
    local g = { id = id, host = "Host-R", bet = 100, winner = "A-R", players = { "Host-R", "A-R", "B-R" } }
    check(not L.Verify(g), "Neviděná hra není ověřená")
    G.Remember({ id = id, host = "Host-R", bet = 100,
        players = { { name = "B-R" }, { name = "Host-R" }, { name = "A-R" } } })
    check(L.Verify(g), "Viděná hra je ověřená")
    g.bet = 1000
    check(not L.Verify(g), "Jiná sázka než ve hře se odmítne")
    g.bet = 100
    g.players = { "Host-R", "A-R", "Obet-R" }
    check(not L.Verify(g), "Cizí hráč v záznamu se odmítne")
    g.host = "Podvodnik-R"
    g.players = { "Host-R", "A-R", "B-R" }
    check(not L.Verify(g), "Jiný hostitel se odmítne")
    G.Forget(id)
end

-- Statistiky: bilance, výhry a série z uložených her (na dočasných datech)
local function testStats()
    local db = ns.db
    local saved = db.games
    db.games = {
        a = { id = "a", time = 100, bet = 100, winner = "A-R", players = { "A-R", "B-R" } },
        b = { id = "b", time = 200, bet = 50, winner = "A-R", loser = "B-R", players = { "A-R", "B-R", "C-R" } },
        c = { id = "c", time = 300, bet = 10, winner = "C-R", players = { "A-R", "B-R", "C-R" } },
        t = { id = "t", time = 400, bet = 999, winner = "B-R", players = { "A-R", "B-R" }, test = true },
        u = { id = "u", time = 500, bet = 999, winner = "B-R", players = { "A-R", "B-R" }, unverified = true },
    }
    local ok, err = pcall(function()
        local s = ns.Ledger.Stats()
        local A, B, C = s["A-R"], s["B-R"], s["C-R"]
        check(A and A.net == 140 and A.wins == 2 and A.games == 3, "Statistiky: hráč A",
            A and ("net %d wins %d games %d"):format(A.net, A.wins, A.games))
        check(B and B.net == -160 and B.wins == 0, "Statistiky: hráč B", B and ("net %d"):format(B.net))
        check(C and C.net == 20 and C.best == 20, "Statistiky: hráč C", C and ("net %d"):format(C.net))
        check(A and A.bestStreak == 2 and A.streak == 0, "Statistiky: série výher")
        local recent = ns.Ledger.Stats(250)
        check(recent["A-R"] and recent["A-R"].games == 1, "Statistiky: období")
        check(B and B.worst == 100 and B.bestLossStreak == 3 and A.lossStreak == 1, "Statistiky: prohry a série proher")
        local badges = ns.Ledger.Badges(s)
        local function has(name, key)
            for _, b in ipairs(badges[name] or {}) do if b.key == key then return true end end
            return false
        end
        check(has("A-R", "highroller") and not has("C-R", "highroller"), "Odznak High roller")
        check(has("B-R", "bigloss") and not has("A-R", "bigloss"), "Odznak Největší prohra")
        check(not has("A-R", "streak") and not has("B-R", "veteran10"), "Odznaky: bez série a veterána")
    end)
    db.games = saved
    if not ok then check(false, "Výjimka v testu", tostring(err)) end
end

-- Dvě lobby naráz: ustoupit musí právě jedna
local function testConflict()
    local G = ns.Game
    local a = { phase = "lobby", created = 100, host = "A-R" }
    local b = { phase = "lobby", created = 105, host = "B-R" }
    check(not G.ShouldYield(a, b) and G.ShouldYield(b, a), "Mladší lobby ustoupí starší")
    b.created = 100
    check(G.ShouldYield(a, b) ~= G.ShouldYield(b, a), "Při shodném čase ustoupí právě jedna")
    local running = { phase = "running", created = 200, host = "C-R" }
    check(G.ShouldYield(a, running) and not G.ShouldYield(running, a), "Lobby ustoupí rozehrané hře")
end

-- Porovnání verzí (0.10.0 je novější než 0.9.9)
local function testVersion()
    local cmp = ns.Version.Compare
    check(cmp("0.10.0", "0.9.9") == 1 and cmp("0.8", "0.8.0") == 0 and cmp("0.7.2", "0.8.0") == -1,
        "Porovnání verzí")
end

-- Export pro Discord bota (SUCDR_Export)
local function testExport()
    local db = ns.db
    local savedGames, savedDebts = db.games, db.debts
    db.games = {
        a = { id = "a", time = 100, bet = 100, mode = "mass", winner = "A-R", players = { "A-R", "B-R", "C-R" } },
        t = { id = "t", time = 200, bet = 5, winner = "A-R", players = { "A-R", "B-R" }, test = true },
    }
    db.debts = {
        ["a:B-R"] = { id = "a:B-R", game = "a", from = "B-R", to = "A-R", amount = 100, time = 100, paid = false,
            partial = 30 },
        ["a:C-R"] = { id = "a:C-R", game = "a", from = "C-R", to = "A-R", amount = 100, time = 100, paid = false,
            unconfirmed = true },
        ["t:B-R"] = { id = "t:B-R", game = "t", from = "B-R", to = "A-R", amount = 5, time = 200, paid = false,
            test = true },
    }
    local ok, err = pcall(function()
        local e = ns.Export.Build(1000)
        check(e.format == ns.Export.FORMAT and #e.games == 1 and e.games[1].payout == 200 and e.games[1].verified,
            "Export: hry bez testovacích")
        check(#e.debts == 2 and e.debts[1].remaining + e.debts[2].remaining == 170, "Export: dluhy a zbytek")
        local b = e.balances[1]
        check(#e.balances == 2 and b.amount == 100 and b.confirmed == 0, "Export: součty dluhů",
            b and ("%s>%s %d/%d"):format(b.from, b.to, b.amount, b.confirmed))
        local json = ns.Export.ToJSON({ b = { 1, 2 }, a = 'ŽŘř"\\\n', c = {}, d = true, e = 1.5 })
        local want = '{"a":"ŽŘř\\"\\\\\\n","b":[1,2],"c":[],"d":true,"e":1.5}'
        check(json == want, "Export: JSON", json)
        check(ns.Export.ToJSON(e):sub(1, 1) == "{", "Export: celý JSON")
    end)
    db.games, db.debts = savedGames, savedDebts
    if not ok then check(false, "Výjimka v testu", tostring(err)) end
end

-- Dlouhá oznámení do chatu (max. 255 bajtů na zprávu)
local function testChatSplit()
    local names = {}
    for i = 1, 30 do names[i] = ("Hráčřčš%d"):format(i) end
    local text = "Pořadí: " .. table.concat(names, ", ")
    local parts = ns.SplitChat(text)
    local ok = #parts > 1
    for _, p in ipairs(parts) do
        local b = p:byte(1)
        if #p > 240 or (b and b >= 0x80 and b < 0xC0) then ok = false end
    end
    check(ok and table.concat(parts, " ") == text, "Dělení dlouhého oznámení do chatu")
    check(#ns.SplitChat("krátká zpráva") == 1, "Krátké oznámení zůstane celé")
end

local function testRoll()
    local cases = {
        { "Žofie", 37, 1, 100, "Žofie-" .. ns.Realm() },
        { "Řehoř-Drakthul", 1, 1, 2, "Řehoř-Drakthul" },
        { "Bob", 999999, 1, 1000000, "Bob-" .. ns.Realm() },
    }
    for _, c in ipairs(cases) do
        local msg = RANDOM_ROLL_RESULT:format(c[1], c[2], c[3], c[4])
        local name, roll, low, high = ns.Game.ParseRoll(msg)
        check(name == c[5] and roll == c[2] and low == c[3] and high == c[4], "Čtení hodu", msg)
    end
    check(ns.Game.ParseRoll("Žofie se připojila ke skupině.") == nil, "Čtení hodu: cizí zpráva")
end

-- Hráč z jiného realmu: systémová zpráva o hodu realm neuvádí
local function testRoller()
    local G = ns.Game
    local saved = G.state
    G.state = { players = {
        { name = "Mathese-Silvermoon" }, { name = "Genoop-" .. ns.Realm() },
        { name = "Dvojnik-RealmA" }, { name = "Dvojnik-RealmB" },
    } }
    local ok, err = pcall(function()
        local p = G.FindRoller(ns.Normalize("Mathese"))
        check(p and p.name == "Mathese-Silvermoon", "Hod hráče z jiného realmu")
        p = G.FindRoller(ns.Normalize("Genoop"))
        check(p and p.name == "Genoop-" .. ns.Realm(), "Hod hráče z mého realmu")
        check(G.FindRoller(ns.Normalize("Dvojnik")) == nil, "Dvě stejná jména se nesmí splést")
        check(G.FindRoller("Mathese-JinyRealm") == nil, "Hod s jiným realmem ve zprávě")
    end)
    G.state = saved
    if not ok then check(false, "Výjimka v testu", tostring(err)) end
end

local function testSplit()
    local texts = { string.rep("ř", 300) .. "x", string.rep("a", 229) .. "čřž", string.rep("€", 200) }
    for n, text in ipairs(texts) do
        local parts = ns.CommSplit(text)
        local ok = table.concat(parts) == text
        for _, part in ipairs(parts) do
            local b = part:byte(1)
            if #part > ns.CommMaxPart or (b and b >= 0x80 and b < 0xC0) then ok = false end
        end
        check(ok, "Dělení zprávy (UTF-8) č. " .. n)
    end
end

---------------------------------------------------------------------------
-- Skutečné addon zprávy šeptem sám sobě
---------------------------------------------------------------------------
local function finish()
    if not run then return end
    if run.timer then run.timer:Cancel() end
    for case in pairs(run.expected) do
        if not run.got[case] then check(false, "Zpráva nedorazila", case) end
    end
    run = nil
    if failed == 0 then
        ns.Print(ns.T("self_ok", passed))
    else
        ns.Print(ns.T("self_fail", failed, passed))
    end
end

ns.OnComm("SELFTEST", function(_, rest)
    if not run then return end
    local id, case, data = rest:match("^([^:]+):([^|]+)|(.*)$")
    if id ~= run.id or not run.expected[case] or run.got[case] then return end
    run.got[case] = true
    check(data == run.expected[case], "Zpráva " .. case .. " dorazila poškozená",
        ("délka %d, čekáno %d"):format(#(data or ""), #run.expected[case]))
    for c in pairs(run.expected) do
        if not run.got[c] then return end
    end
    finish()
end)

function T.Run()
    if run then
        ns.Print(ns.T("self_busy"))
        return
    end
    passed, failed = 0, 0
    ns.Print(ns.T("self_checking"))
    for _, fn in ipairs({ testState, testGame, testVerify, testStats, testConflict, testRoll, testRoller, testSplit,
        testChatSplit, testVersion, testExport }) do
        local ok, err = pcall(fn)
        if not ok then check(false, "Výjimka v testu", tostring(err)) end
    end

    run = { id = tostring(math.random(100000, 999999)), got = {}, expected = {
        kratka = "ahoj",
        stav = ns.Game.Serialize(sampleState()),
        cestina = string.rep("ř", 300) .. " Příliš žluťoučký kůň úpěl ďábelské ódy.",
    } }
    local chunks = 0
    for case, data in pairs(run.expected) do
        local payload = run.id .. ":" .. case .. "|" .. data
        chunks = chunks + #ns.CommSplit("SELFTEST;" .. payload)
        ns.Send("SELFTEST", payload, "WHISPER", ns.Me())
    end
    local wait = chunks + 10
    ns.Print(ns.T("self_sending", chunks, wait))
    run.timer = C_Timer.NewTimer(wait, finish)
end

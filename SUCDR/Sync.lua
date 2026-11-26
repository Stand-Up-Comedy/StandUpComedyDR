-- SUCDR - dorovnání stavu dluhů a sběr her pro guild mastera
--
-- OPEN;<id,id,...>  "tyhle dluhy mám jako nezaplacené" - posílá se po přihlášení do guildy
--                   a do skupiny, když do ní přibude někdo nový. Věřitel, který má dluh
--                   jako zaplacený, odpoví šeptem PAID;<id>.
-- COLLECT;<dní>     guild master žádá guildu o hry. Každý odpoví šeptem: GAMEREC (hry,
--                   kde byl hostitel nebo hráč) a DEBT (dluhy, kde je věřitel).
-- LOGREQ;<id>       guild master žádá hostitele o průběh hry; hostitel odpoví LOG;<id>\n<řádky>.
local _, ns = ...

local S = {}
ns.Sync = S

local L = ns.Ledger
local function db() return ns.db end
local function T(...) return ns.T(...) end

local COLLECT_DAYS = 30
local OPEN_DAYS = 120
local OPEN_MAX = 300
local LOG_MAX_LINES = 400

---------------------------------------------------------------------------
-- Guild master
---------------------------------------------------------------------------
function S.IsGuildMaster()
    if not IsInGuild() then return false end
    local _, _, rankIndex = GetGuildInfo("player")
    return rankIndex == 0
end

-- Je hráč (Jmeno-Realm) guild master mé guildy? Bere se ze seznamu členů guildy.
function S.IsGuildMasterName(name)
    if not name or not IsInGuild() then return false end
    for i = 1, GetNumGuildMembers() do
        local n, _, rankIndex = GetGuildRosterInfo(i)
        if rankIndex == 0 then
            return ns.Normalize(n) == name
        end
    end
    return false
end

---------------------------------------------------------------------------
-- Dorovnání zaplacených dluhů (OPEN -> PAID)
---------------------------------------------------------------------------
local function openIds()
    local ids, limit = {}, time() - OPEN_DAYS * 86400
    for id, d in pairs(db().debts) do
        if not d.paid and not d.test and (d.time or 0) >= limit then
            ids[#ids + 1] = id
            if #ids >= OPEN_MAX then break end
        end
    end
    return ids
end

function S.SendOpen(channel)
    local ids = openIds()
    if #ids == 0 then return end
    if channel == "GUILD" then
        ns.SendGuild("OPEN", table.concat(ids, ","))
    else
        ns.SendGroup("OPEN", table.concat(ids, ","), "OPEN")
    end
end

ns.OnComm("OPEN", function(sender, rest)
    local me = ns.Me()
    for id in rest:gmatch("[^,]+") do
        local d = db().debts[id]
        if d and d.paid and not d.test and d.to == me then
            ns.Send("PAID", id, "WHISPER", sender)
        end
    end
end)

-- Ve skupině se objevil někdo nový: požádám o dorovnání (nejvýš jednou za minutu)
local seenInGroup, lastGroupOpen, pendingOpen = {}, 0, false
ns.On("GROUP_ROSTER_UPDATE", function()
    if pendingOpen or not ns.GroupChannel() then return end
    local me, fresh = ns.Me(), false
    for _, n in ipairs(ns.GroupMembers()) do
        if n ~= me and not seenInGroup[n] then
            seenInGroup[n] = true
            fresh = true
        end
    end
    if not fresh then return end
    pendingOpen = true
    local wait = math.max(5, 60 - (GetTime() - lastGroupOpen))
    C_Timer.After(wait, function()
        pendingOpen = false
        lastGroupOpen = GetTime()
        if ns.GroupChannel() then S.SendOpen("GROUP") end
    end)
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(30, function() S.SendOpen("GUILD") end)
end)

---------------------------------------------------------------------------
-- Sběr her pro guild mastera
---------------------------------------------------------------------------
local collecting = nil     -- { until = čas, games = n, from = { [jméno] = true } }
local lastCollect = 0

function S.RequestCollect()
    if not S.IsGuildMaster() then
        ns.Print(T("collect_not_gm"))
        return
    end
    if GetTime() - lastCollect < 60 then
        ns.Print(T("collect_wait"))
        return
    end
    lastCollect = GetTime()
    local c = { untilT = GetTime() + 300, games = 0, from = {} }
    collecting = c
    ns.SendGuild("COLLECT", tostring(COLLECT_DAYS))
    ns.Print(T("collect_sent", COLLECT_DAYS))
    -- průběžný souhrn po dvou minutách; odpovědi se přijímají ještě 5 minut
    -- (kdo má hodně her, posílá je kvůli limitu zpráv postupně)
    C_Timer.After(120, function()
        if collecting ~= c then return end
        local n = 0
        for _ in pairs(c.from) do n = n + 1 end
        ns.Print(T("collect_done", c.games, n))
        ns.RefreshUI()
    end)
    C_Timer.After(300, function()
        if collecting == c then collecting = nil end
    end)
end

local answered = {}
ns.OnComm("COLLECT", function(sender, rest, channel)
    if channel ~= "GUILD" then return end
    -- seznam členů guildy může být neaktuální, tak ho nechám obnovit a ověřím až za chvíli
    if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
    local days = math.min(tonumber(rest) or COLLECT_DAYS, 90)
    if answered[sender] and GetTime() - answered[sender] < 50 then return end
    answered[sender] = GetTime()
    -- náhodné zpoždění, ať neodpovídá celá guilda naráz
    C_Timer.After(3 + math.random() * 25, function()
        if not S.IsGuildMasterName(sender) then return end
        local me, limit = ns.Me(), time() - days * 86400
        for _, g in pairs(db().games) do
            if not g.test and g.winner and (g.time or 0) >= limit and not g.unverified
                and (g.host == me or tContains(g.players, me)) then
                ns.Send("GAMEREC", L.SerializeGame(g), "WHISPER", sender)
            end
        end
        for _, d in pairs(db().debts) do
            if d.to == me and not d.test and (d.time or 0) >= limit then
                ns.Send("DEBT", table.concat({ d.id, d.game, d.from, d.to, d.amount, d.time or 0,
                    d.paid and 1 or 0 }, ";"), "WHISPER", sender)
            end
        end
    end)
end)

-- Hra od člena guildy. Přijímá ji jen guild master, který o hry požádal,
-- a jen od hostitele nebo hráče té hry.
ns.OnComm("GAMEREC", function(sender, rest, channel)
    if channel ~= "WHISPER" or not collecting or GetTime() > collecting.untilT then return end
    local g = L.ParseGame(rest)
    if not g or (g.host ~= sender and not tContains(g.players, sender)) then return end
    collecting.from[sender] = true
    local me = ns.Me()
    local old = db().games[g.id]
    if old then
        -- hru už mám (např. jako neověřenou z guild zprávy) - potvrzuje ji hostitel nebo hráč
        if old.unverified and not old.test then
            old.unverified = nil
            old.collected = old.collected or sender
            collecting.games = collecting.games + 1
        end
        return
    end
    g.collected = sender
    -- dluhy, které se týkají mě, nechám neověřené, pokud jsem hru sám neviděl
    local mine = L.Verify(g)
    if L.AddGame(g, true) then
        collecting.games = collecting.games + 1
        if not mine then
            for _, d in pairs(db().debts) do
                if d.game == g.id and (d.from == me or d.to == me) then d.unconfirmed = true end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Průběh (log) hry od hostitele
---------------------------------------------------------------------------
local logWanted = {}

function S.CanRequestLog(g)
    return g and not g.log and not g.test and g.host and g.host ~= ns.Me() and S.IsGuildMaster()
end

function S.RequestLog(g)
    if not S.CanRequestLog(g) then return end
    logWanted[g.id] = GetTime()
    ns.Send("LOGREQ", g.id, "WHISPER", g.host)
    ns.Print(T("log_requested", ns.Display(g.host)))
end

ns.OnComm("LOGREQ", function(sender, id)
    local g = db().games[id]
    if not g or g.test or g.host ~= ns.Me() then return end
    if not S.IsGuildMasterName(sender) then return end
    local lines = {}
    for i, l in ipairs(g.log or {}) do
        if i > LOG_MAX_LINES then break end
        lines[#lines + 1] = (l:gsub("\n", " "))
    end
    if #lines == 0 then return end
    ns.Send("LOG", id .. "\n" .. table.concat(lines, "\n"), "WHISPER", sender)
end)

ns.OnComm("LOG", function(sender, rest, channel)
    if channel ~= "WHISPER" then return end
    local id, body = rest:match("^([^\n]+)\n(.*)$")
    local g = id and db().games[id]
    if not g or g.host ~= sender or not logWanted[id] then return end
    logWanted[id] = nil
    local lines = {}
    for l in (body .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
    g.log = lines
    ns.Print(T("log_received", ns.Display(sender)))
    ns.RefreshUI()
end)

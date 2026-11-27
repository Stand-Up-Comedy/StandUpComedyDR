-- SUCDR - výzva na duel
-- Pravý klik na hráče (nebo /sucdr vyzva Jmeno) pošle šeptem výzvu o sázku z okna.
-- Vyzvaný ji přijme nebo odmítne. Po přijetí vyzyvatel hráče pozve do skupiny
-- (když v ní ještě není) a jakmile jsou spolu ve skupině, duel se sám založí a spustí.
--
-- Zprávy (šeptem): CHAL "id;sázka", CHALOK "id", CHALNO "id;důvod" (důvod: no / busy)
local _, ns = ...
local T = ns.T

local C = {}
ns.Challenge = C

C.ANSWER_TIME = 60 -- jak dlouho čekám na odpověď
C.GROUP_TIME = 120 -- jak dlouho po přijetí čekám, až bude vyzvaný ve skupině

C.DECLINE_PAUSE = 60 -- po odmítnutí od stejného hráče výzvu chvíli neukazuji

local declined = {} -- [jméno] = čas, kdy jsem ho odmítl
local outgoing -- moje výzva: { id, target, bet, t, accepted }
local incoming -- výzva pro mě: { id, from, bet, t }

local function busy()
    local s = ns.Game.state
    return s ~= nil and s.phase ~= "done" and not ns.Game.ForeignStale()
end

local function clearOutgoing(id)
    if outgoing and (not id or outgoing.id == id) then outgoing = nil end
end

-- Pro test a UI: aktuální odeslaná výzva
function C.Outgoing() return outgoing end

-- Odpověď přijde se jménem přesně jako ve hře, já ho mohl napsat jinou velikostí písmen
local function isTarget(o, sender)
    if o.target:lower() ~= sender:lower() then return false end
    o.target = sender
    return true
end

function C.Send(name)
    name = ns.Normalize(name)
    if not name then
        ns.Print(T("chal_need_name"))
        return
    end
    if name == ns.Me() then return end
    if ns.Game.testMode then
        ns.Print(T("chal_no_test"))
        return
    end
    if busy() then
        ns.Print(T("game_exists"))
        return
    end
    local bet = math.floor(tonumber(ns.db.bet) or 0)
    if bet < 2 or bet > ns.Game.MAX_ROLL then
        ns.Print(T("bad_bet"))
        return
    end
    local id = (UnitName("player") or "x") .. time() .. math.random(100, 999)
    outgoing = { id = id, target = name, bet = bet, t = GetTime() }
    ns.Send("CHAL", id .. ";" .. bet, "WHISPER", name)
    ns.Print(T("chal_sent", ns.Display(name), ns.Gold(bet)))
    C_Timer.After(C.ANSWER_TIME, function()
        if outgoing and outgoing.id == id and not outgoing.accepted then
            clearOutgoing(id)
            ns.Print(T("chal_no_answer", ns.Display(name)))
        end
    end)
end

-- Vyzvaný je se mnou ve skupině: založ a spusť duel. Jinak ho pozvi.
function C.TryStart()
    local o = outgoing
    if not o or not o.accepted then return end
    if GetTime() - o.accepted > C.GROUP_TIME then
        clearOutgoing()
        ns.Print(T("chal_group_timeout", ns.Display(o.target)))
        return
    end
    if ns.GroupChannel() and ns.IsInMyGroup(o.target) then
        if busy() then
            clearOutgoing()
            ns.Print(T("game_exists"))
            return
        end
        clearOutgoing()
        ns.Game.ChallengeDuel(o.target, o.bet)
        return
    end
    if not o.invited then
        o.invited = true
        local invite = (C_PartyInfo and C_PartyInfo.InviteUnit) or InviteUnit
        if invite then pcall(invite, o.target) end
        ns.Print(T("chal_inviting", ns.Display(o.target)))
    end
end

ns.On("GROUP_ROSTER_UPDATE", function() C.TryStart() end)

---------------------------------------------------------------------------
-- Přijetí výzvy
---------------------------------------------------------------------------
local function answer(ok)
    local i = incoming
    incoming = nil
    if not i then return end
    if ok then
        if busy() then
            ns.Send("CHALNO", i.id .. ";busy", "WHISPER", i.from)
            ns.Print(T("game_exists"))
            return
        end
        ns.Send("CHALOK", i.id, "WHISPER", i.from)
        if ns.IsInMyGroup(i.from) then
            ns.Print(T("chal_accepted_me", ns.Display(i.from)))
        else
            ns.Print(T("chal_accepted_invite", ns.Display(i.from)))
        end
    else
        declined[i.from] = GetTime()
        ns.Send("CHALNO", i.id .. ";no", "WHISPER", i.from)
    end
end
C.Answer = answer

ns.OnComm("CHAL", function(sender, rest)
    local id, bet = strsplit(";", rest or "")
    bet = tonumber(bet)
    if not id or id == "" or not bet or bet < 2 or bet > ns.Game.MAX_ROLL or bet ~= math.floor(bet) then return end
    if declined[sender] and GetTime() - declined[sender] < C.DECLINE_PAUSE then
        ns.Send("CHALNO", id .. ";no", "WHISPER", sender)
        return
    end
    if busy() or (incoming and GetTime() - incoming.t < C.ANSWER_TIME) then
        ns.Send("CHALNO", id .. ";busy", "WHISPER", sender)
        return
    end
    incoming = { id = id, from = sender, bet = bet, t = GetTime() }
    if ns.db.sound then PlaySound(SOUNDKIT.READY_CHECK) end
    ns.Print(T("chal_incoming", ns.Display(sender), ns.Gold(bet)))
    if ns.UI and ns.UI.Confirm then
        ns.UI.Confirm(T("chal_incoming", ns.Display(sender), ns.Gold(bet)), {
            { T("chal_accept"), function() answer(true) end, true },
            { T("chal_decline"), function() answer(false) end },
        })
    end
    local myId = id
    C_Timer.After(C.ANSWER_TIME, function()
        if incoming and incoming.id == myId then incoming = nil end
    end)
end)

ns.OnComm("CHALOK", function(sender, id)
    local o = outgoing
    if not o or o.id ~= id or o.accepted or not isTarget(o, sender) then return end
    o.accepted = GetTime()
    ns.Print(T("chal_accepted", ns.Display(sender)))
    C.TryStart()
    C_Timer.After(C.GROUP_TIME + 1, function() C.TryStart() end)
end)

ns.OnComm("CHALNO", function(sender, rest)
    local id, why = strsplit(";", rest or "")
    local o = outgoing
    if not o or o.id ~= id or not isTarget(o, sender) then return end
    clearOutgoing()
    ns.Print(T(why == "busy" and "chal_busy" or "chal_declined", ns.Display(sender)))
end)

---------------------------------------------------------------------------
-- Pravý klik na hráče
---------------------------------------------------------------------------
local MENUS = {
    "MENU_UNIT_PLAYER", "MENU_UNIT_PARTY", "MENU_UNIT_RAID_PLAYER", "MENU_UNIT_TARGET", "MENU_UNIT_FOCUS",
    "MENU_UNIT_FRIEND", "MENU_UNIT_GUILD", "MENU_UNIT_COMMUNITIES_GUILD_MEMBER", "MENU_UNIT_CHAT_ROSTER",
}

-- Jméno "Jmeno-Realm" z kontextu menu
local function contextName(ctx)
    if not ctx then return nil end
    if ctx.unit and UnitIsPlayer(ctx.unit) then return ns.UnitFull(ctx.unit) end
    local name = ctx.name
    if not name or name == "" then return nil end
    if ctx.server and ctx.server ~= "" and not name:find("-", 1, true) then
        name = name .. "-" .. ctx.server:gsub("[%s%-]", "")
    end
    return ns.Normalize(name)
end
C.ContextName = contextName

ns.OnInit(function()
    if not Menu or not Menu.ModifyMenu then return end
    for _, tag in ipairs(MENUS) do
        pcall(Menu.ModifyMenu, tag, function(_, root, ctx)
            local name = contextName(ctx)
            if not name or name == ns.Me() or ns.IsSecret(name) then return end
            root:CreateDivider()
            -- text bez č, ř, ě, ů: menu kreslí font WoW
            root:CreateButton(T("chal_menu", ns.Gold(ns.db.bet)), function() C.Send(name) end)
        end)
    end
end)

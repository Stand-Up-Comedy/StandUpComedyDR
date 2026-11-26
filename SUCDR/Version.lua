-- SUCDR - kontrola verzí mezi hráči
-- VER;<verze> jde do guildy po přihlášení a do skupiny, když v ní je někdo nový.
-- Kdo má novější verzi, odpoví staršímu šeptem, aby se dozvěděl o aktualizaci.
local _, ns = ...
local T = ns.T

local V = {}
ns.Version = V

V.mine = C_AddOns.GetAddOnMetadata("SUCDR", "Version") or "0"
V.known = {}           -- [jméno] = verze, jen za toto přihlášení

local told = {}        -- komu ve skupině už moje verze odešla
local replied = {}     -- komu z guildy jsem už odpověděl
local warnedOld = {}   -- o kom už víme, že má starou verzi
local newestNotified = V.mine

-- 1 = a je novější, -1 = b je novější, 0 = stejné
function V.Compare(a, b)
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

local GROUP = { PARTY = true, RAID = true, INSTANCE_CHAT = true }

ns.OnComm("VER", function(sender, payload, channel)
    local v = payload:match("^(%d+[%d%.]*)$")
    if not v or #v > 20 then return end
    V.known[sender] = v
    local cmp = V.Compare(v, V.mine)
    if cmp > 0 then
        if V.Compare(v, newestNotified) > 0 then
            newestNotified = v
            ns.Print(T("ver_newer", v, ns.Display(sender), V.mine))
        end
    elseif cmp < 0 then
        if GROUP[channel] and not warnedOld[sender] then
            warnedOld[sender] = true
            ns.Print(T("ver_older", ns.Display(sender), v))
        end
        -- staršímu v guildě dám vědět šeptem (s náhodným zpožděním, ať neodpovídá celá guilda naráz)
        if channel == "GUILD" and not replied[sender] then
            replied[sender] = true
            C_Timer.After(2 + math.random() * 18, function()
                ns.Send("VER", V.mine, "WHISPER", sender)
            end)
        end
    end
end)

-- Ve skupině pošle verzi, jen když přibyl někdo, kdo ji ještě nedostal
local pending = false
local function announceGroup()
    pending = false
    if not ns.GroupChannel() then return end
    local me, fresh = ns.Me(), false
    local members = ns.GroupMembers()
    for _, n in ipairs(members) do
        if n ~= me and not told[n] then fresh = true end
    end
    if not fresh then return end
    for _, n in ipairs(members) do told[n] = true end
    ns.SendGroup("VER", V.mine, "VER")
end

ns.On("GROUP_ROSTER_UPDATE", function()
    if pending then return end
    pending = true
    C_Timer.After(3, announceGroup)
end)

ns.On("PLAYER_LOGIN", function()
    C_Timer.After(25, function() ns.SendGuild("VER", V.mine) end)
    C_Timer.After(8, announceGroup)
end)

-- /sucdr version
function V.Print()
    ns.Print(T("ver_mine", V.mine))
    local names = {}
    for n in pairs(V.known) do names[#names + 1] = n end
    table.sort(names)
    if #names == 0 then
        ns.Print(T("ver_none"))
        return
    end
    for _, n in ipairs(names) do
        local v = V.known[n]
        local c = V.Compare(v, V.mine)
        local color = (c < 0 and "|cffff6a66") or (c > 0 and "|cff66e680") or "|cffffffff"
        ns.Print(("  %s: %s%s|r"):format(ns.Display(n), color, v))
    end
end

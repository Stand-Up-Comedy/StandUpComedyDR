-- SUCDR - Stand up Comedy death roll
-- Core: nastavení, události, pomocné funkce
local ADDON_NAME, ns = ...

ns.PREFIX = "SUCDR"
ns.MEDIA = "Interface\\AddOns\\SUCDR\\Media\\"
ns.ICON = ns.MEDIA .. "icon"   -- komik z loga guildy (64x64 TGA)
ns.LOGO = ns.MEDIA .. "logo"   -- celé logo Stand Up Comedy (256x256 TGA)

local defaults = {
    bet = 1000,       -- sázka v goldech
    roundTime = 30,   -- limit na hod/kolo v sekundách, 0 = bez limitu
    announce = true,  -- oznamovat průběh do party/raid chatu
    lang = "cs",      -- jazyk addonu: "cs" nebo "en"
    sound = true,     -- zvuk na tahu a při nové lobby
    autoOpen = true,  -- otevřít okno, když se přidám do hry
    minimap = true,   -- ikona u minimapy
    minimapAngle = 200, -- poloha ikony na okraji minimapy (stupně)
    remind = true,    -- připomínat dluhy po přihlášení a ve skupině
    tooltip = true,   -- tituly a počet her v tooltipu hráče
    font = true,      -- moderní font Inter (false = font z chatu)
    statsPeriod = "all", -- období statistik: "all", "30", "7"
    statsSort = "net",   -- řazení žebříčku: "net", "wins", "games"
}

---------------------------------------------------------------------------
-- Události
---------------------------------------------------------------------------
local handlers = {}
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        -- chyba v jedné obsluze nesmí zastavit ostatní (chyba se dál ukáže normálně)
        for i = 1, #list do xpcall(list[i], geterrorhandler(), ...) end
    end
end)

function ns.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

local initFns = {}
function ns.OnInit(fn) table.insert(initFns, fn) end

ns.On("ADDON_LOADED", function(name)
    if name ~= ADDON_NAME then return end
    SUCDR_DB = SUCDR_DB or {}
    for k, v in pairs(defaults) do
        if SUCDR_DB[k] == nil then SUCDR_DB[k] = v end
    end
    SUCDR_DB.debts = SUCDR_DB.debts or {}
    SUCDR_DB.games = SUCDR_DB.games or {}
    ns.db = SUCDR_DB
    for _, fn in ipairs(initFns) do fn() end
end)

-- Přepíše UI.lua
function ns.RefreshUI() end

---------------------------------------------------------------------------
-- Pomocné funkce
---------------------------------------------------------------------------
function ns.Print(msg)
    print("|cffff8800SUCDR|r: " .. tostring(msg))
end

-- Midnight: některé hodnoty můžou být v boji/instanci "secret" a nejde s nimi pracovat
function ns.IsSecret(...)
    if not issecretvalue then return false end
    for i = 1, select("#", ...) do
        if issecretvalue((select(i, ...))) then return true end
    end
    return false
end

function ns.Realm()
    return GetNormalizedRealmName() or ((GetRealmName() or ""):gsub("[%s%-]", ""))
end

-- Všechna jména ukládáme jako "Jmeno-Realm"
function ns.Normalize(name)
    if not name or name == "" then return nil end
    if name:find("-", 1, true) then return name end
    return name .. "-" .. ns.Realm()
end

function ns.Me()
    return ns.Normalize(UnitName("player"))
end

function ns.UnitFull(unit)
    local n, r = UnitFullName(unit)
    if not n then return nil end
    if r and r ~= "" then return n .. "-" .. r end
    return ns.Normalize(n)
end

function ns.Display(name)
    return name and Ambiguate(name, "none") or "?"
end

function ns.Gold(n)
    return BreakUpLargeNumbers(n or 0) .. "g"
end

function ns.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
    return nil
end

function ns.GroupMembers()
    local list = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            local n = ns.UnitFull("raid" .. i)
            if n then list[#list + 1] = n end
        end
    else
        list[1] = ns.Me()
        for i = 1, GetNumSubgroupMembers() do
            local n = ns.UnitFull("party" .. i)
            if n then list[#list + 1] = n end
        end
    end
    return list
end

-- Jednotka (target / party1 / raid5...) hráče podle jména "Jmeno-Realm", nebo nil
function ns.UnitByName(name)
    if ns.UnitFull("target") == name and UnitIsPlayer("target") then return "target" end
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do
            if ns.UnitFull("raid" .. i) == name then return "raid" .. i end
        end
    else
        for i = 1, GetNumSubgroupMembers() do
            if ns.UnitFull("party" .. i) == name then return "party" .. i end
        end
    end
    return nil
end

function ns.IsInMyGroup(name)
    for _, n in ipairs(ns.GroupMembers()) do
        if n == name then return true end
    end
    return false
end

-- Zpráva do chatu smí mít nejvýš 255 bajtů. Delší text (např. seznam 20 jmen)
-- rozdělíme na mezerách, nikdy uprostřed UTF-8 znaku.
local CHAT_MAX = 240
function ns.SplitChat(text, max)
    max = max or CHAT_MAX
    local parts = {}
    while #text > max do
        local cut = max
        local space = text:sub(1, max + 1):match("^.*() ")
        if space and space > max / 2 then
            cut = space - 1
        else
            while cut > 1 do
                local b = text:byte(cut + 1)
                if not b or b < 0x80 or b >= 0xC0 then break end
                cut = cut - 1
            end
        end
        parts[#parts + 1] = text:sub(1, cut)
        text = text:sub(cut + 1):gsub("^ +", "")
    end
    if text ~= "" or #parts == 0 then parts[#parts + 1] = text end
    return parts
end

-- Oznámení do party/raid chatu (nebo jen lokálně, když nejsme ve skupině)
function ns.Announce(msg)
    local ch = ns.GroupChannel()
    if not ns.db.announce or not ch then
        ns.Print(msg)
        return
    end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    for _, part in ipairs(ns.SplitChat(msg)) do
        local ok = pcall(send, "[SUCDR] " .. part, ch)
        if not ok then
            ns.Print(msg)
            return
        end
    end
end

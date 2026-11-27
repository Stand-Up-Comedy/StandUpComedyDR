-- SUCDR - tituly v tooltipu hráče
-- Po najetí myší na hráče se pod tooltip přidá jeho titul (odznaky ze statistik)
-- a počet her. Počítá se z her, které mám uložené (stejně jako žebříček za celé období),
-- nic se kvůli tomu neposílá.
local _, ns = ...
local T = ns.T

local Tip = {}
ns.Tooltip = Tip

local ACCENT = "|cffff8f29"
-- pořadí titulů v tooltipu: nejdřív "hodnost" podle počtu her, pak rekordy a série
local ORDER = { veteran500 = 1, veteran100 = 1, veteran50 = 1, veteran10 = 1,
    highroller = 2, streak = 3, unlucky = 4, bigloss = 5 }

local cache, cacheRev
local function data()
    local L = ns.Ledger
    if not cache or cacheRev ~= L.rev then
        local stats = L.Stats()
        cache = { stats = stats, badges = L.Badges(stats) }
        cacheRev = L.rev
    end
    return cache
end

-- Řádky do tooltipu pro hráče "Jmeno-Realm", nebo nil (žádná odehraná hra)
function Tip.Lines(name)
    local d = data()
    local p = name and d.stats[name]
    if not p or p.games == 0 then return nil end
    local list = {}
    for _, b in ipairs(d.badges[name] or {}) do list[#list + 1] = b end
    table.sort(list, function(a, b) return (ORDER[a.key] or 9) < (ORDER[b.key] or 9) end)
    local titles = {}
    for i, b in ipairs(list) do titles[i] = T("badge_" .. b.key) end
    local first = ACCENT .. "SUCDR|r  " .. (#titles > 0 and table.concat(titles, ", ") or T("tip_no_title"))
    return first, T("tip_stats", p.games, p.wins)
end

local function onUnit(tip)
    if tip ~= GameTooltip or not ns.db or not ns.db.tooltip or InCombatLockdown() then return end
    local ok, _, unit = pcall(tip.GetUnit, tip)
    if not ok or not unit or ns.IsSecret(unit) then return end
    local isPlayer = UnitIsPlayer(unit)
    if ns.IsSecret(isPlayer) or not isPlayer then return end
    local name = ns.UnitFull(unit)
    if not name or ns.IsSecret(name) then return end
    local a, b = Tip.Lines(name)
    if not a then return end
    local first = tip:NumLines() + 1
    tip:AddLine(a)
    tip:AddLine(b, 0.75, 0.75, 0.75)
    if ns.UI and ns.UI.CzechTooltip then ns.UI.CzechTooltip(first) else tip:Show() end
end

ns.OnInit(function()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnit)
    end
end)

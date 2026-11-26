-- SUCDR - export pro externí programy (Discord bot Comedy Tools)
-- Při odhlášení / reloadu se do SavedVariables SUCDR_Export zapíše přehled her a dluhů
-- v jednoduchém stabilním formátu. Popis formátu: EXPORT.md. Testovací data se neexportují.
local _, ns = ...

local E = {}
ns.Export = E

E.FORMAT = 2 -- 1 = Lua tabulka (0.9.0-0.9.1), 2 = JSON řetězec

local function sortByTime(list)
    table.sort(list, function(a, b)
        if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
        return a.id < b.id
    end)
end

function E.Build(now)
    local db = ns.db
    local out = {
        format = E.FORMAT,
        addonVersion = ns.Version and ns.Version.mine or "?",
        exporter = ns.Me(),
        exportedAt = now or time(),
        games = {},
        debts = {},
        balances = {},
    }

    for _, g in pairs(db.games) do
        if not g.test and g.winner then
            local players, payers = {}, 0
            for i, p in ipairs(g.players) do
                players[i] = p
                if p ~= g.winner and (not g.loser or p == g.loser) then payers = payers + 1 end
            end
            out.games[#out.games + 1] = {
                id = g.id, time = g.time, host = g.host, bet = g.bet, mode = g.mode,
                winner = g.winner, loser = g.loser, players = players,
                payout = g.bet * payers, verified = not g.unverified,
            }
        end
    end
    sortByTime(out.games)

    local pairSum = {}
    for _, d in pairs(db.debts) do
        if not d.test then
            local remaining = d.paid and 0 or ns.Ledger.Remaining(d)
            out.debts[#out.debts + 1] = {
                id = d.id, game = d.game, from = d.from, to = d.to, time = d.time,
                amount = d.amount, remaining = remaining,
                paid = d.paid and true or false, paidAt = d.paidTime,
                confirmed = not d.unconfirmed,
            }
            if remaining > 0 then
                local key = d.from .. ">" .. d.to
                local b = pairSum[key]
                if not b then
                    b = { from = d.from, to = d.to, amount = 0, confirmed = 0, since = d.time }
                    pairSum[key] = b
                    out.balances[#out.balances + 1] = b
                end
                b.amount = b.amount + remaining
                if not d.unconfirmed then b.confirmed = b.confirmed + remaining end
                if (d.time or 0) < (b.since or math.huge) then b.since = d.time end
            end
        end
    end
    sortByTime(out.debts)
    table.sort(out.balances, function(a, b)
        if a.amount ~= b.amount then return a.amount > b.amount end
        return a.from .. a.to < b.from .. b.to
    end)
    return out
end

---------------------------------------------------------------------------
-- JSON: hra umí uložit jen Lua hodnoty, proto se export ukládá jako jeden
-- řetězec s hotovým JSONem (UTF-8, klíče seřazené, bez odsazení).
-- Tabulka s prvky 1..n = pole, prázdná tabulka = [], jinak objekt.
---------------------------------------------------------------------------
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function jsonString(s)
    -- jen ASCII řídicí znaky 0-31 (%c na Windows bere i bajty 0x80-0x9F z UTF-8, např. v "Ř")
    return '"' .. s:gsub('[%z\1-\31"\\]', function(c)
        return ESC[c] or ("\\u%04x"):format(c:byte())
    end) .. '"'
end

local function encode(v, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = jsonString(v)
    elseif t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then
            out[#out + 1] = "null"
        elseif v == math.floor(v) and math.abs(v) < 2 ^ 53 then
            out[#out + 1] = ("%d"):format(v)
        else
            out[#out + 1] = ("%.14g"):format(v)
        end
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
        if #v > 0 or next(v) == nil then
            out[#out + 1] = "["
            for i = 1, #v do
                if i > 1 then out[#out + 1] = "," end
                encode(v[i], out)
            end
            out[#out + 1] = "]"
        else
            local keys = {}
            for k in pairs(v) do keys[#keys + 1] = tostring(k) end
            table.sort(keys)
            out[#out + 1] = "{"
            for i, k in ipairs(keys) do
                if i > 1 then out[#out + 1] = "," end
                out[#out + 1] = jsonString(k)
                out[#out + 1] = ":"
                encode(v[k], out)
            end
            out[#out + 1] = "}"
        end
    else
        out[#out + 1] = "null"
    end
end

function E.ToJSON(v)
    local out = {}
    encode(v, out)
    return table.concat(out)
end

-- SavedVariables se zapisují hned po PLAYER_LOGOUT (odhlášení, konec hry i /reload)
ns.On("PLAYER_LOGOUT", function()
    if not ns.db then return end
    SUCDR_Export = E.ToJSON(E.Build())
end)

-- Tlačítko / příkaz Exportovat: addon neumí zapsat soubor sám, zápis udělá až reload.
-- Rozehraná hra by se reloadem ukončila (u hostitele), proto se během hry nepovolí.
function E.Run()
    local s = ns.Game.state
    if s and not s.test and s.phase ~= "done" then
        ns.Print(ns.T("export_busy"))
        return
    end
    local T = ns.T
    ns.UI.Confirm(T("export_confirm"), { { T("btn_yes"), ReloadUI, true }, { T("btn_no") } })
end

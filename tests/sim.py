"""Simulace SUCDR pro víc hráčů naráz (každý hráč = vlastní Lua 5.1 runtime).
Spuštění: python sim.py <složka addonu>"""
import sys, os
from lupa import lua51

ADDON = sys.argv[1]
FILES = ["Core.lua", "Locale.lua", "Ledger.lua", "Game.lua", "Challenge.lua", "Tooltip.lua"]
REALM = "Drakthul"

STUBS = r"""
local me, others = ...
__group = others -- kdo je se mnou ve skupině (jména bez realmu)
__invites = {}
__out = {}
local _xp = xpcall
function xpcall(f, h, ...) local a, n = {...}, select("#", ...) return _xp(function() return f(unpack(a, 1, n)) end, h) end
__sent = {}
__frames = {}
__now = 1000
__clock = 1732190000
function CreateFrame() local f = { scripts = {} }
  function f:SetScript(k, fn) self.scripts[k] = fn end
  function f:RegisterEvent() end
  __frames[#__frames + 1] = f
  return f end
function __fire(ev, ...) for _, f in ipairs(__frames) do if f.scripts.OnEvent then f.scripts.OnEvent(f, ev, ...) end end end
function geterrorhandler() return function(e) error(e, 0) end end
function print(m) __out[#__out + 1] = m end
function UnitName(u) if u == "player" then return me end end
function UnitFullName(u)
  if u == "player" then return me, "Drakthul" end
  local i = tonumber(u:match("^party(%d+)$") or "")
  if i and __group[i] then return __group[i], "Drakthul" end
end
function UnitIsPlayer() return true end
function UnitExists() return false end
function GetNormalizedRealmName() return "Drakthul" end
function GetRealmName() return "Drakthul" end
function Ambiguate(n) return (n:gsub("%-Drakthul$", "")) end
function BreakUpLargeNumbers(n) return tostring(n) end
function IsInGroup() return true end
function IsInRaid() return false end
function IsInGuild() return true end
LE_PARTY_CATEGORY_INSTANCE = 2
function IsInGroup(cat) if cat == 2 then return false end return #__group > 0 end
function GetNumSubgroupMembers() return #__group end
function GetNumGroupMembers() return #__group + 1 end
function GetTime() return __now end
function time() return __clock end
date = os.date
function strsplit(sep, s)
  local t, pat = {}, "([^" .. sep .. "]*)" .. sep .. "?"
  local pos = 1
  while true do
    local a, b = s:find(sep, pos, true)
    if not a then t[#t + 1] = s:sub(pos); break end
    t[#t + 1] = s:sub(pos, a - 1)
    pos = b + 1
  end
  return unpack(t)
end
function tContains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end
RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
__rolls = {}
function RandomRoll(a, b) __rolls[#__rolls + 1] = { a, b } end
SOUNDKIT = {}
function PlaySound() end
C_AddOns = { GetAddOnMetadata = function() return "0.10.0" end }
C_ChatInfo = { SendChatMessage = function(m) __out[#__out + 1] = "CHAT " .. m end }
C_Timer = {
  After = function() end,
  NewTimer = function() return { Cancel = function() end } end,
  NewTicker = function() return { Cancel = function() end } end,
}
function InCombatLockdown() return false end
C_PartyInfo = { InviteUnit = function(n) __invites[#__invites + 1] = n end }
function GetMoney() return 10^12 end
SUCDR_DB = nil
"""

COMM = r"""
local ns = ...
local h = {}
function ns.OnComm(t, fn) h[t] = h[t] or {}; table.insert(h[t], fn) end
function ns.Send(t, p, ch, target) __sent[#__sent + 1] = { t, p, ch, target } end
function ns.SendGroup(t, p) __sent[#__sent + 1] = { t, p, "GROUP" } end
function ns.SendGuild(t, p) __sent[#__sent + 1] = { t, p, "GUILD" } end
function __deliver(t, sender, p) for _, fn in ipairs(h[t] or {}) do fn(sender, p) end end
"""


class Player:
    def __init__(self, name, others):
        self.name = name
        self.full = name + "-" + REALM
        self.lua = lua51.LuaRuntime(unpack_returned_tuples=True)
        lua = self.lua
        lua.execute("function __mk(t) local r = {} for i, v in python.iter(t) do r[#r+1] = v end return r end")
        lua.execute(STUBS.replace("local me, others = ...", "local me, others = __ME, __OTHERS")
                    .replace("__ME", repr(name)).replace("__OTHERS", "{" + ",".join(repr(o) for o in others) + "}"))
        self.ns = lua.table()
        lua.globals()["__ns"] = self.ns
        lua.execute("local ns = __ns; " + COMM.replace("local ns = ...", ""))
        for f in FILES:
            src = open(os.path.join(ADDON, f), encoding="utf-8").read()
            fn = lua.execute("return function(src, name) return assert(loadstring(src, '@' .. name)) end")(src, f)
            fn("SUCDR", self.ns)
        lua.execute("__fire('ADDON_LOADED', 'SUCDR')")
        lua.execute("__ns.db.roundTime = 0; __ns.db.sound = false; __ns.db.autoOpen = false")

    def run(self, code):
        return self.lua.execute("local ns, G, L = __ns, __ns.Game, __ns.Ledger\n" + code)

    def out(self):
        o = list(self.lua.globals()["__out"].values())
        self.lua.execute("__out = {}")
        return o


class World:
    def __init__(self, names):
        self.players = {n: Player(n, [o for o in names if o != n]) for n in names}

    def p(self, n):
        return self.players[n]

    def pump(self):
        moved = True
        while moved:
            moved = False
            for n, pl in self.players.items():
                sent = list(pl.lua.globals()["__sent"].values())
                pl.lua.execute("__sent = {}")
                for m in sent:
                    t, payload, ch = m[1], m[2], m[3]
                    target = m[4] if len(m) >= 4 else None
                    moved = True
                    for on, op in self.players.items():
                        if on == n:
                            continue
                        if ch == "WHISPER" and target != op.full:
                            continue
                        op.lua.globals()["__deliver"](t, pl.full, payload)

    def roll(self, who, value, low, high):
        """Hod hráče `who`: systémovou zprávu vidí všichni ve skupině."""
        msg = f"{who} rolls {value} ({low}-{high})"
        for pl in self.players.values():
            pl.lua.globals()["__fire"]("CHAT_MSG_SYSTEM", msg)
        self.pump()

    def set_group(self, groups):
        """groups: seznam skupin (seznamů jmen); kdo v žádné není, je sám."""
        for n, pl in self.players.items():
            mates = next((g for g in groups if n in g), [n])
            lst = "{" + ",".join(repr(o) for o in mates if o != n) + "}"
            pl.lua.execute(f"__group = {lst}")
        for pl in self.players.values():
            pl.lua.execute("__fire('GROUP_ROSTER_UPDATE')")
            self.pump()

    def tick(self, sec):
        for pl in self.players.values():
            pl.lua.execute(f"__now = __now + {sec}; __clock = __clock + {sec}")


FAILS = []


def check(cond, label, extra=""):
    print(("OK   " if cond else "FAIL ") + label + ((" | " + str(extra)) if extra and not cond else ""))
    if not cond:
        FAILS.append(label)


def debts(pl):
    """Otevřené / zaplacené dluhy hráče jako seznam (from, to, amount, paid)."""
    res = pl.run("""
        local out = {}
        for id, d in pairs(ns.db.debts) do
            out[#out + 1] = d.from .. '>' .. d.to .. ':' .. d.amount .. ':' .. (d.paid and 'P' or 'O')
                .. (d.unconfirmed and ':U' or '')
        end
        table.sort(out)
        return table.concat(out, ',')
    """)
    return res


def state(pl, field):
    return pl.run(f"local s = G.state; return s and s.{field}")

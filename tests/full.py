"""Celý addon podle TOC se skutečným Comm.lua (zprávy se dělí, posílají a skládají jako ve hře),
/sucdr selftest a regresní scénáře z kontroly kódu. Spuštění: python tests/full.py SUCDR"""
import os
import sys

import sim

ADDON = sys.argv[1]
toc = open(os.path.join(ADDON, "SUCDR.toc"), encoding="utf-8").read().splitlines()
exec_src = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ui_smoke.py"), encoding="utf-8").read()
UI_MOCK = exec_src.split('MOCK = r"""', 1)[1].split('"""', 1)[0]
sim.FILES = [x.strip() for x in toc if x.strip().endswith(".lua") and not x.startswith("#")]
sim.COMM = ""  # skutečný Comm.lua

NET = r"""
__tickers, __timers, __wire, __chat = {}, {}, {}, {}
C_Timer = {
  After = function(s, f) __timers[#__timers + 1] = { at = __now + s, f = f } end,
  NewTimer = function(s, f) local t = { at = __now + s, f = f } function t:Cancel() self.dead = true end
    __timers[#__timers + 1] = t return t end,
  NewTicker = function(s, f) __tickers[#__tickers + 1] = f return { Cancel = function() end } end,
}
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  SendAddonMessage = function(prefix, text, channel, target)
    assert(#text <= 255, "addon zpráva delší než 255 bajtů")
    __wire[#__wire + 1] = { text, channel, target or "" } return true end,
  SendChatMessage = function(m, ch, _, target) assert(#m <= 255, "chat delší než 255 bajtů")
    __chat[#__chat + 1] = { m, ch, target } end,
}
__guild = { "Anna", "Bob", "Cyril" }
__roster = 0
C_GuildInfo = { GuildRoster = function() __roster = __roster + 1 end }
function IsInGuild() for _, n in ipairs(__guild) do if n == UnitName("player") then return true end end return false end
function GetGuildInfo() for i, n in ipairs(__guild) do if n == UnitName("player") then return "SUC", "r", i - 1 end end end
function GetNumGuildMembers() return #__guild end
function GetGuildRosterInfo(i) return __guild[i] .. "-Drakthul", "r", i - 1 end
__trade = { 0, 0 }
function GetTargetTradeMoney() return __trade[1] * 10000 end
function GetPlayerTradeMoney() return __trade[2] * 10000 end
ERR_TRADE_COMPLETE = "Trade complete."
local _full = UnitFullName
function UnitFullName(u) if u == "NPC" then return __npc, "Drakthul" end return _full(u) end
function __advance(sec)
  __now = __now + sec; __clock = __clock + sec
  for _, f in ipairs(__tickers) do for _ = 1, math.max(1, math.floor(sec * 4)) do f() end end
  local due, rest = {}, {}
  for _, t in ipairs(__timers) do if not t.dead then if t.at <= __now then due[#due + 1] = t else rest[#rest + 1] = t end end end
  __timers = rest
  for _, t in ipairs(due) do t.f() end
end
"""
sim.STUBS = sim.STUBS + UI_MOCK.split("function IsInGuild")[0] + "Enum = {}\nfunction ReloadUI() end\n" + NET
from sim import World, check, FAILS  # noqa: E402

R = "-Drakthul"


class Net(World):
    def pump(self):
        pass

    def step(self, n=40, sec=1):
        """Posune čas a doručí addon zprávy."""
        for _ in range(n):
            for pl in self.players.values():
                pl.lua.execute(f"__advance({sec})")
            for name, pl in self.players.items():
                wire = list(pl.lua.globals()["__wire"].values())
                pl.lua.execute("__wire = {}")
                for m in wire:
                    text, channel, target = m[1], m[2], m[3]
                    for on, op in self.players.items():
                        if channel == "WHISPER":
                            if target.lower() != op.full.lower():
                                continue
                        elif on == name:
                            continue
                        op.lua.globals()["__fire"]("CHAT_MSG_ADDON", "SUCDR", text, channel, pl.full)

    def roll(self, who, value, low, high):
        for pl in self.players.values():
            pl.lua.globals()["__fire"]("CHAT_MSG_SYSTEM", f"{who} rolls {value} ({low}-{high})")
        self.step(3)


def trade(w, a, b, a_gives):
    for me, other, gave, got in ((a, b, a_gives, 0), (b, a, 0, a_gives)):
        w.p(me).run(f"__npc = '{other}'; __trade = {{ {got}, {gave} }}; __fire('TRADE_SHOW'); "
                    "__fire('TRADE_MONEY_CHANGED'); __fire('UI_INFO_MESSAGE', 0, ERR_TRADE_COMPLETE)")
    w.step(3)


def duel(w, host, loser, bet):
    turn = w.p(host).run("return G.state.players[G.state.turn].name").split("-")[0]
    other = w.p(host).run("return G.state.players[3 - G.state.turn].name").split("-")[0]
    if turn == loser:
        w.roll(turn, 1, 1, bet)
    else:
        w.roll(turn, 50, 1, bet)
        w.roll(other, 1, 1, 50)


# --- samotest addonu ve hře ---------------------------------------------------
w = Net(["Anna", "Bob"])
a = w.p("Anna")
a.out()
a.run("ns.SelfTest.Run()")
w.step(60)
msgs = a.out()
bad = [m for m in msgs if "✗" in m or "selhal" in m.lower() or "chyb" in m.lower()]
ok_text = a.run("return ns.T('self_ok', 0)").split("0")[0].strip()
check(any(ok_text in m for m in msgs) and not bad, "/sucdr selftest projde", (ok_text, msgs[-6:]))
print("   selftest:", msgs[-1])

# --- celá hra přes skutečné zprávy (40 hráčů by dělilo stav na části) -----------
names = ["Anna", "Bob", "Cyril"] + [f"Hrac{i}" for i in range(1, 10)]
w = Net(names)
a = w.p("Anna")
a.run("ns.db.mode = 'diff'; G.Create(1000)")
w.step(5)
for n in names[1:]:
    w.p(n).run("G.Join()")
    w.step(3)
a.run("G.Start()")
w.step(10)
for i, n in enumerate(names):
    w.roll(n, 100 + i, 1, 1000)
w.step(30)
want = f"Anna{R}>Hrac9{R}:11"
got = [p.run("local t = {} for _, d in pairs(ns.db.debts) do t[#t+1] = d.from .. '>' .. d.to .. ':' .. d.amount end "
             "return table.concat(t, ',')") for p in w.players.values()]
check(all(g == want for g in got), "Hra 12 hráčů přes dělené zprávy: stejný dluh u všech", set(got))

# --- 1) odveta: hráč odejde ze skupiny -> lobby nesmí zůstat viset --------------
w = Net(["Anna", "Bob"])
a = w.p("Anna")
a.run("ns.db.mode = 'duel'; G.Create(1000)"); w.step(3)
w.p("Bob").run("G.Join()"); w.step(3)
a.run("G.Start()"); w.step(3)
duel(w, "Anna", "Bob", 1000)
a.run("G.DoubleOrNothing()"); w.step(3)
a.run("G.RemovePlayer('Bob-Drakthul')"); w.step(5)
check(a.run("return G.state == nil"), "Odveta se po odchodu hráče zruší",
      a.run("return G.state and (G.state.phase .. ' ' .. #G.state.players)"))

# --- 2) loterie: dlužník pošle víc, než dluží, a zvolí Dluh -----------------------
w = Net(["Anna", "Bob", "Cyril"])
a = w.p("Anna")
a.run("ns.UI.Confirm = function(_, b) __confirm = b end; ns.Lottery.Create(ns.Lottery.DEFAULTS)"); w.step(3)
a.run(f"L.AddGame({{ id = 'g1', time = time(), host = 'Anna{R}', bet = 3000, mode = 'duel', winner = 'Anna{R}', "
      f"players = {{ 'Anna{R}', 'Bob{R}' }} }}, true)")
trade(w, "Bob", "Anna", 25000)
a.run("__confirm[2][2]()"); w.step(3)
res = a.run("local l = ns.db.lottery; return tostring(ns.db.debts['g1:Bob-Drakthul'].paid) .. '/' .. l.count "
            ".. '/' .. tostring(l.back['Bob-Drakthul'])")
check(res == "true/2/2000", "Dluh 3000 z 25000: zbytek jde na 2 losy a 2000 k vrácení", res)

# --- 3) stav loterie projde po přihlášení (seznam guildy se vyžádá) --------------
b = w.p("Bob")
b.run("ns.db.lotterySeen = nil; __roster = 0; __fire('PLAYER_LOGIN')")
w.step(60)
check(b.run("return __roster > 0"), "Po přihlášení se vyžádá seznam guildy")
check(b.run("return ns.db.lotterySeen and ns.db.lotterySeen.mine") == "1-2", "Po přihlášení vidím svoje losy")

# --- 4) tooltip po potvrzení neověřené hry sběrem GM ------------------------------
a.run(f"L.AddGame({{ id = 'u1', time = time(), host = 'Cyril{R}', bet = 10, mode = 'duel', winner = 'Cyril{R}', "
      f"players = {{ 'Cyril{R}', 'Bob{R}' }} }}, false)")
before = a.run("return ns.Tooltip.Lines('Cyril-Drakthul')")
a.run("ns.Sync.RequestCollect(true)")
a.run(f"__deliver_rec = L.SerializeGame(ns.db.games.u1)")
rec = a.run("return __deliver_rec")
w.p("Cyril").run(f"ns.Send('GAMEREC', '{rec}', 'WHISPER', 'Anna{R}')"); w.step(10)
after = a.run("return ns.Tooltip.Lines('Cyril-Drakthul')")
check(before is None and after is not None, "Tooltip se po sběru her obnoví", (before, after))

# --- 5) výzva se jménem napsaným malými písmeny -----------------------------------
w = Net(["Anna", "Bob"])
a, b = w.p("Anna"), w.p("Bob")
a.run("SlashCmdList.SUCDR('vyzva bob')"); w.step(3)
b.run("ns.Challenge.Answer(true)"); w.step(5)
check(a.run("return G.state and G.state.phase") == "running", "/sucdr vyzva bob (malými) spustí duel")

# --- 6) odmítnutá výzva nejde hned poslat znovu ------------------------------------
w = Net(["Anna", "Bob"])
a, b = w.p("Anna"), w.p("Bob")
a.run("ns.Challenge.Send('Bob')"); w.step(3)
b.run("ns.Challenge.Answer(false)"); w.step(3)
b.out()
a.run("ns.Challenge.Send('Bob')"); w.step(3)
check(not any("vyzývá" in m for m in b.out()), "Po odmítnutí hned další výzva nevyskočí")
w.step(65)
a.run("ns.Challenge.Send('Bob')"); w.step(3)
check(any("vyzývá" in m for m in b.out()), "Po minutě jde vyzvat znovu")

# --- poškozené zprávy od jiných hráčů nesmí vyvolat chybu ---------------------------
import random
random.seed(7)
w = Net(["Anna", "Bob"])
a = w.p("Anna")
a.run("ns.db.mode = 'duel'; G.Create(100); ns.Lottery.Create(ns.Lottery.DEFAULTS)"); w.step(3)
types = ["STATE", "JOIN", "LEAVE", "CANCEL", "RESET", "GAME", "PAID", "HELLO", "SYNCALL", "DEBT", "VER", "OPEN", "COLLECT",
         "GAMEREC", "LOGREQ", "LOG", "CHAL", "CHALOK", "CHALNO", "LOT", "LOTT", "LOTQ", "SELFTEST", "NEZNAMA"]
bits = ["", ";", "/", ",", ":", "-1", "0", "1", "abc", "Bob-Drakthul", "Anna-Drakthul", "lobby", "running", "done",
        "open", "drawn", "1e309", "nan", "%s", "|c", "x" * 400, "\n", "ř"]
errors = []
for i in range(6000):
    t_ = random.choice(types)
    payload = "".join(random.choice(bits) + random.choice([";", "", "/", ","]) for _ in range(random.randint(0, 18)))
    pl = w.p(random.choice(["Anna", "Bob"]))
    other = "Bob-Drakthul" if pl.name == "Anna" else "Anna-Drakthul"
    frame = f"{i % 900 + 1}:1:1:{t_};{payload}"[:250]
    try:
        pl.lua.globals()["__fire"]("CHAT_MSG_ADDON", "SUCDR", frame, random.choice(["WHISPER", "PARTY", "GUILD"]), other)
        if i % 500 == 0:
            pl.lua.execute("__advance(40)")
            pl.run("ns.Ledger.Stats(); ns.Export.ToJSON(ns.Export.Build()); ns.UI.ShowTab('history'); "
                   "ns.UI.ShowTab('debts'); ns.UI.ShowTab('stats'); ns.UI.ShowTab('lottery'); ns.UI.ShowTab('game')")
    except Exception as e:
        errors.append((t_, payload[:80], str(e)[:200]))
check(not errors, "6000 náhodných zpráv bez chyby", (len(errors), errors[:4]))

print()
print("CHYBY celek:", FAILS or "žádné")

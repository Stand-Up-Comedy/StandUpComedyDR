"""Scénáře loterie a kouřový test okna. Spuštění: python tests/lottery.py SUCDR"""
import sys

import sim

sim.FILES = ["Core.lua", "Locale.lua", "Ledger.lua", "Sync.lua", "Game.lua", "Challenge.lua", "Lottery.lua",
             "Tooltip.lua"]
from sim import World, check, FAILS  # noqa: E402

R = "-Drakthul"
GUILD = r"""
__guild = { "Anna", "Bob", "Cyril" }  -- Anna je guild master, Host v guildě není
function IsInGuild() for _, n in ipairs(__guild) do if n == UnitName("player") then return true end end return false end
function GetGuildInfo() for i, n in ipairs(__guild) do if n == UnitName("player") then return "SUC", "r", i - 1 end end end
function GetNumGuildMembers() return #__guild end
function GetGuildRosterInfo(i) return __guild[i] .. "-Drakthul", "r", i - 1 end
C_GuildInfo = { GuildRoster = function() end }
__chat = {}
C_ChatInfo = { SendChatMessage = function(m, ch, _, target) __chat[#__chat + 1] = { m, ch, target } end }
__trade = { 0, 0 }
function GetTargetTradeMoney() return __trade[1] * 10000 end
function GetPlayerTradeMoney() return __trade[2] * 10000 end
ERR_TRADE_COMPLETE = "Trade complete."
__npc = nil
local _full = UnitFullName
function UnitFullName(u) if u == "NPC" then return __npc, "Drakthul" end return _full(u) end
__confirm = nil
"""
sim.STUBS = sim.STUBS + GUILD
NAMES = ["Anna", "Bob", "Cyril", "Host"]


def world():
    w = World(NAMES)
    for p in w.players.values():
        p.run("ns.UI = { Confirm = function(text, buttons) __confirm = buttons end }")
    return w


def trade(w, a, b, a_gives=0, b_gives=0):
    """Hráči a a b dokončí trade."""
    for me, other, gave, got in ((a, b, a_gives, b_gives), (b, a, b_gives, a_gives)):
        w.p(me).run(f"__npc = '{other}'; __trade = {{ {got}, {gave} }}; __fire('TRADE_SHOW'); "
                    "__fire('TRADE_MONEY_CHANGED'); __fire('UI_INFO_MESSAGE', 0, ERR_TRADE_COMPLETE)")
    w.pump()


OPTS = "{ price = 10000, limit = 20, step = 500000, bonus = 25000, bonusMax = 100000, share = 10, guests = %s }"


def create(w, guests="true"):
    ok = w.p("Anna").run(f"return ns.Lottery.Create({OPTS % guests})")
    w.pump()
    return ok


def lot(w, expr):
    return w.p("Anna").run(f"local l = ns.db.lottery; return {expr}")


def money(w):
    return w.p("Anna").run("return ns.Lottery.Money(ns.db.lottery)")


# --- vyhlášení a oprávnění ---------------------------------------------------
w = world()
check(not w.p("Bob").run(f"return ns.Lottery.Create({OPTS % 'true'})"), "Vyhlásit smí jen guild master")
check(w.p("Anna").run("local o = " + OPTS % "true" + "; o.bonus = 60000; return ns.Lottery.Validate(o)") == "lot_bad_bonus",
      "Bonus vyšší než podíl banky se odmítne")
check(create(w), "GM vyhlásí loterii")
check(not create(w), "Druhou loterii nejde vyhlásit, dokud běží první")
check(w.p("Bob").run("return ns.db.lotterySeen.status") == "open", "Člen guildy vidí otevřenou loterii")
check(w.p("Host").run("return ns.db.lotterySeen") is None, "Host zatím nic neví")

# --- prodej ------------------------------------------------------------------
trade(w, "Bob", "Anna", a_gives=50000)
check(lot(w, "l.count") == 5, "50k = 5 losů", lot(w, "l.count"))
check(w.p("Bob").run("return ns.db.lotterySeen.mine") == "1-5", "Bob vidí svoje losy 1-5")
check(w.p("Bob").run("return ns.db.lotterySeen.prize") == 45000, "Bob vidí výhru 45000")
trade(w, "Host", "Anna", a_gives=35000)
check(lot(w, "l.count") == 8 and lot(w, f"l.back['Host{R}']") == 5000, "Host: 35k = 3 losy a 5000 k vrácení")
check(w.p("Host").run("return ns.db.lotterySeen and ns.db.lotterySeen.mine") == "6-8", "Host mimo guildu vidí losy 6-8")
trade(w, "Anna", "Host", a_gives=5000)
check(lot(w, f"l.back['Host{R}']") is None, "Vrácení přeplatku tradem se odepíše")
trade(w, "Bob", "Anna", a_gives=200000)
check(lot(w, "l.count") == 23 and lot(w, f"l.back['Bob{R}']") == 50000, "Limit 20: Bob dostane 15, 50k k vrácení",
      (lot(w, "l.count"), lot(w, f"l.back['Bob{R}']")))
trade(w, "Anna", "Bob", a_gives=50000)
trade(w, "Cyril", "Anna", a_gives=5000)
check(lot(w, "l.count") == 23 and lot(w, f"l.back['Cyril{R}']") is None, "Méně než cena losu se nezapíše")
check(not any("%" in m for m in w.p("Bob").out()), "Hráči nevidí procenta")

# --- dluh vs. losy --------------------------------------------------------------
w.p("Anna").run(f"L.AddGame({{ id = 'g1', time = time(), host = 'Anna{R}', bet = 30000, mode = 'duel', "
                f"winner = 'Anna{R}', players = {{ 'Anna{R}', 'Cyril{R}' }} }}, true)")
trade(w, "Cyril", "Anna", a_gives=30000)
check(lot(w, "#l.pending") == 1 and lot(w, "l.count") == 23, "Dlužník: platba čeká na rozhodnutí")
check(w.p("Anna").run("return ns.db.debts['g1:Cyril-Drakthul'].paid") is False, "Dluh se mezitím neodepsal")
check(not w.p("Anna").run("return ns.Lottery.Close()"), "S nerozhodnutou platbou nejde uzavřít")
w.p("Anna").run("__confirm[2][2]()")  # splacení dluhu
check(w.p("Anna").run("return ns.db.debts['g1:Cyril-Drakthul'].paid") is True and lot(w, "l.count") == 23,
      "Volba Dluh: dluh zaplacen, žádné losy")
trade(w, "Cyril", "Anna", a_gives=20000)
check(lot(w, "l.count") == 25, "Bez dluhu: 20k = 2 losy")

# --- uzavření a losování -----------------------------------------------------
w.p("Anna").run("RandomRoll = function(a, b) __rolls[#__rolls + 1] = { a, b } end")
w.roll("Anna", 7, 1, 25)
check(lot(w, "l.status") == "open", "Hod před uzavřením nic neudělá")
check(w.p("Anna").run("return ns.Lottery.Close()"), "Uzavření prodeje")
chat = w.p("Anna").run("local t = {} for _, c in ipairs(__chat) do t[#t+1] = c[2] .. ' ' .. c[1] end return table.concat(t, '\\n')")
check("GUILD [SUCDR] Losy 1-25" in chat, "Seznam losů zveřejněn v guildě", chat[-300:])
trade(w, "Bob", "Anna", a_gives=10000)
check(lot(w, "l.count") == 25, "Po uzavření se losy neprodávají")
w.roll("Anna", 7, 1, 25)
check(lot(w, "l.status") == "closed", "Ruční hod bez tlačítka Losovat se nepočítá")
w.p("Anna").run("ns.Lottery.Draw()")
check(w.p("Anna").run("return __rolls[#__rolls][2]") == 25, "Losovat hodí /roll 1-25")
w.roll("Bob", 7, 1, 25)
check(lot(w, "l.status") == "closed", "Cizí hod nevylosuje")
w.roll("Anna", 7, 1, 100)
check(lot(w, "l.status") == "closed", "Jiný rozsah nevylosuje")
w.roll("Anna", 7, 1, 25)
check(lot(w, "l.winner") == "Host" + R and lot(w, "l.number") == 7, "Los 7 patří Hostovi")
w.roll("Anna", 1, 1, 25)
check(lot(w, "l.winner") == "Host" + R, "Druhý hod výherce nezmění")
check(w.p("Host").run("return ns.db.lotterySeen.winner") == "Host" + R, "Host vidí, že vyhrál")
sales, bonus, prize, bank, _ = money(w)
check((sales, bonus, prize, bank) == (250000, 0, 225000, 25000), "Peníze: 250k -> výhra 225k, banka 25k",
      (sales, bonus, prize, bank))
trade(w, "Anna", "Host", a_gives=100000)
check(w.p("Anna").run("return ns.Lottery.PrizeLeft()") == 125000, "Částečná výplata výhry")
check(not create(w), "Nová loterie nejde před vyplacením")
trade(w, "Anna", "Host", a_gives=125000)
check(w.p("Anna").run("return ns.Lottery.PrizeLeft()") == 0, "Výhra vyplacena")
back = lot(w, f"l.back['Bob{R}']")
check(back is None, "Platba po uzavření se nezapsala jako vratka (jen upozornění)", back)
check(create(w, "false"), "Po vyřízení jde vyhlásit další loterii")
check(w.p("Anna").run("return #ns.db.lotteryHistory") == 1, "Stará loterie je v historii")

# --- hosté zakázáni, zrušení --------------------------------------------------
trade(w, "Host", "Anna", a_gives=20000)
check(lot(w, "l.count") == 0 and lot(w, f"l.back['Host{R}']") == 20000, "Bez hostů: platba hosta k vrácení")
trade(w, "Bob", "Anna", a_gives=30000)
check(not w.p("Anna").run("return ns.Lottery.Close()"), "S jedním hráčem nejde losovat")
w.p("Anna").run("ns.Lottery.Cancel()")
w.pump()
check(lot(w, "l.status") == "cancelled" and lot(w, f"l.back['Bob{R}']") == 30000, "Zrušení: Bobovi vrátit 30k")
w.p("Anna").run(f"ns.Lottery.MarkReturned('Bob{R}'); ns.Lottery.MarkReturned('Host{R}')")
check(not w.p("Anna").run("return ns.Lottery.Busy()"), "Po vrácení všeho je loterie vyřízená")

# --- bonusy: banka nikdy neprodělá ---------------------------------------------
bad = w.p("Anna").run("""
    local l = { price = 10000, step = 500000, bonus = 25000, bonusMax = 100000, share = 10 }
    local bad = {}
    for n = 0, 600 do
        l.count = n
        local sales, bonus, prize, bank = ns.Lottery.Money(l)
        if bank < 0 or prize + bank ~= sales then bad[#bad + 1] = n end
    end
    l.count = 200
    local _, b, p, k = ns.Lottery.Money(l)
    return #bad .. '/' .. b .. '/' .. p .. '/' .. k
""")
check(bad == "0/100000/1900000/100000", "Banka nikdy v minusu; 2m -> výhra 1,9m, banka 100k", bad)

# --- podvržený stav od cizího hráče ----------------------------------------------
w = world()
w.p("Bob").run("__deliver('LOT', 'Cyril-Drakthul', 'X;open;999;1;1;1;;')")
check(w.p("Bob").run("return ns.db.lotterySeen") is None, "Stav loterie od ne-GM se ignoruje")

# --- jen guild master -----------------------------------------------------------
w = world()
create(w)
b = w.p("Bob")
trade(w, "Bob", "Anna", a_gives=10000)
trade(w, "Cyril", "Anna", a_gives=10000)
# Anna přestane být guild master uprostřed loterie
for p in w.players.values():
    p.run('__guild = { "Bob", "Anna", "Cyril" }')
check(not w.p("Anna").run("return ns.Lottery.Close()"), "Bývalý GM neuzavře prodej")
w.p("Anna").run("ns.Lottery.Cancel()")
check(lot(w, "l.status") == "open", "Bývalý GM loterii nezruší")
w.p("Anna").run("__chat = {}; ns.Lottery.PublishList()")
check(w.p("Anna").run("return #__chat") == 0, "Bývalý GM nezveřejní seznam")
trade(w, "Cyril", "Anna", a_gives=10000)
check(lot(w, "l.count") == 2, "Bývalý GM neprodá další losy")
w = world()
w.p("Bob").run("ns.Lottery.paidTo['Cyril-Drakthul'] = GetTime(); "
               "__deliver('LOT', 'Cyril-Drakthul', 'X;open;999;1;1;1;;')")
check(w.p("Bob").run("return ns.db.lotterySeen") is None, "Člen guildy, kterému jsem platil, loterii nepodstrčí")

print()
print("CHYBY loterie:", FAILS or "žádné")

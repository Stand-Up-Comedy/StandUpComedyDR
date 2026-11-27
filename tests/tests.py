import sys
sys.argv = [sys.argv[0], sys.argv[1]]
from sim import World, check, debts, state, FAILS

R = "-Drakthul"


def setup(names, mode, bet):
    w = World(names)
    host = w.p(names[0])
    host.run(f"ns.db.mode = '{mode}'; G.Create({bet})")
    w.pump()
    for n in names[1:]:
        w.p(n).run("G.Join()")
        w.pump()
    host.run("G.Start()")
    w.pump()
    return w, host


def chat(pl):
    return [m for m in pl.out() if m.startswith("CHAT")]


# --- Rozdíl: 3 hráči, jasný výsledek ---------------------------------------
w, a = setup(["Anna", "Bob", "Cyril"], "diff", 1000)
check(state(a, "mode") == "diff", "Rozdíl: režim diff po startu")
check(state(w.p("Bob"), "mode") == "diff", "Rozdíl: klient má režim diff")
check(w.p("Bob").run("return G.MyRollMax()") == 1000, "Rozdíl: klient hází 1-1000")
a.out()
w.roll("Anna", 700, 1, 1000)
w.roll("Bob", 200, 1, 1000)
check(state(a, "phase") == "running", "Rozdíl: čeká na posledního hráče")
w.roll("Cyril", 950, 1, 1000)
check(state(a, "phase") == "done", "Rozdíl: hra skončila")
check(state(a, "winner") == "Cyril" + R and state(a, "loser") == "Bob" + R, "Rozdíl: Cyril vítěz, Bob platí")
check(state(a, "bet") == 750, "Rozdíl: sázka = rozdíl 750", state(a, "bet"))
msgs = chat(a)
print("   chat:", msgs[-1] if msgs else None)
for n in ["Anna", "Bob", "Cyril"]:
    d = debts(w.p(n))
    check(d == "Bob" + R + ">Cyril" + R + ":750:O", f"Rozdíl: dluh u {n} = Bob dluží Cyrilovi 750 (ověřeno)", d)
stats = a.run("local s = L.Stats(); return s['Cyril-Drakthul'].net .. '/' .. s['Bob-Drakthul'].net .. '/' .. s['Anna-Drakthul'].net")
check(stats == "750/-750/0", "Rozdíl: statistiky +750 / -750 / 0", stats)
check(w.p("Bob").run("return G.DonOffer()") is None, "Rozdíl: double or nothing se nenabízí (není duel)")

# --- Rozdíl: neplatný rozsah ------------------------------------------------
w, a = setup(["Anna", "Bob"], "diff", 1000)
w.roll("Bob", 50, 1, 100)
check(a.run("return G.FindPlayer('Bob-Drakthul').rolled") is False, "Rozdíl: hod 1-100 místo 1-1000 se nepočítá")

# --- Rozdíl: shoda na nejnižším -> hází se znovu ---------------------------
w, a = setup(["Anna", "Bob", "Cyril"], "diff", 1000)
w.roll("Anna", 300, 1, 1000)
w.roll("Bob", 300, 1, 1000)
w.roll("Cyril", 900, 1, 1000)
check(state(a, "phase") == "running" and state(a, "round") == 2, "Rozdíl: shoda dole -> nové kolo")
check(w.p("Anna").run("return G.MyRollMax()") == 1000, "Rozdíl: v novém kole zase 1-1000")
w.roll("Anna", 10, 1, 1000)
w.roll("Bob", 20, 1, 1000)
w.roll("Cyril", 30, 1, 1000)
check(state(a, "winner") == "Cyril" + R and state(a, "loser") == "Anna" + R and state(a, "bet") == 20,
      "Rozdíl: po rozstřelu Anna platí Cyrilovi 20")

# --- Rozdíl: remíza ---------------------------------------------------------
w, a = setup(["Anna", "Bob"], "diff", 500)
w.roll("Anna", 77, 1, 500)
w.roll("Bob", 77, 1, 500)
check(state(a, "phase") == "done" and state(a, "winner") is None, "Rozdíl: remíza bez vítěze")
check(debts(a) == "" and debts(w.p("Bob")) == "", "Rozdíl: remíza nevytvoří dluh")
check(a.run("return next(ns.db.games) == nil"), "Rozdíl: remíza se neukládá do historie")

# --- Rozdíl: kdo nehodí včas, má 1 ------------------------------------------
w, a = setup(["Anna", "Bob", "Cyril"], "diff", 1000)
w.roll("Anna", 400, 1, 1000)
w.roll("Bob", 600, 1, 1000)
a.run("G.ResolveRound()")  # vypršel limit
w.pump()
check(state(a, "loser") == "Cyril" + R and state(a, "winner") == "Bob" + R and state(a, "bet") == 599,
      "Rozdíl: Cyril nehodil, počítá se 1, platí Bobovi 599", (state(a, "loser"), state(a, "bet")))

# --- Double or nothing: poražený vyhraje odvetu -> kvit ---------------------
w, a = setup(["Anna", "Bob"], "duel", 1000)
first = a.run("return G.state.players[1].name")
second = a.run("return G.state.players[2].name")
w.roll(first.split("-")[0], 500, 1, 1000)
w.roll(second.split("-")[0], 1, 1, 500)  # druhý hodil 1 -> prohrál
loser, winner = second, first
check(state(a, "winner") == winner, "DON: první duel má vítěze")
check(a.run("return G.DonOffer()") is not None, "DON: hostiteli se nabízí odveta")
check(w.p("Bob").run("return G.DonOffer()") is None, "DON: klientovi (ne hostiteli) se nenabízí")
a.out()
a.run("G.DoubleOrNothing()")
w.pump()
check(state(a, "phase") == "lobby" and state(a, "don") is not None and state(a, "bet") == 1000,
      "DON: lobby odvety o 1000")
check(state(w.p("Bob"), "don") == state(a, "don"), "DON: klient ví, že jde o odvetu")
check(a.run("return #G.state.players") == 2, "DON: oba hráči jsou rovnou v lobby")
a.run("G.SetMode('mass')")
check(state(a, "choice") == "duel", "DON: režim odvety nejde změnit")
a.run("G.Start()")
w.pump()
on_turn = a.run("return G.state.players[G.state.turn].name").split("-")[0]
other = [n for n in ["Anna", "Bob"] if n != on_turn][0]
# poražený (loser) musí vyhrát: hráč na tahu, který není loser, hodí 1, nebo loser hodí a druhý 1
if on_turn + R == winner:
    w.roll(on_turn, 1, 1, 1000)
else:
    w.roll(on_turn, 300, 1, 1000)
    w.roll(other, 1, 1, 300)
check(state(a, "winner") == loser, "DON: odvetu vyhrál původní poražený")
print("   chat:", chat(a)[-1:])
for n in ["Anna", "Bob"]:
    d = debts(w.p(n))
    check(":O" not in d and d.count(":P") == 2, f"DON: u {n} jsou oba dluhy vyrovnané", d)
check(a.run("return G.DonOffer()") is None, "DON: po vyrovnání se další odveta nenabízí")
stats = a.run("local s = L.Stats(); return s['Anna-Drakthul'].net .. '/' .. s['Bob-Drakthul'].net")
check(stats == "0/0", "DON: statistiky po vyrovnání 0 / 0", stats)

# --- Double or nothing: poražený prohraje znovu -> 2x, další odveta o 2000 ---
w, a = setup(["Anna", "Bob"], "duel", 1000)


def finish_duel(w, a, loser_short, start):
    on_turn = a.run("return G.state.players[G.state.turn].name").split("-")[0]
    other = [n for n in ["Anna", "Bob"] if n != on_turn][0]
    if on_turn == loser_short:
        w.roll(on_turn, 1, 1, start)
    else:
        w.roll(on_turn, 300, 1, start)
        w.roll(other, 1, 1, 300)


finish_duel(w, a, "Bob", 1000)
check(state(a, "winner") == "Anna" + R, "DON2: Bob prohrál první duel")
a.run("G.DoubleOrNothing()"); w.pump(); a.run("G.Start()"); w.pump()
finish_duel(w, a, "Bob", 1000)
check(state(a, "winner") == "Anna" + R, "DON2: Bob prohrál i odvetu")
print("   chat:", chat(a)[-1:])
d = debts(w.p("Bob"))
check(d == "Bob-Drakthul>Anna-Drakthul:1000:O,Bob-Drakthul>Anna-Drakthul:1000:O", "DON2: Bob dluží 2x 1000", d)
off = a.run("return G.DonOffer()")
check(off == (2000, "Bob" + R, "Anna" + R, off[3] if off else None), "DON2: další odveta o 2000", off)
a.run("G.DoubleOrNothing()"); w.pump(); a.run("G.Start()"); w.pump()
check(state(a, "bet") == 2000 and state(a, "start") == 2000, "DON2: třetí hra o 2000, hod 1-2000")
finish_duel(w, a, "Anna", 2000)
check(state(a, "winner") == "Bob" + R, "DON2: Bob vyhrál třetí hru")
for n in ["Anna", "Bob"]:
    d = debts(w.p(n))
    check(":O" not in d and d.count(":P") == 3, f"DON2: u {n} všechny 3 dluhy vyrovnané", d)

# --- DON: zaplacený dluh -> odveta se nenabízí ------------------------------
w, a = setup(["Anna", "Bob"], "duel", 1000)
finish_duel(w, a, "Bob", 1000)
a.run("for id, d in pairs(ns.db.debts) do L.SetPaid(id, true) end")
check(a.run("return G.DonOffer()") is None, "DON: po zaplacení se odveta nenabízí")

# --- DON: podvržená odveta s jinou sázkou nic nevyrovná ---------------------
w, a = setup(["Anna", "Bob"], "duel", 1000)
finish_duel(w, a, "Bob", 1000)
prev = state(a, "id")
fake = f"FAKE1;1732190001;Anna{R};500;duel;Bob{R};Anna{R}/Bob{R};;{prev}"
w.p("Bob").run(f"L.AddGame(L.ParseGame('{fake}'), true)")
d = debts(w.p("Bob"))
check("Bob-Drakthul>Anna-Drakthul:1000:O" in d, "DON: odveta o jinou částku dluh nevyrovná", d)

# --- starší klient: záznam hry rozdílu (9 polí) se načte -------------------
check(w.p("Bob").run("return L.ParseGame('X;1;A-R;10;diff;B-R;A-R/B-R;A-R').loser") == "A-R",
      "Záznam hry v původním formátu (8 polí) se stále načte")

print()
print("CHYBY:", FAILS if FAILS else "žádné")

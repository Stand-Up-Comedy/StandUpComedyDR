"""Kouřový test okna: načte všechny soubory z TOC s atrapou rámečků, otevře každou záložku
a proklikne stavy loterie. Odhalí chybějící funkce a překlepy, ne vzhled.
Spuštění: python tests/ui_smoke.py SUCDR"""
import os
import sys

import sim

ADDON = sys.argv[1]
toc = open(os.path.join(ADDON, "SUCDR.toc"), encoding="utf-8").read().splitlines()
sim.FILES = [line.strip() for line in toc if line.strip().endswith(".lua") and not line.startswith("#")]

MOCK = r"""
-- atrapa rámečku: jakákoli metoda existuje a vrací další atrapu, rozměry vrací čísla
local NUM = { GetWidth = 100, GetHeight = 100, GetStringWidth = 50, GetStringHeight = 12, GetVerticalScroll = 0,
  GetVerticalScrollRange = 0, NumLines = 0, GetID = 1, GetFrameLevel = 1, GetEffectiveScale = 1 }
local function mock()
  local o = { scripts = {}, text = nil }
  local data = {}
  return setmetatable(o, { __index = function(self, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if NUM[k] then return function() return NUM[k] end end
    if k == "SetText" then return function(s, t) data.text = t end end
    if k == "GetText" then return function() return data.text or "" end end
    if k == "SetChecked" then return function(s, v) data.checked = v end end
    if k == "GetChecked" then return function() return data.checked end end
    if k == "SetScript" or k == "HookScript" then return function(s, n, fn) s.scripts[n] = fn end end
    if k == "IsShown" then return function() return data.shown ~= false end end
    if k == "Show" then return function() data.shown = true end end
    if k == "Hide" then return function() data.shown = false end end
    if k == "SetShown" then return function(s, v) data.shown = v and true or false end end
    if k == "IsEnabled" then return function() return true end end
    if k == "IsMouseOver" or k == "IsPlaying" then return function() return false end end
    if k == "GetFont" then return function() return "font", 12, "" end end
    if k == "GetCenter" then return function() return 0, 0 end end
    return function() return mock() end
  end })
end
local _create = CreateFrame
function CreateFrame(...)
  local real = _create(...)
  local m = mock()
  m.scripts = real.scripts
  rawset(m, "RegisterEvent", function() end)
  rawset(m, "SetScript", function(s, n, fn) real.scripts[n] = fn end)
  return m
end
CreateFont = function() return mock() end
UIParent, Minimap, GameTooltip, ChatFontNormal = mock(), mock(), mock(), mock()
GameFontNormal, GameFontHighlight, GameFontHighlightSmall, GameFontDisable = mock(), mock(), mock(), mock()
UISpecialFrames, SlashCmdList, StaticPopupDialogs = {}, {}, {}
tinsert = table.insert
RAID_CLASS_COLORS = {}
function UnitClass() return "x", "MAGE" end
function GetCursorPosition() return 0, 0 end
function IsInGuild() return true end
__rank = 0
function GetGuildInfo() return "SUC", "r", __rank end
function GetNumGuildMembers() return 2 end
function GetGuildRosterInfo(i) return (i == 1 and "Anna" or "Bob") .. "-Drakthul", "r", i - 1 end
C_GuildInfo = { GuildRoster = function() end }
Enum = {}
function ReloadUI() end
"""
sim.STUBS = sim.STUBS + MOCK
# Comm.lua nahrazuje simulace
sim.FILES = [f for f in sim.FILES if f != "Comm.lua"]
from sim import World, check, FAILS  # noqa: E402

w = World(["Anna", "Bob"])
a = w.p("Anna")


def ui(code, label):
    try:
        a.run(code)
        check(True, label)
    except Exception as e:  # chyba Lua
        check(False, label, str(e)[:300])


for tab in ["game", "debts", "history", "lottery", "stats", "settings"]:
    ui(f"ns.UI.ShowTab('{tab}')", f"Záložka {tab}")
ui("ns.Lottery.Create(ns.Lottery.DEFAULTS)", "Loterie: vyhlášení s oknem")
ui("ns.UI.ShowTab('lottery'); ns.Lottery.Sell('Bob-Drakthul', 25000); ns.Lottery.Sell('Anna-Drakthul', 10000)",
   "Loterie: prodej s oknem")
ui("ns.Lottery.Close(); ns.UI.ShowLog('x', ns.Lottery.Report())", "Loterie: uzavření a záloha")
ui("ns.Lottery.Cancel(); ns.RefreshUI()", "Loterie: zrušení")
ui("__rank = 3; ns.db.lotterySeen = { id = 'a', host = 'Bob-Drakthul', status = 'drawn', prize = 1, price = 1, "
   "limit = 1, winner = 'Bob-Drakthul', number = 1, mine = '1-3,5' }; ns.RefreshUI()", "Loterie: pohled hráče")
ui("ns.db.lotterySeen = nil; ns.UI.ShowTab('lottery'); ns.RefreshUI()", "Skrytá záložka u hráče")
ui("SlashCmdList.SUCDR('loterie'); SlashCmdList.SUCDR('help')", "Příkazy")

print()
print("CHYBY okna:", FAILS or "žádné")

# SUCDR – export pro Discord bota

Addon SUCDR (Stand Up Comedy DR) zapisuje přehled her a dluhů jako **JSON**. Je určený pro externí programy, například bota Comedy Tools.

## Kde soubor je

```
World of Warcraft\_retail_\WTF\Account\<ÚČET>\SavedVariables\SUCDR.lua
```

- `<ÚČET>` je název složky účtu, ne jméno postavy.
- Soubor zapisuje hra, ne addon. Stane se to při odhlášení, ukončení hry nebo `/reload`.
- Ručně jde export vyvolat tlačítkem **Exportovat pro Discord** v Nastavení addonu nebo `/sucdr export`. Po potvrzení se udělá `/reload`.
- Export se pokaždé přepíše celý a obsahuje kompletní aktuální stav, ne jen změny.
- Ve stejném souboru je i `SUCDR_DB`, což jsou vnitřní data addonu. Ta nečti, jejich struktura se může měnit.

## Jak JSON načíst

Addon nemůže vytvořit vlastní soubor. Hra umí ukládat jen Lua hodnoty, proto je JSON uložený jako jeden Lua řetězec:

```lua
SUCDR_Export = "{\"balances\":[{\"amount\":5000,\"confirmed\":5000,\"from\":\"Řehoř-Drakthul\",...}],...}"
```

Stačí najít řádek `SUCDR_Export = "..."`, zrušit Lua escapování (`\"` → `"`, `\\` → `\`) a výsledek je čistý JSON v UTF-8.

**Python:**

```python
import json, re

def load_sucdr(path):
    with open(path, encoding="utf-8") as f:
        text = f.read()
    m = re.search(r'^SUCDR_Export = "((?:[^"\\]|\\.)*)"', text, re.M | re.S)
    if not m:
        return None  # export ještě neproběhl
    esc = {"n": "\n", "r": "\r", "t": "\t", "\n": "\n"}
    raw = re.sub(r'\\(\d{1,3}|.)',
                 lambda e: chr(int(e.group(1))) if e.group(1).isdigit() else esc.get(e.group(1), e.group(1)),
                 m.group(1), flags=re.S)
    return json.loads(raw)
```

**Node.js:**

```js
const fs = require("fs");

function loadSucdr(path) {
  const text = fs.readFileSync(path, "utf8");
  const m = text.match(/^SUCDR_Export = "((?:[^"\\]|\\[\s\S])*)"/m);
  if (!m) return null; // export ještě neproběhl
  const esc = { n: "\n", r: "\r", t: "\t", "\n": "\n" };
  const raw = m[1].replace(/\\(\d{1,3}|[\s\S])/g,
    (_, c) => /^\d/.test(c) ? String.fromCharCode(+c) : (esc[c] ?? c));
  return JSON.parse(raw);
}
```

Kontrola: pole `format` musí být `2`. Verze 0.9.0–0.9.1 ukládaly Lua tabulku (`format` 1), a tu výše uvedený kód nenajde. Verze 0.9.2 poškozovala některá česká písmena (např. `Ř`), používej 0.9.3 a novější.

Python funkce je ověřená na souboru ve formátu, jaký zapisuje WoW. Node.js verze dělá totéž, ale spuštěná nebyla.

## Ukázka (naformátovaná)

```json
{
  "format": 2,
  "addonVersion": "0.9.2",
  "exporter": "Žofie-Drakthul",
  "exportedAt": 1763820000,
  "games": [
    {
      "id": "Žofie1763819000123",
      "time": 1763819000,
      "host": "Žofie-Drakthul",
      "bet": 5000,
      "mode": "mass",
      "players": ["Žofie-Drakthul", "Řehoř-Drakthul", "Karel-Drakthul"],
      "winner": "Žofie-Drakthul",
      "payout": 10000,
      "verified": true
    }
  ],
  "debts": [
    {
      "id": "Žofie1763819000123:Řehoř-Drakthul",
      "game": "Žofie1763819000123",
      "from": "Řehoř-Drakthul",
      "to": "Žofie-Drakthul",
      "amount": 5000,
      "remaining": 5000,
      "paid": false,
      "time": 1763819000,
      "confirmed": true
    },
    {
      "id": "Žofie1763819000123:Karel-Drakthul",
      "game": "Žofie1763819000123",
      "from": "Karel-Drakthul",
      "to": "Žofie-Drakthul",
      "amount": 5000,
      "remaining": 0,
      "paid": true,
      "paidAt": 1763819500,
      "time": 1763819000,
      "confirmed": true
    }
  ],
  "balances": [
    {
      "from": "Řehoř-Drakthul",
      "to": "Žofie-Drakthul",
      "amount": 5000,
      "confirmed": 5000,
      "since": 1763819000
    }
  ]
}
```

Ve skutečném exportu jsou klíče seřazené abecedně a JSON je na jednom řádku bez odsazení.

## Pole

Všechny částky jsou v celých goldech. Všechny časy jsou Unix timestamp v sekundách (UTC). Jména jsou vždy `Jmeno-Realm`. Pole, která nemají hodnotu, v JSONu chybí: `loser` u jiných režimů než `ring`, `paidAt` u nezaplacených dluhů. Prázdný seznam je `[]`.

### Kořen

| pole | typ | význam |
|---|---|---|
| `format` | číslo | verze formátu. Teď `2`; při nekompatibilní změně se zvýší. |
| `addonVersion` | text | verze addonu, který export zapsal |
| `exporter` | text | postava, ze které je export |
| `exportedAt` | číslo | čas zápisu |
| `games` | pole | hry, seřazené od nejstarší |
| `debts` | pole | dluhy, seřazené od nejstaršího |
| `balances` | pole | otevřené dluhy sečtené za dvojici dlužník → věřitel, od největšího |

### `games[]`

| pole | typ | význam |
|---|---|---|
| `id` | text | unikátní id hry |
| `time` | číslo | konec hry |
| `host` | text | kdo hru založil |
| `bet` | číslo | sázka |
| `mode` | text | `duel`, `mass` (hromadný) nebo `ring` (okruh) |
| `players` | pole textů | všichni hráči |
| `winner` | text | vítěz |
| `loser` | text / chybí | jen v režimu `ring`: jediný, kdo platí |
| `payout` | číslo | kolik vítěz celkem vyhrál (`bet` × počet platících) |
| `verified` | bool | `true` = exportující postava hru sama viděla ve skupině. `false` = přišla jen zprávou přes guildu od hostitele (běžné, když u hry nebyla). |

### `debts[]`

Každý poražený dluží vítězi sázku. V režimu `ring` platí jen `loser`.

| pole | typ | význam |
|---|---|---|
| `id` | text | `<id hry>:<dlužník>` |
| `game` | text | id hry |
| `from` | text | dlužník |
| `to` | text | věřitel |
| `amount` | číslo | původní částka |
| `remaining` | číslo | kolik zbývá zaplatit (0 = zaplaceno; méně než `amount` = částečně zaplaceno tradem) |
| `paid` | bool | zaplaceno |
| `paidAt` | číslo / chybí | kdy bylo označeno jako zaplacené |
| `time` | číslo | kdy dluh vznikl |
| `confirmed` | bool | dluh potvrdil dlužník nebo ho exportující postava viděla. U cizích her, kde exportující nebyl, je běžně `false`. |

### `balances[]`

Hotový souhrn pro připomínky typu „kdo komu dluží“. Obsahuje jen dvojice, kde zbývá něco zaplatit.

| pole | typ | význam |
|---|---|---|
| `from` | text | dlužník |
| `to` | text | věřitel |
| `amount` | číslo | součet `remaining` všech otevřených dluhů |
| `confirmed` | číslo | totéž, ale jen z potvrzených dluhů |
| `since` | číslo | čas nejstaršího otevřeného dluhu |

## Co export obsahuje a co ne

- **Hry celé guildy:** addon ukládá i hry, u kterých exportující postava nebyla. Každý hostitel totiž po hře pošle výsledek do guildy. Podmínka je, aby exportující postava byla v tu chvíli online.
- **Zaplacení:** zaplacení ohlásí věřitel do guildy, tlačítkem nebo automaticky po tradu. Částečné platby (`remaining`) se ale do guildy nehlásí. Ty zná jen ten, kdo trade dělal.
- **Testovací hry** (`/sucdr test`) v exportu nikdy nejsou.
- **Historie:** zaplacené dluhy addon maže po 120 dnech, hry po roce. Bot by si tedy měl historii ukládat sám a slučovat podle `id`.
- **Více exportérů:** export lze číst z víc postav a PC zároveň. Slučuj podle `id`. Pro `paid` platí, že `true` vyhrává.

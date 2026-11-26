# Stand Up Comedy DR (SUCDR)

Addon do World of Warcraft (Midnight) pro guildu Stand Up Comedy: death roll o goldy ve skupině, s evidencí dluhů, statistikami a žebříčkem.

Hotové balíčky ke stažení jsou v záložce **Releases**, zdrojový kód addonu je ve složce `SUCDR/`. Addon je i na [CurseForge](https://www.curseforge.com/wow/addons/stand-up-comedy-dr).

## Instalace přes WowUp (doporučeno, aktualizace samy)

1. Nainstaluj [WowUp](https://wowup.io).
2. Ve WowUp otevři **Get Addons → Install from URL**.
3. Vlož adresu `https://github.com/Stand-Up-Comedy/StandUpComedyDR` a potvrď **Import / Install**.
4. Nové verze ti WowUp nabídne samo.

Do pole *GitHub Personal Access Token* v nastavení WowUp nic nevyplňuj, jinak instalace selže.

## Ruční instalace

1. V **Releases** stáhni nejnovější `SUCDR-x.y.z.zip`.
2. Rozbal ho do `World of Warcraft\_retail_\Interface\AddOns` (vznikne složka `SUCDR`).
3. Úplně restartuj hru.

Ve hře: `/sucdr` otevře okno, `/sucdr help` vypíše příkazy.

## Vydání nové verze (pro správce)

Vydání je automatické (workflow `.github/workflows/release.yml`):

1. Ve změně addonu zvyš `## Version:` v `SUCDR/SUCDR.toc` (např. na `0.9.6`).
2. Nahoru do `CHANGELOG.md` přidej sekci `## 0.9.6` s popisem změn.
3. Jakmile se změna dostane do `main` (merge pull requestu), workflow sestaví `SUCDR-0.9.6.zip`, vytvoří release `v0.9.6` (WowUp ho hráčům nabídne) a nahraje zip na CurseForge.

Na CurseForge se nahrává jen s nastaveným secretem `CF_API_KEY` (API token z CurseForge) v **Settings → Secrets and variables → Actions**. Verze hry se bere z `## Interface:` v `SUCDR.toc`. Pokud verze v `.toc` už release má, workflow nic nevydá.

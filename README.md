# Stand Up Comedy DR (SUCDR)

Addon do World of Warcraft (Midnight) pro guildu Stand Up Comedy: death roll o goldy ve skupině, s evidencí dluhů, statistikami a žebříčkem.

Tady jsou jen hotové balíčky ke stažení (záložka **Releases**). Addon je i na [CurseForge](https://www.curseforge.com/wow/addons/stand-up-comedy-dr).

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

Po zveřejnění nového releasu se zip `SUCDR-x.y.z.zip` automaticky nahraje na CurseForge (workflow `.github/workflows/curseforge.yml`). Verze hry se bere z řádku `## Interface:` v `SUCDR.toc`, changelog z popisu releasu a pre-release se nahraje jako beta.

Workflow potřebuje secret `CF_API_KEY` (API token z CurseForge) v **Settings → Secrets and variables → Actions**. Starší release jde nahrát ručně přes **Actions → Upload to CurseForge → Run workflow** a zadání tagu.

# Changelog

Poznámky k verzím SUCDR. Při vydání nové verze sem přidej sekci `## x.y.z` nahoru – text se použije jako popis releasu na GitHubu i jako changelog na CurseForge.

## 0.12.0

**Guildovní loterie** (záložka Loterie, `/sucdr loterie`): guild master ji vyhlásí, losy se platí předem tradem a addon sám přidělí čísla. Hrát může kdokoli (jde omezit jen na guildu). Čím víc losů se prodá, tím větší výhra. Na konci se zveřejní seznam losů a guild master vylosuje výherce veřejným /roll. Hráči vidí aktuální výhru a svoje losy.

Přibyly nové soubory, po aktualizaci je potřeba hru úplně restartovat.

## 0.11.0

**Výzva na duel**: pravým klikem na hráče (v cíli, ve skupině, v guildě nebo v seznamu přátel) vyber „SUCDR: vyzvat na death roll“, nebo napiš `/sucdr vyzva Jmeno`. Hraje se o sázku z okna. Vyzvanému vyskočí okno Přijmout / Odmítnout. Po přijetí tě addon pozve do skupiny (pokud v ní ještě nejste spolu) a duel se sám spustí, žádné zakládání ani join.

**Tituly v tooltipu**: po najetí myší na hráče uvidíš jeho tituly (Legenda, Smolař, High roller...) a počet her a výher. Vypnout jde v Nastavení.

Přibyly nové soubory, po aktualizaci je potřeba hru úplně restartovat (nestačí /reload). Výzva funguje jen mezi hráči s verzí 0.11.0.

## 0.10.0

Nový režim **Rozdíl**: všichni hodí jednou 1..sázka a nejnižší hod platí nejvyššímu rozdíl obou hodů. Při shodě nahoře nebo dole se hází znovu, když hodí všichni stejně, je remíza a nikdo nic neplatí. Kdo nehodí včas, počítá se mu 1.

**Dvojnásob nebo nic**: po skončeném duelu může hostitel tlačítkem „2× nebo nic“ založit odvetu stejné dvojice o všechno, co poražený dluží. Když odvetu vyhraje poražený, dluhy se smažou a jsou si kvit. Když prohraje, dluží dvojnásob a jde to zkusit znovu.

Odvetu správně vyrovná jen verze 0.10.0, aktualizujte prosím všichni. Rozdíl se se staršími verzemi hraje i počítá správně.

## 0.9.6

Guild master nove sbira hry z guildy automaticky minutu po prihlaseni (vypnuti: `/sucdr collect off`, zapnuti: `/sucdr collect on`). Po rucnim sberu addon rovnou nabidne zapsat export pro Discord bota, takze bot ma data za celou guildu.

## 0.9.5

Zaplacené dluhy se nově dorovnají i u ostatních: po přihlášení, při joinu nového hráče do skupiny a tlačítkem Sync (žádné staré nezaplacené dluhy u třetích stran). Guild master může v Nastavení (nebo `/sucdr collect`) sebrat od online členů guildy hry a stav dluhů za posledních 30 dní a u sebrané hry si vyžádat log od hostitele. Novinky fungují jen mezi hráči s verzí 0.9.5, aktualizujte prosím všichni.

## 0.9.4

Oprava ceskych znaku v tooltipech (mody hry, odznaky, minimapa, zaplatit) a v potvrzovacich oknech (zaplaceno, overeni dluhu, export).

## 0.9.3

Oprava: export JSON poskozoval nektera ceska pismena ve jmenech (napr. R s hackem).

## 0.9.2

Export pro Discord bota je nove ve formatu JSON (format 2). Popis a ukazka nacteni v EXPORT.md v balicku.

## 0.9.1

Tlacitko Exportovat pro Discord v Nastaveni a prikaz /sucdr export: zapise export pro Discord bota (provede /reload, behem rozehrane hry nejde).

## 0.9.0

Export pro Discord bota: pri odhlaseni nebo /reload addon zapise SUCDR_Export do SavedVariables (WTF\Account\<ucet>\SavedVariables\SUCDR.lua). Popis formatu je v EXPORT.md v balicku.

## 0.8.2

Nové ikonky odznaků (černá kočka pro Smolaře, koruna pro Legendu, ...). Stačí /reload.

## 0.8.1

V seznamu addonů ve hře se addon jmenuje Stand Up Comedy DR. Jinak beze změn, stačí /reload.

## 0.8.0

Kontrola verzí mezi hráči, odznaky a tituly ve statistikách.


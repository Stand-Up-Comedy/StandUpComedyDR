# Changelog

Poznámky k verzím SUCDR. Při vydání nové verze sem přidej sekci `## x.y.z` nahoru – text se použije jako popis releasu na GitHubu i jako changelog na CurseForge.

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


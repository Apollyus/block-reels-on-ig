# MyGram – Instagram bez Reels a Explore (iPhone)

Osobní iOS appka (SwiftUI + `WKWebView`), která načte `instagram.com` a skryje Reels, Explore
a navržený obsah. Feed sledovaných, stories, DM, vyhledávání a profil fungují dál. Žádný server,
žádná analytika, žádné neoficiální API – appka jen upravuje zobrazení stránky na zařízení.

## Instalace na vlastní iPhone (bez placení)

Potřebuješ Mac s Xcode 15+.

```sh
brew install xcodegen
# v project.yml případně změň bundle id (com.example.mygram) na vlastní
DEVELOPMENT_TEAM=TVOJE_TEAM_ID xcodegen     # team id: Xcode → Settings → Accounts
open MyGram.xcodeproj
```

V Xcode vyber svůj iPhone a stiskni Run. Zdarma stačí běžné Apple ID – podpis ale platí **7 dní**,
pak je potřeba appku znovu nainstalovat. Obnovu může automatizovat SideStore/AltStore (ověř aktuální
stav). Placený Apple Developer Program (99 USD/rok) = podpis na rok. App Store se nepoužívá.
Appka jako PWA nejde: do cizí webové stránky se skripty vkládat nedají, to umí jen vlastní prohlížeč.

## Jak to funguje

Filtry vznikají z **jednoho souboru** `Sources/MyGramCore/Resources/filters.json`:

| Vrstva | Co | Kde |
| --- | --- | --- |
| 1 | `WKContentRuleList` (`css-display-none`, jen jednoduché selektory) | `FilterBuilder.contentRuleListJSON` |
| 2 | CSS vložené při `.atDocumentStart` (až s `:has()`) | `FilterBuilder.css` |
| 3 | `filters.js`: `MutationObserver` + hook na `history.pushState/replaceState/popstate` | `filters.js` |

Navigaci řídí `URLPolicy` (`allow / redirectHome / openInSafari / blockAndGoBack`):

- `/reels/…`, `/explore/…`, `/<uživatel>/reels/` → zpět na `/` (výjimka: `/explore/search/`).
- `/reel/<id>/`, `/p/<id>/`, `/<uživatel>/reel/<id>/` → povoleno. Id se zapamatuje; přechod na
  **jiné** id bez kliknutí (swipe) se vrátí zpět.
- `/reels/<id>/` je povoleno jen z `/direct/…` nebo z už otevřeného Reelu.
- Cizí domény, `mailto:` apod. → Safari.
- Na stránce jednoho Reelu se pravidlo „Reel ve feedu“ nepoužije (`skipOnContentPages`), jinak by
  se skryl právě otevřený Reel.

Skrytí počtu lajků: iOS Nastavení → MyGram → „Skrýt počty lajků“ (projeví se po restartu appky).

## Zprávy přes Zkratky

Notifikace o zprávách posílá dál oficiální appka Instagram (vlastní appka push od Instagramu
dostat nemůže). Zkratka po otevření Instagramu přepne do MyGram rovnou na DM.

1. Zkratky → Automatizace → Nová → Aplikace → Instagram → „Je otevřena“ → **Spustit okamžitě**.
2. Akce: **Otevřít zprávy v MyGram** (App Intent).
3. Vypnout „Oznámit při spuštění“.
4. V Instagramu nechat zapnuté jen notifikace zpráv; lajky, Reels a doporučení vypnout.
5. Ikonu Instagramu přesunout jen do Knihovny aplikací.

Appku jde otevřít i přes `mygram://open` (DM) nebo `mygram://open?path=/direct/inbox/`
(jen cesty povolené `URLPolicy`). Omezení: Instagram se na zlomek vteřiny ukáže, než automatizace
přepne, a do konkrétní konverzace se z notifikace dostat nedá – otevře se seznam DM.

## FilterHealth

3 s po načtení domovské stránky (přihlášený uživatel) se ověří, že „kotevní“ selektory
(`health` v `filters.json`, např. záložka Reels) něco našly. Když ne, nahoře se zobrazí varování –
Instagram nejspíš změnil web. Oprava = úprava `filters.json`.

## Testy

- `swift test` – `URLPolicy` (každý řádek pravidel), generování CSS / JS / rule listu, health, deep linky.
- `npm install && npm test` – `filters.js` nad falešným DOM (jsdom).
- GitHub Actions (`.github/workflows/ci.yml`) spouští obojí a navíc build appky pro simulátor.

### Ruční kontrola na iPhonu po každé změně selektorů

Start (žádný záblesk záložek Reels/Explore) · scroll feedu 2 min · DM s Reelem (přehraje se se
zvukem, swipe dál nefunguje) · ruční zadání `/reels/` a `/explore/` · profil · hledání · přidání
příspěvku a story · odkaz mimo Instagram se otevře v Safari.

## Co je potřeba ověřit na skutečném webu (nešlo to z cloudu)

Kód vznikl bez přístupu k Xcode ani k Instagramu, nebyl tedy přeložen ani spuštěn na iPhonu
(v Actions poběží `swift test` a build). Je nutné ověřit:

1. **Search**: pokud mobilní web otevírá hledání jen přes `/explore/`, appka ho zablokuje.
   Oprava v `filters.json`: odeber `"/explore"` z `blockedPrefixes` a položku `a[href="/explore/"]`
   ze skupiny `navigation`.
2. **URL Reelu z DM** (`/reel/<id>/`, `/reels/<id>/`, nebo modál nad `/direct/`) – případně uprav
   `URLPolicy.classify` a testy.
3. Zda Instagram ve `WKWebView` nenabízí „Otevřít v aplikaci“ (nastaven Safari User-Agent).
4. Selektory: Instagram mění web často, tak se mohou rozbít (viz FilterHealth).

## Rizika

Změny webu Instagramu (rychlá oprava přes `filters.json`), chybějící funkce mobilního webu (Notes,
hlasové zprávy, část nálepek – použij oficiální appku) a podmínky Instagramu. Appka nic nescrapuje
ani neautomatizuje, nelogguje cookies ani obsah a neposílá data nikam mimo Instagram.

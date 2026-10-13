# Pretraga naslovnice: Mali GPU, mobilni ekran i pametni search (13. 10. 2026.)

LIVE: v2.0.183 (razmak + mobilni ekran), v2.0.184 (pametni search).
Commitovi: `a7e567a`, `bcc07f7`, `d2b1d86`.

Vezani dokumenti: `docs/search-and-mobile-header-worklog.md`,
`docs/web-delivery-and-rendering.md`, `docs/plans/virtualni-kanali.md` (odluka O6).

## 1. „Nakon fra ne mogu upisati drugu riječ" — kvar crtanja, ne unosa

Prijava s Androida. Reproducirano na farmi, **moto g86** (MediaTek MT6878,
**Mali-G615 MC2**, Chrome, Gboard), produkcija v2.0.182, skwasm.

| Mjerenje | Rezultat |
|---|---|
| `document.activeElement.value` (CDP) | `"fra stje"` — unos ispravan |
| Što Flutter crta u paleti | „frastje" (razmak negativne širine), „d" kao „đ" („epizođe", „Mlađ za Domovinu") |
| Isti uređaj, `/search` (bez transforma) | ispravno |
| edge 30 ultra (Adreno), ista paleta | ispravno |
| Desktop Chrome / Playwright s iOS UA, 4× CPU throttle | ispravno — emulacija kvar NE vidi |

Uzrok: paleta se otvarala `ScaleTransition` (0,96 → 1,0) i ostajala pod tim
transformom; skwasm na Mali GPU-u pod njim krivo crta glifove. Popravak: samo
`FadeTransition` (pri opacity 1 nema sloja). Test `test/search_overlay_test.dart`
drži da polje nikad nije pod scale transformom.

**Pravilo:** tekst (osobito polje za unos) ne ostavljati pod scale
tranzicijom/transformom; dijalozi se otvaraju fadeom.

**Kako se to dijagnosticira** (bez ovoga se kvar ne vidi):

1. `adb forward tcp:9333 localabstract:chrome_devtools_remote` →
   `playwright.connectOverCDP('http://localhost:9333')` → usporedi
   `activeElement.value` sa screenshotom (`adb exec-out screencap`).
2. Lokalni build na uređaju: `adb reverse tcp:<port> tcp:<port>` + statički
   server s `COOP: same-origin` i `COEP: credentialless`. `localhost` je secure
   context, pa ostaje skwasm (isti renderer kao produkcija); LAN IP bi pao na
   canvaskit i test ne bi vrijedio.
3. Tipkati tapovima po Gboardu (`adb shell input tap`), ne `input text` —
   `input text` zaobilazi IME i zna pojesti prvo slovo.

## 2. Mobilni ekran pretrage

- `shortestSide < 600` (mobitel i u landscapeu) → pretraga preko cijelog
  ekrana s `viewInsets` paddingom; strelica natrag zatvara, × briše upit.
  Centrirana paleta s `maxHeight 0.8 × ekran` nije znala za tipkovnicu: u
  landscapeu je bila potpuno prekrivena.
- Tipka „traži" na tipkovnici mobitela samo spušta tipkovnicu (i keydown
  Enter, koji Gboard na webu šalje, ignorira se na mobitelu); Enter na
  desktopu otvara odabrani red.
- Dok je tipkovnica gore, podnožje (ID / „Prikaži sve") je skriveno — u
  landscapeu je zauzimalo jedini preostali redak.

**Brzina lokalnog sloja.** Korpus: 3326 epizoda, 2,7 MB (`search.json`).
Prije se sve foldalo u svakom `build()`: ~75 ms po buildu (M-čip, JIT), a
build se okidao na spinner, dolazak rezultata i svaku notifikaciju
`channelCache`-a. Sada indeks jednom ~24 ms, upit ~4 ms. `foldText` ima ASCII
brzi put (bez `split('')`).

## 3. Pametni search — tri izvora, jedan rezultat

Povod: `pNSblshqEuU` („Nedjeljom u 2: Damir Sabol") i `UUKPkDRfPMo` („Jo
Nesbø") su ad-hoc obrade (kanal `_unlisted`); `generate_channel_index.js`
preskače `_`-direktorije, pa ih nema u listinzima ni `search.json`. Meili
`episodes` ih ima (derivat ClickHousea, bez filtra po kanalu).

```mermaid
flowchart LR
  Q[upit, normalizeQuery] -->|150 ms| L[lokalno: channelCache + search.json]
  Q -->|200 ms, ≥2 znaka| M[Meili episodes]
  Q -->|420 ms, ≥3 znaka| S["/api/search semantika"]
  L --> X[mergeSearchResults<br/>ključ = YouTube ID]
  M --> X
  S --> X
  X --> R["razredi: naslov/osoba → tekst → samo semantika<br/>chunkovi iste epizode = ≤3 trenutka"]
```

Kod: `lib/services/unified_search.dart` (čista funkcija, testovi u
`test/unified_search_test.dart`), UI u `lib/screens/home/search_overlay.dart`.

Odluke i zamke:

- **Djelomični Meili pogoci.** Meili po defaultu (`matchingStrategy: last`)
  odbacuje riječi s kraja dok ne nađe pogotke, pa „damir sabol" vrati svakog
  „Damira". Meili pogodak je „po naslovu" samo kad `<em>` u naslovu pokriva
  SVE riječi upita (`coversAllTokens`); inače ide u razred teksta.
- **Nema isječka članka.** `article_text` nije u `displayedAttributes` indeksa,
  pa `_formatted.article_text` nikad ne stiže (provjereno curl-om) — i `/search`
  zbog toga nema isječak. Isječak je zato iz `_formatted.section_titles`.
  Producer nismo dirali.
- **`_unlisted` / `_*`** se ne prikazuju kao kanal; red ima samo datum.
- Lokalni rang: naslov +6, govornik +3 (inače epizoda u kojoj je osoba samo
  govornik pobjeđuje onu s imenom u naslovu).
- Odabir (↑/↓) prati ID epizode dok mreža preslaže listu; odgovor za zastarjeli
  upit se baca.
- `/search` ostaje puni prikaz (filtar po kanalu); u paleti vodi „Prikaži sve
  rezultate".
- **`MeiliClient.baseUrl`** je bez `--dart-define=MEILI_URL` gađao `localhost`
  — nightly (iOS/Android) i `flutter run` imali su mrtav full-text. Sad default
  `AppBrand.config.endpoints.meili`.
- `/api/search` odbija `localhost` origin (CORS) — semantiku i trenutke
  provjeravati tek na produkciji.

Provjereno na produkciji v2.0.184: „damir sabol" → Sabol 1. s trenucima
6:28 / 12:19 / 52:48; „Jo Nesbø" 1.; „fra stjepan" i „kako odgajati djecu"
(praćeni kanali) ispravno.

## 4. Usput: „Nanovoroeni"

Nije font. Na hladnom `/search` indeks kanala nije bio učitan, pa je chip
nastajao iz sluga (`nanovoroeni`). Ekran sad pričeka `channelCache.loadIndex()`.

## Otvoreno

- [ ] Pametni search i mobilni ekran nisu isprobani na pravim **iPhoneima**
  farme (samo emulacija; stara verzija je u emulaciji bila ispravna).
- [ ] Native (iOS/Android) build s novim `MeiliClient` defaultom — prvi
  nightly nakon v2.0.184; provjeriti da full-text radi u aplikaciji.
- [ ] Isječak iz članka u Meiliju traži `article_text` u `displayedAttributes`
  (domovina-rag `sync-meili.sh`) — odluka, ne napravljeno.
- [ ] Ostale scale animacije s tekstom na Mali uređaju nisu provjerene
  (`streak_flags.dart` ScaleTransition, pinka `Transform.scale`) — kratke,
  završavaju, ali vrijedi pogledati na moto g86.

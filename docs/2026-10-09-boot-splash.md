# Boot splash: od prvog bajta do prvog Flutter framea (9.10.2026.)

## 1. Što se događalo

Plavi HTML splash (`#boot-intro`) micao se na `flutter-first-frame` **ili nakon
fiksnih 6 s**. `<html>`/`<body>` nisu imali pozadinu, a `#legal-footer` je
namjerno trajno u DOM-u (Google OAuth provjera). Na sporoj mreži Flutter treba
puno više od 6 s, pa je korisnik gledao bijelu stranicu s footerom.

Mjereno na produkciji (v2.0.174), mobilni viewport 390 px, hladni cache:

| profil | splash nestaje | `main()` start | prvi frame | bijela praznina | `main()`→`runApp` |
|---|---|---|---|---|---|
| bez throttlinga | 1,5 s | 1,3 s | 1,5 s | 0 | 0,2 s |
| Slow 4G | 6,4 s | 16,7 s | 19,7 s | **13,3 s** | 3,0 s |
| 3G | 6,8 s | 34,0 s | 37,1 s | **30,3 s** | 3,0 s |

```bash
python3 scripts/measure-boot.py https://domovina.ai/ --profile none
python3 scripts/measure-boot.py https://domovina.ai/ --profile slow4g --mobile
python3 scripts/measure-boot.py https://domovina.ai/ --profile 3g --mobile
```

Profili su u headeru skripte (Slow 4G = 1,6 Mbit/s / 150 ms RTT, Lighthouse).

## 2. Gdje ode vrijeme na sporoj mreži

Put je **ograničen propusnošću**, ne latencijom:

| datoteka | preko žice | host |
|---|---|---|
| `main.dart.wasm` | 1,57 MB (br) | domovina.ai |
| `skwasm.wasm` | 1,2 MB | gstatic.com |
| google_fonts (7 varijanti TTF) | ~0,7 MB | fonts.gstatic.com |

≈ 3,5 MB pri 1,6 Mbit/s ≈ 17–18 s, što odgovara izmjerenom prvom frameu.

```bash
curl -s -o /dev/null -H 'Accept-Encoding: br' -w '%{size_download}\n' https://domovina.ai/main.dart.wasm
```

Usputni nalazi (nisu popravljeni u ovom koraku):

- `main()`→`runApp` je na sporoj mreži točno 3,0 s: `AppTypography.awaitPreload`
  dosegne svoj timeout, jer fontovi kreću tek kad Dart starta (serijski iza
  wasma). Preload fontova iz HTML-a ne bi pomogao — isti bajtovi, ista cijev.
  Pomaže samo manje bajtova (subset/woff2 umjesto punih TTF-ova).
- `main.dart.wasm` počinje tek kad stigne `main.dart.mjs` (~0,5 s na Slow 4G,
  ~1 s na 3G). `<link rel=preload>` bi to uštedio, ali na pregledniku bez
  WasmGC (stariji Safari, ide `main.dart.js`) bi potrošio 1,5 MB uzalud.
- `main.dart.wasm` ima `cf-cache-status: DYNAMIC`, TTFB ~0,5 s (ostali asseti
  ~0,07 s). Worker ga šalje uz `CDN-Cache-Control: no-store`.

## 3. Što je promijenjeno (`web/index.html`)

- **Splash se miče samo na `flutter-first-frame`.** Fiksni timeout od 6 s je
  maknut. Osigurač za slučaj da event izostane (promjena enginea): 20 s
  **nakon što stigne `main.dart.wasm`/`.js`** — tada je sve preuzeto, a
  `main()` do `runApp` traje ≤ ~3 s, pa osigurač nikad ne otkrije prazninu.
- **Boja prije prvog framea = boja teme.** Inline skripta u `<head>` čita
  `localStorage['theme_mode']` (isti ključ kao `ThemeController`) i postavlja
  `data-theme`; `html` i splash dobivaju `#111318` (tamna, default) ili
  `#faf7f2` (svijetla) — `scaffoldBackgroundColor` iz `AppTheme`. Prijelaz
  splash → aplikacija je fade unutar iste boje. Pozadina je samo na `html`,
  ne na `body`, jer bi body prekrio `#legal-footer` (`z-index:-1`).
- **Hijerarhija:** wordmark „DOMOVINA" + crveni „.ai" (kao u headeru),
  podnaslov, tanki indikator, faza. Opis za Google provjeru i linkovi ostaju u
  izvornom HTML-u, prigušeni na dnu.
- **Istinite faze:** „Preuzimanje aplikacije…" → „Pokretanje…" kad
  `PerformanceObserver` vidi da je stigao `main.dart.wasm`/`.js`. Nakon 8 s
  preuzimanja: „Veza je spora. Aplikacija se preuzima samo prvi put…"
  (istina: asseti se nakon toga revalidiraju s 304).
- **Greška:** neuspjelo učitavanje skripte enginea/aplikacije ili odbijen
  fetch/compile wasma prije prvog framea → „Učitavanje je zapelo." + gumb
  „Pokušaj ponovno".

Poslije (lokalni release build kroz `wrangler pages dev build/web`, Slow 4G,
mobilni): splash do 20,1 s, prvi frame 20,1 s, **praznina 0 ms**; snimke svake
2 s pokazuju samo splash.

```bash
python3 scripts/measure-boot.py http://localhost:8788/ --profile slow4g --mobile --shots /tmp/shots
```

## 3a. Splash se miče tek kad je platno NACRTANO (v2.0.176 → 2.0.178)

Dvije prijave nakon prvog deploya, obje s otvorenim DevToolsima uz Slow 4G:

1. v2.0.175: 1–2 s nakon `flutter-first-frame` vidio se samo legal footer.
   Event znači da je frame *složen*; skwasm ga rasterizira u workeru.
   → v2.0.176: čeka se `<canvas>` u shadow rootu `flt-glass-pane`, a
   `flutter-view` nosi boju teme (footer više ne proviruje).
2. Lokalno nakon toga: 2–3 s praznog ekrana u boji teme. Platno je postojalo,
   ali je bilo prazno. → Platno se presnima u 8×8 (`createImageBitmap`) i
   splash se miče tek kad je > 32 od 64 piksela neprozirno (naslovnica uvijek
   crta neprozirnu pozadinu). Osigurač 8 s nakon eventa.

Kod mene (Mac, Slow 4G) razmaci su mali, ali poredak je sad zajamčen:

| CPU | firstFrame | canvas | painted | fade |
|---|---|---|---|---|
| 1× | 20 342 | 20 402 | 20 512 | 20 635 |
| 6× | 20 947 | 21 076 | 21 204 | 21 309 |

```bash
python3 scripts/measure-boot.py http://localhost:8788/ --profile slow4g --cpu 6
```

## 4. Citat dok se čeka (isti skup kao TV splash)

Splash prikazuje nasumičan biblijski citat iz istog skupa kao Android TV:
Mt 10,26-27 (native TV splash) + 13 citata iz `defaultBibleVerses`
(`lib/screens/tv/widgets/tv_loading_tips.dart`). Tekst je KS Jeruzalemska
Biblija, provjeren na biblija.ks.hr (`docs/splash-bible-citations-factcheck.md`)
— zato web nema vlastiti popis, nego doslovnu kopiju koju čuva
`test/boot_splash_verses_test.dart`.

- U HTML-u stoji Mt 10,26-27 (preglednik bez JS-a, crawler); inline skripta
  odmah iza njega, prije prvog iscrtavanja, izabere nasumičan citat različit
  od prošlog učitavanja (`localStorage['boot_verse']`).
- **Krug dok se čeka:** citati se izmjenjuju promiješanim redom bez
  ponavljanja (pa novi krug), fade 0,45 s; uz `prefers-reduced-motion` bez
  animacije. Rotacija staje kad `#boot-intro` nestane.
- **Trajanje po duljini:** `2,5 s + 350 ms × riječi`, ograničeno na 5–15 s
  (sabrano čitanje, ne skeniranje). Mt 9,37 (6 riječi) → 5 s, Luka 8,17
  (17) → 8,5 s, Mt 10,26-27 (33) → 14 s. Izmjereno u pregledniku: izmjene na
  0 / 9 / 18 s za Luka 8,17 → Mt 5,37 → Mk 4,22.
- **Bez skakanja:** okvir (citat + izvor) dobiva `min-height` najduljeg citata
  u trenutnoj širini; mjeri se ponovno na `resize` i kad stigne Lora
  (`document.fonts.ready`). Wordmark i traka napretka stoje na istom pikselu
  kroz cijeli krug (mobitel y = 65 / 361, desktop 132 / 454).
- Lora Italic (`ital` dodan u Google Fonts `<link>`), atribucija s crvenom
  crticom kao na TV-u.
- Na brzoj vezi citat se vidi ~1,5 s — svjesno: kratak pogled, bez čekanja.
- Novi/izmijenjeni citat: prvo fact-check na biblija.ks.hr, pa Dart popis,
  pa `web/index.html` (test pada dok nisu isti), pa po potrebi PNG-ovi za
  TV (`scripts/generate-premium-splash-taglines.py`).

## 5. Otvoreno (sljedeći koraci, po učinku)

1. Fontovi: ~0,7 MB TTF-ova je ~3 s na Slow 4G (= 3 s timeout u `main()`).
   Subset (latin + latin-ext) kao asset ili manje varijanti.
2. Edge cache za `main.dart.wasm` (TTFB 0,5 s → ~0,07 s) — provjeriti je li
   `CDN-Cache-Control: no-store` još nužan uz purge u deploy skripti.
3. Preload `main.dart.wasm` samo kad preglednik ima WasmGC (inline detekcija).

## 6. Više faza ispod trake (28.10.2026.)

Prije su bile dvije: „Preuzimanje aplikacije…” → „Pokretanje…”. Sada su
četiri, i svaka se **mjeri**, ne izmišlja. Redak ide samo naprijed, a promjena
ide uz fade od 0,2 s (bez njega uz `prefers-reduced-motion`).

| faza | tekst | okidač |
|---|---|---|
| 0 | Preuzimanje aplikacije… | početno stanje |
| 1 | Pogon za crtanje je tu, stiže ostatak… | Resource Timing: `skwasm`/`skwasm_heavy`/`canvaskit` `.wasm` |
| 2 | Pokretanje… | Resource Timing: `main.dart.wasm`/`.js` |
| 3 | Priprema fontova… | `main()` → `reportBootStage('fonts')` pred `AppTypography.awaitPreload` |

Faza 3 dolazi iz Darta kao `CustomEvent('app-boot-stage', detail: 'fonts')`
(`lib/services/boot_stage.dart`, uvjetni import po `dart.library.js_interop`,
na nativeu no-op). Pogon i kod aplikacije preuzimaju se paralelno; kad kod
stigne prvi, faza 1 se preskače.

Izmjereno lokalno (release, `wrangler pages dev`, Slow 4G, mobitel, CPU 4×):

| ms | tekst |
|---|---|
| 0 | Preuzimanje aplikacije… |
| 14 278 | Pogon za crtanje je tu, stiže ostatak… |
| 16 549 | Pokretanje… |
| 17 361 | Priprema fontova… |
| 20 637 | splash nestaje (praznina 0 ms) |

```bash
python3 scripts/measure-boot.py http://localhost:8788/ --profile slow4g --mobile --cpu 4
```

Skripta sada ispisuje i retke `faza <ms> <tekst>`.

Odbačeno nakon mjerenja: „Učitavanje tvojih postavki…” (inicijalizacija servisa
u `main()` traje ~10 ms, pa je fade uvijek preskoči) i „Slaganje stranice…”
(`runApp` → prvi frame ~70 ms; tekst se pojavi tek kad splash već blijedi).

Otvoreno: preuzimanje je i dalje najdulja faza (~12 s na Slow 4G). Pravi
postotak bi tražio da bajtove broji naš kod, ne Flutterov loader, jer Resource
Timing javlja tek završenu datoteku. Postotak koji se procjenjuje iz vremena ne
bi bio istinit.

## 7. Traka 0–100 % po stvarnim bajtovima (29.10.2026.)

Prijedlog je bio procijeniti brzinu veze i iz nje puniti traku. Nije bilo
potrebno: Flutterov loader dohvaća `main.dart.wasm` i `skwasm.wasm` kroz
**globalni `fetch`** (`compileStreaming(fetch(c))` u `flutter_bootstrap.js`), pa
splash omota `fetch` i broji bajtove tijela kako stižu. Postotak je mjeren,
ne procijenjen.

| dio trake | izvor | istinitost |
|---|---|---|
| 0–80 % | brojeni bajtovi `main.dart.wasm` + `skwasm(_heavy).wasm` | mjereno |
| 85 % | Resource Timing: `main.dart.wasm` stigao | mjereno |
| 85 → 98 % kroz 3 s | `reportBootStage('fonts')` | gornja granica: `awaitPreload` ima timeout 3 s |
| 100 % | `flutter-first-frame` | mjereno |

- **Nazivnik** su nekomprimirane veličine iz builda (fetch predaje tijelo već
  dekomprimirano). `scripts/stamp-boot-sizes.sh` ih nakon `flutter build web`
  upiše u `build/web/index.html` umjesto `/*BOOT_SIZES*/`; `deploy.sh` ga zove.
  `skwasm.wasm` s gstatic.com je ista datoteka kao `build/web/canvaskit/skwasm.wasm`.
- **Broji se klon odgovora** (`res.clone().body`), a Flutter dobiva originalni
  `Response` s URL-om, pa V8 zadrži cache kompiliranog wasma. Prva izvedba
  (v2.0.210) je predavala novi `Response` bez URL-a i zato brojanje gasila na
  ponovnom posjetu istog builda (`localStorage['boot_wasm_size']`). Prijava
  29.10. (Brave, Windows): „traka je stalno na 100 %”. Na ponovnom posjetu
  traka je bila neodređena, a uz `prefers-reduced-motion` (Windows „Animation
  effects” isključen) neodređena traka je crtana PUNA na pola prozirnosti.
  Od v2.0.211 se broji i na ponovnom posjetu, a neodređena traka bez
  animacije je prazna.
- **Kad traka ostaje neodređena**: bez upisanih veličina (`flutter run`) i na
  dart2js putanji (`main.dart.js` ide `<script>` tagom, ne fetchom).
- Postotak stoji u zasebnom `#bi-pct` s `aria-hidden`, da čitač zaslona ne
  čita svaki postotak (`#bi-load` je `aria-live`).

Izmjereno lokalno (release, `wrangler pages dev`):

| profil | traka | prvi frame |
|---|---|---|
| Slow 4G, mobitel | 0 % @ 1,0 s … 50 % @ 9,0 s … 100 % @ 16,2 s (~1,4 s po 10 %) | 20,05 s (prije 20,1 s) |
| bez throttlinga, CPU 4×, median 3 | 0 → 100 % unutar ~0,2 s | 1 057 ms (bez promjene 1 079 ms) |

Omotač dakle ne usporava pokretanje.

**Pod „Priprema fontova…” nema ničeg drugog.** Pretpostavka je bila da se tada
preuzimaju i JSON-ovi i thumbnailovi s CDN-a. Mjerenje kaže drukčije: u tom
prozoru (17,6 → 20,4 s) idu samo Roboto i četiri google_fonts TTF-a, a prvi
`cdn.domovina.ai` zahtjev (`index.json`, `home.json`) kreće 7 ms NAKON prvog
framea, kad splasha više nema. Katalog se učitava pod skeletonima aplikacije,
pa se u splashu ne segmentira. `measure-boot.py` sad ispisuje i
`cdn.domovina.ai`/`api.domovina.ai` zahtjeve, pa se to može ponovno provjeriti.

```bash
flutter build web --release --wasm && ./scripts/stamp-boot-sizes.sh
npx wrangler pages dev build/web --port 8788 &
python3 scripts/measure-boot.py http://localhost:8788/ --profile slow4g --mobile   # redak „traka …"
```

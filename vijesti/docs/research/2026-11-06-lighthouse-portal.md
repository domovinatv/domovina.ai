# Lighthouse portala vijesti (S6, 2026-11-06)

**Zaključak:** stranica članka na lokalnom produkcijskom buildu ima Lighthouse mobile
performance **100** (cilj iz odluke 3 je ≥ 90), accessibility 100, best practices 100, SEO
100. Naslovnica isto. Brojke vrijede za lokalni server bez CDN-a; na rubu Cloudflarea će
TTFB biti veći (vidi „Ograničenja”), ali stranica nema JS-a ni blokirajućih zahtjeva osim
fontova, pa ima rezerve.

## Naredbe

```bash
cd vijesti
npm run lighthouse                                     # build + shim + preview, 3× po stranici, simulirani throttling
npm run lighthouse -- --no-build                       # nad postojećim portal/dist-local/
LIGHTHOUSE_THROTTLING=devtools npm run lighthouse -- --no-build   # stvarno usporenje umjesto simulacije
LIGHTHOUSE_RUNS=5 npm run lighthouse                   # više ponavljanja
```

Skripta je `portal/dev/lighthouse.ts`. Ispisuje medijan po kategoriji (u zagradi pojedina
mjerenja) i FCP/LCP/TBT/CLS/SI, HTML izvještaj prvog mjerenja sprema u
`vijesti/.cache/lighthouse/{clanak,naslovnica}.html`. Izlazi s 1 ako je medijan performancea
članka ispod 90.

## Okolina

- Mac mini, Apple M4 Pro, macOS 26.5.1, Node 24.16.0.
- Lighthouse 13.6.0 (npm paket, devDependency), Google Chrome 156.0.8078.80 headless
  (`/Applications/Google Chrome.app`, ili `CHROME_PATH`).
- Profil: zadani mobile (Moto G Power emulacija, 412 px). Throttling `simulate` (Lantern):
  RTT 150 ms, 1,6 Mbit/s, CPU 4× sporiji. Za usporedbu i `devtools` (stvarno usporena
  mreža i CPU).
- Poslužitelj: `npm run portal:preview` u procesu skripte, tj. produkcijski Astro build
  (`output: 'server'`, `@astrojs/cloudflare`) u lokalnom načinu prijave, poslužen kroz
  `astro preview` u workerdu na `127.0.0.1:4322`; podaci iz PostgREST-shima nad PGliteom
  (`127.0.0.1:8790`, seed iz `portal/dev/seed.ts`), lažni CDN za `episode.json`.
- Članak: objavljen članak seeda (`MGLq9v3AtvE`, slug
  `matija-stepanic-u-podcastu-domovina-pa-ne-znamo-znaci-kad-ce-MGLq9v3AtvE`).

## Brojke (2026-11-06)

| stranica | throttling | performance | a11y | best practices | SEO | FCP = LCP | TBT | CLS |
|---|---|---|---|---|---|---|---|---|
| članak | simulate | 100 (100/100/100) | 100 | 100 | 100 | 604 ms | 0 ms | 0,000 |
| naslovnica | simulate | 100 (100/100/100) | 100 | 100 | 100 | 603 ms | 0 ms | 0,030 |
| članak | devtools | 100 (100/100/100) | 100 | 100 | 100 | 766 ms | 0 ms | 0,030 |
| naslovnica | devtools | 99 (99/99/99) | 100 | 100 | 100 | 757 ms | 0 ms | 0,073 |

Preneseno na članku (devtools): dokument 11,9 kB, Playfair Display Bold ttf 120,9 kB,
Inter Regular woff2 43,1 kB, Inter SemiBold woff2 46,8 kB, favicon 1,0 kB; ukupno oko
230 kB. Nijedna skripta, nijedan zahtjev izvan izvora (`<audio preload="none">` ne vuče
medij dok čitatelj ne klikne).

## Što je popravljeno usput

Prvo mjerenje je best practices članka dalo 96 u jednom od tri ponavljanja:
`errors-in-console` zbog `GET /favicon.ico` → 404 (portal nije imao `<link rel="icon">`, pa
je preglednik tražio ikonu s korijena). Portal sada ima vlastitu ikonu
`/vijesti/favicon.png` (kopija `web/favicon.png`, 32×32) i link u `Base.astro`; e2e to
provjerava. Nakon toga 100/100/100.

## Ograničenja

- **Lokalni server nije rub Cloudflarea.** TTFB je ovdje 9–34 ms; na produkciji Worker
  za svaki neuhvaćen zahtjev ide u PostgREST na Coolifyju (dva upita za članak, plus
  `episode.json` s CDN-a s prekidom 1,5 s), pa TTFB može biti stotine milisekundi.
  Rubni cache (odluka 608, posao za S7) to uklanja za ponovljene posjete; prvo mjerenje
  na `domovina.ai/vijesti` treba ponoviti nakon S7 (PageSpeed Insights ili ova skripta
  uz URL produkcije).
- **Simulacija ≠ stvarni uređaj.** Lantern procjenjuje FCP iz grafa zahtjeva; `devtools`
  varijanta je stvarnija i daje oko 160 ms više, ali na istom stroju. Mjerenje na
  fizičkom mobitelu (farma uređaja) nije napravljeno.
- **CLS naslovnice 0,03–0,07** dolazi od zamjene fontova (`font-display: swap`): ispod
  granice 0,1, ali je to prvo mjesto za poboljšanje (`size-adjust` na zamjenskom fontu)
  ako stvarni podaci pokažu više.
- Najveći pojedinačni teret je neizmijenjeni Playfair ttf (121 kB, OFL Reserved Font Name,
  odluka 609); preload ga stavlja na kritični put naslova.
- Seed ima pet kratkih članaka; dugi članak s mnogo citata (više `<audio>` elemenata)
  nije mjeren.

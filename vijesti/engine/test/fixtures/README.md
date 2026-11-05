# Fixturei: 5 stvarnih epizoda s cdn.domovina.ai

Izvučeni 5.11.2026. skriptom `npm run fixtures:refresh`
(`engine/test/fixtures-refresh.ts`, popis `FIXTURES`). Skripta ide na mrežu i nije
dio `npm run check`; testovi čitaju samo ove datoteke kroz lažni CDN
(`engine/test/fake-cdn.ts`).

Svaka epizoda je skraćena na **prvih 15 min**: SRT blokovi i `words` cueovi koji
počinju prije 15:00, iteracije i sekcije članka (i outlinea) čiji
`start_time`/`screenshot_timestamp` je prije 15:00. JSON zadržava stvarni oblik, uz
dvije iznimke: iz `info.json` (yt-dlp dump od ~85 kB) ostaju samo polja koja loader
čita, a iz `episode.json` `inline` izbačen je Magisterium. `files` je nepromijenjen
(stvarni popis s R2), pa loader za datoteku s popisa koje nema u fixtureu dobije 404.

| ID | Kriterij | Zašto |
|---|---|---|
| `pIx_7N-6HJ4` | s `words.json` | mreze_rijeci, 32 min, 2 govornika; soniox, `anchored` 1 |
| `P9sLks-f2mQ` | bez `words.json` | iva_kraljevic, 83 min, 2 govornika; članak gemini-3.5-flash |
| `x3w2BVZJ9vQ` | engleska | catholic_futurist, 21 min; `diarized.srt` je HRVATSKI prijevod, izvornik je `diarized.en.srt` + `words.en.json`; sažetak i članak na hrvatskom |
| `MGLq9v3AtvE` | > 3 govornika | CroAI Code Club, 12 oznaka govornika u SRT-u (10 u prvih 15 min); ujedno 2 h 11 min s `words.json`; `summary.source.channel` je `_unlisted`, listing `domovina_tv` |
| `b-nls1ck8EE` | duga (> 2 h) | domovina_tv, 2 h 41 min, 4 iteracije članka; soniox |

Veličine po epizodi i vrijeme izvlačenja su u `manifest.json` (sve ispod 200 kB).
`channels/` drži `index.json` i listinge četiriju kanala, filtrirane na ove epizode.

Ako epizoda više ne zadovoljava kriterij (npr. dobije `words.json` backfillom),
skripta pada s porukom i treba izabrati drugu epizodu u `FIXTURES`. Tiha zamjena bi
promijenila što test dokazuje.

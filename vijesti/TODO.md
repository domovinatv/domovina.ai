# TODO — portal vijesti

Radna lista. Čuva se u repou da napredak preživi između sesija. Označene stavke su gotove
i provjerene (`npm run check` zelen u `vijesti/`). Odluke idu u
[docs/decisions.md](docs/decisions.md).

Plan po sesijama: [docs/plan.md](docs/plan.md). Handoff po sesiji: [docs/handoffs/](docs/handoffs/)
(pravila lanca i stanje u njegovom README-u).

Legenda: `[x]` gotovo · `[ ]` otvoreno · `[~]` u radu · `(!)` traži korisnika · `→ Sn` planirana sesija

## F0 — temelj i mjerenje (ništa javno)

- [ ] `vijesti/package.json`, TypeScript strict, eslint, vitest, `npm run check` → S1
- [ ] CDN loader s tipovima za `info.json`, `summary.json`, `article.json`, `episode.json`, `diarized.srt`, `words.json`, channel listing → S1
- [ ] Fixturei: 5 stvarnih epizoda (jedna bez `words.json`, jedna engleska, jedna s više od 3 govornika), skraćeni na ≤ 200 kB po epizodi → S1
- [ ] Shema `vijesti` (moments, stories, articles, article_versions, article_sources, corrections, runs) + migracije, testovi na PGlite → S1
- [ ] `LlmClient` sučelje, Gemini klijent, lažni klijent za testove; brojač poziva i tokena po `run` → S1
- [ ] Izvlačenje trenutaka (prompt + JSON shema izlaza) → S2
- [ ] Provjera citata prema `words.json`: normalizacija (dijakritika, interpunkcija, razmaci), dopušteno odstupanje, SRT fallback s oznakom niže sigurnosti → S2
- [ ] Odbačeni trenuci zapisani s razlogom, ne izgubljeni → S2
- [ ] `vijesti extract <id>` CLI → S2
- [ ] Ocjena vijesti (novost, tko govori, konkretna tvrdnja) → S3
- [ ] (!) Mjerenje na uzorku: koliko epizoda, procjena poziva prije pokretanja → S3
<!-- doc-refs:ignore-start -->
- [ ] Izvještaj `docs/research/YYYY-MM-DD-f0-mjerenje.md`, svaka brojka s naredbom → S3
<!-- doc-refs:ignore-end -->
- [ ] (!) Odluka korisnika: nastavljamo li na F1 → S3

## F1 — prvi format i javna objava

- [ ] Format „vijest iz podcasta”: obrnuta piramida, 300–500 riječi, naslov, lead, citati s vremenom → S4
- [ ] Stilski vodič HR (treće lice, pravopis IHJJ, bez emojija, bez superlativa bez izvora) → S4
- [ ] Verify: svaka rečenica ima izvorni trenutak ili ide uredniku označena → S4
- [ ] Verzije članka (svaka promjena nova verzija, izvori po verziji) → S4
- [ ] Stanja: nacrt → pregled → odobreno → objavljeno → ispravljeno / povučeno → S5
- [ ] Dnevnik ispravaka (javan na članku) → S5
- [ ] API za portal i admin (smještaj po pravilu iz CLAUDE.md: pisanje u bazu = Supabase) → S5
- [ ] Astro SSR na Cloudflare Workers: naslovnica, članak, kategorija → S6
- [ ] Audio isječak uz svaki citat, „Poslušaj cijeli razgovor” → `/v/<id>/t/<sec>` → S6
- [ ] Admin urednika iza Supabase prijave (uloga `editor`) → S6
- [ ] Playwright e2e + Lighthouse budžet → S6
- [ ] News sitemap (48 h), RSS, canonical, robots, `NewsArticle` JSON-LD → S7
- [ ] `/vijesti/*` kroz `web/_worker.js` (service binding) + `scripts/test-social-tags.mjs` → S7
- [ ] Impresum, stranica „Kako nastaju članci” (AI + urednik), politika ispravaka → S7
- [ ] (!) Produkcijska shema na `api.domovina.ai` → S7
- [ ] (!) Upis elektroničke publikacije kod AEM-a, glavni urednik → S7
- [ ] (!) Popis dopuštenih kanala (`allowlist`) → S7
- [ ] Dnevni job (launchd LaunchAgent), idempotentan, Telegram kroz `telegram-notify.rb` → S8
- [ ] (!) 30 objavljenih članaka bez ispravka citata → S8

## F2 — priče i povezivanje

- [ ] Embedding trenutaka, grupiranje u priče, spajanje s postojećom pričom → S9
- [ ] Stranica priče + format „pregled” (što su o X rekli podcasti) → S9
- [ ] Stranice tema i osoba, veza na `/p/:slug` → S10
- [ ] Meili indeks `articles`, pretraga portala → S10
- [ ] Push novog članka kroz FCM teme → S10

## F3 — formati, jezici, brzina

- [ ] Formati: intervju (pitanja i odgovori), citati tjedna, objašnjenje → S11
- [ ] Stilovi kao prikaz iste kanonske stranice → S11
- [ ] Zaštita od duplikata: prag sličnosti, najviše N članaka po priči → S11
- [ ] EN izdanje odobrenih članaka, hreflang → S12
- [ ] Newsletter → S12
- [ ] Okidač iz pipelinea (cilj < 2 h od objave podcasta do nacrta) → S13
- [ ] (!) Pristanak kreatora, veza s vlasništvom kanala i dijeljenjem prihoda → S13

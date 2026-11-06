# TODO — portal vijesti

Radna lista. Čuva se u repou da napredak preživi između sesija. Označene stavke su gotove
i provjerene (`npm run check` zelen u `vijesti/`). Odluke idu u
[docs/decisions.md](docs/decisions.md).

Plan po sesijama: [docs/plan.md](docs/plan.md). Handoff po sesiji: [docs/handoffs/](docs/handoffs/)
(pravila lanca i stanje u njegovom README-u).

Legenda: `[x]` gotovo · `[ ]` otvoreno · `[~]` u radu · `(!)` traži korisnika · `→ Sn` planirana sesija

## F0 — temelj i mjerenje (ništa javno)

- [x] `vijesti/package.json`, TypeScript strict, eslint, vitest, `npm run check` → S1
- [x] CDN loader s tipovima za `info.json`, `summary.json`, `article.json`, `episode.json`, `diarized.srt`, `words.json`, channel listing → S1
- [x] Fixturei: 5 stvarnih epizoda (jedna bez `words.json`, jedna engleska, jedna s više od 3 govornika), skraćeni na ≤ 200 kB po epizodi → S1
- [x] Shema `vijesti` (moments, stories, articles, article_versions, article_sources, corrections, runs) + migracije, testovi na PGlite → S1
- [x] `LlmClient` sučelje, Gemini klijent, lažni klijent za testove; brojač poziva i tokena po `run` → S1
- [x] Izvlačenje trenutaka (prompt + JSON shema izlaza) → S2
- [x] Provjera citata prema `words.json`: normalizacija (dijakritika, interpunkcija, razmaci), dopušteno odstupanje, SRT fallback s oznakom niže sigurnosti → S2
- [x] Odbačeni trenuci zapisani s razlogom, ne izgubljeni → S2
- [x] `vijesti extract <id>` CLI → S2
- [x] Ocjena vijesti (novost, tko govori, konkretna tvrdnja) → S3
- [x] Backend `agy` (tmux, po uzoru na `fetch.domovina.tv/lib/agy_tmux.js`) + `npm run eval` (`--channels`, `--limit`, `--max-calls`, procjena prije poziva), testirano bez pravih poziva → S4 (prvi dio)
- [ ] (!) ODGOĐENO (korisnik 6.11., odluka 315): pravo mjerenje kroz `agy` na uzorku ~40 epizoda / 8 kanala (~440 poziva, 5–8 h, $0). Korisnik kaže kad; pokreće se noću s `run_in_background`, bez praćenja napretka. Naredbe (iz `vijesti/`): `VIJESTI_LLM_BACKEND=agy npm run eval -- --channels mreze_rijeci,iva_kraljevic,catholic_futurist,domovina_tv --limit 5 --dry-run`, pa isto s `--max-calls 500`, pa `npm run eval:report -- --out docs/research/YYYY-MM-DD-f0-mjerenje.md` (odluke 400–412) → kasnije, prije S7
<!-- doc-refs:ignore-start -->
- [ ] Izvještaj `docs/research/YYYY-MM-DD-f0-mjerenje.md`, svaka brojka s naredbom → S3
<!-- doc-refs:ignore-end -->
- [ ] Pravih 10 nacrta (agy) nakon odgođenog mjerenja; `--fake` daje 5 (5 fixturea), `docs/research/2026-11-06-prvi-nacrti.md` → nakon mjerenja
- [ ] (!) Odluka korisnika: nastavljamo li na F1 i s kojim pragom ocjene (nakon mjerenja; do tada privremeni prag) → prije S7

## F1 — prvi format i javna objava

- [x] Format „vijest iz podcasta”: obrnuta piramida, 300–500 riječi, naslov, lead, citati s vremenom → S4
- [x] Stilski vodič HR (treće lice, pravopis IHJJ, bez emojija, bez superlativa bez izvora) → S4
- [x] Verify: svaka rečenica ima izvorni trenutak ili ide uredniku označena → S4
- [x] Verzije članka (svaka promjena nova verzija, izvori po verziji) → S4
- [x] Stanja: nacrt → pregled → odobreno → objavljeno → ispravljeno / povučeno → S5
- [x] Dnevnik ispravaka (javan na članku) → S5
- [x] API za portal i admin (smještaj po pravilu iz CLAUDE.md: pisanje u bazu = Supabase) → S5 (RLS + SECURITY DEFINER `rpc`, odluka 500; na pravom Supabaseu neisprobano → S7)
- [x] Astro SSR na Cloudflare Workers: naslovnica, članak, kategorija → S6
- [x] Audio isječak uz svaki citat, „Poslušaj cijeli razgovor” → `/v/<id>/t/<sec>` → S6
- [x] Admin urednika iza Supabase prijave (uloga `editor`) → S6 (lokalna prijava u e2e; prava Supabase prijava neisprobana → S7)
- [x] Playwright e2e + Lighthouse budžet → S6 (19 e2e; Lighthouse mobile članak 100, lokalno)
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

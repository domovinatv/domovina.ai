# Odluke — portal vijesti

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …), da se
paralelni worktreeji ne sudare. Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-05, planiranje)

1. **Samostalna aplikacija u `vijesti/`**, s vlastitim `package.json`, lockfileom i
   `npm run check`. Ne dira Flutter aplikaciju (`packages/podcast_core/`) ni korijenski
   `package.json`. Iznimka je S7: ruta `/vijesti/*` u `web/_worker.js`.
2. **Pipeline se ne mijenja.** Engine čita CDN samo čitanjem. Ako treba nešto što pipeline
   ne daje, to ide kao zahtjev u `fetch.domovina.tv` (zapis u TODO s `(!)`), ne kao
   zaobilaženje.
3. **Portal je Astro sa server-side renderom na Cloudflare Workers**, ne Flutter (SEO,
   LCP, Google News). Revidira se samo ako S6 izmjeri da Astro ne može dati Lighthouse
   mobile ≥ 90.
4. **Na `domovina.ai/vijesti`, ne na poddomeni** (autoritet domene).
5. **Jedna kanonska stranica po priči i formatu.** Stilovi nisu zasebni URL-ovi.
6. **Testovi nikad ne zovu mrežu ni LLM.** Fixturei i lažni klijent. Pravi pozivi idu samo
   kroz `npm run eval -- --max-calls N`, koji prije pokretanja ispiše procjenu.
7. **Objava ide samo kroz urednika** (Zakon o medijima, AI Act čl. 50(4)). Nema
   automatske objave ni u jednoj fazi.
8. **Samo kanali s popisa dopuštenih.** Popis puni korisnik.

## S1 (2026-11-05)

100. **Alati: TypeScript strict, ESM, zod, vitest, eslint `strictTypeChecked`.** Node
     22+ (`engines`), lokalno 24. tsconfig uz `strict` pali `noUncheckedIndexedAccess` i
     `exactOptionalPropertyTypes`. Runtime validacija svega izvana (CDN, LLM) ide kroz
     zod 4, skripte kroz `tsx`. Razlog: isti jezik za engine i Astro portal, a ulaz s
     CDN-a i iz modela se ne vjeruje bez provjere. Revizija: ako `npm run check` naraste
     iznad ~30 s zbog type-aware linta.
101. **`episode.json` je popis istine za epizodu.** Inline sadržaj se koristi umjesto
     zasebnog zahtjeva, datoteka koje nema na popisu se ne traži, a popis iz disk cachea
     koji kaže „nema” se jednom revalidira prije zaključka. Bez `episode.json` loader ide
     datoteku po datoteku, kao Flutter. Razlog: pravila iz korijenskog `CLAUDE.md`.
102. **404 se ponavlja jednom s `?cb=<floor(now / 300 000)>`.** Drugi 404 znači da
     datoteke nema; 404 se ne sprema u cache; ostali ne-2xx statusi su greška
     (`CdnHttpError`), ne „nema datoteke”. Razlog: CDN cachira 404 do 4 h.
103. **Disk cache `vijesti/.cache/cdn/<putanja>`.** Per-epizoda datoteke bez roka,
     `episode.json` i `channels/data/*` s rokom od 5 min, zapis atomaran (tmp +
     rename). Revizija: ako engine počne čitati datoteke koje pipeline prepisuje pod
     istim imenom (`reels.json`), one idu u promjenjive.
104. **Loader šalje vlastiti `User-Agent`** (`domovina-vijesti/0.1 (+https://domovina.ai/vijesti)`).
     Razlog: Cloudflare vraća 403 Pythonovom `urllib` (izmjereno 5.11.), pa ne ovisimo
     o tome što zadani klijent pošalje, a promet engina je prepoznatljiv u logovima.
105. **Uparivanje `words.json` po početku ±1 ms, a kod istog početka i po kraju.**
     Odstupa od Flutterovog uparivanja samo po početku, koje cueove od 0 ms koji dijele
     početak sa sljedećim ostavlja bez vremena (8 promašaja na 3 epizode, poslije
     popravka 0). Cue s drugim brojem riječi je `count_mismatch`, bez vremena, nikad
     pomaknut. Isti popravak vrijedi predložiti Flutteru, izvan ovog lanca.
106. **Jezik citata nije `summary.language`.** To je jezik izlaza (uvijek `hr`).
     `diarized.srt` na engleskim kanalima je negdje hrvatski prijevod
     (`x3w2BVZJ9vQ`), negdje engleski izvornik (`nuNw4qWs0r4`), bez metapodatka.
     Loader prima `lang` i tada uzima `diarized.<lang>.srt` + `words.<lang>.json` kad ih
     `episode.json` navodi, a `moments` ima `quote_lang`. Kako engine zna jezik snimke,
     odlučuje S2. Prijedlog: jezik kanala u popisu dopuštenih (odluka 8).
107. **`runs` je zbroj po prolazu, trošak je NULL dok cijena nije u konfiguraciji.**
     Stupci: `calls`, `failed_calls`, `tokens_in`, `tokens_out` (izlaz uključuje
     „thinking” tokene), `cost_usd`. Cijena dolazi iz `VIJESTI_GEMINI_PRICE_*_PER_MTOK`,
     jer cjenik nismo provjerili i ne upisujemo broj bez izvora. Neuspio poziv (HTTP,
     prekid, shema) se broji, jer su tokeni plaćeni. Jedan poziv bez cijene čini ukupni
     trošak nepoznatim. Revizija: ako S3 treba trošak po pozivu, dodaje se tablica
     `llm_calls`.
108. **Vlastiti runner migracija** (`db/migrate.ts`, `NNN_ime.up.sql` + `.down.sql`,
     svaka u transakciji). Shemu `vijesti` i `vijesti.schema_migrations` stvara runner,
     pa `down` prve migracije briše tablice, a trag o stanju ostaje. Baza je iza sučelja
     `SqlDb` (`exec`, `query`) koje PGlite zadovoljava izravno; produkcija dobiva
     adapter u S7.
109. **Ograničenja u shemi od prvog dana.** `quote_check` CHECK (`exact`, `fuzzy`,
     `srt_only`, `failed`), `end_ms > start_ms`, neprazan citat, UNIQUE (`video_id`,
     `start_ms`, `end_ms`, `quote`). Citiran trenutak se ne može obrisati
     (`article_sources` → `moments` RESTRICT). `articles.status` CHECK sa stanjima iz
     plana (`draft`, `review`, `approved`, `published`, `corrected`, `rejected`).
     `moments.score` je `real` bez raspona jer skalu određuje S3. Revizija: S3 (skala
     ocjene), S5 (stanja).
110. **Gemini preko REST-a `generateContent`.** Ključ ide u zaglavlje `x-goog-api-key`,
     nikad u URL. Shema izlaza ide kao `responseJsonSchema` (zod → JSON Schema 2020-12,
     bez `$schema`), uz `responseMimeType: application/json`. `finishReason` različit od
     `STOP`, blokiran ili prazan izlaz je `LlmResponseError`; izlaz koji nije JSON ili ne
     prolazi shemu je `LlmSchemaError`. Zadani model je `gemini-3.5-flash`, koji
     pipeline koristi za članke (`P9sLks-f2mQ`). Revizija: prvi pravi poziv (S2/S3) mora
     potvrditi da API prima `responseJsonSchema` za naše sheme. Ako ne prima, prelazi se
     na `responseSchema`, uz test.
111. **Lažni klijent vraća snimke `{text, usage}`** po imenu poziva ili redom, i
     validira ih istom funkcijom (`parseLlmJson`) kao pravi klijent. S1 snimke su ručno
     napisane (`engine/test/fixtures/llm/README.md`), jer S1 ne zove model.
112. **Kanal epizode dolazi iz listinga, ne iz `summary.source.channel`.** Epizode
     kanala `domovina_tv` tamo imaju `_unlisted`. Važno za popis dopuštenih (odluka 8).
113. **Fixturei: prvih 15 min, stvarni oblik, `info.json` sveden na polja loadera.**
     Magisterium je izbačen iz `inline`, a `files` ostaje stvaran. `fixtures:refresh`
     pada kad epizoda više ne zadovoljava kriterij, umjesto da tiho promijeni test.
     Razlog: `words.json` se backfilla (`MGLq9v3AtvE` ga je dobio tijekom ove sesije).
114. **`npm audit`: 10 moderate ranjivosti u lancu `eslint` → `minimatch`, samo dev.**
     Ne dira se dok popravak ne traži major skok. U produkcijski kod ne ulazi.
     Revizija: kad `eslint` objavi popravak ili kad portal (S6) uvede runtime ovisnosti.

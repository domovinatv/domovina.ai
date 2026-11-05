# Odluke — katalog

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …), da se
paralelni worktreeji ne sudare. Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-05, planiranje)

1. **Opseg: samo zbirni sloj.** Servis isporučuje popise (kanali, epizode po kanalu, po
   danu, naslovnica, kartica epizode). Datoteke po epizodi (`data/<id>/*`, medija, slike)
   ostaju na R2 i čitaju se kao danas. Razlog: dohvat po ključu već skalira, linearno
   rastu samo zbirne datoteke.
2. **Kod živi u `katalog/` u ovom repou**, s vlastitim `package.json` i `npm run check`
   (uzor `vijesti/`). Razlog: ugovor s `podcast_core` i testovi klijenta su ovdje.
   Revizija: ako Podcasterium treba servis bez DOMOVINA repoa, izdvaja se u zaseban repo.
3. **Cloudflare Worker + D1 + Cache API.** Bez KV-a i Durable Objecta u F0–F1. Razlog:
   pravilo „Backend placement” iz korijenskog `CLAUDE.md` (javno čitanje, bez korisničkih
   podataka i bez service rolea → Worker). Ranija odluka protiv Workera
   (`docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §7) odbacila je Worker koji drži
   JSON u memoriji; ovdje nema parsiranja velikih datoteka, svaki odgovor je indeksirani
   upit za jednu stranicu. Revizija: ako S5 izmjeri latenciju lošiju od statičnog puta.
4. **Shema je spremna za shardove od prvog dana**: stupci `brand`, `lang`, `tier`,
   `published_date`; jedna D1 baza po brendu. D1 baza ima tvrdi limit 10 GB koji se ne
   može povećati, a Cloudflare preporučuje mnogo manjih baza po tenantu. Brend je naš
   tenant.
5. **Statični snapshot ostaje rezerva i ugovor za stare buildove.** `index.json` je Tier 1
   i zamrznutog oblika. Novi podaci idu samo kroz API (ili nove datoteke).
6. **D1 je projekcija.** Upsert je idempotentan po YouTube ID-u (`episodes.id`).
   Konvergencija se mjeri prema R2 (`drift-check`), ne vjeruje se pipeline zastavicama
   (pravilo „pipeline zastavice ≠ stvarnost”).
7. **Ruta je na istom originu**: `domovina.ai/api/katalog/v1/*` (uzor
   `domovina-analytics`, ruta `domovina.ai/api/state`). Bez riječi koje adblockeri
   blokiraju (`analytics`, `track`, `collect`, `event`, `beacon`).
8. **Paginacija je samo keyset.** `OFFSET` je zabranjen. Limit stranice je u ugovoru.
9. **Testovi bez mreže**: vitest + `@cloudflare/vitest-pool-workers` (lokalni D1),
   fixturei iz stvarnih datoteka, `skipped 0`.
10. **Rad na pipelineu ide iz sesije u `fetch.domovina.tv`** (S7), nikad iz ovog repoa.
    Ovaj repo smije čitati fetch repo i CDN.
11. **Hero ostaje samo Tier 1** dok korisnik ne odluči drukčije (vrata u S12). Tier 2 se
    pojavljuje u „Danas u korpusu”, na `/dani/`, `/channels` („Svi”) i na `/c/:slug`.

## S1 (2026-11-05, kostur i shema)

100. **Verzije alata.** `wrangler` 4.107.0 i `@cloudflare/workers-types` 4.20260702.1 kao
     u `domovina-analytics` (ondje instalirano). `@cloudflare/vitest-pool-workers` 0.18.0 je
     jedina verzija koja pinna točno `wrangler` 4.107.0 i `miniflare` 4.20260701.0, pa u
     stablu postoji jedna kopija workerda (`npm ls wrangler miniflare`). Ona traži
     `vitest` ^4.1.0 → 4.1.12 (analytics je na 3.2.4 bez poola, nije uzor za testove).
     `typescript` 5.9.3 (`typescript-eslint` 8.72.1 traži < 6.1), `eslint` 10.14.0,
     `vite` 8.3.6 izravno, zbog tipova `vite/client` (`?raw`, `import.meta.glob`).
     Revizija: `wrangler` se diže samo zajedno s pool verzijom koja ga pinna.
101. **Testni API je v4 pool.** `cloudflareTest()` plugin u `vitest.config.ts`; `env` i
     `exports` iz `cloudflare:workers` (`SELF`/`env` iz `cloudflare:test` su deprecated).
     `fetchMock` u ovoj verziji ne postoji, pa mrežu zatvaraju dvije ograde: stub
     `globalThis.fetch` u `test/setup.ts` (baca) i miniflare `outboundService` (izmjereno:
     sirovi `fetch` mimo stuba dobije 500 s porukom, ne ide van).
102. **`STRICT` + `WITHOUT ROWID`.** STRICT da uvoznik ne može tiho upisati tekst u
     broj (napomena: STRICT i dalje prima `'511'` kao 511 jer je pretvorba bez gubitka).
     WITHOUT ROWID za `brands`, `channels`, `episodes`: prirodni tekstualni PK, redak
     živi u stablu PK-a. `ingest_runs` ostaje rowid tablica (`INTEGER PRIMARY KEY`).
     Revizija: ako staging D1 u S5 odbije STRICT (lokalno radi).
103. **`tier` je naš, ne registryjev**: 1 = praćen kanal s listingom, 2 = `_unlisted`;
     `CHECK (tier IN (1, 2))`. Registry tier 1–4 se ne uvozi pod tim imenom.
104. **`youtube_channel_id` je nullable i bez `UNIQUE`**: tri playlist-kanala dijele
     `UCuk9D5H9mx7birJ1-S22nyQ`, a `dijalog`/`launched`/`subclub` nemaju YouTube kanal.
105. **`duration_seconds REAL`, nullable**: postoji 245.295 s (X/Twitter) i `null`
     (`hmM9f_3Mqm4`). Cijeli broj se sprema kao REAL (test).
106. **`flags` = ugovor `PIPELINE_BITS`** (`generate_channel_index.js`,
     `VideoPipeline.fromBits`), bit 0…8, `CHECK 0–511`, `NOT NULL` bez `DEFAULT` da ga
     uvoznik mora postaviti. 0 = nijedna zastavica podignuta, ne „ne znamo”.
107. **`magisterium_score INTEGER 0–100`, nullable.** Izmjereno u `home.json`: samo
     cijeli brojevi (66–96) ili polje izostaje. Decimalna vrijednost se odbija, ne
     zaokružuje: puknuće uvoza je signal da se ugovor promijenio.
108. **Datumi su provjereni, ne samo oblikovani.** `published_date` i
     `latest_published_date`: `GLOB 'YYYY-MM-DD'` i `date(x) = x` (odbija `2026-02-30` i
     yt-dlp `YYYYMMDD`; pretvorba je posao parsera). Vremena (`updated_at`,
     `started_at`, `finished_at`) su ISO 8601, `julianday(x) IS NOT NULL`.
109. **NULL samo gdje ulaz stvarno nedostaje**: `channel_slug`, `published_date`,
     `duration_seconds`, `title_hr`, `lang`, `magisterium_score`, `avatar`,
     `latest_published_date`. `channels.name` i `episodes.title` su `NOT NULL`: kanal
     bez imena se ne stvara, epizoda tada ostaje s `channel_slug` NULL. Revizija: ako
     S2 nađe kanal bez imena koji se mora prikazati.
110. **Strani ključevi**: `episodes(brand, channel_slug) → channels`, `brand → brands`;
     D1 ih provodi. Posljedica za S2: kanal se upisuje prije epizoda, upsert je
     `INSERT … ON CONFLICT DO UPDATE`, nikad `INSERT OR REPLACE` (briše pa umeće).
111. **Indeksi i rute koje ih čitaju.**
     `episodes_by_date (brand, published_date DESC, id DESC)`: najnovije epizode
     (naslovnica, „Danas u korpusu”, S9/S12) i `/dani/:datum` (S9).
     `episodes_by_channel (brand, channel_slug, published_date DESC, id DESC)`:
     `/c/:slug` (S10), usput i provjera stranog ključa pri promjeni kanala.
     `channels_directory (brand, tier, latest_published_date DESC, slug DESC)`:
     `/channels` po tieru (S10). Odstupanje od handoffa: i drugi stupac je `DESC`, jer
     `ORDER BY a DESC, b DESC` i kursor `(a, b) < (?, ?)` traže isti smjer na oba.
     „Svi” kanali (oba tiera) po datumu ovim indeksom traže TEMP B-TREE; kad ta ruta
     dođe, dobiva svoj indeks `(brand, latest_published_date DESC, slug DESC)`.
112. **Row-value kursor radi kao raspon indeksa** (lokalni D1, miniflare
     4.20260701.0): `SEARCH episodes USING INDEX episodes_by_date (brand=? AND
     (published_date,id)<(?,?))`. Ekspandirani oblik s `OR` nije potreban.
113. **Svaki upit ima `INDEXED BY`.** Izmjereno: bez `ANALYZE` (svježa baza) upit po
     danu bira PRIMARY KEY `(brand, id)`, koji daje isti redoslijed bez sortiranja, ali
     čita cijeli brend: `rows_read` 400 umjesto ≤ 41 na 400 epizoda. Granica
     `rows_read` (tvrdi uvjet 2) ne smije ovisiti o statistici; nestanak indeksa sad je
     greška, ne tihi sken. Test zato radi bez `ANALYZE`.
114. **SQL ruta živi u `src/db/queries.ts`**, dvije varijante po ruti (prva stranica,
     iza kursora), jer `(?2 IS NULL OR …)` planer ne pretvara u raspon. Retci bez
     datuma ne ulaze u popise po datumu ni na prvoj stranici (`IS NOT NULL`) ni iza
     kursora. `MAX_PAGE_SIZE = 100`; limit izvan 1–100 baca `RangeError`. Test provjerava
     plan (indeks, bez `SCAN`, bez `TEMP B-TREE`) i `meta.rows_read ≤ 2 × limit + 1`.
115. **`ingest_runs`**: `status IN ('running','ok','failed')`, `finished_at` je NULL
     točno dok je `running`, ne prije `started_at`; `counts` je JSON objekt.
116. **Health**: samo `GET /api/katalog/v1/health` → `{ok, service, version}`,
     `cache-control: no-store`; sve ostalo (i `POST` na health) je 404 JSON
     `{ok: false, error: "not_found"}`.
117. **Fixturei u testu se uvoze, ne čitaju s diska.** U poolu rade (izmjereno) JSON
     import, `import x from "./f.json?raw"` i `import.meta.glob(…, {query: "?raw",
     import: "default", eager: true})`. Za parsere `?raw`: parser dobiva string kao u
     produkciji, a JSON import bi ga već parsirao.

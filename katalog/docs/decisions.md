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
118. **Parseri se pokreću i u Nodeu bez builda.** `src/input/` uvozi s `.ts` nastavkom
     (`allowImportingTsExtensions`, uz `noEmit`) i koristi samo brisivu TS sintaksu
     (`erasableSyntaxOnly`), pa ih Node 24 učita izravno (type stripping); isti moduli
     idu u Worker kroz esbuild i u vitest. Uvoznik S2 i `fixtures:refresh` ih uvoze iz
     `.mjs`. `engines.node >= 24`. Izmjereno (Node 24.16): parseri prođu cijeli stvarni
     ulaz, 52 listinga / 3412 epizoda, 232 `_unlisted` `info.json` s diska i 588
     registry unosa, bez greške. Revizija: ako S2 treba stariji Node.
119. **Pravila parsera.** Opcionalno polje koje nedostaje ili je `null` → `null`.
     Obavezno → `InputError`: identitet i ono što je u D1 `NOT NULL` (`id`, `title`,
     `name`, registry `slug`/`display_name`/`tracking.enabled`, `episode.json`
     `version`/`files`). Krivi tip → greška, nikad pretvorba. Prazan string → greška i u
     opcionalnom polju (D1 ga odbija `CHECK length > 0`, ovdje dobije putanju).
     Nepoznati ključevi se ignoriraju. Putanja greške koristi izvorna imena ključeva,
     korijen je `$`. Ponovljen kanal u indexu, epizoda u listingu ili slug u registryju →
     greška (izmjereno: 0 ponavljanja u svih 52 listinga, ni unutar ni preko listinga).
120. **Pipeline zastavice.** Zastavica koja nedostaje = nije podignuta; listing bez
     `pipeline` objekta → `pipeline: null`, `flags: 0`; vrijednost koja nije boolean →
     greška (strože od `pipelineBits()` u fetch repou, koji gleda truthiness). Nepoznata
     zastavica se preskače (ugovor se nadopunjuje na kraju). `fixtures:refresh` regexom
     uspoređuje `PIPELINE_BITS` s `generate_channel_index.js` i pada na razlici.
121. **`episode.json` verzija mora biti 1** (kao `EpisodeBundle.supportedVersion`);
     druga verzija je greška, ne pokušaj čitanja.
122. **`youtubeChannelId` samo iz `https://(www.|m.)youtube.com/channel/UC…{22}`.** Strože
     od Dartovog `canonicalUcId` (ondje bilo koji URL s `/channel/UC…`). `index.json`
     nema polje `youtube_channel_id`, pa Dartova „eksplicitna” grana ovdje ne postoji.
123. **Fixturei su generirani, testovi tvrde stvarne vrijednosti.** Izbor i skraćivanje
     u `test/fixtures/README.md`; upis u izvornom redoslijedu ključeva (ne sortirano: bliže
     onome što parser dobiva u produkciji), deterministički (dvaput = isti bajtovi,
     provjereno). Promjena izvora (reobrada epizode) obara test s konkretnom vrijednošću;
     to je namjerno.

## S2 (2026-11-05, uvoznik)

Mjerenja i naredbe: [research/2026-11-05-uvoz-tier2.md](research/2026-11-05-uvoz-tier2.md).

200. **Popis Tier 2 epizoda dolazi iz key cachea.** `../fetch.domovina.tv/.r2_keys_cache.json`
     je `{v: 2, sizes: {<R2 ključ>: <bajtovi>}}` (209 056 ključeva, 9,5 MB). `parseKeyCache`
     prihvaća samo `v === 2` i čita ključeve `data/<id>/<datoteka>`; `images/`, `channels/`
     i ostalo preskače. `_unlisted` u ključevima ne postoji, pa je Tier 2 = ID-evi s
     `data/<id>/article.json` (pravilo `podcast.domovina.ai` `58fb664`) minus ID-evi iz
     Tier 1 listinga. Izmjereno: 3665 − 3412 = **253**; svih 3412 Tier 1 epizoda ima
     `article.json`. Revizija: kad pipeline (S7) objavi popis izravno.
201. **Dohvat ide s CDN-a, uz jedan retry na 404.** `index.json`, 52 listinga, pa
     `info.json` + `summary.json` za svaku Tier 2 epizodu; konkurentnost 6. 404 se ponovi
     jednom s `?cb=<5-minutni bucket>` (pravilo `DataService._get`); tek drugi 404 znači
     „nema”. Izmjereno: 562 GET-a = 1 + 52 + 2 × 253 + 3 retryja (tri `info.json`, ni
     nakon retryja). Tier 1 datoteka koje nema i svaka greška parsera ruše uvoz (puknuće
     je signal da se ugovor promijenio, odluka 107). Registry se čita s diska.
202. **`flags` Tier 2 epizode računa se iz imena datoteka na R2**, po pravilima
     `generate_channel_index.js` preslikanima na R2 imena (`diarized.srt` → transcript i
     diarized, `article.magisterium.json` ili `_batch` → magisterium, `translation_en` =
     `summary.en.json` ∧ `article.en.json`). Provjera na Tier 1: 3411/3412 epizoda daje
     isti `flags` kao listing; jedina razlika je `MGLq9v3AtvE` (R2 ima
     `article.magisterium.json`, listing kaže `has_magisterium: false`, tj. listing je
     stariji od uploada). Tier 1 `flags` i dalje dolazi iz listinga (ulaz za Tier 1 je
     listing). Revizija: ako se razlika poveća, Tier 1 prelazi na ključeve.
203. **Redoslijed razrješavanja kanala Tier 2 epizode** (`src/ingest/resolve.ts`, čista
     funkcija): (a) `info.channel_id` = točno jedan Tier 1 kanal po `youtubeChannelId` iz
     `index.json`; više njih (`UCuk9D5H9mx7birJ1-S22nyQ`) → NULL,
     `ambiguous_tier1_channel_id` (izmjereno: 0 takvih epizoda); (b) registry po
     `youtube.channel_id` (odluka 204); (c) kanal bez registryja (odluka 205). Tier 2
     epizoda praćenog kanala ide na Tier 1 kanal, `tier` epizode ostaje 2, i stavka je
     izvještaja (`tier2OnTier1Channel`, izmjereno 17), ne tihi spoj. Bez `info.json` vidi
     odluku 206. Svaka epizoda bez kanala ima razlog u izvještaju.
204. **Izbor registry unosa među onima s istim `channel_id`**, redom: jedini unos; jedini
     `youtube.type === "umbrella"` (HKM `hkm` uz 9 playlista); jedini `type === "channel"`;
     jedini bez `parent_slug`; inače NULL, `ambiguous_registry_channel_id`. Pravilo
     `channel` je dodano nakon mjerenja: bez njega 36 epizoda bez kanala, s njim 22 (Podcast
     Inkubator 6, Nova Eva 5, Poslovni dnevnik 2, VIDA 1 dobivaju svoj kanal; ondje je
     jedan unos kanal, ostali su playliste tog kanala). Preostale 22 (8,7 % od 253, ispod
     praga rizika 10 %) su sa 7 YouTube kanala koji u registryju imaju samo playliste: TV
     Jadran 8, Jutarnji list 4, HRT vijesti 4, Anze Tomic 3, VTV 1, RTL 1, NOVA TV 1.
     Popravak je u registryju (unos `umbrella` ili `channel` za te `channel_id`-eve), ne u
     pogađanju. Registry slug koji nakon `-` → `_` postoji kao Tier 1 CDN slug je taj Tier 1
     kanal (`registry_tier1`); inače Tier 2 kanal sa slugom i `display_name` iz registryja.
     Parser registryja zato čita i `youtube.type` i `parent_slug`.
205. **Kanal bez registryja: slug `yt-<channel_id>` ili `x-<channel_id>`**, po
     `info.extractor` (`youtube`, `twitter`; izmjereno samo ta dva). Veličina slova ostaje
     (`yt-UCckHqySbfy5FcPP6MD_S-Yg`): YouTube ID razlikuje velika i mala slova, a CDN
     slugovi su mala slova s `_`, registry mala slova s `-`, pa izvedeni slug ne može
     pogoditi ni jedan ni drugi; resolver svejedno baca ako bi pogodio. Drugi extractor →
     NULL, `unknown_extractor`. Ime je `info.channel`, a kad ga nema `info.uploader` (X
     zapis `CUJmOc91C64` nema `channel`, `uploader` je „Hobba 🟢”; to je ime iz izvora, ne
     naš tekst sučelja, pa pravilo bez emojija ne vrijedi). Bez oba → NULL,
     `no_channel_name` (izmjereno 0; odluka 109 ostaje). `youtube_channel_id` je NULL za X.
     Oznaka je stupac `channels.unregistered` (migracija `0002`; `DEFAULT 0` samo jer
     `ADD COLUMN … NOT NULL` traži zamjensku vrijednost, uvoznik ga uvijek piše;
     `CHECK (unregistered IN (0, 1) AND (unregistered = 0 OR tier = 2))`, provjereno u
     poolu). Izmjereno: 28 takvih kanala, 31 epizoda.
206. **Epizoda bez `info.json` se ne baca.** Naslov, datum i trajanje dolaze iz
     `summary.json` `source`, kanal iz `source.channel` samo ako je to Tier 1 CDN slug
     (`summary_source_channel`), inače NULL, `no_info_json`. Izmjereno: 3 takve epizode,
     sve s kanalom (`6dcab9c9837`, `cd7ac05aabf` → `subclub`, `eab99cbaefd` →
     `launched`). Dopuna S1: `source.channel` nije uvijek `"_unlisted"` (194 `_unlisted`,
     55 `_varijante`, 2 `subclub`, 1 `launched`, 1 `domovina_tv` od 253), ali se za kanal
     čita samo kad `info.json` nema. `source.upload_date` dolazi u dva oblika (185
     `YYYY-MM-DD`, 68 `YYYYMMDD`), pa ga čita `optIsoOrCompactDate`; svugdje drugdje oblik
     ostaje strog.
207. **Ime Tier 2 kanala uzima se s najnovije epizode** (datum, pa ID), jer kanali mijenjaju
     ime. Za registry kanal je `display_name` isti za sve epizode. Tier 1 ime je iz
     listinga.
208. **Eksperimentalne varijante se uvoze kao i svaka epizoda** (D1 je projekcija R2) i
     navode u izvještaju. Varijanta = 9 znakova osnovnog ID-a + `_<znamenka>`
     (`0Oo1LHNiJ_2` uz `0Oo1LHNiJR4`), pod uvjetom da osnovni ID s tim prefiksom postoji.
     Izmjereno: 55 varijanti od 15 osnovnih ID-eva, točno onoliko koliko `summary.json` ima
     `source.channel: "_varijante"`. Varijanta dobiva kanal kao i osnovna epizoda
     (`UM2MWlNUp_1` → `podcast_cuspajz` po `channel_id`) ili ga nema (`KA73jz0Q7_2…5`, TV
     Jadran, odluka 204). Revizija: ako proizvod želi varijante skrivati, treba stupac ili
     zastavica (S3+), ne filtar u uvozniku.
209. **Polja epizode.** Tier 1: iz listinga doslovno (`title`, `title_hr`, `date`,
     `duration_seconds`, `magisterium_score`, `flags`); `lang` NULL jer ga listing nema.
     Tier 2: `title` iz `info.json` (bez njega `source.title`), `title_hr` i `lang` iz
     `summary.json`, `duration_seconds` iz `info.json` (bez njega iz `source`),
     `magisterium_score` NULL (nije u `info`/`summary`; magisterium datoteke se ne
     dohvaćaju). Revizija: pipeline (S7) šalje ocjenu.
210. **`processed_count` = broj redaka u D1 s tim kanalom (oba tiera), `latest_published_date`
     = njihov najnoviji datum.** Ne `video_count`: izmjereno `video_count = len(videos)` u
     52/52 listinga, ali 17 Tier 2 epizoda praćenih kanala ne bi bilo u brojci koju lista
     `/c/:slug`. `video_count ≠ len(videos)` ostaje tripwire u izvještaju
     (`videoCountMismatch`, stvarni ulaz 0). Tier 2 kanal nema avatar ni jezik (NULL).
211. **Brend je `domovina` s hostom `domovina.ai`**, upsert istim pravilom kao ostalo.
212. **Uvoz ne briše retke koji su nestali iz ulaza** (izvan opsega S2; konvergencija je
     drift-check, S7/S11). Plan je deterministički: retci sortirani po ID-u/slugu, isti
     ulaz daje isti plan (test).
213. **Upis kroz `getPlatformProxy`, ne `wrangler d1 execute --file`.** `getPlatformProxy`
     (wrangler 4.107, `remoteBindings: false`, zadani `persist` = `.wrangler/state/v3`) daje
     `env.DB` nad istom lokalnom bazom koju čita `wrangler d1 execute katalog --local`
     (provjereno: isti retci). Razlozi: isti `applyPlan` kao u testu (pool `env.DB`),
     `meta.changes` po naredbi iz `db.batch()` bez parsiranja izlaza wranglera, i bez
     generiranja SQL-a s ručnim escapeom. Batch je 200 naredbi i transakcija; uvoz kao
     cjelina nije atomaran, pa prekid ostavi `ingest_runs.status = 'failed'` s greškom.
214. **Idempotentan upsert**: `INSERT … ON CONFLICT (brand, …) DO UPDATE SET … WHERE
     t.a IS NOT excluded.a OR …` preko svih stupaca osim `updated_at`. `IS NOT` jer `<>` s
     NULL nikad nije istinit (test: broj → NULL je promjena). Nepromijenjen redak ne broji
     se u `meta.changes` i ne pomiče `updated_at`. Izmjereno: prvi uvoz 1/162/3665 (brend,
     kanali, epizode), drugi 0/0/0, `updated_at` jedna vrijednost (vrijeme prvog uvoza).
     Kanali se pišu prije epizoda (odluka 110).
215. **`ingest_runs`**: `source = 'backfill'`, redak `running` prije upisa, `ok` ili
     `failed` nakon; `counts` je cijeli izvještaj (plan, key cache, HTTP, `written`).
216. **Fixturei S2.** Svaki kanal iz `index.json` fixturea ima i listing (plan to traži):
     dodani `slijedi_svoj_poziv_1`/`_2`, `podcast_cuspajz` (drži `UM2MWlNUpqg`), `subclub`.
     Tier 2: `A-oDNz3nvdQ` (Nova Eva, pravilo `channel`), `0sxT3NF8yFg` (VTV, dvosmisleno),
     `UM2MWlNUp_1` (varijanta, Tier 1 kanal po `channel_id`), `6dcab9c9837` (samo
     `summary.json`). `r2_keys_cache.json` je isječak stvarnog cachea za ID-eve iz fixturea.
     Grane bez stvarne epizode (dvosmislen Tier 1 `channel_id`, bez `channel_id`, bez imena,
     nepoznat extractor) testiraju se izmjenom jednog polja stvarnog `info` objekta, kao
     negativni testovi parsera.

## S3 (2026-11-05, API v1)

Rute (sve `GET`, prefiks `/api/katalog/v1`): `days/:date`, `channels`, `channels/:slug`,
`channels/:slug/episodes`, `episodes/:id/card`, `directory`, `health`. Kod u `src/api/`
(`v1.ts`, `cursor.ts`), SQL u `src/db/queries.ts`, ugovor u `contract/v1/`, testovi u
`test/api/`. Mjerenja nad stvarnim podacima su s lokalnog D1 iz S2 (3665 epizoda, 162
kanala), nakon migracije `0003` i ponovnog uvoza.

300. **Omotnica odgovora.** Popis: `{version: "1", catalog, items, next, meta: {rows_read}}`;
     jedan objekt: `{version, catalog, item, meta}`. `version` je string (stari build čita
     `as String?`, isto pravilo kao listing v2 u korijenskom `CLAUDE.md`). `catalog` = `id`
     zadnjeg `ok` retka u `ingest_runs` kao string, `null` kad uspješnog uvoza nema. Polja se
     samo dodaju, tip se nikad ne mijenja. `meta.rows_read` = zbroj `meta.rows_read` svih D1
     upita tog zahtjeva, uključujući upit brenda i verzije (`Reader` u `v1.ts`). Greška ima
     svoj oblik `{ok: false, error}` (odluka 116), bez omotnice.
301. **Kartica epizode** je ista u svim popisima epizoda i u `card`: `id, title, title_hr,
     date, duration_seconds, magisterium_score, p, tier, lang, variant_of, channel`, snake_case
     kao `ChannelVideo.fromJson` / `HomeSnapshot` (`date` = `published_date`, `p` = `flags`
     za `VideoPipeline.fromBits`). `duration_seconds` je broj ili `null` i ostaje decimalan
     (245.295; Dart radi `(num?)?.toInt()`). `channel` je `{slug, name, tier}` ili `null`
     (ključ uvijek prisutan). Kanal dolazi `LEFT JOIN`-om po PK `(brand, slug)` u istom upitu;
     plan `SEARCH c USING PRIMARY KEY (brand=? AND slug=?) LEFT-JOIN` (test). Izmjereno: JOIN
     ne povećava `rows_read` (20 redaka kanala = 40 kao i bez JOIN-a), pa granica `2 × n + 1`
     iz odluke 114 vrijedi i za upite kartice.
302. **Eksperimentalne varijante se skrivaju iz popisa.** Migracija `0003` dodaje
     `episodes.variant_of TEXT` (`NULL` ili `length > 0`, STRICT), uvoznik ga puni iz
     `experimentalVariants` koje plan već računa (odluka 208), upsert ga uključuje u `SET` i u
     `WHERE … IS NOT` (odluka 214). `episodes_by_date` i `episodes_by_channel` su ponovo
     stvoreni kao parcijalni `WHERE variant_of IS NULL`; svaki upit epizoda nosi
     `e.variant_of IS NULL` doslovno i i dalje `INDEXED BY` (bez tog uvjeta parcijalni indeks
     nije upotrebljiv i `INDEXED BY` pukne, a ne skenira). `card` vraća i varijantu, s
     `variant_of` = osnovni ID. `processed_count` i `latest_published_date` (odluka 210) broje
     samo ne-varijante, pa `processed_count` = broj stavki `/channels/:slug/episodes` (test
     nad fixtureima: `podcast_cuspajz` 21 redak, 20 u popisu i u `processed_count`).
     Izmjereno na stvarnim podacima: 55 varijanti, 51 na 14 kanala, 4 bez kanala; nijedan kanal
     ne pada na 0, `latest_published_date` se ne mijenja ni jednom; `podcast_cuspajz` 178 →
     174 = 174 stavke u popisu. Prvi uvoz nakon migracije: 0 / 14 / 58 promijenjenih redaka
     (55 varijanti + 3 epizode koje su se na CDN-u promijenile od S2), drugi 0 / 0 / 0.
     Epizoda bez datuma ima 0, pa „uključujući one bez datuma” u shemi kanala zasad nema
     razlike. Posljedica: parcijalni `episodes_by_channel` više ne služi provjeri stranog
     ključa pri brisanju kanala ili promjeni sluga (tada bi SQLite skenirao `episodes`).
     Uvoz danas ništa ne briše (odluka 212); revizija kad drift-check počne brisati kanale.
     `variant_of` nema strani ključ: `ALTER TABLE ADD COLUMN` ne može dodati složeni ključ.
303. **`/directory` i `/channels` bez `tier` čitaju isti indeks i isti skup.** Novi parcijalni
     `channels_all_by_date (brand, latest_published_date DESC, slug DESC) WHERE
     processed_count >= 1` (predviđen odlukom 111); upit `allChannels` nosi
     `processed_count >= 1` doslovno. Plan: `SEARCH channels USING INDEX channels_all_by_date
     (brand=? AND latest_published_date>?)`, iza kursora `(latest_published_date,slug)<(?,?)`,
     bez SCAN i TEMP B-TREE. Za `channels` bez tiera uvjet ne mijenja skup: kanal bez obrađene
     epizode nema ni datum (plan ih računa iz istih redaka), a popis po datumu takve ionako ne
     pokazuje. Izmjereno: oba popisa daju istih 162 kanala. `channels?tier=` ostaje na
     `channels_directory`. Ruta `directory` je zadržana zasebno da se može razići (npr.
     abecedni poredak) bez promjene `channels`; to je otvoreno pitanje za S10.
304. **Keyset kursor i limit.** Kursor je base64url bez paddinga nad JSON nizom
     `[datum, ključ]` (epizode `[published_date, id]`, kanali `[latest_published_date, slug]`).
     400 `bad_cursor` kad se ne da dekodirati, nije niz od dva neprazna stringa, datum nije
     valjan, ili zapis nije kanonski (ponovno kodiranje mora dati isti string: s paddingom ili
     razmakom u JSON-u isti kursor bi imao dva ključa u cacheu). `?cursor=` prazan je
     `bad_cursor`. Za `days/:date` datum u kursoru mora biti jednak `:date`. `limit`: zadano
     30, `^\d{1,3}$` i 1–100 (`MAX_PAGE_SIZE`), inače `bad_limit` (`0`, `101`, `1.5`, `1e1`,
     `-1`, prazno). `next` iz `LIMIT n+1`: ima li n+1-vi redak, `next` = kursor n-tog, vraća
     se n; prazna i zadnja stranica imaju `next: null`. Revizija odluke 114: funkcije u
     `queries.ts` primaju `limit` do `MAX_PAGE_SIZE + 1`, jer im API predaje n+1. `OFFSET`
     čuva `test/api/no-offset.test.ts`: čita `src/**/*.ts` kroz `import.meta.glob(?raw)`, miče
     komentare (`/* */`, `//`) i pada na `\bOFFSET\b` bez obzira na veličinu slova; isti test
     dokazuje da bi provjera uhvatila `OFFSET` u SQL stringu.
305. **Brend i verzija kataloga jednim upitom.** `catalogContext`: tri skalarna podupita
     (brend po `brands.host` = `url.hostname`, bez porta; brend `env.DEFAULT_BRAND`; `max(id)`
     iz novog parcijalnog indeksa `ingest_runs_ok (id) WHERE status = 'ok'`). Host koji nije u
     tablici pada na `DEFAULT_BRAND` (wrangler `vars`, `"domovina"`), da `wrangler dev` na
     localhostu radi; ni tako → 404 `brand_not_found`. Izmjereno `rows_read` 2–3, konstantno:
     `ingest_runs_ok` daje `max(id)` jednim čitanjem kako god tablica rasla (`SEARCH
     ingest_runs USING COVERING INDEX ingest_runs_ok`), dok bi `max(id) WHERE status='ok'` bez
     indeksa čitao cijelu tablicu. Parametri i datum se provjeravaju PRIJE baze, pa loš zahtjev
     ne troši ništa.
306. **`INDEXED BY` i za dohvat po PK.** PK tablice WITHOUT ROWID SQLite imenuje
     `sqlite_autoindex_<tablica>_1` i prima ga u `INDEXED BY` iako ga nema u `sqlite_schema`
     (izmjereno lokalno); `UNIQUE (host)` u `brands` je `sqlite_autoindex_brands_2` (postoji u
     shemi). Tako i kartica, zaglavlje kanala, JOIN kanala i upit brenda poštuju odluku 113.
     Revizija: ako staging D1 (S5) odbije ime autoindeksa, dohvat po punom PK ide bez
     `INDEXED BY` (jednakost na cijelom PK planer uvijek rješava po PK).
307. **Cache.** `Cache-Control` po ruti, računa se pri svakom odgovoru (i na hit), pa se
     granica „jučer” pomiče sama: `days/:date` stariji od jučer (UTC) `public, max-age=3600,
     stale-while-revalidate=86400`; danas, jučer i budućnost `public, max-age=60,
     stale-while-revalidate=300`; `channels`, `channels/:slug`, epizode kanala, `directory`
     `public, max-age=60, stale-while-revalidate=600`; `card` `public, max-age=300,
     stale-while-revalidate=3600`; greške `no-store`. Ni prošli dan nema dan-dug browser
     cache, jer pipeline backfill dodaje epizode i u stare dane. U Workeru `caches.default`:
     ključ = origin + put + sortirani poznati parametri (`limit` uvijek, normaliziran;
     `cursor`, `tier` kad su zadani; nepoznati odbačeni) + `_cv=<catalog>` (`none` bez
     uvoza). Novi `ok` uvoz daje nove ključeve, pa purge po URL-u nikad ne treba. Razlog je
     pravilo iz korijenskog `CLAUDE.md`: purge `{"files":[url]}` vrati `success` a varijanta s
     `Origin` ostane; verzija u ključu zaobilazi purge u potpunosti. Upit verzije ide na
     svakom zahtjevu i jedini je D1 upit pri hitu. Na hit tijelo je ono iz izračuna (i
     `meta.rows_read`), uz `x-katalog-cache: hit|miss`. U cache ide samo 200, kroz
     `ctx.waitUntil(cache.put)`. Dopuna: zapis u `caches.default` nosi vlastiti
     `cache-control: public, max-age=3600` (ne klijentov), jer je sadržaj po verziji
     nepromjenjiv; gornja granica od sat vremena pokriva jedini slučaj kad se D1 mijenja bez
     nove verzije (prekinut uvoz ostavi djelomičan upis i `status = 'failed'`, odluka 213).
     U testu odgovor stigne prije upisa u cache, pa test ponavlja zahtjev do `hit`.
308. **CORS: `access-control-allow-origin: *` na svim odgovorima (i greškama i health), bez
     `Vary: Origin`.** Javni podaci samo za čitanje; jedan cache zapis za web (šalje `Origin`)
     i native (ne šalje), čime se izbjegava dvostruki zapis iz
     `docs/2026-09-19-cachiran-404-vary-origin.md` (test: zahtjev s `Origin` dobije `hit` na
     zapis bez njega). OPTIONS preflight se ne dodaje (jednostavan GET ga ne treba); svaka
     druga metoda je 404 `not_found`.
309. **`rows_read` po ruti** (`test/api/rows-read.test.ts`, granica `3 × limit + 5` za
     limit 1, 5, 30, 100). Nad fixtureima, `limit=30`: `days/2026-05-13` 7,
     `days/2026-11-03` 4, `channels` 14, `channels?tier=1` 10, `channels?tier=2` 7,
     `directory` 14, `channels/podcast_cuspajz/episodes` 44 (20 stavki: 2 kontekst + 1
     zaglavlje + 2 × 20 + 1 kraj raspona); `channels/subclub` 3, `episodes/UM2MWlNUp_1/card`
     4. Na stvarnim podacima, najveća stranica: `channels` (limit 30) 35, `directory`
     (limit 100) 104, `channels/podcast_cuspajz/episodes` limit 30 → 67, limit 100 → 206
     (= 2 × 101 + 4, ispod 305), `days/2026-11-04` (26 stavki) 53. Prolaz kroz cijeli popis
     kanala (162, 6 stranica po 30) je 190 ukupno, tj. linearno u broju stavki, ne u dubini.
     Sintetički test s velikim brojem epizoda dolazi zasebno; `measure()` i `ROUTES` u istoj
     datoteci su mu ostavljeni.
310. **Ugovor: JSON Schema draft 2020-12 u `contract/v1/`.** Zajedničke `card.schema.json`
     i `channel.schema.json`; odgovori `days`, `channels`, `directory`, `channel-episodes`,
     `channel-response`, `card-response`, `error`. Odstupanje od imena u zadatku: odgovori
     `channels/:slug` i `card` su `channel-response` / `card-response`, jer su `channel` i
     `card` imena sheme stavke. `additionalProperties: false` na odgovorima, karticama,
     kanalu i `meta` (novo polje se svjesno dopiše u shemu), `null` samo gdje ga D1 dopušta,
     `items` najviše 100. `$id` (`https://domovina.ai/api/katalog/v1/contract/…`) je
     identifikator za `$ref`, ne poslužena adresa. Validator je `@cfworker/json-schema` 4.1.1
     (radi u workerd bez `eval`/`new Function`; Ajv ne radi jer generira kod kroz `new
     Function`), pinan točno u `devDependencies`; 4.1.3–4.1.6 su objavljeni 30. 10. – 4. 11.
     2026., premladi za uvođenje. Svaki 2xx i 4xx odgovor u `test/api/` prolazi shemu
     (`api()` u `helpers.ts`, `shortCircuit = false` da greška nabroji sva prekršena pravila).
311. **Rute.** Putanja se dijeli na segmente; prazan segment (kosa crta na kraju) i
     segment koji `decodeURIComponent` ne prima su 404 `not_found`. `:date` se provjerava
     istim pravilom kao CHECK u shemi (`YYYY-MM-DD` i stvaran datum, odluka 108) → 400
     `bad_date`. Redoslijed provjera: ruta (404) → parametri (400) → brend (404) → cache →
     upit (404 `channel_not_found` / `episode_not_found`). Ponovljen parametar uzima prvu
     vrijednost. `channels/:slug/episodes` dohvaća zaglavlje i stranicu jednim `db.batch`,
     da 404 za nepoznat kanal ne košta drugi odlazak do baze. `latestEpisodes` (naslovnica,
     S9/S12) je usklađen s karticom i varijantama, ali API v1 ga još ne izlaže.
312. **Glavni modul izvozi samo handler.** workerd svaki imenovani export glavnog modula
     (`main` u `wrangler.jsonc`) čita kao entrypoint i odbija sve što nije funkcija/klasa ili
     `ExportedHandler`: `export { API_PREFIX }` u `src/index.ts` rušio je `wrangler dev
     --local` („Incorrect type for map entry 'API_PREFIX'”), a vitest pool to ne vidi.
     `API_PREFIX` je u `src/api/prefix.ts`; `test/main-module-exports.test.ts` uvozi
     `src/index.ts` i pada na svaki imenovani export koji nije funkcija (dokazano privremenim
     `export const`). Izmjereno nakon popravka nad lokalnim D1 iz S2 (`wrangler dev --local
     --port 8799`): `days/2026-11-04?limit=100` → 26 epizoda (Tier 1: 4, Tier 2: 22), 3 s
     `channel: null`, 0 varijanti, `next: null`, `catalog "4"`, `rows_read` 52 (odluka 309
     je izmjerila 53; razlika je upit konteksta, 2–3 ovisno o tome nađe li se host).
313. **Sintetički `rows_read`** (`test/api/rows-read-synthetic.test.ts`): fixturei + 5000
     sintetičkih epizoda kroz isti `applyPlan` kao uvoz (jedan plan, 5127 epizoda, 340
     kanala, 211–230 ms u poolu, pa batch INSERT mimo uvoznika nije trebao). Raspodjela je
     deterministička (mulberry32, sjeme `20261105`): kanali od 2370 i 1100 epizoda, 6 po 80,
     320 s 1–2, 140 bez kanala, 30 bez datuma, „vrući” dan `2026-10-20` s 331 sintetičkih ne-varijanti
     (4 stranice po 100) i parovima ID-eva koji se razlikuju samo veličinom slova, te 400
     varijanti uz osnovnu epizodu (isti kanal i dan, ID `<9 znakova>_<n>`), pola na vrućem
     danu, dakle usred raspona koji popis čita. Za svaku rutu limit 1, 30, 100 na prvoj
     stranici i iza kursora do kojeg se dođe slijedeći `next` po 100 (200 do 1500 redaka
     duboko): `rows_read ≤ 3 × limit + 5` i duboka − prva ≤ 5. Izmjereno (prva / duboka),
     limit 30: vrući dan 62 / 63, `channels` 33 / 34, `channels?tier=2` 33 / 32, `directory`
     33 / 34, veliki kanal 65 / 66 (dubina 1500 i 800); limit 100: vrući dan 199 / 199,
     veliki kanal 205 / 206, `channels`/`directory` 103 / 43 (zadnja, kratka stranica). Isto
     kao na stvarnim podacima (206 za limit 100), pa varijante usred raspona ne troše ništa:
     nisu u parcijalnom indeksu. Kartica varijante 4, zaglavlje malog kanala 3. Uz to test
     prolista vrući dan i kanal od 1100 epizoda do kraja i uspoređuje s poretkom izračunatim
     u JS-u (datum DESC, id DESC; za ASCII ID-eve JS usporedba = SQLite BINARY), te
     `processed_count` s brojem stavki. Datoteka traje ~0,5 s. `measure()` i
     `ROWS_READ_CONSTANT` su premješteni u `helpers.ts`: uvoz iz `rows-read.test.ts` bi u
     drugoj datoteci ponovo registrirao njegove testove.
314. **Neovisni pregled `src/api/*` i `queries.ts` (S3): nema stvarne greške osim 312.**
     Provjereno testom (`test/api/review.test.ts`, svi zeleni bez promjene koda): `%2F` u
     slugu je dio sluga (dijeli se prije dekodiranja) → 404 `channel_not_found`; `%00`, SQL u
     slugu i ID-u → 404, ne 500 (sve ide kroz bind); `%73ubclub` = `subclub` (zaseban ključ
     cachea, isti sadržaj); neispravan UTF-8 → 404 `not_found`; `%2e%2e` URL parser
     normalizira prije rute; kursor s NUL-om, nepostojećim, ne-ASCII i ključem od 2000 znakova
     → 200; HEAD/OPTIONS/POST/PUT/DELETE → 404 `no-store` s ACAO; `catalog: null` (podaci bez
     `ok` uvoza) → `_cv=none`, prvi `ok` uvoz → miss s novom verzijom i istim stavkama (pool
     izolira storage po datoteci, pa je to prvi test datoteke); `Cache-Control` dana u
     00:00:00.000Z i 23:59:59.999Z, preko kraja godine i prijestupnog dana; ključ cachea
     razdvaja host, port, limit, kursor, tier i verziju, a nepoznate parametre odbacuje.
     Kursor na granici: jednaki datumi i ID-evi koji se razlikuju samo veličinom slova
     pokriveni su u 313 (usporedbu radi samo SQLite, JS ništa ne uspoređuje). Otvoreno, nije
     mijenjano: (a) HEAD je 404 (odluka 308), iako HTTP traži da GET resurs prima i HEAD; (b)
     iznimka iz D1 izlazi kao 500 iz runtimea, bez JSON-a, ACAO i `no-store`, pa je web klijent
     vidi kao CORS grešku; (c) ključ cachea nosi sirovi `pathname`, pa isti resurs može imati
     više zapisa (`%73ubclub`); (d) host koji nije u `brands` dobiva `DEFAULT_BRAND` i vlastiti
     ključ cachea, dakle proizvoljan `Host` puni cache (u produkciji to ograničava ruta zone).

## S4 (2026-11-06, sintetička skala)

Oblik stvarnog korpusa: [research/2026-11-06-raspodjela-korpusa.md](research/2026-11-06-raspodjela-korpusa.md).

400. **Iznimka iz handlera je 500 `internal` u obliku ostalih grešaka** (zatvara 314 b):
     JSON `{ok:false,error:"internal"}`, ACAO `*`, `no-store`, `console.error` s imenom,
     porukom i putanjom bez upita. Omot je u `src/index.ts`, funkcija
     `internalErrorResponse` u `v1.ts` (glavni modul izvozi samo handler, odluka 312).
     Sprema se samo 200, pa 500 nikad ne ulazi u cache (`test/api/internal-error.test.ts`:
     env bez `DB`, D1 koji baca u `all` i `batch`, sljedeći zahtjev je `miss`). Razlog: goli
     500 iz runtimea web klijent vidi kao CORS grešku. `error.schema.json` dobiva kod
     `internal`.
401. **Sintetičke raspodjele žive u `src/synth/`** kao čisti TS bez Node i Workers API-ja,
     da ih uvoze i vitest pool i Node 24. `s3.ts` je ograda za paginaciju (odluka 313,
     brojke za N=5000 i sjeme `20261105` nepromijenjene); `korpus` je oblik stvarnog
     kataloga i služi mjerenjima.
402. **`korpus` skalira na više kanala, ne na dulje kanale.** Veličine kanala uzorkuju se
     iz stvarnih po tieru (broj kanala ∝ N, ~44 na 1000 epizoda), udjeli po epizodi su
     stalni, uz `max(1, round(N/50k))` divovskih kanala od 1000–3000 epizoda (najviše
     N/10), vrući dan ~0,8 % N, bez datuma 0,05 % (stvarno 0, ali put mora postojati).
     Razlog: korpus raste novim kanalima (stvarni najveći ima 320 epizoda), a divovi daju
     duboke kursore.
403. **Generator (`scripts/synth.ts`) piše izravno u SQLite** (`node:sqlite`) odvojenog
     `--persist-to` direktorija pod `.wrangler/`, s migracijama kroz wrangler i istim
     `UPSERT_*`/`channelParams`/`episodeParams` kao `applyPlan`. `.wrangler/state` (baza
     S2 uvoza) je zabranjen, postojeći direktorij se briše samo uz `--force`. Razlog: 1M
     kroz `getPlatformProxy` bilo bi ~5000 batcheva, a shema i stupci ovako ostaju
     identični uvozniku.
404. **Skripte u TS-u imaju vlastiti `scripts/tsconfig.json`** (Node + workers tipovi,
     `@types/node@24.19.1`); `typecheck` pokriva oba projekta.

Mjerenje na 10k/100k/1M, projekcija, trošak i staging recept:
[research/2026-11-06-f0-mjerenje-lokalno.md](research/2026-11-06-f0-mjerenje-lokalno.md).

405. **Mjerenje ide kroz `scripts/measure.ts`** (`npm run measure -- --persist <dir>`).
     Miss se mjeri drugim `Host` po ponavljanju, s oznakom pokretanja, jer `--persist-to`
     čuva i Cache API na disku; prije mjerenja skripta provjeri da pet novih hostova daje
     pet missova. Hit se mjeri zasebno. Lokalno trajanje (~1–2 ms) je SQLite na Macu i ne
     ulazi u odluke; vrijedi latencija sa staginga (S5).
406. **Tvrdi uvjet 2 potvrđen na 10k, 100k i 1M epizoda**: `rows_read` po stranici isti
     na sve tri razine i na prvoj i na najdubljoj punoj stranici. Najveći je 206
     (`channels/:slug/episodes?limit=100` na divu), oblik `2 × (limit + 1) + 2…4` za
     popise epizoda i `limit + 3…4` za popise kanala; kartica 4. Nijedna ruta nije trebala
     popravak.
407. **Kapacitet i odluka 4.** 411 B po epizodi s indeksima (sintetika; stvarne 342 B, pa
     je projekcija konzervativna), budžet 7 GB po bazi (70 % od 10 GB) → 17 M epizoda.
     Shard po brendu stoji za DOMOVINA (3665 epizoda, ~9000 godišnje). Brend sa svjetskim
     korpusom treba shard unutar brenda kad `kanala × epizoda po kanalu > 17 M` (500 000
     kanala: 1 baza uz 23 epizode po kanalu, 2 uz 66, 5 uz 150); ključ je jezik/zemlja,
     hash kanala unutar jezika kad jedan jezik sam prijeđe budžet. Fan-out preko shardova
     ide u S14.
408. **Trošak se dimenzionira po Worker zahtjevima, ne po D1 čitanju.** I scenarij 100×
     (90 M zahtjeva, 1,42 mlrd. redaka mjesečno; najgori slučaj bez cachea 18,5 mlrd.) je
     ispod 25 mlrd. uključenih redaka; Workers ~25 USD iznad paušala. Pretpostavke (DAU,
     zahtjeva po sesiji, udio hita) revidiraju se stvarnim podacima iz ClickHousea u S5;
     potrošnju ostalih Workera na računu treba provjeriti u nadzornoj ploči.
409. **Staging**: `env.staging` s `workers_dev: true`, bez `routes`, Worker
     `domovina-katalog-staging`, baza `katalog-staging`. Jednokratni uvoz stvarnih podataka
     kroz `d1 export --local --no-schema` (četiri tablice podataka, bez `d1_migrations`) i
     `d1 execute --remote --file`; recept je lokalno isproban (3833 naredbe, isti brojevi i
     `rows_read`). `--remote` u `import.mjs` ostaje za S6. Novi rizik: dokumentacija jamči
     Cache API samo na custom domenama, pa S5 provjerava `x-katalog-cache: hit` na
     `workers.dev`; cache je po podatkovnom centru, pa će udio hita biti niži od 80 %.

## S5 (2026-11-06, staging i latencija)

Korisnik je 6. 11. 2026. u chatu odobrio staging („Da, pokreni”). Izvještaj:
[research/2026-11-06-staging-latencija.md](research/2026-11-06-staging-latencija.md).

500. **Staging postoji na računu D.O.M.** (isti račun i zona kao `domovina-analytics`):
     D1 `katalog-staging` (hint `eeur`, primarna u MXP), Worker `domovina-katalog-staging`
     na `workers.dev`, bez rute i bez secreta. `database_id` je u `env.staging` u
     `wrangler.jsonc`; `account_id` nije u konfiguraciji nego u `CLOUDFLARE_ACCOUNT_ID`
     (`katalog/.dev.vars`). Ostaje podignut za S6; povratak je u izvještaju.
501. **Rizici iz S4 zatvoreni na pravom D1 i edgeu**: Cache API daje `hit` i na
     `workers.dev`; STRICT i `INDEXED BY sqlite_autoindex_*` prolaze; `rows_read` po
     formuli iz 406 (33 / 65 / 4); HEAD 404; sirovi `pathname` je zaseban ključ (314 c
     potvrđen, ostaje kao poznato ograničenje); tuđi `Host` na `workers.dev` Cloudflare
     odbije s 403 prije Workera (314 d vrijedi samo na ruti zone).
502. **Hit putanja u S6 ne ide u D1.** Mjereno iz HR (VIE): hit p50 ~51 ms, Worker bez D1
     16–19 ms, CDN `HIT` 20 ms; razlika je jedno putovanje VIE → MXP za `catalogContext`
     prije `cache.match`. Kontekst (brend po hostu, verzija kataloga) ide u memoriju
     izolata s TTL-om ≤ 30 s (ili u Cache API), pa hit ne čita D1. Posljedica: novi
     uvoz se vidi do 30 s kasnije, manje od `max-age=60`. Test: hit ne zove `DB`.
503. **Miss u jednom putovanju je druga, manja izmjena** (~84 → ~50 ms): kontekst kao
     podupit u upitu rute ili kroz `DB.batch`. D1 read replication se ne uključuje dok
     502 i 503 nisu izmjereni.
504. **F1 ostaje kako je planiran**, bez snapshota iz D1 na R2 kao primarnog puta. Prva
     stranica kanala je 1,9 KB preko žice naspram 119 KB listinga; na optici je katalog
     20–50 ms sporiji, na mobilnoj vezi brži. `home.json` ostaje statični snapshot.
505. **Potrošnja računa** (30 dana do 6. 11.): 0,77 M Worker zahtjeva, 561 M pročitanih
     D1 redaka (94 % `pipeline_domovina`); račun je na Workers Paid (besplatni plan
     dopušta ~150 M redaka mjesečno). Katalog D1 kvotu ne ugrožava ni u scenariju 100×;
     dimenzionira se po zahtjevima (408 vrijedi).
506. **Latencija se mjeri skriptom `scripts/latency.ts`** (`npm run latency`): miss niz s
     različitim stvarnim ključevima, hit niz s istim ključem, `health` i dva CDN URL-a,
     50 zahtjeva po nizu. Ponovno pokretanje unutar TTL-a Worker cachea (3600 s) daje
     prazan miss niz; pravi miss traži novu verziju kataloga.
507. **Staging ima custom domenu `katalog-staging.domovina.ai`** (`routes` s
     `custom_domain: true` u `env.staging`; Cloudflare sam drži DNS zapis i certifikat),
     da aplikacija u testiranju koristi čitljiv URL; `workers.dev` ostaje uključen.
     Host nije u `brands.host`, pa brend daje `DEFAULT_BRAND`. Latencija ista kao na
     `workers.dev` (hit ~51 ms, miss ~83 ms). Produkcija i dalje ide na isti origin
     `domovina.ai/api/katalog/*` (plan); poddomena za produkciju je otvoreno pitanje za S6.
     Povratak: `wrangler delete --env staging` miče i domenu.

## S6 (2026-11-06, produkcija, ingest, drift-check)

Kod: `src/api/context.ts` (memorija konteksta), `src/api/ingest.ts` (`POST /ingest`,
`GET /ingest/ids`), `writeRows`/`commitRun`/`discardRun` u `src/ingest/write.ts`,
`episodeIds`/`existingChannelSlugs` u `src/db/queries.ts`. Ugovor:
`contract/v1/ingest-response.schema.json`, `ingest-ids.schema.json`, prošireni
`error.schema.json`. Testovi: `test/api/ingest.test.ts`, `test/api/context-memory.test.ts`.

600. **Kontekst kataloga u memoriji izolata, TTL 30 s** (`CONTEXT_TTL_MS`, provodi 502).
     Modulska `Map` po `hostname` + `DEFAULT_BRAND`, najviše 32 hosta (prijelaz briše sve,
     host dolazi iz zahtjeva). Hit uz zapamćen kontekst ne dira `env.DB` (test: D1 koji baca
     na svaki pristup). Miss uvijek ponovno čita kontekst iz D1 i osvježi memoriju, pa
     `meta.rows_read` ostaje isti kao prije (309 vrijedi bez izmjene). `brand_not_found` se
     NE pamti: nastaje samo kad baza nema ni `DEFAULT_BRAND` (prazna baza prije prvog
     uvoza), i tada brend mora proraditi odmah nakon uvoza, a ne do 30 s kasnije. Novi
     uvoz drugi izolati vide do 30 s kasnije; ingest zaboravi memoriju svog izolata.
     Testovi zaboravljaju kroz `forgetCatalogContexts()` (`okRun()` u `helpers.ts`), koji
     nije u `src/index.ts` (312).
601. **Miss uz zapamćen kontekst ide jednim odlaskom do baze** (provodi 503). `Reader.lead`
     stavlja `catalogContext` u isti `db.batch` kao upit rute (zapamćen brend daje
     parametar upita). Bez memorije ostaju dva odlaska (kontekst, pa ruta), jer upit rute
     treba brend. Ako se brend hosta u međuvremenu promijenio, izračun se baca i ponavlja.
     Izmjereno brojanjem poziva u testu: zaglavlje kanala 2 → 1 odlazak, epizode
     kanala 1 batch s tri upita. Latencija na stagingu nije ponovno mjerena.
602. **Auth ingesta: `Authorization: Bearer <token>` prema secretu `INGEST_TOKEN`.** Usporedba
     nad SHA-256 obje strane s `crypto.subtle.timingSafeEqual` (jednaka duljina, pa ni duljina
     tokena ne curi). Nema tokena (ili prazan) → 503 `ingest_disabled`; nedostaje, kriva
     shema ili krivi token → 401 `unauthorized`. Auth je prva provjera, prije tijela i baze.
     Testni token je miniflare binding u `vitest.config.ts`, nikad `.dev.vars`.
603. **`POST /ingest` je jedina ne-GET ruta**; ostale metode i dalje 404 (308). Tijelo
     `{source, channels: ChannelRow[], episodes: EpisodeRow[]}` (camelCase, točno ključevi
     sučelja iz `plan.ts`, svi obavezni, nullable kao `null`). Granice: najviše 1 MiB
     (`content-length` i stvarna duljina čitanja streama) → 413 `body_too_large`; najviše
     200 kanala i 500 epizoda → 400 `batch_too_large` s `detail` `channels`/`episodes`.
     `source` = `^[a-z][a-z0-9_-]{0,31}$` (`pipeline`, `drift-check`). Content-type mora biti
     `application/json` (parametri dopušteni) → inače 400 `bad_content_type`; nevaljan JSON
     ili UTF-8 → 400 `bad_json`. Svi odgovori `no-store`, nikad u Cache API; CORS/OPTIONS
     se ne dodaje (server-to-server).
604. **Validacija prema CHECK ograničenjima sheme, `detail` = putanja prvog lošeg polja**
     (`{"ok":false,"error":"bad_body","detail":"episodes[3].tier"}`). Tier 1|2, `flags`
     cijeli 0–511, `magisteriumScore` cijeli 0–100 ili `null`, datumi `YYYY-MM-DD` i stvaran
     dan, neprazni stringovi gdje shema traži `length > 0`, `lang` 2–16 znakova (broje se
     znakovi kao u SQLite, ne UTF-16 jedinice), `durationSeconds` konačan ≥ 0,
     `unregistered: true` samo uz tier 2, nepoznat ili nedostajući ključ je greška, tijelo
     koje nije objekt je `detail: "body"`. Duplikat sluga ili ID-a u batchu je loše polje
     (`episodes[1].id`): inače bi `changes` brojao isti redak dvaput. `detail` je opcionalno
     polje u `error.schema.json` i postoji samo uz greške ingesta.
605. **Upis ide istim kodom kao uvoznik**: `writeRows(db, brandId, channels, episodes, now)`
     izdvojen iz `applyPlan` (koji sad samo doda upsert brenda); `scripts/import.mjs`
     nepromijenjen. Ingest ne stvara brendove: brend dolazi iz `catalogContext` po hostu kao
     kod čitanja (404 `brand_not_found`). D1 u poolu provodi strani ključ (test), ali ga
     ingest provjerava PRIJE upisa jednim upitom (`existingChannelSlugs`, PK po slugu iz
     `json_each`): `writeRows` dijeli upis na batcheve od 200 naredbi, pa bi FK greška usred
     upisa ostavila ranije batcheve upisane. Nepoznat kanal → 409 `unknown_channel`,
     `detail` `episodes[i].channelSlug`, ništa upisano; FK greška iz D1 (utrka s brisanjem)
     je ista greška bez `detail`.
606. **0 promjena = bez nove verzije kataloga.** Ingest otvori `running` redak; s ≥ 1
     stvarnom promjenom ga u jednom `db.batch` zamijeni NOVIM `ok` retkom (`commitRun`, novi
     `id` je najveći u trenutku završetka, pa dva usporedna ingesta ne ostave verziju
     ispod upisa onog koji je završio drugi), `counts` = `{received, written}`. Bez
     promjena se `running` redak briše (`discardRun`): ponovljen batch ne diže verziju i ne
     poništava cache. Iznimka tijekom upisa → `failed` s porukom u `counts` i 500 `internal`.
     Odgovor 200: `{"ok":true,"changes":{"channels":n,"episodes":n},"catalog":"<id>"}`;
     `catalog` je nova verzija kad je promjena bilo, inače verzija pročitana na početku
     zahtjeva (`null` dok uspješnog uvoza nema).
607. **`GET /ingest/ids` za drift-check**: isti Bearer, `?after=<id>&limit=1..5000` (zadano
     5000) → `{"ids":[…],"next":"<zadnji id>"|null,"meta":{"rows_read":n}}`. Sve epizode
     brenda, i varijante, po `id` ASC; raspon po PK `(brand, id)` (`INDEXED BY`, plan
     `SEARCH episodes USING PRIMARY KEY (brand=? AND id>?)`), `LIMIT n+1` za `next`, bez
     OFFSET-a. `rows_read` ≤ limit + 1 + kontekst (≤ 3) na svakoj stranici, kako god duboko
     (test sa stranicom 37 nad 627 epizoda). `bad_limit` za sve izvan `^\d{1,4}$` i 1–5000,
     `bad_after` za prazan `after=`. `no-store`, bez Cache API, bez omotnice `version`/`catalog`.

Produkcija (korisnik odobrio 6. 11. 2026. na vratima S5 → S6: „Da, sve odobravam”, ruta na istom originu):

608. **Produkcija je na istom originu `domovina.ai/api/katalog/*`**, ne na poddomeni (507
     zatvoreno): Worker `domovina-katalog` s rutom na zoni, D1 `katalog`
     (`a841df13-…`, hint `eeur`), secret `INGEST_TOKEN`. Pages i dalje servira sve
     ostalo (provjereno: `/` i `/v/<id>` 200 `text/html`, `/api/katalog/v1/health` 200 JSON).
     Povratak: `wrangler delete` (miče i rutu) + `wrangler d1 delete katalog`.
609. **Brend se u praznu bazu upisuje ručno prije prvog ingesta** (`INSERT INTO brands
     VALUES ('domovina','domovina.ai')`): ingest razrješava brend po hostu i bez retka
     vraća `brand_not_found`. Novi brend (S14) isto, ili kroz uvoznik.
610. **Prvo punjenje produkcije je `drift-check --sync`**, ne export lokalnog D1 kao u S5:
     isti put kojim će ići svaki popravak. 162 kanala i 3670 epizoda u 8 poziva; zato je
     prva verzija kataloga `8` (svaki poziv s promjenama diže verziju).
611. **Izmjereno na produkciji iz HR (VIE), 50 zahtjeva po nizu**: hit p50 22–24 ms
     (S5: 51), miss 48–49 ms (S5: 84), `health` 19 ms, CDN `home.json` 18 ms.
     Reprodukcija: `npm run latency -- --base https://domovina.ai --out …`; sirovo u
     `research/2026-11-06-produkcija-latencija.json`. Token ingesta lokalno u
     `.dev.vars` (`INGEST_TOKEN=`), launchd ga čita odande.

## S7 (2026-11-06, pipeline producer, rađeno iz fetch.domovina.tv)

700. **Pipeline zove katalogov kod, ne slaže retke sam**: `scripts/ingest-episode.ts`
     (`npm run ingest-episode -- <id…> | --all`) gradi plan istim `buildImportPlan` putem
     kao uvoznik i `drift-check --sync`, pa šalje na `POST /ingest` sa `source: "pipeline"`.
     `run_pipeline.sh` (fetch.domovina.tv, KORAK 13.5) ga poziva iz `katalog/` s tokenom iz
     fetch `.env` (`INGEST_TOKEN`); fallback je `katalog/.dev.vars` kao u drift-checku.
701. **Puni plan i za jednu epizodu**: redak kanala nosi `processed_count` i
     `latest_published_date`, upsert ih prepisuje, a brojka Tier 2 kanala ovisi o svim
     Tier 2 epizodama (kanal svake zna tek resolver). Šalju se samo retci traženih epizoda
     i kanala na koje pokazuju, s brojkama iz punog plana (`selectRows`). Cijena: ~560
     GET-ova na CDN, 3,3 s suho; `--all` s upisom 6,5 s, 8 poziva, 0 promjena kad je poravnato.
702. **Prioritetni/reprocess run šalje svoj ID, ostali `--all`**: nightly tako usput
     prenese i promjene zastavica bez novog ID-a (Magisterium, EN stižu izvan
     `run_pipeline.sh`), koje drift-check (samo ID-evi) ne vidi.
703. **Exit kodovi `ingest-episode`**: 0 upisano; 1 neki traženi ID nije u planu (nema
     `article.json` u key cacheu ili listingu), ostali upisani; 2 ne mogu (token, mreža,
     4xx/5xx, plan). Pipeline nastavlja u svim slučajevima; propušteno popravi
     `drift-check --sync` u 08:45. Watchdog 5 min po pozivu, 60 s po HTTP zahtjevu.
704. **CDN `fresh` način** (`createCdn({ fresh: true })`): `channels/*` uvijek, a 404
     retry svugdje, s jedinstvenim busterom (`Date.now()`), jer se zove sekundama nakon
     uploada: edge zna držati listing od prije KORAKA 13, a 404 zapamćen pod 5-minutnim
     bucketom koji koristi i aplikacija. Uvoznik i drift-check ostaju na starom ponašanju.
705. **Mapa kanala za `episode.json`** (`--channels-out`, u fetch repou
     `.katalog_channels.json`, gitignored): `{v:1, generated_at, seeded_at, episodes:{id:
     {channel:{slug,name,tier}|null, first_seen}}}` za SVE epizode plana. `channel.tier`
     je tier kanala (Tier 2 epizoda na praćenom kanalu daje 1). Piše se atomarno i samo
     kad je ingest uspio; u dry-runu ne.
706. **`first_seen` drži pravilo „bez backfilla”** (fetch CLAUDE.md #4): pri prvom zapisu
     (06.11.2026. 11:42, 3670 epizoda) sve dobivaju `null`; epizoda koje nema u prethodnoj
     mapi dobiva vrijeme runa. `build_episode_bundle.js` piše `channel` samo za ne-`null`,
     a `channel` ulazi u otisak samo tada, pa se 3671 starih bundleova ne dira (suhi
     `--all`: 0 za provjeru). Backfill = posebna odluka.
707. **`episode.json` `channel` je aditivan, verzija ostaje 1**: `null` = katalog epizodu
     ima bez kanala, bez ključa = nepoznato. Provjereni čitači ignoriraju nepoznat ključ:
     `EpisodeBundle.tryParse` (podcast_core), `EpisodeBundleSchema` (vijesti, zod
     `z.object` odbacuje višak), `parseEpisodeManifest` (katalog), `isReady`
     (domovina-push).
708. **Redoslijed u `run_pipeline.sh`**: 12 … 12.68 → 13 (listinzi) → 13.5 (ingest + mapa)
     → 12.7 (bundle). 13.5 za Tier 1 treba listing iz 13, a bundle mapu iz 13.5; ni 13 ni
     13.5 ne pišu u `data/`, pa je bundle i dalje zadnji upload u `data/`. Bundle koji
     `upload_to_r2.js` napravi u KORAKU 12 (još bez kanala) 12.7 prepiše jer se otisak
     promijenio.
709. **Fast-path s Tier 1 ID-em** (prioritetni job na praćenom kanalu) nema KORAK 13, pa
     epizodu još nema u listingu: plan je vidi kao Tier 2 (`tier: 2`, kanal kroz resolver).
     Idući nightly `--all` je ispravi na Tier 1. Prihvaćeno: kartica i kanal su odmah
     točni, kriv je samo `tier` epizode do noći.

## S8 (2026-11-06, CatalogClient u podcast_core, ekran epizode)

800. **`Endpoints.catalog`** (`packages/podcast_core/lib/brand/brand_config.dart`), zadano
     prazno kao `events`; DOMOVINA `https://domovina.ai/api/katalog/v1`, Podcasterium ga ne
     postavlja (tvrdi uvjet 3). Sve što dolazi iz kataloga, i `episode.json` `channel`, ide
     kroz `CatalogClient.enabled`: bez endpointa nema zahtjeva ni čitanja `channel`, pa je
     ponašanje brenda bez kataloga isto kao prije S8.
801. **Ekran epizode prvo traži kanal starim putem, katalog tek kad on ne nađe ništa.**
     Redom: `index.json` po imenu (`channelIdForName`, kao do sada), pa `episode.json`
     `channel`, pa `GET /episodes/:id/card` (`catalogChannelFor` u
     `services/episode_catalog_lookup.dart`). Handoff je predlagao obrnuto (bundle →
     kartica → stari put). Promijenjeno iz tri razloga: Tier 1 je zbog toga identičan
     današnjem; 3670 starih epizoda bez ključa `channel`, kojima ime pogađa kanal, ne plaća
     zahtjev za karticu; a bundle je ionako već učitan (dijeljeni `_bundles` u
     `DataService`), pa za njega ne ide nijedan novi zahtjev. Cijena: kad ime pogodi krivi
     kanal, katalog to ne ispravi, kao ni do sada. `channel: null` u bundleu znači „katalog
     zna da kanala nema”, pa se kartica tada ne traži.
802. **Kanal bez `/c/` rute (`channel.tier != 1`, Tier 2 do S10) dobiva samo ime.**
     Breadcrumb ga pokazuje bez linka (`_Breadcrumb.showUnlinkedChannel`, odluku o čvoru
     donosi `episodeBreadcrumbChannel`). Slug ne ulazi u
     `_channelSupportRefs` ni u `_supportPath`; fallback ostaje `/c/kanal/support?uc=…`,
     isti kao danas. Tier 1 iz kataloga daje `_channelSlug` s crticom
     (`CatalogChannel.routeSlug`), kao i stari put. Kad S10 doda rutu, mijenja se samo
     `CatalogChannel.hasChannelRoute`.
803. **`_QueuedEpisodeScreen` prvo pita karticu** (`findQueuedEpisode`). Pogodak daje naslov
     (`title_hr ?? title`), datum i kanal, a embed je dopušten jer je ID potvrđen u našem
     katalogu. Slug Tier 1 iz kataloga je s crticom, slug iz listinga ostaje ID s podvlakom
     kao prije; ruter oba vodi na isti kanal. Tier 2 epizoda bez `info.json` (resolver
     `no_info_json`, podaci iz `summary.json`) sada dobiva YouTube embed, osim kad joj je
     ID sintetički (odluka 808).
804. **Katalog 404 uz dostupan katalog: i dalje `findVideoAsync`.** Kod S6/S7 pokazuje da
     Tier 1 retke plana slaže `buildPlan` iz SVIH redaka listinga
     (`katalog/src/ingest/plan.ts`), pa je listana epizoda u obradi u katalogu čim prođe
     ingest. D1 ipak smije kasniti za listingom: KORAK 13.5 s exitom 1 ili 2 ostavlja rupu
     do `drift-check --sync` u 08:45 (odluka 703). Taj pad ne košta ništa novo, jer je
     `findVideoAsync` do S8 išao uvijek. Kad katalog nije dostupan (endpoint prazan,
     mreža, timeout, 5xx, nečitljiv odgovor), ide se isto na `findVideoAsync`.
805. **`CatalogClient.lookup` ide kroz `CdnJsonCache.getMutable`, bucket `episode`** (kao
     `episode.json`: na webu najviše 150 zapisa, na nativeu 20 MB). Spremljena kartica
     vraća se odmah i revalidira u pozadini. Timeout je 4 s, a 404 i greške se ne spremaju.
     Da bi se 404 razlikovao od kvara, `getMutable` sada baca `CdnHttpException(statusCode,
     url)`; `toString` je isti kao prije (`Exception: HTTP <kod>: <url>`). Timeout ne
     prekida sam zahtjev: kasni odgovor se spremi za idući put.
806. **Šav za testove**: `CatalogClient.instance` je statičko polje koje se smije
     zamijeniti (obrazac `CdnJsonCache.instance`), npr. podklasom koja prepisuje `lookup`.
     Logika ekrana je u čistim funkcijama `findQueuedEpisode(id, findVideo:, catalog:)` i
     `catalogChannelFor(id, bundle:, catalog:)`. Testovi bez `AppBrand.init` rade s
     DOMOVINA brendom, dakle s uključenim katalogom. Widget test ekrana epizode zato treba
     postaviti `CatalogClient.instance = CatalogClient(baseUrl: '')` (staro ponašanje) ili
     lažni klijent, inače zahtjev ode kroz `package:http`.
807. **`EpisodeBundle.channelKnown`**: `true` samo kad ključ `channel` postoji i vrijednost
     je `null` ili ispravan `{slug,name,tier}`. Nečitljiva vrijednost se tretira kao da
     ključ izostaje (pita se kartica), a ostatak bundlea vrijedi i dalje. Verzija ostaje 1
     (odluka 707).
808. **Ekran u obradi ne ugrađuje sintetički ID** (pravilo iz korijenskog `CLAUDE.md`:
     X i `_yt_matched:false` nemaju YouTube video). Embed, bočni player i poveznica
     „Otvori na YouTubeu” idu samo uz `QueuedEpisodeListing.youtubeVideoId`; kad je
     `null`, ekran pokazuje naslov, kanal i status bez playera. Kartica ne nosi izvor
     epizode, pa `queuedYouTubeVideoIdForCard` hvata ono što ima: `variant_of` (embed
     osnovnog ID-a, kao `PodcastInfo.youtubeVideoId`), slug kanala `x-…` (neregistrirani X
     autor, `resolve.ts` `UNREGISTERED_PREFIX`) i oblik ID-a: bez 11 znakova base64url
     nema embeda, a 11 malih heks znakova je RSS (`sha1(guid)[:11]`, `ingest_rss.mjs`) ili
     beamly (zadnjih 11 znakova ObjectId-a, `ingest_beamly.mjs`); pravi YouTube ID takav je
     s vjerojatnošću oko 2·10⁻⁷. Listing (`queuedYouTubeVideoIdForListing`) nosi
     `youtube_url` = `info.webpage_url` (`generate_channel_index.js`), pa ne-YouTube host
     (x.com, launchedfm.com, Spotify) i `source` različit od `youtube` gase embed. Ovo
     vrijedi i za brend bez kataloga: za pravi YouTube ID ekran je isti kao prije S8, a
     za sintetički je do sada nudio embed i poveznicu koji vode na YouTubeovo
     „nedostupno”. Ostaje rupa: X ID (sha256 → 11 znakova) po obliku je
     isti kao YouTubeov, pa X epizoda na praćenom kanalu bez `info.json` dobiva embed.
     Praćenih X kanala danas nema, a X epizode imaju `info.json`. Potpuno rješenje je
     polje izvora u kartici (`source` ili `yt_matched`), promjena ugovora `card.schema.json`.
     Beamly epizoda s pravim YouTube ID-om (`_yt_matched: true`) u listingu ima
     `webpage_url` epizode na launchedfm.com (`buildInfoJson`) i gubi embed. To je svjesna cijena: radije bez playera nego tuđi video.

## S9 (2026-11-06, „Danas u korpusu” i /dani/:datum)

Kod: `3f910b2`. Flutter: `services/catalog_client.dart` (`day()`), `models/catalog_day.dart`,
`screens/home/catalog_day_rail.dart`, `screens/catalog_day/`. Worker: `injectDayTags` i
pomoćne funkcije u `web/_worker.js`.

900. **`CatalogClient.day()` ima tri ishoda, a prazan dan je uspjeh.** `CatalogDayFound`
     (i s praznom stranicom: katalog je odgovorio, pipeline radi noću), `CatalogDayBadDate`
     (datum nije strogo `YYYY-MM-DD` ili ne postoji, npr. `2026-02-30`, provjereno bez
     zahtjeva; isto za HTTP 400 `bad_date`) i `CatalogDayUnavailable` (nema endpointa,
     mreža, timeout 4 s, 5xx, nečitljiv odgovor). Nikad ne baca; svaki korak ide u `log()`.
901. **Stranice dana idu kroz `getMutable` u bucketu `episode`.** Svaki dan i kursor je svoj
     URL, pa treba bucket s ograničenim brojem zapisa (web 150). Revalidacija kroz `onUpdate`
     tjera rail da ponovno izabere dan, da jutarnji prazan „danas” iz cachea ne ostane
     zaglavljen. Nečitljiva stavka se preskače, ostatak stranice vrijedi; `limit` se stisne
     na 1–100.
902. **Rail gleda danas i najviše tri dana unatrag.** Izmjereno 6. 11. u 12:38:
     `days/2026-11-06` 0 epizoda, 05. 7, 04. 27 (`curl -s
     "https://domovina.ai/api/katalog/v1/days/<d>?limit=100" | jq '.items|length'`).
     Do četiri upita s `limit=12`, redom; prvi neprazan dan se pokazuje, naslov
     `homeRailCatalogToday` / `…Yesterday` / `…OnDate`. Prvi `CatalogDayUnavailable`
     prekida petlju (pokvaren katalog ne košta četiri timeouta); brend bez kataloga ne šalje
     ništa.
903. **Rail nema skeleton.** Pojavi se tek sa sadržajem, a stoji ispod „Upravo stiglo”, pa
     ništa iznad njega ne skače. Zadnji pokazani dan pamti se u statičkom memou vezanom za
     današnji datum, da remount naslovnice ne nacrta frame bez raila. „Prikaži sve” →
     `drillDown('/dani/<datum>')`; tap kartice ide istim `onVideoTap` kao ostali railovi.
904. **Ruta `/dani/:datum` postoji za svaki brend** (podijeljen link ne pada na naslovnicu);
     ekran sam pokazuje učitavanje, popis, prazno (gumb na prethodni dan), nevaljan datum i
     nedostupno (bez kataloga nudi „Početna”, inače „Pokušaj ponovno”). Ključ rute nosi samo
     datum. Prethodni/sljedeći dan kroz `goPeer`; sljedeći je onemogućen iza današnjeg
     lokalnog datuma. Pomak datuma preko konstruktora `DateTime`, ne `Duration` (DST).
905. **Paginacija je beskonačno listanje, gumb je rezerva** za popis koji ne puni ekran.
     Pad stranice ostavlja učitani popis i nudi ponovni pokušaj; isti ID se ne crta dvaput
     (spremljena stranica može biti starija). Tap → `drillDown('/v/<id>')`.
906. **Datumi kroz `intl` `DateFormat` po jeziku sučelja** (`yMMMMd` za ekran, `MMMMd` za
     rail), uz pad na „4. 11. 2026.” kad podataka za locale nema. Obrazac za TODO u
     `founder_booking.dart`, koji ovime nije riješen.
907. **Novi ARB ključevi:** `homeRailCatalogToday`, `homeRailCatalogYesterday`,
     `homeRailCatalogOnDate`, `catalogDayEyebrow`, `catalogDayPrevious`, `catalogDayNext`,
     `catalogDayEmptyTitle`, `catalogDayEmptyBody`, `catalogDayInvalidTitle`,
     `catalogDayInvalidBody`, `catalogDayUnavailableTitle`, `catalogDayUnavailableBody`,
     `catalogDayLoadMore`, `catalogDayLoadMoreFailed`. Novih analitičkih događaja nema, pa se
     pravni dokumenti ne mijenjaju.
910. **Worker katalog zove samo kroz service binding `KATALOG`, uz graceful fallback.**
     Cloudflare: „Routes cannot be the target of a same-zone fetch() call”, pa bi
     `fetch('https://domovina.ai/api/katalog/…')` iz Pages workera dobio SPA HTML. Bez
     bindinga, na grešci ili nakon 800 ms: isti statični tagovi (naslov s datumom, bez broja
     epizoda). Binding na Pages projektu je vanjska radnja i ide u S11.
911. **Brend ima katalog u workeru samo uz `CATALOG_API`;** zadana vrijednost
     (`https://domovina.ai/api/katalog/v1`) vrijedi samo bez `SITE` bindinga. Ostali defaulti
     su DOMOVINA-ini pa bi ih Podcasterium naslijedio; ovako mu ruta, AASA i sitemap ostaju
     bajt-identični dosadašnjima. Zrcali odluku 800.
912. **Nevaljan i budući datum: SPA s `no-store` i `X-Robots-Tag: noindex`** (zaglavlje, ne
     meta, da HTML ostane jednak SPA fallbacku). Granica „danas” u Europe/Zagreb. Dan s 0
     epizoda (kad katalog odgovori) također dobiva noindex.
913. **Cache HTML-a `/dani/`:** prošli dani `max-age=3600, s-maxage=86400`; danas i jučer
     `max-age=300, s-maxage=300` (razlika UTC/Zagreb i kasni ingest).
914. **Sitemap: zadnjih 30 dana, računato, bez subrequesta**, priority 0.4 (ispod epizoda),
     `changefreq` daily za zadnja dva dana, inače monthly. Prazne dane sitemap ne zna; stranica
     ih označi noindex.
915. **AASA `/dani/*` eksplicitno, iza auth exclusiona, samo uz `CATALOG_API`;** Android
     `pathPrefix="/dani/"`. Popis je ugovor s Android allowlistom; `test-social-tags.mjs`
     provjerava redoslijed. Matcher je strogo `^/dani/\d{4}-\d{2}-\d{2}$` (dogovor s lancem
     `vijesti/`: ništa ne smije hvatati `/vijesti`). `/dani/<d>/en` ne postoji ni u Flutteru
     ni u workeru.

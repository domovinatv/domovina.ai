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

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

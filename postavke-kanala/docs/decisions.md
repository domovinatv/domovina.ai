# Odluke — postavke kanala

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …).
Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-11, planiranje)

1. **Prekidači (20 ključeva, zadano `true`).** Ključevi su ugovor između svih potrošača i
   ne preimenuju se:

   | skupina | ključ | isključeno znači |
   |---|---|---|
   | glavni | `channel_enabled` | kanal povučen iz cijele domovina.ai; svi ostali se tretiraju kao isključeni |
   | prisutnost | `processing` | nove epizode se ne preuzimaju ni obrađuju |
   | prisutnost | `home_featured` | nema u heru, „Upravo stiglo”, railovima, „Danas u korpusu” |
   | prisutnost | `in_app_search` | nema u paleti pretrage (lokalno, Meili, semantika) |
   | prisutnost | `search_engines` | `noindex`, izostaje iz sitemapa |
   | prisutnost | `push_notifications` | nema push obavijesti za nove epizode |
   | medij | `cdn_playback` | nema reprodukcije s našeg CDN-a; samo službeni YouTube player |
   | medij | `share_clips` | nema isječaka po poglavlju, 9:16 rendera ni OG slika po trenutku |
   | medij | `ebook` | nema EPUB-a |
   | AI | `article_summary` | nema članka ni sažetka |
   | AI | `transcript_subtitles` | nema transkripta, titlova ni „Pronađi u epizodi” |
   | AI | `english_translation` | nema `/en` izdanja |
   | AI | `magisterium` | umjesto ocjene stoji „Vlasnik je isključio procjenu” |
   | AI | `highlights_reels` | nema istaknutih trenutaka |
   | AI | `persons_mentions` | epizode kanala ne ulaze u `/p/` profile i virtualne kanale |
   | AI | `news_portal` | epizode kanala ne koriste se za članke na portalu vijesti |
   | AI | `ai_assistants` | izostaje iz MCP-a i semantičkog korpusa |
   | novac | `donations` | nema zida podrške ni donacija |
   | novac | `paid_sponsor_moments` | nema izloga ni prodaje sponzorskih trenutaka |
   | novac | `sponsors_in_video` | nema sekcije „Uz podršku” |

   Razlog: inventura od 11. 11. 2026. (chat S0) nad funkcionalnostima opisanima u
   korijenskom `CLAUDE.md`. TV, Cast i analitika nisu prekidači (način isporuke, ne
   sadržaj). Revizija: nova funkcionalnost nad sadržajem kanala dobiva svoj ključ.
2. **Magisterium je prekidač** (odluka korisnika 11. 11. 2026.), ali se ne skriva tiho:
   na mjestu ocjene stoji „Vlasnik je isključio procjenu”.
3. **Pišu primarni vlasnik i suradnik** (odluka korisnika 11. 11. 2026.): `role in
   ('primary','collaborator')`, `status = 'verified'`, `verified_at` mlađi od 90 dana
   (pravilo D4 iz `docs/channel-ownership-and-safe-payout-plan.md`). Isto vrijedi za
   zahtjev za brisanje i njegovo otkazivanje.
4. **Kronološki log svake promjene** (zahtjev korisnika): `channel_settings_events`
   append-only (ključ, stara i nova vrijednost, račun, uloga, vrijeme, izvor `app` /
   `phone` / `system`). Vlasnik i suradnici kanala ga vide na ekranu, od najnovijeg.
5. **Trajno brisanje = potvrda u aplikaciji + telefonski poziv na +385 98 967 9022**
   (zahtjev korisnika). Tek nakon poziva operater (service_role) potvrđuje zahtjev, a
   skripta brisanja `channel-delete.sh` (nastaje u S9) briše R2 (uz purge obje `Vary: Origin` varijante), Meili,
   RAG, vijesti, push teme i katalog. Vlasnik može otkazati zahtjev dok poziv nije
   potvrđen. Nema dodatnog vremenskog odmaka: poziv je potvrda. Broj je javan (repo i
   aplikacija su javni).
6. **Tombstone u katalogu je trajan** (zahtjev korisnika): UC id, ime kanala, slugovi,
   vrijeme zahtjeva, vrijeme potvrde poziva, vrijeme brisanja. Ne briše se nikad; pipeline
   ga čita kao blokadu.
7. **Ključ postavki je UC id**, ne slug: slugovi iz playlista dijele isti UC
   (`katalog/migrations/0001_init.sql`), pa postavka vrijedi za sve. Kanali bez UC id-a
   nemaju vlasnika na ovoj platformi dok S1 ne izmjeri koliko ih je.
8. **Isključen AI prekidač u v1 sakriva postojeće i ne generira nove artefakte**; postojeće
   datoteke ostaju na R2 do trajnog brisanja kanala. Revizija: ako vlasnik zatraži brisanje
   jednog artefakta, uvodi se brisanje po ključu.
9. **Lanac živi u `postavke-kanala/`**, a kod u postojećim mjestima: `packages/podcast_core/`,
   `katalog/`, `web/_worker.js`, i u repoima `domovina-api`, `fetch.domovina.tv`,
   `domovina-rag`, `domovina-push`. Rad u drugom repou ide iz sesije u tom repou.
10. **Paralelni lanci** `katalog/` i `vijesti/`: ovaj lanac im ne mijenja dokumente; izmjene
    koda u `katalog/` idu samo kad katalog nema necommitanih izmjena, a migracija uzima
    prvi slobodan broj.

## S1 (2026-11-11, mjerenje)

100. **Ključ po UC-u ostaje** (potvrda odluke 7). Mjereno 11. 11.: 182 od 186 kanala u
     katalogu ima UC, 180 različitih; jedan UC (`UCuk9D5H9mx7birJ1-S22nyQ`) nosi tri sluga.
     Postavka po UC-u ih pokriva jednim retkom. Naredba:
     [research/2026-11-11-uc-pokrivenost-i-claim.md](research/2026-11-11-uc-pokrivenost-i-claim.md) §1.
101. **`launched` i `subclub` dobivaju UC iz registryja** (S3): registry ima
     `youtube.channel_id`, a katalog ga ne prenosi jer su epizode audio-direct bez YouTube
     `channel_id`. S3 u ingest kataloga dodaje pad na registry kad epizode UC nemaju.
     Revizija: ako se pokaže da je taj UC tuđi (playlista na kanalu treće strane), kanal
     ide u skupinu iz odluke 102.
102. **Kanal bez YouTube izvora nema postavke u v1** (`dijalog` RSS, `x-…` X izvor; 2 od
     186). Vlasnik koji se javi telefonom dobiva povlačenje kroz registry
     (`tracking.enabled=false`) i, ako traži, brisanje skriptom iz S9 po slugu. Revizija:
     kad takvih kanala s vlasnikom bude više od jednog, uvodi se drugi tip vlasništva
     (RSS `itunes:owner` e-pošta).
103. **Vrata prije S2: u produkciji nema nijednog vlasnika.** `youtube-claim` je deployan
     i env postavljen, ali `channel_claims` ima 0 `verified` redaka (5 sintetičkih iz
     probe 14. 10.). Ekran postavki bez vlasnika nema korisnika (plan, „Najrizičnije”).
     Korisnik bira: dovršiti Google verifikaciju `youtube.readonly` i prvi stvarni claim
     prije S2, ili graditi paralelno. Pitanje je na vrhu `S2.md`.
104. **S1 ne čisti sintetičke claimove u produkciji.** 5 testnih redaka iz 14. 10. ostaje;
     brisanje je vanjska radnja (vrata) i nije u opsegu lanca. S2 ih u testovima ne
     smije brojati kao vlasnike (svi su `revoked`/`pending`).
105. **Aplikacija stanje čita iz novog `GET /v1/settings` kataloga** (S3), a ne samo uz
     kanal. Naslovnica, popis kanala i lokalna pretraga danas dolaze iz CDN datoteka koje
     piše pipeline (KORAK 13: `index.json`, listinzi, `home.json`, `search.json`), ne iz
     kataloga. S5 filtrira u `ChannelCache`/`HomeFeed`/`mergeSearchResults` po tom odgovoru,
     a S7 iste kanale izbacuje i u KORAKU 13 kao drugu liniju.
     [research/2026-11-11-matrica-provedbe.md](research/2026-11-11-matrica-provedbe.md) Zaključak 1.
106. **Poller domovina-api → D1 je nov posao S3** (Cron Trigger, kursor `updated_at`):
     katalog danas nema `triggers`. Zastoj = period crona + do ~11 min ruba
     (`max-age=60, stale-while-revalidate=600`); S3 ga mjeri.
107. **„Isključeno” za postojeće epizode provode čitači** (aplikacija, worker, MCP/`/api/search`),
     ne regeneracija indeksa: RAG i Meili se sinkaju jednom dnevno u 04:00, pa bi bez toga
     sakrivanje kasnilo do 24 h. Indeksi se poravnaju u svom ciklusu.
108. **Ovisni AI ključevi padaju s ulazom** (pretpostavka, revizija po korisniku na vratima
     S2): `article_summary` off → `ebook`, `magisterium`, `english_translation`,
     `share_clips`, `news_portal` se tretiraju kao off; `transcript_subtitles` off → svi AI
     ključevi off. Ekran postavki (S4) ovisne prekidače crta sive s objašnjenjem. Medij i
     transkript se za obradu smiju preuzeti samo kad se nešto od njih objavljuje.
109. **Novac se provodi u domovina-api SQL-u** (S2): `donations` i `paid_sponsor_moments`
     provjeravaju `pinka-contribute`/`create_contribution`/`create_sponsor_contribution` i
     pogled `public_live_moments`, u istoj bazi i bez kašnjenja. Već prodan živ trenutak
     traje do isteka slota (pretpostavka; revizija na vratima S2).
110. **Nepredviđeni potrošači dobivaju sesiju**: `domovina-cutter` i namjena
     `purpose=search|assistant|news` na `/api/search` → S8; `og:video` i Cast receiver → S6;
     KORAK 13, Vertex import (KORAK 11), `share_to_whatsapp.js` i glasački bazen → S7; TV
     ekrani, `/yt/:videoId`, Cast pošiljatelj, vlasnikov ekran kampanja → S4/S5.
111. **Trajno brisanje kreće od lokalnih izvora** (S9): lokalni RAG i lokalni Meili na Mac
     miniju pune cloud u 04:00, pa se brišu prvi, uz zaustavljen `sync-cron.sh`. Ne brišu se
     financijski zapisi pinke, `episode_safes`/`safe_actions`, log postavki, zahtjev za
     brisanje, tombstone i `person_optouts`; registry i `vote_candidates` se označavaju,
     ne uklanjaju. R2 se briše listanjem prefiksa (`episode.json` ne navodi screenshotove ni
     OG slike). Mjerenje na `ikra_institut`: 1 385 R2 objekata, 2 776 purge unosa.
     [research/2026-11-11-popis-brisanja.md](research/2026-11-11-popis-brisanja.md).

## S2 (2026-11-11, domovina-api)

200. **Pretpostavke 108 i 109 potvrđene** (korisnik, 11. 11. 2026., vrata S2): ovisni AI
     ključevi padaju s ulazom; prodan živ sponzorski trenutak traje do isteka slota.
     Efektivno stanje računa jedna SQL funkcija (`domovina_ai.channel_effective_settings`),
     a S3/S4/S5/S7 je čitaju ili preslikavaju, ne preračunavaju.
201. **KYC se za postavke ne traži.** Odluka 3 navodi ulogu, status i 90 dana. Vlasništvo se
     čita iz baze (`channel_claims`), ne iz JWT-a. KYC ostaje uvjet samo za isplate
     (`safe-owner-add`). Trajno brisanje ionako potvrđuje telefonski poziv.
202. **Slug → UC živi u `domovina_ai.channel_slugs`.** Pinka kampanje kanal nose po slugu
     (`subject_type='podcast_channel'`, `subject_ref=slug`), a postavke po UC-u (odluka 7).
     Migracija sije `domovina_tv`; S3 tablicu puni iz kataloga. Nepoznat slug = sve uključeno.
203. **`settings` je rijedak jsonb**: samo ključevi koje je vlasnik postavio, nedostaje =
     `true`. Postavljanje iste vrijednosti ne stvara događaj u logu.
204. **Jedan log za postavke i brisanje** (`channel_settings_events.kind`: `setting`,
     `deletion_requested`, `deletion_cancelled`, `deletion_phone_confirmed`,
     `deletion_executed`): vlasnik na ekranu vidi jednu kronologiju.
205. **Čitanje loga traži potvrđen claim bilo koje starosti; pisanje traži i < 90 dana.**
     Vlasnik kojem je claim istekao vidi što se mijenjalo i obnavlja claim.
206. **`paid_sponsor_moments=false` gasi izlog i nove kupnje, ne `public_live_moments`.**
     Plaćen, a još nenamiren hold koji se namiri nakon isključivanja također traje do isteka.
     Kupnja je započela prije isključivanja.
207. **Tombstone piše `mark_channel_deletion_executed` (samo `service_role`)**, koju na kraju
     poziva skripta iz S9; tombstone i log odbijaju UPDATE/DELETE za sve uloge.
208. **Odstupanja izvedbe od ugovora, prihvaćena** (S2, migracija `20261111120000` u
     domovina-api, commit `7d01d49`):
     - Kampanja → kanal ide jednom funkcijom `pinka_finance.campaign_channel_uc`:
       `podcast_channel` preko `channel_slugs` (pa slug iz tombstonea), `podcast_episode`
       preko `episode_safes`, a za oboje je pad na `campaigns.youtube_channel_id`. Kad
       ništa ne pogodi, uplata je dopuštena.
     - Kampanja s timeline mapom (sponzorski crowdfund) kroz `create_contribution` čita
       `paid_sponsor_moments`, a ostale čitaju `donations`. Provjera prekidača je prva
       linija, prije `not_authenticated`.
     - `record_sepa_contribution` i `record_onchain_contribution` se ne blokiraju, jer
       bilježe novac koji je već stigao.
     - Dodatni kodovi grešaka: `invalid_value`, `invalid_state: <stanje>`,
       `invalid_transition`.
     - `is_channel_settings_writer/reader(uc, uuid)` su izvršive za authenticated, jer ih
       RLS policy zove. Prijavljen korisnik zato može pitati je li neki tuđi uuid vlasnik
       kanala. Prihvaćeno: vlasništvo kanala nije tajna, a uuid tuđeg računa se ne vidi
       nigdje u sučelju.
     - Log nema FK na `auth.users`, kako brisanje računa ne bi kaskadiralo u append-only
       log.
     - Popravljeno prije commita: `campaign_channel_uc` i `campaign_channel_setting_enabled`
       moraju imati EXECUTE za anon/authenticated, jer ih javni pogledi zovu. Bez toga
       izlog i „Sponzorirano” padaju svima. Uhvatio ga je S2 test.

## S3 (2026-11-11, katalog)

300. **Produkcijska migracija S2 primijenjena pojedinačno, ne kroz `db-migrate.sh`**
     (korisnik odobrio 11. 11.). Skripta bi povukla i dvije namjerno zadržane migracije od
     3. 9. (`events_publish_rail_gate`, `events_rotate_ticket_tokens`; vidi
     `domovina-api/docs/sponzorski-trenuci-zakljucak.md`). Primijenjeno kao 8. 10.: `begin;
     <fajl>; insert u schema_migrations; commit`. Prije toga puni backup
     `domovina-api/backups/20261111-191542-public_domovina_ai_pinka_finance-full.sql`, a
     produkcijski `create_contribution`/`create_sponsor_contribution` uspoređen sa S2
     verzijom (razlika = samo nove provjere prekidača). Zamka: `detect_db_container` u
     `scripts/lib/db-env.sh` zove ssh koji pojede stdin, pa `db-psql.sh --stdin` vraća prazno;
     upit kroz stdin traži `detect_db_container </dev/null`.
301. **D1 tablice** (`katalog/migrations/0005_channel_settings.sql`): `channel_settings`
     (UC → `effective` JSON, preslikan, ne preračunat), `channel_tombstones` (triggeri odbijaju
     UPDATE/DELETE), `settings_poll_state`, indeks `channels_by_uc`. Nije po brendu.
302. **Poller na Cron Triggeru svake minute**; staging bez crona (nema ključa). Ključ je
     secret `SETTINGS_ANON_KEY`, URL var `SETTINGS_API_URL`; bez ključa poller bilježi
     `disabled` i ne zove mrežu.
303. **Kursor (`updated_at`, UC) uz 5 minuta preklapanja.** `updated_at` u izvoru je početak
     transakcije, pa kasni commit bez preklapanja nikad ne bi bio pročitan; ponovni upis je
     idempotentan. Kursor nikad ne ide unatrag.
304. **Jedan loš redak odbija cijeli odgovor** (`invalid_response`), ništa se ne piše.
     Kodovi u `settings_poll_state.status`: `ok`, `http_N`, `network`, `invalid_response`,
     `d1_error`, `internal`, `disabled`. Poller ne baca.
305. **Verzija kataloga se podiže samo kad se promijeni izlaz API-ja** (efektivno stanje ili
     novi tombstone): novi `ingest_runs` redak mijenja `_cv` u ključu rubnog cachea, pa purge
     ne treba.
306. **Brisanje retka u izvoru se ne preslikava** (domovina-api nema DELETE put); drift-check
     bi ga javio kao `extra`.
307. **Filtar u SQL-u**: `LEFT JOIN` postavki i tombstonea po UC-u; nedostajući redak ili
     ključ = uključen. Kanal bez postavki ne troši dodatni `rows_read`; plan bez SCAN-a.
308. **`home_featured=false` djeluje samo na `/days/:date`** (hrani „Danas u korpusu” i
     `/dani/`). `/channels`, `/directory` i stranica kanala ga zadržavaju: `/directory` je
     popis kanala, ne rail. Naslovnica (`home.json`) nije u katalogu; filtrira je S5 po
     `/v1/settings`.
309. **Povučen i obrisan kanal vraćaju 200 sa `state`, nikad 404.** `item` uvijek prolazi
     shemu kanala, pa stari build prikaže prazan kanal umjesto „katalog nije dostupan”.
     Obrisan: `item` je samo identitet (ime iz tombstonea, bez avatara, 0 epizoda) + `deleted_at`.
     `/channels/:slug/episodes` za oba vraća prazne `items` i `state`.
310. **Tombstone ima prednost pred postavkama**; bez retka kanala slug se traži u
     `tombstone.slugs` (sken samo na putu „nije nađen”).
311. **Kartica**: `status` samo kad nije `active`; `magisterium_off: true` +
     `magisterium_score: null` kad je `magisterium` isključen (i kad je kanal povučen ili
     obrisan, jer master gasi sve).
312. **`GET /v1/settings`**: `{UC: {status, off:[sortirano], deleted_at?}}`, samo UC s
     barem jednim isključenim poznatim ključem ili tombstoneom; obrisan kanal ima svih 20 u
     `off`. Nije po brendu; cache kao popisi.
313. **UC iz registryja samo kad ga listing, `index.json` i epizode nemaju**, i samo valjan
     `UC…` (odluka 101). Izvještaj plana dobiva `ucFromRegistry`.
314. **`channel-slugs-sync` samo umeće i mijenja, nikad ne briše** (kampanja na starom slugu
     mora naći kanal). Dry-run anon ključem, `--commit` service ključem iz
     `domovina-api/.coolify-current.env`; ne-lokalna baza traži i `--confirm-production`.
     Dry-run nad produkcijom 11. 11.: 186 kanala, 184 s UC-om (2 iz registryja), 183 nova.
315. **Drift postavki je samo izvještaj** (popravlja poller); exit 0/1/2 kao i dosad, a kod
     spajanja dijelova 2 > 1 > 0. Obrisan kanal se uspoređuje po statusu i `deleted_at` kao
     trenutku, ne po `off`.
316. **Zastoj promjene vlasnika do aplikacije**: lokalno izvor → D1 medijan 39,7 ms (p90
     42,6 ms; `cd katalog && npm run settings-latency -- --reps 20` nad lokalnim
     domovina-api). Produkcija: do 60 s čekanja na cron + poziv + do 30 s memorije
     konteksta u izolatu (`CONTEXT_TTL_MS`) + rub (`max-age=60`, do 600 s
     `stale-while-revalidate` na popisima). Produkcijski zastoj nije izmjeren (nema
     verificiranog vlasnika koji bi mijenjao postavke); mjeri ga S4 prvim stvarnim
     prekidačem.

## S4 (2026-11-12, aplikacija: ekran postavki)

400. **Ekran postavki čita `domovina_ai.public_channel_settings` (sirovo + efektivno), ne
     katalog.** Katalog kasni do ~1,5 min i nosi samo efektivni `off`, a prekidač mora
     pokazati što je vlasnik postavio. `ChannelSettingsCatalog.fetch/parse`
     (`lib/services/channel_settings_service.dart`) postoji za S5; ne baca, `null` =
     nedostupno.
401. **Prekidač prikazuje sirovu vrijednost**, a siv je kad je sirovo `true` i efektivno
     `false`. Efektivno stanje uvijek dolazi iz viewa ili odgovora RPC-a (odluka 200).
     Klijentska mapa roditelja služi samo za tekst: prvi roditelj sa sirovim `false` redom
     `channel_enabled` → `transcript_subtitles` → `article_summary`, preko lanca; inače
     generičan tekst.
402. **Optimistično pisanje**: red „Sprema se…” ostaje dok se log ponovno ne učita (bez
     treptaja). Na grešku se vraća samo taj ključ, a istovremene promjene drugih ključeva ostaju.
403. **Log se učitava po 50 redova**, a „Učitaj starije” ide preko `p_before`. Imena računa
     RPC ne vraća, pa „tko” znači ulogu, uz „(ti)” kad je `account_id` trenutni korisnik.
404. **Samo za čitanje**: claim stariji od 90 dana (uz radnju ponovne potvrde kroz
     `/account/channels/:uc`), kanal s tombstoneom i uloga koja nije primary/collaborator.
     Nepotvrđen claim dobiva samo poruku, jer ni log ne smije čitati.
405. **Claim bez `channel_title` nema obrazac za brisanje**, samo telefon, jer bi backend vratio
     `confirm_name_mismatch`. Brisanje i otkazivanje nemaju dodatni dijalog: upis točnog
     imena je potvrda, a poziv je drugi korak.
406. **Kodovi grešaka**: prepoznaju se poznati prefiksi (8 iz S2 + `invalid_state`,
     `invalid_transition`), sve ostalo je `unknown`, a iznimka koja nije Postgrest je
     `network`.
407. **Telefon je na dva mjesta**: konstante `kChannelDeletionPhoneDisplay/Uri` i doslovno u
     3 HR + 3 EN ARB stringa. Promjena broja mijenja oba mjesta.
408. **Traka „donacije isključene” na ekranu kampanja čita efektivni `donations`**, pa se
     prikazuje i za povučen ili obrisan kanal. Backend uplate ionako odbija (odluka 109).
     Testirana je samo traka, jer ekran kampanja ovisi o Supabase singletonima.
409. **`channel-slugs-sync --commit --confirm-production` izvršen 12. 11.** (korisnik
     odobrio): upisano 183 sluga, nakon upisa razlika 0 (184 slug → UC; bez UC-a ostaju
     `dijalog` i `x-1973380383166050304`, odluka 102). `launched`/`subclub` su UC već imali iz
     ingesta (iz registryja 0). Naredba: `cd katalog && npm run channel-slugs-sync` (dry-run).
410. **Produkcijski zastoj (odluka 316) i dalje nije izmjeren**: ekran je na produkciji, a
     mjerenje traži da vlasnik `domovina_tv` (korisnik) prebaci jedan prekidač. Izmjeri se na
     vrhu S5: vrijeme RPC-a → `curl -s https://domovina.ai/api/katalog/v1/settings` pokazuje
     promjenu, pa prekidač vratiti.
411. **Tekstovi novog ekrana su na „ti”**, a postojeći `ownership*` stringovi na susjednim
     ekranima još su na „Vi” („Niste…”). Nije dirano. Usklađivanje je zaseban posao, izvan lanca.

## S5 (2026-11-12, aplikacija: provedba na ekranima)

500. **Jedan izvor u aplikaciji je `ChannelVisibility.instance`**
     (`lib/services/channel_visibility.dart`): katalog `GET /v1/settings` jednom po sesiji,
     osvježen najviše svakih 5 min, bez zahtjeva po prekidaču. Fail-open: kanal bez UC-a,
     kanal izvan mape, nepoznat ključ i nedostupan katalog znače sve uključeno; neuspjelo
     osvježavanje zadrži zadnju poznatu mapu. Ekran epizode i kanala čeka učitavanje
     najviše 1,5 s (`ready()`), pa nastavlja s onim što ima. Povučen ili obrisan kanal
     gasi svaki ključ, i kad `off` ne bi bio potpun. AI ključevi se provode na mjestu
     dohvata (matrica §B), pa tri stabla playera i TV dobivaju isto bez prop drillinga.
501. **Reprodukcija u tijeku se ne prekida** (matrica §C 5). Provjera je pri otvaranju
     ekrana i pri učitavanju epizode. Katalog ionako kasni do ~1,5 min, pa prekid usred
     sesije ne bi bio ni točan ni predvidljiv.
502. **Korisnikovi popisi** (§C 6): uz `channel_enabled` isključen kartice kanala nestaju
     iz svih popisa i railova, uključujući „Nastavi slušati”, favorite i „Pratim”.
     Spremljeni podaci se ne brišu, pa se kanal vrati kad ga vlasnik uključi. Izravan
     `/v/<id>` prikazuje povučen sadržaj. Uz `home_featured` isključen korisnikovi popisi
     ostaju, jer ih je korisnik sam napravio.
503. **`/v/<id>/en` uz `english_translation` isključen se zamjenjuje HR rutom** (§C 7),
     umjesto da prikazuje hrvatski sadržaj na engleskom URL-u. Canonical i `hreflang` u
     workeru rješava S6.
504. **Magisterium na karticama nema ni ocjenu ni značku** (§C 8). Tekst „Vlasnik je
     isključio procjenu” stoji samo na epizodi (panel, tab, TV čitač), jer na kartici od
     ~180 px ne stane, a tooltip ne radi na dodir. U sortiranju po ocjeni kanal se
     ponaša kao da ocjene nema.
505. **`PeopleRail` uz `persons_mentions` isključen** (§C 9): imena ostaju kao tekst, bez
     poveznice na `/p/`. Imena su dio članka (`article_summary`), a ključ gasi profil i
     nastupe, ne tekst članka.
506. **Dva sloja provedbe.** Popisi i rute: `ChannelCache` (filtar u `index`,
     `orderedChannels`, `allVideos`, `feedVideos`), `HomeFeed.onlyHomeAllowed`,
     `mergeSearchResults(allow:)`, `PersonHub.whereEpisodes`, `ChannelFeatureOffGuard` na
     `/c/:slug/doniraj|support`, `/c/:slug/oglasi`, `/v/:id/sponzoriraj`. Epizoda:
     `DataService.loadInfo` upiše UC epizode u `ChannelFeatureGate`, a svaki dohvat
     (članak, titl, `*.en.*`, Magisterium, reels, sponzori, `resolveMedia`, `EbookService.probe`,
     `SponsoredMomentsService.loadLive`) ga pita prije zahtjeva. `EpisodeData` nosi snimku
     stanja iz trenutka učitavanja. Stare epizode bez `episode.json` zato imaju jedan
     dodatni povratni put prije AI datoteka.
507. **Obrisan kanal nema gumb za YouTube**, povučen ga ima. Vlasnik je tražio trajno
     uklanjanje, a povlačenje je samo odluka o domovina.ai. `findVideo`/`findVideoAsync`
     i dalje nalaze epizode povučenog kanala, da `/v/` može prikazati povučen prikaz.
508. **`/m/` uz `magisterium` isključen nema tab „Magisterium”**; tekst stoji u tabu Info.
     `diarized.en.srt` se računa kao `english_translation` i za kanale na engleskom (ondje
     je to izvorni titl), jer klijent ne zna jezik izvora; ako to zasmeta, pipeline (S7)
     treba označiti izvorni jezik. Isječci ovise samo o `share_clips`; ovisnost o
     `cdn_playback` računa katalog.
509. **Ikona preuzimanja vlasništva ostaje na povučenom `/c/`**, da vlasnik dođe natrag
     do postavki i uključi kanal.

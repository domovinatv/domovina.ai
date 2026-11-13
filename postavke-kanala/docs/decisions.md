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
510. **Produkcijski zastoj izmjeren 12. 11. (dopuna odluke 316).** Vlasnik `domovina_tv`
     isključio je `ebook`: događaj u logu `13:13:59.13 UTC`
     (`domovina-api: ./scripts/db-psql.sh -c "'select * from domovina_ai.channel_settings_events order by 1 desc limit 3'"`),
     a `curl -s https://domovina.ai/api/katalog/v1/settings` ga je prvi put pokazao u
     `13:15:05 UTC` (provjera svake 3 s), dakle **≤ 66 s** do ruba. Preglednik je zatim u
     13:15:55 i dalje dobio prazan odgovor iz svog HTTP cachea (`max-age=60,
     stale-while-revalidate=600`), pa je e-knjiga ostala ponuđena; nakon svježeg dohvata u
     13:16:51 nestala je (živa provjera S5 na `/v/QkcpHsj43rE`). Popravak (v2.0.234):
     klijent traži `/settings?t=<minuta>`; katalog nepoznate parametre izbacuje iz ključa
     rubnog cachea, pa rub i dalje dijeli jedan zapis. Ukupno: do ~2 min od prekidača do
     nove sesije aplikacije; otvorena sesija vidi promjenu najkasnije za 5 min
     (`ChannelVisibility.maxAge`) ili pri ponovnom učitavanju.

511. **Ekran postavki na desktopu u stupcima (v2.0.235, na zahtjev vlasnika).** Ispod 960 px
     jedan stupac do 720 px (mobitel nepromijenjen). 960–1279: prisutnost + reprodukcija +
     novac | AI. Od 1280 (sadržaj do 1560 px): prisutnost + trajno brisanje | AI (8, najviši
     stupac) | reprodukcija + novac; glavni prekidač na vrhu (do 720 px), dnevnik ispod
     svega. Provjereno u Braveu 1568×762: svih 20 prekidača, brisanje i dnevnik na ekranu
     bez scrolla. Test (`channel_settings_screen_test.dart`) čuva samo broj stupaca po
     širini — testni font Ahem je širi od Intera, pa „stane bez scrolla” u testu ne vrijedi
     (na 1440×900 prijavljuje prelijevanje kojeg u pregledniku nema).

## S6 (2026-11-12, worker: OG, noindex, sitemap, Cast)

600. **Worker čita stanje iz kataloga `GET /settings`, ne iz `/channels/:slug` po zahtjevu.**
     Jedan poziv kroz binding `KATALOG` (`fetchChannelSettings` u `web/_worker.js`) daje stanje
     za `/v/`, `/m/`, `/c/` i sitemap; epizoda kanal zna iz `info.json` `channel_id`, Tier 1
     kanal iz `youtube_channel_url` u listingu i `index.json`. Memorija izolata 60 s, po
     `CATALOG_API` i bindingu; na grešci ostaje zadnja poznata mapa. Fail-open kao aplikacija
     (odluka 500): bez kataloga povučen kanal izgleda kao prije, uključujući sitemap.
     Tier 2 i kanal kojem je S9 obrisao listing čitaju `state`/`deleted_at` iz
     `/channels/:slug` (odluka 309); taj poziv ide paralelno s `/settings`, da se dva
     timeouta kataloga (800 ms) ne zbroje.
601. **Povučen i obrisan kanal imaju jedan OG** (`injectGoneTags`) na `/c/<slug>` i svim
     podrutama (`/doniraj`, `/support`, `/oglasi`) te na svim varijantama `/v/` i `/m/`
     (`/t/<sec>`, `/en`, `/hr`, `/sponzoriraj`): naslov i opis prema ARB `channelGone*`
     (ime brenda umjesto „domovina.ai”, `/en` na engleskom), `og-image.png`, JSON-LD `WebPage`
     umjesto `VideoObject`/`PodcastSeries`, bez hreflanga i bez ijednog podatka epizode
     (naslov, opis, thumbnail, og:video). Ime kanala ostaje (identitet, ne sadržaj). Povučen
     ima `relatedLink` na YouTube (video za `/v/`, kanal za `/c/`), obrisan nema (odluka 507).
     Datum je zagrebački `dd. mm. gggg.`. `X-Robots-Tag: noindex` i `<meta name="robots">`.
602. **Povučen/obrisan OG se cachira 5 min, ostali 1 h kao prije.** Povratak kanala tako je na
     rubu vidljiv za ~5 min; povlačenje kasni do 1 h (matrica §3), osim uz purge obje
     `Vary: Origin` varijante.
603. **Ključevi na aktivnom kanalu:** `search_engines` → `noindex` na `/v/`, `/m/`, `/c/` (i
     Tier 2) i izvan sitemapa zajedno s epizodama; `cdn_playback` → bez `og:video*` i JSON-LD
     `contentUrl`; `share_clips` → bez `og-t-<sec>` slike (pada na `og-share.jpg`);
     `article_summary` → opis iz `info.json`, bez AI sekcije u `/t/` (poglavlja s YouTubea
     ostaju); `english_translation` → `/en` dobiva HR OG, canonical na HR i bez hreflanga
     (odluka 503; nije 301, jer bi preglednik trajno pamtio preusmjerenje i nakon uključivanja).
604. **`donations`/`paid_sponsor_moments` isključeni:** `/c/<slug>/doniraj|support|oglasi`
     dobivaju OG kanala uz `noindex`, `/v/<id>/sponzoriraj` plain SPA uz `noindex` — aplikacija
     ondje prikazuje „isključeno” (`ChannelFeatureOffGuard`), pa OG ne smije nuditi donaciju
     ni kupnju.
605. **Cast receiver ima vrata u zasebnoj skripti** (`web/cast-receiver-gate.js`, učitava je
     `cast-receiver.html`): prije svakog LOAD-a `info.json` epizode + `/api/katalog/v1/settings?t=<minuta>`;
     povučen/obrisan kanal i `cdn_playback` off → `LOAD_FAILED` (`CONTENT_FILTERED`).
     Fail-open: bez ID-a, na mrežnoj grešci ili nakon 2,5 s reprodukcija ide. Odvojena
     skripta je zbog Node testa bez CAF-a. Na pravom televizoru nije isprobano.
606. **Testovi:** `node scripts/test-worker-postavke-kanala.mjs` (lažni katalog i CDN, bez mreže,
     134 provjere; mutacija `isOff → false` ruši 19) i `scripts/test-social-tags.mjs`
     `testChannelSettingsLive` (čita živi `/settings`, za najviše 4 skrivena kanala provjerava
     `noindex`, OG i sitemap). Na dan S6 u produkciji nema nijednog isključenog ključa, pa živi
     dio provjerava samo kontrolu (kanal bez postavki je indeksiran) i serviranje gate skripte.
     `test-worker-katalog-kanal.mjs` sada broji pozive kartice odvojeno od `/settings`.
607. **Otvoreno (nije paket S6):** `/v/<id>` obrisanog kanala nakon S9 (kad `info.json` više
     nema) worker ne prepoznaje, pa daje plain SPA (`no-store`), ne OG s datumom brisanja; za
     to treba `GET /episodes/:id/card` sa stanjem kanala ili popis ID-eva u tombstoneu → S9.
     `/p/<slug>` JSON-LD i dalje može nabrajati epizode kanala s `search_engines` ili
     `persons_mentions` isključenim (matrica §5): `domovina-rag` nastupe ne veže uz UC → S8.
     `/dani/` OG već filtrira katalog (S3).

## S7 (2026-11-12, pipeline u `fetch.domovina.tv`)

Kod: `fetch.domovina.tv` `9b96aa5d` (modul) + `1de73cad` (integracija). Opis za pipeline:
`fetch.domovina.tv/docs/2026-11-12-postavke-kanala-u-pipelineu.md`.

700. **Izvor stanja za pipeline je katalog `GET /v1/settings`** (odgovor na §C-13 matrice),
     jednom po runu: `run_pipeline.sh` zapiše snimku i izveze `CHANNEL_SETTINGS_FILE`, a
     skripta pokrenuta sama dohvati jednom (15 min svježe). Jedan odgovor nosi i tombstone,
     pa nema drugog izvora. Modul `lib/channel_settings.js` ponovno zatvara `off` po
     ovisnostima iz odluke 108, iako je odgovor već efektivan.
701. **Obrada je fail-closed, čitači nisu.** Nedostupan katalog (3 pokušaja, 15 s) → snimka
     `ok:false`, svaki korak obrade preskače SVE epizode (i kanale bez retka) uz
     `⛔ POSTAVKE KANALA NEDOSTUPNE`; run se ne ruši. Čitači (KORAK 13, watch, discover,
     WhatsApp, glasački bazen) koriste zadnju uspješnu snimku
     (`storage/.channel_settings.last_ok.json`), a bez nje ne filtriraju i to javljaju: druga
     su linija, a prazna naslovnica je gora greška. WhatsApp `--commit` i glasački bazen
     `--commit` uz zastarjelu snimku odbijaju rad.
702. **UC epizode = `info.json` `channel_id` ∪ UC kanala liste iz registryja.** Isključeno
     kod bilo kojeg od njih = preskoči. Direktorij `domovina_tv` traži registry slug
     `domovina-tv` (46 od 62 direktorija ima samo oblik s crticom).
703. **Svaki korak obrade provjerava `processing` + master + svoj ključ** (`checkStep`), pa
     isključena obrada zaustavlja i epizodu koja je već skinuta (odgovor na §C-4: provjera u
     svakom koraku, ne samo prije uploada).
704. **Preskočena epizoda ne dobiva nikakav trag** (`failed[]`, `completed[]`,
     `.words.skipped.json`, done-cache): kad vlasnik uključi ključ, sljedeći run je obradi.
     Ništa se ne briše (odluka 8).
705. **Medij se ne skida kad su `cdn_playback` i `transcript_subtitles` oboje off**
     (odluka 108: nema što objaviti). Lista Tier 1 se provjerava po kanalu liste prije
     skidanja; epizoda tuđeg kanala na listi hvata se u `convert_to_wav`/ASR po `info.json`.
     Ad-hoc (`--unlisted-url`/`--video-id`) pita `yt-dlp --print channel_id` samo kad katalog
     ima barem jedan isključen kanal.
706. **KORAK 13 filtrira po kanalu, ne po epizodi**: povučen ili obrisan kanal izostaje iz
     `index.json`, listinga (ne piše se novi, stari na R2 ostaje), `home.json` i
     `search.json`; `home_featured` off samo iz `home.json`, `in_app_search` off samo iz
     `search.json`. Bez isključenih kanala izlaz je bajt-identičan (ETag stabilan, test).
707. **Tombstone UC se nikad ne vraća**: `watch_candidates.js` ga ne prati, `discover.js`
     ga izbacuje u aggregate/triage/classify/apply (i uz `--force`, i za playliste vlasnika),
     Tier 2 ne stvara job. U discover `ledger.json` se ne piše (izvor istine je katalog).
708. **Glasački bazen**: povučen ili obrisan UC ispada iz skupa kandidata prije `--limit`, pa
     ga postojeća logika označi `withdrawn` (nikad DELETE). Skripta nije pokretana (glasanje
     skriveno, voting-drift ugašen).
709. **Poznate rupe, svjesno ostavljene**: KORAK 2.5 (rclone WAV na Drive) i ugašeni KORAK 6
     nemaju ogradu; `render_reels.js` objava šalje već postojeći `reels.json`; Magisterium job
     koji pokrene admin skripta preskoči s exit 0, a bridge ga označi kao failed (drugi repo);
     izvorni jezik za `diarized.en.srt` (odluka 508) nije označen jer nijedan kanal na
     engleskom nije prijavio problem. Revizija: prvi vlasnik koji isključi ključ, ili prvi
     kanal na engleskom koji ga isključi.

## S8 (2026-11-13, Meili, RAG, push, cutter, ugovor vijesti)

Kod: `domovina-rag` `aa48d28`, `08ca056`, `817c0d4`; `domovina-push` `78016b0`;
`domovina-cutter` `835d7af`; katalog `1b8a2f7`. Ugovor za vijesti:
[research/2026-11-13-ugovor-vijesti.md](research/2026-11-13-ugovor-vijesti.md). Opis za RAG:
`domovina-rag/docs/2026-11-13-postavke-kanala.md`.

800. **`GET /v1/settings` nosi `slugs` po UC-u** (katalog, aditivno, `version` ostaje "1"):
     unija slugova iz tablice `channels` i, za tombstone, iz tombstonea. Razlog: RAG, Meili,
     push i vijesti kanal znaju po slugu, a povučen kanal izostaje iz `/v1/channels`, pa mapu
     slug↔UC nemaju odakle složiti. Usporedba sluga svugdje normalizirana (lowercase, `_` = `-`).
     Bez `slugs` (stari katalog) RAG ne filtrira i upozori; push i cutter rade po UC-u.
801. **Čitači koriste zadnju dobru snimku, pošiljatelji su fail-closed.** MCP, Meili sync i
     cutter: greška → zadnja uspješna snimka, bez nje bez filtra uz glasan log (kao odluka 701).
     Push je pošiljatelj: greška dohvata → ciklus ne šalje ništa i ne upisuje `sent:`. Engine
     vijesti je pisac: fail-closed (ugovor §5).
802. **`/api/search?purpose=search|assistant|news`** → ključ `in_app_search` | `ai_assistants` |
     `news_portal`. Bez parametra = `search` (stari buildovi aplikacije). Nepoznat ili ponovljen
     parametar = 400, da tipfeler pozivatelja ne zaobiđe ključ. MCP alati uvijek `ai_assistants`;
     `mode=map` poštuje `purpose`.
803. **Filtar je u upitu, prije `LIMIT`** (`channel NOT IN` nad svim varijantama sluga u
     ClickHouseu, `channel NOT IN [...]` u Meiliju), da `limit` ostane točan.
804. **`rag_chunks` se prekidačem ne brišu.** ETL i `sync-incremental` nedirnuti: `rag_chunks`
     hrani i Meili i person hub, a ponovno uključivanje bi tražilo re-embed. Fizičko uklanjanje
     radi samo skripta trajnog brisanja (S9). Zamjenjuje rečenicu matrice §17 „sljedeći sync ih
     briše iz `rag_chunks`”.
805. **Meili `episodes` se filtrira pri buildu** (noćni puni rebuild + swap, pa se uključivanje
     samo vraća); **`segments` je inkrementalan**, pa se skrivene epizode brišu zajedno sa
     stanjem synca i sljedeći sync ih nakon uključivanja vidi kao nove. Postavke u jednom runu ne
     smiju izbaciti više od 50 % dokumenata; snimka `logs/channel_settings.last_ok.json`.
806. **Osobe**: kanal s `persons_mentions` off izostaje iz `episodes[]`, `cameo_episodes[]`,
     `mentions[]` i iz pravila virtualnog kanala (računa se bez njega; `is_virtual_channel` se ne
     predračunava, provjereno grepom). Osoba poznata samo iz isključenog kanala dobiva prazan
     profil (200, ne 404), kao kod opt-outa. Cache `/api/persons` vezan je uz skup skrivenih
     kanala. `count_mentions` gleda ključ samo uz `group_by=speaker`.
807. **`get_episode` za isključen kanal vraća `EPISODE_NOT_FOUND`**, isto kao za nepostojeću
     epizodu: alat ne otkriva što je vlasnik isključio. `server_info` brojke filtrira po
     `ai_assistants`.
808. **Push: isključena epizoda dobiva `sent:<id>` = `skipped:push_notifications`.** Inače bi
     uključivanje poslalo zastarjele obavijesti (prozor 4 dana) koje je vlasnik namjerno utišao.
     Epizoda u više listinga je utišana ako je utišava ijedan; preskočene ne troše `MAX_PER_RUN`.
     UC dolazi iz `youtube_channel_url` u `index.json` (52/52 kanala ga imaju) i iz `slugs`;
     `info.json` po epizodi se ne čita (≈ 84 KB). Tema kanala ostaje.
809. **Cutter: 403 `setting_off:<ključ>` / `channel_withdrawn`, 410 `channel_deleted`**, `no-store`,
     na obje `/clip` rute i `/chapters` (prije cache-gatea, pa i 302 na već izrezan isječak).
     UC iz `info.json` kroz R2 binding (ne CDN, zbog cachiranog 404). Već izrezani isječci na
     `cdn.domovina.ai/clips/…` ostaju dostupni izravnim URL-om (sakriti ≠ obrisati).
810. **Rizik: cutter je u zoni `domovina.ai`.** Fetch iz Workera prema
     `domovina.ai/api/katalog/…` iste zone može ne proći; tada je cutter tiho fail-open. Provjera
     nakon deploya: `wrangler tail` bez „postavke kanala nedostupne”; ako se pojavi → service
     binding na katalog Worker.
811. **Objavljeni članci vijesti ostaju kad je kanal povučen** (prijedlog, ugovor §4); za trajno
     obrisan kanal urednik bira ispravak ili povlačenje. `article_sources … ON DELETE RESTRICT`
     je otvoreno pitanje lanca vijesti i blokira dio S9 za `vijesti.*`.
812. **Kašnjenje se zbraja**: katalog poller + MCP snimka 60 s + `Cache-Control` odgovora
     (`/api/search` i `/api/person` 300 s, `/api/persons` 900 s); indeksi do sljedećeg 04:00.
     Klijentski filtar iz S5 pokriva aplikaciju u međuvremenu.
813. **Cutter čita katalog kroz service binding `KATALOG`** (zamjenjuje rizik iz odluke 810;
     `domovina-cutter` `6345f95`). Izmjereno 13. 11. nakon prvog deploya: fetch na
     `domovina.ai/api/katalog/v1/settings` iz Workera u istoj zoni vratio je HTML (`Unexpected
     token '<'`) i gate je bio fail-open; nakon bindinga `wrangler tail` je čist. Svaki budući
     Worker u zoni `domovina.ai` koji čita katalog ide kroz binding, ne fetchom.
814. **Deploy S8 13. 11. (korisnik odobrio):** katalog `4c623f0c` (`slugs`), MCP preko
     `deploy.sh` (novi kod živ tek ~1–2 min nakon što skripta javi „živo”: `/health` odgovara
     stari kontejner dok se novi gradi, pa je provjera `purpose=xyz` → 400, ne `/health`), push
     `622840a6` (`DRY_RUN=1` ostaje; ciklus 9:50 „nema novih epizoda”, dohvat postavki bez greške — push nije u zoni), cutter `17eb5410`.

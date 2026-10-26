# Izborni dan — predaja timu (krug 1)

> Dizajn, istraživanje i obrazloženja: **`docs/plans/2026-08-08-glasanje-o-kanalima.md`**.
> Ovaj dokument je samo razbijanje na taskove. Svaki dev PRVO pročita dizajn
> dokument (barem §4, §5, §6 i §8) — ovdje se ne ponavlja.

## Za orkestratora — pročitaj prije dispatcha

1. **Tri repoa.** T1 je u `~/git/domovinatv/domovina-api`, T4 u
   `~/git/domovinatv/fetch.domovina.tv`, ostalo u ovom repou. Svaki se
   commita **zasebno, u svom radnom stablu, s vlastitom porukom**. Reviewer
   gleda `git diff` u **sva tri**, ne samo u `domovina.ai`.
   *Zatečeno*: `fetch.domovina.tv` ima necommitanu izmjenu
   `magisterium_doc_urls.json` koja NIJE dio ovog posla — ne uvlačiti je u commit.
2. **T1 ‖ T2 jer je RPC ugovor iz dizajn §5.2 normativan.** Ako T1 mora
   odstupiti od tog JSON-a (imena polja, oblik greške), orkestrator to mora
   javiti **prije nego T2 krene**, odnosno zaustaviti T2 i uskladiti — inače
   Flutter modeli parsiraju nepostojeći ugovor.
3. **Rizik je visok** (Supabase shema + KYC putanja + `web/_worker.js`) →
   reviewer ide na `/model opus` prije prvog pregleda.
   **Ne pokretati `supabase db push`, ne deployati migracije na Coolify, ne
   pokretati `./scripts/deploy.sh`.** Ništa od toga nije u ovom krugu.

### Ispravci nakon provjere repoa (2026-08-08, planner)

Sve ostalo iz popisa fajlova postoji kako je napisano. Tri stvari su se
razišle sa zatečenim stanjem i **ovdje napisano ima prednost** nad dizajn
dokumentom:

- **T4 putanja**: `fetch.domovina.tv` **nema `scripts/` direktorij** — sve
  skripte su u korijenu repoa (`ingest_beamly.mjs`, `generate_channel_index.js`,
  …). Skripta ide kao **`sync_voting_candidates.mjs` u korijenu**, ne u
  `scripts/`. Dizajn §9.1 navodi `scripts/…` — pogrešno. Ekstenzija `.mjs` je
  obavezna (`package.json` nema `"type": "module"`).
- **Zastavica**: T3 (`CustomPaint` u `lib/widgets/hrvatska_zastavica.dart`)
  **nadjačava** dizajn §8.3 (`assets/voting/zastavica.png`). Razlog je u T3:
  asset bi tražio izmjenu `pubspec.yaml`, koji je zajednička točka i lomi
  paralelizaciju.
- **`⚑ Prati`**: dizajn §8.2 stanje 1 prikazuje ga gostu umjesto 👍👎, ali
  `candidate_follows` UI je u **Van opsega**. U ovom krugu gost vidi ljestvicu
  bez akcijskog gumba + trajnu traku „Potvrdi se e-Osobnom i glasaj". Tablica
  `candidate_follows` se svejedno stvara u T1.

### Ugovor v1.1 — preciziranje iz T1 (2026-08-08, normativno umjesto §5.2)

T1 je javio odstupanja/preciziranja RPC ugovora. **Ovo nadjačava dizajn §5.2**;
T2 modeli se rade na OVO:

1. **Imena parametara nose `p_` prefiks** (konvencija repoa):
   `cast_vote(p_slug text, p_direction int)`;
   `round_leaderboard(p_round_id int, p_sort text, p_tag text, p_limit int, p_offset int, p_query text)`
   — `p_query` je NOVI opcionalni parametar za pretragu, default `null`.
   `my_voting_state()`, `current_round()`, `accept_voting_terms()` bez parametara.
2. **`my_voting_state`** — polja točno kao §5.2, uz preciziranje:
   `today_vote` je `null` ILI `{"slug":"…","direction":1}`;
   `round` je `{"id","starts_on","ends_on","days_left"}`.
3. **`cast_vote`** vraća isti JSON kao `my_voting_state` **plus**
   `"flags_burned"` (int) i `"streak_saved"` (bool).
4. **`current_round`** vraća `{"id","starts_on","ends_on","status","days_left",
   "today","quorum_net","quorum_total","total_votes","voters"}`.
5. **`round_leaderboard`** vraća `TABLE(slug, display_name, youtube_url,
   youtube_channel_id, avatar_url, tags, voditelji, subscribers,
   episodes_estimate, quality_score, tier, notes, source_type, status, up,
   down, net, rank)`; `p_sort in (leaderboard|random|least_votes)`.
6. **Greške nepromijenjene**: `not_verified`, `terms_not_accepted`,
   `already_voted_today`, `candidate_not_available`, `round_closed`.
7. **Transport grešaka (T1, potvrđeno)**: kroz PostgREST dolaze kao HTTP 400
   s tijelom `{"code":"P0001","message":"already_voted_today"}` — klijent
   parsira **`message`**, ne `code`. Nedostatak execute prava = `42501`/401.
8. **Lokalno test stanje (za T2/T3)**: lokalni Supabase ima 4 test kandidata
   (`podcast-inkubator`, `projekt-velebit`, `rebootcast`, `mjesto-zlocina`)
   i otvoreno kolo koje pokriva današnji dan.
9. **`streak_at_risk` semantika (T2 nalaz, ZA REVIEW)**: doslovna formula iz
   §6.3 (`missed == flags`) daje `true` i glasaču koji nikad nije glasao
   (`0 == 0`). T2 projekcija zato traži **i `streak > 0`** — to je ispravno
   ponašanje (UI ne smije nuditi „niz visi" nad nizom od nula dana). T1 SQL
   mora vraćati isto; reviewer provjerava da se server i klijent ne raziđu
   na ovom polju. (Primjer JSON-a u dizajn §5.2 sam sebi proturječi na tom
   polju — formula §6.3 + `streak > 0` je normativna, JSON je ilustracija.)

## Cilj

Verificiran hrvatski građanin (Certilia) dobiva jedan glas svakih 24 h koji troši
na 👍/👎 jednog od 181 kandidata iz podcast registra. Glasanje teče u kolima od
14 dana; pobjednik se stvarno onboarda u pipeline. Dnevni povratak drži streak
mehanika po uzoru na Brilliant (niz 🔥 + do 2 hrvatske zastavice koje automatski
spašavaju propušteni dan).

Nakon ovog kruga: shema i RPC-evi postoje i testirani su lokalno, Flutter data
sloj i ekran `/glasanje` rade end-to-end protiv lokalnog Supabasea, kandidati se
mogu sinkronizirati iz registra. **Deploy migracija na Coolify i objava feature-a
NISU u ovom krugu.**

## Kontekst

Zatečeno stanje s dokazom u kodu:

- `domovina-api/supabase/migrations/20260529120000_identity_verifications.sql:27`
  — `oib_hash text not null unique`. Jedan OIB = jedan račun na razini baze.
- **ALI** `…:23` — `user_id … references auth.users(id) on delete cascade`.
  Brisanje računa oslobađa `oib_hash` → ista osoba može glasati dvaput isti dan
  (obriši → ponovno verificiraj). Zato glas NE ide na `user_id` nego na trajni
  `domovina_ai.voters.id` koji nosi `oib_hash` i ima `user_id … on delete set null`.
  **Ovo je razlog postojanja tablice `voters` — ne izbacivati je „radi
  jednostavnosti".**
- `lib/services/auth_service.dart:162` — `isVerified: appMeta['kyc_verified'] == true`.
  Klijentski gate za glasanje je već tu, ne treba novi.
- `lib/services/follow_service.dart` — obrazac servisa (singleton + `local_prefs`).
  `PlaybackSpeed`/`PlayerMute` su presedan za „stanje ide kroz singleton, ne kroz
  propove" (CLAUDE.md) — `VotingService` mora biti singleton `ChangeNotifier`
  jer se niz prikazuje na tri odvojena stabla.
- `fetch.domovina.tv/data/podcasts_registry.json` v1.2 — 273 zapisa, filter iz
  dizajn dokumenta §3 daje **181 kandidata** (177 s `youtube.channel_id`).

Odluke koje su već pale (ne re-litigirati):

1. Slobodan izbor iz cijelog registra, **ne** „trojka dana".
2. Kola od 14 dana s pobjednikom, **ne** vječna ljestvica.
3. Streak samo za verificirane.
4. Bez podsjetnika (e-mail/push) u v1.
5. Rangiranje = **neto 👍−👎**, bez Wilsona. Kvorum: `net ≥ 10` i `up+down ≥ 25`.
6. Granica dana = `(now() at time zone 'Europe/Zagreb')::date`, **isključivo**
   u Postgresu. Bez grace sati. Bez crona — sve je lijeno.
7. Zastavice se troše **sve-ili-ništa** (odstupanje od Brilliant-a, §6.3).

**Ugovor RPC-eva iz dizajn dokumenta §5.2 je normativan.** T1 i T2 idu paralelno
upravo zato što je taj JSON fiksiran. Ako T1 mora odstupiti, orkestrator to mora
javiti prije nego T2 krene.

## Taskovi

### T1 — Supabase shema, RLS i RPC-evi

- **Repo**: `domovina-api` (**drugi repo!** — vidi §Ovisnosti)
- **Fajlovi**:
  - `supabase/migrations/20260808120000_channel_voting.sql`
  - `supabase/migrations/20260808120100_channel_voting_rls.sql`
  - `supabase/migrations/20260808120200_channel_voting_rpcs.sql`
  - `docs/channel-voting-curl-scenario.md`
- **Opis**: implementiraj shemu iz dizajn dokumenta §5 (6 tablica u
  `domovina_ai`), RLS iz §5.1, RPC-eve iz §5.2 i logiku iz §6.3 (streak
  prijelaz) i §7 (rangiranje, kvorum, lijeno zatvaranje kola s
  `pg_advisory_xact_lock`). Trojka migracija po uzoru na
  `20260716120000_events_ticketing_*`.
  `cast_vote` mora razriješiti `voter` iz `public.identity_verifications.oib_hash`
  kroz SECURITY DEFINER (tablica je service_role-only), sve u JEDNOJ transakciji.
- **Definicija gotovog**:
  - `supabase db reset` lokalno prolazi bez greške
  - `docs/channel-voting-curl-scenario.md` prolazi ručno: verificiran korisnik
    glasa → drugi glas isti dan pada na `already_voted_today` → tally se
    inkrementira točno jednom
  - svih 10 rubnih slučajeva iz §6.4 pokriveno SQL scenarijem (simulacija dana
    kroz parametar u test wrapperu, NE kroz mijenjanje `now()`)
  - **NE pokretati `supabase db push` ni deploy na Coolify**

### T2 — Flutter data sloj i streak projekcija

- **Fajlovi**:
  - `lib/models/vote_candidate.dart`
  - `lib/models/vote_round.dart`
  - `lib/models/voting_state.dart`
  - `lib/services/voting_service.dart`
  - `test/voting_streak_test.dart`
- **Opis**: modeli za JSON iz §5.2, singleton `ChangeNotifier` servis nad
  Supabase RPC-evima (`client.schema('domovina_ai').rpc(...)`, vidi
  `db_schema_split` obrazac), optimistički update s rollbackom, i **čista
  Dart funkcija** koja replicira projekciju iz §6.3 za trenutni prikaz između
  dva network poziva. `already_voted_today` se ne prikazuje kao greška nego kao
  tiho poravnanje stanja.
  Lokalni cache zadnjeg stanja kroz `local_prefs.dart` — **nikad
  `SharedPreferences` na webu**.
- **Definicija gotovog**: `test/voting_streak_test.dart` pokriva svih 10 slučajeva
  iz §6.4 i prolazi; `flutter analyze` čist; nijedan UI fajl nije dirnut.

### T3 — Ekran `/glasanje`

- **Serijski nakon T2** (troši njegove modele i servis)
- **Fajlovi**:
  - `lib/screens/voting/voting_screen.dart`
  - `lib/screens/voting/widgets/candidate_tile.dart`
  - `lib/screens/voting/widgets/voting_header.dart`
  - `lib/screens/voting/widgets/streak_flags.dart`
  - `lib/widgets/hrvatska_zastavica.dart`
  - `lib/router/app_router.dart`
  - `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`
- **Opis**: ljestvica kola s pretragom, sort chipovima (Ljestvica / Nasumično /
  Najmanje glasova) i tag filterima (§3.1), te **svih 5 stanja iz §8.2** kao
  zasebni widgeti — ne if-ovi u buildu. Rute `/glasanje` i `/glasanje/:slug`.
  - **Zastavica je `CustomPaint`, ne asset i ne emoji.** 🇭🇷 emoji se ne
    renderira na Windows Chromeu; asset bi tražio izmjenu `pubspec.yaml` koji je
    zajednička točka i lomi paralelizaciju.
  - Padding ide **kao `padding:` parametar na listu**, nikad kao `Padding`
    wrapper (CLAUDE.md).
  - Avatari kroz `CachedThumbnail` s CDN URL-a, **nikad** direktno s YouTubea
    (CORS). Fallback = monogram na `AppTheme.croBlue` + `brandRim()`.
  - i18n prefiks **`voting*`**, ICU plural za dane/glasove/zastavice
    (hr `one/few/other`). Perzistentni tekst → `AppLocalizations.of(context)`;
    `appStrings` samo u catch blokovima.
- **Definicija gotovog**: `/glasanje` radi protiv lokalnog Supabasea u sva
  4 stanja koja se daju izazvati (gost, verificiran-nije-glasao,
  verificiran-glasao, niz-visi); `flutter gen-l10n` prolazi; `flutter analyze` čist.

### T4 — Sync kandidata iz registra

- **Repo**: `fetch.domovina.tv` (**drugi repo!**) — može paralelno s T3
- **Fajlovi**:
  - `sync_voting_candidates.mjs` (**korijen repoa** — taj repo nema `scripts/`)
  - dopuna `CLAUDE.md` u tom repou (kratka sekcija o skripti)
- **Opis**: čita `data/podcasts_registry.json`, filtrira po §3
  (`tracking.enabled == false` AND ima `youtube.url` AND
  `status ∈ {active, active-slowing, unknown}`), upserta u
  `domovina_ai.vote_candidates` preko `service_role`. Nikad ne briše kandidate s
  glasovima — samo `status = 'withdrawn'`. Avatare povlači kroz `yt-dlp --print
  thumbnail` i uploada na `cdn.domovina.ai/registry/avatars/<slug>.jpg`.
- **Definicija gotovog**: `node sync_voting_candidates.mjs --dry-run`
  ispiše točno **181** kandidata i broj razriješenih avatara; bez `--commit` ne
  piše ni u bazu ni na CDN.

### T5 — Ulazne točke i distribucija

- **Serijski nakon T3** (dira iste ARB fajlove + `web/_worker.js`)
- **Fajlovi**:
  - `lib/screens/home/home_app_bar.dart` (chip s nizom + crvena točka kad je
    glas neiskorišten)
  - `lib/screens/account/account_screen.dart` (niz, najduži niz, ukupno glasova)
  - `lib/screens/channels/all_channels_screen.dart` (traka „Nema tvog podcasta?")
  - `web/_worker.js` (OG za `/glasanje` i `/glasanje/:slug`, AASA `components`)
  - `android/app/src/main/AndroidManifest.xml` (intent filter za `/glasanje`)
  - `lib/l10n/app_hr.arb`, `lib/l10n/app_en.arb`
- **Opis**: sve su to **trajne površine** — nijedan modal, nijedan snackbar koji
  prekida reprodukciju (CLAUDE.md pravilo o nudge-evima).
  `/glasanje` je javna content ruta → **mora ući u OBA popisa** (AASA components
  i Android intent filter), a NE u auth exclusion.
- **Definicija gotovog**: `node scripts/test-social-tags.mjs` prolazi za nove
  rute; `flutter analyze` čist.

### Zapisnik T4 (2026-08-08, dev1)

- `--dry-run` daje točno **181** kandidata, **179** razriješenih avatara.
- **2 mrtva `@handle` URL-a u registru** (`iza-okvira`, `povijest-cetvrtkom`)
  — yt-dlp vraća 404. To je podatak u registru (`fetch.domovina.tv`), nije
  popravljan u ovom krugu; avatar fallback (monogram) to pokriva u UI-ju.
- `--commit` je verificiran protiv **lokalnog** Supabasea — lokalna baza sada
  ima svih 181 kandidata (bolja podloga za T3 od 4 test-reda iz T1).
- Jedini produkcijski side-effect: **jedan** avatar
  (`registry/avatars/2pogled-povijest.jpg`) uploadan na `cdn.domovina.ai`
  kao dokaz R2 putanje (prefiks je bio prazan). Ostavljen — dio je budućeg
  feature-a; obrisati samo ako smeta.
- `magisterium_doc_urls.json` (tuđa necommitana izmjena) nije diran.
- **Odstupanje od dizajn §8.4 (obrazloženo)**: `yt-dlp --print thumbnail` na
  URL-u kanala vraća banner 1060×175, ne avatar → skripta čita
  playlist-razinu (`-J --flat-playlist --playlist-items 0`) i bira kvadratni
  thumbnail; playliste bez avatara padaju na najveći poster.
- Avatar URL-ovi s `yt3.googleusercontent.com` rewriteaju se na
  `=s400-c-k-c0x00ffffff-no-rj` (~260→100 KB) s fallbackom na original ako
  HEAD ne prođe.
- Regresija „re-run označi ~180 kandidata withdrawn" (slug mismatch) uhvaćena
  testom protiv lokalne baze, popravljena, pravilo zapisano u CLAUDE.md tog
  repoa.

### Ishod kruga 1 (2026-08-08)

- **r1 (T1+T2): VERDIKT OK** → commitano: `domovina-api b5e1588` (T1),
  `domovina.ai d851b3e` (T2), plan docsi `8d23825`.
- **r2 (T4): VERDIKT OK** → commitano: `fetch.domovina.tv a6419d2`.
- **Follow-upovi iz r2 za sljedeći krug (fulfillment)** — ne blokiraju:
  `registry_synced_at` se nikad ne osvježava (jedna linija u `toRow()`);
  CDN purge vezati uz „uploadano", ne uz `--force-avatars` (negativni cache
  nakon prvog pravog `--commit`); `patchStatus` dodati `&status=eq.…` filter
  (mikroskopski race prema `winner`); `slug=in.(…)` batchati (8 KB URL limit);
  kozmetika dvostrukog brojanja grešaka u statistici.
- **Za T3/T5**: 3 kandidata (`umbrella` ×2, `disputed` ×1) mapiraju se u
  `VoteSourceType.unknown` — bez badgea izvora, siguran fallback.

### Zapisnik T5 (2026-08-08, dev1)

- **Ugovor v1.2**: `my_voting_state()` (i `cast_vote` odgovor) dobiva i
  **`total_votes`** (int) — kolona `voters.total_votes` je postojala i
  `cast_vote` je inkrementira, samo nije bila u projekciji. Flutter model ga
  nosi kao `int?` i redak na `/account` izostaje kad polja nema (bez izmišljene
  nule).
- Verifikacija OG tagova za `/glasanje` rađena lokalnim harnessom —
  produkcijski prolaz `test-social-tags.mjs` moguć tek nakon deploya workera
  (van opsega kruga).
- **Izvanplanski posao (uputa iz panela)**: očekivanja za epizode u
  `scripts/test-social-tags.mjs` poravnata s workerom (og-share.jpg,
  1200/630/image/jpeg) — pre-postojeći pad, nije regresija T5.
- Home rail „Izborni dan" iz dizajn §8.6 NIJE rađen — nije na popisu fajlova
  T5 (dirao bi home feed). Sitemap također odgođen do izlaska featurea.

### Ishod kruga 2 (2026-08-08) — PLAN IZVRŠEN

- **r3 (T3): DORADA** (3 nalaza u `voting_screen.dart`) → **r4: OK** →
  commit `domovina.ai a59ce38`.
- **r5 (T5 + ugovor v1.2 + izvanplanski social-tags): OK** → commiti
  `domovina.ai 2f4fcc6` (T5) + `32d25ab` (social-tags), `domovina-api
  5b67aed` (total_votes).
- **Deploy NIJE rađen** (migracije nisu na Coolifyju, worker nije deployan)
  — po planu. Prije objave featurea: `supabase db push`/Coolify deploy
  migracija, produkcijski `sync_voting_candidates.mjs --commit` (uklj.
  avatare), `./scripts/deploy.sh`, pa produkcijski `test-social-tags.mjs`
  za `/glasanje` rute.
- **Follow-upovi za sljedeći krug** (iz r5, ne blokiraju): home rail
  „Izborni dan" (dizajn §8.6) + sitemap; zastarjeli komentari o v1.1 u
  `voting_state.dart:249` i `account_screen.dart:375`; dedup dvostrukog
  `refresh()` (home chip + account); `</script>` escape u JSON-LD injekciji
  (zatečeni obrazac, sada prolazi i `display_name`); chip a11y
  (`ExcludeSemantics` bez tap akcije); + raniji iz r3/r4 (compactCount
  decimalni zarez, `_maybeOpenFocused` jednokratni pokušaj, `_NetScore`
  semantika, drag chip redova) i r2 (sync robusnost).
- **VAŽNO za `domovina-api`**: migracija `…120200` je uređivana in-place
  NAKON commita `b5e1588` — legitimno samo dok migracije nisu pushane na
  Coolify; od prvog pusha svaka izmjena = novi migracijski fajl.

## Ovisnosti

```
T1 ‖ T2 ‖ T4        (tri različita repoa / disjunktni fajlovi)
T2 → T3 → T5        (serijski)
T3 ‖ T4             (drugi repo)
```

**Kritično — zajedničke točke:**

- `lib/l10n/app_hr.arb` i `app_en.arb` dira T3 **i** T5 → nikad istovremeno.
- `web/_worker.js`, `pubspec.yaml`, `AndroidManifest.xml` dira samo T5.
- **T1 i T4 rade u DRUGIM repoima** (`domovina-api`, `fetch.domovina.tv`).
  Orkestrator commita samo `domovina.ai`; izmjene u druga dva repoa mora
  commitati zasebno, u njihovim radnim stablima, s vlastitom porukom. Reviewer
  mora eksplicitno pogledati `git diff` u sva tri repoa, ne samo u ovom.

## Rizik

**visok** — Supabase shema + identitet/KYC putanja + `web/_worker.js` + nova
javna ruta. Reviewer ide na Opus.

Specifično što reviewer mora provjeriti, a lako se previdi:

1. `voters.user_id` MORA biti `on delete set null` (ne cascade) — inače je
   „jedan čovjek jedan glas" probijen brisanjem računa.
2. Datum se nigdje ne prima od klijenta.
3. `votes` i `voters` nemaju **nijednu** client RLS policy.
4. `unique (voter_id, vote_day)` postoji i dupli tap ne duplira tally.
5. `cast_vote` je jedna transakcija (insert + tally + streak), ne tri poziva.
6. Zastavice se ne troše kad ne mogu spasiti niz (§6.3).

## Verifikacija

- `flutter analyze` čist (obavezno).
- `flutter test test/voting_streak_test.dart` — svih 10 slučajeva iz §6.4.
- `supabase db reset` u `domovina-api` prolazi; curl scenarij odrađen ručno.
- `node scripts/test-social-tags.mjs` za nove rute.
- Ručno u appu: `/glasanje` kao gost (ljestvica vidljiva, glasanje zaključano),
  pa kao verificiran korisnik (glas prolazi, drugi glas isti dan odbijen,
  header prikazuje niz i zastavice).
- **Poznato**: `test/widget_test.dart` i `home_feed_test` padaju i na čistom
  mainu — nisu regresija.

## Van opsega

- Deploy migracija na Coolify i `./scripts/deploy.sh` — **ne u ovom krugu**.
- Podsjetnici (e-mail/web push/native push) — svjesna odluka, §11.1.
- `promote_winner.mjs` i cijela fulfillment petlja (§9) — sljedeći krug, nakon
  što prvo kolo stvarno postoji.
- Arhiva kola `/glasanje/kola`, pečat pobjednika, „podijeli svoj niz".
- `candidate_follows` UI (⚑ Prati) — tablica se stvara u T1, UI dolazi kasnije.
- Rive animacije zastavica — v1 je `AnimatedSwitcher`.
- Bilo kakva izmjena postojećeg Certilia flowa.

## Zapisnik deploya (2026-08-08)

Pisano za tim koji NIJE bio u ovom razgovoru. Deploy je izvršen isti dan
nakon kruga 2, redom: migracije → sync kandidata → web deploy → social-tags.
Aplikacija je live kao **v2.0.130+152** (`domovina.ai` commit `403f6cb`).

### 1. Što je stvarno otišlo na produkcijsku bazu

Migracije se na prod NE guraju sa `supabase db push` nego s
**`domovina-api/scripts/db-migrate.sh`** (SSH na dom-001 → `docker exec psql`,
transakcija + pg_dump backup + tracking tablica
`supabase_migrations.schema_migrations`). Skripta primjenjuje SVE pending
migracije **linearno, bez cherry-picka** — zato su uz tri voting migracije
(`20260808120000/120100/120200_channel_voting*`) otišle i **dvije starije
events/Stripe migracije** koje su bile na mainu ali ne i na produkciji:

- `20260803120000_events_stripe_rail.sql`
- `20260803130000_events_stripe_refund.sql`

Posljedica: events/Stripe **shema postoji na produkciji, ali backend koji je
koristi nije deployan u ovom krugu** (edge funkcije/worker za taj tok nisu
dirani). Tablice su aditivne i inertne — ali tko bude debugirao prod bazu neka
se ne iznenadi što postoje; a tko bude deployao events backend, neka zna da mu
je shema već tamo.

### 2. Pravilo za migracije OD SADA (i kako prepoznati kršenje)

Povijest migracija je na produkciji → **svaka daljnja izmjena bilo koje
migracije ide kao NOVI fajl s novim timestampom, nikad in-place.**
(In-place izmjena `…120200` s `total_votes` bila je legitimna SAMO zato što se
dogodila prije prvog produkcijskog pusha — ta iznimka više ne postoji.)

Kako se kršenje prepozna: `db-migrate.sh` preskače verzije koje su već u
tracking tablici, pa in-place izmjena **tiho nikad ne stigne na prod** —
lokalna baza (nakon `supabase db reset`) i produkcija se raziđu bez ijedne
greške. Provjera sumnje:
`git log -p --follow supabase/migrations/<fajl>.sql` (izmjene NAKON
2026-08-08 = kršenje) i usporedba definicije funkcije na produkciji
(`\sf domovina_ai.<fn>` kroz `scripts/db-psql.sh`) s lokalnim fajlom.

### 3. Coolify API token vraća 403

- Pokušano: `domovina-api/scripts/coolify-env-get.sh SERVICE_ROLE_KEY`
  (i iz repo roota) → `HTTP 403 {"message":"You are not allowed to access
  the API."}`. Token u envu skripte je nevažeći ili mu fali read scope.
- Zaobiđeno: SSH na dom-001
  (`ssh -i ~/.ssh/dom-001-oracle-ssh-key-2026-04-20.key ubuntu@89.168.100.120`),
  `SUPABASE_SERVICE_KEY` pročitan iz env-a containera
  `supabase-kong-cv887vonujh1swebndh4x4iu`, korišten isključivo kroz procesni
  env (`SUPABASE_SERVICE_ROLE_KEY=... node sync…`), privremeni fajl obrisan.
  Ključ NIJE upisan ni u jedan `.env`.
- **Prije sljedećeg ops posla**: popraviti/rotirati Coolify API token
  (treba read+write — vidi memory `feedback_coolify_ops`), inače svi
  `coolify-*.sh` alati stoje. `fetch.domovina.tv/.env` i dalje NEMA
  `SUPABASE_SERVICE_ROLE_KEY` — to je namjerno.

### 4. Otvoreno / neizvršeno

- **Ručna provjera `/glasanje` u pravom browseru NIJE izvršena** (bila je
  utipkana u panel orkestratora, ali tim se gasi). Verificirano jest: OG/HTML
  kroz `node scripts/test-social-tags.mjs` (164/164, obje /glasanje rute),
  REST count 181 kandidata, jedan avatar HTTP 200. NIJE verificirano: Flutter
  UI kao gost/verificiran korisnik na produkciji, niti ijedan pravi
  `cast_vote` na produkciji (na prod bazi još nema verificiranih glasača).
  Napomena za provjeru: automation browser slika /v/ rute tek nakon 30–60 s
  (memory `feedback_automation_browser_slow_paint`) — vrijedi i tu.
- **Prvo kolo se otvara lijeno** na prvi poziv `current_round()` (prvi posjet
  /glasanje) — u trenutku pisanja NIJE potvrđeno da je otvoreno. Tko prvi
  provjerava, neka očekuje da sam otvorio kolo svojim posjetom.
- **Sljedeći krug: fulfillment petlja** — `promote_winner` tok (dizajn §9),
  arhiva kola, `candidate_follows` UI. Plus follow-upovi popisani u
  „Ishod kruga 1" (sync robusnost) i „Ishod kruga 2" (home rail „Izborni
  dan", sitemap, zastarjeli komentari o v1.1, JSON-LD escape, itd.).

### 5. Sitnice koje bi sljedeći tim krivo pretpostavio

- **Dva kandidata nemaju avatar** (`iza-okvira`, `povijest-cetvrtkom`) — mrtvi
  `@handle` URL-ovi u registru (yt-dlp 404). To je podatak u
  `fetch.domovina.tv/data/podcasts_registry.json`, ne bug u syncu; UI ima
  monogram fallback. Popraviti handle u registru → ponoviti sync.
- **Lokalna** Supabase baza je ostavljena sa 181 kandidatom i kolom
  otvorenim tijekom testiranja (id 2, 8.–21.8.); test korisnici su obrisani.
  `glasac@test.hr` iz starijih zapisa NE postoji.
- Produkcijski sync se pokreće iz `fetch.domovina.tv` korijena:
  `SUPABASE_SERVICE_ROLE_KEY=… node sync_voting_candidates.mjs --commit`
  (env inače iz `.env`; `--dry-run` je default i ništa ne piše). Re-run je
  idempotentan; `withdrawn` dobivaju samo kandidati koji ispadnu iz registra.
- `registry/avatars/2pogled-povijest.jpg` na CDN-u NIJE anomalija — bio je
  test ključ iz T4, sada je legitiman dio potpunog seta (179 avatara).

---

## Naknadni zapisnik — 25.8.2026.: T5 je isporučio 3 od 4 ulazne točke

**Nalaz.** Dizajn §8.6 traži četiri ulazne točke. T5 (commit `2f4fcc6`) je
isporučio tri — home chip, `/account` kartica, `/channels` traka. **Home rail
„Izborni dan" nikad nije napisan**, a on je bio jedini javni ulaz na
naslovnici. Uz to su chip i `/account` kartica bili gate-ani na
`isVerified`, pa je posljedica bila:

> korisnik prijavljen Googleom (velika većina) nije imao NIJEDAN znak da
> glasanje postoji, osim trake na dnu `/channels`.

To je izokrenulo odluku 3 iz ovog dokumenta. Ona gate-a **glas** — niz i
zastavice postoje samo za građanina potvrđenog e-Osobnom. Ne gate-a saznanje
da se glasa. Bez saznanja nema ni razloga za potvrdu e-Osobnom, pa je lijevak
prema Certiliji bio prekinut na prvom koraku.

**Popravak** (isti dan):

1. `lib/screens/home/voting_rail.dart` — dug iz §8.6. Vrh ljestvice (10
   kandidata) + kartica koja objašnjava što se ovdje radi, iznad „Nastavi
   slušati". Javno, jedan `anon` RPC (`round_leaderboard` bez `p_round_id`),
   nikad ne dira `lastError`, sam se sakrije kad ljestvica ne stigne.
2. `VotingService.ensurePreviewLoaded()` — **odvojeno** polje od
   `candidates`; rail traži 10 redaka, `/glasanje` 100, a `ensureLoaded()` na
   drugom ulasku vraća dovršeni Future pa bi dijeljeno polje zaključalo krivi
   broj kandidata. Pokriveno u `test/voting_rail_preview_test.dart`.
3. `_VotingDiscoverChip` u `home_app_bar.dart` — chip za neverificirane, bez
   niza/zastavica/točke i **bez ijednog RPC-a**. Natpis tek od 840 dp:
   izmjereno, na 606 dp desktop red pukne za 38 px jer `Expanded` oko
   `_SearchTrigger`a spadne ispod ~90 dp koliko traži njegov sadržaj.
4. `/account` sekcija „Izborni dan" se prikazuje svima; neverificirani dobiva
   poziv umjesto niza. To je ekran na kojem Google korisnik ionako sjedi kad
   gleda načine prijave.
5. Usput: neto rezultat (`+N`) crtao se u `AppTheme.croBlue` — #002F6C kao
   tekst na tamnoj podlozi je nečitljiv, pa je vodeći kandidat gubio jedinu
   brojku koja ga razlikuje. Sada `cs.primary` (isto brand sjeme, tema-svjesno).
   Pravilo „navy = croBlue" vrijedi za POVRŠINE koje se boje, ne za tekst.

**Pravilo za idući put**: review kruga gleda diff onoga što je task dirao, pa
NE vidi točku iz plana koja uopće nije napisana. Kad plan nabraja N stavki,
zapisnik taska mora izrijekom reći koliko ih je isporučeno.

## Privremeno skriveno (26.10.2026., v2.0.200)

Značajka je ugašena za krajnje korisnike jer je na domovina.ai još zbunjujuća
i nije dovoljno razrađena. Kod, baza, RPC-evi i `voting-drift-check.sh` rade
dalje; ništa nije obrisano.

Kako je skrivena:

- `packages/podcast_core/lib/brand/domovina_brand.dart` — `voting: false`.
  Postojeća zastavica već je gatala sve ulaze: rute `/glasanje*`
  (`app_router.dart`), rail na naslovnici, chip u zaglavlju, traku na
  `/channels`, karticu u Mom računu (i njezin `VotingService.refresh`) i
  `upTarget`. Stari linkovi na `/glasanje` padaju u `errorPageBuilder`, tj.
  na naslovnicu.
- `web/_worker.js` — `VOTING_HIDDEN = true`. Env `FEATURE_VOTING` je zadano
  `true`, pa bi bez ovoga worker i dalje davao OG kartu glasanja i slao
  `/glasanje*` u native app kroz AASA. Provjereno na produkciji: AASA bez
  `/glasanje`, `/glasanje` dobiva OG naslovnice.
- Prijava e-Osobnom (Certilia) NIJE dio ove zastavice i ostaje.

Vraćanje: `voting: true`, `VOTING_HIDDEN = false`, a u
`test/feature_flags_test.dart` invarijanta `domovinaBrand` opet
`containsAll(votingRoutes)` + `isUnroutable('/glasanje') == false`. Što
točno je korisnicima bilo zbunjujuće još nije zapisano — to je prvo pitanje
prije povratka.

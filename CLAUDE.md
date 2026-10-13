# CLAUDE.md — DOMOVINA.ai

## Project Overview

Flutter web/mobile app for AI-processed Croatian podcast episodes.
All data loads from CDN (`cdn.domovina.ai`). Deployed on Cloudflare Pages.

- **Package ID**: `ai.domovina`
- **Display name**: `DOMOVINA.ai`
- **Platforms**: Web (primary), Android (+ Android TV / Leanback), iOS, macOS

## Raspored: `podcast_core` + ljuska (od 18. 9. 2026.)

Repo je pub workspace s dva paketa:

- **`packages/podcast_core/`** — SAV kod aplikacije (`lib/`, `test/`,
  `l10n.yaml`, ARB-ovi). Ovo je jezgra koju dijele DOMOVINA.ai i
  [Podcasterium](https://github.com/podcasterium/podcasterium-app); ljuska
  je uvozi samo kroz `package:podcast_core/podcast_core.dart` i poziva
  `runPodcastApp()`.
- **korijen** — DOMOVINA ljuska: `lib/main.dart` (jedan poziv),
  `lib/certilia/` (e-Osobna kao `AuthProviderPlugin` — DOMOVINA-specifično,
  vuče `flutter_certilia`), `android/`, `ios/`, `web/`, `macos/`, `assets/`
  (brend), `integration_test/`, skripte, deploy. Runtime ovisnosti navodi
  paket; korijen navodi `podcast_core` (path), `flutter_certilia`,
  `supabase_flutter` (za plugin) i platformske dev alate.

Posljedice za dnevni rad:

- **Testovi se pokreću iz paketa**: `cd packages/podcast_core && flutter test`.
  `.nightly/test-baseline.txt` je relativan na taj direktorij; nightly to zna.
- `flutter analyze` iz korijena analizira i paket (provjereno: greška u
  `packages/podcast_core/lib/src/log.dart` obara root analyze).
- **ARB i `flutter gen-l10n`**: u `packages/podcast_core/`. Generirani Dart je
  u gitu jer se paket gradi kao ovisnost, pa ga build ljuske ne regenerira.
- **Asset ugovor**: jezgra učitava logo i splash iz bundlea LJUSKE
  (korijenski `pubspec.yaml`) na putanjama `BrandConfig.logoAsset` /
  `splashAsset` (`assets/icons/domovina_ai_logo_1024.png`,
  `assets/splash/splash_full_1.png` za DOMOVINA). Brand-neutralni asseti
  (Google „G”) su u paketu i učitavaju se s `package: 'podcast_core'`.
  Testovi paketa nemaju brend assete, pa widget testovi koji ih crtaju
  koriste `test/support/fake_asset_bundle.dart`.
- `appVersion` (footer) je u `packages/podcast_core/lib/src/log.dart`;
  `scripts/deploy.sh` ga bumpa ondje.
- Dokumenti i dalje citiraju `lib/…` bez prefiksa; `verify-doc-refs.sh`
  to prihvaća kad datoteka postoji u `packages/podcast_core/`.
- **Tripwire**: `scripts/build-podcasterium-shell.sh` gradi Podcasterium
  ljusku (sestrinski repo `../../podcasterium/podcasterium-app`) nad zadanim
  `packages/podcast_core`; nightly ga vrti nakon testova kao tvrda vrata
  (preskače samo ako ljuske nema na disku). Promjena jezgre koja lomi
  white-label pada ovdje, prije taga.

## Build & Deploy

```bash
./scripts/deploy.sh          # release build + deploy + CDN purge
./scripts/deploy.sh --debug  # profile build (unminified) + deploy + CDN purge
```

Deploy script runs: `flutter pub get` → `flutter analyze` → `flutter build web` → `wrangler pages deploy` → Cloudflare cache purge → HTTP verification.

`.env` must contain `CLOUDFLARE_ZONE_ID` and `CLOUDFLARE_PURGE_TOKEN`.

**Rule (produkcija ide SAMO s `main`)**: skripta ne prosljeđuje `--branch`, pa
wrangler granu čita iz gita — deploy s bilo koje druge grane završi kao
Cloudflare **Preview**, a `domovina.ai` ostane na staroj verziji. Skriptina
verifikacija to ne uhvati: `https://domovina.ai/ -> HTTP 200` je istina i kad
ništa nije objavljeno (izmjereno 19.9.2026., deploy s `feat/podcast-core`
javio „Deployed v2.0.154" dok je produkcija servirala v2.0.153). Provjeravaj
**verziju**, ne status:
`curl -s https://domovina.ai/main.dart.js | grep -o 'DOMOVINA v[0-9.]*' | head -1`
i `wrangler pages deployment list --project-name=domovina-ai | head -3`
(stupac mora pisati `Production`, grana `main`).

## AI tim (tmux, 5 panela)

`./scripts/tim.sh` diže jedan tmux session s pet Claude Code panela:
**planner** (opus, tu čovjek promptira) → **orkestrator** (fable) →
**dev1/dev2** (opus) → **reviewer** (fable, diže se na opus za rizičan diff).
Petlja, helperi (`tim-send.sh`/`tim-read.sh`/`tim-status.sh`) i zamke:
`docs/ai-tim-tmux.md`. Uloge: `.claude/commands/{delegiraj,tim,pregled}.md`,
kickoff `/pocni` (skripta ga sama pošalje planneru; `TIM_AUTOSTART=0` gasi).

`./scripts/tim-kickoff.sh [--fresh]` (skill `/digni`) gasi stari tim, diže
novi **headless**, pošalje planneru kickoff i na kraju `exec tmux attach` u
prozoru u kojem je pokrenuta. Višelinijski prompt ide u
`.tim/kickoff-prompt.md`, planneru se šalje samo putanja — TUI svaki `\n` čita
kao submit. Bez `--fresh` se attacha na postojeći tim i prompt se NE šalje.

**Rule (prozore otvara ČOVJEK)**: agent NIKAD ne otvara, ne resizea i ne
zatvara iTerm prozore — ni `osascript`, ni `open -a`. Za novi posao timu agent
napiše `.tim/kickoff-prompt.md` i **da korisniku komandu**; korisnik otvori
prozor (⌘N) i pokrene je. Razlog je izmjeren 8.8.2026.: kad se ubije session na
koji su prozori attachani, iTermov AppleScript se trajno zablokira
(`AppleEvent timed out -1712`, do restarta iTerma) — stari tim je bio ubijen a
novi se nije digao. Uz to `create window … command` vraća `missing value`, a
`current window` odmah nakon `create window` pokaže KRIVI prozor (`set bounds`
je otišao korisnikovom Claude prozoru). Puni popis u headeru
`scripts/tim-kickoff.sh`.

Session se zove `tim-<repo-slug>` (`tim-domovina-ai`) da timovi za različite
projekte na istom stroju ne kolidiraju. **Rule**: tmux radi prefix matching na
imenima sessiona — `kill-session`/`has-session`/`attach` uvijek s `=` prefiksom
(`-t "=$(./scripts/tim-status.sh session)"`), inače možeš ubiti tuđi tim.

**Rule**: agent NIKAD ne šalje poruke u planner panel (korisnik ondje tipka) —
napredak ide u tmux status bar preko `scripts/tim-status.sh set "…"`. Review
ide PRIJE commita i PRIJE `/clear`, da dorade padnu devu kojem je kontekst još
živ.

## Git & AI Co-authoring

**Rule (AI Commit Trailers)**: Kako bi se očuvala zajednička memorija o tome koji je AI asistent (Claude Code, Antigravity, Codex, itd.) odradio koji zadatak, **SVI** agenti prilikom kreiranja Git commitova MORAJU dodati standardni *Git trailer* u poruku commita.
Format mora biti: `Co-authored-by: <Ime Agenta> (<Verzija Modela>) <bot@domena>`
Primjer: `Co-authored-by: Antigravity (Gemini 3.1 Pro) <bot@antigravity.google>` ili `Co-authored-by: Claude Code (Claude 3.7 Sonnet) <bot@anthropic.com>`.

**Rule (dokumentacija se provjerava, ne vjeruje joj se)**: prije nego preuzmeš
tuđi (ili svoj stariji) `docs/*.md` kao izvor istine, pokreni
`./scripts/verify-doc-refs.sh docs/*.md` — provjeri postoji li svaka `lib/…`
putanja citirana u markdownu i predloži pravu ako ne. Povod je izmjeren
14.8.2026.: AI-generirana analiza citirala je 33 putanje od kojih 6 nije
postojalo (imena datoteka točna, direktoriji izmišljeni), uz 186 kB generirane
ispune u istom setu dokumenata. Dokument koji NAMJERNO citira krivu putanju
omeđi s `<!-- doc-refs:ignore-start -->` / `<!-- doc-refs:ignore-end -->`.
Isto pravilo vrijedi za brojke: ako broj ima decimalu, mora postojati naredba
koja ga reproducira (primjer: `docs/podcasterium_analysis_report.md` §7).

## Nightly store build (launchd, 03:00)

`scripts/nightly-build.sh` svaku noć — ako je HEAD drukčiji od zadnjeg uspješno
izgrađenog — gradi iOS + Android iz **odvojenog git worktreea** i šalje ih na
TestFlight i Play internal. Ishod ide u Telegram grupu preko
`scripts/telegram-notify.rb`. Puna slika: `docs/nightly-build-pipeline.md`.

- **Testovi su tvrda vrata** — pad → nema uploada. Poznati crveni testovi žive u
  `.nightly/test-baseline.txt` (praćen u gitu) i izuzeti su iz vrata, ali se i
  dalje vrte; kad prorade, nightly javi da ih makneš.
- **Build broj se računa** (`max(ASC, Play, pubspec) + 1` → `--build-number`),
  pubspec se NE dira i nightly ne piše u git.
- **Rule**: sve što ide u Telegram mora kroz `telegram-notify.rb` — grupa je
  javna, a ta skripta redigira vrijednosti iz `.env`, JWT-ove i `--dart-define`
  parove prije slanja. Nikad `curl` izravno na Bot API.
- **Rule**: launchd job mora biti **LaunchAgent** (`gui/$(id -u)`), ne Daemon —
  `xcodebuild` potpisivanje traži otključan login keychain iz Aqua sesije.
- Stanje storeova u bilo kojem trenutku: `./scripts/store-status.rb`
  (review state, TestFlight `processingState`, Play rollout %).
- Produkcija iz postojećeg builda, bez re-uploada: `./scripts/play-promote.sh <vc>
  production "<tekst>"` i `./scripts/asc-submit.rb <build> --notes-hr "<tekst>" --submit`
  (bez `--submit` samo plan). Tako je 24.9.2026. poslan 2.0.154 (177).
- **Rule (odobrena verzija zatvara train)**: kad Apple odobri verziju X, svaki
  sljedeći upload s istim `version:` u pubspecu altool odbije („Pre-Release Train
  … closed"). Do 24.9. je to prolazilo kao ✅ (buildovi 159 i 160 nikad nisu
  stigli na TestFlight); sada `testflight-upload.sh` vraća exit 3 i nightly javi
  „bumpaj verziju".
- **Rule (build artefakti NE idu izravno na `/Volumes/DOMOVINA2TB`)**: taj exFAT
  ima alokacijski blok od **512 KB**, pa je Gradle home od 14 GB u 156 000
  datoteka pri kopiranju narastao na **41 GB** (izmjereno 2026-08-13). Sve što
  ima puno sitnih datoteka ide na APFS disk `/Volumes/DOMOVINA1TB`
  (nightly: `domovina_build/{gradle,derived-data}`, Android emulatori:
  `android/{system-images,avd}`). Sparsebundle `DOMOVINA_BUILD` je ugašen
  26.9.2026. (I/O ~6 MB/s). Cache i emulatori se ne sele: obriši i napravi
  iznova.

## Farma uređaja + smoke vrata (od 13.10.2026.)

Na Mac mini su trajno spojena 2 Androida (moto g86 / Android 16, edge 30
ultra / Android 15) i 2 iPhonea (SE 2nd, 12 mini). Nightly nakon uploada
vrti `scripts/nightly-smoke.sh <build>`: na svakom uređaju **release smoke**
(isti AAB / development export istog iOS archivea, deep linkovi, crash,
ANR, `FLUTTER ERROR` iz release loga) i **ui smoke**
(`integration_test/smoke_test.dart`, portrait + landscape, reprodukcija
mora napredovati, overflow obara test). Ishod u Telegram i u
`.nightly/smoke/builds/<build>.txt`. Plan, mjerenja i zamke:
`docs/plans/2026-10-13-smoke-testovi-na-uredajima.md`.

**Rule (vrata su na promociji, ne na uploadu)**: `asc-submit.rb` i
`play-promote.sh … production` odbijaju build bez `result=pass`
(`scripts/smoke-gate.sh`). Play production ide kao staged rollout 20 %
(`scripts/play-rollout.sh` podiže/zaustavlja), App Store kao phased
release 7 dana. Iznimke su izričite: `--skip-smoke-gate`, `SKIP_SMOKE_GATE=1`,
`ROLLOUT=1`, `--no-phased`.

**Rule (uređaj se zaključava)**: tko koristi uređaj farme drži
`~/.device-farm/locks/<id>` (mkdir). 13.10. je druga aplikacija
(„DOMOVINA Kamera”) usred smokea preuzela prednji plan i test je visio
20 min. Uređaji: zaključavanje zaslona „Ništa” (iza keyguarda Android
aplikaciji ne pušta mrežu), Auto-Lock „Nikad”, Cloudflare WARP ugašen
(blokira mDNS prema iPhoneu).

**Rule (iOS deep link u testu)**: `ai.domovina:///v/<id>` — tri kose crte.
S dvije je `v` host i ruter dobije samo `/<id>`.

## Tripwire: registar podcasta ↔ glasački bazen (launchd, 08:30)

`domovina_ai.vote_candidates` je **snimka** `fetch.domovina.tv/data/podcasts_registry.json`,
ne živi pogled — podcast dodan u registar ne stigne u bazu dok se ne pokrene
`sync_voting_candidates.mjs --commit`. Izmjereno 25.8.2026.: registar je 17 dana
nosio 37 kandidata (AbbaCast među njima) kojih u bazi nije bilo, korisnici za njih
nisu mogli glasati, i ništa to nije javilo.

`scripts/voting-drift-check.sh` (launchd `ai.domovina.voting-drift`) svako jutro
usporedi registar i bazu; tiho je kad su poravnati, na drift sinkronizira i
javi ishod u Telegram.
Sama usporedba je `node sync_voting_candidates.mjs --check` u fetch repou —
**filtar kandidata (§3) živi na jednom mjestu**, u sync skripti, i tripwire ga
ne prepisuje. (Reimplementacija filtra je pri prvom pokušaju dala 164 umjesto
218 kandidata.) `--check` preskače yt-dlp i CDN pa traje sekundu; exit 0 =
poravnato, 1 = drift, 2 = ne mogu provjeriti.

**Rule (od 2.9.2026. tripwire sinkronizira sam)**: launchd job prosljeđuje
`--sync`, pa na drift sam pokrene `--commit`. Prije toga je samo javljao i
AbbaCast je 5 dana stajao u glasanju iako je 28.8. ušao u pipeline. Opravdanje:
registar je izvor istine, baza njegova projekcija, a sync je idempotentan
rekoncilijator — čovjek tu nije odlučivao ništa osim da prepiše isti izračun.
Ručno pokretanje skripte i dalje NE piše bez `--sync`.

**Rule (exit kodovi su ugovor)**: `--check` vraća 0 = poravnato, 1 = ima drifta,
2 = ne mogu provjeriti. Do 2.9.2026. je nečitljiva baza rušila `existing.length`
TypeErrorom i izlazila s 1 — tripwire je prolaznu mrežnu grešku javljao kao
drift, a pod `--sync` bi na nju i pisao. Ne miješati „ne znam" s „ima drifta".

**Rule (onboardan ≠ povučen)**: kandidat koji ispadne iz §3 filtra dobiva status
po razlogu — `tracking.enabled === true` u registru → `onboarded`, sve ostalo
(zapis nestao, status ugašen) → `withdrawn`. `onboarded` se NIKAD ne vraća u
bazen ni ako se zastavica vrati na false. `--commit` nakon pisanja sam provjeri
konvergenciju (`verifyConverged`) i padne s 2 ako baza nije poravnata: pisanje je
7 HTTP poziva pa nije atomarno, i bez te provjere polupisano stanje ostane
nezamijećeno do sutrašnjeg tripwirea. Puna atomarnost traži jednu Postgres
funkciju nad cijelim payloadom (95,8 kB za 217 kandidata) — nije napravljeno.

## Known Issues & Gotchas

> **Web delivery, rendering & caching** (service worker staleness, cache-busting
> header strategy, channel-list scroll perf, prefetch race, Flutter-web image
> debug decision tree) — vidi `docs/web-delivery-and-rendering.md`.
>
> **Tech-stack odluka (Flutter vs Expo/RN, 2026)** — zašto OSTAJEMO na Flutteru
> unatoč web-bolu, i kad bi Expo bio bolji: `docs/tech-stack-assessment-flutter-vs-expo.md`.
> TL;DR: ne prepisivati; web zamke su omeđene i dokumentirane.

### Boot splash — miče se SAMO na prvi frame (od 9.10.2026.)

`#boot-intro` u `web/index.html` pokriva sve do `flutter-first-frame`. Fiksni
timeout od 6 s ga je na Slow 4G micao 13 s prije Fluttera (bijela stranica s
legal footerom). Pozadina `html` i splasha = `scaffoldBackgroundColor` teme
(čita `localStorage['theme_mode']`). Mjerenja i odluke:
`docs/2026-10-09-boot-splash.md`, reprodukcija `scripts/measure-boot.py`.

**Rule**: splash se ne miče timeoutom koji ne zna je li Flutter tu; osigurač
kreće tek kad je kod aplikacije preuzet. Mijenjaš li boje teme, mijenjaj i
`--boot-bg` u `index.html`. Opis i linkovi u splashu ostaju u izvornom HTML-u
(Google OAuth provjera). Citat u splashu je doslovna kopija TV skupa
(`defaultBibleVerses` + Mt 10,26-27) — mijenja se samo uz fact-check na
biblija.ks.hr, čuva `test/boot_splash_verses_test.dart`.

### Pretraga naslovnice — tri izvora + tekst ne pod scale transformom (od 13.10.2026.)

Paleta (`search_overlay.dart`) spaja lokalni sloj, Meili `episodes` i
semantiku po YouTube ID-u (`services/unified_search.dart`) — Meili je jedini
full-text izvor za ad-hoc epizode (`_unlisted`) kojih nema u listinzima.
Mjerenja, zamke i otvoreno: `docs/2026-10-13-pretraga-mali-gpu-i-pametni-search.md`.

**Rule (tekst ne ostaje pod scale transformom)**: skwasm na Mali GPU-u (moto
g86) pod `ScaleTransition` krivo crta glifove — razmak nestane („fra stje" →
„frastje"), „d" izađe kao „đ". Korisnik to prijavi kao „ne mogu upisati riječ".
Dijalozi se otvaraju fadeom; čuva `test/search_overlay_test.dart`.

### SharedPreferences crashes on web release builds

`SharedPreferences` throws `MissingPluginException(No implementation found for method getAll on channel plugins.flutter.io/shared_preferences)` in dart2js release mode. The method channel plugin registration is stripped during minification.

**Fix**: Web uses `window.localStorage` directly via `package:web`. Native (iOS/Android/macOS) uses `SharedPreferences` normally. Gated by `kIsWeb` in `home_screen.dart`.

**Rule**: Never use `SharedPreferences` on web. Always check `kIsWeb` and use `localStorage` for browser persistence.

### ensureSemantics na webu — stara zabrana OPOVRGNUTA (2026-07-22)

Povijesno pravilo "ensureSemantics crasha release web build" retestirano na
Flutter 3.41.6: **crash se NE reproducira** ni na skwasm (`--wasm`) ni na
dart2js putanji, ni s pozivom odmah nakon `ensureInitialized()`. Originalna
atribucija (2026-03-31) gotovo je sigurno bila kriva — u istom periodu su
postojali SharedPreferences/flutter_svg crashevi na minificiranom buildu.

Semantics ipak NIJE uključen svima uvijek, zbog poznatih **bihevioralnih**
web bugova (flutter/flutter#163576 P1 — click-through kroz preklapajuće
widgete). Trenutni mehanizam u `lib/src/app.dart` (`runPodcastApp`):

- `?a11y=1` query param → `ensureSemantics()` odmah (za Playwright/Cypress
  e2e i ručnu inspekciju a11y DOM-a).
- Screen readeri: Flutterov ugrađeni `flt-semantics-placeholder` (pali
  identično stablo — potvrđeno, 73 čvora na home).
- `Semantics(identifier: 'pinka-*')` sidra na doniraj ekranu izlaze kao
  `flt-semantics-identifier` atribut. Vidi `docs/e2e-testing.md`.

**Rule**: prije eventualnog always-on uključivanja ručno protestirati
overlay klikove (search palette, share sheet) zbog #163576.

### flutter_svg crashes on web

`flutter_svg` (`SvgPicture.asset`) causes `Uncaught Error` on web builds. Replaced with `Image.asset` using PNG version of the logo.

**Rule**: Use PNG (`Image.asset`) instead of SVG for in-app images on web.

### Fontovi na webu — `<link>` u index.html NE oblikuje Flutter tekst

canvaskit/skwasm ne čita `@font-face` iz dokumenta (to je radio samo stari HTML
renderer). Sve dok je `AppTypography` na webu postavljao goli
`fontFamily: 'Playfair Display'` i računao na `<link>` u `web/index.html`,
Flutter je taj font tražio među **registriranima**, ne nalazio ga i padao na
ugrađeni fallback: naslovi i wordmark su se na webu crtali sans-serifom umjesto
Playfairom (izmjereno 25.8.2026. na produkciji), a pojedini glyphovi znali su
nestati dok asinkroni Noto fallback ne stigne.

Fontovi se zato registriraju kroz `google_fonts` na **svim** platformama.
`web/index.html` `<link>` ostaje — njime se crta HTML boot-intro splash (pravi
DOM, prije Fluttera) i ugrije `fonts.gstatic.com`.

**Rule**: novi font/težina u `lib/theme/typography.dart` mora ići i u
`AppTypography._usedVariants`. `main()` zove `startPreload()` odmah, a
`awaitPreload()` pred `runApp` — inače se prvi frame crta fallbackom pa cijela
stranica prelomi kad pravi font stigne.

### Hero na naslovnici se otkriva TEK kad je izbor konačan

`ChannelCache` javlja svakim učitanim kanalom, a `HomeFeed.pickFeaturedCarousel`
rangira po **trenutno** učitanom bazenu. Hero je zato tijekom prefetcha
prelistavao kandidate (bljeskanje + skakanje stranice). Sada
`_ChannelGridViewState` latcha izbor jednom — kad je `channelCache.done` (ili
nakon 6 s grace prozora, uz `hasMinimumData`) — i više ga ne dira.

**Rule**: `HeroSkeleton` mora biti **točno jednako visok** kao `HeroCarousel`,
uključujući `kHeroControlBarHeight` (zato karusel s jednim pickom zadržava
praznu kontrolnu traku). Kontrakt čuva `test/hero_slot_layout_test.dart`;
mijenjaš li hero layout, mijenjaj i skeleton. Testni font je širi od Intera pa
test namjerno drži meta red u jednom retku.

### Universal/App Links NE smiju hvatati auth callback rute

Web OAuth povratak (`GoTrue → https://domovina.ai/auth/callback`) je
cross-origin redirect — ako ga native app presretne kao universal/app link,
web prijava se prekine otvaranjem appa (bug viđen na iOS-u 2026-07-22).

- **iOS** (`web/_worker.js` AASA_JSON): `components` s `exclude: true` za
  `/auth/*`, `/login-callback`, `/youtube-claim/*` + legacy `NOT` u `paths`.
  Apple CDN/uređaji cachiraju AASA — propagacija tek nakon reinstalacije
  appa ili do ~tjedan dana.
- **Android** (`AndroidManifest.xml`): intent filter nema exclude sintaksu —
  App Links su ALLOWLIST content putanja (`/v/`, `/m/`, `/c/`, `/p/`,
  `/handoff`, `/`, `/channels`). Auth rute namjerno izostavljene.
- Native login flow koristi `ai.domovina://` custom scheme — na njega ovo
  ne utječe.

**Rule**: nova javna content ruta → dodaj u OBA popisa (AASA components +
Android intent filter). Nova auth/callback ruta → NE dodavati, i provjeri
da je pokrivena AASA exclusionom. Deploy skripta ima tripwire koji provjeri
live AASA exclusion.

### Auth return-to (povratak na izvornu rutu nakon prijave)

Prije OAuth/magic-link full-page redirecta `AuthService` sprema path+query u
localStorage (`auth_return_to`); `AuthCallbackScreen` vraća korisnika tamo
umjesto na `/`. Čista logika u `lib/services/auth_return_path.dart`,
kontrakt čuvaju unit testovi u `test/auth_return_path_test.dart`
(open-redirect guard + callback-loop guard). Ne zaobilaziti sanitizaciju.

### Auth nudge NIKAD ne prekida reprodukciju

Onboarding momenti M1 (snackbar o napretku) i M2 (auth sheet nakon 30 s
slušanja) obrisani su 2026-07-25 — modal preko videa prekida upravo ono zbog
čega je korisnik došao. Zamjena je `widgets/anonymous_signin_bar.dart`: trajna
slim traka u `bottomNavigationBar` ekrana epizode, vidljiva samo dok je
`AuthService.instance.isAnonymous`.

**Rule**: novi nudge (prijava, pretplata, install) → persistent surface
(traka/kartica/chip). Modal SAMO kad ga je korisnik svojim tapom pozvao;
snackbar SAMO kao potvrda korisnikove radnje (kao M3 na favorit).

**Rule (safe area na dnu)**: kad se u `bottomNavigationBar` slaže više traka
koje se nezavisno pale/gase (gost traka, `PinkaSupportBar`, mobilna nav),
donji `SafeArea` ide na zajednički Column — nikad na pojedinu traku. Inače je
ili duplo (dvije sestre primijene isti inset) ili nula (sve se sakriju).

Prolaz kroz auth UI/UX + otvoreni backlog: `docs/auth-ux-backlog.md`.

### Bez anonimnih prijava — gost nema sesiju (LIVE od v2.0.172)

Anonimne Supabase prijave su ugašene (99 % korisnika bilo je anonimno, 3
konverzije). Bez sesije korisnik je **gost**: javno čita anon ključem, a
donacija ide gostujućom granom `pinka-contribute` (Supabase klijent sam šalje
anon ključ kao bearer; limit 30/sat/IP → `rate_limited`). Ugovor:
`domovina-api/docs/sponzorski-trenuci-ugovor.md` §9. Postojeće anonimne
sesije rade dok ne isteknu (`AuthService.isAnonymous` je `true` i za gosta).

**Rule**: klijent NIKAD ne zove `signInAnonymously` — ni pri pokretanju, ni
nakon odjave/brisanja računa, ni prije edge funkcije. Čuva
`test/no_anonymous_sign_in_test.dart`. Što traži pravi račun (mjesto na zidu,
sponzorski checkout, upload loga) dobiva `401 login_required` →
`PinkaLoginRequired` i nudi prijavu (`onSignInRequested` / `showAuthSheet`),
nikad generičku grešku. Sponzorski checkout traži prijavu PRIJE forme — web
OAuth je full-page redirect i upisana forma ga ne bi preživjela.

**Rule (redoslijed)**: ovaj frontend NE ide u produkciju prije koraka 1
backendovog redoslijeda (`domovina-api` zaključak §7) — stari backend
donaciju bez sesije odbija. Turnstile namjerno NIJE ugrađen (iframe pod našim
COEP-om radi samo u Chromiumu, native nema SDK), pa `TURNSTILE_SECRET_KEY` na
backendu mora ostati nepostavljen.

### Backend placement — Cloudflare Worker vs Supabase Edge Function

**Rule (decide by purpose):** does the backend code read/write our Postgres
(`api.domovina.ai`, Supabase on Coolify) for a logged-in user, or need the
service role / GoTrue admin / RLS context?

- **No** (pure proxy / presentation / third-party SaaS that hides a vendor key
  but doesn't touch our DB) → **Cloudflare Pages Worker** (`web/_worker.js`).
  Examples: SPA routing, OG injection, the Cal.com proxy (`/api/cal/*`,
  `CAL_API_KEY`). Never put `SUPABASE_SERVICE_ROLE_KEY` or DB writes here.
- **Yes** → **Supabase Edge Function** (`domovina-api/supabase/functions/`),
  where the service role is auto-injected and lives only on Coolify. Examples:
  `revenuecat-webhook` (writes entitlement state), `pinka-webhook`, auth bridges.

Full rationale + examples: `domovina-api/docs/backend-architecture.md`.

### Cloudflare Pages pretty URLs

Cloudflare auto-strips `.html` extensions (`/social-test.html` → `/social-test`). The worker in `_worker.js` checks for `.html` files in ASSETS before falling back to SPA routing.

### Cache purge required after deploy

Cloudflare CDN caches aggressively. Always purge cache after deploy (the deploy script does this automatically). Without purge, users may see stale versions.

### Brzi start videa — `video_h264_fmp4.mp4` (od 11.10.2026.)

`moov` u `video_h264.mp4` indeksira svaki uzorak (2,7 MB za sat epizode), pa je
prvi frame na Slow 4G stizao za 15,9 s. Pipeline (KORAK 12.5) za NOVE epizode
uploada i iste struje kao fragmentirani MP4 + `sidx` (zaglavlje ~11 KB → 2,6 s).
`resolveMedia` ga bira SAMO kad ga `episode.json` navodi; stari katalog se ne
backfilla. Mjerenja i reprodukcija: `docs/2026-10-11-brzi-start-videa-fmp4.md`.

**Rule (WebKit ograđen)**: `isWebKitBrowser()` (Safari, svi iOS preglednici)
ostaje na `video_h264.mp4` dok se fmp4 ne isproba na iPhoneu. Native (libmpv) i
Chromium su izmjereni.

**Rule (screenshotovi: PNG je original, WebP je prikaz)**: od 10.10.2026.
pipeline (KORAK 12.65) uz PNG 1920×1080 uploada `{ts}-960.webp` i oznaku
`data/{id}/screenshots_webp.json`; app bira WebP samo kad je bundle navodi.
PNG se nikad ne briše ni ne prepisuje — trajni full-HD originali. Do prvog
`playing` vidi se samo screenshot prve sekcije i one iz `/t/<sec>`
(`DeferredScreenshots`), a titl se ne crta prije stvarne pozicije > 0.

**Rule (fmp4 bez `sidx` ne radi)**: Chrome ga skenira fragment po fragment i ne
krene ni u 2 min. Pipelineov `verifyFmp4` odbija takav izlaz — ne zaobilaziti.

### Android TV — AV1 codec ne-radi u hardware decoder-u

EON SDSTB02 (Amlogic, Android 11) i većina Android TV box-ova prije ~2024.
godine **nemaju funkcionalan AV1 hardware decoder** unatoč tome što
`av1_mediacodec` postoji u sistemu. Pokušaj otvaranja AV1 streama daje:

```
ffmpeg/video: av1_mediacodec: Both surface and native_window are NULL
ffmpeg/video: av1_mediacodec: Unsupported or unknown profile
```

**Trenutni video.mp4 na CDN-u je AV1 Main @ 640×360**. Software decode
radi (bitrate je nizak ~94 kbps), ali zahtijeva eksplicitno `hwdec=no`
u libmpv konfiguraciji. Vidi `lib/screens/tv/tv_episode_screen.dart`
gdje se to setira preko `player.platform.setProperty('hwdec', 'no')`.

**RIJEŠENO** (provjereno 15.8.2026., ovo je nekad bio TODO): pipeline producira
H.264 verziju kao **`video_h264.mp4`** (podvlaka, ne točka) paralelno s
`video.mp4`/AV1. Klijent bira sam — `DataService.resolveMedia()` probe-a redom
`video_h264.mp4` → `audio.mp3` → legacy `video.mp4`. H.264 hardware decode radi
univerzalno od Android 4 nadalje.

**Rule**: probe URL MORA nositi cache-buster (`videoH264ProbeUrl`) — CDN cachira
404 četiri sata, pa bi jedan prerani probe zaključao fallback na cijeli prozor.

### Android TV lokalni emulator (dev loop)

EON-matched emulator na Mac miniju za brzu TV layout/D-pad iteraciju. Auto-detektira
se kao Leanback (bez `FORCE_TV`), ali **ne reproducira EON perf/jank** (Mac GPU +
arm64 native). Setup, svakodnevne komande i objašnjenje rezolucije (960×540 dp je
logički dp prostor uz dpr 2.0, NE downsampling — EON crta native 1920×1080):
`docs/android-tv-emulator.md`.

**Rule**: `EON_TV_API31` živi na `/Volumes/DOMOVINA1TB/android/` kao i ostali
emulatori; stari `DOMOVINA_ANDROID.sparsebundle` više ne postoji (26.9.2026.).
Ako AVD fali, napravi ga iznova po `docs/android-tv-emulator.md`, ne seli ga.
Perf mjeriš samo na fizičkom EON-u.

### Native Android splash je static (nije rotirajuc)

Pokušali smo runtime rotaciju biblijskih citata u native splash-u (5
različitih pristupa), ali Android <12 starting window se ne može
runtime-modificirati (komponira se iz manifest teme PRIJE Activity-a).
Puna istraga: `docs/splash-randomization-research.md`. Verdict: nemoguće
na API <12 bez vidljivih nuspojava (activity-alias rotacija razbacuje
ikonu po Leanback Apps row-u).

**Trenutna splash arhitektura** (vidi `docs/splash-bible-citations.md`):
- Native splash = premium full-frame 4K PNG (`splash_full_1.png`,
  Mt 10,26-27 KS Jeruzalemska Biblija).
- Flutter `TvBootSplash` prikazuje istu sliku + "Učitavanje…" progress
  za seamless native→Flutter kontinuitet.
- Generiranje: `scripts/generate-premium-splash-taglines.py` (PIL auto-fit;
  `--all` za svih 14 citata). Mirror u `assets/splash/` za Flutter asset.

**Rule**: ne dirati `MainActivity.kt` za splash rotaciju — nemoguće. Za
promjenu native splash teksta: edit `VERSES` u Python skripti, rerun,
rebuild. Citati MORAJU biti KS Jeruzalemska Biblija (biblija.ks.hr), ne
Magisterium AI raw — vidi `docs/splash-bible-citations-factcheck.md`.

### Flash između native i Flutter splash-a — NormalTheme windowBackground

`NormalTheme.windowBackground` MORA biti isti drawable kao
`LaunchTheme.windowBackground` (`@drawable/launch_background`). Inače Flutter
theme swap pri prvom frame-u zamijeni splash sliku za crno → vidljiv flash.
Vidi `values/styles.xml` + `values-night/styles.xml`.

### Impeller disabled na svim Android buildovima — Skia renderer

`io.flutter.embedding.android.EnableImpeller=false` u AndroidManifest.xml.
Razlog: Impeller shader compile na low-end Amlogic GPU (EON). Trenutno
koristimo Skia. Tradeoff + buduće opcije (SkSL warmup) + cijela TV perf
analiza: `docs/android-tv-performance.md`.

**Rule**: ne re-enable-ati Impeller bez re-mjerenja cold starta na EON-u.
NE koristiti `FlutterEngineCache` engine pre-warm — collide-a s
audio_service `provideFlutterEngine()` (dupli `main()`). Detalji u perf docu.

### media_kit web — fullscreen/tap/subtitle gotchasi

media_kit (2.0.1) na webu ima 4 zamke; sve ih rješava zajednički wrapper
`lib/widgets/episode_video.dart` (koriste ga VideoPanel i episode_simple_screen):

1. Ulazak u fullscreen pauzira video — enterFullscreen pusha novu rutu s novim
   `Video` widgetom pa se `<video>` re-parenta u DOM-u (remove+insert = pauza
   po HTML spec-u). Fix: auto-resume nakon tranzicije (retry 300/900 ms).
2. Esc izađe iz browser fullscreena, ali Flutter fullscreen ruta ostane —
   paket nema `fullscreenchange` listener. Fix: `lib/services/browser_fullscreen.dart`
   (conditional import web/stub) + exit preko `GlobalKey<VideoState>`.
3. `playAndPauseOnTap` je default OFF — klik na video ne radi ništa bez toga.
4. `setSubtitleTrack` na webu traži VTT (`<track>` element; SRT ne radi) i u
   sourcu piše "UNTESTED". Titlove rendamo SAMI: `diarized.srt` → cue text u
   `SpeakerTimeline` → overlay kroz `controls:` builder (radi i u fullscreenu).

**Rule**: za video u episode ekranima koristi `EpisodeVideo`, ne goli `Video`.
YouTube embed mode = službeni youtube-nocookie iframe (`lib/widgets/youtube_embed.dart`,
web-only) — NIKAD ad-stripping ili stream extraction (YouTube ToS).

### Kontrole reprodukcije — brzina, seek-undo, rotacijski fullscreen

Uvedeno 2026-07-27 (plan `docs/plans/2026-07-27-playback-overhaul.md`, zaključak
i otvoreni dug u `-zakljucak.md`). Servisi: `services/playback_speed.dart`
(globalna brzina po uređaju, kružno kroz `kPlaybackRates`),
`services/seek_undo.dart` (detekcija RUČNOG skoka nad `player.stream.position`),
`services/screen_orientation.dart`. Dijeljeni widgeti:
`widgets/playback_controls.dart`.

**Rule**: nova kontrola playera ide u `playback_controls.dart` i mora se
pojaviti na **tri** mjesta — video traka, `video_panel.dart` i `_PlayerTab` u
`episode_simple_screen.dart`. Zadnja dva su jedina putanja za **audio-only**
epizode, gdje `EpisodeVideo` uopće ne postoji.

**Rule (stanje kontrole ide kroz singleton, ne kroz propove)**: iste kontrole
crtaju tri odvojena stabla, a na mobitelu je player u bočnom panelu — prop
drilling se tu neizbježno negdje ispusti. `PlaybackSpeed`, `BackgroundPlayback`
i `PlayerMute` su zato singletoni; `VideoPanel` nema parametre za njih.
(Povijest: `mutedAutoplay`/`onUnmute` su bili propovi i **nedostajali su na
obje mobilne pozivne točke** — unmute na mobitelu nije postojao.)

### Muted autoplay — browserska politika, ne naš bug

Autoplay **sa zvukom** dopušten je samo uz prethodni gesture: Chromium traži
klik/tap po domeni u toj sesiji (ili MEI prag na desktopu / PWA na home
screenu), WebKit traži `muted` element ili audio-less stream i **pauzira
reprodukciju ako se element odmuta bez gesturea**. Hladno otvoren share link
(`/v/<id>/t/<sec>`) nema ništa od toga → `openAndResume` pada na muted
autoplay i to zapiše u `PlayerMute` singleton.

Iz tog se stanja izlazi ISKLJUČIVO korisnikovim tapom. Zato UI mora ponuditi
tri izlaza: `UnmuteOverlay` preko slike, `MuteToggleButton` u trakama, i (na
mobitelu) gumb „Video" u donjoj traci koji se pretvori u „Uključi zvuk" — jer
je on jedina površina koju korisnik vidi dok je player u zatvorenom draweru.

**Rule (mute na webu = `muted` property, NIKAD `volume`)**: na iOS-u
`HTMLMediaElement.volume` nije zapisiv (setter je no-op, getter uvijek 1), a
media_kitov `setVolume` usput **skida** `muted` flag — pa `setVolume(0)` na
iPhoneu ne mutira ništa i autoplay ostane odbijen. Mute na webu ide preko
`services/media_element_mute_web.dart` (`<video>.muted`); `player.setVolume`
je samo native putanja i fallback.

**Rule (širinski budžet trake)**: `MuteToggleButton` ide SAMO u mobilnu
media_kit traku — desktop varijanta već ima `MaterialDesktopVolumeButton`, a
osmi slot bi joj probio 328 dp (`test/playback_bar_layout_test.dart`).

**Rule**: prag detekcije skoka ne spuštati ispod 1 s — `position` stream fira
~5×/s, pa je pri brzini 2,0× prirodni pomak ~0,4 s i niži prag bi generirao
lažne skokove. Programski seek (resume, tap na poglavlje, sam Undo) mora ići uz
`SeekUndo.suppress()`.

**Rule**: fullscreen su **tri** putanje, ne jedna — pravi landscape na nativeu
(`SystemChrome`, probija sistemsku bravu rotacije), `screen.orientation.lock`
na Android Chromeu, vizualna rotacija (`RotatedBox`) ondje gdje oboje padne
(iPhone Safari/Chrome). Desktop široki viewport ostaje na media_kitovoj ruti.
Naša ruta jednako re-parenta `<video>` → koristi postojeći
`_resumeAfterTransition`, ne piši novi.

**Poznato, nepopravljeno**: `MediaSession.clear()` na webu ne postavlja
`playbackState = 'none'`, pa iOS ostavlja *mrtvu* stavku u Dynamic Islandu
(vidljiva, tap ne radi ništa). Dizajniran popravak i zamke re-registracije:
`docs/ios-background-playback.md` §4.3. Tap na Dynamic Island koji otvara
aplikaciju je namjerno iOS ponašanje — to nije bug i ne može se isključiti dok
želimo pozadinski zvuk.

### Faza obrade epizode — `EpisodeStatus`, ne „AI obrada nije gotova"

Epizoda u railu „Upravo stiglo" može biti u bitno različitim stanjima, a do
26.8.2026. su sva govorila istu rečenicu. Izmjereno tog dana na produkciji:

| epizoda | `info.json` | medija | AI | što je korisnik vidio |
|---|---|---|---|---|
| `UclibQB3SZM` | 404 | — | — | „nije pronađena na CDN-u" (slijepa ulica) |
| `ZYG_ksNDl3s` | ✓ | 404 | — | „Prikazujemo samo **video**…" (videa nema) |
| `DnzG2OvRflI` | ✓ | `video_h264` | — | crveni „Gledaj na YouTubeu" iako video IMAMO |

`lib/models/episode_status.dart` uvodi pet faza (`queued` → `fetched` →
`mediaReady` → `transcribed` → `published`) + listu koraka koju crta
`widgets/episode_status_card.dart` (detaljni ekran, `_InfoTab` jednostavnog).
Puna slika (mermaid prijelazi, odbačene alternative, otvoreni backend dug):
`docs/2026-08-26-episode-processing-status.md`. Koliko je epizoda zaglavljeno
gdje: `node scripts/audit-episode-stages.mjs`.

**Rule (faza se MJERI, ne čita iz listinga)**: `EpisodeStatus.measured(...)`
(preko `EpisodeData.status`) je jedini autoritet — `info.json` presence, probe
medije, prisutnost artefakata. `pipeline` zastavice iz channel listinga su
producentova namjera i lažu u oba smjera (`DnzG2OvRflI` ima video uz
`has_transcript:false`; `UclibQB3SZM` ima listinganu `thumbnail` putanju koja
vraća 404). `EpisodeStatus.fromPipeline(...)` postoji SAMO za oznake na
karticama u railovima/channel listi, gdje ničeg boljeg nema.

**Rule (izostanak zastavice NIJE informacija)**: `fromPipeline` smije tvrditi
fazu samo kad je neka zastavica **podignuta**; inače je `stageCertain == false`,
`badge()` vraća `null` i call-site padne na neutralno „U obradi". Prva izvedba
je iz samih `false` vrijednosti zaključila „Preuzimamo" i tu oznaku dala svakoj
epizodi u railu — netočno za 12 od 20. Danas pipeline zastavice piše sve
odjednom na kraju (0 od 20 ima ijednu među-zastavicu), pa je neutralna oznaka
jedini pošten izlaz.

**Rule (`info.json` 404 ≠ 404)**: `VideoNotFoundException` vodi na
`_QueuedEpisodeScreen`, koji epizodu potraži u channel listinzima
(`channelCache.findVideoAsync`, kanali poredani po svježini, staje na prvi
pogodak). Nađe li je — naslov, kanal i YouTube player. Ne nađe li — tek tada
prava 404. Embed se NE nudi bez tog pogotka, inače bi `/v/<bilo-koji-YT-ID>`
ugrađivao proizvoljan tuđi video pod našim brandom.

### In-app YouTube za epizode bez medije — `InAppYouTubePlayer`

Facade (poster + play gumb) koji na tap zamijeni sam sebe službenim
`youtube-nocookie` iframeom (`widgets/youtube_embed.dart`). Dva razloga za
facade umjesto odmah-iframea: prvi tap JEST korisnikova gesta pa embed krene sa
zvukom (ista politika kao u „Muted autoplay" gore), a tko ne klikne ne plati
~1 MB YouTube playera na stranici koja mu je ionako samo status.

- Web (`youTubeEmbedSupported`) + `info.playable_in_embed` → iframe u aplikaciji.
- Native, ili vlasnik isključio ugrađivanje → tap otvori youtube.com, uz
  objašnjenje (`episodeEmbedBlocked`) zašto korisnika šaljemo van.

**Rule (COEP zabranjuje SVAKI tuđi iframe)**: `web/_worker.js` šalje
`Cross-Origin-Embedder-Policy: credentialless` jer bez cross-origin izolacije
Flutter učita jednodretveni `skwasm.wasm` i rasterizira na glavnoj niti
(uzrok janka iz `docs/web-delivery-and-rendering.md` §1). Pod COEP-om ugniježđeni
dokument mora **sam** slati COEP — YouTube ga ne šalje, pa frame bude odbijen
(„refused to connect"). Jedini izlaz je `<iframe credentialless>` (Chrome/Edge
110+), i atribut se MORA postaviti **prije** `src`. Safari i Firefox ga nemaju,
pa `youTubeEmbedSupported` ondje vraća false i facade otvori youtube.com umjesto
crne plohe. **Nova integracija treće strane ide preko API-ja, ne iframea** (kao
`cal_booking_native.dart` nad Cal.com API-jem). Puna analiza s mjerenjima:
`docs/web-delivery-and-rendering.md` §6.

**Rule**: embed se nudi samo dok kod nas NEMA što pustiti
(`EpisodeStatus.needsExternalSource`) — inače bi na stranici bila dva playera.
Kad medija JEST na CDN-u, primarna radnja je NAŠ player („Gledaj epizodu" →
bočni panel na uskom ekranu), a YouTube pada na tihu tekstualnu poveznicu.
Sintetički ID-evi (X izvor, `_yt_matched:false`) nemaju YouTube video iza sebe
i ne smiju se ugrađivati.

**`/yt/:videoId` (od v2.0.169)**: samostalni ekran koji pušta BILO KOJI
YouTube video kroz isti službeni embed (native: `webview_flutter` s `baseUrl`
na domovina.ai zbog Referera) + gumb na obrađenu epizodu. Reklame ostaju.
Varijanta bez reklama je zapisana i NIJE odobrena; native još nije isproban:
`docs/plans/2026-10-06-youtube-bez-reklama-plan-b.md`.

### Cachiran 404 na CDN-u — web vidi 404, native 200 (isti URL)

Per-epizoda datoteke (`data/<id>/*.json`, `diarized.srt`) su `immutable` i
dohvaćaju se BEZ cache-bustera. Ali dok ih pipeline još nije uploadao,
Cloudflare cachira i **404** — i to u zasebnom `Vary: Origin` zapisu. Preglednik
šalje `Origin` na svaki cross-origin fetch, `dart:io` klijent (iOS/Android/
macOS) ga ne šalje, pa ista epizoda čita DVA cache zapisa i dobiva dva
odgovora. Dovoljan je jedan posjet stranici prije uploada da web ostane
zaključan na 404.

Izmjereno 19.9.2026. na `aue1GuuMsbA` i `70uXR4DDZiE`: `info.json` je uz
`Origin: https://domovina.ai` vraćao 404 (`cf-cache-status: HIT`, `age`
20 972 s uz `cache-control: max-age=3600`), a bez tog zaglavlja 200. `loadInfo`
je zato na webu bacao `VideoNotFoundException` → epizoda je padala na
`EpisodeStage.queued` („epizoda još nije preuzeta") uz YouTube embed, dok se u
iOS aplikaciji uredno reproducirala. Uzorak od 360 epizoda: pogođene 2 — obje
među najsvježijima, tj. točno one koje se klikću iz raila „Upravo stiglo".

**Rule (404 se ne vjeruje iz prve)**: `DataService._get` na 404 ponovi zahtjev s
`CdnConfig.bustCache(url)` (isti 5-minutni bucket kao probe-ovi) — druga cache
adresa ide na origin. Tek drugi 404 znači da datoteke nema. Cijena je jedan
dodatni zahtjev po assetu koji ionako nedostaje, nula na uspjehu. Kontrakt čuva
`test/data_service_stale_404_test.dart`. Novi per-epizoda dohvat ide kroz
`_get`/`_fetch`, nikad izravno kroz `http.get`.

Puna slika (mjerenja, dijagram grana, odbačene alternative):
`docs/2026-09-19-cachiran-404-vary-origin.md`.

**Rule (purge po golom URL-u NE čisti `Vary` varijantu)**:
`purge_cache` s `{"files":["https://cdn…/info.json"]}` vrati `success:true` a
otrovani zapis ostane 404 (provjereno). Varijantu čisti samo
`{"files":[{"url":"…","headers":{"Origin":"https://domovina.ai"}}]}`.
Isto pravilo kao kod verifikacije purgea: s `Vary: Origin` postoje dva zapisa,
pa i provjera i purge moraju ići u obje varijante.

### Naslovnica bez čekanja kataloga + disk cache (LIVE od v2.0.173, 9.10.2026.)

Naslovnica je povlačila svih 50 listinga (6,9 MB sirovo / 1,3 MB preko žice)
pri svakom otvaranju. Sada: listinzi bez `?v=` (304 umjesto punog downloada),
prefetch po svježini kroz pool, hero se latcha čim je *dokazivo* konačan
(`HomeFeed.heroPoolComplete`), `home.json` (~6 KB) kad ga pipeline isporuči, i
stale-while-revalidate disk cache (`CdnJsonCache`). Mjerenja, ugovori za
`home.json`/`search.json`/listing v2 i zašto ne Worker s podacima u memoriji:
`docs/2026-10-08-brzina-ucitavanja-naslovnice.md`.

**Rule (CDN JSON ide kroz `CdnJsonCache`)**: promjenjive datoteke
(`channels/data/*`) kroz `getMutable` s `onUpdate`, per-epizoda kroz
`DataService._get`. Novi channel-level fajl NE dobiva `?v=` — origin šalje
`max-age=60` + ETag i edge to poštuje (izmjereno 9.10.2026.). U debug buildu i
uz `?nocache=1` cache je ugašen.

**Rule (ekran epizode čita `episode.json` prvi)**: `DataService._get` pita
`data/<id>/episode.json` (`EpisodeBundle`) i datoteku koje NEMA na njegovom
popisu ne traži — taj 404 je izmjeren na R2, pa mu se vjeruje (za razliku od
404 s CDN-a). Pipeline ga zato mora regenerirati nakon SVAKOG uploada u
`data/<id>/`. Predučitavanje ide samo kroz `EpisodePrefetch` (hover/dodir +
hero/„Nastavi slušati" u mirovanju), nikad za sve klikabilne epizode. Vidi §8
dokumenta gore.

**Rule (listing v2 mora čitati i stari build)**: `version` ostaje **string**
(stari build radi `as String?`), a v2 bez `pipeline` objekta ide tek kad stari
native buildovi ispadnu iz upotrebe — inače im sve epizode izgledaju
neobrađene.

### Thumbnail caching + WebP varijante — `CachedThumbnail`

Sve slike epizoda idu kroz `CachedThumbnail` (`lib/widgets/cached_thumbnail.dart`):
disk-persistent cache, sivi placeholder, error widget, i — ako je URL kanonski
`/images/{id}/thumbnail.png` — **automatska zamjena WebP varijantom** po
render-širini (`thumb-320/640/1280.webp`, pipeline KORAK 9.7). Call-siteovi ne
znaju za varijante. Fallback na PNG ide kroz `errorWidget` (ne `errorListener`).

*(Povijesno: do 25.8.2026. su varijante koristili SAMO TV ekrani, a web je i
dalje vukao PNG od ~830 KB po slici — naslovnica ~20 MB. Sada ~0,9 MB.)*

**Rule**: za slike epizoda koristi `CachedThumbnail`, ne `Image.network`.
Uvijek proslijedi `width` kad ga znaš — bez njega widget pesimistično uzima
širinu ekrana i bira najveću varijantu.

**Rule (CORS je tvrdi uvjet)**: `CachedNetworkImage` povlači bajtove kroz
`package:http`, pa URL MORA imati `access-control-allow-origin`.
`Image.network` na webu ima `<img>` fallback koji CORS preživi — `CachedThumbnail`
ga NEMA. Ne prosljeđuj mu strane hostove bez provjere. Zato su namjerno ostavljeni
na `Image.network`: person avatar + `person_monogram` (host iz `mcp.domovina.ai`),
`pinka_campaign_screen`, i `episode_simple_screen` (`info.thumbnail` =
`i.ytimg.com`, što ionako krši pravilo "nikad `info.thumbnail`").

**Rule (WebP na webu dekodira BROWSER, ne Flutter)**: na nativeu dekodira Skia pa
WebP radi svugdje; na webu podrška prati browser (Chrome 32+, Firefox 65+,
Safari/iOS Safari **14+**). Ne tvrditi da je "Flutter neovisan o browseru" — to
vrijedi samo za native.

### E-knjiga epizode (EPUB) — preuzimanje i slanje datoteke

Pipeline (`fetch.domovina.tv`, KORAK 9.8 `generate_ebook.js`) slaže cijelu
epizodu u EPUB i uploada ga kao `data/<id>/book.epub` te — kad postoji
`article.en.json` — `data/<id>/book.en.epub`. Frontend ga nudi na dva mjesta:
`EbookCard` (iza sažetka, u oba prikaza) i `EbookAction` (ikona otvorene knjige
u app baru); oba otvaraju `showEbookSheet` iz `lib/widgets/ebook_sheet.dart`.

**Rule (postojanje se MJERI, nema zastavice)**: `EbookService.probe` radi HEAD
na URL **s cache-busterom** i tek na 200 prikazuje ponudu. Channel listing nema
`has_ebook`, a i da ga dobije, vrijedi pravilo „pipeline zastavice ≠ stvarnost".
Cache-buster nije kozmetika: CDN cachira 404 četiri sata, a knjiga se generira
NAKON članka (englesko izdanje tek nakon prijevoda) — jedan prerani probe bez
njega sakrio bi knjigu do kraja tog prozora.

**Rule (bajtovi se predpreuzimaju na otvaranje sheeta)**: `navigator.share`
mora pasti unutar korisnikove geste, a knjiga je ~2,5 MB. Preuzimanje usred tapa
na iOS-u istekne (`NotAllowedError`), pa `_EbookSheet.initState` odmah povuče
izdanje na jeziku koji korisnik čita; tap tada samo preda gotove bajtove.

**Rule (jedan poziv, dvije platforme)**: sve ide kroz `services/file_share.dart`
— web preko `navigator.share({files})` iz `package:web`, native preko
`share_plus` (datoteka u temp direktorij pa sistemski sheet). Web ispad je
**blob URL + `<a download>`**, nikad `data:` URL (2,5 MB u base64 browseri znaju
tiho odbiti). `share_plus` je u projektu SAMO zbog nativea; ovisi o `web: ^1.1.1`
(ne o `dart:html`) pa ne ruši `--wasm` build — provjeriti pri svakom bumpu.

**Rule (ime datoteke se transliterira)**: `EbookService.fileName` miče
dijakritike i interpunkciju. Datoteka putuje kroz WhatsApp, e-poštu i tuđe
datotečne sustave, gdje „č" i „?" završe kao smeće ili odbijen upload.

Mjerenja, odbačene alternative i otvoreni dug (backfill, EN izdanje, `epubcheck`):
`docs/2026-09-15-ebook-epub-na-frontendu.md`.

### Sponzori u snimci — `SponsorsInVideo` (od 24.9.2026.)

`data/<id>/sponsors_in_video.json` (fetch pipeline KORAK 9.85,
`detect_sponsors.js`) nosi partnere koje je autor SAM doveo i koji su ugrađeni
u snimku. Sekcija „Uz podršku" na `/v/:id` (`widgets/sponsors_in_video_section.dart`)
crta karticu po imenovanom sponzoru; `playable: true` segment dobiva
„Poslušaj", koji skoči na raspon i na `end` samo javi „Poruka sponzora je
završila" — reprodukcija NE staje (`_checkSponsorClip` u `episode_screen.dart`;
pauza je do 24.9.2026. djelovala kao da je player stao), a ostali segmenti su samo skok na trenutak. Isti
„Poslušaj" stoji i u panelu playera (`SponsorsInVideoPlayerStrip` iznad
„Poglavlja") — sekcija je ~1500 px ispod vrha, a deep-link na mobitelu odmah
otvori ladicu s playerom, pa je bez trake gumb bio nevidljiv (prijava
24.9.2026. na `aue1GuuMsbA/t/8`). Ugovor:
`fetch.domovina.tv/docs/2026-09-23-sponzori-u-snimci.md`, testovi
`test/sponsors_in_video_test.dart`. Odluke, mjerenja, zamke i provjera
(`scripts/verify-sponsor-listen.py`): `docs/2026-09-24-sponzori-u-snimci-frontend.md`.

U članku sekcija u koju PADA POČETAK pouzdanog raspona dobiva prigušenu
oznaku „Poruka sponzora na 1:39:23" s gumbom (`SponsorsInVideo.marksBySection`
→ `SponsorsInVideoSectionMark`).

**Rule (sidro je vrijeme, ne tekst)**: AI članak sponzora opisuje drugdje i
drukčije napisanog — Ivin spot 1:39:23 opisan je tek u sekciji od 1:43:05,
„Cafe Brazil" je u članku „Caffe Brazil", „HiPP"/„Plazma" su „HIP-a"/„Plasme".
Označavanje imena u tekstu čeka `aliases` iz pipelinea; ne nagađati fuzzy
pravilima u klijentu.

**Rule (jedan sponzor = jedan redak)**: u traci playera ime i uloga stoje u
svom retku, gumb ispod („Poslušaj · 0:45"). Prva verzija je sponzore bez
raspona slagala u naslov, pa se gumb drugog sponzora čitao kao njihov.

**Rule (ime sloja)**: ovo NISU dinamička sponzorstva kupljena na domovina.ai
nakon snimanja — ta dolaze kao zaseban proizvod, izvor i widget. Ne preimenovati
u generičko `Sponsors`.

**Rule (dohvat)**: kroz `DataService.loadSponsorsInVideo` (`_get`, jedan retry
s cache-busterom), izvan `EpisodeData.load`, bez memorije preko sesije i bez
pollinga; 404/greška/nečitljiv JSON = sekcije nema. Zapis bez imena
(`_unattributed`) se ne prikazuje.

**Rule (radnja koja pusti reprodukciju pa otvori player ide kroz
`_revealPlayer`)**: do v2.0.166 je player bio u `endDraweru`, čije je
montiranje premještalo `<video>` u DOM-u i pauziralo ga (izmjereno 24.9.2026.
na 390 px: seek je sjeo na 5963 s, a poruka nije krenula). Panel platna je sad
uvijek montiran, ali `_revealPlayer` i dalje ponovi `play()` na 300/900 ms kao
osigurač — osim ako je korisnik u međuvremenu pauzirao (`PlaybackIntent`).

### Plaćeni sponzorski trenuci — `SponsoredMoment` (od 7.10.2026., nedeployano)

Samoposlužni oglas na `domovina_tv`: izlog `/c/:slug/oglasi`, karta + checkout
`/v/:id/sponzoriraj` (`?narudzba=<id>` = stanje narudžbe), prikaz
„Sponzorirano · {brand}" na epizodi. Ugovor: `domovina-api/docs/sponzorski-trenuci-ugovor.md`;
plan, stanje i otvoreno: `docs/plans/2026-10-06-mvp-sponzorski-trenuci-zakljucak.md`.

**Rule (dva sloja, nikad jedan)**: `SponsoredMoment` (`public_live_moments`,
kupljeno NAKON snimanja, „Sponzorirano · {brand}", DSA čl. 26) NIJE
`SponsorsInVideo` (autorov partner u snimci, „Uz podršku"). Odvojen model,
izvor i widgeti; boja je `AppTheme.sponsoredAccent` (zlatna), ne `tertiary`.

**Rule (tri mjesta, jedan kontroler)**: traka ide u `EpisodeVideo` (kroz
`controls:` builder, da postoji i u fullscreenu), `VideoPanel` i `_PlayerTab`.
Sva tri slušaju isti `SponsoredMomentsController.active`, koji ekran hrani
pozicijom. Bez `_PlayerTab` audio-only epizoda ne pokazuje tko je platio.

**Rule (mjerenje)**: `impression` jednom po sesiji po trenutku, `play_through`
samo bez skoka (ulazak skokom se ne računa), prag skoka kao `SeekUndo` (≥ 1 s).
Ugovor v1 nema tablicu — `LogSponsoredMomentSink` je privremen; ništa se ne
naplaćuje po prikazu.

**Rule (`functions.invoke` baca, ne vraća)**: svaki ne-2xx je
`FunctionException` s tijelom u `details`; greška u `res.data` stiže samo uz
200. Kodove greške uspoređuj po prefiksu do prve dvotočke
(`slot_taken:<key>`, `invalid_sponsor:<polje>`) — vidi
`PinkaClient._invokeContribute`.

**Rule (lokalni checkout ne šalji)**: lokalni edge runtime nema
`PINKA_INTENTS_URL`, pa `pinka-contribute` stvara intent na PRODUKCIJSKOM
`mpt.domovina.ai`. Lokalni e2e plaćanja ide kroz `create_sponsor_contribution`
→ `attach_intent` → `mark_contribution_paid` nad lokalnom bazom.

### Epizoda na uskom ekranu — tri stupca, ne draweri (od 5.10.2026.)

Ispod 1100 px (`_kPlayerColumnMinWidth`) su sadržaj i player stupci na
`EpisodePanelCanvas` (`widgets/episode_panel_canvas.dart`): kad uz panel ostane
≥ 320 px, članak se suzi i oba se vide (iPhone landscape: 390 | 360); inače
panel gura članak s ekrana. Mobitel u landscapeu skriva header i footer dok se
čita. Odluke, mjerenja, zamke i otvoreno:
`docs/2026-10-05-epizoda-tri-stupca.md`.

**Rule (panel ostaje montiran)**: zatvoren panel se NE demontira ni `Offstage`-a —
inače `<video>` putuje po DOM-u i pauzira se. Skrivanje ide kroz
`ExcludeSemantics` + `ExcludeFocus` + `TickerMode`, omotače koji su uvijek u
stablu.

**Rule (programski skok na sekciju ide kroz `_scrollToSection`)**: on bilježi
skok, pa ga sidro čitanja tijekom reflowa ne poništi nego ponovno pinna cilj.
Izravan `jumpTo` na sekciju zaobilazi to i članak se vrati na staro mjesto.
U landscapeu na mobitelu `_scrollToSection` MJERI koliko je floating headera na
ekranu (`_floatingHeaderJumpDelta`) — fiksna „puna visina" je na skrivenom
headeru ostavljala ~100 px praznine iznad naslova.

**Rule (landscape na mobitelu = platforma I dimenzije)**: `_isPhoneLandscape`
traži iOS/Android. Bez toga nizak desktop prozor gubi header. Footer se u tom
načinu NE skriva dok je autoplay utišan (izlaz „Uključi zvuk").

**Rule (titlovi se ne režu)**: titl nema `maxLines`/ellipsis — puni tekst je
vrijedniji od slike koju prekrije. Kad ne stane, smanjuje se font
(`fittingSubtitleFontSize`), mjeren istim `DefaultTextStyle` kojim se crta.

### Pronađi u epizodi + članak klizi uz reprodukciju (od 7.10.2026.)

Pretraga transkripta (Meili `segments`, `services/transcript_search.dart`) i
„odjavna špica" (`_creditsScroll`: dok player svira, članak klizi kroz sekciju
proporcionalno vremenu). Mjerenja, zamke i otvoreno:
`docs/2026-10-07-pronadi-u-epizodi-i-odjavna-spica.md`.

**Rule (Meili `sort` ne drži kronologiju)**: `sort` se primjenjuje iza
`words`/`typo`, pa tipfeleri stižu zadnji — redoslijed po vremenu slaže klijent.

**Rule (špica ide samo naprijed)**: nikad ne scrolla unatrag, staje 8 s nakon
ručnog scrolla i ne vuče korisnika koji je više od ekrana daleko. Novi
programski scroll članka postavlja `_scrollLock`, inače ga `_onScroll` pročita
kao ručni i ugasi špicu.

### Titlovi riječ po riječ + titl ispod playera (od 6.10.2026.)

`data/<id>/words.json` (Speechmatics vrijeme po riječi, poravnato s Geminijevim
tekstom iz `diarized.srt`) pali isticanje izgovorene riječi. Na mobitelu u
portraitu titl crta `SubtitleStrip` ISPOD slike, a svugdje drugdje (i u svakom
fullscreenu) overlay preko slike. Ugovor, mjerenja i pipeline dug:
`docs/2026-10-06-titlovi-rijec-po-rijec.md`.

**Rule (ugovor je SRT)**: `words.json` vrijedi za cue samo ako ima točno
onoliko riječi koliko `text.split(/\s+/)` tog cue-a. Inače cue ostaje bez
isticanja, nikad s pomaknutim.

**Rule (isticanje = samo boja)**: debljina ili veličina aktivne riječi
raširi redak i tekst se prelomi drukčije na svakoj riječi.

**Rule (traka ispod playera ima fiksnu visinu)**: dugačak cue se lista po
stranicama (`pageTokens`), ne raste. Inače seek bar skače sa svakim cue-om.

### Pinka SEPA — uspjeh na ZAPRIMANJU, namira u pozadini (od 28.9.2026.)

Rail stage `received_processing` stiže ~1 s nakon SEPA Instant uplate, a mint
(→ RPC `paid`) kod prve uplate s novog IBAN-a zna trajati 1 min – 8 h. Panel
zato slavi na zaprimanju, sam se zatvori nakon 4 s i namiru prati u pozadini.
Tok, mjerenja i zamke: `docs/2026-09-28-pinka-sepa-instant-i-zid.md`.

**Rule**: `onPaid` (zid, kvadratić) samo na RPC `paid` — doprinos je u bazi
plaćen tek tada. Rano prikazivanje ide kroz `onReceived` + optimistični unos na
zidu (isti contribution id). Nijedna petlja u SEPA toku nema vremenski limit;
gase je `dispose` i terminalni stage (`settled`/`rejected`).

**Rule (OG slike)**: zid i obrazac crtaju SAMO `link_preview.image_cached`
(`api.domovina.ai`, bucket `pinka-og-cache`), NIKAD tuđi `og:image` — to bi
posjetiteljev IP odalo vlasniku tog hosta. Preview u obrascu ide preko edge
funkcije `pinka-link-preview`, ne dohvatom iz preglednika.

## Logging

`lib/src/log.dart` exports a `log()` function that prefixes messages with `[DOMOVINA v{version}]` (and the `appVersion` constant that `scripts/deploy.sh` bumps). Use it throughout the app for console debugging:

```dart
import '../src/log.dart' show log;

log('MyWidget.build()');
log('fetch complete: ${items.length} items');
```

Logs are visible in browser DevTools console and help trace the exact point of failure in release builds where stack traces are minified.

**Rule**: When adding new async operations or widget builds that could fail, add `log()` calls at key checkpoints. This is critical because release web builds minify all symbols — without logs, errors show only `Uncaught Error` at an unreadable line number.

## Internationalization (i18n)

> Puna referenca s mermaid dijagramima (UI vs sadržaj, string resolution,
> locale perzistencija, key-prefiksi, Magisterium uzrok) —
> `docs/i18n-and-localization.md`.

App UI is fully localized via Flutter `gen-l10n` (ARB). **Hrvatski je izvorni/template
jezik**, engleski je drugi jezik. Konfiguracija u `l10n.yaml`; ključevi u
`lib/l10n/app_hr.arb` (template, s `@key` metapodacima + placeholderima) i
`lib/l10n/app_en.arb` (prijevod). Generirana klasa: `lib/l10n/app_localizations.dart`
(`flutter gen-l10n` ili automatski preko `generate: true`).

**Razlika UI jezik vs. jezik sadržaja**: ovo je jezik *chrome-a* (gumbi, naslovi,
poruke) i bira ga `LocaleController` (`services/locale_service.dart`, persist u
localStorage/SharedPreferences, default HR, prebacivač u `/account`). ODVOJENO od
per-epizoda jezika *sadržaja* (`services/episode_language.dart` +
`widgets/language_toggle_chip.dart`), koji bira HR/EN CDN članak/Magisterium preko
`pickLang(...)`. CDN/model tekst se NIKAD ne lokalizira kroz ARB — samo hardkodirani
Dart literali.

**Kako lokalizirati novi string:**
- Dodaj ključ PRVO u `app_hr.arb` (+ `@key` ako ima placeholdere/plural), pa prijevod
  u `app_en.arb`, pa `flutter gen-l10n`.
- U widgetu s contextom: `final l = AppLocalizations.of(context); … l.mojKljuc`.
- Bez contexta (servisi, callbackovi, modeli): `appStrings.mojKljuc` (globalni getter u
  `services/locale_service.dart` → `lookupAppLocalizations(LocaleController…locale)`).
- **Rule (live language switch)**: `appStrings` NE registrira dependency na
  Localizations scope — tekst renderiran preko njega u buildu ostaje na starom
  jeziku nakon promjene UI jezika (stale dok se widget ne rebuilda iz drugog
  razloga). Zato: sve što se perzistentno renderira → `AppLocalizations.of(context)`
  (ili proslijeđen `AppLocalizations l` parametar); `appStrings` SAMO za
  jednokratni event-time resolve (SnackBar, `_error` u catch bloku, outreach
  poruke, servisi). Enum/model copy getteri primaju `AppLocalizations l`
  parametar (primjeri: `ChannelSortMode.label(l)`, `UpgradeTriggerCopy.headline(l)`,
  `MagisteriumSection.scoreLabel(score, l)`). Sweep 2026-07-23 poravnao codebase.
- **Rule (dvosmjerna sprega jezika)**: svaki prebacivač UI jezika
  (`LanguageToggleButton`, account SegmentedButton) sprema i preferirani jezik
  sadržaja (`savePreferredLanguage`), a `LanguageToggleChip` (jezik sadržaja na
  epizodi) postavlja i UI locale — sadržaj i sučelje se uvijek prebacuju zajedno.
- Imenovanje ključeva: `<područje>CamelCase` (npr. `home*`, `episode*`, `magisterium*`,
  `legal*`, `auth*`, `channel*`, `ownership*`, `tv*`, `pinka*`, `service*`, `common*`).
  `common*` za stringove dijeljene kroz aplikaciju (Odustani, Zatvori, Pokušaj ponovno…).
- ICU plural za brojive imenice (hrvatski one/few/other). Imena jezika u prebacivaču su
  endonimi ("Hrvatski"/"English") — namjerno NISU u ARB-u.

**Rule (registar/ton)**: aplikacija oslovljava korisnika **neformalno „ti"**
(topli, izravan glas, usklađen s pinka SDK-om). Iznimka: **outreach poruke trećim
stranama** (npr. `ownershipInviteMessage` vlasniku kanala) i pravni/formalni tekst —
tu je „Vi" ispravno. Ne miješaj registar unutar istog konteksta.

**Rule (bez emojija u sučelju)**: user-facing string ne nosi emoji ni
piktograf. Dva razloga, oba izmjerena. Estetski: emoji u proizvodu čita se kao
AI-generirana ispuna. Tehnički: glif ovisi o fontu koji ga na kraju dobije —
`🇭🇷` nema glifa u Windows Chromeu (zato je `HrvatskaZastavica` `CustomPaint`),
a `⏱` je Pillow tiho nacrtao kao `.notdef` kvadratić na svih 65 759 OG slika.

Zamjena je **`Icons.*`** na pozivnom mjestu (vektor iz fonta koji putuje s
aplikacijom, prati `IconTheme` boju i veličinu), a ne drugi znak. Ako uz string
već stoji ikona, emoji se samo briše — `🙏` ispod `Icons.check_circle` je bio
čista redundancija. Smjer na D-padu crta `TvKeyHint`
(`lib/screens/tv/widgets/tv_key_hint.dart`), pa u ARB idu **samo riječi**
(„odlomci"), nikad tipke — inače svaki novi jezik prepisuje glifove i prva
greška u prijepisu je nevidljiva dok je netko ne ugleda na televizoru.

Iznimka su znakovi koji imenuju **fizičku tipku**: `⌘` (U+2318, otisnut na Apple
tipki) i `↑ ↓ ← → ↵` u legendi tipkovnice. Ikona bi ih učinila manje jasnima, ne
više. Oznaka prečice mora pratiti platformu (`theme.platform`) jer
`home_screen.dart` veže i `meta:` i `control:` — do 15.9.2026. je Windows
korisnik čitao `⌘K`.

Kontrakt čuva `test/no_emoji_in_strings_test.dart` (ARB vrijednosti + Dart
literali u `lib/`; komentari su izuzeti jer ih korisnik ne vidi). Inventura
cijelog stabla: `python3 scripts/scan-emoji.py --summary` — ide preko
`git ls-files`, jer `rglob` ubroji i `ios/Pods/` pa brojka govori o tuđem SDK-u.
Odluka o icon setu (Lucide razmotren i odbačen), mjerenja i otvoreno:
`docs/2026-09-15-emoji-u-sucelju.md`.

**Rule (lektor)**: svaki user-facing string mora imati ispravne dijakritike
(č/ć/š/ž/đ), gramatiku i pravopis (Hrvatski pravopis IHJJ — npr. „sažetci", „pogreške",
„adresa e-pošte"). Bez ALL-CAPS u ARB vrijednostima; vizualni caps radi se u kodu preko
`.toUpperCase()` na već lokaliziranom stringu.

**TODO (poznato)**: `widgets/founder_booking.dart` koristi ručne hrvatske nazive
mjeseci/dana (`_hrWeekdayShort`/`_hrMonthsGen`) — za pravu lokalizaciju datuma treba
`intl` `DateFormat` s locale podrškom (van opsega string-ekstrakcije).

## Architecture Notes

### Scrollabilne liste — rubni padding UNUTAR scrolla

Scrollabilni sadržaj (horizontalni railovi, breadcrumbovi, vertikalne liste)
mora klizati do fizičkog ruba ekrana; rubni razmak postoji samo u mirovanju.
Vanjski `Padding` oko scrollabla "reže" sadržaj na uvučenom rubu — izgleda
odrezano, posebno na mobile.

**Rule**: padding ide kao `padding:` parametar NA listu
(`ListView`/`SingleChildScrollView`/`SliverPadding`), nikad kao `Padding`
wrapper oko nje. Scrollabilni sadržaj u `AppBar`/`SliverAppBar` title →
`titleSpacing: 0` + padding unutar scrollabla (primjer: `home_app_bar.dart`).
Bottom sheet s horizontalnom listom → sheet padding bez horizontalne
komponente, sekcije nose svoj h-padding (primjer: `founder_booking.dart`).
Iznimka: bordered card/panel/dialog gdje je padding chrome kartice.
Sweep 2026-07-23 poravnao cijeli codebase na ovaj pattern.

**Rule (auto-scroll unutar ugniježđenog scrolla)**: `Scrollable.ensureVisible`
scrolla **sve** nadređene scrollable-ove, ne samo najbliži. U horizontalnoj
traci unutar vertikalne stranice to povuče i stranicu — vlastiti
`ScrollController` + ručni izračun offseta (primjer: `PeopleRail` u
`widgets/entities_section.dart`, koji bi inače poništio `_scrollToPersonAnchor`
u `episode_screen.dart`).

### Virtualni kanali — osoba kao kanal (LIVE od 4.9.2026.)

`/p/:slug` u kanal-formi; osoba je i u `/channels` (filtar „Osobe",
`?prikaz=osobe`), na home railu, u pretrazi, u TV laneu i u sitemapu.
`PersonChannelFlag` je default **ON**; `?vk=0` gasi po korisniku i preživljava
promjenu defaulta — to je rollback bez redeploya. Backend je u `domovina-rag`
(`/api/persons`, prošireni `/api/person/:slug`, `POST /api/person-report`).

**Rule (pravilo uvrštavanja živi u backendu, na jednom mjestu)**: frontend NE
preračunava prag — čita `is_virtual_channel`. Pravilo je
`domovina-rag/services/mcp/src/tools/person-channel.ts` i nije „≥ 3 epizode":
traži i ≥ 3 kanala, ≤ 60 % epizoda na najvećem kanalu i ≥ 2 tokena u slugu.
Bez ta tri uvjeta katalog naraste s 74 na 311 osoba i pušta **domaćine praćenih
kanala** (fra Stjepan Brčina 178 ep / 97 % na jednom kanalu) koji već imaju
svoju `/c/` stranicu, te rolne oznake („Pjevač", „Svećenik", „Ana").

**Rule (prikaz BEZ kanal-forme mora ostati potpun)**: backend dijeli nastupe na
`episodes[]` (primary) i `cameo_episodes[]`. Cameo je 31,7 % svih parova
govornik-epizoda, pa profil bez flaga crta `PersonHub.allAppearances`, NIKAD
`hub.episodes` — inače gotovo trećina nastupa tiho nestane, bez iznimke i bez
crvenog testa. Podjela na dvije sekcije postoji samo u kanal-formi.

**Rule (prijava greške nije brisanje)**: „Prijavi grešku" piše u
`person_channel_overrides` s `confirmed = false`; agregacija čita samo
`confirmed = true`. Bez te podjele bi javni gumb bez autentikacije bio brisač
tuđih epizoda iz kataloga. Opt-out (`person_optouts`) gasi kanal, ali
`/p/{slug}` namjerno ostaje 200 s `optout: true` — 404 bi razbio podijeljene
linkove, i taj prikaz NIJE iza flaga.

Planovi, mjerenja i naredbe za reprodukciju:
`docs/plans/virtualni-kanali.md`, `docs/plans/2026-09-03-virtualni-kanal-belavic.md`,
`docs/plans/2026-09-03-organizacije-kao-kanal.md` (organizacija kao entitet —
odgođeno). Ugovor prema backendu čuva `test/person_backend_contract_test.dart`
nad stvarnim odgovorima, ne nad izmišljenim fixtureima.

### Person hub — osoba postoji i bez gostovanja

`/p/:slug` agregira DVA disjunktna izvora: `episodes[]` (osoba GOVORI,
diarizirano) i `mentions[]` (osoba se SPOMINJE). Identitet je disjunkcija —
povijesna/pokojna figura (bl. Ivan Merz) ima valjan profil samo iz spomena;
404 tek kad nema ni jedno ni drugo. Backend živi u `domovina-rag`
(`docs/person-hub.md`), ne ovdje.

**Rule**: spomen ima ILI razriješen `first_ts` (tap seeka na sekundu) ILI ga
nema (~40% — tap otvara epizodu od početka). Te dvije stvari se NE smiju
prikazivati isto: `_MentionMomentChip` u `person_screen.dart` je puna brand
crvena vs prigušena obrubljena.

**Rule**: dolazak na epizodu s `?p=<slug>` mora raditi i BEZ `/t/<sec>` —
sidro se tada traži po sadržaju (prva sekcija koja referencira osobu), članak
se doscrolla onamo, ali se video NE seeka (znamo sekciju, ne sekundu). Pill
bez ciljne sekunde nikad ne tvrdi „govori ovdje", nego „ovdje se spominje".

### Routing i navigacijski stog

Ruting je **go_router 14.8** u `lib/router/app_router.dart` (`createRouter()`).
Puna tablica ruta: `docs/podcasterium_technical_manual.md` §3. Analiza koja je
dovela do stoga: `docs/2026-09-04-navigacija-i-scroll-restoration.md`.

**Rule (jedan helper po VRSTI prijelaza — `lib/router/nav.dart`)**: do 6.9.2026.
je 82 od 98 poziva bilo `context.go()`, koji **zamijeni cijelu listu ruta**. Zbog
toga aplikacija nije imala stog: svaki ekran s kojeg odeš bio je *uništen*, pa se
scroll nije imao odakle vratiti, `canPop()` nikad nije bio `true`, a na Androidu
je sistemski Back zatvarao aplikaciju.

| Prijelaz | Helper |
|---|---|
| lista → detalj, detalj → dublji detalj | `drillDown` |
| isti sadržaj, druga prezentacija (`/v` ↔ `/m`, HR ↔ EN) | `swapPresentation` |
| peer → peer (epizoda → srodna epizoda) | `goPeer` |
| povratak na korijen (breadcrumb „Početna") | `context.go('/')` |
| gumb „nazad" | `back` / `backUp` (+ `upTarget`) |

`context.go('/')` je dopušten SAMO u `nav.dart`, breadcrumbovima i error/prazna
stanja ekranima. `push` bez ograde je curenje memorije (`NoTransitionPage` ima
`maintainState: true`, ekrani ostaju živi) — zato `kMaxStackDepth`.

**Rule (`GoRouter.optionURLReflectsImperativeAPIs = true` mora ostati)**:
`RouteMatchList.uri` po ugovoru odražava samo NE-imperativne matcheve
(`go_router match.dart:509-511`), a `push` ne prosljeđuje `uri` — bez zastavice
bi `push('/v/abc')` ostavio adresnu traku na `/`, čime pada „Kopiraj poveznicu",
worker OG inject i `url_sync`. go_router od nje odgovara jer „URL najgornje rute
nije uvijek deeplink-abilan"; kod nas vrijedi obratno (nema `ShellRoute`, sve su
rute top-level i moraju biti dosežne izravnim URL-om). Čuva
`test/nav_contract_test.dart`, uključujući test koji s ISKLJUČENOM zastavicom
dokazuje da URL ostane na `/`.

**Rule (`ValueKey` rute ne smije nositi promjenjivo stanje)**: ključ epizode je
nosio `startAt`, pa je `/v/<id>` → `/v/<id>/t/<sec>` bio novi ključ → novi
`State` → **uništen player**. Ključ nosi samo identitet ekrana (video + jezik);
`startAt`/`person` primjenjuje `didUpdateWidget` (seek na živom playeru).

**Rule (`url_sync` mora proslijediti postojeći `history.state`)**: Flutter engine
u njega omota `{serialCount, state}`, a go_router serijalizira `location` +
`imperativeMatches`. `replaceState(null, …)` je taj omot brisao — izmjereno na
produkciji 4.9.2026. S pushanim stogom bi to značilo gubitak cijelog traga.

**Rule (modal na webu ne zna za browserov Back)**: `showDialog`/
`showModalBottomSheet` guraju IMPERATIVNU rutu bez history entryja. Na nativeu
Back uredno popa modal; na webu browserov Back promijeni stranicu ISPOD modala,
a modal ostane visjeti. Novi modal → `closeOnRouteChange` iz `nav.dart`.

**Scroll**: glavni mehanizam je `push` (ekran ispod ostaje živ, pozicija nikad ne
ode). `services/scroll_memory.dart` pokriva samo remount (deep-link pa ←, hard
refresh, `go('/')` s breadcrumba) i ima tri obavezna detalja: `jumpTo` a ne
`animateTo`; čekanje `maxScrollExtent >= offset` uz odustajanje nakon 2 s (inače
se offset clampa na visinu skeletona); ključ nosi query string. Izračunati
redoslijed kanala živi u `ChannelCache`, NE u `_HomeScreenState` — inače
naslovnica u prvom frameu nakon povratka crta skeleton i visina joj raste u
skokovima, pa vraćanju scrolla meta bježi ispod njega.

*(Povijesno: ovdje je do 15.8.2026. pisalo da `main.dart` koristi
`onGenerateRoute` s `home: const HomeScreen()` i da `initialRoute` /
`onGenerateInitialRoutes` crashaju na webu. To je zastarjelo — migracija na
go_router se dogodila u međuvremenu, a ova sekcija nije bila ažurirana.)*

### Croatian flag theme

Colors from the logo SVG:
- Red: `#FF0000` — `AppTheme.brandAccent` (tertiary)
- White: `#FFFFFF`
- Navy blue: `#002F6C` — `AppTheme.brandPrimary` (M3 seed)

Od 18. 9. 2026. obje boje čitaju `AppBrand.config` (`seed` / `accent` u
`packages/podcast_core/lib/brand/domovina_brand.dart`); u kodu NEMA hex
literala brenda. Komentari po kodu još spominju stara imena `croBlue` /
`croRed` — isto značenje.

### Social sharing

- Homepage: static OG tags in `web/index.html` + JSON-LD structured data
- Episode pages: dynamic OG injection in `web/_worker.js` (Cloudflare Worker)
- OG image: `web/og-image.png` (1200x630) generated from `assets/icons/og-image.svg`
- Test page: `https://domovina.ai/social-test`
- Test script: `node scripts/test-social-tags.mjs`

> Puna slika (četiri tiha kvara, mjerenja, zamka u verifikaciji purgea) —
> `docs/2026-09-15-engleski-share-i-og-slike.md`.

**Rule (svaka ruta koju Flutter zna mora znati i worker)**: `/en` sufiks je u
`app_router.dart` postojao od uvođenja per-epizoda jezika, a u `_worker.js` ga
nije bilo ni u jednom matcheru — svaki engleski share (`/v/<id>/t/<sec>/en`)
padao je kroz sve rute na SPA fallback i dobivao **generički OG naslovnice, na
hrvatskom**. Tiho: stranica se otvarala ispravno, seek je radio, samo je preview
bio kriv. Izmjereno 15.9.2026. Nova ruta s vlastitim OG-om → dodaj je u OBA
matchera i pokrij u `test-social-tags.mjs`.

**Rule (share URL se NE sastavlja ručno)**: ide kroz `episodeShareUrl`
(`lib/services/share_links.dart`), jer je jezik dio PUTANJE — ručni string ga
tiho gubi. „Kopiraj poveznicu" na poglavlju davalo je hrvatski URL i kad je
korisnik čitao engleski; na webu se to nije vidjelo jer se link dao prepisati iz
adresne trake (koju `url_sync` održava), a u iOS/Android aplikaciji adresne
trake nema pa je gubitak bio potpun. Redoslijed `/v/<id>/t/<sec>/en` mora ostati
usklađen na TRI mjesta: matcheri u `_worker.js`, `url_sync`, i ovaj builder —
čuva `test/share_links_test.dart`.

**Rule (izvan episode ekrana jezik se NAGAĐA, pa traži dva uvjeta)**: kartice u
railovima nemaju `EpisodeLanguageScope`, pa jezik dolazi iz
`shareLanguageForVideo` (`services/share_language.dart`), koji nudi EN samo kad
vrijedi **oboje**: korisnik je izabrao engleski (`PreferredEpisodeLanguage` —
sinkroni singleton, jer odluka pada u trenutku klika) I listing za tu epizodu
ima podignut `pipeline.has_article_en`. Drugi uvjet nije formalnost: `/v/<id>/en`
za neprevedenu epizodu tehnički radi (padne na HR), pa bi bez njega link
obećavao engleski i otvarao hrvatski — gore nego da je odmah hrvatski.

Zastavici se ovdje vjeruje samo u JEDNOM smjeru, u skladu s pravilom da
izostanak zastavice nije informacija. Mjereno 15.9.2026. nad svim kanalima:
42 epizode s podignutom zastavicom, 0 bez `article.en.json` (nikad ne laže
pozitivno), ali 5 epizoda ima prijevod uz zastavicu koja šuti. Te 5 dobiju
hrvatski link — svjesna cijena za nula lažnih obećanja.

**Rule (share URL kartice se gradi pri KLIKU)**: `ShareContextMenu.lazy`
(`urlBuilder`), ne `ShareContextMenu(url:)`. `push` drži ekran ispod
montiranim, pa kartica preživi promjenu jezika na ekranu iznad bez rebuilda —
URL izračunat u `build` ostao bi na starom jeziku. Fiksne poveznice (kanal,
osoba) i dalje koriste obični konstruktor.

**Rule (EN je zaseban CDN fajl, ne polje)**: prijevod živi u
`data/<id>/article.en.json` i `summary.en.json` — u njima su i HR i `*_en`
polja, pa se fallback radi **po polju** (`pickLang`), ne po dokumentu; prijevodi
su parcijalni. Naslov epizode se NE prevodi (izvorni YouTube naslov), niti
`inLanguage` u JSON-LD-u — audio ostaje hrvatski. HR i EN imaju svaki svoj
self-referencing canonical + uzajamni `hreflang`.

**Rule (u OG sliku se ne piše emoji)**: `generate_og_sections.py` je crtao `⏱`
Helveticom, koja taj glyph nema — Pillow ga je tiho renderirao kao `.notdef`,
prazan kvadratić, na svih 65 759 postojećih `og-t-*.jpg`. Ikone u kompozitima se
CRTAJU (`draw_clock_icon`), jer vektor ne može pasti na fallback koji nitko ne
vidi do WhatsApp previewa. Isto vrijedi za `og-t-<sec>-en.jpg` (subtitle_en).

**Rule (app ključ ≠ pipeline ime)**: `upload_to_r2.js` mapira
`{base}.og-sections/manifest.json` → `images/{id}/og-sections.json`, pa je
provjera „je li ovo manifest" po basenameu promašivala i manifest je prvim
uploadom postao `immutable` na godinu dana — nove sekcije i cijela `sections_en`
mapa nikad nisu stizale do workera iako su slike bile na R2. Popisi u
`isContentMutable`/`cacheControlFor` moraju nositi OBA imena. Regeneriranu
immutable sliku na CDN šalje tek `--force-og` (analogno `--force-mp4`).

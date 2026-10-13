# Nightly store build — TestFlight + Play internal, svaku noć

Dopuna `docs/mobile-release-pipeline.md`: ondje je **ručni** put (build → upload →
promocija), ovdje je **automatski noćni** koji taj put vozi sam u 03:00 kad ima
novih commitova, i javlja ishod u Telegram grupu.

Cilj nije objava. Cilj je da na oba storea **uvijek stoji svjež, provjeren build**
spreman za promociju, i da se pokvareni build otkrije isto jutro, a ne dva tjedna
kasnije kad ga zatrebaš.

```mermaid
flowchart TD
    L[launchd 03:00<br/>ai.domovina.nightly-build] --> C{HEAD != zadnji<br/>izgrađeni sha?}
    C -->|ne| S[💤 Telegram: preskočeno<br/>izlaz 0]
    C -->|da| E{.env potpun?<br/>key.properties?}
    E -->|ne| F[❌ Telegram: preduvjeti]
    E -->|da| W[git worktree --detach<br/>../.nightly-domovina @ HEAD]
    W --> A[flutter pub get<br/>flutter analyze]
    A --> T{testovi<br/>bez baselinea}
    T -->|pad| F2[❌ Telegram: testovi<br/>UPLOAD SE NE DOGAĐA]
    T -->|prolaz| B[build broj =<br/>max ASC, Play, pubspec + 1]
    B --> I[iOS: xcodebuild archive → IPA]
    I --> D[Android: AAB]
    D --> U1[altool → TestFlight]
    U1 --> U2[Play Developer API → internal]
    U2 --> V[verifikacija:<br/>processingState + track read-back]
    V --> R[✅ Telegram + .nightly/reports/<br/>zapiši last-built-sha]
```

## Zašto baš ovako

**Rule: worktree je SESTRA glavnog repoa** (`../.nightly-domovina`), ne bilo gdje.
`pubspec.yaml` ima path ovisnost `flutter_certilia: ../../stepanic/flutter_certilia`
koja se razrješava relativno na worktree. Premještanje u APFS kontejner
(2026-08-14, radi uštede boot prostora) odmah je oborilo `pub get` s „could not
find package flutter_certilia" — jer `../../stepanic` ondje pokazuje u
`/Volumes/stepanic`. Nightly mora razrješavati putanje identično ručnom buildu.

**Odvojeni git worktree.** Nightly nikad ne gradi iz tvog radnog direktorija.
U 03:00 ondje lako leži nedovršen WIP, a `flutter clean` iz iOS grane bi ti
usput obrisao artefakte. Worktree je detached na HEAD shi u
`../.nightly-domovina`, s `.env` i `android/key.properties` simlinkanim iz
glavnog repoa. Čisti se s `git clean -fd` **bez `-x`**, pa ignorirani artefakti
(`build/`, `.dart_tool/`, Pods) prežive i sljedeći build je topao.

**Build broj se računa, ne bumpa.** `BUILD_NUMBER = max(ASC, Play, pubspec) + 1`,
proslijeđen kroz `--build-number` (`Info.plist` već koristi
`$(FLUTTER_BUILD_NUMBER)`). Zato:
- pubspec.yaml se **ne mijenja i ne commita** — nightly nema pisanja u git,
- kolizija s već uploadanim buildom je nemoguća (Play odbija ponovljeni
  `versionCode`, TestFlight ponovljeni build),
- `deploy.sh` i dalje bumpa verziju za web kako je bumpao; nightly se samo
  penje iznad onoga što na storeovima stvarno postoji.

Ime verzije ostaje ono iz pubspeca. Dva nightlyja s istim imenom verzije su u
redu — razlikuju se build brojem.

**Zamka koja je ovo skoro pojela:** `xcodebuild -exportArchive` po defaultu ima
`manageAppVersionAndBuildNumber = true` — pri App Store distribuciji **sam pita
App Store Connect i prepiše `CFBundleVersion` na „zadnji + 1"**. Izmjereno
2026-08-13 izolirano: ista arhiva ima 158, izvezena IPA 159, bez ijednog traga u
`.xcdistributionlogs`. Dok se to ne isključi, iOS broj dolazi od Applea a Android
od nas — i razilaze se čim Play prestigne ASC. `ios/ExportOptions.plist` zato
eksplicitno postavlja `manageAppVersionAndBuildNumber = false`.

**Rule: nightly gradi iz HEAD-a, pa izmjene skripti vrijede tek nakon commita.**
Worktree je `git checkout --detach <sha>` — necommitane promjene u
`scripts/build-mobile-release.sh` (ili bilo čemu drugom) nightly jednostavno ne
vidi. Ovo je namjerno (build mora biti reproducibilan iz gita), ali zna zbuniti:
mijenjaš skriptu, a ponašanje se ne mijenja.

**Testovi su tvrda vrata, s eksplicitnim baselineom.** Pad testa → nema uploada.
Ali dva testa padaju i na čistom mainu, pa bi „sve mora biti zeleno" značilo da
se nikad ništa ne uploada. Popis izuzetih je u `.nightly/test-baseline.txt`
(jedini praćeni fajl u `.nightly/`). Nightly ih **svejedno vrti** i ako prorade,
javi 🎉 da ih makneš — inače baseline tiho trune i pokriva prave regresije.

**Verifikacija nakon uploada.** HTTP 200 na uploadu ne znači da je build dobar:
Apple obrađuje asinkrono i ITMS-90xxx odbijenice stižu tek minutama kasnije.
Nightly zato do 45 minuta (`NIGHTLY_TF_POLL_MIN`) polla `processingState` za taj
build broj i tek onda javlja ✅ ili ⚠️. Za Play čita natrag internal track i
provjeri da je `versionCode` stvarno ondje.

**Rule (build kojeg ASC ne vidi NIJE „u obradi")**: do 24.9.2026. je poll
nepoznat build brojao kao `PROCESSING`. Zato je 13.8. zaključeno da „build 159 ni
25 min nakon uploada nije u `/v1/builds`" i prozor je podignut s 20 na 45 min.
Istina je bila drukčija: 159 (i kasnije 160) **nikad nije stigao**. `altool` je
javio `UPLOAD FAILED … Invalid Pre-Release Train. The train version '2.0.136' is
closed`, ali uz exit 0, pa je korak prošao kao ✅, a izvještaj je javio „Apple ga
još obrađuje, nije greška". Pravi uploadi (168, 171, 176, 177) postanu `VALID`
za 2–3 min. Sada:

- `testflight-upload.sh` priznaje uspjeh samo uz `UPLOAD SUCCEEDED` u ispisu
  altoola; zatvoren train vraća **exit 3** i nightly javi „bumpaj verziju".
- poll razlikuje `NOT_FOUND` od `PROCESSING`; `NOT_FOUND` na kraju prozora je ⚠️
  „upload možda nije stigao", ne umirujuća poruka.

Zatvoren train se događa kad je verzija iz pubspeca već **odobrena** na App
Storeu, a nitko je nije bumpao (`deploy.sh` bumpa samo kad se deploya web).

## Datoteke

| Putanja | Uloga |
|---|---|
| `scripts/nightly-build.sh` | orkestrator (guard → worktree → vrata → build → upload → verifikacija → Telegram) |
| `scripts/store-status.rb` | stanje oba storea; `--json` za skriptu, `--max-build` za build broj |
| `scripts/telegram-notify.rb` | slanje u grupu (chunking, retry, supergroup migracija, **redakcija tajni**) |
| `scripts/telegram-chatid.rb` | jednokratno otkrivanje `chat_id`-a |
| `launchd/ai.domovina.nightly-build.plist` | raspored 03:00 |
| `.nightly/test-baseline.txt` | poznati crveni testovi, izuzeti iz vrata (praćen u gitu) |
| `.nightly/logs/`, `.nightly/reports/`, `.nightly/last-built-sha` | lokalno stanje (ignorirano) |

## Ručno pokretanje

```bash
./scripts/nightly-build.sh --force --skip-upload   # cijeli put bez diranja storeova
./scripts/nightly-build.sh --force                 # pravi run
./scripts/nightly-build.sh --no-telegram           # bez notifikacije
./scripts/store-status.rb                          # gdje su storeovi sada
```

## Instalacija launchd agenta

```bash
cp launchd/ai.domovina.nightly-build.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/ai.domovina.nightly-build.plist
launchctl print gui/$(id -u)/ai.domovina.nightly-build | head -20   # provjera
launchctl kickstart -k gui/$(id -u)/ai.domovina.nightly-build       # ručni okid
launchctl bootout gui/$(id -u)/ai.domovina.nightly-build            # gašenje
```

**Rule**: mora biti **LaunchAgent** (`gui/$(id -u)`), nikad LaunchDaemon.
`xcodebuild` potpisivanje traži otključan login keychain, a njega ima samo
korisnikova Aqua sesija. Daemon bi vidio zaključan keychain i visio.

**Rule**: `ProgramArguments[0]` je `/opt/homebrew/bin/bash`. `/bin/bash` je 3.2 i
nema `mapfile`; skripta se doduše sama re-execa na brew bash, ali plist to radi
eksplicitno da se ne oslanjamo na dva mehanizma.

Mac mini je na `sleep 0` / `displaysleep 0` (`pmset -g custom`) pa se raspored u
03:00 ispali pouzdano. Ako se to ikad promijeni, launchd će job pokrenuti tek
kad se stroj probudi — a ne u 03:00.

## Telegram

Grupa je **javna**, pa `telegram-notify.rb` prije slanja **redigira**: svaku
vrijednost iz `.env` dulju od 8 znakova, JWT-olike nizove, desnu stranu svakog
`--dart-define=KEY=VALUE` i bot tokene u URL-ovima. To je važno jer poruka o padu
nosi zadnjih ~1800 znakova build loga, a `flutter build … --dart-define=…` zna
završiti u ispisu greške.

**Rule**: sve što ide u Telegram mora proći kroz `telegram-notify.rb`. Ne slati
`curl`-om izravno na Bot API iz drugih skripti — zaobišao bi redakciju.

Preneseno iz `ms-toptal-projects/tools/job-watch/src/notify.js`:
- **supergroup migracija** — grupa promoviranjem u supergrupu dobije **novi**
  `chat_id`, a stari zauvijek vraća 400. Odgovor nosi `migrate_to_chat_id`;
  slijedimo ga i zapišemo u `.env`.
- **chunking na 3800** znakova (Telegram hard limit 4096), lom po recima.
- **retry** na 429/5xx uz `retry_after`.
- **poruka i na prazan dan** — 💤 „nema novih commitova" se šalje namjerno:
  njezin izostanak je jedini signal da je launchd crknuo.

Notifikacija je non-fatal: ako Telegram padne, build i upload i dalje vrijede.

## Disk je preduvjet, ne detalj

Nightly prije svega provjeri prostor i padne odmah s jasnom porukom ako ga nema.
Razlog je izmjeren 2026-08-13: boot volumen je bio na ~3 GiB slobodno i Android
build je pao nakon 3 minute uz

```
Failed to release lock on Build Output Cleanup Cache
Could not add entry ':shared_preferences_android:compileReleaseKotlin' to cache executionHistory.bin
[!] Gradle does not have execution permission.   ← Flutterova KRIVA dijagnoza
```

Nigdje ne piše „nema mjesta na disku". Bez preflighta bi se to svaku noć javljalo
kao misteriozan Gradle lock problem.

Pragovi (env-podesivi): `NIGHTLY_MIN_FREE_BOOT_GB` (default **8**),
`NIGHTLY_MIN_FREE_DD_GB` (default 15).

**Zašto je boot prag spušten s 20 na 8 GB (24.9.2026.)**: 20 GB je postavljeno
13.8., dok su DerivedData i Gradle cache (14+ GB) još bili na boot disku. Dan
kasnije preseljeni su u sparsebundle, ali prag je ostao. Od 13.8. do 23.9. odbio
je **18 noći** uz 7–14 GB slobodno, dakle više nego što je buildova prošlo (4),
i 18 dana zaredom (28.8.–15.9.) nije bilo novog builda. Na boot disku build sada
drži samo worktree `../.nightly-domovina` (~2 GB, trajno). Najveći potrošač koji
se mijenja je **swap**: raste s uptimeom (7 GB nakon 6 h), pa je nakon reboota
slobodno ~32 GB, a u 03:00 ~10 GB.

Izvještaj sada nosi red `boot disk: X GB na startu, najmanje Y GB tijekom builda`
(sampler svakih 20 s). Prag spuštati dalje samo uz te brojke.

**DerivedData je na vanjskom disku** — `IDECustomDerivedDataLocation` pokazuje na
`/Volumes/DOMOVINA2TB/xcode_temp_files/DerivedData/` (exFAT). Preflight provjeri i
da je taj volumen montiran, jer nakon reboota ili odspajanja `xcodebuild` padne s
2000 redaka ispisa koji nikad ne kažu „nema diska".

Najveći potrošači na ovom stroju (mjereno 2026-08-13): `~/Library/Containers/com.docker.docker`
30 GB (Docker.raw, od čega je reclaimable samo ~3 GB jer 19 kontejnera aktivno radi),
`~/.gradle` 14 GB, `~/fvm/versions` 5,8 GB (četiri Flutter SDK-a).

### Build artefakti idu na APFS disk DOMOVINA1TB

**Rule: cache s puno sitnih datoteka ide na APFS, nikad na exFAT** (exFAT s
blokom od 512 KB je 13.8.2026. napuhao Gradle home od 14 GB u 156 394 datoteke
na 41 GB).

```
/Volumes/DOMOVINA1TB/domovina_build/     (APFS, izravno na disku)
  ├── gradle/         ← GRADLE_USER_HOME nightlyja
  └── derived-data/   ← BUILD_DERIVED_DATA za xcodebuild
```

Obje mape su cache. Kad nedostaju, nightly napravi praznu `gradle/`, a Xcode
`derived-data/`; prvi build je sporiji jer sve skida ispočetka. Nikad ih ne
kopirati s diska na disk — obrisati i pustiti da se napune.

Do 26.9.2026. ovdje je bio APFS sparsebundle
`DOMOVINA2TB/domovina_ai_build_files/DOMOVINA_BUILD.sparsebundle`, montiran
na `/Volumes/DOMOVINA_BUILD` preko `launchd/ai.domovina.build-volume.plist`.
Čitanje kroz njega palo je na ~6 MB/s (Android emulator s AVD-om unutra
bootao je 17 min, s DOMOVINA1TB 16 s), pa su kontejner i launchd agent
uklonjeni.

**Xcode DerivedData**: globalni `IDECustomDerivedDataLocation` i dalje pokazuje na
goli exFAT (`/Volumes/DOMOVINA2TB/xcode_temp_files/DerivedData`, zatečeno 66 GB
zauzeća uz veliki dio otpada na 512 KB blokove). Nightly ga **ne dira** — koristi
vlastiti `-derivedDataPath` na DOMOVINA1TB. Bez toga Xcode svakoj putanji
projekta radi novi `Runner-<hash>`, pa bi worktree svaku noć ostavljao naslage.
GC prag: kad na kontejneru padne ispod `NIGHTLY_DD_GC_GB` (default 60), nightly
obriše svoj DerivedData prije builda.

## Poznate zamke

- **Prvi run mora biti nadziran.** `Apple Distribution: ITalk d.o.o. (6SCK58757K)`
  je u keychainu kao certifikat, ali ga `security find-identity` ne izlistava —
  privatni ključ nije lokalan, pa potpisivanje ovisi o `-allowProvisioningUpdates`
  koji u build-timeu razgovara s Appleom. Ako to ikad zatraži keychain dopuštenje,
  job visi na **nevidljivom** promptu. Zato prvi put pokreni preko
  `launchctl kickstart` dok gledaš ekran, ne pusti ga naslijepo u 03:00.
  Watchdog (`timeout`) svejedno prekine korak nakon zadanih minuta.
- **TestFlight buildovi istječu nakon 90 dana** i svaki upload šalje mail
  testerima ako grupa ima auto-distribuciju. Za nightly grupu je **isključi** —
  inače 30 mailova mjesečno.
- **Nightly ne promovira ništa na produkciju.** To je i dalje svjesna ručna
  radnja (`scripts/play-promote.sh` + ASC koraci iz `mobile-release-pipeline.md`).
- **`last-built-sha` se zapisuje samo na uspjeh** — pao build se sljedeću noć
  pokušava ponovno umjesto da bude preskočen kao „već obrađen".

## Smoke na uređajima farme (korak 8b, od 13.10.2026.)

<!-- doc-refs:ignore-start -->
<!-- .nightly/smoke/builds/ je izlaz nightlyja, ne datoteka u repou. -->

Nakon uploada i verifikacije storeova nightly zove
`scripts/nightly-smoke.sh <build>` nad 2 Androida i 2 iPhonea spojena na
ovaj Mac. Upload ne blokira; ishod ide u istu Telegram poruku i u
`.nightly/smoke/builds/<build>.txt`, koji čitaju vrata promocije
(`scripts/smoke-gate.sh` iz `asc-submit.rb` / `play-promote.sh`). Za iOS
`build-mobile-release.sh` uz `EXPORT_DEV_IPA=1` iz istog archivea izveze i
development IPA (`build/ios/ipa-dev/`), jer se App Store IPA ne da
instalirati na uređaj. `NIGHTLY_SMOKE=0` preskače korak.
<!-- doc-refs:ignore-end -->

Nije još provjereno pod launchd-om: iOS ui smoke treba mDNS prema iPhoneu
(macOS „Local Network” dozvola), a vožen je samo iz iTerma. Ako prva noć
javi iOS ui „nije provjereno”, to je prvi osumnjičenik.

Vezani dokumenti: `docs/plans/2026-10-13-smoke-testovi-na-uredajima.md`
(skripte, mjerenja, zamke uređaja).

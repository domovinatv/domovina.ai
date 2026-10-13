# Smoke testovi na pravim uređajima nakon nightly builda — plan

Status: **PLAN**, ništa nije implementirano (13. 10. 2026.).

<!-- doc-refs:ignore-start -->
<!-- .nightly/smoke/ su izlazne putanje koje skripta tek treba stvoriti. -->

## Cilj

Svaki build koji nightly pošalje na TestFlight i Play internal instalira se
na fizičke uređaje spojene na Mac mini i prođe kratak smoke. Ishod ide u
Telegram grupu uz broj builda: „205 radi” ili „205 pada na otvaranju
epizode, Android”. Kasnije se isti ishod koristi kao uvjet za promociju u
produkciju (faza 4).

Zašto lokalno, a ne GitHub Actions: GitHubovi macOS runneri nemaju prave
uređaje, samo iOS Simulator. Android emulator na ARM macOS runneru ne radi
(nema nested virtualizacije). Mac mini već gradi oba binarna paketa i ima
uređaje na USB-u.

## Uređaji (stanje 13. 10. 2026.)

| uređaj | veza | napomena |
|---|---|---|
| moto g86 5G, Android 16 | USB, `adb` serijski `ZY32M4Q2GJ` | spojen; zaključavanje „Ništa”; smoke prolazi (13.10.) |
| drugi Android | ? | trenutno ga `adb devices` ne vidi |
| stari iPhone | — | još nije spojen; treba Developer Mode i Auto-Lock „Nikad” |

`xcrun devicectl list devices` danas vidi iPhone 15 Pro i iPad 10, oba
`unavailable` (bežično, bez Developer Modea). Za smoke uređaj mora biti na
kabelu i otključan.

## Načelo: testira se binarni paket koji je otišao u store

Smoke vrti **isti build** koji je uploadan, ne zaseban debug build. Inače
bi testirao kod koji korisnik nikad ne dobije (release minifikacija,
R8/ProGuard i potpisivanje su upravo mjesta gdje release puca, a debug ne).

- **Android**: iz `app-release.aab` `bundletool build-apks --connected-device`
  napravi APK za spojeni uređaj i `bundletool install-apks` ga instalira.
  To je isti bytecode koji Play isporučuje. Potpis je naš upload ključ, ne
  Playev, pa se prije instalacije deinstalira postojeća verzija iz storea.
- **iOS**: IPA potpisan za App Store ne može se instalirati izravno na
  uređaj. Isti `Runner.xcarchive` zato se **eksportira drugi put** s
  `method: development` (zaseban `ExportOptions-dev.plist`). Kod je isti,
  razlikuje se samo potpis. Instalacija:
  `xcrun devicectl device install app`.

## Što smoke provjerava

### Razina 1: deep linkovi + detekcija crasha (bez UI automatizacije)

Aplikacija se otvara nizom ruta, za svaku se čeka N sekundi i provjerava
da je proces još živ:

1. hladni start (`/`)
2. epizoda s AI sadržajem (`/v/<id>`; ista epizoda kao `kTestVideoId` u
   `integration_test/rendering_test.dart`)
3. epizoda s timestampom (`/v/<id>/t/<sec>`): seek + reprodukcija
4. kanal (`/c/<slug>`), osoba (`/p/<slug>`), pretraga (`/?q=…`)

Poslije svakog koraka:

- **Android**: `adb logcat -b crash` (Java i native crash),
  `dumpsys dropbox --print data_app_crash data_app_anr`, `pidof ai.domovina`.
  Prije runa se `logcat -c` isprazni.
- **iOS**: `devicectl device process launch --payload-url …` otvara rutu;
  novi `.ips` zapisi za `Runner` iz `idevicecrashreport` (alat je već
  instaliran) znače crash.
- Uz to screenshot svakog koraka u `.nightly/smoke/<build>/`, lokalno, ne u
  Telegram. Grupa je javna, a na ekranu mogu biti podaci računa.

Prednost ove razine: ne treba pisati testove ni dodavati alat, a hvata
najskuplju klasu kvara, a to je build koji se sruši pri pokretanju ili na
ekranu epizode.

**Otvoreno pitanje (provjeriti u fazi 0)**: vodi li `ai.domovina://v/<id>`
na epizodu kroz go_router ili se custom scheme danas obrađuje samo za auth
callback? Na Androidu je alternativa `https://domovina.ai/v/<id>` (App Link
s allowlistom), ali ako verifikacija App Linka na uređaju nije prošla, link
otvori browser i test lažno prođe. Zato se uz svaki korak provjerava da je
`ai.domovina` u prednjem planu (`dumpsys activity activities` na Androidu).

### Razina 2: interaktivni tokovi

Tap na play, pauza, seek, promjena jezika HR↔EN, otvaranje panela playera,
pretraga s rezultatom. Dva kandidata:

- **Maestro** (YAML tokovi, crna kutija nad release buildom, čita
  accessibility stablo). Na Androidu radi nad pravim uređajem. Podršku za
  iOS na fizičkom uređaju treba provjeriti za verziju dostupnu u trenutku
  implementacije.
- **Flutter `integration_test`** preko `flutter drive --profile -d <uređaj>`.
  Pristup widgetima je bolji, ali gradi **zaseban** profile build iz istog
  SHA, što krši gornje načelo.

Odluka pada nakon razine 1. Ako Maestro radi na oba uređaja, ide Maestro.

## Tijek u nightlyju

Nova skripta `scripts/device-smoke.sh <build> [--android-only|--ios-only]`,
pokretljiva i ručno. Nightly je zove **nakon** uploada:

```
… → iOS/Android build → TestFlight + Play internal upload → device-smoke → Telegram
```

Smoke **ne blokira upload**. Build na TestFlightu i internalu je
interni, a informacija „205 pada” je vrijedna upravo zato što je build već
vani i nitko ga ne smije promovirati. Vrata su na promociji (faza 4), ne
na uploadu.

**Exit kodovi** (isti ugovor kao `--check` u voting tripwireu): `0` = prošlo,
`1` = aplikacija pada, `2` = ne mogu provjeriti (uređaj nije spojen,
zaključan je, nema mreže, CDN ne odgovara). Kod `2` nikad ne smije izgledati
kao `1`. Nespojen uređaj nije crash aplikacije.

Ishod po buildu ide u `.nightly/smoke/<build>.json`
(`{build, sha, platform, device, result, failed_step, log}`) za fazu 4.

**Telegram** kroz `telegram-notify.rb` (redigira `.env`). Poruka se
dodaje postojećoj nightly poruci, ne šalje se kao zasebna, npr.:

```
Smoke 2.0.183 (206)
  Android moto g86 (16) — prošlo 6/6
  iPhone <model> (<iOS>) — PAO: epizoda /v/H-p2Hl6x7I0, crash nakon 4 s
```

## Faze

| faza | sadržaj | gotovo kad |
|---|---|---|
| 0 | uređaji: iPhone na kabel + Developer Mode + Auto-Lock „Nikad”; Android `svc power stayon usb`, isključeni lock screen i automatska ažuriranja; provjera deep link rute | `adb devices` i `devicectl` vide sve uređaje, ruta otvara epizodu |
| 1 | `device-smoke.sh` razina 1, Android | ručni run nad buildom 205 prođe; namjerno slomljen build padne |
| 2 | iOS: dev export istog archivea + razina 1 | isto, na iPhoneu |
| 3 | spajanje u nightly + Telegram + `.nightly/smoke/*.json` | jedna noć s porukom za oba uređaja |
| 4 | promocija na uvjet: `asc-submit`/`play-promote` traže `result: pass` za taj build; Play kao staged rollout | promocija bez smoke rezultata se odbije |
| 5 | razina 2 (Maestro ili `integration_test`) | tokovi reprodukcije i jezika na oba OS-a |
| 6 | crash reporting s pravih korisnika (Sentry), Play Vitals kao uvjet za podizanje rollouta | — |

Faza 1 mora uključiti **negativni test**: build koji se namjerno sruši
(npr. `throw` iza `--dart-define=SMOKE_CRASH=1`) mora dati exit `1` i
crvenu poruku. Smoke koji nikad nije vidio pad nije dokazao ništa.

## Zamke koje već znamo

- **Zaključan Android**: test pokrenut iza lock screena padne na prvom
  dohvatu s CDN-a (`Failed host lookup … errno = 7`), iako `adb shell ping`
  s istog telefona radi i `InternetAddress.lookup` u istom procesu prije
  `app.main()` prolazi. Izmjereno 13.10.2026. na moto g86 (5 runova).
  Uzrok: aplikacija iza keyguarda nije u prvom planu pa joj Android ne
  pušta mrežu. Potvrđeno istog dana: sa zaključavanjem „Ništa” isti test
  prođe svih 8 koraka za 1:16. `smoke-device.sh` zato
  budi uređaj, miče keyguard i na PIN/uzorak vraća exit 2. Telefon treba
  zaključavanje „Ništa”.
- **Nakon pada runner visi**: `flutter test` je nakon pada visio 10 min u
  `tearDownAll`. Skripta ga zato vrti pod `gtimeout 15m`, a „Some tests
  failed” u logu ima prednost pred timeoutom (pad ostaje exit 1).
- **Zaključan iPhone**: `devicectl` ne pokreće aplikaciju na zaključanom
  uređaju. Auto-Lock „Nikad” + uređaj stalno na punjaču. Ako je ipak
  zaključan, to je exit `2`.
- **Baterija na stalnom punjenju**: Android ima „Adaptive charging” / limit
  punjenja, uključiti ga. iPhone ima „Optimised Battery Charging”.
- **launchd i Aqua sesija**: nightly je LaunchAgent (`gui/$(id -u)`), što
  `devicectl` treba. Daemon ne bi vidio uređaje.
- **Mreža**: smoke ovisi o živom CDN-u. Ako `https://cdn.domovina.ai/` ne
  odgovara 200 prije runa, to je exit `2`.
- **Nema anonimne prijave**: smoke radi kao gost (v2.0.172+). Ništa u
  smokeu ne smije zvati prijavu (vidi `test/no_anonymous_sign_in_test.dart`).
- **Play `install-apks` i postojeća store instalacija**: različit potpis →
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE`. Prije instalacije `adb uninstall ai.domovina`.
  Telefon se zato ne koristi za osobno slušanje.

<!-- doc-refs:ignore-end -->

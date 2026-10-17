# Android TV (Leanback) podrška

Standalone 10-foot UI varijanta DOMOVINA.ai aplikacije za Android TV uređaje (Philips,
EON Smart Box, NVIDIA Shield, Chromecast s Google TV-om, itd.). Ne pokušava se
retrofitati postojeći desktop/mobile layout — paralelni `lib/screens/tv/` modul
dijeli `services/*` i `models/*` s ostatkom aplikacije, ali ima vlastiti home,
channel, episode/player i widget set.

## TV detekcija flow

Detekcija je sinhrona u runtimeu (resolve-ana jednom u `main()` prije `runApp`):

```
main()                                            lib/main.dart
  └─ await TvMode.init()                          lib/services/tv_mode.dart
       ├─ if (FORCE_TV dart-define) → isTv=true
       ├─ if (kIsWeb || !Android)    → isTv=false
       └─ else MethodChannel("app/tv_mode").invokeMethod("isLeanback")
            └─ MainActivity.kt
                 packageManager.hasSystemFeature(FEATURE_LEANBACK) → true/false
```

Nakon `init()`, `TvMode.isTv` je sync getter koji čitaju:

- **`lib/main.dart`** — odabire `AppTheme.tv()` umjesto `light()/dark()` + forsira `ThemeMode.dark`
- **`lib/router/app_router.dart`** — `/` ruta i `errorPageBuilder` rute na `TvHomeScreen` umjesto `HomeScreen`

URL strukturu (`/`, `/c/:slug`, `/v/:id`, itd.) **držimo identičnu** za TV i ne-TV — bitno
za deep linking, social sharing, i potencijalan handoff iz mobitela na TV kasnije.

## Dev workflow

### Lokalno (Mac/Chrome) — primarni iteracijski loop

```bash
flutter run -d macos  --dart-define=FORCE_TV=true
flutter run -d chrome --dart-define=FORCE_TV=true
```

Tab/Shift+Tab simulira D-pad LEFT/RIGHT, Enter = OK. Većina Faze 2-5 razvija se
ovako jer je hot reload <1s. TV se koristi za finalni sanity check po fazi.

### Na pravom Android TV uređaju

ADB-over-Tailscale je najbolji setup (vidi memory `tv_dev_workflow.md`):

```bash
adb connect <tailscale-hostname>:5555
flutter devices                                # provjera
flutter run -d <ip>:5555                       # bez FORCE_TV — pravi Leanback
adb -s <ip>:5555 logcat -s flutter             # uživo logovi
scrcpy --tcpip=<ip>:5555                       # mirror TV ekrana na Mac
```

Operatorski Android TV box-ovi (Telemach EON, A1, T-Com) često **otvaraju port
5555 čim uključiš USB debugging u Developer Options** — ne treba USB ni `adb pair`.
Provjera: `nc -zv <ip> 5555`.

## Faza plan

| Faza | Status | Sadržaj |
|---|---|---|
| 1 | Gotovo | TV detekcija (MethodChannel + FORCE_TV), `AppTheme.tv()`, Leanback launcher manifest |
| 2 | Gotovo | Railovi naslovnice (`HomeFeed`, `WatchProgressService`, `ChannelCache`), `TvFocusable`/`TvRail`/`TvHero`/kartice, skeletoni |
| 3 | Gotovo | `TvChannelScreen` (`/c/:slug`) i `TvPersonScreen` (`/p/:slug`) — mreža epizoda s D-padom |
| 4 | Gotovo | `TvEpisodeScreen` (`/v/:id`, i `/t/`, `/en` varijante) — player s poglavljima, fullscreen, overlay |
| 4.1 | Gotovo | `TvEpisodeReaderScreen` (`/v/:id/read`) — članak po sekcijama, video u kutu |
| 2.5 | Nije počelo | TV pretraga |
| 4.5 | Nije počelo | TV handoff prijava (kod + QR) |
| 5 | Djelomično | Banner PNG postoji; TV listing u Play Consoleu nije provjeren |

Od 17. 10. 2026. TV se usklađuje s ostatkom aplikacije (sponzorski trenuci,
faza obrade, titlovi, …) i reprodukcija ide kroz zajedničku
`EpisodePlaybackSession`. Inventura razlika i redoslijed:
`docs/plans/2026-10-17-tv-uskladivanje-i-refaktor.md`.

### Reprodukcija i dekoder

Oba TV ekrana epizode dijele jednu `EpisodePlaybackSession` po videu
(`acquire`/`release`) — čitač nastavlja player epizode ispod sebe u stogu.
mpv dobiva `hwdec-codecs` bez `av1` (EON AV1 mediacodec prijavi, a ne
dekodira), pa H.264 ide hardverski, a stari AV1 `video.mp4` softverski. Za
mjerenje na uređaju: `--dart-define=MPV_HWDEC=no` (ili druga mpv vrijednost);
logcat svakih 60 s piše `PlaybackSession stats: codec=… hwdec-current=…
frame-drop=…`.

## Build & deploy

```bash
flutter build apk --debug                      # za sideload
flutter build appbundle --release              # za Play Store TV track
adb install build/app/outputs/flutter-apk/app-debug.apk
```

`scripts/deploy.sh` ostaje web-only (Cloudflare Pages). TV release ima vlastiti
track u Play Console-u — listing zahtijeva 3 TV screenshota 1920×1080, banner
320×180 (trenutno placeholder XML, vidi `android/.../drawable/tv_banner.xml`),
i `<uses-feature leanback />` u manifestu (već postoji).

## Focus model (Faza 1+)

Svaki interaktivni element ima vlastiti `FocusNode` + `FocusableActionDetector`.
Vizualna pravila:

- **Card fokus**: scale 1.08 + 4px ring u `colorScheme.primary` (crveni)
- **Primary button fokus**: scale 1.06 + 4px ring u `colorScheme.onSurface` (bijeli na crvenom)
- **Subtle button fokus**: `primaryContainer` background + 4px ring u `primary`
- **Auto-scroll**: `Scrollable.ensureVisible(alignment: 0.5)` kad fokus dođe na karticu izvan viewport-a

Detalji: `lib/screens/tv/tv_home_screen.dart` (Faza 1 lokalni helperi se
promoviraju u `lib/screens/tv/widgets/` kad počnu služiti drugim TV screenovima
u Fazi 2+).

## Theme adjustments

`AppTheme.tv()` (`lib/theme/app_theme.dart`):

- Dark base (Croatian navy seed, `Brightness.dark`)
- 1.3× tipografija (`textTheme.apply(fontSizeFactor: 1.3)`)
- Crveni `tertiary` ostaje za primarne CTA (PLAY)
- Ostatak ColorScheme tokena nasljeđen iz `_build(scheme)` — `surface`, `outline`,
  `surfaceContainerHighest`, itd. su konzistentni s dark mode-om

## Rezolucija, density i dp (zašto 960×540)

Čest izvor zabune. EON prijavljuje logički ekran `960×540 dp`, što izgleda kao
niska rezolucija — **nije**. To je logički dp prostor, ne broj piksela.

### dp je fizička veličina, ne broj piksela

`dp` je apstrakcija fizičke veličine (mdpi baseline: 1 dp ≈ 1/160 inča), NE
piksela. `density` mapira dp → piksele:

```
density 320dpi → devicePixelRatio (dpr) = 2.0
fizički framebuffer:  1920×1080 px   (ono što EON stvarno crta — oštro)
logički canvas:        960× 540 dp   = px / dpr   (prostor za widgete)
1 dp = 2×2 = 4 fizička piksela
```

Identično Retina ekranu. Flutter rasterizira vektorski (tekst, oblici) na razini
framebuffera, pa je UI uvijek oštar u 1080p — `dpr` određuje **veličinu**
elemenata, ne oštrinu. Veći density = veći elementi = čitljivo s 10-foot (3m)
udaljenosti.

### Logički canvas NIJE konstantan — ovisi o density-ju koji OEM postavi

```
Panel              density      dpr    logički canvas
1080p @ xhdpi      320          2.0    960×540 dp     ← EON, Googleov preporučeni default
1080p @ mdpi       160          1.0    1920×1080 dp   ← jeftini boxovi, sve sitno
720p  @ tvdpi      213          1.33   1444×812 dp
4K    @ xxxhdpi    640          4.0    960×540 dp     ← nativni 4K, 1 dp = 4×4 px
```

Googleova konvencija: 1080p→xhdpi, 4K→xxxhdpi, tako da **logički canvas ostaje
~960×540 dp** i na 1080p i na 4K (density skalira s rezolucijom). Pa ~960×540 jest
de-facto Android TV 16:9 grid u ispravnoj konfiguraciji. ALI density postavlja
OEM, a jeftini boxovi ga zezaju (prijave 160/213) → zato se NE smije hardkodirati
960×540.

### Display lanac kad je 4K TV iza 1080p boxa

EON → 1080p HDMI izlaz → Philips 4K panel **upscalira (interpolira)** 1080p→2160p:
1 logički dp završi kao 4×4 = 16 fizičkih LED-ica, ali interpolirano (blago meko).
Na **Full HD** TV-u nema upscalea → 1 dp = 2×2 = 4 nativne LED-ice, pixel-perfect.
Nativni 4K UI bi tražio 4K HDMI izlaz + jaču GPU (Amlogic već janka na 1080p);
za EON 1080p je ispravan perf kompromis. Ovo je display/HDMI/system stvar — **ne
kontrolira se iz Flutter codebasea**.

### Posljedica za layout

Dizajniraj responsive u dp, ne za fiksni 960×540. `TvMetrics`
(`lib/screens/tv/widgets/tv_metrics.dart`) čita stvarni `MediaQuery.size`, skalira
relativno na /540 baseline (clamp [0.85, 1.15]) i koristi % širine za paddinge —
tako isti app radi na cijelom rasponu TV logičkih veličina. Za lokalni
EON-matched emulator vidi `docs/android-tv-emulator.md`.

## Known device quirks

- **Telemach EON Smart Box (SDMC SDSTB02)**: Android 11, ali density je 320 dpi
  što daje logički ekran 960×540 dp na 1080p TV-u. `TvHomeScreen` koristi
  `LayoutBuilder` da hero skalira na 45% visine (clamp 220-380 dp).
- **Philips 55PUS7303/12 (Android 8.0 Saphi)**: ADB authorization dialog je
  bug-an na operator-customized Saphi launcheru. Bez USB-a ne može se autorizirati
  ključ. Workaround: jednokratni USB visit s `adb tcpip 5555` +
  `setprop persist.adb.tcp.port 5555` preživi reboot.

## Files added/modified

**Faza 1** (commit `52096ed`):
```
lib/services/tv_mode.dart                                  +new
lib/screens/tv/tv_home_screen.dart                         +new (placeholder skeleton)
lib/theme/app_theme.dart                                   +tv() factory
lib/main.dart                                              +TvMode.init() + theme branch
lib/router/app_router.dart                                 +TV import + / route + error branch
android/app/src/main/AndroidManifest.xml                   +leanback features + LEANBACK_LAUNCHER + banner
android/app/src/main/kotlin/ai/domovina/MainActivity.kt    +MethodChannel handler
android/app/src/main/res/drawable/tv_banner.xml            +new placeholder
```

**Faza 2**:
```
lib/screens/tv/tv_home_screen.dart                         refactor — data wiring
lib/screens/tv/widgets/tv_focus.dart                       +new (TvFocusable + TvFocusStyle)
lib/screens/tv/widgets/tv_rail.dart                        +new (eyebrow + horizontal ListView)
lib/screens/tv/widgets/tv_episode_card.dart                +new (16:9 thumb + score badge + progress)
lib/screens/tv/widgets/tv_channel_card.dart                +new (square avatar + name + count)
lib/screens/tv/widgets/tv_hero.dart                        +new (backdrop + gradient + PLAY CTA)
```

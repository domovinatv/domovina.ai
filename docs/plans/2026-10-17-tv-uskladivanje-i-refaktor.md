# Android TV — usklađivanje s aplikacijom i refaktor (plan)

Datum: 17. 10. 2026. Stanje: analiza, ništa još nije promijenjeno u kodu.

## Zaključak

TV modul (`lib/screens/tv/`, ~6 300 redaka) zadnji je put funkcionalno rastao
u srpnju 2026. Od tada su web i mobitel dobili desetak značajki koje TV nema, a
od kojih je jedna obveza, ne želja: **plaćeni sponzorski trenuci moraju nositi
oznaku „Sponzorirano · {brand}" na SVAKOJ površini reprodukcije** (DSA čl. 26,
pravilo „tri mjesta, jedan kontroler"). TV je četvrta površina koju to pravilo
ne spominje.

Uzrok drifta nije TV kod sam po sebi, nego to što je **životni ciklus playera
napisan tri puta**: `episode_screen.dart` (~1484), `tv_episode_screen.dart`
(`_initPlayer`) i `tv_episode_reader_screen.dart` (`_initPlayer`, vlastiti
`Player`). Svaka nova stvar oko reprodukcije (resume, analitika, sponzori,
titlovi, brzina, seek-undo) ide u prvi, a druga dva zaostaju. Refaktor zato
počinje izdvajanjem tog ciklusa, a značajke se na TV dodaju tek nad njim.

## Inventura: što TV ima, a što ne (izmjereno nad kodom 17. 10.)

| Područje | Web/mobitel | TV | Napomena |
|---|---|---|---|
| Naslovnica — izvor | `loadHomeSnapshot()` (`home.json`, ~6 KB) + `heroPoolComplete` latch | čeka `ChannelCache.done` (svih 50 listinga) | TV hero čeka 3–10 s, web se otkriva čim je izbor dokazivo konačan |
| Naslovnica — railovi | hero karusel, Nastavi, Najnovije, Upravo stiglo, praćeni, favoriti, glasanje, osobe | jedan hero, Nastavi, Najnovije, Osobe, kanali | |
| Epizoda — faza obrade | `EpisodeStatus` + `EpisodeStatusCard`, `_QueuedEpisodeScreen` | samo „nije pronađena" / greška | epizoda bez medije na TV-u je slijepa ulica |
| Titlovi | `diarized.srt` + `words.json`, `SubtitleStrip`/overlay | nema | |
| Brzina, seek-undo | `PlaybackSpeed`, `SeekUndo` | nema | |
| Sponzori u snimci | `SponsorsInVideo` + „Poslušaj" | nema | |
| Plaćeni sponzorski trenuci | `SponsoredMomentsController` na 3 površine | **nema** | pravna obveza kad trenuci postanu živi |
| Jezik sadržaja (EN) | `EpisodeLanguageScope`, `pickLang` | `/v/:id/en` crta isti HR ekran | |
| Analitika reprodukcije | `PlaybackAnalytics` | epizoda da, **čitač ne** | |
| Prijelaz epizoda → čitač | — | čitač stvara **novi** `Player` | video kreće ispočetka / ponovno buffera |
| Pretraga | paleta (lokalno + Meili + semantika) | nema (faza 2.5 nikad počela) | |
| Prijava | sheet, OAuth, passkey, Certilia | nema (handoff faza 4.5 nikad počela) | bez prijave nema favorita/praćenih |
| Hardverski dekoder | — | `hwdec=no` **uvijek** (`tv_episode_screen.dart:236`) | komentar pretpostavlja AV1; danas se bira H.264 (fmp4) |
| Testovi | desetci | samo `tv_row_traversal_test.dart` | smoke farma nema TV |

Rute koje ruter na TV-u NE preusmjerava (`/channels`, `/m/*`, `/yt/*`,
`/search`, `/favorites`, `/glasanje`, `/obavijesti`, `/account`, `/handoff`)
crtaju web/mobilni ekran. Danas su dosežne samo deep linkom, ali neprovjereno je
jesu li upotrebljive D-padom.

## Plan

### R0 — higijena (mali, bez rizika)

- `docs/android-tv.md`: tablica faza na stvarno stanje (3 i 4 su gotove, čitač
  postoji), poveznica na ovaj plan.
- `hwdec`: `no` samo kad je izvor AV1 (`video.mp4`), inače default. **Prvo
  mjerenje na EON-u** (dropped frames, CPU) na H.264 i fmp4, tek onda commit.

### R1 — zajednička sesija reprodukcije (srž refaktora)

Izdvojiti `EpisodePlaybackSession` (servis, ne widget): otvaranje `Player`a,
resume (`PlayerResume`), spremanje napretka, `PlaybackAnalytics`, `SeekUndo`,
`PlaybackSpeed`, praćenje aktivnog poglavlja, `SponsoredMomentsController`,
`_checkSponsorClip`. Tri ekrana ga koriste umjesto vlastitog koda.

- Redoslijed: prvo TV epizoda i čitač (manji, lakše provjeriti), pa
  `episode_screen.dart` tek kad je API dokazan — taj ekran je 3 899 redaka i
  pod njim su web zamke (re-parent `<video>`, muted autoplay), pa ide u
  zasebnom koraku uz pun prolaz testova.
- Čitač dobiva **istu** sesiju od epizode (bez novog `Player`a) — prijelaz bez
  ponovnog bufferiranja.
- Platformske razlike (mpv `setProperty` na TV-u, `media_element_mute_web`)
  ostaju kao opcije sesije, ne kao grananje po ekranima.

### R2 — epizoda na TV-u dostiže web

Nad R1, redom vrijednosti:

1. `EpisodeStatus` — umjesto „nije pronađena": faza obrade + (native nema
   iframe) QR na youtube.com za epizode bez medije.
2. Plaćeni sponzorski trenuci — traka „Sponzorirano · {brand}" u TV playeru
   (+ ažurirati CLAUDE.md pravilo s „tri" na „četiri" mjesta).
3. Titlovi (`SubtitleStrip` logika, isticanje riječi) — TV je mjesto gdje se
   titlovi najviše čitaju.
4. Sponzori u snimci, brzina reprodukcije.
5. EN sadržaj (`pickLang` u članku čitača i u poglavljima).

### R3 — naslovnica

`loadHomeSnapshot()` + `heroPoolComplete` umjesto čekanja `done`; hero kao
karusel (`pickFeaturedCarousel`); rail „Upravo stiglo" (`freshlyArrived`).
Mjeriti vrijeme do prvog fokusa na EON-u prije i poslije.

### R4 — pretraga i prijava (odlučiti nakon Casta D1)

Ako će se TV uglavnom puniti castom s mobitela, pretraga i prijava na TV-u
padaju na prioritetu. Inače: TV pretraga nad `unified_search` s ekranskom
tipkovnicom, pa handoff prijava (kod + QR, `/handoff` već postoji na webu).

### R5 — mreža sigurnosti

- Widget testovi za TV ekrane s `FORCE_TV` (fokus, BACK, prijelaz u čitač).
- Revizija ruta bez TV varijante: preusmjeriti ili omogućiti D-pad.
- Eventualno EON u smoke farmi (ADB preko Tailscalea je već tu).

## Otvorena pitanja

- Smije li R1 dirati `episode_screen.dart` u istom ciklusu ili tek kad TV dio
  odradi tjedan na EON-u?
- Prioritet R4 ovisi o odluci o Castu.

## Napredak

### 17. 10. 2026. — R0 + R1 (TV dio)

- `EpisodePlaybackSession` (`lib/services/episode_playback_session.dart`):
  player, resume, spremanje napretka, analitika, poll do prvog framea, mpv
  postavke. `acquire`/`release` po videu — `TvEpisodeScreen` i
  `TvEpisodeReaderScreen` dijele isti player. Ugovor čuva
  `test/episode_playback_session_test.dart`.
- **Popravljen bug**: od `6bd9d61` (drill-down pusha stog) epizoda je ostajala
  montirana ispod čitača i njezin player je svirao dalje dok je čitač
  pokretao drugi — dva zvuka. Čitač usput dobiva i analitiku reprodukcije.
- Dekoder: umjesto `hwdec=no` za sve, `hwdec-codecs` bez `av1` (default
  media_kita je `auto-safe`). `--dart-define=MPV_HWDEC=no` vraća staro
  ponašanje za usporedbu; logcat svakih 60 s `PlaybackSession stats`.
- `docs/android-tv.md`: tablica faza na stvarno stanje.

**Nije još provjereno na EON-u** (100.67.17.53, na njemu je 2.0.22). Sljedeća
sesija, prije ičega drugog:

1. `flutter build apk --profile --target-platform android-arm`, instalirati,
   pustiti H.264 epizodu: `adb logcat | grep PlaybackSession` →
   `hwdec-current` mora biti `mediacodec*`, `frame-drop` ~0; `top` CPU.
2. Isto s `--dart-define=MPV_HWDEC=no` (staro ponašanje) — usporedba CPU-a i
   dropova. Ako hardver ispadne lošiji, default vratiti na `no` u sesiji.
3. Epizoda → „Čitaj" → nazad: jedan zvuk, pozicija se nastavlja.
4. Tek tada ažurirati CLAUDE.md sekciju „Android TV — AV1" (još citira
   `setProperty('hwdec','no')` u `tv_episode_screen.dart`).
5. Uređaj otključati: `rmdir ~/.device-farm/locks/100.67.17.53`.

### Sljedeće: R2.1 (faza obrade na TV-u) — nalazi, kod nije pisan

- `EpisodeData.load` baca `VideoNotFoundException` na 404 `info.json` → TV
  danas pokaže „nije pronađena". Treba kao web: `channelCache.findVideoAsync`
  → ako je nađena, naslov + `EpisodeStatusCard` (queued) + gumb „Gledaj na
  YouTubeu" (`openUrl` na `youtube.com/watch?v=` — Android TV ga otvara u
  YouTube aplikaciji); `ytMatched == false` → bez gumba.
- `info` postoji, `!data.hasMedia` → TV danas otvara prazan URI (vječni
  spinner). Ne otvarati sesiju; isti prikaz sa `data.status`.
- Ima medije, `status.stage != published` → `EpisodeStatusCard` umjesto
  stupca poglavlja (kojih tada ionako nema; vidi `_buildBody`, `hasChapters`).
- Novi widget u `screens/tv/widgets/`, postojeći ARB ključevi:
  `episodeWatchOnYouTube`, `tvEpisodeNotFound`, `commonGoHome`.

# Prvi frame videa: kritični put ekrana epizode (19. 11. 2026.)

## Zaključak

Prvi frame na ekranu epizode nije spor zbog videa ni CDN-a. Iste datoteke u običnom
`<video>` elementu daju prvi frame za **80–150 ms**, a 1080p jednako brzo kao 360p.
U aplikaciji (web build, hladni start, emulirani mobitel) prvi frame dolazi za **10,1 s**,
od čega je sam video oko **1,6 s (16 %)**. Ostatak je pokretanje aplikacije i redoslijed
učitavanja: player dobije URL tek kad `EpisodeData.loadWithProgress` učita i
isparsira sve artefakte epizode.

Format datoteke (`video_h264.mp4` → fmp4 → `fmp4_web`) riješen je 11. 10.
(`docs/2026-10-11-brzi-start-videa-fmp4.md`). Daljnji rad na formatu ne donosi ništa
vidljivo. Dobitak je u tome da video krene čim je poznat njegov URL.

## Mjerenja

Epizoda `RdEN7Ny1bV8` (re:DEFINICIJA ep. 11, muzevni_budite, 74:36) i ručni isječak
`clips/RdEN7Ny1bV8/RdEN7Ny1bV8_30m16s-36m32s_1080p.mp4` (6:16, H.264 High
1920×1080, 2,6 Mbit/s). Epizoda je H.264 Main 640×360, video 95 kbit/s.

### Sam video, bez aplikacije

| Datoteka | ffmpeg `-frames:v 1` s CDN-a (kao libmpv) | Chrome, običan `<video>`, svjež kontekst |
|---|---|---|
| isječak 1080p (moov 288 KB, faststart) | 0,22–0,41 s | 80 / 99 ms |
| `video_h264.mp4` 360p (moov 3,4 MB) | 0,22–0,39 s | 149 / 133 ms |
| `video_h264_fmp4_web.mp4?g=1` 360p (zaglavlje ~20 KB) | 0,34–0,39 s | 117 / 78 ms |

CDN: range GET je `cf-cache-status: HIT`, TTFB ~50 ms, 1 MB za ~90 ms.
(`curl -I` javlja `DYNAMIC`, ali HEAD i GET se na ovom CDN-u razlikuju. Mjeri se GET.)
Svaki novi query string (`?zz=…`) je novi cache ključ, pa prvi zahtjev ide u MISS.
Mjerenja s dodanim parametrom za razbijanje cachea zato lažu.

### Aplikacija, `https://domovina.ai/v/RdEN7Ny1bV8`, hladni start

Chrome DevTools MCP, svaki run u vlastitom izoliranom kontekstu. `initScript` presreće
`HTMLMediaElement.src` i bilježi `loadedmetadata`, `loadeddata` i
`requestVideoFrameCallback` (= prvi iscrtani frame), uz `longtask` observer.

| Trenutak (ms od navigacije) | Desktop, bez prigušenja | Mobitel: Fast 4G, CPU 4×, 412×915 |
|---|---|---|
| `skwasm.wasm` + `main.dart.wasm` skinuti | ~760 | 3363 / 3982 |
| `GET /api/katalog/v1/settings` | 582–605 | 4586–4752 |
| `GET episode.json` | 710–863 | **5661**–5931 |
| long task na glavnom threadu | 952 (+443) | 6432 (**+1854**) |
| `video.src` postavljen | 1413 | **8487** |
| prvi zahtjev za video | 1417 | 8667 |
| `loadedmetadata` | 1664 | 10092 |
| **prvi frame** | **1685** | **10120** |

Prije zahtjeva za video na mobitelu ide 40 drugih zahtjeva.

Raspodjela na mobitelu:

| Dio | Trajanje |
|---|---|
| boot wasma | ~4,0 s |
| settings → `episode.json` (jedno za drugim, s rupom ~0,9 s) | ~1,9 s |
| čekanje ostalih artefakata + parsing + build (long task 1,85 s) | ~2,6 s |
| video: zahtjev → prvi frame | ~1,6 s |

Prvi desktop run je imao drugi range zahtjev od 1,27 s (prvi frame 3,8 s). Ponovljeni
run u svježem kontekstu dao je 1,69 s, pa je onaj prvi tretiran kao šum.

**Nativna aplikacija (libmpv) nije mjerena.** Tamo nema boota wasma, ali isto čekanje
na artefakte i isti parsing postoje, jer je kod u `podcast_core` zajednički.

## Uzrok u kodu

1. `EpisodeScreen._load()` (`packages/podcast_core/lib/screens/episode_screen.dart`)
   čeka `EpisodeData.loadWithProgress(...)`. Tek tada `setState(() => _data = data)`
   gradi `_EpisodeContent`, a njegov `initState` zove `_initVideo()` → `Player()` →
   `openAndResume`.
2. `loadWithProgress` / `load` (`packages/podcast_core/lib/services/data_service.dart`)
   paralelno pokreće ~18 učitavanja (info, summary, outline, article, 5× Magisterium,
   EN overlayi, `resolveMedia()`…), ali `await`-a ih redom i vraća `EpisodeData`
   tek kad su SVA gotova. Titlove je već skinuo s kritičnog puta (`onTimeline`), ostalo
   je i dalje na njemu.
3. `resolveMedia()` treba samo `_allowed(cdnPlayback)` (postavke kanala) i `_bundle()`
   (`episode.json`). URL videa je dakle poznat odmah nakon `episode.json`, ali se ne
   koristi dok ne stigne sve ostalo.
4. Postavke kanala (`/api/katalog/v1/settings`) i `episode.json` idu jedno za drugim.
5. Long task od 1,85 s (CPU 4×) između `episode.json` i `video.src` nije profiliran.
   Kandidati: dekodiranje JSON-a artefakata, `EpisodeData`, layout članka s ~30
   screenshotova.

## Smjer popravka (za implementaciju)

- Pokrenuti download videa čim je URL poznat, neovisno o ostatku `EpisodeData`.
  Primjeri: stvoriti `Player` i `open(..., play: false)` čim `resolveMedia()` završi,
  pa ga predati ekranu. Ili ekran gradi player stupac odmah s URL-om, a članak dolazi
  kasnije.
- Postavke kanala i `episode.json` dohvaćati paralelno.
- Profilirati i razbiti long task (Flutter DevTools / Chrome Performance).
- Web, za kasnije: `<link rel="preload">` ili rani `fetch` zaglavlja videa iz
  `_worker.js` za `/v/:id`, dok se wasm još skida (URL je deterministički:
  `data/{id}/video_h264_fmp4_web.mp4?g=1` kad ga bundle navodi).
- Ograde koje moraju ostati: `cdn_playback` isključen = nema playera (fail-closed),
  WebKit ostaje na `video_h264.mp4`, resume-seek čeka duration (`player_resume.dart`),
  `?g=` cache-buster mora ostati isti, inače CDN MISS.

## Reprodukcija

```bash
# ffmpeg, prvi frame s CDN-a
time ffmpeg -nostdin -loglevel error -i "https://cdn.domovina.ai/data/RdEN7Ny1bV8/video_h264_fmp4_web.mp4?g=1" -frames:v 1 -f null -
```

Aplikacija: Chrome DevTools MCP `new_page` s `isolatedContext`, `emulate`
(`Fast 4G`, `cpuThrottlingRate: 4`), `navigate_page` s `initScript` koji presreće
`HTMLMediaElement.prototype.src` i registrira `requestVideoFrameCallback` +
`PerformanceObserver({type:'longtask'})`. Zatim `evaluate_script` čita
`performance.getEntriesByType('resource')`.

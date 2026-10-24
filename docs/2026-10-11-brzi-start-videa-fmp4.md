# Brzi start videa — fragmentirani MP4 (11. 10. 2026.)

## Zaključak

`video_h264.mp4` ima `faststart`, ali `moov` indeksira **svaki** uzorak: za epizodu
od 1 h (`PPXbSP14H4Y`, 92 MB) to je **2,73 MB** koje player mora povući prije prvog
framea ili zvuka. Iste struje prepakirane (`-c copy`) u fragmentirani MP4 sa `sidx`
imaju zaglavlje od **10,5 KB**. Pipeline od 11. 10. uz `video_h264.mp4` uploada i
`data/{id}/video_h264_fmp4.mp4`, a klijent ga bira kad ga `episode.json` navodi.

- Stari katalog se **ne** backfilla; ručno su obrađene epizode od 10. 10.
  (`PPXbSP14H4Y`, `sf_eM7e4XVY`, `XwgjW2crt6U`, `e7gdlnWZ6W0`, `8Php54O2M-Y`).
- **WebKit (Safari, svi iOS preglednici) je isključen** (`isWebKitBrowser`) dok se
  ne isproba na pravom uređaju. Native (libmpv, iOS/Android/macOS/TV) i Chromium su
  izmjereni.
- `video_h264.mp4` ostaje: fallback, cutter, stari buildovi, WebKit.

## Uzrok

`moov` epizode `PPXbSP14H4Y` (3601,6 s; video 70 kbps, audio AAC 130 kbps):

| box | veličina |
|---|---|
| video `ctts` (B-frameovi) | 706 KB |
| audio `stsz` (168 823 AAC frameova) | 675 KB |
| video `stsz` / `stco` | 360 KB / 360 KB |
| audio `stco` / `stsc` | 360 KB / 270 KB |

Svaki uzorak je svoj chunk, pa indeks raste s trajanjem, a ne s kvalitetom.
Ponovno kodiranje bez B-frameova spušta `moov` samo na 2,0 MB.

## Mjerenja (Chrome, DevTools „Slow 4G", čisti `<video>`)

| varijanta | prvi frame / zvuk | nastavak od 30:00 |
|---|---|---|
| `video_h264.mp4` s CDN-a | 15,9 s | — |
| ista datoteka s localhosta | 15,9 s | 17,1 s |
| bez B-frameova, audio 64k (`moov` 2,0 MB) | 12,1 s | — |
| fragmentirani **bez** `sidx` | nije krenuo u 120 s (140 range zahtjeva) | — |
| **fragmentirani + `sidx`** | **2,6 s** | **5,9 s** |
| samo audio, AAC 128k `.m4a` | 4,4 s | — |
| samo audio, MP3 64k mono | 0,8 s | 1,5 s |

CDN nije usko grlo (CDN = localhost), a range zahtjevi su `HIT`. Bez `sidx` Chrome
ne zna gdje je koji fragment — zato `verifyFmp4` u pipelineu odbija takav izlaz.
Struje su bit-identične: `ffmpeg -f streamhash` daje isti MD5 za obje datoteke.

Reprodukcija:

```bash
# varijante iz izvorne datoteke
curl -o orig.mp4 https://cdn.domovina.ai/data/PPXbSP14H4Y/video_h264.mp4
ffmpeg -i orig.mp4 -c copy -movflags +frag_keyframe+empty_moov+default_base_moof+global_sidx frag_sidx.mp4
ffmpeg -i orig.mp4 -vn -c:a libmp3lame -b:a 64k -ac 1 audio_mp3_64.mp3
# server s Range podrškom + stranica za mjerenje
python3 -I scripts/video-start/rangeserver.py <dir-s-datotekama>   # port 8791
cp scripts/video-start/test.html <dir-s-datotekama>/
# u Chromeu: DevTools → Network → Slow 4G, otvori http://127.0.0.1:8791/test.html, u konzoli:
await runTest('http://127.0.0.1:8791/frag_sidx.mp4', 'video', 0)      # 3. arg = startAt (s)
```

## Screenshotovi (isti dan)

Članak gradi sve sekcije odjednom, pa su svi screenshotovi kretali s videom:
`PPXbSP14H4Y` ima 26 PNG-ova 1920×1080 = **33,3 MB**, prikazanih na najviše
480×270. Dva popravka:

- `DeferredScreenshots`: odmah samo prva sekcija i ona iz `/t/<sec>`, ostali
  kad player javi `playing` (ili najkasnije 8 s). Player se pokazuje odmah, ne
  tek nakon `open()`.
- Pipeline KORAK 12.65 (`generate_webp_screenshots.js`) uz PNG uploada
  `{ts}-960.webp` (q80) i oznaku `data/{id}/screenshots_webp.json`; aplikacija
  bira WebP samo kad ga `episode.json` navodi, kadar bez WebP-a pada na PNG.
  PNG ostaje kao trajni original. Samo od 10. 10. 2026. — 5 epizoda: 141 MB
  PNG → 3,3 MB WebP (`node generate_webp_screenshots.js --dry-run` pokazuje
  opseg).

## Titl prije videa (isti dan, v2.0.182)

Kad se player počeo pokazivati odmah, titl je isticao riječi prvog cue-a preko
crne plohe: media_kit javlja `playing = true` čim je `play()` pozvan, a
`CaptionClock` je između događaja ekstrapolirao vrijeme. Sat sad crta titl tek
kad player javi poziciju > 0 i ne ekstrapolira dok je `buffering`.

## Provjera (lokalni build u Chromeu, ne Playwright)

`flutter build web --release --wasm` (~40 s) → `build/web` poslužen lokalno sa
SPA fallbackom i COOP/COEP zaglavljima → ruta u Chromeu uz DevTools Slow 4G.
Network panel pokazuje `video_h264_fmp4.mp4` i `-960.webp`, screenshot pokazuje
player sa spinnerom bez titla. Instalacija Playwright WebKita za provjeru Safarija
dvaput je zapela pa je odbačena — Safari ostaje za ručni test na iPhoneu.

## Što nije napravljeno (opcije za kasnije)

- **WebKit**: isprobati `/v/PPXbSP14H4Y` na iPhoneu u Safariju s maknutom ogradom
  (`isWebKitBrowser` u `DataService.resolveMedia`) — start, seek, pozadinski zvuk.
- **Audio 96k umjesto 128k** i **`-g 100`** u `backfill_video_h264.js` za nove
  epizode: audio je 65 % bajtova, keyframe je prosječno svakih 9,3 s.
- **Audio prvi** (MP3 za 0,8 s, video kasnije): dva media elementa koja treba
  sinkronizirati; uz fmp4 dobitak je ~1,8 s. Nije vrijedno sada.
- **WebP za TV reader** (`tv_episode_reader_screen.dart`) još crta PNG.
- Video se u aplikaciji otvara tek nakon `episode.json`; hladni share link je
  izmjeren na ~26 s do zahtjeva za video (od toga ~19 s boot wasma).

## Dopuna 24. 10. 2026. — fmp4 bez interleavinga ruši libmpv

Prvi fmp4-ovi (11.–24.10.) imali su po fragmentu jedan video pa jedan audio trun;
libmpv u iOS aplikaciji zbog toga je skakao natrag-naprijed i preko
CDN-a otvarao novi TLS po uzorku — `kmVTa8OjHpc` nije mogao bufferirati (460 HTTP
zahtjeva za 2 min videa). Pipeline sada remuxa s `-frag_interleave 25`, a
`verifyFmp4` odbija ne-interleavan izlaz; svih 55 datoteka prepisano + purge.
Ovaj test u Chromeu je to propustio jer Chrome ima vlastiti buffer. Mjerenja i
zamke: `../fetch.domovina.tv/docs/2026-10-24-fmp4-interleave-ios-zastajkivanje.md`.

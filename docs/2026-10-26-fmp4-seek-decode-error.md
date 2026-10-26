# fmp4 ruši Chromium na skoku (26. 10. 2026.)

## Zaključak

Remux `video_h264_fmp4.mp4` s `-frag_interleave 25` (fetch `aa84a0f7`, 24.10.,
svih 55 fmp4 prepisano) u Chromiumu (Chrome, Brave, Edge) **ruši reprodukciju
nakon skoka**: `<video>` javi `PIPELINE_ERROR_DECODE: video decode error!` i
stane. Za `PPXbSP14H4Y` je dovoljan **jedan** skok na 3403 s.

Korisnik to vidi kao:

- klikanje po poglavljima → zvuk i slika/titl se raziđu, player „se pogubi";
- refresh → video se više ne učita. Ekran nastavlja sa spremljene pozicije
  (`WatchProgressService`), a to je opet skok, i ako sjedne na loše mjesto,
  reprodukcija ne krene.

Popravak: isti remux uz `+cmaf` u `-movflags`. Interleave ostaje (treba ga libmpv
na iOS-u), a skokovi su čisti.

## Mjerenja

Brave (macOS), čisti `<video>`, lokalni range server s `Cache-Control: no-store`
(`scripts/video-start/rangeserver.py`), isti niz skokova
`878, 327, 3403, 1500, 3231, 128, 2100, 55, 2777, 967` s po 300 ms razmaka:

| varijanta (`PPXbSP14H4Y`) | rezultat |
|---|---|
| `video_h264.mp4` (klasični `moov`) | 10/10 skokova, svira |
| fmp4 bez interleavea (stanje 11.–24.10.) | 10/10, svira |
| fmp4 `-frag_interleave 25` (= CDN, `cmp` identičan) | `PIPELINE_ERROR_DECODE` na 3. skoku (@3403), 2/2 |
| isti, samo jedan skok na 3403 | `PIPELINE_ERROR_DECODE`, `readyState 1` |
| fmp4 `-frag_interleave 25` **`+cmaf`** | 10/10, svira; samo 3403 → svira |

ffmpeg (isti mov demuxer koji Chromium koristi za progresivni MP4), dekodiranje
8 s nakon `-ss` na 6–8 pozicija:

| varijanta | linije `[h264 …]` grešaka |
|---|---|
| klasični / bez interleavea / interleave + `cmaf` | 0 |
| `-frag_interleave 1` | 4 |
| `-frag_interleave 25` (CDN) | 12 |
| `-frag_interleave 100` | 22 |

Reprodukcija:

```bash
curl -o orig.mp4 https://cdn.domovina.ai/data/PPXbSP14H4Y/video_h264.mp4
F=+frag_keyframe+empty_moov+default_base_moof+global_sidx
ffmpeg -i orig.mp4 -c copy -movflags $F -frag_interleave 25 bad.mp4
ffmpeg -i orig.mp4 -c copy -movflags $F+cmaf -frag_interleave 25 good.mp4
for f in bad good; do ffmpeg -v error -ss 3403 -i $f.mp4 -t 8 -f null - 2>&1 | grep -c h264; done
```

## Uzrok (koliko je viđeno)

Struktura je inače jednaka (ftyp → moov → 2× sidx → moof s 3–4 truna po trafu,
isti broj ključnih kadrova). Jedina vidljiva razlika: bez `cmaf` video `sidx`
ima `earliest_presentation_time = 1024` (0,08 s pomaka B-frameova) uz `tfdt = 0`;
s `cmaf` je 0. Bez interleavea isti pomak nije smetao. Kako točno demuxer iz toga
sjedne usred GOP-a nije potvrđeno u izvoru ffmpega.

## Zamke pri dijagnozi

- **Usporedba „originalni URL vs cache-buster" vara.** Prvi niz mjerenja
  (originalni CDN URL 3/3 pada, s `?nb=` 0/4) izgledao je kao miješanje starih i
  novih range-ova u cacheu preglednika. Ponovljeno s novim ključem je opet palo;
  nasumični skokovi samo ponekad pogode loše mjesto. Determinirani niz skokova
  preko `no-store` servera je pravi test.
- Cloudflare edge je čist: range-ovi s `Origin`, bez njega i s cache-busterom
  daju iste bajtove.

## Popravak

- fetch `backfill_video_h264.js`: `+cmaf` u `FMP4_MOVFLAGS` i `verifyFmp4Seek`
  (ffmpeg dekodira 6 s nakon skoka na šest pozicija; ijedna `[h264`/`[aac`
  linija odbija izlaz, epizoda ostaje samo s `video_h264.mp4`).
- Klijent: `CdnConfig.videoH264FragmentedUrl` dodaje `?g=3` (generacija). Fajl je
  `immutable` godinu dana i prepisuje se na istom R2 ključu; bez novog ključa
  preglednik koji je epizodu gledao čuva pokvarene range-ove, a Cloudflare purge
  do njih ne dopire. **Redoslijed: prvo prepisati fmp4 na R2, tek onda deploy
  klijenta** — inače se pod `?g=3` cachira stari fajl.

Izvedeno 26.10.2026.: svih 59 fmp4 na R2 (55 od 24.10. + 4 iz nightlyja
25.–26.10.) prepisano `--fmp4-only --force`, 59/59 prošlo `verifyFmp4Seek`.
CF purge obje varijante (golo + `Origin`); nakon njega svih 59 × 2 vraća
`last-modified` 26. 10. `PPXbSP14H4Y` @3403 s: 0 grešaka i na golom URL-u i
na `?g=3`. Klijent s `?g=3` deployan nakon toga.

## Otvoreno

- `+cmaf` nije isproban na iPhoneu (libmpv); broj truna po trafu i redoslijed
  bajtova su isti kao u generaciji 2, pa bi zahtjeva trebalo biti jednako malo.
  Provjera: `../fetch.domovina.tv/docs/2026-10-24-fmp4-interleave-ios-zastajkivanje.md`.
- Opcija ostaje: na nativeu puštati klasični `video_h264.mp4`.

# Interleavani fmp4 ruši Chromium na nizu skokova (28. 10. 2026.)

Nastavak `docs/2026-10-26-fmp4-seek-decode-error.md`. Popravak od 26.10.
(`+cmaf`) uklonio je pad na **jednom** skoku, ali ne i pad na **nizu** skokova.

## Zaključak

`video_h264_fmp4.mp4` generacije 3 (`+cmaf`, `-frag_interleave 25`) i dalje
ruši Chromium (Chrome, Brave, Edge) kad korisnik skače naprijed-natrag:
`<video>` javi `PIPELINE_ERROR_DECODE: video decode error!` i ostane u
`readyState 1`. Korisnik vidi „loading/buffering", zvuk se razide sa slikom i
titlovima, a popravi ga tek refresh.

Uzrok je **interleaving** (više trunova po trafu, audio i video naizmjence u
`mdat`-u), ne `cmaf` i ne Flutter. Isti remux bez interleavea je čist.

Popravak (v2.0.208, fetch isti dan):

- pipeline uz `video_h264_fmp4.mp4` (interleave, za libmpv na iOS-u) radi i
  **`video_h264_fmp4_web.mp4`** (`+cmaf`, bez interleavea);
- web (Chromium) bira SAMO `video_h264_fmp4_web.mp4`, a kad ga `episode.json`
  ne navodi, klasični `video_h264.mp4`. Interleavani fmp4 na webu se više nikad
  ne pušta (`fragmentedVideoUrl` u `data_service.dart`, test u
  `test/episode_bundle_test.dart`);
- native ostaje na `video_h264_fmp4.mp4`, pa objavljeni store buildovi ne
  trebaju ništa.

## Mjerenja

Epizoda `QkcpHsj43rE` (2 h 5 min), Brave na macOS-u.

**U aplikaciji (produkcija, v2.0.207)**: polagani skokovi (16 skokova, 0,4–1,6 s
razmaka) prolaze; šest rundi po 12 nasumičnih skokova s 30–180 ms razmaka — pad
u 3. rundi, na skoku 1350,9 → 1066,1 s, 4 ms nakon `seeking`.

**Goli `<video>`, bez Fluttera** — lokalni range server s `no-store`
(`scripts/video-start/rangeserver.py`), snimljeni niz od 30 skokova iz te
runde (razmaci ograničeni na 1,5 s):

| datoteka (iste struje, `-c copy`) | snimljeni niz |
|---|---|
| CDN `video_h264_fmp4.mp4` (`+cmaf`, `-frag_interleave 25`) | **7/7 pada** |
| klasični `video_h264.mp4` | 0/6 |
| `+cmaf`, bez interleavea (= novi `video_h264_fmp4_web.mp4`) | 0/3 |
| bez `cmaf` i bez interleavea (stanje 11.–24.10.) | 0/3 |
| `video_h264_fmp4_web.mp4?g=1` s CDN-a | 0/3, linearno 30 s čisto |

Lokalni remux s pipelineovim zastavicama bajt je po bajt jednak CDN fajlu
(`cmp`), pa je usporedba čista.

Što NE ruši: jedan skok na bilo koju poziciju iz pada (8/8 čisto), kratki nizovi
od 2–3 skoka (0/9), nasumični nizovi od 25 skokova s 30–200 ms razmaka bez
ikakve reprodukcije između (0/8 na oba fajla). Pada niz u kojem se između
skokova nešto i reproducira i dobufferira.

ffmpeg (`-ss X -t 6 -f null`) na svim pozicijama iz pada, oba fajla: **0**
grešaka. Zato `verifyFmp4Seek` u pipelineu ovaj kvar ne vidi: on radi jedan
skok po procesu, a Chromium puca tek na nizu skokova u istom demuxeru.

Reprodukcija:

```bash
curl -o il.mp4  "https://cdn.domovina.ai/data/QkcpHsj43rE/video_h264_fmp4.mp4?g=3"
curl -o web.mp4 "https://cdn.domovina.ai/data/QkcpHsj43rE/video_h264_fmp4_web.mp4?g=1"
python3 scripts/video-start/rangeserver.py .   # :8791, no-store
# stranica s <video> koja na svježe učitanom fajlu skoči na 1350 pa odvrti niz:
# 580.77 1637.87 5867.15 552.7 1999.91 6694.63 6098.76 6515.12 6850.25 2590.59
# 1831.07 3516.08 4619.69 5241.42 6584.77 686.38 4670.21 637.64 6724.51 4500.33
# 1298.96 6933.17 939.98 1724.42 720.49 3220.87 2499.41 7026.46 1350.88 1066.12
# razmaci (ms): 0 71 115 109 178 37 68 167 42 94 35 163 1500 116 166 141 99 104
#               131 99 178 35 142 87 1500 40 173 101 87 100
```

## Uzrok (koliko je viđeno)

Mehanizam u izvornom kodu Chromiuma/ffmpega nije potvrđen. Hipoteza: Chromium
za progresivni MP4 koristi ffmpegov mov demuxer, i nakon niza prekinutih skokova
po fragmentu s više naizmjeničnih trunova po trafu stanje po stazi završi
neusklađeno. Video dekoder tada dobije kadar bez referentnog ključnog kadra
(`PIPELINE_ERROR_DECODE`), a audio staza svira dalje: odatle „zvuk ide, slika
stoji".

## Zašto ne jedan fajl za sve

- Bez interleavea libmpv (iOS app) čita fragment po dts-u i skače natrag-naprijed
  ~22×/s; preko CDN-a to je bilo 460 zahtjeva za 2 min videa
  (`../fetch.domovina.tv/docs/2026-10-24-fmp4-interleave-ios-zastajkivanje.md`).
  Chromium čita kroz vlastiti međuspremnik pa tu ne zapinje: generacija bez
  interleavea (11.–24.10.) na webu je bila zdrava.
- S interleaveom pada Chromium (gore).

Dvije datoteke koštaju ~175 MB više na R2 po satu-dva epizode i jedan `-c copy`
remux (sekunde).

## Provjera da ništa staro nije vraćeno

| prošli problem | stanje |
|---|---|
| bez `sidx` Chrome ne krene (11.10.) | obje varijante `global_sidx`; `verifyFmp4` ga i dalje traži |
| bez interleavea libmpv zapinje (24.10.) | native i dalje dobiva interleavani fajl |
| bez `cmaf` jedan skok ruši Chromium (26.10.) | obje varijante `+cmaf`; `verifyFmp4Seek` za obje |
| prepisan immutable ključ → stari range-ovi u pregledniku (24.10.) | novi ključ, ništa nije prepisano; `?g=1` za buduća prepisivanja |
| WebKit fmp4 neisproban | WebKit i dalje na `video_h264.mp4` |
| Cast | pošiljatelj još ne postoji; receiver dobiva URL od njega |
| cutter (isječci) | koristi `video_h264.mp4`, nepromijenjeno |

`verifyFmp4` sada provjerava i obrat: web varijanta s više trunova nego trafova
odbija se („ruši Chromium").

## Kad web dobije novu datoteku

`episode.json` preglednik drži `max-age=3600`, a aplikacija ga još drži i u
disk cacheu (`CdnJsonCache.getMutable`, stale-while-revalidate). Posjetitelj
koji je epizodu već otvorio vidi web fmp4 tek na 2.–3. otvaranju, a do tada
dobiva klasični `video_h264.mp4`. To je sporiji start, ali bez pada. Izmjereno
u e2e: v2.0.208 je prva dva učitavanja otvorila `video_h264.mp4`, treće
`video_h264_fmp4_web.mp4?g=1`.

## Otvoreno

- Epizode s fmp4 od prije 28.10. nemaju web varijantu, pa web na njima pušta
  klasični MP4 (spor start na Slow 4G, ali bez pada). Backfill:
  `node backfill_video_h264.js --fmp4-only --video-id …` (postojeći
  interleavani fajl se preskače), zatim `node build_episode_bundle.js --video-id …`.
- Oporavak u klijentu nakon `PIPELINE_ERROR_DECODE` (ponovno otvaranje na istoj
  poziciji) nije napravljen; `episode_playback_session.dart` grešku samo
  zapiše u log.
- `verifyFmp4Seek` ne može uhvatiti ovu klasu kvara; prava provjera bi bio niz
  skokova u headless Chromiumu.

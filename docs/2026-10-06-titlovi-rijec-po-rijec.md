# Titlovi riječ po riječ + titl ispod playera na mobitelu

**Datum:** 2026-10-06
**Kod:** `lib/models/speaker_timeline.dart` (`WordTiming`, `parseWordTimings`),
`lib/widgets/subtitle_caption.dart` (`CaptionClock`, `captionSpan`, `SubtitleStrip`),
`lib/widgets/episode_video.dart` (overlay), `lib/services/subtitle_prefs.dart`
(`SubtitlesEnabled`)
**Testovi:** `test/word_timings_test.dart` (stvarni isječak `fln3cFCwHcs`)
**Skripte:** `scripts/subtitle-words-reference.py`, `scripts/spa-server.py`
**Provjera u pregledniku:** `scripts/verify-subtitle-words.py`

## Zaključak

Nove epizode imaju Speechmaticsov kostur s vremenom po riječi, a tekst piše
Gemini (KORAK 2.8). Titl sada ističe riječ koja se upravo izgovara, a na
mobitelu u portraitu ide **ispod** slike umjesto preko nje. U landscapeu,
na desktopu i u svakom fullscreenu titl ostaje preko slike kao i prije.

Frontend je gotov. Isticanja na produkciji NEMA dok pipeline ne objavi
`data/<id>/words.json` (§3). Bez te datoteke titl izgleda kao i prije.

## 1. Poravnanje: izmjereno

Gemini ne prepisuje Speechmaticsove riječi, nego piše ono što čuje unutar
granica segmenta. Riječi zato nisu 1:1. Poravnanje po segmentu
(`difflib.SequenceMatcher` nad normaliziranim riječima: mala slova, bez
dijakritika, bez interpunkcije) daje:

| skup | usidreno izravno |
|---|---|
| svih 33 epizode s `.speechmatics.gemini.diarized.srt` (5.10.2026.) | 78,2 % od 349 553 riječi |
| hrvatske epizode | 81–91 % |
| `fln3cFCwHcs` | 87,6 % od 14 651 |
| epizode s engleskim zvukom (tekst je preveden na HR) | 24–32 % |

Neusidrene riječi dobiju vrijeme interpolacijom između susjednih sidara,
razmjerno broju znakova. Engleske epizode treba preskočiti (prag u §3).

Reprodukcija: `scripts/subtitle-words-reference.py` (algoritam u §3). Ulaz su `{audio}.speechmatics.json` + kanonski `{base}.wav.canary.diarized.srt`.
Objavljeni `data/fln3cFCwHcs/diarized.srt` je bajt-za-bajt jednak kanonskom
(provjereno `diff`-om).

## 2. Frontend: odluke

- **Ugovor je SRT, ne Speechmatics.** Frontend broji riječi kao
  `text.trim().split(/\s+/)` teksta cue-a bez `[SPEAKER_XX]`. `words.json`
  mora imati točno toliko parova po cue-u, inače se taj cue prikazuje bez
  isticanja (`withWordTimings`). Tako regenerirani SRT ne može dati krivo
  isticanje, samo nikakvo.
- **Sat od 60 Hz, rebuild po riječi.** `player.stream.position` fira ~5×/s, a
  riječ traje 150–400 ms. `CaptionClock` ekstrapolira tickerom (uz
  `rate`, najviše 600 ms bez potvrde streama) i radi `setState` samo kad se
  promijeni aktivna riječ.
- **Isticanje mijenja samo boju.** Podebljana riječ raširi redak pa se tekst
  prelama drukčije na svakoj riječi. Aktivna riječ: bijela na
  `colorScheme.tertiary` (hrvatska crvena). Izgovorene: pune. Neizgovorene:
  prigušene.
- **Traka ispod playera ima fiksnu visinu (3 retka).** Inače bi seek bar i sve
  ispod skakali sa svakim cue-om. Cue od 60 riječi se zato lista po
  stranicama (`pageTokens`) koje prate govor. Svaka stranica se izmjeri; ako
  ne stane, ponovi se s užim retkom. Titl se ne reže.
  Bez `words.json` stranice se listaju po procjeni (razmjerno znakovima), a
  isticanja nema.
- **„Mobitel u portraitu"** = iOS/Android + `height > width` +
  `shortestSide < 600`, ista definicija kao `_isPhoneLandscape`. Overlay se
  povlači samo izvan fullscreena (`isFullscreen(context)` + rotacijska ruta).
- **CC stanje je singleton** (`SubtitlesEnabled`), jer traka živi izvan
  `EpisodeVideo`. Isto pravilo kao `PlaybackSpeed`/`PlayerMute`.

## 3. Pipeline: što treba napraviti (fetch.domovina.tv)

Pipeline rad ide iz fetch sesije. Ugovor:

```
data/<id>/words.json
{"v": 1, "source": "speechmatics", "anchored": 0.876,
 "cues": [{"s": 0, "e": 15000, "w": [120, 300, 300, 450, …]}, …]}
```

- `s`, `e`: granice cue-a iz kanonskog `diarized.srt`, u ms (frontend
  tolerira ±1 ms).
- `w`: ravan niz `(početak, kraj)` u ms po riječi, istim redom kao
  `text.split(/\s+/)`. Monoton po početku.
- `anchored`: udio izravno usidrenih riječi. **Ne objavljivati ispod ~0,6**
  (engleske epizode).
- Veličina: 244 kB (51 kB gzip) za 1,5 h epizode. `immutable` je u redu
  samo ako se `words.json` regenerira zajedno s SRT-om, inače `--force`.

Algoritam (referentna izvedba `scripts/subtitle-words-reference.py`, ~70 redaka Pythona):

1. Riječi iz `results[]` s `type == "word"`, `alternatives[0].content`.
2. Po cue-u: Speechmatics riječi unutar `[s-50, e+50]` ms.
3. `SequenceMatcher(autojunk=False)` nad normaliziranim riječima, a pogođene
   riječi preuzmu Speechmaticsovo vrijeme.
4. Neusidreni niz se interpolira između susjednih sidara, razmjerno znakovima.
   **Zamka (izmjereno):** riječi na kraju cue-a koje je Speechmatics stavio u
   SLJEDEĆI cue dobiju nulti raspon na `e` i nikad se ne istaknu. Niz zato
   upija susjedne usidrene riječi dok svaka ne dobije ≥ 120 ms. Prije tog
   popravka 565 od 14 651 riječi je imalo < 60 ms, poslije 147.
5. Monotonost: početak riječi nikad prije početka prethodne.

`upload_to_r2.js` treba mapiranje `{base}.words.json` → `data/{id}/words.json`
(dodati sufiks u `UPLOAD_SUFFIXES` i granu u `getFlutterKey`), plus korak u
`run_pipeline.sh` nakon KORAKA 2.8 (i backfill za 33 epizode koje već imaju
`.speechmatics.json`).

## 4. Provjera

```
flutter build web --release --wasm -o /tmp/web
python3 -I scripts/spa-server.py /tmp/web &   # SPA fallback + COOP/COEP, port 8788
python3 scripts/verify-subtitle-words.py --base http://127.0.0.1:8788 \
    --words /put/do/words.json --out /tmp
```

Izmjereno 6.10.2026. na `fln3cFCwHcs/t/60`. Portrait 390×844: traka ispod
slike, 3 retka, istaknuto „se" u „Trudimo se to postati" na 01:25, što
odgovara zvuku. Landscape 844×390: overlay preko slike kao prije, istaknuto
„postati" na 01:26.

## 5. Backfill bez LLM-a: dva puta (izmjereno 6.10.2026.)

| skup | izvor vremena po riječi | trošak |
|---|---|---|
| 57 epizoda s `{audio}.speechmatics.json` (33 s Gemini tekstom) | uparivanje iz §3 | nula, nekoliko sekundi po epizodi |
| ~3 300 Canary epizoda (3 383 kanonskih SRT-ova, audio lokalno za svih 3 383) | **nema ga na disku** | vidi niže |

Canary vremena po riječi zapravo **vraća**, ali ih se baca:
`modal_canary/canary_modal.py` zove `transcribe(timestamps=True)` i sprema samo
`timestamp["segment"]` (u `.wav.canary.csv`). Spremanje `timestamp["word"]` je
besplatno za buduće epizode. Za stare bi trebao novi GPU prolaz (Modal, plaća se).

Preporučeni put za stare epizode je **forced alignment**: lokalno, bez LLM-a i
plaćenog API-ja. Postojeći tekst cue-a poravna se s postojećim zvukom unutar
granica cue-a, npr. torchaudio `MMS_FA` ili wav2vec2 CTC model za hrvatski.
Poravnava točno tekst koji korisnik vidi, pa je usidreno 100 % riječi, ne 78 %.

Neizmjereno, prije punog backfilla:
- **Brzina na Macu**: probati 2–3 epizode i iz toga procijeniti ukupno trajanje.
- **Collapse epizode** (~12 % Canary transkripata, vidi fetch
  `docs/2026-09-19-speechmatics-kostur-gemini-sluh.md` §1.2): tekst ne odgovara
  zvuku. Takve epizode preskočiti po niskoj pouzdanosti poravnanja, inače titl
  ističe krive riječi.

## Otvoreno

- Pipeline korak + backfill (§3, §5).
- Frontend je LIVE od v2.0.168 (6.10.2026.); isticanje čeka prvi `words.json` na CDN-u.
- Audio-only epizode nemaju titl ni prije ni sada (nema `EpisodeVideo`).
- Isticanje u članku/transkriptu (isti `words.json`) nije rađeno.

## Titl na dva jezika (29.10.2026.)

Titl sada prati jezik sadržaja: `diarized.<lang>.srt` + `words.<lang>.json`
uz pad na `diarized.srt`. Engleski kanali (325 epizoda) imaju izvorni engleski
titl s isticanjem riječi. Ugovor, mjerenja i otvoreno (HR titl za novije
engleske epizode, pipeline korak): `docs/plans/2026-10-29-titlovi-na-dva-jezika.md`.

Uzrok preskočenog `words.json` na engleskim ad-hoc epizodama (`_unlisted`) bio
je jezik ASR-a: kanal bez unosa u `channel_languages.conf` išao je kao `hr`.
Popravljeno u fetchu 29.10. (`info.json` `language` kao pad).

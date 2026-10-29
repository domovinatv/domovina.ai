# Titlovi na dva jezika (HR/EN) — plan

29.10.2026. Zvuk je uvijek na jeziku snimke. Titl prati jezik sadržaja koji je
korisnik izabrao (`EpisodeLanguage`), kao članak, sažetak i Magisterium.
Isticanje riječi postoji samo na titlu u **izvornom** jeziku snimke, jer vrijeme
po riječi pripada izgovorenim riječima, a prijevod ih nema.

## Stanje (izmjereno 29.10.2026.)

Po epizodi postoji jedan titl i jedan `words.json`, bez jezika:
`data/<id>/diarized.srt` (iz `{base}.wav.canary.diarized.srt`, `upload_to_r2.js`)
i `data/<id>/words.json`. Flutter ih čita kroz `CdnConfig.diarizedSrtUrl` /
`wordsUrl` u `DataService.loadSpeakerTimeline`, bez jezičnog parametra.

| snimka | `diarized.srt` | drugi jezik |
|---|---|---|
| hrvatska (većina kataloga) | HR, s `words.json` | nema |
| engleski kanal (`launched`, `subclub`, `catholic_futurist`: 325 ep.) | **HR prijevod** (Canary en→hr, `run_pipeline.sh` uvijek `--target-lang hr`) | EN tekst lokalno samo za 3 od 325 (Speechmatics) |
| engleska ad-hoc (`_unlisted`) | EN (Gemini) | nema |

Zato engleski kanali nemaju isticanje riječi: `words.json` se ne može usidriti
na hrvatski prijevod (`generate_words_json.js`, prag 0,6; catholic_futurist
`f_E_fizx_zM` 2,6 %, subclub 3 %). Na disku su za svih 325 epizoda WAV i
diarizirani HR SRT (govornici iz lokalnog pyannotea).

## Ugovor (CDN)

Aditivan; ništa postojeće se ne mijenja ni ne briše.

- `diarized.srt` + `words.json` ostaju kakvi jesu (zadani titl, stari buildovi).
- `diarized.<lang>.srt` = titl na jeziku `<lang>` (`hr` | `en`), ista
  `[SPEAKER_xx]` oznaka kao u `diarized.srt` za isti trenutak.
- `words.<lang>.json` = vrijeme po riječi za `diarized.<lang>.srt`, isti format
  i isto pravilo 1:1 kao `words.json` (`docs/2026-10-06-titlovi-rijec-po-rijec.md`).
  Postoji samo za izvorni jezik snimke.
- Klijent za jezik L: `diarized.L.srt` (+ `words.L.json`) ako ga `episode.json`
  navodi, inače `diarized.srt` (+ `words.json`). Bez metapodatka o jeziku
  zadanog titla: kombinacija gore daje točan ishod u sva tri retka tablice.

| snimka | HR korisnik | EN korisnik |
|---|---|---|
| engleski kanal | `diarized.srt` (HR) | `diarized.en.srt` + `words.en.json` |
| hrvatska | `diarized.srt` + `words.json` | `diarized.en.srt` (prijevod, faza 3), inače HR |
| engleska ad-hoc | `diarized.hr.srt` (prijevod, kasnije), inače EN | `diarized.srt` + `words.json` |

Govornici: EN cue dobiva govornika HR cue-a s najvećim vremenskim preklapanjem.
Tako `SPEAKER_xx` znači istu osobu u oba fajla, pa imena iz članka vrijede za oba.

## Faza 1 — engleski kanali (fetch.domovina.tv)

1. `modal_canary/canary_modal.py`: parametar `out_tag` (`main` i `batch`). Uz
   `--out-tag en` izlaz je `{wav}.canary.en.srt` / `.canary.en.csv` /
   `.canary.en.word_ts.json`, a `batch` traži WAV-ove bez `.canary.en.srt`.
   Bez parametra ponašanje je nepromijenjeno.
2. `modal run …::batch --channels <ch> --source-lang en --target-lang en --out-tag en`.
   Cijena: Canary na Modalu ~$0,01–0,03/ep (A100-40GB, izmjereno u docsima fetcha),
   za 325 epizoda reda veličine $5–10 Modal kredita; nula Claude kvote.
3. `build_original_subs.js` (novo): `.canary.en.srt` + govornici iz
   `.wav.canary.diarized.srt` → `{base}.diarized.en.srt`; zatim `buildWords` iz
   `generate_words_json.js` nad `.canary.en.word_ts.json` → `{base}.words.en.json`
   kad je usidrenost ≥ 0,6, inače `{base}.words.en.skipped.json`.
4. `upload_to_r2.js` / `force_upload.js`: `{base}.diarized.en.srt` →
   `data/<id>/diarized.en.srt`, `{base}.words.en.json` → `data/<id>/words.en.json`;
   zatim `build_episode_bundle.js --video-id …` (popis `files` se mjeri na R2).
5. Novi kanali: KORAK u `run_pipeline.sh` koji za kanal s `=en` (i ad-hoc s
   `info.json language`) uz `en→hr` pusti i `en→en` s `--out-tag en`. Nakon pilota.

Pilot: `catholic_futurist` (21 ep.), pa provjera u pregledniku, pa ostale.

## Faza 2 — klijent (domovina.ai)

- `CdnConfig.diarizedSrtUrl(id, lang:)` / `wordsUrl(id, lang:)`.
- `DataService.loadSpeakerTimeline(lang:)`; `EpisodeData.speakerTimelineEn` i
  `speakerTimelineFor(wantEn)` s padom na `speakerTimeline`, isti obrazac kao
  `summaryFor` / `articleFor`. `speakerTimelineHr` (za `diarized.hr.srt` engleskih
  ad-hoc epizoda) dolazi s prvim takvim fajlom. Datoteka koje bundle ne navodi
  `_get` ne traži, pa nema dodatnog zahtjeva po epizodi. Čuva
  `test/episode_bundle_test.dart` („titl na jeziku sadržaja").
- Pozivna mjesta (`episode_screen.dart`, `episode_simple_screen.dart`) predaju
  `data.speakerTimelineFor(wantEn)`; `EpisodeVideo`, `VideoPanel` i
  `SubtitleStrip` ostaju kakvi jesu.
- `EpisodeStatus.hasTranscript` i dalje gleda `speakerTimeline`.

## Faza 3 — hrvatske epizode → EN titl

Otvoreno, mjeri se na 2–3 epizode prije odluke:
- Canary `hr→en` iz zvuka (~$0,01/ep): jeftino, ali cue-ovi nisu 1:1 s HR-om.
- LLM prijevod postojećih HR cue-ova (put kao `article.en.json`): cue-ovi
  poravnati, bolja kvaliteta, skuplje i sporije.

## Rizici

- Canary en→en segmentira drukčije od en→hr; govornik po preklapanju to
  pokriva, ali cue koji pada preko promjene govornika dobije većinskog.
- `words.en.json` mora biti regeneriran kad god se promijeni `diarized.en.srt`
  (isto pravilo kao `words.json`).

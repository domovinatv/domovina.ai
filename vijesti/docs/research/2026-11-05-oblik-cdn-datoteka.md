# Stvarni oblik CDN datoteka za engine (S1, 2026-11-05)

Provjereno na stvarnim datotekama s `cdn.domovina.ai`, ne iz dokumentacije. Sheme su u
`engine/cdn/schemas.ts`, fixturei u `engine/test/fixtures/` (README tamo).

## Zaključak

- `words.json` nosi samo vremena, ne tekst riječi. `w` je ravan niz parova (početak,
  kraj) u **apsolutnim** ms. Na 6 epizoda s `words.json` 100 % cueova ima točno onoliko
  parova koliko SRT cue ima riječi, kad se uparuje po početku **i** kraju. Uparivanje
  samo po početku (Flutter) gubi cueove od 0 ms koji dijele početak sa sljedećim.
- `diarized.srt` na engleskim kanalima nema stalan jezik: negdje je hrvatski prijevod,
  negdje engleski izvornik. Metapodatka o jeziku nema. `summary.language` je jezik
  izlaza (uvijek `hr`), ne snimke.
- `summary.source.channel` je za epizode kanala `domovina_tv` `_unlisted`. Kanal se
  čita iz listinga.

## Mjerenja

Cijele epizode, stvarni CDN (`.cache/cdn` kao disk cache):

```
npm run cdn:stats -- pIx_7N-6HJ4 P9sLks-f2mQ x3w2BVZJ9vQ MGLq9v3AtvE b-nls1ck8EE QkcpHsj43rE nuNw4qWs0r4
npm run cdn:stats -- x3w2BVZJ9vQ nuNw4qWs0r4 --lang en
```

| ID | titl | words (izvor, `anchored`) | cueova | s vremenima | govornika |
|---|---|---|---|---|---|
| `pIx_7N-6HJ4` | `diarized.srt` | soniox, 1 | 179 | 179 (100 %) | 2 |
| `P9sLks-f2mQ` | `diarized.srt` | nema | 424 | 0 | 2 |
| `x3w2BVZJ9vQ` | `diarized.srt` (HR prijevod) | nema | 216 | 0 | 2 |
| `x3w2BVZJ9vQ` | `diarized.en.srt` | canary, 1 | 211 | 211 (100 %) | 2 |
| `MGLq9v3AtvE` | `diarized.srt` | soniox, 1 | 1009 | 1009 (100 %) | 12 |
| `b-nls1ck8EE` | `diarized.srt` | soniox, 1 | 782 | 782 (100 %) | 2 |
| `QkcpHsj43rE` | `diarized.srt` | soniox, 1 | 647 | 647 (100 %) | 6 |
| `nuNw4qWs0r4` | `diarized.srt` (EN izvornik) | speechmatics, 0,935 | 146 | 146 (100 %) | 4 |
| `nuNw4qWs0r4` | `diarized.en.srt` | canary, 1 | 327 | 327 (100 %) | 4 |

Prije popravka uparivanja (samo po početku, kao Flutter) bilo je 178/179, 1003/1009 i
646/647. Svih 8 promašaja su kratki cueovi (1–3 riječi, često 0 ms) koji dijele početak
sa sljedećim cueom, npr. `pIx_7N-6HJ4` 00:18:34,590 „mi” (0 ms) pa dugi cue od istog
trenutka. Test: `engine/cdn/srt-words.test.ts` („dva cue-a s istim početkom”).

## `words.json`

```json
{"v":1,"source":"soniox","anchored":1,
 "cues":[{"s":330,"e":4710,"w":[330,690,690,810,…],"a":1}, …]}
```

- `source`: `soniox` (većina novijih), `speechmatics`, `canary` (`words.en.json`). Ugovor
  iz `docs/2026-10-06-titlovi-rijec-po-rijec.md` spominje samo Speechmatics.
- `a`: udio usidrenih riječi po cue-u. Nije u ugovoru od 6.10.; postoji u svim viđenim
  datotekama. Speechmatics na engleskoj epizodi ima `a` od 0 do 1 po cue-u, soniox i
  canary 1.
- `s`/`e` su granice SRT cue-a, `w` su parovi unutar njih; u fixtureima su riječi
  monotone po početku i unutar cue-a ±1 s (test „riječi u fixtureima su monotone”).
- `words.json` se backfilla: `MGLq9v3AtvE` je pri prvoj provjeri 5.11. bio bez njega, sat
  kasnije s njim. Fixture „bez words.json” zato može zastarjeti; `fixtures:refresh` tada
  pada.

## `diarized.srt`

- Blok: redni broj, `HH:MM:SS,mmm --> HH:MM:SS,mmm`, jedan redak teksta koji počinje s
  `[SPEAKER_XX]` (dvije znamenke, od `SPEAKER_00`). U 9 titlova 7 epizoda iz tablice
  nijedan cue nema više redaka teksta, nijedan nije bez oznake i nijedan nema oznaku
  usred teksta. Provjera nakon `cdn:stats` (titlovi su tada u `.cache/cdn`):
  `cd .cache/cdn/data && for f in */diarized*.srt; do awk -v f="$f" 'BEGIN{RS="";FS="\n"} {if(NF>3)m++; if($3!~/^\[SPEAKER_[0-9][0-9]\]/)n++; c++} END{print f, c, "multi="m+0, "nospk="n+0}' "$f"; done`
- Postoje cueovi od 0 ms (`start == end`).
- Engleski kanali imaju i `diarized.en.srt` + `words.en.json`. HR i EN titl nemaju iste
  cueove (`x3w2BVZJ9vQ`: 216 prema 211), pa se ne mogu uparivati po indeksu.
- Kod `x3w2BVZJ9vQ` je `diarized.srt` hrvatski prijevod, kod `nuNw4qWs0r4` i
  `2Lu4MDwtC54` (launched) engleski izvornik. Plan
  `docs/plans/2026-10-29-titlovi-na-dva-jezika.md` tvrdi da je na engleskim kanalima
  `diarized.srt` uvijek HR prijevod. To ne vrijedi za sve. Provjera:
  `curl -s https://cdn.domovina.ai/data/<id>/diarized.srt | sed -n 3p`.

## `episode.json` (v1)

`{"version":1,"generated_at":…,"files":[…],"inline":{…}}`. `files` je izmjereni popis
R2 prefiksa. `inline` nosi `info.json`, `summary.json`, `outline.json`, `article.json` i,
kad postoji, `article.magisterium.json`. Za epizodu u kojoj je sve inline loader treba
dva zahtjeva: `episode.json` i `diarized.srt` (test „words.json se uopće ne traži”).

## `info.json`

yt-dlp dump od ~85 kB, većinom `formats`. Engine čita `id`, `title`, `duration`,
`description`, `channel`, `upload_date`, `timestamp`, `webpage_url`, `thumbnail`, `tags`,
`playable_in_embed`, `chapters`.

## `summary.json` i `article.json`

- `summary`: `title_hr`, `abstract_hr`, `key_topics`, `speakers[{id, suggested_name,
  role}]`, `key_points`, `mentioned_people|places|organizations`, `language`,
  `content_type`, `sentiment`. `source.channel` može biti `_unlisted`.
- `article`: `metadata{model, complete, …}` i `iterations[{iteration_number, start_time,
  end_time, theme, sections[{subtitle, screenshot_timestamp, screenshot_description,
  content, keywords, entities}]}]`. Vremena su `HH:MM:SS`. Sekcija nema svoj kraj, samo
  `screenshot_timestamp`. Iteracija pokriva oko 40 min. Modeli: `claude-code:opus`,
  `gemini-3.5-flash`, `gemini-2.5-flash`. `content` je markdown (`**ime**`).

## Listinzi

`channels/data/index.json` (`version`, `channel_count`, `channels[{id, name,
video_count, latest_video}]`, 52 kanala 5.11.) i `channels/data/<slug>.json`
(`version: "1.0"` kao string, `videos[{id, title, date, duration_seconds, abstract,
topics, speakers, pipeline{has_*}}]`). Neki ID-evi nisu YouTube oblika (`c9db520f0cf`,
X izvor).

## Pristup CDN-u

Cloudflare vraća 403 Pythonovom `urllib` zadanom klijentu, a curl i Node `fetch`
prolaze. Loader šalje vlastiti `User-Agent` (odluka 104). Provjera:
`python3 -c "import urllib.request;urllib.request.urlopen('https://cdn.domovina.ai/data/QkcpHsj43rE/episode.json')"`
(HTTP 403) prema `curl -s -o /dev/null -w '%{http_code}' https://cdn.domovina.ai/data/QkcpHsj43rE/episode.json` (200).

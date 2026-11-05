# Oblik ulaza kataloga (S1, 05.11.2026.)

Izmjereno na stvarnim datotekama s `cdn.domovina.ai`, na `../fetch.domovina.tv/data/podcasts_registry.json`
i na `/Volumes/DOMOVINA2TB/fetch_domovina_tv_output/_unlisted/`. Svaka brojka ima naredbu.

## `channels/data/index.json`

`{version: "1.0", generated_at, channel_count, channels: ChannelSummary[]}`, 52 kanala.

```bash
curl -s https://cdn.domovina.ai/channels/data/index.json | python3 -c "import json,sys;d=json.load(sys.stdin);print(d['channel_count'],len(d['channels']))"
```

`ChannelSummary`: `id` (= slug), `name`, `avatar_square`, `avatar_cover` (+ `*_dimensions`, može
`null`), `youtube_channel_url`, `youtube_playlist_url`, `follower_count`, `video_count`,
`total_duration_seconds`, `avg_magisterium_score`, `latest_video: {id, date, title}`.

- **Nema polja `youtube_channel_id`.** Izvodi se iz `youtube_channel_url` samo kad je oblik
  `https://www.youtube.com/channel/UC…`. Tri kanala imaju ne-YouTube URL
  (`dijalog` → Spotify, `launched`, `subclub`).
- **`youtube_channel_id` nije jedinstven**: `na_kavi_sa_svetim_ignacijem`,
  `slijedi_svoj_poziv_1` i `slijedi_svoj_poziv_2` dijele `UCuk9D5H9mx7birJ1-S22nyQ`
  (kanali iz playlista istog YouTube kanala). U shemi nema `UNIQUE` na tom stupcu.

## `channels/data/<slug>.json` (listing)

Zaglavlje kao `ChannelSummary` + `description`, `tags`, `latest_video_date`, i `videos[]`.
Svaki video ima točno ova polja (provjereno na `40_dana_za_zivot`, `dijalog`, `nanovoroeni`,
`subclub`): `id, title, title_hr, date (YYYY-MM-DD), duration_seconds, duration_display, views,
likes, thumbnail, youtube_url, abstract, topics, speakers, magisterium_score, pipeline`.

- `pipeline` je objekt s 9 booleana. Redoslijed bitova za `p` u `home.json` je ugovor
  (`PIPELINE_BITS` u `../fetch.domovina.tv/generate_channel_index.js`, `VideoPipeline.fromBits`):
  `has_transcript, has_diarized, has_summary, has_article, has_magisterium,
  has_translation_en, has_summary_en, has_article_en, has_magisterium_en` (bit 0…8).
- `magisterium_score` je većinom `null` (`nanovoroeni` 318/320 null).
- `dijalog` ID-evi nisu YouTube ID-evi (`f898a3f0774`, 11 hex znakova). `episodes.id` je
  zato „ID epizode”, ne nužno YouTube ID.
- U listinzima 4 provjerena kanala `duration_seconds` je uvijek `int`.

## `home.json`

`{version: 1, generated_at, episodes[]}`; epizoda `{c, id, title, date, duration_seconds,
magisterium_score, p}`. `p` = bitmaska gore (npr. 511 = svih 9).

## Tier 2: `_unlisted`

232 `*.info.json`, 132 različita `channel_id`.

```bash
ls /Volumes/DOMOVINA2TB/fetch_domovina_tv_output/_unlisted/*.info.json | wc -l
```

`info.json` (yt-dlp, ~60 polja, do 120 kB). Trebaju: `id, title, channel, channel_id,
upload_date (YYYYMMDD), duration, extractor`.

- `duration`: 230 `int`, 1 `float` (`CUJmOc91C64`, 245.295, X/Twitter), 1 `null`
  (`hmM9f_3Mqm4`).
- `extractor`: 231 `youtube`, 1 `twitter`. Twitter zapis ima `channel: null` i numerički
  `channel_id` (`1973380383166050304`).
- 32 od 232 epizode nemaju registry unos po `channel_id`.
- **41 Tier 2 epizoda je s kanala koji je `tracking.enabled` u registryju**, a neke su
  istodobno i u Tier 1 listingu: `KLPD-Meu4e8` je u `_unlisted` i u
  `channels/data/nanovoroeni.json`. Tier 2 skup = key cache minus ID-evi iz Tier 1 listinga
  (S2), inače ista epizoda dobiva dva retka ili krivi tier.
- Registry unos `nanovoroeni` nema `youtube.channel_id` (`null`), pa se taj kanal po
  `channel_id` ne razrješava iako je Tier 1. Razrješavanje u S2 mora imati i put preko
  `index.json` (`youtube_channel_url`).

```bash
cd ../fetch.domovina.tv && python3 -c "
import json,glob
reg=json.load(open('data/podcasts_registry.json'))['podcasts']
byc={e['youtube'].get('channel_id') for e in reg if e['youtube'].get('channel_id')}
tr={e['youtube'].get('channel_id') for e in reg if e['tracking'].get('enabled')}
rows=[json.load(open(f)) for f in glob.glob('/Volumes/DOMOVINA2TB/fetch_domovina_tv_output/_unlisted/*.info.json')]
print(sum(r['channel_id'] not in byc for r in rows), sum(r['channel_id'] in tr for r in rows))"
```

## `data/<id>/summary.json`

`{version, generated_at, model, source: {filename, channel: "_unlisted", youtube_id, title,
upload_date (YYYY-MM-DD), duration_seconds, …}, summary: {title_hr, abstract_hr, key_topics,
speakers, …, language}}`. `source.duration_seconds` prati `info.json` (i float i `null`).

## `data/<id>/episode.json`

`{version: 1, generated_at, files: string[], inline: {"info.json": {...}, "summary.json": …}}`.
`inline` nosi cijeli `info.json` (do 330 kB ukupno). Parser treba samo `files`.

## `podcasts_registry.json`

`{version: "1.2", podcasts: [588]}`. Unos: `slug, display_name, youtube: {url, type,
channel_id?, handle?, playlist_id?, parent_channel?}, tracking: {enabled}, tier, …`.

- **Registry `tier` (1–4, ocjena kvalitete) NIJE naš Tier 1/2** (praćen kanal s
  listingom vs. `_unlisted`). U D1 `tier` znači samo naše; registry tier se ne uvozi pod
  tim imenom.
- `channel_id` postoji u 571/588 unosa.

## Dopuna (S1, parseri i fixturei)

Izmjereno pri pisanju parsera (`src/input/`), ista sesija.

- **„`null`” u `info.json` je zapravo ključ koji NEDOSTAJE.** `CUJmOc91C64` nema ključ
  `channel`, `hmM9f_3Mqm4` nema ključ `duration` (na disku i na CDN-u). Ostalih 230/231
  ima ključ. `language` nema nijedan od 5 provjerenih `info.json`.
- **Registry slug ≠ CDN slug.** 46 od 52 sluga iz `index.json` ne postoji u registryju;
  svih 46 se nađe nakon `_` → `-` (`40_dana_za_zivot` ↔ `40-dana-za-zivot`). I ime se
  razlikuje: index `Nanovo rođeni`, registry `display_name` `Na novo rođeni`.
- **Registry `channel_id` nije jedinstven ni približno**: 32 `channel_id`-a imaju više
  unosa, najviše 20 (`UCjTiZ9ebMJumhPMsciuevxg`, `tribina` umbrella + playliste). Kanal
  epizode `kYwKrihe2K0` (`UCrfV3uhCoHNBaqiva1wCB4Q`, HKM) ima 10 unosa: umbrella `hkm`
  (`youtube.type: "umbrella"`) i 9 playlista, svi `tracking.enabled: false`.
  Razrješavanje Tier 2 kanala po `channel_id` mora birati među njima.
- Registry: 17 unosa nema `youtube.channel_id`, 1 ga ima kao `null`
  (`duhovno-duhoviti-poziv`); `tier` je `null` u 3 unosa (1: 27, 2: 29, 3: 490, 4: 39).
  `dijalog` ima `youtube: {url: null, handle: null, type: "audio-only"}` i
  `source_type: "audio-direct"`.
- `index.json` unos nema `latest_video_date` (samo `latest_video.date`); listing ga ima.
  `youtube_playlist_url` je `null` u svih 52 kanala.
- Listinzi (svih 52, 3412 epizoda): ID uvijek 11 znakova, `pipeline` uvijek s točno 9
  ključeva, `duration_seconds` uvijek `int`, svi datumi valjani, nijedan prazan
  `title`/`title_hr`, nijedan ID se ne ponavlja ni preko listinga. `magisterium_score`:
  363 cijela broja, 3049 `null`. `likes` zna biti `null` (`nanovoroeni` 11).
- `summary.json` `source.channel` je `"_unlisted"` i za `KLPD-Meu4e8` (Tier 1 kanal), pa
  kanal epizode iz njega ne slijedi. `summary.version` je string `"1.0"`, `episode.json`
  `version` broj `1`. `episode.json` `generated_at` je bez milisekundi
  (`2026-10-09T18:56:16Z`), `index.json`/listing s milisekundama.

```bash
# slug razlika i nejedinstven channel_id (registry iz fetch repoa, index s CDN-a)
curl -s https://cdn.domovina.ai/channels/data/index.json > /tmp/index.json
python3 -c "
import json,collections
reg=json.load(open('../fetch.domovina.tv/data/podcasts_registry.json'))['podcasts']
rs={e['slug'] for e in reg}; idx=[c['id'] for c in json.load(open('/tmp/index.json'))['channels']]
miss=[s for s in idx if s not in rs]; print(len(miss), sum(s.replace('_','-') in rs for s in miss))
c=collections.Counter(e['youtube'].get('channel_id') for e in reg if e['youtube'].get('channel_id'))
print(sum(n>1 for n in c.values()), c.most_common(1))"
```

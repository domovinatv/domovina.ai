# Fixturei parsera ulaza

Skraćeni **stvarni** podaci s `https://cdn.domovina.ai/` i iz
`../fetch.domovina.tv/data/podcasts_registry.json`. Ništa nije ručno pisano: sve generira
`npm run fixtures:refresh` (`scripts/fixtures-refresh.mjs`), a testovi ih uvoze kao `?raw`
(`test/input/fixtures.ts`, odluka 117). Raspored prati CDN.

## Što je što

| Datoteka | Zašto |
|---|---|
| `channels/index.json` | `index.json` sveden na 5 kanala: tri Tier 1 ispod i `slijedi_svoj_poziv_1`/`_2`, koji dijele YouTube `channel_id` (S2 mora podnijeti nejedinstven ID). |
| `channels/40_dana_za_zivot.json` | Tipičan YouTube kanal: ocjene magisteriuma i zastavice 15/31/511. |
| `channels/dijalog.json` | Spotify kanal: URL nije YouTube, ID-evi epizoda su 11 hex znakova. |
| `channels/nanovoroeni.json` | Drži `KLPD-Meu4e8`, epizodu koja je i u `_unlisted` (preklapanje Tier 1/Tier 2 za S2). |
| `data/kYwKrihe2K0/*` | Tier 2 epizoda kanala koji je u registryju (HKM: 10 unosa s istim `channel_id`, svi `tracking.enabled: false`). |
| `data/7N0gyXAfA4M/*` | Tier 2 epizoda kanala s jednim registry unosom (`tracking.enabled: false`). |
| `data/KLPD-Meu4e8/*` | Tier 2 kopija Tier 1 epizode; registry unos `nanovoroeni` nema `channel_id`. |
| `data/CUJmOc91C64/*` | X/Twitter: trajanje 245.295, ključa `channel` nema, numerički `channel_id`, kanal nije u registryju. |
| `data/hmM9f_3Mqm4/*` | Ključa `duration` nema (trajanje nepoznato), kanal nije u registryju. |
| `registry/podcasts_registry.json` | Unosi s `channel_id` nekog kanala iz fixturea, plus `nanovoroeni` i `dijalog` po slugu. |

## Pravila skraćivanja

- Vrijednosti koje parser čita su doslovne; mijenja se samo količina.
- Listing: ≤ 20 epizoda u izvornom redoslijedu (obavezne, sve s ocjenom magisteriuma, prva
  sa svakom kombinacijom zastavica, pa redom od vrha); `abstract` i `description` ≤ 160
  znakova + `…`, `topics`/`speakers` ≤ 3, `tags` ≤ 5. Zaglavlje (`video_count`, …) ostaje
  izvorno, pa `video_count` > broj epizoda u fixtureu.
- `index.json`: zaglavlje izvorno (i `channel_count: 52`), `channels` filtriran.
- `info.json`: samo `id, title, channel, channel_id, upload_date, duration, extractor,
  timestamp, webpage_url, uploader, language`; ključ koji u izvoru ne postoji ne postoji ni
  ovdje (nije `null`).
- `summary.json`: sve osim nizova i objekata unutar `summary` (`key_topics`, `speakers`, …).
- `episode.json`: `version`, `generated_at`, `files`; `inline` izbačen.
- Registry: `{version, podcasts}`, unosi bez `quality_score`, `notes`, `sources`,
  `discovery`, `revision`.

## Osvježavanje

```bash
cd katalog
npm run fixtures:refresh            # registry iz ../../fetch.domovina.tv/data/
KATALOG_REGISTRY_PATH=/put/do/podcasts_registry.json npm run fixtures:refresh
git diff --stat test/fixtures/      # drugo pokretanje bez promjene izvora = prazno
npm run check
```

Skripta pada ako: izabranog kanala ili epizode više nema, kanal za `CUJmOc91C64` ili
`hmM9f_3Mqm4` uđe u registry, `PIPELINE_BITS` u `src/input/pipeline-bits.ts` odstupi od
`generate_channel_index.js`, ili bilo koja zapisana datoteka ne prolazi svoj parser.
Testovi provjeravaju konkretne stvarne vrijednosti (ocjene, zastavice, datumi); ako se
izvor promijeni (npr. reobrada epizode), test pada i vrijednost se svjesno ažurira.
Registry fixture se mijenja i kad pipeline osvježi `activity.checked_at`.

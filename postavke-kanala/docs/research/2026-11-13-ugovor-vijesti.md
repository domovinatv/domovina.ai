# Ugovor: kako portal vijesti poštuje postavke kanala (S8, 13. 11. 2026.)

Ugovor između lanca „postavke kanala” i lanca vijesti (`vijesti/`). Ovaj lanac piše pravilo,
izvedba je u lancu vijesti (odluka 10: ovaj lanac ne mijenja kod ni dokumente `vijesti/`).
Ključevi i značenja su iz odluke 1, potrošači iz matrice
[2026-11-11-matrica-provedbe.md](2026-11-11-matrica-provedbe.md) §16.

## 1. Izvor stanja

`GET https://domovina.ai/api/katalog/v1/settings` (isti izvor kao pipeline, odluka 700):

```json
{"version":"1","catalog":"327","settings":{
  "UCxxxxxxxxxxxxxxxxxxxxxx":{"status":"active","off":["news_portal"],"slugs":["primjer_kanala"]},
  "UCyyyyyyyyyyyyyyyyyyyyyy":{"status":"deleted","off":["…svih 20…"],"deleted_at":"2026-…","slugs":["…"]}
}}
```

- Navedeni su samo UC-ovi s barem jednim isključenim ključem ili tombstoneom. Kanal kojeg nema
  u odgovoru ima sve uključeno (tvrdi uvjet 4 plana). Nepoznat ključ = uključen.
- `slugs` (odluka 800) su svi katalog slugovi tog UC-a. Engine kanal zna po slugu
  (`allowed_channels.channel`, listinzi), pa uspoređuje po slugu, normalizirano: lowercase i
  `_` = `-` (direktorij `domovina_tv` ↔ slug `domovina-tv`, odluka 702).
- Druga linija je UC epizode: `data/<id>/info.json` `channel_id`. Epizoda s playliste koja nije
  na kanalu vlasnika liste ima tuđi UC; isključeno kod BILO KOJEG od dva UC-a (kanal liste,
  `info.json`) znači isključeno (isto kao pipeline, odluka 702).
- Efektivni skup isključenih ključeva zatvara se po ovisnostima (odluka 108; izvedba
  `fetch.domovina.tv/lib/channel_settings.js` `closeOff`, prepisati, ne uvoziti preko repoa):
  `withdrawn`/`deleted` ili `channel_enabled` → svih 20; `transcript_subtitles` → svi AI ključevi
  (uključujući `news_portal`); `article_summary` → `news_portal` i ostali ovisni.

## 2. Ključevi koje engine i portal čitaju

| ključ (efektivno off) | engine | portal |
|---|---|---|
| `news_portal` | epizoda se ne uzima ni za izvlačenje, ni za ocjenu, ni za pisanje; ne nudi se kao „O istoj temi u drugim podcastima” | novi članci ne nastaju; objavljeni: §4 |
| `cdn_playback` | — | citat ostaje, `<audio>` isječak s CDN-a ne crta se (`mediaFile = null` u `Quote.astro`); poveznica „Poslušaj cijeli razgovor” ostaje (aplikacija sama pokaže YouTube umjesto našeg playera, S5) |
| `persons_mentions` | — | link s imena govornika na `/p/:slug` se ne crta (kad stranice osoba dođu, S10 vijesti); ime ostaje tekst |
| `search_engines` | — | članak se i dalje indeksira (članak je naš tekst, ne sadržaj kanala), ali `/v/` poveznice dobivaju `rel="nofollow"` |

`search_engines` red je prijedlog; ako lanac vijesti procijeni drukčije, vrijedi njihova odluka
uz zapis ovdje.

## 3. Gdje u engineu

- `engine/daily/run.ts` `loadAllowedChannels` → `recentEpisodes`: kanal s `news_portal` off
  ispada iz popisa prije dohvata listinga; epizoda se dodatno provjerava po `info.json`
  `channel_id` prije izvlačenja (druga linija iz §1).
- `engine/eval/sample.ts` i `engine/score/context.ts`: isto pravilo (eval ne smije uzorkovati
  isključen kanal, jer i eval troši LLM pozive nad sadržajem kanala).
- `engine/rag/related.ts`: poziv `mcp.domovina.ai/api/search` dobiva **`purpose=news`**
  (odluka 802). RAG tada sam izbacuje kanale s `news_portal` off. Bez parametra RAG
  pretpostavlja `search` i filtrira po `in_app_search`, što je za vijesti krivi ključ.
- Verifikacija (`runVerify`) postojećih nacrta: nacrt čiji izvorni trenutak pripada kanalu
  koji je u međuvremenu isključen ne ide dalje u `review`/`approved`; ostaje nacrt s napomenom
  „Vlasnik kanala isključio je portal vijesti” (urednik ga odbacuje ili čeka uključivanje).

## 4. Već objavljeni članci

| stanje kanala | prijedlog |
|---|---|
| `news_portal` off ili kanal povučen (reverzibilno) | članak ostaje objavljen: tekst je provjeren i objavljen kao novinarski prilog, a prekidač je reverzibilan (tvrdi uvjet 1: sakriti ≠ obrisati). Nema novih verzija koje dodaju citate tog kanala. Urednik može članak povući ručno (`retracted`), engine ništa ne mijenja sam. |
| kanal trajno obrisan (tombstone) | skripta brisanja (S9) javlja popis objavljenih članaka s trenucima tog kanala; urednik za svaki bira **ispravak** (nova verzija bez citata, zapis u `vijesti.corrections`, `kind='attribution'`) ili **povlačenje** s razlogom „Vlasnik kanala trajno je uklonio izvorni sadržaj”. Tiho brisanje članka nije dopušteno (politika ispravaka portala). |

Otvoreno za lanac vijesti: `article_sources.moment_id` je `ON DELETE RESTRICT`, pa S9 ne može
obrisati trenutke dok ih drži ijedna verzija (i stara). Treba odluka: anonimizirati trenutak
(prazan citat, zadržan red) ili brisati verzije prije trenutaka. S9 skripta čeka tu odluku
za `vijesti.*` (popis brisanja §4, red 10).

## 5. Ponašanje kad izvor nije dostupan

Engine je **pisac** (troši LLM pozive nad sadržajem kanala i stvara nove nacrte), pa je
**fail-closed** kao obrada u pipelineu (odluka 701): ako `/v1/settings` ne odgovori (3
pokušaja, 15 s), dnevni job preskače korak „nove epizode” i to piše u Telegram izvještaj;
red provjere postojećih nacrta i dalje radi (ništa ne objavljuje bez urednika). Portal je
**čitač**: koristi zadnju uspješnu snimku; bez nje crta kao danas.

## 6. Latencija

Promjena postavke → katalog D1: do jednog ciklusa pollera (S3). Katalog → engine: sljedeći
dnevni run (LaunchAgent 06:30, odluka 809 vijesti). Katalog → portal: SSR po zahtjevu uz
cache koji odredi lanac vijesti (preporuka ≤ 10 min, kao push).

## 7. Testovi koje lanac vijesti treba (prijedlog)

1. `settings:{}` → popis epizoda i pozivi identični današnjima.
2. Kanal s `news_portal` off (po slugu, i s `_`/`-` razlikom) → nema epizoda tog kanala u
   `recentEpisodes`, eval uzorku ni `related`.
3. Epizoda tuđeg kanala na listi, UC iz `info.json` isključen → preskočena.
4. `related.ts` šalje `purpose=news`.
5. Nedostupan izvor → korak „nove epizode” preskočen, run ne pada, izvještaj to kaže.
6. Portal: `cdn_playback` off → nema `<audio>`; `news_portal` off → objavljeni članak i dalje 200.

## 8. Poruka lancu vijesti

Za vrh sljedećeg handoffa lanca vijesti (korisnik je unosi ili potvrđuje da je ušla u
`vijesti/TODO.md`):

> **Iz lanca postavke kanala (S8, 13. 11.):** engine i portal moraju poštovati vlasnikove
> postavke kanala. Ugovor: `postavke-kanala/docs/research/2026-11-13-ugovor-vijesti.md`.
> Ukratko: `GET /api/katalog/v1/settings` jednom po runu; kanal s `news_portal` off (po slugu
> i po `info.json` UC-u) ne ulazi u `recentEpisodes`, eval ni `related`; `related.ts` šalje
> `purpose=news`; nedostupan izvor = korak „nove epizode” se preskače; portal bez `<audio>` kad
> je `cdn_playback` off. Objavljeni članci ostaju (prijedlog §4); za trajno obrisan kanal treba
> vaša odluka o `article_sources … ON DELETE RESTRICT`. Predložena stavka za TODO (F1):
> `- [ ] Postavke kanala: news_portal/cdn_playback filtar u engineu i portalu, purpose=news u related.ts (ugovor iz postavke-kanala S8)`.

# Staging i latencija iz HR (S5, 6. 11. 2026.)

**Zaključak:** F1 kako je planiran, uz jednu izmjenu u S6: hit putanja ne smije ići u D1.
Danas svaki zahtjev, i onaj koji se posluži iz cachea, prvo pita D1 za brend i verziju
kataloga (odluka 305). Primarna baza je u Milanu (MXP), a Worker se iz HR izvršava u Beču
(VIE), pa taj jedan upit košta ~32 ms. Bez njega bi hit bio na razini Workera bez D1
(p50 16–19 ms) i CDN-a (p50 20 ms). Snapshot iz D1 na R2 kao primarni put ne treba:
prva stranica kanala je 1,9 KB preko žice umjesto 119 KB listinga, a na mobilnoj mreži
presuđuju bajtovi, ne 30 ms.

Staging ostaje podignut za S6 (0 USD). Povratak je na dnu ovog dokumenta.

## Što je napravljeno

| Resurs | Vrijednost |
|---|---|
| Račun | D.O.M. (isti kao `domovina-analytics`, zona `domovina.ai`); ID samo u `katalog/.dev.vars` |
| D1 | `katalog-staging`, `80c56ea0-0fa3-4bbc-9b36-31b1c8641bbf`, hint `eeur`, primarna u MXP, read replication isključen |
| Worker | `domovina-katalog-staging`, https://domovina-katalog-staging.d-o-m.workers.dev, bez rute, bez secreta |
| Podaci | 1 brend, 162 kanala, 3670 epizoda, `ingest_runs` 5; 11 398 upisanih redaka |

```bash
cd katalog
export CI=1 WRANGLER_SEND_METRICS=false CLOUDFLARE_ACCOUNT_ID=<iz .dev.vars>
npx wrangler d1 create katalog-staging --location eeur
# database_id → env.staging u wrangler.jsonc
npx wrangler d1 migrations apply katalog-staging --remote --env staging
npm run migrate:local && npm run import
R=.wrangler/measure/staging; mkdir -p $R
npx wrangler d1 export katalog --local --no-schema \
  --table brands --table channels --table episodes --table ingest_runs --output $R/katalog-data.sql
npx wrangler d1 execute katalog-staging --remote --env staging --file $R/katalog-data.sql --yes
npx wrangler deploy --env staging
```

Provjera da je remote jednak lokalnom (oba vraćaju `1 | 162 | 3670 | 5 | 273972`):

```bash
Q="select (select count(*) from brands),(select count(*) from channels),(select count(*) from episodes),(select max(id) from ingest_runs where status='ok'),(select sum(length(id)+length(title)) from episodes)"
npx wrangler d1 execute katalog-staging --remote --env staging --command "$Q" --json
npx wrangler d1 execute katalog --local --command "$Q" --json
```

Izvoz je dao 3838 `INSERT`-a (1,64 MB); u S4 su bila 3832, razlika je pet novih epizoda i
jedan `ingest_runs` iz svježeg uvoza.

## Rizici iz S4: što je provjereno

| Rizik | Ishod |
|---|---|
| `x-katalog-cache: hit` na `workers.dev` | **radi**: drugi zahtjev na svim rutama `hit` |
| STRICT tablice na pravom D1 | **prima**: migracije 0001–0003 prošle |
| `INDEXED BY sqlite_autoindex_*` (306) | **prima**: nijedan upit ne pada; `rows_read` po formuli iz 406 |
| HEAD (314 a) | `404`, kao lokalno |
| sirovi `pathname` u ključu (314 c) | potvrđeno: `nano%76oroeni` je zaseban unos (prvi `miss`); nepoznat parametar (`&zz=1`) ne mijenja ključ (`hit`) |
| proizvoljan `Host` puni cache (314 d) | na `workers.dev` nemoguće: tuđi `Host` Cloudflare odbije s `403` prije Workera |
| potrošnja ostalih Workera (408) | 0,77 M zahtjeva i 561 M pročitanih D1 redaka u 30 dana (niže) |

```bash
B=https://domovina-katalog-staging.d-o-m.workers.dev/api/katalog/v1
for p in "channels?limit=30" "channels/nanovoroeni/episodes?limit=30" "episodes/Lg_n2sJDwxg/card" "days/2026-11-04?limit=30" "days/2026-11-06"; do
  for i in 1 2; do curl -s -o /tmp/b.json -D /tmp/h.txt "$B/$p"; echo "$p $(grep -i x-katalog-cache /tmp/h.txt) $(grep -o '"rows_read":[0-9]*' /tmp/b.json)"; done; done
curl -s -I $B/channels | head -1                                   # HTTP/2 404
curl -s -o /dev/null -D - "$B/channels/nano%76oroeni/episodes?limit=30" | grep -i x-katalog-cache
curl -s -o /dev/null -D - "$B/channels?limit=30&zz=1" | grep -i x-katalog-cache
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: evil.example' "$B/channels"   # 403
```

`rows_read` na stagingu: `channels?limit=30` 33 (`limit + 3`),
`channels/nanovoroeni/episodes?limit=30` 65 (`2 × (limit + 1) + 3`), kartica 4,
`days/2026-11-04?limit=30` 54 (dan ima 27 epizoda), prazan današnji dan 2.

## Latencija

Mac mini, Hrvatska, optički priključak, 6. 11. 2026. oko 10:05. TCP connect do oba hosta
11–13 ms. Svi zahtjevi su izašli u podatkovnom centru **VIE** (`cf-ray`). Tijela u tablici su raspakirana (`fetch` šalje `accept-encoding`). Vrijeme je do
zadnjeg bajta, uz keep-alive vezu (prvi zahtjev s TLS-om se bilježi zasebno). 50 zahtjeva po
nizu; miss niz ima 50 različitih stvarnih ključeva (drugi dan, kanal, epizoda ili `limit`),
hit niz je isti ključ nakon zagrijavanja.

```bash
cd katalog && npm run latency -- --out .wrangler/measure/latency-run1.json
```

| Ruta | miss p50 / p95 | hit p50 / p95 | tijelo |
|---|---|---|---|
| `days/<dan>?limit=30` | 86,9 / 129,3 ms | 51,6 / 56,4 ms | 1280 B (dan), 75 B (prazan današnji) |
| `channels/:slug/episodes?limit=30` | 83,5 / 89,6 ms | 51,0 / 59,5 ms | 10 500 B |
| `episodes/:id/card` | 81,2 / 90,8 ms | 51,6 / 57,3 ms | 371 B |
| `channels?limit=30…79` | 87,5 / 101,0 ms | 51,1 / 54,6 ms | 12 803 B |
| `health` (Worker bez D1 i cachea; 2. pokretanje) | — | 16,0 / 40,7 ms | 43 B |
| CDN `home.json` | — | 19,6 / 48,9 ms (`HIT` 50/50) | 28 744 B |
| CDN `nanovoroeni.json` (listing) | — | 33,6 / 46,5 ms (`HIT` 50/50) | 622 543 B |

Drugo pokretanje (`--out .wrangler/measure/latency-run2.json`) unutar sata dalo je hit
50,4–53,5 ms p50 na sve četiri rute, CDN `home.json` 20,0 ms, listing 33,2 ms, health
16,0 ms; miss niz je bio prazan jer su ključevi već bili u cacheu (skripta to broji kao
„hit izbačeno”). `days/<dan>` miss u prvom pokretanju ima n = 49: jedan dan je već bio
zagrijan provjerom iznad.

**Hladno nakon deploya**: prvi zahtjev nakon `wrangler deploy` (s DNS-om i TLS-om) 115 ms
(CDN 189 ms), u drugom pokretanju 65 ms (CDN 82 ms). Hladni start izolata se u tome ne
razlikuje od uspostave veze; nije faktor.

### Gdje odlazi vrijeme

- `health` ≈ CDN `HIT`: Worker sam po sebi ne dodaje ništa mjerljivo.
- hit − health ≈ **32 ms**: jedno putovanje VIE → D1 primarna u MXP (upit konteksta,
  `catalogContext`, prije `cache.match`). Sam SQL traje 0,15 ms
  (`wrangler d1 execute … --command "select 1" --json` → `sql_duration_ms`).
- miss − hit ≈ **32 ms**: drugo putovanje (upiti rute).

Što to znači za S6, redom isplativosti:

1. **Hit bez D1** (odluka 502): kontekst (brend po hostu, verzija kataloga) u memoriji
   izolata s kratkim TTL-om ili u samom Cache API-ju. Hit pada na ~16–20 ms, kao CDN.
   Cijena: nova verzija kataloga se vidi s kašnjenjem do TTL-a (npr. 30 s), što je
   ionako manje od `max-age=60` odgovora.
2. Miss u jednom putovanju: kontekst kao podupit u upitu rute ili `DB.batch`; ~50 ms.
3. D1 read replication (Sessions API) bi približio repliku Beču; traži `withSession` u
   kodu i nije potreban dok 1. i 2. nisu napravljeni.

### Usporedba s današnjim putem

Ekran kanala danas vuče cijeli listing: 622 KB raspakirano, **119 KB preko žice**, 33 ms
na optici. Katalog daje prvu stranicu (30 epizoda) od 9,4 KB raspakirano, **1,9 KB preko
žice**, za 51 ms (hit) ili 84 ms (miss). Na optici je to 20–50 ms sporije; na mobilnoj vezi
117 KB manje vrijedi više od toga (Chromeov Slow 4G, ~1,6 Mbit/s, za 117 KB treba ~0,6 s).
Uz izmjenu 1 razlika na hitu nestaje.

```bash
B=https://domovina-katalog-staging.d-o-m.workers.dev/api/katalog/v1
curl -s -o /dev/null --compressed -w '%{size_download}\n' "$B/channels/nanovoroeni/episodes?limit=30"   # 1914
curl -s -o /dev/null -w '%{size_download}\n' "$B/channels/nanovoroeni/episodes?limit=30"                # 9423
curl -s -o /dev/null --compressed -w '%{size_download}\n' https://cdn.domovina.ai/channels/data/nanovoroeni.json  # 119319
``` `home.json` ostaje statični snapshot (plan), pa se naslovnica ne mijenja.

Cache je po podatkovnom centru i po verziji kataloga: svaki uvoz (nightly) mijenja ključ, a
prvi korisnik u svakom centru plati miss. Udio hita će biti niži od pretpostavke iz 408;
stvarni broj daje tek produkcija.

## Potrošnja računa (odluka 408)

Zadnjih 30 dana na računu D.O.M. (GraphQL Analytics, `workersInvocationsAdaptive` i
`d1AnalyticsAdaptiveGroups`):

- Workeri: **769 053** zahtjeva (najveći `tehnoetika-app` 137 692,
  `pipeline-domovina-backend` 107 088); uključeno 10 M mjesečno.
- D1: **560 825 836** pročitanih i 326 628 upisanih redaka; 94 % čitanja je jedna baza
  (`pipeline_domovina`, 526 M). Uključeno 25 mlrd. Besplatni plan dopušta 5 M redaka
  dnevno (~150 M mjesečno), pa račun mora biti na Workers Paid.

Katalog i u scenariju 100× (90 M zahtjeva, odluka 408) prelazi uključene zahtjeve, ali D1
ostaje daleko ispod uključenog. Pages Functions (`web/_worker.js`) se ovdje ne vide po
imenu skripte; nisu provjerene.

Naredba: `python3 -I usage.py`. Skripta nije u repou jer čita OAuth token iz
`~/Library/Preferences/.wrangler/config/default.toml`; upit je:

```graphql
query($a:String!,$s:Time!,$e:Time!,$sd:Date!,$ed:Date!){viewer{accounts(filter:{accountTag:$a}){
 w:workersInvocationsAdaptive(limit:200,filter:{datetime_geq:$s,datetime_leq:$e}){sum{requests} dimensions{scriptName}}
 d:d1AnalyticsAdaptiveGroups(limit:200,filter:{date_geq:$sd,date_leq:$ed}){sum{rowsRead rowsWritten} dimensions{databaseId}}}}}
```

## Povratak

```bash
cd katalog
export CI=1 CLOUDFLARE_ACCOUNT_ID=<iz .dev.vars>
npx wrangler delete --env staging
npx wrangler d1 delete katalog-staging
# zatim maknuti env.staging iz wrangler.jsonc
```

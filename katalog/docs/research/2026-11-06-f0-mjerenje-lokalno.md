# F0 mjerenje na lokalnom D1: 10k, 100k, 1M epizoda (S4, 06.11.2026.)

## Zaključak

`rows_read` po zahtjevu ne raste s veličinom kataloga ni s dubinom kursora: na 10k, 100k i
1M epizoda svaka ruta čita isti broj redaka (najskuplja, epizode diva uz limit 100, 205 na
prvoj i 206 na najdubljoj punoj stranici na sve tri razine), pa tvrdi uvjet 2 vrijedi i
nijedna ruta ne treba popravak. Baza ima 411 B po epizodi s indeksima (1M = 411 MB, 392 MiB), dakle
u jednu D1 bazu od 10 GB uz rezervu 30 % stane 17,0 M epizoda: DOMOVINA (3665 epizoda,
~9000 godišnje) je tri reda veličine ispod toga i shard po brendu joj je dovoljan
desetljećima. Svjetski korpus od 500 000 kanala stane u jednu bazu samo uz današnju gustoću
(23 epizode po kanalu, 4,75 GB), uz gustoću Tier 1 kanala (66) treba 2 baze, a s rastom od
~3,1 GB godišnje shard unutar brenda (jezik/zemlja ili hash kanala) postaje nužan unutar
godinu dana od takvog korpusa. Trošak D1 čitanja je zanemariv i u scenariju 100× (1,4 mlrd.
redaka mjesečno, ispod 25 mlrd. uključenih); trošak vodi broj Worker zahtjeva (~24 USD
mjesečno iznad paušala na 90 M zahtjeva). Lokalno trajanje je ~1–2 ms i govori samo da
upit nije usko grlo na Macu; latencija za odluku je ona sa staginga (S5).

Sve naredbe se pokreću iz `katalog/`. Lokalni izlazi su u `.wrangler/measure/` (u
`.gitignore`).

## Postupak

```bash
# generator (stvarno trajanje: /usr/bin/time; log u .wrangler/measure/synth-*.log)
/usr/bin/time -l npm run synth -- --episodes 10000   --seed 1 --persist .wrangler/synth-10k  --force
/usr/bin/time -l npm run synth -- --episodes 100000  --seed 1 --persist .wrangler/synth-100k --force
/usr/bin/time -l npm run synth -- --episodes 1000000 --seed 1 --persist .wrangler/synth-1m   --force
# mjerenje (skripta digne i ugasi wrangler dev --local na :8799; JSON u .wrangler/measure/<ime>.json)
npm run measure -- --persist .wrangler/synth-10k
npm run measure -- --persist .wrangler/synth-100k
npm run measure -- --persist .wrangler/synth-1m
```

`scripts/measure.ts` (zadano `--reps 30 --deep 20`): (a) iz SQLite datoteke
`PRAGMA page_count/page_size/freelist_count` i `dbstat` po tablici i indeksu; (b) za svaku
rutu prva stranica, pa slijedi `next` do 20 stranica (div do kraja), „duboka” je najdublja
PUNA stranica. MISS se mjeri tako da svako ponavljanje ima drugi `Host` (origin je u
ključu cachea, odluka 307/314 d; host nije u `brands`, pa vrijedi `DEFAULT_BRAND`), HIT
zasebno nakon zagrijavanja istim hostom. Imena hostova nose oznaku pokretanja, jer
`--persist-to` čuva i Cache API na disku (prvo ponovljeno mjerenje 10k bez oznake dalo je
675 lažnih „miss” koji su bili hit). U svim izvještajima ovdje `missWasHit = 0`.

`meta.rows_read` u tijelu HIT-a je iz izračuna koji je zapis stvorio; stvarni D1 trošak
HIT-a je samo upit konteksta, 2–3 retka (odluka 305).

**Trajanje je lokalno**: Node → `wrangler dev` → workerd → SQLite na Macu (keep-alive, jedan
socket, sekvencijalno). To nije latencija D1 na edgeu, gdje upit ide iz Workera u
podatkovni centar baze.

## Veličina baze i generator

| razina | epizoda | kanala | baza | B/epizodi (cijela baza) | B/epizodi (`episodes` + indeksi) | B/kanalu | generator (ukupno / upis) |
|---|---|---|---|---|---|---|---|
| stvarno (S2) | 3665 | 162 | 1,36 MB | 372 | 342 | 303 | — |
| 10k | 10 000 | 401 | 4,2 MB | 420 | 405 | 266 | 1,1 s / 0,1 s |
| 100k | 100 000 | 4300 | 41,3 MB | 413 | 402 | 239 | 2,7 s / 1,6 s |
| 1M | 1 000 000 | 43 263 | 411,4 MB (392 MiB) | **411,4** | 401,2 | 234,9 | 35,2 s / 32,9 s |

Raspodjela na 1M (`dbstat`): `episodes` 303,8 MB, `episodes_by_channel` 57,8 MB,
`episodes_by_date` 39,6 MB, `channels` 5,8 MB, `channels_directory` 2,2 MB,
`channels_all_by_date` 2,2 MB. Indeksi epizoda su 24 % baze. `freelist_count` 0 na svim
razinama. Generator 1M: 310 MB RSS, migracije 0,8 s, prvi prolaz 0,9 s.

Sintetička epizoda je ~17 % teža od stvarne (401 prema 342 B za `episodes` + indeksi):
naslovi su prosječno 153 prema 126 znakova (`title` + `title_hr`). Projekcija s 411 B je
zato konzervativna.

```bash
# „stvarno (S2)”: probna kopija stvarnih podataka (vidi „Staging”, korak 4) izmjerena istom skriptom
npm run measure -- --persist .wrangler/rehearsal
# usporedba stvarne i sintetičke epizode
for d in state synth-1m; do f=$(ls .wrangler/$d/v3/d1/miniflare-D1DatabaseObject/*.sqlite | grep -v metadata)
  sqlite3 -readonly "$f" "select count(*), (select sum(pgsize) from dbstat where name in
    ('episodes','episodes_by_channel','episodes_by_date'))*1.0/count(*),
    avg(length(title)+coalesce(length(title_hr),0)) from episodes"; done
```

## `rows_read` po ruti

Prva / najdublja puna stranica; u zagradi dubina u stavkama. Isto na sve tri razine osim
dubine (koja raste jer je katalog veći), što je točno tvrdnja uvjeta 2.

| ruta | limit | 10k | 100k | 1M |
|---|---|---|---|---|
| `days/2026-10-20` (vrući dan: 104 / 829 / 7969 epizoda) | 20 | 44 / 44 (80) | 44 / 44 (380) | 44 / 44 (380) |
| | 100 | 204 / — (1 str.) | 204 / 204 (700) | 204 / 204 (1900) |
| `channels` | 20 | 23 / 24 (380) | 23 / 24 (380) | 23 / 24 (380) |
| | 100 | 103 / 104 (300) | 103 / 104 (1900) | 103 / 104 (1900) |
| `channels?tier=1` | 20 | 23 / 24 (80) | 23 / 24 (380) | 23 / 24 (380) |
| | 100 | 103 / — | 103 / 104 (1200) | 103 / 104 (1900) |
| `channels?tier=2` | 20 | 23 / 24 (260) | 23 / 24 (380) | 23 / 24 (380) |
| | 100 | 103 / 104 (100) | 103 / 104 (1900) | 103 / 104 (1900) |
| `directory` | 20 | 23 / 24 (380) | 23 / 24 (380) | 23 / 24 (380) |
| | 100 | 103 / 104 (300) | 103 / 104 (1900) | 103 / 104 (1900) |
| `channels/:div/episodes` (div: 1000 / 1990 / 2981 epizoda, do kraja) | 20 | 45 / 45 (980) | 45 / 46 (1960) | 45 / 46 (2960) |
| | 100 | 205 / 205 (900) | 205 / 206 (1800) | 205 / 206 (2800) |
| `channels/:mali/episodes` (1 epizoda) | 20, 100 | 6 | 6 | 6 |
| `channels/:div`, `channels/:mali` | — | 3 | 3 | 3 |
| `episodes/:id/card` | — | 4 | 4 | 4 |

Oblik je `2 × (limit + 1) + 2…4` za popise epizoda (stranica + JOIN kanala po PK + upit
konteksta + zaglavlje kanala) i `limit + 3…4` za popise kanala, kao u odlukama 309 i 313.
Najveći `rows_read` na bilo kojoj stranici bilo kojeg prolaza je 206. **Nijedna ruta ne
raste s veličinom kataloga**, pa `EXPLAIN QUERY PLAN` nije trebao istragu; planovi su već
čuvani testovima iz S3 (`test/api/`). Na stvarnim podacima (probna kopija) isti brojevi:
23/24, 45/46, 205/206, 3, 4.

```bash
node -e 'const r=require("./.wrangler/measure/synth-1m.json");for(const x of r.results)
  console.log(x.name,x.limit,x.first.rowsRead,x.deep?.rowsRead,x.deep?.maxRowsRead,x.deep?.depthItems)'
```

## Trajanje (lokalno, ms)

p50 / p95 preko 30 ponavljanja. Raspon kroz sve rute, limit 20 i 100:

| razina | MISS prva stranica | MISS duboka stranica | HIT |
|---|---|---|---|
| 10k | p50 0,86–1,96 · p95 1,27–4,31 | p50 1,21–1,55 · p95 1,85–3,39 | p50 0,71–1,02 · p95 0,76–2,16 |
| 100k | p50 0,86–2,26 · p95 1,06–4,33 | p50 0,96–1,63 · p95 1,45–3,38 | p50 0,71–0,92 · p95 0,81–5,87 |
| 1M | p50 0,84–1,56 · p95 1,08–3,00 | p50 0,98–1,60 · p95 1,59–3,09 | p50 0,71–1,07 · p95 0,80–2,41 |

Najskuplja ruta na 1M (`channels/:div/episodes?limit=100`): MISS 1,56 / 2,07, duboka MISS
1,58 / 3,09, HIT 0,77 / 2,41. Razlika MISS − HIT je ~0,3–0,8 ms i ne ovisi o razini: na Macu
upit nije usko grlo. To ništa ne govori o edgeu (mreža Worker → D1, hladna baza, PoP
udaljen od baze); to mjeri S5.

```bash
node -e 'const r=require("./.wrangler/measure/synth-1m.json");for(const x of r.results)
  console.log(x.name,x.limit,x.first.timing.miss,x.first.timing.hit,x.deep?.timing.miss)'
```

## Projekcija: koliko stane u D1 i koliko baza treba

Limiti (Workers Paid), pročitano 06.11.2026. na
<https://developers.cloudflare.com/d1/platform/limits/>: najveća baza **10 GB** („the
10 GB limit of a D1 database cannot be further increased”), 1 000 000 baza po računu
(prvih 100 000 uključeno), 1 TB po računu, 1000 upita po pozivu Workera, 100 vezanih
parametara po upitu, 30 s po upitu. Preporuka: mnogo manjih baza („per-user, per-tenant or
per-entity databases”).

Model: `baza = E × 401,2 B + C × 234,9 B` (1M), budžet 70 % od 10 GB = 7 × 10⁹ B.

| mjera | vrijednost |
|---|---|
| epizoda u jednoj bazi uz 70 % | **17,0 M** (bez rezerve 24,3 M) |
| DOMOVINA danas | 3665 epizoda ≈ 1,4 MB (0,02 % budžeta) |
| DOMOVINA rast | ~25 epizoda/dan ≈ 9100/god ≈ 3,7 MB/god |
| 500 000 kanala, 23,1 ep/kanal (gustoća generatora = stvarnih 162 kanala) | 11,55 M ep, **4,75 GB, 1 baza** (68 % budžeta) |
| 500 000 kanala, 65,9 ep/kanal (prosjek stvarnog Tier 1 kanala) | 32,95 M ep, 13,34 GB, **2 baze** |
| 500 000 kanala, 150 ep/kanal (pretpostavka: puni stražnji katalog) | 75 M ep, 30,21 GB, **5 baza** |
| najviše kanala po bazi uz 23,1 / 65,9 / 150 ep/kanal | 737k / 262k / 116k |
| rast 500 000 kanala uz 15,5 ep/kanal/god (25/dan ÷ 588 unosa registryja) | 7,8 M ep ≈ **3,1 GB/god ≈ 0,44 baze/god** |

```bash
python3 -c "
b_e,b_c=401.2,234.9
for d in (23.1,65.9,150):
  E=500_000*d; G=(E*b_e+500_000*b_c)/1e9; print(d, E/1e6, round(G,2), round(G/7,2), round(7e9/(d*b_e+b_c)/1e3,1))
print(7e9/411.4/1e6, 1e10/411.4/1e6); g=25*365/588; print(g, 500_000*g*b_e/1e9)"
```

Gustoća 23,1 = 1 000 000 / 43 263 (sintetika) ≈ 3665 / 162 (stvarno, 22,6). Stopa 25/dan je
iz `plan.md` („~25 epizoda dnevno”), 588 iz istog dokumenta; to je stopa hrvatskog i
regionalnog korpusa i za svjetski korpus je pretpostavka.

**Za odluku 4:**

- **Shard po brendu je dovoljan** dok brend ima manje od ~17 M epizoda (7 GB uz 411 B po
  epizodi). DOMOVINA je na 3665 i raste ~9100 godišnje: i uz 100× rasta (0,37 M epizoda,
  ~150 MB) koristi 2 % budžeta. Za DOMOVINA odluka 4 stoji bez promjene.
- **Shard unutar brenda treba** brendu sa svjetskim korpusom (Podcasterium) kad
  `kanala × epizoda po kanalu > ~17 M`: uz današnju gustoću od ~737 000 kanala, uz gustoću
  Tier 1 već od ~262 000, uz puni stražnji katalog od ~116 000. Uz rast ~3,1 GB godišnje na
  500 000 kanala i jedna baza koja danas stane puni budžet za manje od godinu dana.
- **Ključ sharda** mora držati svaki shard ispod 17 M. Jezik/zemlja je prirodan za popise
  (`days`, `channels`, `directory` su po brendu i jeziku), ali najveći jezik (engleski)
  može sam premašiti budžet; tada shard po hashu kanala unutar jezika. Popis kanala i dana
  preko više shardova traži fan-out i spajanje po kursoru u Workeru (≤ 6 istodobnih veza po
  pozivu, 1000 upita po pozivu), pa `rows_read` po stranici raste s brojem shardova, ne s
  katalogom. To je posao S14.
- Veličina baze ne mijenja `rows_read` (tablica gore), pa shard je pitanje kapaciteta, ne
  troška čitanja.

## Trošak

Cjenik, pročitano 06.11.2026.: <https://developers.cloudflare.com/d1/platform/pricing/>
(Workers Paid: rows read prvih **25 mlrd./mj.** uključeno, zatim **0,001 USD / M**; rows
written prvih 50 M/mj., zatim 1,00 USD / M; pohrana prvih 5 GB, zatim 0,75 USD / GB-mj.;
nema naplate prometa) i <https://developers.cloudflare.com/workers/platform/pricing/>
(paušal 5 USD/mj. po računu; 10 M zahtjeva/mj. uključeno, zatim 0,30 USD / M; 30 M CPU ms
uključeno, zatim 0,02 USD / M CPU ms). D1 broji retke koje upit prođe, ne koje vrati, i
indeks povećava rows written.

Formula:

```
Q    = DAU × sesija/dan × zahtjeva kataloga/sesiji × 30
rows = Q × ((1 − h) × R_miss + h × R_hit)
D1   = max(0, rows − 25e9) × 0,001 / 1e6
Wkr  = max(0, Q − 10e6) × 0,30 / 1e6 + max(0, Q × cpu_ms − 30e6) × 0,02 / 1e6   (+ 5 USD paušal računa)
```

Pretpostavke (nisu izmjerene; DAU zamijeniti brojkom iz ClickHousea u S5): DAU DOMOVINA
danas **1000**, 2 sesije dnevno, 15 zahtjeva kataloga po sesiji, udio HIT-a `h = 0,8`,
`R_miss = 67` (`channels/:slug/episodes?limit=30` na stvarnim podacima, odluka 309;
zadani limit je 30), `R_hit = 3` (upit konteksta), CPU 1 ms po zahtjevu.

| scenarij | Q / mj. | rows read / mj. | najgore (h = 0, R = 206) | D1 čitanje | Worker zahtjevi + CPU |
|---|---|---|---|---|---|
| DOMOVINA danas (1000 DAU) | 0,9 M | 14,2 M | 0,19 mlrd. | 0 USD | 0 USD (unutar uključenog) |
| 10× (10 000 DAU) | 9 M | 142 M | 1,85 mlrd. | 0 USD | 0 USD |
| 100× (100 000 DAU) | 90 M | 1,42 mlrd. | 18,5 mlrd. | 0 USD | 24,00 + 1,20 USD |

Python za tablicu: zadnja petlja u naredbi iz „Projekcija” proširena formulom gore, ili:

```bash
python3 -c "
for D in (1000,10000,100000):
  Q=D*2*15*30; print(D, Q/1e6, Q*(0.2*67+0.8*3)/1e6, Q*206/1e9, max(0,Q-10e6)*0.3/1e6, max(0,Q-30e6)*0.02/1e6)"
```

Čitanje iz D1 ne košta ništa ni u najgorem slučaju 100×: tek iznad ~121 M zahtjeva
mjesečno bez ijednog HIT-a (25 mlrd. / 206) počinje naplata, i tada 1 mlrd. redaka košta
1 USD. Trošak vodi broj Worker zahtjeva, a HIT u našem Cache API-ju je i dalje poziv
Workera (cache je u Workeru, odluka 307). Uključenih 10 M zahtjeva i 25 mlrd. redaka dijele
se s ostalim Workerima i Pages Functions na istom računu (`web/_worker.js`,
`domovina-analytics`), čiju potrošnju ovo mjerenje ne zna.

Pisanje: uvoz stvarnih podataka ≈ 11 381 redak (epizode 3665 + 2 indeksa po ne-varijanti,
kanali × 3, brend × 2, `ingest_runs`), dnevni ingest ~25 epizoda × 3 + kanali ≈ 100–150
redaka; ponovljeni uvoz bez promjena 0 pisanja (upsert s `WHERE … IS NOT`, odluka 214).
Sve je unutar 50 M uključenih. Sintetika 1M na stagingu (ako S5 želi latenciju na skali):
~3,1 M redaka pisanja, 0,41 GB pohrane, i dalje unutar uključenog.

```bash
f=$(ls .wrangler/rehearsal/v3/d1/miniflare-D1DatabaseObject/*.sqlite | grep -v metadata)
sqlite3 -readonly "$f" "select (select count(*) from episodes) + 2*(select count(*) from episodes where variant_of is null)
  + 2*(select count(*) from channels) + (select count(*) from channels where processed_count>=1)
  + 2*(select count(*) from brands) + (select count(*) from ingest_runs) + (select count(*) from ingest_runs where status='ok')"
```

## Staging (S5) — naredbe, NIŠTA OD OVOGA NIJE POKRENUTO

U S4 nijedna naredba nije išla prema Cloudflare računu. `wrangler.jsonc` nije mijenjan.

Prijedlog `env.staging` u `wrangler.jsonc` (D1 vezanja i `vars` se ne nasljeđuju iz vrha
konfiguracije, pa se ponavljaju; bez `routes`, samo `workers.dev`):

```jsonc
  "env": {
    "staging": {
      "name": "domovina-katalog-staging",
      "workers_dev": true,
      "vars": { "DEFAULT_BRAND": "domovina" },
      "d1_databases": [
        {
          "binding": "DB",
          "database_name": "katalog-staging",
          // ID iz `wrangler d1 create katalog-staging`. Ide u javni repo:
          // database_id nije tajna (bez tokena ne daje pristup), ali se ne
          // upisuje ništa drugo s računa (account_id ostaje izvan konfiguracije).
          "database_id": "<ID iz koraka 2>",
          "migrations_dir": "migrations"
        }
      ]
    }
  }
```

```bash
cd katalog
# 1. račun (prijava u pregledniku; provjera da je to račun zone domovina.ai)
npx wrangler login
npx wrangler whoami

# 2. baza; ispisani database_id upisati u env.staging gore
npx wrangler d1 create katalog-staging

# 3. shema (iste tri migracije)
npx wrangler d1 migrations apply katalog-staging --remote --env staging

# 4. podaci: izvoz iz lokalnog D1 (S2 uvoz u .wrangler/state) i izvršavanje na remoteu.
#    Samo tablice podataka: d1_migrations već puni korak 3 i dupli unos bi pukao.
#    Lokalna proba ovog koraka je napravljena (vidi niže).
npm run migrate:local && npm run import          # osvježi lokalni D1 s CDN-a (po želji)
npx wrangler d1 export katalog --local --no-schema \
  --table brands --table channels --table episodes --table ingest_runs \
  --output .wrangler/measure/staging-rehearsal/katalog-data.sql
npx wrangler d1 execute katalog-staging --remote --env staging \
  --file .wrangler/measure/staging-rehearsal/katalog-data.sql
npx wrangler d1 execute katalog-staging --remote --env staging \
  --command "select (select count(*) from channels), (select count(*) from episodes), (select max(id) from ingest_runs where status='ok')"

# 5. deploy i provjera
npx wrangler deploy --env staging
curl -s https://domovina-katalog-staging.<subdomena>.workers.dev/api/katalog/v1/health
curl -s -D - 'https://domovina-katalog-staging.<subdomena>.workers.dev/api/katalog/v1/channels?limit=30' -o /dev/null | grep -i x-katalog-cache

# 6. povratak
npx wrangler delete --env staging
npx wrangler d1 delete katalog-staging
```

**Lokalna proba koraka 4** (samo `--local`, stvarni podaci iz S2): izvoz 1,64 MB, 3832
`INSERT`-a (1 brend, 162 kanala, 3665 epizoda, 4 `ingest_runs`) uz
`PRAGMA defer_foreign_keys=TRUE`; izvršavanje u svježe migrirani lokalni D1
(`.wrangler/rehearsal`) „3833 commands executed successfully”, `pragma foreign_key_check`
prazan, brojevi i sadržaj (`sum(length(id)+length(title))` 273 604) isti kao izvor, verzija
kataloga `4`; API nad tom kopijom daje iste `rows_read` kao izvor.

```bash
export CI=1 WRANGLER_SEND_METRICS=false R=.wrangler/measure/staging-rehearsal P=.wrangler/rehearsal
mkdir -p $R && rm -rf $P
npx wrangler d1 export katalog --local --no-schema --table brands --table channels --table episodes --table ingest_runs --output $R/katalog-data.sql
npx wrangler d1 migrations apply katalog --local --persist-to $P
npx wrangler d1 execute katalog --local --persist-to $P --file $R/katalog-data.sql --yes
f=$(ls $P/v3/d1/miniflare-D1DatabaseObject/*.sqlite | grep -v metadata)
sqlite3 -readonly "$f" "select (select count(*) from channels),(select count(*) from episodes),(select max(id) from ingest_runs where status='ok'); pragma foreign_key_check;"
```

**`import.mjs` i `--remote`**: danas piše samo lokalno (`getPlatformProxy({ remoteBindings:
false })`, `.wrangler/state`). Za jednokratni staging uvoz dovoljan je korak 4 bez promjene
koda. Za ingest iz uvoznika na remote (S6) treba: zastavica `--remote --env <env>` koja
proslijedi `environment` u `getPlatformProxy` i uključi `remoteBindings: true`, uz
`"remote": true` na D1 vezanju u tom okruženju; `applyPlan` tada šalje ~20 `db.batch` po
200 naredbi preko mreže (3665 epizoda), a provjera „lokalni D1 nije migriran” postaje
provjera remotea. Zaštita: bez `--env` uvoznik nikad ne smije pisati na remote.

## Rizici za S5

1. **HEAD je 404** (odluka 314 a). Monitori i neki klijenti šalju HEAD; na stagingu
   provjeriti da ništa ne ovisi o tome, popravak je mali (HEAD = GET bez tijela).
2. **Ključ cachea nosi sirovi `pathname`** (314 c): `%73ubclub` i `subclub` su dva zapisa.
3. **Proizvoljan `Host` puni cache** (314 d). Na `workers.dev` host je fiksan, na zoni ga
   ograničava ruta; isti mehanizam ova skripta koristi za mjerenje MISS-a lokalno.
4. **Cache API na `workers.dev` nije potvrđen**: dokumentacija kaže da Workeri „deployed
   to custom domains have access to functional `cache` operations” i ne spominje
   `workers.dev` (<https://developers.cloudflare.com/workers/runtime-apis/cache/>, čitano
   06.11.2026.). S5 mora provjeriti `x-katalog-cache: hit`; ako HIT-a nema, HIT latencija
   se mjeri tek na ruti zone. Cache API je lokalan po podatkovnom centru i nema tiered
   cache, pa je stvarni udio HIT-a niži od `h = 0,8` iz troška za promet raspršen po PoP-ovima.
5. **`INDEXED BY sqlite_autoindex_*` i STRICT na pravom D1** nisu provjereni (odluka 306).
   Ako D1 odbije ime autoindeksa, sve rute s karticom i zaglavljem padaju s 500; revizija
   je već zapisana u 306.
6. **`rows_read` na pravom D1** može se brojati drukčije od lokalnog miniflarea; prva
   provjera na stagingu je usporedba `meta.rows_read` s tablicom gore.
7. **Brisanje kanala skenira `episodes`**: parcijalni `episodes_by_channel` ne služi
   provjeri stranog ključa (odluka 302). Na 1M to je 1M redaka po brisanju; uvoz danas ne
   briše, drift-check (S6) hoće.
8. **Poruka D1 iznimke ide u log** (`internalErrorResponse`): na stagingu provjeriti da log
   ne nosi ništa osim poruke i putanje.
9. **U profilu `korpus` zastavice su nasumične**: `p` (`flags`) u sintetici ne prati
   stvarnu korelaciju (npr. EN članak samo uz HR). Za `rows_read` i veličinu nebitno, za
   bilo kakav test filtra po zastavici neupotrebljivo.
10. **Latencija nije izmjerena nigdje osim na Macu.** Pretpostavka plana (D1 + edge cache
    nije sporiji od statičnog `home.json`) ostaje neprovjerena do S5.

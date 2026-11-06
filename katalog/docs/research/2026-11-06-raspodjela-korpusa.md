# Raspodjela stvarnog korpusa i kako je generator skalira (S4, 06.11.2026.)

Izmjereno na lokalnom D1 iz S2 uvoza (nakon migracije `0003` i ponovnog uvoza u S3,
`ingest_runs.id` 4), samo čitanjem. Ovim se oblikom ravna raspodjela `korpus` u
`src/synth/korpus.ts`, koju puni `scripts/synth.ts`. Naredbe se pokreću iz `katalog/`.

```bash
F=$(ls .wrangler/state/v3/d1/miniflare-D1DatabaseObject/*.sqlite | grep -v metadata)
```

## Oblik

| mjera | vrijednost |
|---|---|
| epizoda | 3665 (Tier 1: 3412, Tier 2: 253 = 6,9 %) |
| kanala | 162 (Tier 1: 52, Tier 2: 110, bez registryja: 28) |
| epizoda bez kanala | 22 (0,6 %), sve Tier 2 |
| epizoda bez datuma | 0 |
| varijanti (`variant_of`) | 55 (1,5 %): 15 osnova s 3–4 varijante, sve iz zadnjeg mjeseca |
| Tier 2 epizoda na Tier 1 kanalu | 17 od 3429 |
| najveći dan | `2026-11-02`, 28 ne-varijanti (0,78 %); prosjek 2026. je 3,2 na dan |
| najveći kanal | 320 epizoda (`nanovoroeni`); prosjek Tier 1 kanala 65,9 |
| `magisterium_score` nije NULL | 363 (9,9 %) |
| `duration_seconds` je NULL | 4 |
| raspon datuma | 1698 različitih dana, 2010-10-28 … 2026-11-05 |

Kanali po broju epizoda (sve epizode kanala, i varijante):

| epizoda po kanalu | 1 | 2 | 3–10 | 11–100 | 101–1000 | > 1000 |
|---|---|---|---|---|---|---|
| kanala | 78 (48 %) | 13 (8 %) | 33 (20 %) | 27 (17 %) | 11 (7 %) | 0 |
| epizoda u razredu | 78 | 26 | 198 | 1218 | 2123 | 0 |

Epizode po godini: 2010 1, 2016 9, 2017 40, 2018 39, 2019 65, 2020 204, 2021 286,
2022 242, 2023 367, 2024 587, 2025 891, 2026 934.

```bash
sqlite3 -readonly "$F" "
select count(*), sum(tier=1), sum(tier=2), sum(channel_slug is null), sum(published_date is null),
       sum(variant_of is not null) from episodes;
select count(*), sum(tier=1), sum(tier=2), sum(unregistered) from channels;
with c as (select channel_slug s, count(*) n from episodes where channel_slug is not null group by 1)
select case when n=1 then '1' when n=2 then '2' when n<=10 then '3-10' when n<=100 then '11-100'
            when n<=1000 then '101-1000' else '>1000' end b, count(*), sum(n) from c group by b order by min(n);
select published_date, count(*) from episodes where variant_of is null group by 1 order by 2 desc limit 1;
select n, count(*) from (select variant_of, count(*) n from episodes where variant_of is not null group by 1) group by n;
select count(*) from episodes e join channels c on c.slug = e.channel_slug where e.tier = 2 and c.tier = 1;
select substr(published_date,1,4), count(*) from episodes group by 1;
select sum(magisterium_score is not null), sum(duration_seconds is null) from episodes;"
# veličine kanala po tieru (ulaz za bootstrap u korpus.ts)
sqlite3 -readonly "$F" "select c.tier, group_concat(n) from (select c.tier, count(e.id) n from channels c
  join episodes e on e.channel_slug = c.slug group by c.slug order by n desc) c group by c.tier"
```

## Kako se skalira na N

Veći katalog ima **više kanala, ne dulje kanale**: S2 korpus je 162 kanala koji su u
pipelineu od kolovoza, a rast (Podcasterium, više brendova) dolazi novim kanalima. Zato:

1. **Udjeli po epizodi su stalni**: bez kanala 0,6 %, Tier 2 kanali 5,84 %, varijante 1,5 %,
   Tier 2 na Tier 1 kanalu 0,5 %, ostalo Tier 1 kanali. Zbroj je točno N.
2. **Veličina kanala se uzorkuje iz stvarnih** (bootstrap: 52 Tier 1 i 110 Tier 2
   veličina iz tablice gore), dok se budžet tiera ne potroši. Broj kanala je zato ∝ N
   (≈ 44 na 1000 epizoda, kao stvarnih 162 na 3665), a histogram ostaje isti na svakoj
   razini.
3. **Divovski kanali**: `max(1, round(N / 50 000))` Tier 1 kanala od 1000–3000 epizoda
   (log-uniformno), najviše N / 10. Danas ih nema (najveći 320), ali u većem katalogu ih
   ima: dnevna emisija kroz ~8 godina je ~3000 epizoda. Gornja granica 3000 drži ih
   realnima; bez divova bi najdublji kursor po kanalu bio ~4 stranice po 100.
4. **Datumi** po godišnjim težinama iz tablice (2016–2026, unutar godine jednoliko, do
   `2026-11-04`). Vrući dan `2026-10-20` dobiva 0,5 % epizoda više, pa s prirodnim
   udjelom i osnovama varijanti ima ~0,8 % N, kao najveći stvarni dan (0,78 %).
5. **Varijante** u grupama od 3 i 4 (kao stvarne), ravnomjerno po epizodama s kanalom,
   odmah iza osnove; osnova je pola na vrućem danu, pola u zadnjih 30 dana.
6. **Bez datuma**: 0,05 % iako je stvarno 0, da put `published_date IS NULL` postoji i na
   1M. Uz to 10 trojki ID-eva koje se razlikuju samo veličinom slova na prvom divu.

Rezultat generatora (`Tally`, iste kategorije kao gore), sjeme 1; izvedeno iz
`new Korpus(...).episodes()`, upis u D1 izmjeren samo na 10k:

| N | kanala | 1 / 2 / 3–10 / 11–100 / 101–1000 / > 1000 | najveći | Tier 2 | varijanti | vrući dan |
|---|---|---|---|---|---|---|
| 10 000 | 401 | 201 / 27 / 84 / 59 / 29 / 1 | 1014 | 7,0 % | 150 | 104 |
| 100 000 | 4300 | 2054 / 355 / 902 / 705 / 282 / 2 | 2022 | 7,0 % | 1501 | 829 |
| 1 000 000 | 43 263 | 20 991 / 3535 / 8873 / 6956 / 2888 / 20 | 3027 | 7,0 % | 15 007 | 7969 |

```bash
node --input-type=module-typescript -e '
import { Korpus } from "./src/synth/korpus.ts";
for (const n of [10_000, 100_000, 1_000_000]) {
  const k = new Korpus({ episodes: n, seed: 1 });
  const it = k.episodes();
  while (it.next().done !== true) {}
  console.log(n, JSON.stringify(k.summary()));
}'
```

Sam generator (bez upisa) treba ~1 s i ~140 MB za 1M. Upis istim SQL-om u SQLite
(`node:sqlite`, transakcije po 50 000, 64 MB stranica) izmjeren je u privremenoj datoteci
izvan `.wrangler/`: 100k 1,6 s, 300k 5,6 s (≈ 120 MB baze). Procjena za 1M: 20–40 s upisa i
~400 MB baze; mjerenje na 100k i 1M radi sljedeća sesija.

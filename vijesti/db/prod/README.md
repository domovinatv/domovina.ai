# Shema `vijesti` na produkcijskom Supabaseu (api.domovina.ai)

Paket je pripremljen u S7 i **primijenjen 2026-11-11** (migracije 1–6, `verify.sql`
prolazi; zapis ispod u „Primjena 2026-11-11”). Odluke 730–734 u `docs/decisions.md`.

| Datoteka | Što je |
|---|---|
| `vijesti-install.sql` | Sve migracije `db/migrations/*.up.sql` redom, s knjigovodstvom kao `migrateUp`, u jednoj transakciji. GENERIRANO (`npm run db:bundle`); test pada ako se razlikuje od generiranog. |
| `verify.sql` | Provjera nakon primjene: migracije 1..N, RLS, prava `anon`/`authenticated`, funkcije, „anon ne vidi nacrte”. Samo čita (završava s `ROLLBACK`). |
| `../bundle.ts` | Generator paketa; `--from N` za kasnije migracije. |

Test (`db/bundle.test.ts`, PGlite, bez mreže) dokazuje: paket na praznoj bazi daje
istu shemu kao `migrateUp` (stupci, ograničenja, indeksi, pogledi, funkcije, okidači,
RLS, politike, prava), ne primjenjuje se dvaput, `--from N` traži bazu s točno 1..N-1,
a `verify.sql` prolazi na ispravnoj shemi i hvata pokvarena prava.

## Prije primjene

1. Iz `vijesti/`: `npm ci && npm run check` zeleno (uključuje gornji test).
2. Paket je svjež: `npm run -s db:bundle | diff - db/prod/vijesti-install.sql` ne ispisuje ništa.
3. Pročitaj `vijesti-install.sql` (to je točno ono što ide u bazu). Shema `vijesti`
   ne smije postojati (`\dn vijesti` u psql-u prazno); ako postoji, paket sam stane
   na provjeri stanja i ništa ne primijeni.
4. Ako želiš suhu probu: schema-only dump produkcije u scratch Postgres i primjena tamo
   (`domovina-api/docs/migration-testing-playbook.md`).

## Primjena

Na Coolify hostu Supabase stacka (SSH; kontejner baze nađi s
`docker ps --filter name=supabase-db --format '{{.Names}}'`):

```bash
# s lokalnog stroja, iz vijesti/
ssh <coolify-host> "docker exec -i <supabase-db-kontejner> psql -U postgres -d postgres -v ON_ERROR_STOP=1" \
  < db/prod/vijesti-install.sql
```

Ishod mora završiti s `COMMIT`. Bilo koja greška = cijeli paket poništen (jedna
transakcija). Grešku traži s `grep -oE "ERROR:.*"` (psql ispred nje stavlja
`psql:…:N:`).

## Provjera u bazi

```bash
ssh <coolify-host> "docker exec -i <supabase-db-kontejner> psql -U postgres -d postgres -v ON_ERROR_STOP=1" \
  < db/prod/verify.sql
```

Prolaz: `NOTICE:  vijesti: provjera prošla, migracije {1,2,3,4,5,6}` i exit 0.
Pad: `ERROR:  vijesti: provjera NIJE prošla (N):` s popisom.

## Izlaganje sheme PostgREST-u

Portal čita kroz PostgREST sa zaglavljem `Accept-Profile: vijesti` (pisanje urednika:
`Content-Profile: vijesti`, odluka 603). PostgREST pušta samo sheme iz
`PGRST_DB_SCHEMAS`.

1. Coolify → Supabase servis → Environment: `PGRST_DB_SCHEMAS` dopuni s `vijesti`,
   npr. `public,storage,graphql_public,domovina_ai,vijesti` (postojeće sheme ostaju).
2. **Redeploy** servisa (sama promjena varijable i restart ne prenose novu vrijednost
   u kontejner `rest`).
3. Paket na kraju šalje `NOTIFY pgrst, 'reload schema'`; nakon redeploya PostgREST
   ionako čita shemu iznova.

## Provjera kroz PostgREST (bez pisanja)

`ANON` je javni anon ključ (isti kao u aplikaciji; nije tajna).

```bash
ANON='<anon ključ>'
H=(-H "apikey: $ANON" -H "Authorization: Bearer $ANON")

# 1. Javno čitanje: 200 i [] (još nema objavljenih članaka).
curl -s -w '\n%{http_code}\n' "${H[@]}" -H 'Accept-Profile: vijesti' \
  'https://api.domovina.ai/rest/v1/articles?select=id,slug&limit=1'

# 2. Urednički sloj anonu zatvoren: 401, kod 42501.
curl -s -w '\n%{http_code}\n' "${H[@]}" -H 'Accept-Profile: vijesti' \
  'https://api.domovina.ai/rest/v1/staff?select=user_id&limit=1'

# 3. Urednička funkcija postoji, ali anon je ne smije zvati: 401, kod 42501
#    (PGRST202 = funkcije nema, znači paket nije primijenjen ili shema nije učitana).
curl -s -w '\n%{http_code}\n' "${H[@]}" -H 'Content-Profile: vijesti' -H 'Content-Type: application/json' \
  -X POST -d '{"p_article_id":0,"p_note":null}' 'https://api.domovina.ai/rest/v1/rpc/publish_article'
```

Ako 1. vrati 406 i `PGRST106` („The schema must be one of the following”), shema
nije u `PGRST_DB_SCHEMAS` ili servis nije redeployan.

## Nakon primjene (korisnik)

- **Prvi admin** (uloga u `vijesti.staff`, odluka 503). Kao `postgres`:
  ```sql
  SELECT id, email FROM auth.users WHERE email = '<e-pošta urednika>';
  INSERT INTO vijesti.staff (user_id, role) VALUES ('<id iz upita>', 'admin');
  ```
  Ostale urednike i popis dopuštenih kanala admin dodaje u `/vijesti/admin`.
- **Prijava u admin**: `https://domovina.ai/vijesti/admin` dodaj u GoTrue
  `ADDITIONAL_REDIRECT_URLS` (u kontejneru `GOTRUE_URI_ALLOW_LIST`), pa Redeploy.
- **Portal**: javni anon ključ u `portal/wrangler.jsonc` `vars.VIJESTI_ANON_KEY`
  (i podaci izdavača, odluka 710), pa `npm run portal:release-check`.
- **Engine** u produkciji piše kao vlasnik sheme ili `service_role` (RLS ga ne
  ograničava, odluka 516). Adapter za pravi Postgres (`db/sql.ts`) još nije napravljen.

## Kasnije migracije

Nova migracija `007_…` ide u `db/migrations/`, pa:

```bash
npm run db:bundle -- --from 7 --out db/prod/vijesti-007.sql
```

Paket od 7 provjerava da baza ima točno 1..6 i staje ako nema. `verify.sql` vrijedi i
dalje (provjerava 1..N bez rupa).

## Povratak (samo dok u shemi nema podataka koje treba čuvati)

```sql
BEGIN;
DROP SCHEMA vijesti CASCADE;
COMMIT;
```

Uloge `anon`, `authenticated` i `service_role` pripadaju Supabaseu i ne diraju se
(odluka 502). Ukloni `vijesti` iz `PGRST_DB_SCHEMAS` i redeployaj.

## Primjena 2026-11-11 (zapis)

- `vijesti-install.sql` kroz `psql` u `supabase-db-*` kontejneru → `COMMIT`; `verify.sql` →
  `provjera prošla, migracije {1,2,3,4,5,6}`.
- **Zamka: `PGRST_DB_SCHEMAS` živi na četiri mjesta.** Coolifyjev env za tu varijablu
  bio je prazan (`coolify-env-get.sh` → `<empty>`), a vrijednost je bila upisana
  doslovno u generirani `docker-compose.yml` na hostu (servisi `supabase-rest` i
  `supabase-studio`) i u host `.env`. Promjena samo kroz Coolify API ili samo u `.env`
  ne bi stigla u kontejner, jer `environment:` u composeu nadjačava `env_file`.
  Promijenjeno je sve četvero: Coolify env (`domovina-api/scripts/coolify-env-set.sh`),
  host `.env`, oba retka u composeu (backup `*.bak-vijesti-<epoch>`) i
  `domovina-api/scripts/build-coolify-env.sh` (`013ce2a`). Nakon toga
  `coolify-restart.sh supabase-rest --recreate`.
- **Neprovjereno:** preživi li `vijesti` puni Coolify redeploy stacka, koji compose
  regenerira iz Coolifyjeva predloška. Nakon prvog takvog redeploya ponovi curl
  provjeru gore. 406 `PGRST106` znači da je shema opet izgubljena.
- `GOTRUE_URI_ALLOW_LIST` već ima `https://domovina.ai/**`, pa admin redirect ne treba posebno.
- Prvi admin: `stepanic.matija@gmail.com`. `allowed_channels`: `catholic_futurist`,
  `domovina_tv`, `iva_kraljevic`, `mreze_rijeci`.

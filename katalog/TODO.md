# TODO — katalog (Worker + D1)

Radna lista. Čuva se u repou da napredak preživi između sesija. Označene stavke su gotove
i provjerene (`npm run check` zelen u `katalog/`). Odluke idu u
[docs/decisions.md](docs/decisions.md).

Plan po sesijama: [docs/plan.md](docs/plan.md). Handoff po sesiji: [docs/handoffs/](docs/handoffs/)
(pravila lanca i stanje u njegovom README-u).

Legenda: `[x]` gotovo · `[ ]` otvoreno · `[~]` u radu · `(!)` traži korisnika · `→ Sn` planirana sesija

## F0 — temelj i mjerenje (ništa javno, ništa na Cloudflare računu)

- [x] `katalog/package.json`, TypeScript strict, eslint, vitest + `@cloudflare/vitest-pool-workers` (lokalni D1), `npm run check` → S1
- [x] `katalog/wrangler.jsonc` bez `routes` i s `workers_dev: false` (ništa se ne deploya) → S1
- [x] Migracije D1: `brands`, `channels`, `episodes`, `ingest_runs`; stupci `brand`, `tier`, `lang`, `published_date` od prvog dana → S1
- [x] Tipovi + parseri za stvarne ulaze: `channels/data/index.json`, `channels/data/<slug>.json`, `data/<id>/info.json` (samo potrebna polja), `data/<id>/summary.json`, `data/<id>/episode.json` → S1
- [x] Fixturei: 3 Tier 1 kanala (skraćeni listinzi), 5 `_unlisted` epizoda iz različitih kanala, isječak registryja → S1
- [x] Uvoznik `katalog import` (lokalni D1): Tier 1 iz listinga, Tier 2 iz `.r2_keys_cache.json` + `info.json`, kanal preko `channel_id` → registry slug → S2
- [x] Idempotentan upsert po YouTube ID-u; drugi uvoz istog ulaza = 0 promjena (test) → S2
- [x] Izvještaj uvoza: epizoda po tieru, epizode bez razriješenog kanala (s razlogom, ne tiho) → S2
- [ ] Registry: 7 YouTube kanala ima samo playliste (TV Jadran, Jutarnji list, HRT vijesti, Anze Tomic, VTV, RTL, NOVA TV), pa 22/253 Tier 2 epizode ostaju bez kanala; dodati `umbrella`/`channel` unos (fetch sesija; odluka 204, `docs/research/2026-11-05-uvoz-tier2.md`) → fetch
- [x] API v1 nad lokalnim D1: `days/:date`, `channels`, `channels/:slug/episodes`, `episodes/:id/card`, `directory` → S3
- [x] Keyset paginacija (cursor), limit stranice, nikad `OFFSET` → S3
- [x] JSON sheme odgovora u `katalog/contract/` + ugovorni testovi → S3
- [x] Cache API + verzija u ključu cachea; purge strategija zapisana → S3
- [ ] Sintetički generator (npr. 50k kanala / 1M epizoda) u lokalnom D1 → S4
- [ ] Mjerenje `rows_read` po ruti (`meta.rows_read`), veličina baze po 100k epizoda, projekcija do limita 10 GB → S4
<!-- doc-refs:ignore-start -->
- [ ] Izvještaj `docs/research/YYYY-MM-DD-f0-mjerenje-lokalno.md` → S4
<!-- doc-refs:ignore-end -->
- [ ] (!) Korisnik odobrava staging na Cloudflare računu (D1 `katalog-staging`, Worker bez produkcijske rute) → S4
- [ ] Staging deploy, uvoz stvarnih podataka, latencija iz HR (p50/p95, hladno/toplo) vs. statični `home.json` → S5
- [ ] (!) Odluka korisnika: idemo u produkciju (F1) ili ne → S5

## F1 — produkcija i Tier 2 u aplikaciji

- [ ] (!) Produkcijski D1 + ruta `domovina.ai/api/katalog/*` (deploy pokreće korisnik ili uz njegov izričit da) → S6
- [ ] `POST /api/katalog/v1/ingest` s tokenom (secret), batch upsert, idempotentno → S6
- [ ] `katalog drift-check`: R2 (`.r2_keys_cache.json`) ↔ D1; exit 0/1/2; Telegram samo kroz `scripts/telegram-notify.rb` → S6
- [ ] launchd tripwire za drift-check (LaunchAgent), tih kad je poravnato → S6
- [ ] Pipeline nakon uploada zove ingest (sesija u `fetch.domovina.tv`) → S7
- [ ] `episode.json` nosi `channel: {slug, name, tier}` (sesija u `fetch.domovina.tv`) → S7
- [ ] `podcast_core`: `Endpoints.catalog` (nullable; bez njega stari statični put), `CatalogClient` → S8
- [ ] Ekran epizode: kanal iz `episodes/:id/card` / `episode.json`; `_QueuedEpisodeScreen` više ne zove `findVideoAsync` kad je katalog dostupan → S8
- [ ] Podcasterium tripwire (`scripts/build-podcasterium-shell.sh`) zelen → S8
- [ ] Rail „Danas u korpusu” + ruta `/dani/:datum` → S9
- [ ] `/dani/` u `web/_worker.js` (OG), AASA components i Android intent filter, sitemap → S9
- [ ] `/channels` filtar „Pratimo / Svi” nad `directory`, paginacija → S10
- [ ] `/c/:slug` za Tier 2 kanal (obrađene epizode iz API-ja); OG u workeru → S10
- [ ] (!) Release: web deploy s `main` + provjera verzije na produkciji, nightly store build → S11

## F2 — katalog računa server

- [ ] (!) Odluka korisnika: smije li Tier 2 u hero (zadano: ne) → S12
- [ ] `GET /home`: hero i railovi na serveru, pravila prenesena iz `HomeFeed.pickFeaturedCarousel` → S12
- [ ] Paritetni test: server vs klijent na 40 simuliranih dana, 40/40 → S12
- [ ] Klijent prelazi na `/home`; `prefetchAll` se gasi kad je katalog dostupan → S12
- [ ] Facete (tier, jezik, datum, kanal, osoba) kroz Meili iza `/search`; `search.json` zamrznut → S13
- [ ] Rangiranje iz ClickHouse signala (slušanost) — istraživanje i dizajn, ne implementacija → S13

## F3 — spremnost za Podcasterium (više brendova, shardovi)

- [ ] Usmjeravanje po brendu: jedna D1 baza po brendu, `brand` iz hosta/ključa → S14
- [ ] Shard po jeziku/zemlji za brend iznad praga; upit preko više shardova samo za liste koje to traže → S14
- [ ] Sintetički test: 500k kanala preko N shardova, `rows_read` po ruti i dalje ograničen veličinom stranice → S14

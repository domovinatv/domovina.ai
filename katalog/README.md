# katalog — servis za isporuku kataloga epizoda

Cloudflare Worker + D1 koji aplikaciji (`packages/podcast_core`) servira katalog
kanala i epizoda kroz paginirani API, umjesto zbirnih JSON datoteka na R2 koje rastu
linearno s korpusom. Datoteke po epizodi (`data/<id>/*`) ostaju na R2 kako jesu.

- Plan: [docs/plan.md](docs/plan.md)
- Radna lista: [TODO.md](TODO.md)
- Odluke: [docs/decisions.md](docs/decisions.md)
- Lanac sesija: [docs/handoffs/README.md](docs/handoffs/README.md)

Provjera: `cd katalog && npm install && npm run check` (tsc + eslint + vitest u
Workers runtimeu s lokalnim D1). Lokalne migracije: `npm run migrate:local`.

Parseri ulaza (`index.json`, listinzi, `data/<id>/*.json`, registry) su u `src/input/`;
fixturei u `test/fixtures/` (stvarni, skraćeni) osvježava `npm run fixtures:refresh`
(Node 24+, čita CDN i `../../fetch.domovina.tv/data/podcasts_registry.json`).

Uvoznik (S2): `npm run migrate:local && npm run import` puni LOKALNI D1 (`.wrangler/`, nije u
gitu) iz CDN-a, key cachea i registryja u `../../fetch.domovina.tv/`; `-- --dry-run` samo
ispiše izvještaj. Pravila: `docs/decisions.md` 200–216.

Sintetički katalog (S4): `npm run synth -- --episodes 100000 --seed 1 --persist
.wrangler/synth-100k` puni ODVOJEN lokalni D1 (nikad `.wrangler/state`) raspodjelom
stvarnog korpusa skaliranom na N (`src/synth/korpus.ts`,
`docs/research/2026-11-06-raspodjela-korpusa.md`); posluži ga `npx wrangler dev --local
--persist-to .wrangler/synth-100k --port 8799`.

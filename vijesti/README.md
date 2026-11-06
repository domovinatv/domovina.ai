# DOMOVINA vijesti

Portal vijesti iz podcasta: iz epizoda koje je pipeline već obradio (`cdn.domovina.ai`)
piše novinarske članke s doslovnim citatima i sekundom uz svaki citat. Urednik ih
odobrava, a objavljuju se na `domovina.ai/vijesti`.

Samostalna aplikacija: vlastiti `package.json`, lockfile i `npm run check`. Ne dira
Flutter aplikaciju ni pipeline.

**Stanje (2026-11-05, S3a):** kostur, CDN loader, fixturei 5 stvarnih epizoda, shema baze
s migracijama, `LlmClient` (Gemini na Vertexu ili AI Studiju + lažni), izvlačenje trenutaka
s provjerom citata (S2) i ocjena vijesti (S3). Pravi model još nije pozvan.

## Pokretanje

```bash
cd vijesti
npm ci
npm run check              # tsc --noEmit + eslint + vitest (bez mreže i bez LLM-a)
npm run fixtures:refresh   # ponovno izvuče fixturee s CDN-a (mreža, nije dio check-a)
npm run cdn:stats -- <id>  # oblik titla i poklapanje words.json za cijelu epizodu (mreža)
npm run vijesti -- extract <id> --fake --db /tmp/v   # trenuci + provjera citata (lažni LLM)
npm run vijesti -- score <id> --fake --db /tmp/v     # ocjena prihvaćenih trenutaka (lažni LLM)
```

Bez `--fake` ide pravi Gemini (zadano Vertex AI s `gcloud` tokenom, vidi `.env.example`)
i troši kvotu; mjerenje ide samo kroz `npm run eval` s procjenom prije pokretanja.

Ključevi idu u `vijesti/.env` (vidi `.env.example`), nikad u git.

## Raspored

- `engine/cdn/`: loader, sheme (zod), SRT parser, spoj SRT + `words.json`, disk cache
  (`.cache/cdn/`)
- `engine/llm/`: `LlmClient`, Gemini klijent (Vertex/Studio), gcloud token, konfiguracija,
  procjena tokena, lažni klijent, brojanje poziva (`runs`)
- `engine/extract/`, `engine/verify/`: trenuci iz titla i provjera citata
- `engine/score/`: ocjena vijesti (novost, govornik, konkretnost), popis osoba
- `engine/test/`: fixturei (`fixtures/README.md`), lažni CDN, setup koji gasi mrežu
- `db/`: migracije (`db/migrations/`), runner, `runs` nad Postgresom (PGlite u testovima)

## Dokumenti

- Plan i arhitektura: [docs/plan.md](docs/plan.md)
- Radna lista: [TODO.md](TODO.md)
- Odluke: [docs/decisions.md](docs/decisions.md)
- Oblik CDN datoteka: [docs/research/2026-11-05-oblik-cdn-datoteka.md](docs/research/2026-11-05-oblik-cdn-datoteka.md)
- Lanac sesija i pravila: [docs/handoffs/README.md](docs/handoffs/README.md)

## Portal (S6)

```bash
npm run portal:dev     # shim (127.0.0.1:8790) + astro dev (127.0.0.1:4321/vijesti), lažna prijava urednika
npm run portal:shim    # samo shim + seed (VIJESTI_SHIM_PORT, zadano 8790)
npm run portal:build   # produkcijski build (VIJESTI_AUTH_MODE=supabase)
npm run portal:check   # astro check
```

Lokalni podaci: `portal/dev/seed.ts` (pet članaka u pet stanja). Admin: `/vijesti/admin`, gumb
„Prijavi se” mintira nepotpisan JWT urednika `11111111-1111-4111-8111-111111111111` (odluka 606).
Shim: `POST /__shim/reset` vraća početni seed.

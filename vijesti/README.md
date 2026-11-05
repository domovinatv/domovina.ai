# DOMOVINA vijesti

Portal vijesti iz podcasta: iz epizoda koje je pipeline već obradio (`cdn.domovina.ai`)
piše novinarske članke s doslovnim citatima i sekundom uz svaki citat. Urednik ih
odobrava, a objavljuju se na `domovina.ai/vijesti`.

Samostalna aplikacija: vlastiti `package.json`, lockfile i `npm run check`. Ne dira
Flutter aplikaciju ni pipeline.

**Stanje (2026-11-05, S1):** kostur, CDN loader, fixturei 5 stvarnih epizoda, shema baze
s migracijama, `LlmClient` (Gemini + lažni). Izvlačenja trenutaka još nema (S2).

## Pokretanje

```bash
cd vijesti
npm ci
npm run check              # tsc --noEmit + eslint + vitest (bez mreže i bez LLM-a)
npm run fixtures:refresh   # ponovno izvuče fixturee s CDN-a (mreža, nije dio check-a)
npm run cdn:stats -- <id>  # oblik titla i poklapanje words.json za cijelu epizodu (mreža)
```

Ključevi idu u `vijesti/.env` (vidi `.env.example`), nikad u git.

## Raspored

- `engine/cdn/`: loader, sheme (zod), SRT parser, spoj SRT + `words.json`, disk cache
  (`.cache/cdn/`)
- `engine/llm/`: `LlmClient`, Gemini klijent, lažni klijent, brojanje poziva (`runs`)
- `engine/test/`: fixturei (`fixtures/README.md`), lažni CDN, setup koji gasi mrežu
- `db/`: migracije (`db/migrations/`), runner, `runs` nad Postgresom (PGlite u testovima)

## Dokumenti

- Plan i arhitektura: [docs/plan.md](docs/plan.md)
- Radna lista: [TODO.md](TODO.md)
- Odluke: [docs/decisions.md](docs/decisions.md)
- Oblik CDN datoteka: [docs/research/2026-11-05-oblik-cdn-datoteka.md](docs/research/2026-11-05-oblik-cdn-datoteka.md)
- Lanac sesija i pravila: [docs/handoffs/README.md](docs/handoffs/README.md)

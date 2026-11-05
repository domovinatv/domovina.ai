# katalog — servis za isporuku kataloga epizoda

Cloudflare Worker + D1 koji aplikaciji (`packages/podcast_core`) servira katalog
kanala i epizoda kroz paginirani API, umjesto zbirnih JSON datoteka na R2 koje rastu
linearno s korpusom. Datoteke po epizodi (`data/<id>/*`) ostaju na R2 kako jesu.

- Plan: [docs/plan.md](docs/plan.md)
- Radna lista: [TODO.md](TODO.md)
- Odluke: [docs/decisions.md](docs/decisions.md)
- Lanac sesija: [docs/handoffs/README.md](docs/handoffs/README.md)

Koda još nema (S0 je samo plan). `npm run check` nastaje u S1.

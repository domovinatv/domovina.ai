# Odluke — portal vijesti

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …), da se
paralelni worktreeji ne sudare. Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-05, planiranje)

1. **Samostalna aplikacija u `vijesti/`**, s vlastitim `package.json`, lockfileom i
   `npm run check`. Ne dira Flutter aplikaciju (`packages/podcast_core/`) ni korijenski
   `package.json`. Iznimka je S7: ruta `/vijesti/*` u `web/_worker.js`.
2. **Pipeline se ne mijenja.** Engine čita CDN samo čitanjem. Ako treba nešto što pipeline
   ne daje, to ide kao zahtjev u `fetch.domovina.tv` (zapis u TODO s `(!)`), ne kao
   zaobilaženje.
3. **Portal je Astro sa server-side renderom na Cloudflare Workers**, ne Flutter (SEO,
   LCP, Google News). Revidira se samo ako S6 izmjeri da Astro ne može dati Lighthouse
   mobile ≥ 90.
4. **Na `domovina.ai/vijesti`, ne na poddomeni** (autoritet domene).
5. **Jedna kanonska stranica po priči i formatu.** Stilovi nisu zasebni URL-ovi.
6. **Testovi nikad ne zovu mrežu ni LLM.** Fixturei i lažni klijent. Pravi pozivi idu samo
   kroz `npm run eval -- --max-calls N`, koji prije pokretanja ispiše procjenu.
7. **Objava ide samo kroz urednika** (Zakon o medijima, AI Act čl. 50(4)). Nema
   automatske objave ni u jednoj fazi.
8. **Samo kanali s popisa dopuštenih.** Popis puni korisnik.

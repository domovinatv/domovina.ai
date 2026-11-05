# Odluke — katalog

Svaka odluka ima broj, datum, razlog i, ako je pretpostavka, uvjet pod kojim se revidira.
Svaka sesija numerira od svog bloka iz [plan.md](plan.md) (S1 od 100, S2 od 200, …), da se
paralelni worktreeji ne sudare. Odluka se ne briše: zamijeni je novom koja je poziva.

## S0 (2026-11-05, planiranje)

1. **Opseg: samo zbirni sloj.** Servis isporučuje popise (kanali, epizode po kanalu, po
   danu, naslovnica, kartica epizode). Datoteke po epizodi (`data/<id>/*`, medija, slike)
   ostaju na R2 i čitaju se kao danas. Razlog: dohvat po ključu već skalira, linearno
   rastu samo zbirne datoteke.
2. **Kod živi u `katalog/` u ovom repou**, s vlastitim `package.json` i `npm run check`
   (uzor `vijesti/`). Razlog: ugovor s `podcast_core` i testovi klijenta su ovdje.
   Revizija: ako Podcasterium treba servis bez DOMOVINA repoa, izdvaja se u zaseban repo.
3. **Cloudflare Worker + D1 + Cache API.** Bez KV-a i Durable Objecta u F0–F1. Razlog:
   pravilo „Backend placement” iz korijenskog `CLAUDE.md` (javno čitanje, bez korisničkih
   podataka i bez service rolea → Worker). Ranija odluka protiv Workera
   (`docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §7) odbacila je Worker koji drži
   JSON u memoriji; ovdje nema parsiranja velikih datoteka, svaki odgovor je indeksirani
   upit za jednu stranicu. Revizija: ako S5 izmjeri latenciju lošiju od statičnog puta.
4. **Shema je spremna za shardove od prvog dana**: stupci `brand`, `lang`, `tier`,
   `published_date`; jedna D1 baza po brendu. D1 baza ima tvrdi limit 10 GB koji se ne
   može povećati, a Cloudflare preporučuje mnogo manjih baza po tenantu. Brend je naš
   tenant.
5. **Statični snapshot ostaje rezerva i ugovor za stare buildove.** `index.json` je Tier 1
   i zamrznutog oblika. Novi podaci idu samo kroz API (ili nove datoteke).
6. **D1 je projekcija.** Upsert je idempotentan po YouTube ID-u (`episodes.id`).
   Konvergencija se mjeri prema R2 (`drift-check`), ne vjeruje se pipeline zastavicama
   (pravilo „pipeline zastavice ≠ stvarnost”).
7. **Ruta je na istom originu**: `domovina.ai/api/katalog/v1/*` (uzor
   `domovina-analytics`, ruta `domovina.ai/api/state`). Bez riječi koje adblockeri
   blokiraju (`analytics`, `track`, `collect`, `event`, `beacon`).
8. **Paginacija je samo keyset.** `OFFSET` je zabranjen. Limit stranice je u ugovoru.
9. **Testovi bez mreže**: vitest + `@cloudflare/vitest-pool-workers` (lokalni D1),
   fixturei iz stvarnih datoteka, `skipped 0`.
10. **Rad na pipelineu ide iz sesije u `fetch.domovina.tv`** (S7), nikad iz ovog repoa.
    Ovaj repo smije čitati fetch repo i CDN.
11. **Hero ostaje samo Tier 1** dok korisnik ne odluči drukčije (vrata u S12). Tier 2 se
    pojavljuje u „Danas u korpusu”, na `/dani/`, `/channels` („Svi”) i na `/c/:slug`.

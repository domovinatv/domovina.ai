# TODO — postavke kanala (vlasnik upravlja kanalom na domovina.ai)

Radna lista. Čuva se u repou da napredak preživi između sesija. Označene stavke su gotove i
provjerene (provjera je navedena u stavci ili u „Gotovo kad” paketa u [docs/plan.md](docs/plan.md)).
Odluke idu u [docs/decisions.md](docs/decisions.md).

Plan po sesijama: [docs/plan.md](docs/plan.md). Handoff po sesiji: [docs/handoffs/](docs/handoffs/).

Legenda: `[x]` gotovo · `[ ]` otvoreno · `[~]` u radu · `(!)` traži korisnika · `→ Sn` planirana sesija

## F0 — mjerenje i matrica provedbe (ništa javno)

- [x] Pokrivenost UC id-a: 182/186 s UC-om, 180 različitih, 1 UC = 3 sluga; bez UC-a `launched`, `subclub` (UC u registryju), `dijalog`, `x-…` → S1, odluke 100–102
- [x] Radi li `youtube-claim` u produkciji: deployan, env postavljen, **0 `verified`** (5 sintetičkih iz 14. 10.); GCP verifikacija nije vidljiva iz CLI-a → S1, odluka 103
- [x] (!) Vrata: prvi stvarni claim (`domovina_tv`, 11. 11.); odluke 108 i 109 potvrđene → S2, odluka 200
- [x] Matrica: 20 prekidača × potrošač (repo, datoteka, funkcija), što „isključeno” znači za NOVE i za POSTOJEĆE epizode, latencija → S1, `research/2026-11-11-matrica-provedbe.md`, odluke 105–110
- [x] Popis svega što trajno brisanje mora počistiti (R2 prefiksi, obje `Vary: Origin` varijante, Meili indeksi, RAG tablice, vijesti, push teme, katalog D1, registry) s naredbom koja broji objekte po kanalu → S1, `research/2026-11-11-popis-brisanja.md` (`ikra_institut`: 1 385 R2 objekata), odluka 111

## F1 — izvor istine (domovina-api)

- [x] Novac u SQL-u: `donations` i `paid_sponsor_moments` u pinka/sponzorskim funkcijama i `public_live_moments` → S2 (odluka 109)

- [x] Migracija: `channel_settings` (trenutno stanje), `channel_settings_events` (append-only, trigger zabranjuje UPDATE/DELETE), `channel_deletion_requests`, `channel_tombstones` → S2
- [x] RPC `set_channel_setting(uc, key, value)`: pišu `primary` i `collaborator` sa `status='verified'` i `verified_at` mlađim od 90 dana; događaj i stanje u istoj transakciji → S2
- [x] RPC `request_channel_deletion` / `cancel_channel_deletion` (vlasnik) i `confirm_channel_deletion_by_phone` (samo service_role, operater nakon poziva) → S2
- [x] RLS testovi lokalno (anon čita stanje i tombstone, log čita samo vlasnik tog kanala, nitko ne mijenja log) → S2, `domovina-api` `7d01d49`, 120 provjera
- [x] (!) Produkcijska migracija: primijenjena pojedinačno 11. 11. uz puni backup (ne `db-migrate.sh`, odluka 300) → vrata nakon S2

## F2 — projekcija i API (katalog)

- [x] D1 migracija: `channel_settings` projekcija + `channel_tombstones` (trajno) → S3, `katalog/migrations/0005`
- [x] Poller: povlači promjene iz domovina-api po `updated_at` kursoru, idempotentan → S3 (odluke 302–306)
- [x] API: `settings` uz svaki kanal; master-isključen kanal i njegove epizode izostaju iz popisa (`/channels`, `/home`, `/dani`, Tier 2); `GET /v1/channels/:slug` vraća stanje `withdrawn` ili `deleted` umjesto 404 → S3
- [x] `GET /v1/settings` + Cron Trigger poller + UC iz registryja za `launched`/`subclub` → S3 (odluke 101, 105, 106)
- [x] `drift-check` uspoređuje postavke domovina-api ↔ D1 → S3 (odluka 315)
- [x] (!) Deploy katalog Workera s novom migracijom (11. 11., verzija `5f5966f7`, korisnik odobrio) → vrata nakon S3
- [x] (!) `channel-slugs-sync --commit --confirm-production`: 183 sluga upisano 12. 11., razlika 0 → S4, odluka 409

## F3 — aplikacija

- [x] `ChannelSettingsService` + model (20 ključeva, zadano sve uključeno, nepoznat ključ = uključen) → S4
- [x] Ekran `/account/channels/:ucId/postavke`: glavni prekidač + 19 u 4 skupine, kronološki log promjena, zahtjev za trajno brisanje s potvrdom i telefonom +385 98 967 9022 → S4
- [x] ARB HR + EN, „ti”, bez emojija, lektor → S4 (`9ed0a41`, 95 ključeva `channelSettings*`)
- [ ] Provedba na ekranima: kanal, epizoda (oba prikaza), naslovnica, pretraga, osobe, TV; „Vlasnik je isključio procjenu” umjesto Magisterium ocjene; CDN reprodukcija isključena → `InAppYouTubePlayer` → S5
- [ ] Ekran „Vlasnik je povukao sadržaj” (+ YouTube poveznica) i „Kanal je trajno uklonjen dd. mm. gggg.” → S5
- [ ] Worker: OG/JSON-LD za povučen i obrisan kanal, `noindex`, sitemap bez njih → S6

## F4 — ostali potrošači

- [ ] Pipeline (`fetch.domovina.tv`): ne obrađuje nove epizode kad je obrada ili master isključen; preskače generiranje isključenih AI artefakata; tombstone UC nikad se ne vraća kroz otkrivanje (Tier 2) → S7 (radi se iz fetch repoa)
- [ ] Meili (`episodes`, `segments`) i semantika/RAG (`domovina-rag`): filtar po postavkama → S8
- [ ] Push (`domovina-push`): ne šalje za isključen kanal → S8
- [ ] `domovina-cutter` i `/api/search` `purpose` → S8; KORAK 13, Vertex, WhatsApp skripta, glasački bazen → S7; `og:video`, Cast receiver → S6 (odluka 110)
- [ ] (!) Vijesti (`vijesti/`, drugi lanac): ugovor kako engine čita postavke; izvedba ide u lancu vijesti → S8 (dogovor)

## F5 — trajno brisanje i objava

- [ ] `scripts/channel-delete.sh <UC>`: `--dry-run` zadano, broji i popisuje; `--execute` samo uz potvrđen poziv u bazi; piše tombstone na kraju → S9
- [ ] Proba brisanja na sintetičkom testnom kanalu (testni prefiks na R2, testni Meili dokument) → S9
- [ ] Pravni tekst: uvjeti korištenja (postupak povlačenja i brisanja, telefon), `docs/compliance/data-protection.md` (nova obrada: log promjena s ID-em računa) → S10
- [ ] (!) Release: web deploy s `main`, store build kroz nightly, smoke vrata → S10

# TODO — postavke kanala (vlasnik upravlja kanalom na domovina.ai)

Radna lista. Čuva se u repou da napredak preživi između sesija. Označene stavke su gotove i
provjerene (provjera je navedena u stavci ili u „Gotovo kad” paketa u [docs/plan.md](docs/plan.md)).
Odluke idu u [docs/decisions.md](docs/decisions.md).

Plan po sesijama: [docs/plan.md](docs/plan.md). Handoff po sesiji: [docs/handoffs/](docs/handoffs/).

Legenda: `[x]` gotovo · `[ ]` otvoreno · `[~]` u radu · `(!)` traži korisnika · `→ Sn` planirana sesija

## F0 — mjerenje i matrica provedbe (ništa javno)

- [ ] Pokrivenost UC id-a: koliko kanala u katalogu ima `youtube_channel_id`, koliko je NULL, koliko slugova dijeli isti UC (playliste) → S1
- [ ] Radi li `youtube-claim` u produkciji od početka do kraja: broj `verified` redaka u `domovina_ai.channel_claims`, stanje GCP projekta `domovina-creators` i Google verifikacije `youtube.readonly` → S1 (!)
- [ ] Matrica: 20 prekidača × potrošač (repo, datoteka, funkcija), što „isključeno” znači za NOVE i za POSTOJEĆE epizode, latencija → S1, matrica u `postavke-kanala/docs/research/`
- [ ] Popis svega što trajno brisanje mora počistiti (R2 prefiksi, obje `Vary: Origin` varijante, Meili indeksi, RAG tablice, vijesti, push teme, katalog D1, registry) s naredbom koja broji objekte po kanalu → S1

## F1 — izvor istine (domovina-api)

- [ ] Migracija: `channel_settings` (trenutno stanje), `channel_settings_events` (append-only, trigger zabranjuje UPDATE/DELETE), `channel_deletion_requests`, `channel_tombstones` → S2
- [ ] RPC `set_channel_setting(uc, key, value)`: pišu `primary` i `collaborator` sa `status='verified'` i `verified_at` mlađim od 90 dana; događaj i stanje u istoj transakciji → S2
- [ ] RPC `request_channel_deletion` / `cancel_channel_deletion` (vlasnik) i `confirm_channel_deletion_by_phone` (samo service_role, operater nakon poziva) → S2
- [ ] RLS testovi lokalno (anon čita stanje i tombstone, log čita samo vlasnik tog kanala, nitko ne mijenja log) → S2
- [ ] (!) Produkcijska migracija (`db-migrate.sh` iz domovina-api s backupom) → vrata nakon S2

## F2 — projekcija i API (katalog)

- [ ] D1 migracija: `channel_settings` projekcija + `channel_tombstones` (trajno) → S3
- [ ] Poller: povlači promjene iz domovina-api po `updated_at` kursoru, idempotentan → S3
- [ ] API: `settings` uz svaki kanal; master-isključen kanal i njegove epizode izostaju iz popisa (`/channels`, `/home`, `/dani`, Tier 2); `GET /v1/channels/:slug` vraća stanje `withdrawn` ili `deleted` umjesto 404 → S3
- [ ] `drift-check` uspoređuje postavke domovina-api ↔ D1 → S3
- [ ] (!) Deploy katalog Workera s novom migracijom → vrata nakon S3

## F3 — aplikacija

- [ ] `ChannelSettingsService` + model (20 ključeva, zadano sve uključeno, nepoznat ključ = uključen) → S4
- [ ] Ekran `/account/channels/:ucId/postavke`: glavni prekidač + 19 u 4 skupine, kronološki log promjena, zahtjev za trajno brisanje s potvrdom i telefonom +385 98 967 9022 → S4
- [ ] ARB HR + EN, „ti”, bez emojija, lektor → S4
- [ ] Provedba na ekranima: kanal, epizoda (oba prikaza), naslovnica, pretraga, osobe, TV; „Vlasnik je isključio procjenu” umjesto Magisterium ocjene; CDN reprodukcija isključena → `InAppYouTubePlayer` → S5
- [ ] Ekran „Vlasnik je povukao sadržaj” (+ YouTube poveznica) i „Kanal je trajno uklonjen dd. mm. gggg.” → S5
- [ ] Worker: OG/JSON-LD za povučen i obrisan kanal, `noindex`, sitemap bez njih → S6

## F4 — ostali potrošači

- [ ] Pipeline (`fetch.domovina.tv`): ne obrađuje nove epizode kad je obrada ili master isključen; preskače generiranje isključenih AI artefakata; tombstone UC nikad se ne vraća kroz otkrivanje (Tier 2) → S7 (radi se iz fetch repoa)
- [ ] Meili (`episodes`, `segments`) i semantika/RAG (`domovina-rag`): filtar po postavkama → S8
- [ ] Push (`domovina-push`): ne šalje za isključen kanal → S8
- [ ] (!) Vijesti (`vijesti/`, drugi lanac): ugovor kako engine čita postavke; izvedba ide u lancu vijesti → S8 (dogovor)

## F5 — trajno brisanje i objava

- [ ] `scripts/channel-delete.sh <UC>`: `--dry-run` zadano, broji i popisuje; `--execute` samo uz potvrđen poziv u bazi; piše tombstone na kraju → S9
- [ ] Proba brisanja na sintetičkom testnom kanalu (testni prefiks na R2, testni Meili dokument) → S9
- [ ] Pravni tekst: uvjeti korištenja (postupak povlačenja i brisanja, telefon), `docs/compliance/data-protection.md` (nova obrada: log promjena s ID-em računa) → S10
- [ ] (!) Release: web deploy s `main`, store build kroz nightly, smoke vrata → S10

# Handoffi za sesije S1–S14

Plan je u [../plan.md](../plan.md). Svaka sesija ima svoj handoff `SN.md`, koji je
ujedno prompt za tu sesiju. Korisnik nakon `/clear` kaže „nastavi katalog” (ili „nastavi
zadnji handoff”) ili zalijepi prompt iz clipboarda.

## Lanac

1. Sesija N počinje iz `katalog/docs/handoffs/SN.md`.
2. Sesija N radi svoj paket po pravilima ispod.
3. Na kraju sesija N:
   - označi `SN` kao gotov u tablici „Stanje lanca” ispod (commit, testovi, napomena);
   - označi gotove stavke u `katalog/TODO.md`;
   - **ako je naučila nešto što mijenja neki od sljedećih paketa, uredi `S(N+1).md`**, a po
     potrebi i kasnije handoffe i plan. Nedovršeni dio paketa N ide na **vrh** `S(N+1).md`;
   - u `S(N+1).md` upiše polazni commit i brojke (`npm run check`: broj testova, skipped);
   - pozove `/wrap-up`. Handoff prompt za clipboard i `~/.claude/handoffs/domovina.ai/`
     (tema `katalog-SN+1`) je **sadržaj `katalog/docs/handoffs/S(N+1).md`**.
4. Ako sesija ostane bez konteksta usred paketa, nastavak je opet `SN` s popisom onoga što
   je ostalo na vrhu datoteke. Broj se ne povećava.
5. **Ljudska vrata** (S4, S5, S6, S11, S12): sesija pripremi sve što može, zapiše na vrh
   `S(N+1).md` točno što korisnik treba odlučiti ili napraviti, i lanac staje. Sljedeća
   sesija na početku provjeri je li odluka donesena. Ako nije, ne radi ništa i to javi.
6. **S7 se radi iz `fetch.domovina.tv`** (pravilo: pipeline posao samo iz fetch sesije).
   S6 na kraju korisniku kaže da S7 pokrene u tom repou; S7 na kraju ažurira lanac
   ovdje (commit u ovom repou, samo `katalog/docs/` i `katalog/TODO.md`).

Handoff se mijenja samo prema naprijed: gotovi `SN` se ne prepisuju, služe kao povijest.

## Stanje lanca

| Sesija | Paket | Stanje | Commit | Testovi | Napomena |
|---|---|---|---|---|---|
| S0 | Plan, TODO, handoffi | gotovo | 5c44d7d | — | 2026-11-05; odluke 1–11 |
| S1 | Kostur, migracije, parseri, fixturei | gotovo | ac07618 | 134 / skipped 0 | 2026-11-05; odluke 100–123; `02a43d7` kostur + shema |
| S2 | Uvoznik Tier 1 + Tier 2 | gotovo | 277d704 | 174 / skipped 0 | 2026-11-05; odluke 200–216; `e367767` uvoznik; D1: 3412 + 253 |
| S3 | API v1 + ugovor + cache | gotovo | 9806bb6 | 269 / skipped 0 | 2026-11-05; odluke 300–314; `d67b17e` API; varijante skrivene (`variant_of`, 0003); `wrangler dev` popravljen |
| S4 | Sintetička skala + izvještaj | gotovo | be80dc3 | 289 / skipped 0 | 2026-11-06; odluke 400–409; 500 omotan; `rows_read` isti na 10k/100k/1M; 411 B/epizodi; **vrata: staging čeka korisnika** |
| S5 | Staging + latencija | gotovo | 371fa09 | 289 / skipped 0 | 2026-11-06; odluke 500–506; hit 51 ms (D1 kontekst +32 ms) → 502; **vrata: produkcija čeka korisnika** |
| S6 | Produkcija, ingest, drift-check | gotovo | b1aaeba | 379 / skipped 0 | 2026-11-06; odluke 600–611; produkcija `domovina.ai/api/katalog/*`, 3670 epizoda kroz `--sync`; hit 22 ms / miss 48 ms; launchd 08:45 |
| S7 | Pipeline producer | | | | u `fetch.domovina.tv` |
| S8 | `CatalogClient`, ekran epizode | | | | |
| S9 | „Danas u korpusu” + `/dani/` | | | | paralelno sa S10 |
| S10 | `/channels` „Svi” + Tier 2 kanal | | | | paralelno sa S9 |
| S11 | Release | | | | vrata: korisnik |
| S12 | `/home` na serveru | | | | vrata: Tier 2 u heru |
| S13 | Facete (Meili) + dizajn rangiranja | | | | |
| S14 | Brendovi i shardovi | | | | |

## Zajednička pravila (vrijede u svakoj sesiji)

- **Polazak:** `cd katalog && npm ci && npm run check` i potvrda u jednoj rečenici da je
  zeleno (S1 to tek stvara). Sesije koje diraju Flutter (S8–S12): i
  `cd packages/podcast_core && flutter test` prema `.nightly/test-baseline.txt`. Ako nije
  zeleno, prvo to popravi.
- **Opseg:** servis živi u `katalog/`. Izvan njega se dira samo ono što paket izričito
  navodi: S8–S12 `packages/podcast_core/` (+ ARB i `flutter gen-l10n`), S9–S10
  `web/_worker.js`, `scripts/test-social-tags.mjs`, AASA u workeru i
  `android/app/src/main/AndroidManifest.xml`. Korijenski `package.json` se ne dira.
- **Tvrdi uvjeti iz plana** (stari buildovi, `rows_read` po stranici, rad bez servisa)
  provjeravaju se u svakoj sesiji koja dira API ili klijent.
- **Orkestracija:** posao rade Opus 5.5 subagenti (`model: "opus"`), glavna sesija
  orkestrira. Paket razbij na dva agenta: (a) implementacija, (b) testovi i spajanje.
  `effort` uvijek eksplicitno (`high` za kod, `medium` za čitanje). Najviše 2–3 agenta
  paralelno. Agent koji stane commita i ostavi popis; nastavak ide kroz novog agenta kojem
  se da hash commita. Fable samo uz korisnikov pristanak (globalni CLAUDE.md, token budget).
- **Agentima zabrani** `katalog/TODO.md`, `katalog/docs/plan.md` i handoffe. Orkestrator
  ih ažurira nakon mergea.
- **Paralelno** (S9 ‖ S10) u zasebnim worktreejima (`isolation: "worktree"`), odluke po
  blokovima iz plana.
- **Testovi:** bez mreže, bez Cloudflare računa (lokalni D1 kroz vitest pool), bez tiho
  preskočenih testova (`skipped 0`). Fixturei su skraćeni stvarni podaci, ne izmišljeni.
- **Trošak:** nema LLM-a u ovom lancu. Bilo kakva petlja nad stvarnim CDN-om ili D1 iznad
  ~10 000 zahtjeva: procjena korisniku prije pokretanja. Nikad petlja `claude -p`.
- **Brojke:** svaka brojka u dokumentu ima naredbu koja je reproducira (korijenski
  `CLAUDE.md`). Prije preuzimanja tuđeg dokumenta `./scripts/verify-doc-refs.sh`.
- **Javni repo.** Tokeni i ID-evi računa samo u `katalog/.dev.vars` / `wrangler secret`
  (u `.gitignore`). Ništa pregovaračko.
- **Cloudflare račun:** sve što stvara ili mijenja resurse (D1, Worker, ruta, secret,
  purge) je vanjska radnja. Lokalno (`wrangler dev`, `--local`) je slobodno; na računu
  samo uz vrata. Produkcija ide SAMO s `main` (pravilo deploya iz korijenskog `CLAUDE.md`).
- **Telegram** samo kroz `scripts/telegram-notify.rb`. launchd job je LaunchAgent.
- **Autonomno:** ne pitaj korisnika osim na vratima i za trošak; odluči sam i zapiši
  odluku. Svaki zeleni korak commitaj na `main` s trailerom iz korijenskog `CLAUDE.md`.
- **Token budget:** bez Monitora koji javlja napredak. Duge jobove pokreni s
  `run_in_background` i javi se tek na kraju. Oko 150k konteksta orkestratora zatvori
  sesiju po koraku 3 lanca.
- Svako istraživanje zapiši u `katalog/docs/research/YYYY-MM-DD-*.md`.
- **Paralelni lanac u istom repou** (dogovor s lancem `vijesti/`, 05.11.2026.; ekvivalent
  stoji u `vijesti/docs/handoffs/README.md`):
  1. katalog dira samo `katalog/`, vijesti samo `vijesti/`; korijen ni jedan bez dogovora
     (iznimke koje paket izričito navodi, gore pod „Opseg”, javljaju se drugoj sesiji prije
     prve izmjene);
  2. commit samo po svojim putanjama (`git commit -m … -- katalog/`) ili uz provjeru
     `git diff --cached --name-only`; nikad `git add -A`, `git commit -a`, `stash`, `reset`
     ni `checkout`/`restore` nad tuđim datotekama;
  3. `git pull --rebase` i push samo kad su vlastite putanje čiste; tuđe necommitane
     izmjene se ne diraju;
  4. greška u zajedničkoj datoteci ili u drugom lancu → prvo `SendMessage` drugoj sesiji,
     tek onda izmjena;
  5. ovo pravilo se prepisuje u brief svakog subagenta;
  6. `/wrap-up` commita i pusha samo svoje putanje.

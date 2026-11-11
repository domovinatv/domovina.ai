# Handoffi za sesije S1–S10

Plan je u [plan](../plan.md). Svaka sesija ima svoj handoff `SN.md`, koji je ujedno
prompt za tu sesiju. Korisnik nakon `/clear` kaže „nastavi postavke kanala” (ili „nastavi
zadnji handoff”) ili zalijepi prompt iz clipboarda.

## Lanac

1. Sesija N počinje iz `postavke-kanala/docs/handoffs/SN.md`.
2. Sesija N radi svoj paket po pravilima ispod.
3. Na kraju sesija N:
   - označi `SN` kao gotov u tablici „Stanje lanca” (commit, testovi, napomena);
   - označi gotove stavke u `postavke-kanala/TODO.md`;
   - **ako je naučila nešto što mijenja neki od sljedećih paketa, uredi `S(N+1).md`**, a po
     potrebi i kasnije handoffe i plan. Nedovršeni dio paketa N ide na **vrh** `S(N+1).md`;
   - u `S(N+1).md` upiše polazni commit i brojke testova;
   - pozove `/wrap-up`. Handoff prompt (clipboard i `~/.claude/handoffs/domovina.ai/`, tema
     `postavke-kanala-SN+1`) je **sadržaj `S(N+1).md`**.
4. Bez konteksta usred paketa: nastavak je opet `SN` s popisom ostatka na vrhu. Broj se ne
   povećava.
5. **Ljudska vrata** (S1 uvjetno, S2, S3, S8, S9, S10): sesija pripremi sve, zapiše na vrh
   `S(N+1).md` točno što korisnik treba odlučiti ili napraviti, i lanac staje. Sljedeća
   sesija prvo provjeri je li odluka donesena; ako nije, ne radi ništa i to javi.
6. **Rad u drugom repou** (S2 `domovina-api`, S7 `fetch.domovina.tv`, S8 `domovina-rag` i
   `domovina-push`): sesija se pokreće u tom repou, a na kraju ažurira lanac ovdje (commit u
   ovom repou samo nad `postavke-kanala/`).

Handoff se mijenja samo prema naprijed: gotovi `SN` se ne prepisuju.

## Stanje lanca

| Sesija | Paket | Stanje | Commit | Testovi | Napomena |
|---|---|---|---|---|---|
| S0 | Plan, TODO, handoffi | gotovo | (upisuje S0) | — | 2026-11-11; odluke 1–10 |
| S1 | Mjerenje + matrica provedbe | | | | vrata ako claim u produkciji ne radi |
| S2 | domovina-api shema + RPC | | | | vrata: produkcijska migracija |
| S3 | katalog projekcija + API | | | | vrata: deploy |
| S4 | Ekran postavki + log + zahtjev za brisanje | | | | |
| S5 | Provedba na ekranima | | | | |
| S6 | Worker OG/noindex/sitemap | | | | ‖ S7 |
| S7 | Pipeline (fetch repo) | | | | ‖ S6 |
| S8 | Meili, RAG, push, ugovor vijesti | | | | vrata: dogovor s lancem vijesti |
| S9 | Skripta trajnog brisanja | | | | vrata: prvo stvarno brisanje |
| S10 | Pravni tekstovi + release | | | | vrata: release |

## Zajednička pravila (vrijede u svakoj sesiji)

- **Polazak:** sesije koje diraju Flutter: `cd packages/podcast_core && flutter test` prema
  `.nightly/test-baseline.txt` i `flutter analyze` iz korijena. Katalog: `cd katalog && npm
  run check`. Drugi repo: njegova provjera iz `CLAUDE.md` tog repoa. Ako nije zeleno, prvo
  popravi ili zapiši zašto nije tvoje.
- **Opseg:** samo putanje koje paket navodi. Tvrdi uvjeti iz [plan](../plan.md)
  provjeravaju se u svakoj sesiji.
- **Orkestracija:** posao rade Opus 5.5 subagenti (`model: "opus"`), glavna sesija
  orkestrira. Paket razbij na (a) implementaciju i (b) testove i spajanje. `effort` uvijek
  eksplicitno (`high` za kod, `medium` za čitanje). Najviše 2–3 agenta paralelno. Fable samo
  uz korisnikov pristanak (globalni `CLAUDE.md`, token budget).
- **Agentima zabrani** `postavke-kanala/TODO.md`, plan lanca i handoffe; ažurira ih
  orkestrator.
- **Testovi:** bez mreže, `skipped 0` (Flutter prema baselineu). SQL testovi na lokalnom
  Supabase stacku (`domovina-api`, Kong 55321, DB 55322), nikad na produkciji.
- **Vanjske radnje su vrata:** produkcijska migracija, Cloudflare deploy/secret/purge,
  brisanje na R2/Meili/RAG, store promocija, objava pravnih tekstova. Lokalno je slobodno.
  Web produkcija ide SAMO s `main` i provjerava se verzijom, ne statusom (korijenski
  `CLAUDE.md`, „Build & Deploy”).
- **Trošak:** nema LLM-a u ovom lancu. Petlja nad stvarnim CDN-om iznad ~10 000 zahtjeva:
  procjena korisniku prije pokretanja. Nikad `claude -p` petlja.
- **Brojke:** svaka brojka u dokumentu ima naredbu koja je reproducira. Prije preuzimanja
  dokumenta `./scripts/verify-doc-refs.sh`.
- **Javni repo:** tajne samo u `.env` / `.dev.vars` / Coolify / `wrangler secret`. Telefon
  +385 98 967 9022 je namjerno javan (odluka 5).
- **Pravila aplikacije** (korijenski `CLAUDE.md`): ARB HR prvo pa EN pa `flutter gen-l10n`
  u `packages/podcast_core/`; „ti”; bez emojija; `AppLocalizations.of(context)` za sve što se
  trajno crta; nova ruta ide kroz `nav.dart` helpere; nova kontrola playera na tri mjesta.
- **Paralelni lanci u istom repou** (`katalog/`, `vijesti/`): commit samo po svojim
  putanjama (`git commit -m … -- <putanje>` ili provjera `git diff --cached --name-only`);
  nikad `git add -A`, `commit -a`, `stash`, `reset` ni `checkout`/`restore` nad tuđim
  datotekama; `git pull --rebase` i push samo kad su vlastite putanje čiste. U `katalog/` se
  dira kod samo kad katalog nema necommitanih izmjena. Pravilo se prepisuje u brief svakog
  subagenta; `/wrap-up` commita samo svoje putanje.
- **Autonomno:** ne pitaj osim na vratima; odluči i zapiši odluku. Svaki zeleni korak
  commitaj na `main` s trailerom iz korijenskog `CLAUDE.md`. Web izmjena koja je gotova ide
  u deploy po pravilu iz memorije („deploy nakon svake izmjene”) tek kad je backend koji
  čita već na produkciji; inače čeka vrata.
- **Token budget:** bez Monitora koji javlja napredak; oko 150k konteksta zatvori sesiju po
  koraku 3 lanca.
- Svako istraživanje u `postavke-kanala/docs/research/YYYY-MM-DD-*.md`.

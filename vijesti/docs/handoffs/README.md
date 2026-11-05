# Handoffi za sesije S1–S13

Plan je u [../plan.md](../plan.md). Svaka sesija ima svoj handoff `SN.md`, koji je
ujedno prompt za tu sesiju. Korisnik nakon `/clear` kaže „nastavi zadnji handoff” ili
zalijepi prompt iz clipboarda.

## Lanac

1. Sesija N počinje iz `vijesti/docs/handoffs/SN.md`.
2. Sesija N radi svoj paket po pravilima ispod.
3. Na kraju sesija N:
   - označi `SN` kao gotov u tablici „Stanje lanca” ispod (commit, testovi, napomena);
   - označi gotove stavke u `vijesti/TODO.md`;
   - **ako je naučila nešto što mijenja neki od sljedećih paketa, uredi `S(N+1).md`**, a po
     potrebi i kasnije handoffe i plan. Primjeri: CDN datoteka ne izgleda kako je
     pretpostavljeno, paket je ispao veći ili manji, mjerenje je promijenilo smjer.
     Nedovršeni dio paketa N ide na **vrh** `S(N+1).md`;
   - u `S(N+1).md` upiše polazni commit i brojke (`npm run check`: broj testova, skipped);
   - pozove `/wrap-up`. Handoff prompt za clipboard i `~/.claude/handoffs/domovina.ai/`
     (ime datoteke s temom `vijesti-SN+1`) je **sadržaj `vijesti/docs/handoffs/S(N+1).md`**.
4. Ako sesija ostane bez konteksta usred paketa, nastavak je opet `SN` s popisom onoga što
   je ostalo na vrhu datoteke. Broj se ne povećava.
5. **Ljudska vrata** (S3, S7, S8): sesija pripremi sve što može, zapiše u `S(N+1).md`
   točno što korisnik treba odlučiti ili napraviti, i lanac staje. Sljedeća sesija na
   početku provjeri je li odluka donesena. Ako nije, ne radi ništa i to javi.

Handoff se mijenja samo prema naprijed: gotovi `SN` se ne prepisuju, služe kao povijest.

## Stanje lanca

| Sesija | Paket | Stanje | Commit | Testovi | Napomena |
|---|---|---|---|---|---|
| S0 | Plan, TODO, handoffi | gotovo | 5e5c652 | — | 2026-11-05; odluke 1–8 |
| S1 | Kostur, loader, shema, LlmClient | gotovo | 4b9f74d | 86 / skipped 0 | 2026-11-05; odluke 100–117; offline check zelen (sandbox-exec) |
| S2 | Trenuci + provjera citata | gotovo | 336426f | 167 / skipped 0 | 2026-11-05; odluke 200–214; 843 napada odbijena, mjerenje u research/2026-11-05-provjera-citata.md |
| S3 | Ocjena vijesti + mjerenje | otvoreno | | | vrata: korisnik |
| S4 | Format „vijest” + verify | | | | |
| S5 | Urednički tok + API | | | | |
| S6 | Portal (Astro) + admin | | | | |
| S7 | Distribucija + pravni sloj + Preview | | | | vrata: korisnik |
| S8 | Dnevni job + prvih 30 članaka | | | | vrata: korisnik |
| S9 | Priče kroz više podcasta | | | | može paralelno sa S10 |
| S10 | Teme, osobe, pretraga, push | | | | može paralelno sa S9 |
| S11 | Formati, stilovi, duplikati | | | | |
| S12 | EN izdanje, newsletter | | | | |
| S13 | Brzina, pristanak kreatora | | | | |

## Zajednička pravila (vrijede u svakoj sesiji)

- **Polazak:** `cd vijesti && npm ci && npm run check` i potvrda u jednoj rečenici da je
  zeleno (S1 to tek stvara). Ako nije zeleno, prvo to popravi.
- **Opseg:** sve živi u `vijesti/`. Izvan njega se dira samo ono što paket izričito
  navodi (S7: `web/_worker.js`, `scripts/test-social-tags.mjs`). Flutter aplikacija,
  `packages/podcast_core/` i korijenski `package.json` se ne diraju.
- **Paralelni lanac u istom repou** (od 2026-11-05): lanac „katalog” (`katalog/`,
  `katalog/docs/handoffs/`) radi druga Claude sesija na istoj grani `main`, u istom
  radnom stablu. Pravila za oba lanca:
  - vijesti dira samo `vijesti/` (plus izričite iznimke paketa), katalog samo `katalog/`;
    korijenske datoteke ni jedan lanac ne dira bez dogovora;
  - commit samo po svojim putanjama (`git commit -m … -- vijesti/`) ili uz provjeru
    `git diff --cached --name-only` prije commita; nikad `git add -A`, `git commit -a`,
    `git stash`, `git reset`, `git checkout`/`restore` nad tuđim datotekama;
  - `git pull --rebase` i push samo kad su vlastite putanje čiste; tuđe necommitane
    izmjene u stablu su normalne i ne diraju se;
  - greška nađena u zajedničkoj datoteci ili u drugom lancu: javi drugoj sesiji
    (`ListAgents` + `SendMessage`) prije nego je diraš;
  - isto pravilo vrijedi za subagente: orkestrator ga prepiše u svaki brief;
  - `/wrap-up` commita i pusha samo vijesti/ putanje.
- **Pipeline se ne mijenja** (odluka 2). Rad na `fetch.domovina.tv` je izvan lanca.
- **Orkestracija:** posao rade Opus 5.5 subagenti (`model: "opus"`), glavna sesija
  orkestrira. Paket razbij na dva agenta: (a) implementacija, (b) testovi i spajanje.
  `effort` uvijek eksplicitno (`high` za kod, `medium` za čitanje). Agent koji stane
  commita i ostavi popis; nastavak ide kroz novog agenta kojem se da hash commita.
  Fable samo uz korisnikov pristanak (globalni CLAUDE.md, token budget).
- **Agentima zabrani** `vijesti/TODO.md`, `vijesti/docs/plan.md` i handoffe. Orkestrator
  ih ažurira nakon mergea.
- **Paralelno** (S9 ‖ S10) u zasebnim worktreejima (`isolation: "worktree"`), odluke po
  blokovima iz plana.
- **Testovi:** bez mreže i bez LLM-a (odluka 6), bez tiho preskočenih testova
  (`skipped 0`). Svaki prompt ima test nad lažnim klijentom koji provjerava da se izlaz
  validira JSON shemom.
- **Pravi LLM pozivi** samo kroz `npm run eval -- --max-calls N`. Prije svakog pokretanja
  iznad ~100 poziva: procjena (poziva × tokena × cijena) korisniku i čekanje na da.
  Nikad petlja `claude -p`.
- **Brojke:** svaka brojka u dokumentu ima naredbu koja je reproducira (pravilo iz
  korijenskog `CLAUDE.md`). Prije preuzimanja tuđeg dokumenta `./scripts/verify-doc-refs.sh`.
- **Jezik:** UI portala i članci na hrvatskom, pravopis IHJJ, bez emojija. Članci su u
  trećem licu (novinarski registar), UI portala oslovljava čitatelja s „ti” kao i
  aplikacija.
- **Javni repo.** Ništa pregovaračko (cijene rada, uvjeti s kreatorima) ne ide ovamo.
  Ključevi samo u `vijesti/.env` (u `.gitignore`).
- **Autonomno:** ne pitaj korisnika osim na vratima i za trošak; odluči sam i zapiši
  odluku. Svaki zeleni korak commitaj na `main` s trailerom iz korijenskog `CLAUDE.md`.
  Nepovratne vanjske akcije (deploy u produkciju, produkcijska baza, AEM, mail kreatorima)
  ostavi korisniku.
- **Token budget:** bez Monitora koji javlja napredak. Duge jobove pokreni s
  `run_in_background` i javi se tek na kraju. Najviše 2–3 agenta paralelno. Oko 150k
  konteksta orkestratora zatvori sesiju po koraku 3 lanca.
- Svako istraživanje zapiši u `vijesti/docs/research/YYYY-MM-DD-*.md`.

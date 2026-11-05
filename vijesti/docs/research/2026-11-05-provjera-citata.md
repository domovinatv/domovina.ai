# Provjera citata: napad i mjerenje rizika (S2, 2026-11-05)

Druga polovica S2: pokušaj rušenja provjere citata (`engine/verify/quote.ts`) nad
stvarnim fixtureima i mjerenje koliko PRAVIH citata provjera odbije. Bez modela:
„pravi citat” je simuliran iz titla. Odluke 210–214.

## Zaključak

- **Prva izvedba (1462778) je propuštala izmijenjene citate.** Na 5 fixturea:
  49 od 49 citata s promijenjenim nastavkom jedne riječi prošlo je kao `fuzzy`
  (`mislim`→`mislis`, `svijest`→`svijet`, `postoje`→`postaje`,
  `thousand`→`thousands`), 91 od 91 citat s promijenjenom dijakritikom kao
  `exact` (`križa`→`kriza`, `naš`→`nas`, `mlađih`→`mladih`), a 155 od 155
  citata koji počinju odmah iza niječnice („da ga ne | izgubiš”) kao `exact`, uz
  jedan s odrezanom niječnicom na kraju („pa možda i | nije”). Sada svih 998
  (843 + 155) pokvarenih citata pada (`engine/verify/adversarial.test.ts`), a doslovni
  citati istih cueova prolaze.
- **Doslovni citati: 773 od 778 prolazi (99,4 %).** Svih 5 padova su
  `negation_cut` u `pIx_7N-6HJ4`, gdje cue završava ili počinje usred rečenice
  uz niječnicu („Mislim da ta priča | nije utemeljena”). Pregledani su ručno:
  svaki je rez uz niječnicu, ne lažni alarm. Citat „od pola cuea do pola
  sljedećeg” prolazi 325 od 335 (97,0 %), padovi su opet samo `negation_cut`.
- **Interpunkcija i velika slova ne smetaju** (isti 773 od 778). Engleski brojevi
  s razdjelnikom tisućica (`300,000`) su do odluke 213 rušili 5 od 242 citata
  kad ih model napiše bez zareza.
- **Model koji izbaci „ovaj”, „znači”, „dakle”, „ono” pada: prolazi 17 od 229**
  (7,4 %, oni gdje je riječ bila na rubu). To je namjerno (odluka 204), ali je
  najveći očekivani izvor odbijanja pravih citata na hrvatskom. Glasova
  oklijevanja (`hm`, `eh`) u hrvatskim titlovima nema nijednog (Gemini ih čisti),
  u engleskom 2 uzorka, oba `fuzzy`.
- **ASCII citat (bez dijakritike) pada uvijek** (0 od 495; prije 495 od 495).
- **Rizik „SRT tekst ↔ words vremena” je na fixtureima nula.** Svaki cue s
  `words.json` ima vremena (0 `count_mismatch`), sva vremena su unutar cuea i
  uzlazna, svi cueovi `a = 1`. `srt_only` daje samo epizoda bez `words.json`
  (`P9sLks-f2mQ`: 126 od 126). Riječi od 0 ms postoje (7, 60, 12, 0), ali nijedan
  doslovni citat zbog njih nije pao na `srt_only`. Ograda: `words.json` nosi samo
  parove vremena, ne tekst, pa se ne može provjeriti pripada li k-ti par k-toj
  riječi Geminijevog teksta; to bi trebalo usporedbu sa zvukom.
- **Za S3 s pravim modelom ostaje izmjeriti**: koliko odgovora padne na
  `no_discourse`-tip izmjena (`not_found`), `word_form` (model „ispravi” oblik),
  `negation_cut` (model počne citat iza niječnice) i `outside_window`. Simulacija
  ne zna koliko često model to radi; zna samo da provjera tada odbija.

## Metoda

`engine/verify/measure.ts` (`samples`, `tally`), za svih 5 fixturea S1, svaki na
jeziku snimke (`x3w2BVZJ9vQ` = `diarized.en.srt` + `words.en.json`):

- **doslovan**: svaki cue s govornikom i ≥ 4 riječi bez poštapalica, i svaki par
  uzastopnih takvih cueova istog govornika, kao citat s točnim `cue_from`/`cue_to`;
- **(a1)** iz istih uzoraka izbačeni glasovi oklijevanja (`FILLERS`, odluka 204);
- **(a2)** izbačeni i `ovaj`, `znači`, `dakle`, `ono`;
- **(b)** bez zareza/točke-zareza/dvotočke, mala slova pa veliko prvo slovo, hrvatski
  navodnici i točka na kraju;
- **(c)** samo parovi: druga polovica riječi prvog cuea + prva polovica drugog;
- **(d)** cijeli citat bez dijakritike.

(a1), (a2) i (d) postoje samo kad mijenjaju tekst, pa imaju manje uzoraka.
Napad (`adversarial.test.ts`) uzima do 12 cueova po fixtureu (≥ 10 riječi, cue
počinje rečenicu, ravnomjerno po titlu) i za svaki radi: zamjenu najdulje riječi,
broja (znamenke +1, broj riječima), nastavka riječi iz rječnika istog fixturea,
dijakritike (skinuta i dodana), umetanje `ne`/`nije` (`not`/`never`), brisanje
riječi, niječnice i broja, zamjenu reda dviju riječi, dvije izmišljene rečenice
iste teme, doslovan citat uz daleki cue (`outside_window`), krivog govornika
(`speaker_mismatch`), spoj cuea i i i+2 bez znaka i s „…”, te sve citate iza
niječnice u cijelom titlu. Plus `x3w2BVZJ9vQ`: hrvatski prijevod kao citat
engleskog izvornika i obrnuto (`not_found`), i `--lang hr` se odbija (odluka 200).
Ukupno 843 napada po cueovima i 155 rezova iza niječnice, uz jezične napade.

## Tablica

| fixture | varijanta | n | exact | fuzzy | srt_only | prolazi | failed (razlozi) |
|---|---|---:|---:|---:|---:|---:|---|
| pIx_7N-6HJ4 | doslovan cue / par cueova | 140 | 135 | 0 | 0 | 96.4 % | negation_cut 5 |
| pIx_7N-6HJ4 | (a2) i bez „ovaj, znači, dakle, ono” | 46 | 4 | 0 | 0 | 8.7 % | not_found 42 |
| pIx_7N-6HJ4 | (b) druga interpunkcija i velika slova | 140 | 135 | 0 | 0 | 96.4 % | negation_cut 5 |
| pIx_7N-6HJ4 | (c) od pola cuea do pola sljedećeg | 60 | 59 | 0 | 0 | 98.3 % | negation_cut 1 |
| pIx_7N-6HJ4 | (d) bez dijakritike (ASCII) | 131 | 0 | 0 | 0 | 0 % | not_found 112, word_form 19 |
| P9sLks-f2mQ | doslovan cue / par cueova | 126 | 0 | 0 | 126 | 100 % | – |
| P9sLks-f2mQ | (a2) i bez „ovaj, znači, dakle, ono” | 25 | 0 | 0 | 1 | 4 % | not_found 24 |
| P9sLks-f2mQ | (b) druga interpunkcija i velika slova | 126 | 0 | 0 | 126 | 100 % | – |
| P9sLks-f2mQ | (c) od pola cuea do pola sljedećeg | 58 | 0 | 0 | 55 | 94.8 % | negation_cut 3 |
| P9sLks-f2mQ | (d) bez dijakritike (ASCII) | 119 | 0 | 0 | 0 | 0 % | not_found 94, word_form 25 |
| x3w2BVZJ9vQ | doslovan cue / par cueova | 242 | 242 | 0 | 0 | 100 % | – |
| x3w2BVZJ9vQ | (a1) bez glasova oklijevanja (hm, eh…) | 2 | 0 | 2 | 0 | 100 % | – |
| x3w2BVZJ9vQ | (b) druga interpunkcija i velika slova | 242 | 242 | 0 | 0 | 100 % | – |
| x3w2BVZJ9vQ | (c) od pola cuea do pola sljedećeg | 107 | 105 | 0 | 0 | 98.1 % | negation_cut 2 |
| MGLq9v3AtvE | doslovan cue / par cueova | 136 | 136 | 0 | 0 | 100 % | – |
| MGLq9v3AtvE | (a2) i bez „ovaj, znači, dakle, ono” | 91 | 6 | 0 | 0 | 6.6 % | not_found 85 |
| MGLq9v3AtvE | (b) druga interpunkcija i velika slova | 136 | 136 | 0 | 0 | 100 % | – |
| MGLq9v3AtvE | (c) od pola cuea do pola sljedećeg | 50 | 48 | 0 | 0 | 96 % | negation_cut 2 |
| MGLq9v3AtvE | (d) bez dijakritike (ASCII) | 118 | 0 | 0 | 0 | 0 % | word_form 66, not_found 52 |
| b-nls1ck8EE | doslovan cue / par cueova | 134 | 134 | 0 | 0 | 100 % | – |
| b-nls1ck8EE | (a2) i bez „ovaj, znači, dakle, ono” | 67 | 6 | 0 | 0 | 9 % | not_found 61 |
| b-nls1ck8EE | (b) druga interpunkcija i velika slova | 134 | 134 | 0 | 0 | 100 % | – |
| b-nls1ck8EE | (c) od pola cuea do pola sljedećeg | 60 | 58 | 0 | 0 | 96.7 % | negation_cut 2 |
| b-nls1ck8EE | (d) bez dijakritike (ASCII) | 127 | 0 | 0 | 0 | 0 % | not_found 87, word_form 40 |

| fixture | cueova | s vremenima | count_mismatch | bez words | a = 1 | riječi | riječi od 0 ms | izvan cuea / unatrag |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| pIx_7N-6HJ4 | 85 | 85 | 0 | 0 | 85 | 1921 | 7 | 0 |
| P9sLks-f2mQ | 73 | 0 | 0 | 73 | 0 | 0 | 0 | 0 |
| x3w2BVZJ9vQ | 149 | 149 | 0 | 0 | 149 | 2521 | 60 | 0 |
| MGLq9v3AtvE | 103 | 103 | 0 | 0 | 103 | 2146 | 12 | 0 |
| b-nls1ck8EE | 75 | 75 | 0 | 0 | 75 | 1956 | 0 | 0 |

Brojke za staru provjeru (1462778) dobivene su istom skriptom nad
`git show 1462778:vijesti/engine/verify/{quote,normalize}.ts` u privremenom
direktoriju; nisu u repou.

## Reprodukcija

```bash
cd vijesti
npm run verify:measure                      # obje tablice
npx vitest run engine/verify                # napad + fiksirane brojke (measure.test.ts)
```

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

## S1 (2026-11-05)

100. **Alati: TypeScript strict, ESM, zod, vitest, eslint `strictTypeChecked`.** Node
     22+ (`engines`), lokalno 24. tsconfig uz `strict` pali `noUncheckedIndexedAccess` i
     `exactOptionalPropertyTypes`. Runtime validacija svega izvana (CDN, LLM) ide kroz
     zod 4, skripte kroz `tsx`. Razlog: isti jezik za engine i Astro portal, a ulaz s
     CDN-a i iz modela se ne vjeruje bez provjere. Revizija: ako `npm run check` naraste
     iznad ~30 s zbog type-aware linta.
101. **`episode.json` je popis istine za epizodu.** Inline sadržaj se koristi umjesto
     zasebnog zahtjeva, datoteka koje nema na popisu se ne traži, a popis iz disk cachea
     koji kaže „nema” se jednom revalidira prije zaključka. Bez `episode.json` loader ide
     datoteku po datoteku, kao Flutter. Razlog: pravila iz korijenskog `CLAUDE.md`.
102. **404 se ponavlja jednom s `?cb=<floor(now / 300 000)>`.** Drugi 404 znači da
     datoteke nema; 404 se ne sprema u cache; ostali ne-2xx statusi su greška
     (`CdnHttpError`), ne „nema datoteke”. Razlog: CDN cachira 404 do 4 h.
103. **Disk cache `vijesti/.cache/cdn/<putanja>`.** Per-epizoda datoteke bez roka,
     `episode.json` i `channels/data/*` s rokom od 5 min, zapis atomaran (tmp +
     rename). Revizija: ako engine počne čitati datoteke koje pipeline prepisuje pod
     istim imenom (`reels.json`), one idu u promjenjive.
104. **Loader šalje vlastiti `User-Agent`** (`domovina-vijesti/0.1 (+https://domovina.ai/vijesti)`).
     Razlog: Cloudflare vraća 403 Pythonovom `urllib` (izmjereno 5.11.), pa ne ovisimo
     o tome što zadani klijent pošalje, a promet engina je prepoznatljiv u logovima.
105. **Uparivanje `words.json` po početku ±1 ms, a kod istog početka i po kraju.**
     Odstupa od Flutterovog uparivanja samo po početku, koje cueove od 0 ms koji dijele
     početak sa sljedećim ostavlja bez vremena (8 promašaja na 3 epizode, poslije
     popravka 0). Cue s drugim brojem riječi je `count_mismatch`, bez vremena, nikad
     pomaknut. Isti popravak vrijedi predložiti Flutteru, izvan ovog lanca.
106. **Jezik citata nije `summary.language`.** To je jezik izlaza (uvijek `hr`).
     `diarized.srt` na engleskim kanalima je negdje hrvatski prijevod
     (`x3w2BVZJ9vQ`), negdje engleski izvornik (`nuNw4qWs0r4`), bez metapodatka.
     Loader prima `lang` i tada uzima `diarized.<lang>.srt` + `words.<lang>.json` kad ih
     `episode.json` navodi, a `moments` ima `quote_lang`. Kako engine zna jezik snimke,
     odlučuje S2. Prijedlog: jezik kanala u popisu dopuštenih (odluka 8).
107. **`runs` je zbroj po prolazu, trošak je NULL dok cijena nije u konfiguraciji.**
     Stupci: `calls`, `failed_calls`, `tokens_in`, `tokens_out` (izlaz uključuje
     „thinking” tokene), `cost_usd`. Cijena dolazi iz `VIJESTI_GEMINI_PRICE_*_PER_MTOK`,
     jer cjenik nismo provjerili i ne upisujemo broj bez izvora. Neuspio poziv (HTTP,
     prekid, shema) se broji, jer su tokeni plaćeni. Jedan poziv bez cijene čini ukupni
     trošak nepoznatim. Revizija: ako S3 treba trošak po pozivu, dodaje se tablica
     `llm_calls`.
108. **Vlastiti runner migracija** (`db/migrate.ts`, `NNN_ime.up.sql` + `.down.sql`,
     svaka u transakciji). Shemu `vijesti` i `vijesti.schema_migrations` stvara runner,
     pa `down` prve migracije briše tablice, a trag o stanju ostaje. Baza je iza sučelja
     `SqlDb` (`exec`, `query`) koje PGlite zadovoljava izravno; produkcija dobiva
     adapter u S7.
109. **Ograničenja u shemi od prvog dana.** `quote_check` CHECK (`exact`, `fuzzy`,
     `srt_only`, `failed`), `end_ms > start_ms`, neprazan citat, UNIQUE (`video_id`,
     `start_ms`, `end_ms`, `quote`). Citiran trenutak se ne može obrisati
     (`article_sources` → `moments` RESTRICT). `articles.status` CHECK sa stanjima iz
     plana (`draft`, `review`, `approved`, `published`, `corrected`, `rejected`).
     `moments.score` je `real` bez raspona jer skalu određuje S3. Revizija: S3 (skala
     ocjene), S5 (stanja).
110. **Gemini preko REST-a `generateContent`.** Ključ ide u zaglavlje `x-goog-api-key`,
     nikad u URL. Shema izlaza ide kao `responseJsonSchema` (zod → JSON Schema 2020-12,
     bez `$schema`), uz `responseMimeType: application/json`. `finishReason` različit od
     `STOP`, blokiran ili prazan izlaz je `LlmResponseError`; izlaz koji nije JSON ili ne
     prolazi shemu je `LlmSchemaError`. Zadani model je `gemini-3.5-flash`, koji
     pipeline koristi za članke (`P9sLks-f2mQ`). Revizija: prvi pravi poziv (S2/S3) mora
     potvrditi da API prima `responseJsonSchema` za naše sheme. Ako ne prima, prelazi se
     na `responseSchema`, uz test.
111. **Lažni klijent vraća snimke `{text, usage}`** po imenu poziva ili redom, i
     validira ih istom funkcijom (`parseLlmJson`) kao pravi klijent. S1 snimke su ručno
     napisane (`engine/test/fixtures/llm/README.md`), jer S1 ne zove model.
112. **Kanal epizode dolazi iz listinga, ne iz `summary.source.channel`.** Epizode
     kanala `domovina_tv` tamo imaju `_unlisted`. Važno za popis dopuštenih (odluka 8).
113. **Fixturei: prvih 15 min, stvarni oblik, `info.json` sveden na polja loadera.**
     Magisterium je izbačen iz `inline`, a `files` ostaje stvaran. `fixtures:refresh`
     pada kad epizoda više ne zadovoljava kriterij, umjesto da tiho promijeni test.
     Razlog: `words.json` se backfilla (`MGLq9v3AtvE` ga je dobio tijekom ove sesije).
114. **`npm audit`: 10 moderate ranjivosti u lancu `eslint` → `minimatch`, samo dev.**
     Ne dira se dok popravak ne traži major skok. U produkcijski kod ne ulazi.
     Revizija: kad `eslint` objavi popravak ili kad portal (S6) uvede runtime ovisnosti.
115. **Tmp datoteka disk cachea je jedinstvena po zapisu** (`<pid>.<uuid>.tmp`).
     Dva istodobna zapisa iste putanje u istom procesu dijelila su `<pid>.tmp`, pa je
     drugi `rename` padao s ENOENT (reproducirano testom, 8 paralelnih `set`).
     Pobjeđuje zadnji `rename`; sadržaj je isti jer su per-epizoda datoteke immutable.
116. **Dvosmislen početak traži i poklapanje kraja, inače cue ostaje bez vremena.**
     Dopuna odluke 105: početak je dvosmislen kad ga dijeli više zapisa u `words.json`
     ILI više SRT cue-ova (±1 ms). Prije je kratki cue uz samo jedan zapis (dugog
     cue-a) dobivao taj zapis, a uz dva zapisa bez poklapanja kraja prvi od njih; uz
     isti broj riječi to su pomaknuta vremena. Fixturei: bez promjene (svi `ok` ostaju).
117. **Gemini: prekid se broji kao neuspio poziv.** `fetch` koji baci ili tijelo
     odgovora prekinuto usred čitanja bilježe poziv s 0 tokena i `ok: false` prije
     nego greška ide dalje, kako odluka 107 traži („HTTP, prekid, shema”). Isti prolaz
     (S1, drugi agent) u loaderu: inline `null` u `episode.json` nije „ima” (`has()` i
     `file()` se slažu), a neuspjela revalidacija popisa se ne pamti u memoizaciji.

## S2 (2026-11-05)

200. **Jezik citata: `--lang` → izvorni par iz `episode.json` → jezik kanala → `hr`,
     pa provjera teksta.** Par je `diarized.<xx>.srt` + `words.<xx>.json` (xx ≠ hr): vrijeme
     po riječi ima samo titl nastao iz zvuka, a prijevod (`diarized.en.srt` hrvatske
     epizode u fazi 3 plana 2026-10-29) ga nema, pa goli `diarized.<xx>.srt` nije znak
     izvornika. `--lang` koji proturječi paru je greška (`x3w2BVZJ9vQ --lang hr` bi citirao
     prijevod), kao i više parova te goli `diarized.srt` bez `words.json` uz titl drugog
     jezika (ne zna se koji je izvornik). Listing kanala jezik ne nosi (`schemas.ts`,
     fixturei), pa je „jezik kanala” parametar za popis dopuštenih (odluka 8), zasad
     prazan. Zatim heuristika nad CIJELIM odabranim titlom: funkcijske riječi hr/en bez
     riječi koje postoje u oba jezika; traži ≥ 30 pogodaka i udio traženog jezika ≥ 0,8,
     inače epizoda se ne obrađuje (prije ijednog poziva modela). Na fixtureima (15 min)
     HR titlovi imaju 498/1, 626/4, 597/2, 459/0 (hr/en), HR prijevod `x3w2BVZJ9vQ` 569/0,
     EN izvornik 0/906 (`engine/extract/lang.test.ts`). Jezici osim hr/en se odbijaju
     dok ne dobiju popis riječi. Revizija: kad popis dopuštenih dobije jezik kanala, ili
     kad tehnička epizoda s puno engleskih termina padne ispod 0,8.
201. **Dijelovi za prompt su sekcije SVIH iteracija članka**, ne zadnje: iteracija je
     vremenski odsječak (~40 min, `b-nls1ck8EE` ih ima 4), ne verzija, pa bi zadnja
     izostavila sve prije nje. Sekcija = [njen `screenshot_timestamp`, početak sljedeće),
     zadnja do kraja titla; prva počinje od 0 (uvod prije prvog podnaslova nije
     izgubljen); cue pripada sekciji u kojoj mu je početak; prazne sekcije nemaju poziv.
     Bez članka fiksni prozori od 10 min. Test: `engine/extract/extract.test.ts`
     („sekcije i prompt”: `pIx_7N-6HJ4` 10 sekcija, svaki cue točno jednom). Revizija:
     ako sekcije budu predugačke za kontekst modela (S3 mjeri).
202. **Normalizacija za usporedbu:** mala slova, `đ → d` eksplicitno (NFD ga ne rastavlja),
     NFD + brisanje kombinirajućih znakova, apostrofi se brišu (`don't → dont`), sve ostalo
     što nije slovo/znamenka je razmak. Ista funkcija ide na citat i na svaku riječ titla,
     pa svaki normalizirani token pamti cue i indeks riječi (za vrijeme). Test:
     `engine/verify/quote.test.ts` („normalizacija”). **Dijakritika se od odluke 210
     briše samo za pretragu; presuda traži ista slova.**
203. **Prozor pretrage W = 5 s** oko [početak `cue_from`, kraj `cue_to`]: pretražuju se
     cueovi koji se s njim preklapaju. Citat izvan prozora je `failed: outside_window`;
     globalna pretraga postoji samo da razlikuje taj razlog od `not_found`. Kad se niz
     pojavi više puta, uzima se prvo točno pojavljivanje s ispravnim govornikom, pa tek
     onda prvo fuzzy. Revizija: ako na pravim odgovorima modela `outside_window` bude
     česta za citate koji su očito točni (pomak cue id-a za više od prozora).
204. **`fuzzy` dopušta samo dvije stvari.** (a) Brisanje iz titla, usred citata, tokena s
     ZATVORENOG popisa glasova oklijevanja: `hm hmm hmmm mm mmm eh ehm ee eee eem aa aaa ah
     uh uhm um umm erm`. Namjerno nisu na popisu: `ovaj`, `ono` (pokazne zamjenice),
     `dakle`, `znači`, `mislim` (ograda), `kao`, `mhm`/`aha` (= da), `em` (em… em), `er`
     (= jer), `e` (`e-pošta`), `a`, `i`, `ne`. (b) Razliku jednog znaka (zamjena, umetanje
     ili brisanje) u ZADNJA 3 znaka riječi kojoj su obje strane ≥ 6 znakova i bez
     znamenaka, najviše `floor(n / 10)` takvih riječi za citat od n tokena (citat ispod 10
     tokena mora biti točan na razini znaka). Prolazi: „ja sam hm rekao” → „ja sam rekao”;
     `napravili`/`napravila`, `milijun`/`milijuna` u citatu od ≥ 10 riječi. Ne prolazi:
     izostavljen `ovaj` ili `ne`, umetnuta riječ, zamjena riječi (`nisam` → `sam`),
     `legalno`/`ilegalno` (početak), `prodati`/`predati` (sredina), `1000000`/`1000001`,
     dvije izmjene u 10 riječi. Sve u `quote.test.ts`. Prvo se traži točno poklapanje.
     Revizija: popis i pravilo se mijenjaju samo s primjerom iz stvarnog odgovora modela
     i testom koji pokazuje da značenje ostaje. **Dio (b) ukinut odlukom 210.**
205. **Razlozi odbijanja** (`failed`, uvijek se zapisuju): `bad_cue_ref` (nepostojeći ili
     obrnut raspon), `span_too_long` (`cue_from..cue_to` > 120 s, da model ne „pokrije”
     cijelu sekciju i time ugasi prozor), `too_short` (< 4 tokena bez poštapalica),
     `not_found`, `outside_window`, `speaker_mismatch` (svaki cue u nađenom spanu mora
     imati SRT oznaku = `speaker` modela), `ellipsis` (citat ima više „…”/„...” od titla
     u tom spanu). Tri točke se ne zabranjuju naslijepo: titlovi ih imaju za prekinut
     govor (`grep -c '\.\.\.\|…' engine/test/fixtures/*/diarized*.srt`: `pIx_7N-6HJ4` 5,
     `MGLq9v3AtvE` 6, `b-nls1ck8EE` 1, ostali 0),
     a prva izvedba je zato odbijala doslovne citate (2 od 70 na `--fake`). Revizija: S3.
206. **Vrijeme citata je iz titla, nikad iz modela.** Model ne vraća ms, samo `cue_from`/
     `cue_to`. `start_ms`/`end_ms` = početak prve i kraj zadnje riječi spana iz
     `words.json` (indeks riječi unutar cuea). `srt_only` kad epizoda nema words za taj
     jezik, kad ijedan cue u spanu nema vremena (`count_mismatch`/`missing`) ili kad bi
     riječi dale kraj ≤ početak; tada su granice prvog i zadnjeg cuea, a cue od 0 ms
     dobiva kraj = početak + 1 (CHECK `end_ms > start_ms`). Test: `quote.test.ts`.
207. **Migracija 002: `claim`, `reject_reason`, `quote_match`, `cue_from`, `cue_to`.**
     CHECK `(quote_check = 'failed') = (reject_reason IS NOT NULL)` i `quote_match`
     (exact/fuzzy) koji za `exact`/`fuzzy` mora biti jednak `quote_check`, za `srt_only`
     postoji (da se ne izgubi je li tekst bio točan), za `failed` je NULL. Odbačen
     trenutak ima raspon cueova koje je model naveo; uz `bad_cue_ref` raspon sekcije u
     kojoj je model odgovarao (uvijek valjan). `cue_from`/`cue_to` se pišu kakve je model
     dao, i kad su nevaljane. Ponovno izvlačenje u jednoj transakciji briše trenutke tog
     videa na koje se NE poziva ni `article_sources` ni `story_moments` (priča iz S3 ne
     smije izgubiti trenutak tiho) i upisuje nove uz `ON CONFLICT DO NOTHING`; dva
     pokretanja daju isti broj redaka i citirani trenutak ostaje (`extract.test.ts`,
     CLI test). Testovi gore/dolje: `db/migrate.test.ts`.
208. **Jedan `runs` zapis po izvlačenju, jedan poziv po sekciji** (`step = extract`,
     `prompt_version = extract-moments/1`, `temperature 0`, `name = extract-moments`).
     Izlaz koji ne prolazi shemu (`LlmSchemaError`) preskače tu sekciju, ostale se
     zapisuju, a run završava kao `failed` s brojem takvih sekcija; svaka druga greška
     prekida prolaz bez zapisa trenutaka. Jezik i titl se provjeravaju prije `startRun`,
     pa odbijena epizoda nema ni run ni poziv. Revizija: S3, ako ponovni pokušaj sekcije
     bude jeftiniji od gubitka.
209. **`--fake`: lažni LLM sastavlja odgovor iz redaka u promptu**, deterministički: cueovi
     s oznakom govornika i ≥ 4 riječi, najdulji prvi (kod iste duljine raniji), 2 ako ih
     sekcija ima ≥ 6, inače 1; citat je doslovan tekst cuea, trošak 0. Prolazi istu shemu
     i brojanje poziva kao Gemini. ID iz `FIXTURES` čita lažni CDN (bez mreže), ostali
     pravi CDN. Na 5 fixturea (`npm run vijesti -- extract <id> --fake --db <tmp>`,
     `extract.test.ts`): `pIx_7N-6HJ4` 10 sekcija / 20 exact, `P9sLks-f2mQ` 5 / 10
     srt_only, `x3w2BVZJ9vQ` 9 / 18 exact (en), `MGLq9v3AtvE` 6 / 12 exact, `b-nls1ck8EE`
     5 / 10 exact; 0 failed. To dokazuje lanac, ne kvalitetu izbora.
210. **`fuzzy` je samo brisanje glasova oklijevanja; razlika u nastavku ili dijakritici
     je `failed: word_form`.** Napad na fixtureima (`engine/verify/adversarial.test.ts`)
     je pod pravilom 204(b) propustio 49 od 49 citata s jednom promijenjenom riječi
     (`fuzzy`) i, zbog normalizacije 202, 91 od 91 s promijenjenom dijakritikom (`exact`).
     U hrvatskom nastavak nosi lice, vrijeme i broj, a parovi iz samih fixturea mijenjaju
     i riječ: `mislim`/`mislis`, `trebamo`/`trebalo`, `svijest`/`svijet`,
     `postoje`/`postaje`, `probao`/`prosao`, `dvadeset`/`dvadesete`, `thousand`/`thousands`,
     `influence`/`influencer`; dijakritika `križa`/`kriza`, `naš`/`nas`, `mlađih`/`mladih`.
     Pravilo ne razlikuje sročnost od promjene značenja, a model ima titl u promptu, pa
     doslovan citat ne treba ni jednu izmjenu. Token zato ima dva oblika (`t` bez
     dijakritike za pretragu, `d` s njom za presudu, `normalize.ts`); poravnanje s
     izmjenom do jedne riječi na 10 (najmanje 1) ostaje samo kao dijagnoza `word_form`
     (`detail: titl→citat`), da S3 vidi koliko ih model radi. Cijena: ASCII citat pada
     uvijek (0 od 495, prije 495 od 495), ostale varijante nepromijenjene (odluka 212).
     Testovi: `quote.test.ts` („dijakritika mora biti ista”, „nastavak koji mijenja lice…”).
     Revizija: S3, ako `word_form` na pravim odgovorima bude čest za izmjene koje ne mijenjaju
     značenje; tada popis dopuštenih parova s primjerom i testom, ne opće pravilo.
211. **`failed: negation_cut`: citat ne smije počinjati odmah iza niječnice ni završavati
     odmah ispred nje** (isti govornik, preko poštapalica i granice cuea, bez interpunkcije
     između; zarez/točka odvajaju, pa „Ne. Mislim da …” smije od „Mislim”). Zatvoren popis
     `NEGATIONS` u `quote.ts`: hr `ne ni niti nit nisam nisi nije nismo niste nisu necu
     neces nece necemo necete nemoj nemojte nikad nikada nimalo`, en `not no never nor
     neither` i stegnuti oblici (`dont`, `isnt`, `cant`…). Doslovan podniz titla inače
     prolazi kao `exact`, a obrće značenje: „da ga ne | izgubiš”, „nikad neću | zaboraviti”,
     „nije | istina da …”. Stara provjera je na fixtureima propustila 155 od 155 takvih
     citata i jedan s odrezanom niječnicom na kraju („pa možda i | nije”, `MGLq9v3AtvE`
     c71). Cijena na simuliranim pravim citatima: 5 od 778 doslovnih i 10 od 335 „pola-pola”
     (odluka 212), svi ručno pregledani kao stvarni rez uz niječnicu (cue podijeljen usred
     rečenice); dvostruka niječnica („nisam | nikad bio”) se također odbija. Testovi:
     `quote.test.ts` („negation_cut”), `adversarial.test.ts`. Revizija: S3, ako model često
     počinje citat iza niječnice — tada prompt, ne popuštanje provjere.
212. **Mjerenje rizika na 5 fixturea (bez modela, `npm run verify:measure`,
     `docs/research/2026-11-05-provjera-citata.md`):** doslovni cue i par cueova istog
     govornika prolaze 773 od 778 (99,4 %; 5 × `negation_cut`), s drugom interpunkcijom i
     velikim slovima isto, od pola cuea do pola sljedećeg 325 od 335 (97,0 %; 10 ×
     `negation_cut`); bez `ovaj/znači/dakle/ono` 17 od 229 (7,4 %), bez dijakritike 0 od 495.
     `srt_only` je samo epizoda bez `words.json` (126 od 126 u `P9sLks-f2mQ`): na ostalima
     0 `count_mismatch`, sva vremena unutar cuea i uzlazna. Brojke fiksira
     `engine/verify/measure.test.ts`. Ograda: simulacija mjeri koliko provjera odbija
     zadani tip izmjene, ne koliko ih model radi. Revizija: S3 mjeri isto na pravom Gemini
     izlazu (udio po razlogu); ako `not_found` zbog izbačenih diskursnih riječi bude velik,
     prvo prompt („ne izbacuj riječi”), ne širenje `FILLERS`.
213. **Razdjelnik tisućica unutar broja se briše** (`300,000` = `300.000` = `300000`),
     samo ispred točno tri znamenke, pa `3,5` i `12.30` ostaju dva tokena. Engleski
     titl piše `300,000`, a model isti broj bez zareza: 5 od 242 citata `x3w2BVZJ9vQ`
     padalo je na varijanti (b) prije ovoga, 0 poslije. Test: `quote.test.ts`
     („normalizacija”), `measure.test.ts`. Broj riječima ≠ znamenke (`deset` ≠ `10`) i dalje.
214. **Popravci pregleda koda S2.** (a) `span_too_long` vrijedi i za NAĐENI citat (vrijeme
     iz riječi ili granice cueova): prozor uključuje svaki cue koji ga dodiruje, pa su dugi
     susjedni cueovi citat s navedenim jednim cueom razvlačili preko 120 s. (b) `saveMoments`
     upisuje prihvaćene trenutke prije odbačenih: odbačen i prihvaćen s istim ključem
     (video, raspon, citat), npr. isti citat uz krivog pa pravog govornika, inače je
     `ON CONFLICT DO NOTHING` zadržavao odbačeni (`engine/extract/store.test.ts`).
     (c) Migracija 002 gore postavlja `quote_match = quote_check` za `exact`/`fuzzy` prije
     CHECK-ova, pa 002 dolje → gore s takvim retcima prolazi; `failed`/`srt_only` nakon 002
     dolje su izgubili razlog i podudaranje, i to se ne izmišlja: migracija pada u
     transakciji (verzija ostaje 1), retke treba ponovno izvući (`db/migrate.test.ts`).
     Provjereno bez promjene: prazan citat i citat od same interpunkcije su `too_short`,
     citat preko cijelog prozora prolazi, cue od 0 ms daje `srt_only` s krajem +1 ms, citat
     preko granice sekcije prolazi s rasponom u sljedećoj sekciji (`extract.test.ts`).

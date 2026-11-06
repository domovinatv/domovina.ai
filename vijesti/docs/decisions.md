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

## S3 (2026-11-05)

300. **Vertex AI je zadani backend; AI Studio ostaje kao `studio`.** Isto tijelo
     `generateContent`, drugi URL (`…/v1/projects/<p>/locations/<l>/publishers/google/models/<m>:generateContent`;
     `global` → `aiplatform.googleapis.com`, `eu`/`us` → `aiplatform.<l>.rep.googleapis.com`,
     regija → `<r>-aiplatform.googleapis.com`, kao `fetch.domovina.tv/lib/vertex_auth.js`) i
     `Authorization: Bearer`. Razlog: `GEMINI_API_KEY` ne postoji nigdje, free-trial krediti
     pokrivaju Vertex, ne AI Studio. Token daje ubrizgan `AccessTokenProvider`; u produkciji
     `execFile('gcloud', ['auth', 'print-access-token', '--account=…'])` (bez ljuske), keš 50 min,
     istodobni pozivi dijele jedan proces, 401 poništava keš. Token se ne logira: greška
     gcloud-a nosi samo stderr, poruka HTTP greške prolazi kroz `redact` (i ključ AI Studija),
     `describeLlmConfig` ispisuje projekt/lokaciju/account bez tajni. Neuspjelo dobivanje tokena
     nije poziv (zahtjev nije poslan) i ne broji se. Izbor: `VIJESTI_LLM_BACKEND`, zadano
     `vertex` bez `GEMINI_API_KEY`, `studio` s njim; `VIJESTI_VERTEX_PROJECT` (obavezan),
     `VIJESTI_VERTEX_ACCOUNT` (preporučen: aktivni gcloud account zna biti drugi SA → 403),
     `VIJESTI_VERTEX_LOCATION` (zadano `global`). Testovi: `engine/llm/vertex.test.ts`.
     **Rizik (pročitano 5.11. u `fetch.domovina.tv`):** pipeline je Vertex isključio 28.10. i
     proglasio ga DEPRECATED 29.10. (`docs/2026-10-28-vertex-iskljucen-agy-jedini-gemini.md`):
     28.10. je pipelineov Vertex projekt za svaki model i regiju vraćao `403 Request rejected in
     accordance with our terms of use and policies`; pipeline od tada Gemini zove samo kroz
     `agy`. Tvrdnja da „pipeline koristi Vertex” vrijedi do 28.10. Revizija: prvi pravi poziv
     (`npm run eval -- --max-calls 1`). Ako vrati 403 terms-of-use, Vertex na tom projektu ne
     radi i odluka o putu (drugi projekt, AI Studio ključ) je korisnikova.
301. **Zadani model `gemini-3.8-flash`** (zamjenjuje model iz 110). Pipeline je na njega prešao
     15.9.2026. (`gemini.conf`), global-only za 3.x flash. Napomena iz pipelinea: 3.8 nije prošao
     kontrolirani A/B kao 3.7; ako kvaliteta trenutaka padne, prvi osumnjičeni je model.
     `VIJESTI_GEMINI_MODEL` ga mijenja.
302. **429 i 5xx: dva ponovna pokušaja, čekanje 2 s pa 4 s.** Pipeline je dobivao 429 iz global
     bazena. Svaki pokušaj je zaseban neuspio poziv u `runs` (odluke 107, 117), jer je zahtjev
     poslan. Ne ponavljaju se 4xx (osim 429) ni prekid veze (`fetch` baci): 400 znači da tijelo
     ne valja (npr. shema, odluka 303) i ponavljanje samo troši kvotu. `sleep` je ubrizgan, test
     ne čeka. Test: „429 i 5xx…”, „nakon iscrpljenih pokušaja…”. Revizija: ako eval vidi više od
     ~5 % poziva s 429, dulji backoff ili lokacija `eu` (zaseban bazen kvote, +10 %).
303. **Polje sheme je opcija: `responseJsonSchema` (zadano) ili `responseSchema`.** Odluka 110
     nije potvrđena na Vertexu. `VIJESTI_GEMINI_SCHEMA_FIELD=responseSchema` šalje istu zod shemu
     pretvorenu u OpenAPI podskup (`toOpenApiSchema`): tip velikim slovima, `null` u tipu ili
     `anyOf` → `nullable`, `const` → `enum`, `propertyOrdering` po redu svojstava, izbačeni
     `additionalProperties`, `exclusiveMinimum`, `default`, `$schema`. Izlaz se u oba slučaja
     validira istim zodom, pa izbačeno ograničenje ne prolazi tiho. Prvi pravi poziv koji vrati
     400 na `responseJsonSchema` prelazi bez novog koda. Testovi: „shema: responseJsonSchema ili
     responseSchema” (oba tijela, isti klijent, odbijanje izlaza izvan sheme u oba).
304. **Zadana cijena u kodu za Vertex `gemini-3.8-flash`** (revizija 107). 107 je tražila da se
     broj ne upisuje bez izvora; izvor sada postoji: cjenik Vertexa prepisan i provjeren u
     `fetch.domovina.tv/gemini.conf` 28.9.2026.: `global` $0,75 ulaz / $3,75 izlaz po M tokena
     PROMOTIVNO do 31.12.2026., od 1.1.2027. $1,50 / $7,50; `eu`/`us` +10 % ($0,825 / $4,125).
     Bez zadane cijene svaki run imao bi `cost_usd = NULL` i S3 ne bi mogao dati trošak po
     epizodi. Tablica nosi datum udvostručenja (`promoUntilUtc`, granica u UTC; Google je
     možda na pacifičkom vremenu, razlika je nekoliko sati), pa se cijena mijenja sama, bez
     koda. `VIJESTI_GEMINI_PRICE_*` i dalje pobjeđuje; AI Studio i nepoznat model nemaju zadanu
     cijenu (NULL). Test: „cijena se sama udvostručuje 1.1.2027.”. Revizija: novi model ili
     promjena cjenika (`cloud.google.com/vertex-ai/generative-ai/pricing`).
305. **Procjena bez poziva iz izgrađenih promptova.** `prepareExtract(cdn, {videoId, lang?})` i
     `prepareScore({cdn, db, persons}, {videoId, channel?})` rade sve do poziva modela (jezik,
     titl, sekcije, kontekst, osobe) i vraćaju promptove; `runExtract`/`runScore` ih koriste, pa
     procjena i pravi prolaz grade isti tekst. `estimateTokens` = ⌈znakova / 3⌉ (pretpostavka:
     Gemini tokenizator nije dostupan offline, hrvatski s dijakritikom troši više od ~4 znaka po
     tokenu engleskog), `estimatePrompts(prompts, outTokensPerCall, pricing)` daje pozive,
     tokene i trošak. Izlazni tokeni (uz „thinking”) nisu procjenjivi iz prompta i zadaje ih
     pozivatelj. Test: „deterministički, prolazi shemu…” (11 promptova za `pIx_7N-6HJ4`).
     Revizija: prvi eval usporedi procjenu s `usageMetadata.promptTokenCount` i ispravi omjer.
306. **Ocjena: jedan poziv po epizodi nad svim prihvaćenim trenucima** (`step = score`,
     `name = score-moments`, `PROMPT_VERSION = score-moments/1`, temperatura 0). Model vidi
     sve trenutke odjednom, pa novost može usporediti i unutar epizode, a epizoda je jedan
     poziv umjesto desetaka. Trenuci su u promptu `t1…tn` redom snimke (ne ID iz baze: kraće,
     i prompt se gradi isto za procjenu). Prihvaćen = `quote_check ≠ failed`; odbačen se ne
     šalje i ne ocjenjuje. Bez prihvaćenih trenutaka nema poziva ni `runs` zapisa. Izlaz po
     trenutku: `novelty`, `concreteness`, `speaker` (0–1, zod `min/max`), `public_role` ili
     null, i po jedna rečenica razloga za svaku sastavnicu. Revizija: epizoda s vrlo mnogo
     trenutaka (izlaz > ~8k tokena) dijeli se na dijelove.
307. **Novost: kontekst je kanal, ne cijeli katalog.** Zadnjih 8 epizoda istog kanala sa
     STROGO ranijim datumom iz listinga (isti dan nije „ranije”, epizoda bez datuma nema
     ranijih), najnovije prvo, s `summary.json` naslovom i do 6 ključnih točaka; bez
     `summary.json` naslov i `abstract` iz listinga (do 400 znakova). Uz to do 40 već izdvojenih
     tvrdnji (`claim`) prihvaćenih trenutaka iz SVIH ranijih epizoda kanala u bazi. Kanal iz
     listinga (odluka 112): `--channel` ga zadaje, inače pretraga po svim listinzima (52
     dohvata na pravom CDN-u, keširani 5 min). Testovi: „kontekst novosti”, prvi test runScore
     (`b-nls1ck8EE` dobiva `MGLq9v3AtvE` i njegovih 12 tvrdnji).
308. **Govornik: ime iz `summary.json`, osoba iz `/api/persons`, uparivanje determinističko.**
     `speakers[].suggested_name` po oznaci SPEAKER_XX daje ime (upisuje se i u
     `moments.speaker_name`); ime se normalizira (mala slova, bez dijakritike, `đ → d`, bez
     zagrada, interpunkcije i titula `don fra dr sc p pater vlč fr mons…`) i mora se poklopiti
     CIJELO s normaliziranim imenom osobe. Samo ime ili samo prezime (`single_token`), oznake
     bez imena („Gost 6 (odvjetnica)”, „Nepoznati govornik”, SPEAKER_01: `placeholder`) i isto
     prezime druge osobe („Stanko Stojić” ≠ „Don Damir Stojić”) nisu pogodak. Dva zapisa istog
     imena („p.” i „Pater Stjepan Ivan Horvat”) daju onaj s više epizoda i drugi kao alternativu.
     LLM ne bira osobu; daje samo `speaker` sud i `public_role` iz konteksta, uz uputu da ne
     nagađa funkcije. Na 5 fixturea nijedan govornik nije u katalogu (voditelji i gosti bez
     profila). Test: `persons.test.ts`. Revizija: kad katalog dobije uloge (ministar, zastupnik),
     uloga ide iz kataloga, ne iz modela.
309. **Konkretnost: zatvoreni popisi obilježja uz sud modela.** Brojka (token sa znamenkom,
     godina 1900–2099 se broji kao datum), broj riječima (bez „jedan/jedna/one”: „jedan od”),
     datum (godina, mjesec hr/en u svim padežima, `12. 3.`; „studeni” ne hvata „student”,
     „siječanj” ne hvata „siječe”, bez engleskog „may”), entiteti iz izvlačenja (bez
     duplikata), najava/odluka (osnove `najav odluč zakon uredb ostavk…`, engleske kratke
     riječi u cijelosti: „ban” ne hvata „banka”). Ocjena obilježja: 0,35 broj + 0,25 datum +
     0,2 × min(entiteti, 2)/2 + 0,2 najava. Test: „konkretnost: obilježja”.
310. **Konačna ocjena je formula u kodu, `score-moments/1+f1`** (`moments.score_version`).
     novost = model; konkretnost = 0,6 model + 0,4 obilježja; govornik = 0,5 model + 0,5
     katalog (uparena osoba 0,5 + 0,5 × min(1, kanala/5), inače 0); ocjena = 0,45 novost +
     0,40 konkretnost + 0,15 govornik, na tri decimale. Novost i konkretnost nose 85 %:
     vijest je nova tvrdnja s provjerljivim sadržajem; poznat govornik je bonus, ne uvjet.
     Sastavnica izvan 0–1 baca i iza sheme. Test: „formula” (primjer 0,551). Revizija: S3
     mjerenje (10 najboljih / 10 najlošijih na pravom izlazu) i prag iz S4; promjena težina =
     `f2`.
311. **Migracija 003: skala i objašnjenje ocjene.** `moments.score` dobiva CHECK 0–1;
     novi `score_parts jsonb` (sastavnice, odgovori modela, obilježja, osoba, težine),
     `score_reasons jsonb`, `score_version`, `score_run_id`, `scored_at`; CHECK da su ocjena,
     verzija, sastavnice, razlozi i vrijeme ili svi postavljeni ili svi NULL i da `failed`
     trenutak nema ocjenu; indeks po ocjeni. 003 gore briše stare vrijednosti `score` (bez
     skale nemaju značenje), dolje briše stupce i ocjene. Ponovno ocjenjivanje u jednoj
     transakciji prvo briše ocjene svih trenutaka videa pa piše nove: dva pokretanja daju
     iste ocjene i isti broj redaka, novi `runs` zapis. Ponovno izvlačenje (207) briše
     trenutke, pa i njihove ocjene: nakon `extract` ide `score`. Testovi: `db/migrate.test.ts`
     („003…”), „ponovno ocjenjivanje je idempotentno”.
312. **Izlaz koji ne odgovara trenucima se nikad ne popravlja tiho.** Nepostojeći (`t13` uz 12
     trenutaka) ili ponovljen broj → `ScoreMismatchError`, ništa se ne upisuje (prethodne
     ocjene ostaju), run `failed`: pomak brojeva znači da nijednom paru ne možemo vjerovati.
     Izostavljen trenutak → ostali se upisuju, izostavljeni ostaje BEZ ocjene (i bez stare),
     run `failed` s popisom (`1 trenutaka bez ocjene: t4`). Izlaz izvan sheme (ocjena 1,5,
     prazan razlog) → `LlmSchemaError`, poziv neuspio uz plaćene tokene, ništa upisano.
     Testovi: tri testa u „runScore nad fixtureima”.
313. **`score --fake`: lažni LLM iz prompta, deterministički.** Novost = 1 − udio riječi citata
     (≥ 5 slova) koje se pojavljuju u kontekstu ranijih epizoda, konkretnost 0,8 sa znamenkom
     inače 0,3, govornik 0,6 ako je u katalogu inače 0,2. Prolazi istu shemu i brojanje poziva
     (trošak 0). `--fake` čita osobe iz fixturea (bez mreže). Tok:
     `npm run vijesti -- extract <id> --fake --db <d>` pa `npm run vijesti -- score <id> --fake --db <d>`.
     Dokazuje lanac, ne kvalitetu (kao 209).
314. **Popis osoba: snimka u fixtureu, disk cache u radu.** `engine/test/fixtures/persons.json`
     je `GET https://mcp.domovina.ai/api/persons` od 5.11.2026. (83 osobe, 82 različita imena,
     81 u indeksu bez „Nepoznati govornik”). `loadPersons` čita svjež cache
     (`vijesti/.cache/persons/persons.json`, rok 24 h), zatim mrežu (spremi samo odgovor koji
     prolazi shemu), zatim zastario cache; bez ičega baca, jer bi ocjena bez popisa svakom
     govorniku tiho dala nulu. Test: „loadPersons: disk cache i zastario cache”.
315. **Pravi pozivi idu kroz `agy`, a mjerenje F0 je odgođeno (korisnik, 2026-11-06).**
     Vertex je na `bimbo-sync-prod` 28.10. vraćao 403 („terms of use”), a pipeline ga je
     29.10. proglasio DEPRECATED (`fetch.domovina.tv/docs/2026-10-28-vertex-iskljucen-agy-jedini-gemini.md`).
     Korisnik je izabrao `agy` (Antigravity CLI u tmuxu, Gemini na Google AI Pro, $0) i
     rekao da se mjerenje pokreće kasnije, „za nekoliko sati”, a da razvoj ide dalje.
     Posljedice: (a) backend `agy` po uzoru na `fetch.domovina.tv/lib/agy_tmux.js` i
     `npm run eval` se pišu i testiraju bez pravih poziva, a pravo pokretanje je zasebna
     stavka u `TODO.md`; (b) `agy` je serijski (23–124 s po pozivu, izmjereno u pipelineu
     28.10.), pa uzorak od ~40 epizoda (~440 poziva) traje 5–8 h, najbolje noću; (c) `agy`
     ne vraća tokene, pa je trošak po epizodi procjena iz znakova (odluka 305), ne
     mjerenje, i to se u izvještaju piše uz svaku takvu brojku; (d) vrata S3 (F1 da/ne i
     prag ocjene) su odgođena, ne preskočena: S4–S6 rade s privremenim pragom i lažnim
     klijentom, a ništa ne ide na Preview s pravim podacima (S7) dok korisnik nije odgovorio
     na pitanje iz mjerenja. Vertex i AI Studio ostaju u kodu kao izbor (`VIJESTI_LLM_BACKEND`).
     Revizija: kad mjerenje pokaže da je udio vijesti premali za portal.

## S4 (2026-11-06)

400. **Backend `agy` (`VIJESTI_LLM_BACKEND=agy`) po uzoru na `fetch.domovina.tv/lib/agy_tmux.js`.**
     `agy -p` ne vraća odgovor, pa upit ide u datoteku `req-<pid>-<n>-<ms>.md` (odjeljci UPUTA,
     SHEMA, ULAZ), agy u tmuxu dobije jednu rečenicu („Read the file X.md … Write ONLY the
     resulting JSON to the file X.json”) i čeka se da X.json nastane i da mu se veličina
     smiri (dvije provjere u 1,5 s). Prije svakog upita `/clear`; ako ekran i dalje pokazuje
     stari upit (pipeline 29.10.: `/clear` prošao kao tekst), sesija se ubija i diže iznova.
     Vlastita sesija `agyvij` (pipeline: `agyen`, `agyss`, `agyt`; glasovne: `agyg`), cilj
     uvijek s `=` (točno ime, tmux inače radi prefix matching), `execFile` bez ljuske. Radni
     direktorij `~/git/.agy-tmux/<sesija>` kao pipeline (agy pita za povjerenje, prvo pitanje
     se potvrđuje samo). Model `gemini-3.8-flash-high` (zadano u pipelineu), u `runs.model` kao
     `agy:<model>`; timeout 600 s. agy nema `responseJsonSchema` ni temperaturu: shema ide u
     datoteku kao JSON Schema iz iste zod sheme, temperatura se ne prenosi. Pozivi jednog
     klijenta su serijalizirani (red obećanja; greška ne blokira idući). Između procesa NEMA
     brave: istodobno smije raditi samo jedan `npm run eval`. Env: `VIJESTI_AGY_SESSION`,
     `VIJESTI_AGY_MODEL`, `VIJESTI_AGY_DIR`, `VIJESTI_AGY_TIMEOUT_SEC`. Kod: `engine/llm/agy.ts`.
     Revizija: prvi pravi poziv (`npm run eval -- --max-calls 1`); nije isproban s pravim agyjem.
401. **Tokeni agyja su procjena i to piše u bazi.** Ulaz = ⌈znakova datoteke upita / 3⌉
     (uputa + shema + ulaz, odluka 305), izlaz = ⌈znakova izlazne datoteke / 3⌉, `cost_usd = 0`
     (pretplata). `LlmCallRecord.tokensEstimated` i migracija 004 `runs.tokens_estimated
     boolean NOT NULL DEFAULT false` (`OR` po pozivu: jedan procijenjeni poziv označi run).
     Vertex/AI Studio zapisuju `false`. Izvještaj uz svaku takvu brojku piše „PROCJENA iz
     znakova”. Test: „runs.tokens_estimated…”, `db/migrate.test.ts` („004…”).
402. **Izlaz agyja ide kroz isti `parseLlmJson` + zod; ne popravlja se ništa osim omota.**
     Skida se BOM i jedan ograđivač ```` ```json … ``` ```` oko cijelog teksta; proza oko
     objekta se NE reže (pipelineov `parseLoose` reže `{…}`; ovdje bi to bio tihi popravak).
     Sintaksno neispravan JSON nije „još piše”: kad stoji nepromijenjen 20 s, agy dobije kratki
     potez da popravi SAMO sintaksu, najviše dvaput (kao pipeline, `n38M_g__TxQ` 29.10.), pa
     `LlmSchemaError`. JSON koji se parsira ali ne prolazi shemu → `LlmSchemaError` odmah, bez
     popravka (odluka 312). Oba slučaja su neuspio poziv.
403. **Timeout je poziv, nepokrenuta sesija nije.** Bez izlaza do roka: Escape dvaput (da
     zaglavljeni potez ne blokira idući), `AgyTimeoutError` (podklasa novog `LlmTimeoutError`),
     poziv neuspio s procijenjenim ulaznim tokenima. Poruka kaže da i odbijen upit izgleda
     ovako: agy nema `blockReason` (zamka iz `fetch.domovina.tv/docs/2026-10-28-vertex-iskljucen-agy-jedini-gemini.md`).
     agy koji se ne digne u 60 s (prijava, nije instaliran) → `AgyStartError`, sesija ubijena,
     upit nije poslan i ne broji se (kao token u odluci 300).
404. **Testovi agyja nad lažnim slojem `AgyIo`** (tmux + datoteke + virtualni sat): uspjeh s
     pitanjem povjerenja, ograđivač, timeout, ne-JSON s popravkom i bez, JSON izvan sheme,
     dva istodobna poziva (nikad dva upita u letu, greška prvog ne blokira drugi), sesija koja
     se ne digne, `/clear` koji ne očisti. Pravi tmux sloj se testira samo argv-om (ubrizgan
     `exec`): `=agyvij` za sesiju, `=agyvij:` za panel. Test: `engine/llm/agy.test.ts`.
405. **Uzorak po kanalu, deterministički** (`engine/eval/sample.ts`). Listing se slaže po
     datumu (najnovije prvo, pa ID) i dijeli na svježu i stariju polovicu. Svježa daje
     ⌈limit/2⌉ epizoda iz prvih 2 × toliko kandidata, starija ostatak iz 2 × toliko ravnomjerno
     raspoređenih kandidata. Kandidat bez `diarized.srt` (po `episode.json`, inače po
     datoteci) se odbija; među ostalima `words.json` (ili `words.<lang>.json`) ide prvi, inače
     redoslijed listinga. Polovica bez dosta kandidata se puni iz druge. Ista epizoda u dva
     listinga ide u prvi kanal. Obrada ide po kanalu i od starijih prema novijima, jer kontekst
     novosti čita ranije epizode kanala iz baze (odluka 307). Bez `--fake` `--channels` je
     obavezan (52 listinga po CDN-u nisu zadani uzorak). Test: „deterministički; words.json
     ima prednost…”.
406. **Izvlačenje preživi jedan timeout sekcije, ne dva zaredom.** Jedan timeout je vjerojatno
     odbijen upit za tu sekciju: sekcija se broji kao neuspjela (kao `LlmSchemaError`, odluka
     208), ostale se upisuju, run je `failed`. Dva zaredom (`MAX_CONSECUTIVE_TIMEOUTS`) znače
     da agy ne odgovara i izvlačenje baca, jer bi inače svaka sekcija čekala 10 min. Ostale
     greške (HTTP 400, mreža) i dalje bacaju odmah. Test: „jedan timeout = neuspjela sekcija…”.
407. **Eval nastavlja gdje je stao.** Uzorak kanala se sprema (`vijesti.eval_sample`, migracija
     004) i idući put čita iz baze, jer se svježe epizode mijenjaju svaki dan (`--resample` za
     novi). Korak je gotov kad je ZADNJI run tog koraka, videa i verzije prompta `ok`; ocjena je
     gotova kad nijedan prihvaćen trenutak nema ocjenu trenutne verzije. Neuspjeli runovi
     zaredom od zadnjeg uspjeha se broje: nakon `--attempts` (zadano 2) korak se preskače
     („odustalih”). Prekinut proces ostavi run `running`, koji se broji kao neuspjeh.
     Djelomično izvlačenje (neuspjele sekcije) ne ide u ocjenu: idući prolaz ga ponavlja.
     Epizoda koja se ne može pripremiti (nema titla, krivi jezik) se ne pokreće; greška u radu
     se zapiše u log i ide se na iduću. Test: „greška jedne epizode ne ruši uzorak…”,
     „pravi prolaz pa nastavak…”.
408. **Procjena prije poziva i ograda `--max-calls`.** Pozivi i ulazni tokeni izvlačenja su iz
     pravih promptova (`prepareExtract`) uz uputu i shemu; ocjena izvučene epizode iz pravog
     prompta (`prepareScore`), neizvučene iz pretpostavke (1500 tokena konteksta + 2 trenutka
     po sekciji × 120 tokena). Izlaz: 2000 tokena po pozivu izvlačenja, 3000 po ocjeni (uz
     „thinking”). Trajanje: agy 60 s po pozivu (23–124 s u pipelineu 28.10.), Vertex/AI Studio
     15 s (pretpostavka), lažni 0. Trošak: cijena backenda (agy $0) i API-ekvivalent po zadanom
     Vertex cjeniku (odluka 304). Procjena iznad `--max-calls` → exit 3 prije ijednog poziva;
     u radu omot `budgetedLlm` ne šalje poziv preko ograde (exit 3, ponovno pokretanje
     nastavlja). Bez `--fake` i `--dry-run` `--max-calls` je obavezan. Primjer 6.11.2026. na
     pravom CDN-u (samo čitanje): 5 epizoda `mreze_rijeci` → 84 poziva
     (`npm run eval -- --channels mreze_rijeci --dry-run`, rezultat ovisi o danu). Revizija:
     prvi agy uzorak (`sekundi` i tokeni u izvještaju) ispravlja 60 s i 2000/3000.
409. **Prag ocjene je jedna konstanta `NEWS_SCORE_THRESHOLD = 0,5`** u `engine/score/formula.ts`,
     s komentarom „privremeno, odluka 315”. Izvještaj ga čita odatle i piše u zaglavlje da je
     privremen. Revizija: odgovor korisnika nakon mjerenja F0.
410. **`npm run eval -- --fake`: 5 fixturea bez mreže.** Lažni CDN nad `engine/test/fixtures`,
     osobe iz fixturea, kanali fixturea kao zadani (`catholic_futurist`, `domovina_tv`,
     `iva_kraljevic`, `mreze_rijeci`), zasebna baza `.cache/eval-fake.pglite` (nikad ista kao
     pravi uzorak). Lažni LLM je spoj lažnog izvlačenja (209) i ocjene (313) po imenu poziva,
     s tokenima procijenjenim iz znakova i oznakom procjene, pa izvještaj prolazi istu granu
     kao agy. Daje 40 poziva, 70 trenutaka, svi iznad praga: brojke dokazuju tok, ne kvalitetu.
     Test: „pravi prolaz pa nastavak…” (`npm run eval -- --fake --max-calls 40`).
411. **Izvještaj iz baze, uz svaku tablicu naredba koja je reproducira.** `npm run eval:report
     -- [--db …] [--out file.md]` piše Markdown: uzorak, trenuci po epizodi, ishod i razlog
     provjere citata, udio iznad praga, raspodjela ocjena, 10 najboljih i 10 najlošijih
     trenutaka doslovno s `https://domovina.ai/v/<id>/t/<sec>`, dotok i „vijesti dnevno”, trošak
     i trajanje. Svaka tablica ima `npm run eval:report -- --db '…' --query "<SQL>"`; `--query`
     ide u read-only transakciji (DELETE pada). Brojke su izlaz Postgresa (decimalna točka),
     da se poklope s `--query`. „Vijesti dnevno” = Σ po kanalu (epizoda u zadnjih 30 dana iz
     listinga / 30) × (izvučenih epizoda uzorka s barem jednim trenutkom ≥ prag / izvučenih
     epizoda uzorka); pretpostavka je jedna vijest po epizodi (generator S4 piše članak iz
     trenutaka jedne epizode). Dotok se mjeri pri uzorkovanju (`vijesti.eval_channels`).
     Trošak po epizodi: stvarni (agy $0) i API-ekvivalent, oba označena kao procjena kad su
     tokeni procijenjeni; sekunde po pozivu iz `runs.started_at/finished_at`.
412. **Bez ispisa napretka.** Eval ne piše ništa po pozivu (globalno pravilo o tokenima, incident
     30.9.2026.): procjena na početku, jedan redak po obrađenoj epizodi u log (`<db>.log`, TAB:
     vrijeme, video, kanal, ishod izvlačenja, ishod ocjene, poziva, greška) i završni sažetak.
     Pravo pokretanje je odgođeno (odluka 315); naredbe su u `.env.example` i u komentaru
     `engine/cli.ts`: prvo `--dry-run`, pa `VIJESTI_LLM_BACKEND=agy npm run eval -- --channels
     mreze_rijeci,iva_kraljevic,catholic_futurist,domovina_tv --limit 5 --max-calls 500` u
     pozadini, pa `npm run eval:report -- --out docs/research/YYYY-MM-DD-f0-mjerenje.md`.
413. **Format „vijest iz podcasta” ima stilski vodič `docs/stil.md`** (pravila V1–V14, zatvoren
     popis kategorija). Generator (`engine/write/`, `step = write`, `PROMPT_VERSION =
     write-vijest/1`, temperatura 0,3) piše jedan članak iz trenutaka JEDNE epizode. Izlaz po zod
     shemi: `title`, `lead`, `body` (2–24 bloka `{type:'p', text}` ili `{type:'quote', moment:N}`),
     `category` iz popisa. Test: „lažni generator prolazi shemu; verzija 1…”.
414. **Ulaz generatora: prihvaćeni trenuci s ocjenom trenutne verzije ≥ `NEWS_SCORE_THRESHOLD`**,
     najviše 12 (`MAX_WRITE_MOMENTS`, najbolji po ocjeni), u promptu redom snimke kao `t1…tn`
     (kao odluka 306), uz naslov, kanal, datum iz listinga i govornike iz `summary.json`. Epizoda
     bez trenutka iznad praga nema članak, poziv ni `runs` zapis; eval to bilježi kao `write=none`.
     Test: „epizoda bez trenutka iznad praga: nema članka, poziva ni runa”. Revizija: prag (409).
415. **Vodič i sistemska uputa se drže usklađenima testom.** `SYSTEM_PROMPT` sažima svako pravilo
     pod istom oznakom V1–V14; test pada kad se oznake ili kategorije razlikuju ili kad se
     `docs/stil.md` promijeni, a `STIL_SHA256` u `engine/write/prompt.ts` nije osvježen. Promjena
     pravila uz to traži novi `PROMPT_VERSION`. Test: „stil.md i sistemska uputa su usklađeni”.
416. **Kategorije: zatvoren popis od deset slugova** (`politika`, `gospodarstvo`, `vjera`,
     `zdravlje`, `obrazovanje`, `znanost-tehnologija`, `kultura`, `sport`, `svijet`, `drustvo`),
     redom prednosti kad tema pripada dvjema; bira se po temi glavne tvrdnje. Shema odbija ostalo
     (`LlmSchemaError`, ništa upisano). Baza drži samo oblik sluga (CHECK), popis je u kodu i vodiču,
     da nova kategorija ne traži migraciju. Test: „izlaz izvan sheme (kategorija izvan popisa)…”.
417. **Citat je referenca na `moments.id`, nikad tekst modela.** Blok `quote` nosi `moment_id` i
     oznaku `ref`; tekst citata, ime govornika i vrijeme pri prikazu (`body`, nacrti) dolaze iz
     `moments`. U odlomcima nema navodnika (V5); prepričana izjava nije citat. Test: isti kao 413
     (`body` sadrži „moments.quote” za svaki citat-blok).
418. **Duljina 300–500 riječi se mjeri, ne prisiljava.** Broje se riječi leada, odlomaka i citata
     kako se prikazuju (naslov ne), broj s razdjelnikom (`8,000`) je jedna riječ. Izvan raspona
     članak se sprema, `word_count` i `verify.word_range.ok = false` ga označe za urednika; nema
     ponovnog poziva (svaki troši kvotu). Revizija: ako pravi prolaz često promaši raspon.
419. **Jedna priča po epizodi dok nema grupiranja (S9):** `stories.slug = video-<videoId>`, članak
     `format = 'vijest'`, `lang = 'hr'`, slug `<naslov prve verzije, do 60 znakova>-<videoId>`
     (jedinstven i kad se naslovi poklope; ID zadržava velika slova). Revizija: S9 (priča iz više
     epizoda).
420. **Engleska epizoda: članak na hrvatskom, citat ostaje izvorni.** Citat-blok upućuje na
     engleski `moments.quote` i prikaz piše „izvornik (en), ne prijevod”; prijevod se nikad ne
     stavlja u navodnike (V13), pa ga provjera citata (426) ukloni ako se pojavi. Za preklapanje
     (430) se uz citat broji i `moments.claim` (hrvatski sažetak), inače bi svaka hrvatska
     rečenica engleske epizode bila nepodržana.
421. **Migracija 005: strukturirana verzija.** `article_versions` dobiva `lead`, `category`,
     `content jsonb` (epizoda, naslov, lead, blokovi), `word_count`, `prompt_version`, `verify
     jsonb`; CHECK da su `content`, `lead`, `category`, `word_count` svi postavljeni ili svi NULL
     (urednička verzija bez strukture smije postojati) i da `verify` traži `content`. `body` ostaje
     čitljiv tekst. Test: `db/migrate.test.ts` („005…”).
422. **Verzije su nepromjenjive; svaka generacija i svaka izmjena je nova stavka.** `write` piše
     verziju n+1 (`created_by = engine:write`, `run_id`, `prompt_version`); `verify` UVIJEK piše
     novu verziju (`engine:verify`, i kad ništa ne ukloni) s rezultatom u `verify`. Izvori
     (`article_sources`) = svi trenuci iz prompta, `position` = broj iza „t”; verify ih prenosi.
     Ponovno izvlačenje ne briše trenutke na koje se verzija poziva (odluka 207, `ON DELETE
     RESTRICT`). Citat-blok na `tN` koji ne postoji sprema se s `moment_id = NULL`, a briše ga tek
     verify (423). Test: isti kao 413 (druga generacija = verzija 2), „lažni provjeravatelj…”.
423. **Politika verifyja: automatski se uklanja samo ono što je mehanički krivo.** Rečenica s
     tekstom u navodnicima koji nije doslovan citat izvora (`quote_not_verbatim`) i citat-blok bez
     trenutka ili s trenutkom izvan izvora verzije (`quote_ref_missing`, `quote_ref_not_source`)
     se brišu i zapisuju u `verify.removed` s tekstom. Tvrdnja bez potpore, krivo ime, krivi broj
     i malo preklapanje OSTAJU, označeni `unsupported` s razlozima, za urednika. Naslov se nikad ne
     briše, samo označi. Test: „provjeravatelj laže „podržano t1”…”.
424. **Lažni generator i provjeravatelj su deterministički iz prompta.** `write --fake` slaže
     vijest od riječi citata najbolje ocijenjenih trenutaka (dva citat-bloka, 300–500 riječi);
     `verify --fake` uz rečenicu stavlja trenutak s najviše zajedničkih osnova (barem dvije),
     inače podatke o epizodi. `lyingVerifyResponse` (testovi) kaže „podržano t1” za sve. Isti
     `parseLlmJson` i brojanje poziva (`createResponderLlm`). Dokazuju tok, ne kvalitetu (kao 313).
425. **Tok bez mreže kroz CLI:** `npm run vijesti -- write <videoId> --fake --db <d>` pa
     `npm run vijesti -- verify <articleId|videoId> --fake --db <d>` (broj = ID članka, inače ID
     videa; verify čita samo bazu, metapodaci epizode su snimljeni u `content.episode`). Test:
     „extract → score → write → verify, sve --fake…”.
426. **Verify: LLM sloj** (`step = verify`, `PROMPT_VERSION = verify-article/1`, temperatura 0):
     rečenice naslova, leada i odlomaka numerirane `s1…sn` (citat-blokovi nisu rečenice; provjereni
     su referencom), za svaku `supported_by` (brojevi `t`), `metadata` (rečenica govori samo o
     epizodi) i `reason`. Nepostojeći ili ponovljen broj rečenice → `VerifyMismatchError`, run
     `failed`, nema nove verzije (kao 312); izostavljena rečenica = `verifier_omitted`;
     nepostojeći `t` u `supported_by` se odbacuje uz `unknown_moment_ref`. Verzija rezultata
     `verify-article/1+d1`. Test: „nepostojeća rečenica u izlazu…”.
427. **Normalizacija citata: samo razmaci, NFC i oblik navodnika/apostrofa** (`normalizeQuote`).
     Interpunkcija i velika slova ostaju, pa „rečeno” ≠ „rečeno.”. Usporedba je jednakost s
     `moments.quote` cijelog trenutka izvora, ne podniz: djelomičan citat u navodnicima se briše,
     jer V5 navodnike u odlomcima ionako zabranjuje. To nije `verify/normalize.ts` (citat prema
     titlu). Test: „citat: normalizacija samo razmaka i oblika navodnika”.
428. **Imena: niz od barem dvije riječi velikim početnim slovom** (titule iz `NAME_TITLES` se
     preskaču, zarez/dvotočka prekidaju niz) mora se naći u imenima govornika, entitetima i
     citatima podupirućih trenutaka ili u metapodacima epizode. Riječ je isto ime u drugom padežu
     kad dijeli početak od barem min(duljina) − 1 i 3 slova (`Horvatu`/`Horvat`, ne
     `Marko`/`Marija`); na početku rečenice prva riječ smije biti obična („Prema Ivanu Horvatu”).
     Tvrdnje (`claim`) ne ulaze: to je tekst modela. Ne provjerava se: pojedinačna riječ velikim
     slovom usred rečenice (mjesto, ustanova) i ime s promjenom osnove (`Petar`/`Petra` da lažnu
     uzbunu). Test: „imena: padeži da…”. Revizija: druga faza S4 (adversarijalni testovi).
429. **Brojevi: znamenke (razdjelnik tisućica `.`, `,` ili razmak ispred točno tri znamenke,
     decimalni zarez) i brojevi riječima od „dva” naviše, hrvatski i engleski, sa složenicama
     („dvadeset pet”, „tri milijuna”).** „Jedan” se ne broji („jedan od”). Broj rečenice mora biti
     među brojevima citata, imena i entiteta podupirućih trenutaka ili metapodataka (datum objave
     daje dan, mjesec i godinu); korpus uključuje i sastavnice (3 i 3000000). Poznata rupa: dan
     ili mjesec iz datuma prođe i kad je napisan krivi datum. Test: „brojevi: …”.
430. **Preklapanje: udio sadržajnih osnova rečenice (riječi od 4+ slova bez dijakritike, prvih 5
     slova, bez riječi izvještavanja „kaže/prema riječima/podcast/epizoda”) koje postoje u
     podupirućim trenucima (citat, tvrdnja, govornik, entiteti) i metapodacima.** Ispod
     `MIN_LEXICAL_OVERLAP = 0,4` rečenica je `low_overlap` i kad je LLM označi podržanom; rečenica
     s manje od 3 osnove nema sud. Gleda se samo kad LLM tvrdi potporu. Privremeno: izmišljena
     tvrdnja u testu ima 0, ispravno prepričavanje oko 1. Test: „preklapanje…”, „provjeravatelj
     laže…”. Revizija: druga faza S4 i prvi pravi prolaz.
431. **Stil se provjerava kao upozorenje, ne kao potpora.** Upitnik/uskličnik/navodnici u naslovu,
     mamci, mišljenje, superlativ izvan navodnika, prvo ili drugo lice, emoji i riječ velikim
     slovima koje nema u izvoru idu u `verify.style`; ništa se ne briše i status rečenice se ne
     mijenja. Na lažnom generatoru se javlja `first_person` (riječi citata prepisane bez navodnika).
432. **Rezultat verifyja je strukturiran** (`article_versions.verify`): `version`, `base_version`,
     `run_id`, pravila (prag preklapanja, duljina osnove), `word_count` i raspon, po rečenici
     `n`, dio, blok, tekst, `status`, `supported_by` (`moments.id`), `metadata`, `overlap`,
     `problems[{code, detail}]`, zatim `removed`, `style` i `summary`. Rečenica je `supported`
     samo kad LLM navede valjan trenutak ili metapodatke I nema nijednog problema.
433. **Izostavljen ili netočan izlaz provjere se nikad ne popravlja tiho** (kao 312): presuda se
     ne nagađa ni za izostavljene rečenice, a nepostojeći trenutak se ne preslikava na drugi.
434. **`npm run eval` piše članak i provjeru nakon ocjene.** Korak `write` je gotov kad je zadnji
     `write` run trenutne verzije `ok` (ili `none` bez trenutka ≥ praga); `verify` kad je `ok`
     zadnji `verify` run NOVIJI od tog članka; neuspjeli se broje kao u 407 (`--attempts`).
     Članak samo nad potpuno ocijenjenom epizodom. Procjena (dopuna 408): +1 poziv za članak (pravi
     prompt kad je ocjena gotova, inače 800 + 150 po trenutku do 12, uz pretpostavku da epizoda
     dobiva članak) i +1 za provjeru (isto + 1300 tokena članka); izlaz 2500 i 2000 tokena. Log
     dobiva `write=` i `verify=`. Na 5 fixturea: 50 poziva (40 + 5 + 5), 5 nacrta, nastavak 0
     poziva: `npm run eval -- --fake --max-calls 50`. Ocjena promijenjena nakon članka ne piše
     novi članak sama (revizija kad ocjena dobije `f2`). Test: „pravi prolaz pa nastavak…”.
435. **Izvoz nacrta: `npm run eval:drafts -- [--fake] [--db …] [--out file.md]`.** Zadnja verzija
     svakog članka: naslov, epizoda s linkom, verzija i autor, kategorija, broj riječi i raspon,
     sažetak provjere, lead, tijelo s citatima iz `moments.quote` uz ime, vrijeme i
     `https://domovina.ai/v/<id>/t/<sec>`, zatim označene rečenice s razlozima, uklonjeno i stil.
     Uz sažetak, epizode uzorka bez nacrta i svaki članak naredba `npm run eval:report -- --db …
     --query "…"` koja reproducira brojke (kao 411). Test: „pravi prolaz pa nastavak…” (5 nacrta,
     naredba sažetka daje istu tablicu).

## S5 (2026-11-06)

500. **API je Postgres, ne edge funkcija.** Čitanje: PostgREST nad shemom `vijesti` uz RLS.
     Pisanje urednika: `SECURITY DEFINER` funkcije (Supabase ih izlaže kao `rpc`) sa
     `SET search_path = vijesti, pg_temp`, koje same provjere ulogu, dopušteni prijelaz i
     uvjete, u jednoj transakciji. Pravilo iz korijenskog `CLAUDE.md` („kroz RLS”) to dopušta;
     isto ponašanje na PGliteu i Supabaseu, nema Deno koda. Edge funkcija dolazi tek kad
     prijelaz treba nuspojavu izvan baze (S7: purge CDN-a, ping sitemapa), i tada zove istu SQL
     funkciju. Izlaganje sheme `vijesti` u PostgREST-u (Supabase API settings) je posao S7.
     Kod: `db/migrations/006_editorial.up.sql`, `db/editorial.ts`. Test: cijeli
     `db/editorial.test.ts` (ista SQL na PGliteu).
501. **Identitet bez sheme `auth`.** `vijesti.current_user_id()` čita
     `current_setting('request.jwt.claims', true)::jsonb ->> 'sub'` (isto što `auth.uid()`);
     vrijednost koja nije UUID daje NULL, ne grešku. Test: „bez uloge nema prijelaza…”.
502. **Migracija 006 uvjetno stvara `anon`, `authenticated`, `service_role` (NOLOGIN,
     `service_role` uz BYPASSRLS); `down` ih ne dira.** Na Supabaseu postoje i nisu naše, a uloga
     je objekt klastera, ne sheme: brisanje bi srušilo druge baze ili tuđa prava. `down` samo
     oduzima prava na shemi. Test: `db/migrate.test.ts` („006: uloge…”).
503. **Uloge u `vijesti.staff` (`editor` | `admin`), `admin` ima sva prava urednika.**
     `vijesti.has_role(text)` (SECURITY DEFINER, STABLE). Prvog admina upisuje vlasnik baze
     izravno (SQL kao `postgres`/`service_role`); dalje `set_staff_role`, `remove_staff`,
     `allow_channel`, `disallow_channel` (samo admin). Zadnji admin se ne može ukloniti ni
     spustiti (`last_admin:`). Korisnik vidi svoj redak u `staff`, urednik sve. Test: „admin
     vodi uloge; zadnji admin ostaje”.
504. **Stroj stanja je tablica `article_transitions` i okidač `BEFORE UPDATE OF status` koji vrijedi
     i za vlasnika baze.** Dodan `retracted` (zadržan `rejected`), 12 prijelaza iz plana S5.
     Okidač brani i invarijante (`approved` ⇒ `approved_version_id`, `published`/`corrected` ⇒
     `published_version_id`). Nepoznato stanje prepušta CHECK-u (`articles_status_check`, test iz
     001 ostaje). `authenticated` nema UPDATE ni na jednoj tablici: jedini put su funkcije.
     `transition_article` radi samo prijelaze u `review`, `draft`, `rejected` (odbijanje traži
     obrazloženje); odobravanje, objava, ispravak i povlačenje imaju svoje funkcije s uvjetima.
     `INSERT` članka okidač ne ograničava (članke stvara samo engine, kao `draft`). Test:
     „nedopušteni prijelazi se odbijaju, i vlasniku”.
505. **Dnevnik `article_events` piše okidač, ne funkcija.** Svaka promjena stanja (i vlasnikova)
     ostavlja redak s `actor` (uuid ili NULL), `actor_label` (`editor:<uuid>`, `engine:verify`,
     `db:<uloga>`), verzijom i bilješkom; funkcije kontekst predaju kroz lokalne postavke
     transakcije `vijesti.event_*` i odmah ih brišu. Nastanak članka (verzija 1) je redak
     `NULL → draft` s `created_by` verzije. Samo dodavanje: UPDATE, DELETE i TRUNCATE odbija
     okidač i vlasniku (`append_only:`). Iznimka je brisanje cijelog članka (CASCADE nosi i
     dnevnik), jer bi inače članak s ijednim retkom dnevnika bio neizbrisiv; brisanje članka je
     vlasnikova operacija, klijent nema DELETE. Test: sretni put, „dnevnik je samo za
     dodavanje…”, test iz 001 koji briše članak.
506. **Odobrava se verzija, ne članak.** `articles.approved_version_id` i `published_version_id`
     sa složenim FK-om `(id, x) → article_versions (article_id, id)`: tuđa verzija je nemoguća.
     `approve_article(članak, verzija)` traži da je verzija ZADNJA (`stale_version:`) i spremna:
     `verify` nije NULL, ima niz `sentences` i `base_version` manji od broja verzije (provjera te
     verzije: engine uvijek piše novu verziju s provjerom sebe), a svaka rečenica koja nije
     `supported` ima razrješenje (`unresolved:` s popisom brojeva). Uklonjeno, stil i raspon
     riječi ne blokiraju (verify uklanja sam, stil je savjet); revizija nakon pravih nacrta.
     Odobrena verzija je zato uvijek verzija `engine:verify`. Verzija se nikad ne mijenja: okidač
     odbija UPDATE (`immutable:`) osim `run_id → NULL` iz FK-a. Test: sretni put, „dnevnik je
     samo za dodavanje…”.
507. **Razrješenje rečenice: `sentence_resolutions (version_id, n)` s `verified` (urednik je
     tvrdnju provjerio u snimci ili drugom izvoru, bilješka kaže gdje) ili `no_claim` (rečenica
     ne iznosi činjenicu).** Bilješka obavezna, `resolved_by` uuid, samo dodavanje
     (`already_resolved:`), samo na zadnjoj verziji koja ima provjeru i samo za rečenicu koju je
     provjera označila. `removed_in_next` nije potreban: nova verzija dobiva svoju provjeru, pa
     razrješenje stare ne vrijedi za nju. Članak s nepotvrđenom rečenicom smije u `review`, ne
     smije u `approved` (preporuka S4). Test: sretni put.
508. **Urednička izmjena: `save_editor_version(članak, bazna_verzija, naslov, lead, kategorija,
     blokovi)` (odstupanje od zadanog potpisa: bez `body` i `content`).** Tijelo i sadržaj računa
     baza iz blokova i `moments` (odluka 417: citat je referenca; `body` napisan rukom bi se
     razišao sa sadržajem); `episode` i `schema` se prepisuju iz prethodne verzije. Izvori: svi
     trenutci prethodne verzije s istim pozicijama + novi citirani trenutci na kraju; citat smije
     samo trenutak iste epizode koji nije `failed` (`invalid_quote:`), `ref` postavlja baza.
     `word_count` je `_word_count` (isti uzorak kao `WORD_RE`; rubni slučaj „11h” se razlikuje
     jer JS uzorak vraća unatrag), a mjerodavan broj dobiva verzija provjere. `created_by` je
     tekst `editor:<uuid>` (ista konvencija kao `engine:*`, bez novog stupca); uuid je i u
     dnevniku. `verify` je NULL, pa se verzija ne odobrava dok engine ne pokrene verify. Izmjena
     je dopuštena u `draft`, `review`, `approved` (okidač vraća u `review`), `published` i
     `corrected` (kandidat za ispravak; javno ostaje stara verzija), nije u `rejected` i
     `retracted`. Test: „urednička verzija: citat samo iz iste epizode…”, sretni put.
509. **Javno čitanje (`anon`, i `authenticated` bez uloge isto):** članci u `published`,
     `corrected`, `retracted`; od verzija samo `published_version_id` objavljenog ili ispravljenog
     članka; za povučen nijedna (vidi se priča s naslovom i obavijest u `corrections`);
     `article_sources` i `moments` samo javne verzije; `stories` i `corrections` javnih članaka.
     Nacrti, `runs`, `staff`, `sentence_resolutions`, `article_events`, `story_moments`, eval
     tablice: ništa. Na `article_versions` prava po stupcu bez `verify`, `run_id`, `created_by`
     (uuid urednika ne smije van), na `corrections` bez `created_by` i `replaced_version_id`.
     Za `select=*` postoje pogledi `public_article_versions` i `public_corrections`
     (`security_invoker = true`). Starije objavljene verzije nisu javne; revizija ako
     transparentnost ispravka zatraži razliku verzija. Test: sretni put, „nova verzija na
     odobrenom članku… povučen članak skriva tijelo”.
510. **Urednik čita pune verzije kroz `editor_article_versions` (prava vlasnika,
     `security_barrier`, filtar `has_role('editor')`),** jer `authenticated` na tablici nema
     `verify`. Red čekanja za verify (S8) je pogled `versions_awaiting_verify`: zadnja verzija sa
     sadržajem bez provjere, članak nije `rejected`/`retracted`; vide ga urednik i engine (uloge
     koje nisu klijentske). Supabaseov linter takve poglede označi („security definer view”):
     namjerno. Test: sretni put (red sadrži točno uredničku verziju; čitatelj nema pravo, korisnik
     bez uloge vidi 0 redaka).
511. **Greške: `RAISE EXCEPTION` (SQLSTATE P0001) s porukom `kod: tekst`.** Kodovi:
     `forbidden`, `not_found`, `invalid_transition`, `invalid_state`, `invalid_input`,
     `invalid_quote`, `stale_version`, `not_verified`, `unresolved`, `already_resolved`,
     `channel_not_allowed`, `last_admin`, `append_only`, `immutable`. Klijent uspoređuje prefiks
     do prve dvotočke (`parseEditorialError`), kao `PinkaClient` u aplikaciji. Greška prava
     (`permission denied`) nije urednička i parser je ne prepoznaje. Test: „parseEditorialError”.
512. **Objava samo s kanala na popisu `allowed_channels`** (plan §3, pristanak kreatora): kanal je
     `content.episode.channel` odobrene verzije, inače `channel_not_allowed:`. Popis vodi admin;
     veza s preuzimanjem kanala je S13. Test: sretni put.
513. **Nova verzija na odobrenom članku ga vraća u `review`** (okidač `AFTER INSERT` na
     `article_versions`, i za engine i za urednika), s retkom dnevnika (`created_by` nove verzije
     kao oznaka) i brisanjem `approved_version_id`. Test: „nova verzija na odobrenom članku…”.
514. **Ispravak: `correct_article(članak, verzija, vrsta, opis)` samo iz `published`/`corrected`,
     za zadnju verziju koja nije već objavljena i spremna je kao kod odobravanja (506).** U jednoj
     transakciji: redak `corrections` (vrsta + opis = što i zašto, `created_at` = kada,
     `created_by` = tko, `version_id` = nova, `replaced_version_id` = dotad objavljena), nova
     `published_version_id`, stanje `corrected`, dnevnik s opisom kao bilješkom. Vrsta
     `retraction` je rezervirana za povlačenje. Javno: `public_corrections`. Test: sretni put.
515. **Povlačenje: `retract_article(članak, razlog)` iz `published`/`corrected`,** redak
     `corrections` vrste `retraction` (dodana u CHECK) s razlogom, `version_id` NULL,
     `replaced_version_id` = objavljena. `published_version_id` ostaje kao interni trag; čitatelj
     ne vidi nijednu verziju. Smije urednik (model uloga nema posebno pravo); revizija ako
     povlačenje treba glavnog urednika. Test: „…povučen članak skriva tijelo”.
516. **RLS je uključen na svim tablicama sheme, prava se prvo oduzimaju pa daju izričito**
     (Supabase može imati zadana prava koja `anon`/`authenticated` daju sve izravno, ne kroz
     PUBLIC; funkcije PostgreSQL inače daje PUBLIC-u). `service_role` dobiva ALL na tablicama
     koje postoje u 006: nova migracija mora sama dati prava, uključiti RLS i dodati politiku
     za svoje tablice. Interne `_` funkcije nemaju EXECUTE ni za koga osim vlasnika; okidači su
     SECURITY DEFINER jer ih okida i `service_role`. Test: sretni put (čitatelj ne poziva
     funkciju), „bez uloge…”.
517. **Svaka funkcija zaključava članak (`FOR UPDATE`), a odobravanje, ispravak, izmjena i
     razrješenje traže id ZADNJE verzije** (optimistička konkurentnost: urednik odobrava točno
     ono što je vidio; između čitanja i odobravanja engine ili kolega može dodati verziju). Test:
     „urednička verzija…” (`stale_version`).
518. **`asUser(db, userId | null, fn)` u `db/editorial.ts`** radi isto što PostgREST: transakcija,
     `SET LOCAL ROLE anon|authenticated`, `set_config('request.jwt.claims', …, true)`; greška
     vraća transakciju. Testovi i budući alati koriste isti put kao klijent. Test: svi u
     `db/editorial.test.ts`.
519. **`vitest` `testTimeout`/`hookTimeout` 20 s.** Prvi PGlite test u datoteci pod punim
     paralelnim opterećenjem traje oko 4,5 s (inicijalizacija WASM-a), tik uz zadanih 5 s; s
     novom datotekom testova `eval` je pucao povremeno (sam traje 1 s). Migracija 006 traje 22 ms
     i nije uzrok. Test: `npm run check` dvaput zaredom zelen.
520. **`006 down` pada kad postoji povučen članak ili ispravak vrste `retraction`** (CHECK iz 001),
     kao `002 down` s podacima: ništa se ne gubi bez traga. Uloge ostaju (502). Test:
     `db/migrate.test.ts` („006: … povučen članak ruši dolje”).
521. **`corrections` i `sentence_resolutions` su samo za dodavanje, i vlasniku baze** (napad S5:
     retci ispravka nisu bili zaštićeni od UPDATE/DELETE, pa je `service_role` ili vlasnik mogao
     tiho prepisati „što i zašto” ispravka; isto za urednikovo jamstvo uz nepotvrđenu rečenicu,
     koje je 507 zvala „samo dodavanje”, a branila ga je samo funkcija). Okidači
     `corrections_append_only` i `sentence_resolutions_append_only` odbijaju UPDATE i DELETE
     (`append_only:`), a `*_no_truncate` TRUNCATE. Iznimka kao u 505: brisanje cijelog članka
     (CASCADE; za `corrections` i UPDATE iz FK-a `version_id → SET NULL` u istoj naredbi), odnosno
     brisanje verzije za razrješenje. Brisanje verzije ispravka bez brisanja članka zato pada
     (FK `SET NULL` bio bi izmjena traga), a zamijenjenu verziju drži FK `replaced_version_id`.
     Test: `db/editorial.adversarial.test.ts` („trag se ne mijenja ni ne briše…”, „iznimka
     505/521…”).
522. **Članak nastaje samo kao `draft`** bez `approved_version_id`, `published_version_id` i
     `published_at` (napad S5: INSERT je primao bilo koje stanje, pa je engine ili vlasnik mogao
     stvoriti objavljen članak mimo stroja stanja; 504 je to svjesno ostavila). Isti okidač
     `articles_status_guard`, sada `BEFORE INSERT OR UPDATE`; nepoznato stanje i dalje prijavljuje
     CHECK. `saveArticleVersion` radi nepromijenjen (`INSERT … ON CONFLICT DO UPDATE` ulazi kao
     nacrt, konflikt ide kroz okidač UPDATE-a). Test iz 001 „šest stanja” provjerava CHECK na
     shemi 005. Test: „INSERT sa stanjem…”, „engine (saveArticleVersion) i dalje radi…”.
523. **Okidač stanja vrijedi za svaki UPDATE članka, ne samo `UPDATE OF status`** (napad S5:
     `UPDATE articles SET published_version_id = <neprovjerena verzija>` bez promjene stanja je
     prolazio, pa je vlasnik ili engine mogao tiho zamijeniti objavljeni tekst bez ispravka, ili
     postaviti `published_version_id = NULL` na objavljen članak). Pravila: `approved_version_id`
     se postavlja samo članku u `review`; `published_version_id` se prvi put postavlja samo
     odobrenom članku i jednak je odobrenoj verziji; poslije se mijenja samo ako postoji redak
     `corrections` (`version_id` = nova, `replaced_version_id` = stara, nije `retraction`);
     `corrected` traži redak ispravka za objavljenu verziju, `retracted` obavijest o povlačenju.
     Funkcije već rade tim redom (redak ispravka prije promjene verzije). Kršenje je
     `invalid_state:`. Test: „objavljena verzija se ne mijenja tiho…”, matrica prijelaza vlasnika.
524. **Javni trenutak je samo onaj koji objavljena verzija CITIRA (blok `quote` u `content`), ne
     svaki među izvorima; javni stupci trenutka bez `run_id`, `score_run_id`, `score*`, `claim`,
     `reject_reason`** (napad S5: izvori verzije su svi prihvatljivi trenutci epizode, a
     `save_editor_version` i verify ih prenose dalje, pa je ispravak koji uklanja netočno pripisan
     citat ostavljao taj trenutak, s imenom govornika, javno čitljivim; uz to su čitatelju bili
     vidljivi `run_id` i ocjena modela). Politika `moments_read` traži `content -> 'blocks' @>
     [{type: quote, moment_id}]`; prava po stupcu kao za `article_versions`, pogled
     `public_moments` za `select=*`. Mijenja dio 509. `article_sources` objavljene verzije ostaju
     javni (samo id-jevi); urednik čita ocjene kroz pogled kad ih zatreba sučelje (S9). Test:
     „svaka relacija sheme…”, sretni put u `db/editorial.test.ts` (broj citiranih trenutaka).
525. **`stories.title` nije javan** (napad S5: naslov priče je naslov prve, generatorove verzije,
     dakle nacrt, i bio je čitljiv uz svaki objavljen i povučen članak). Javni stupci `id`, `slug`,
     `created_at`, `updated_at`, pogled `public_stories`. Povučen članak se čitatelju vidi kroz
     `slug` i obavijest u `public_corrections`; ako portal (S7) treba naslov povučenog članka,
     dobiva ga iz zamijenjene verzije kroz izričit pogled, ne iz `stories`. Svjesno ostaje:
     `articles.slug` je također iz naslova prve verzije (S4, `articleSlug`) i javan je;
     prijedlog za S7 je slug iz odobrenog naslova pri objavi. Mijenja dio 509. Test: „svaka
     relacija sheme…”.
526. **`_nonblank` traži barem jedno slovo ili znamenku (`[[:alnum:]]`)** (napad S5: `btrim`
     skida samo razmak, pa su tabulator, NBSP, zero-width razmak ili crtica prolazili kao
     obrazloženje odbijanja, opis ispravka, razlog povlačenja i bilješka razrješenja). Vrijedi za
     sve funkcije koje ga zovu (i naslov, lead, kanal). Test: „tekstualni argumenti se spremaju
     doslovno…”.
527. **Oznaka `db:<uloga>` u dnevniku je uloga pozivatelja, ne vlasnik funkcije** (napad S5:
     `_actor_label` se zove iz SECURITY DEFINER okidača, gdje je `current_user` vlasnik, pa je
     izravan upis kao `service_role` u dnevniku pisao `db:postgres`, suprotno 505). Sada
     postavka `role` (SET ROLE, kako radi PostgREST), inače `session_user`. Uz to sve funkcije
     sheme, i okidači TRUNCATE koji su bili bez nje, imaju `search_path = vijesti, pg_temp`;
     test čita `pg_proc.proconfig` za svaku funkciju, provjerava da nijedna ne gradi SQL
     dinamički (`EXECUTE`, `format`) i da `anon`, `authenticated`, `service_role` i PUBLIC nemaju
     CREATE na shemi. Test: „service_role (engine) piše…”, „svaka funkcija sheme ima
     search_path…”.
528. **Adversarijalni testovi su zasebna datoteka nad minimalnom bazom**
     (`db/editorial.adversarial.test.ts`, bez generatora), da svako stanje i svaki trenutak bude
     pod kontrolom testa: svih 49 parova stanja kroz funkcije i izravno kao vlasnik (prolazi točno
     tablica, isto stanje je no-op bez dnevnika), `authenticated` bez UPDATE/INSERT/DELETE/TRUNCATE
     ni na jednoj tablici, svaka relacija sheme kao `anon` i kao prijavljeni bez uloge (nova
     relacija bez očekivanja ruši test), curava `pg_temp` funkcija u WHERE, EXECUTE po ulozi za
     svaku funkciju, lažan `sub`, eskalacija uloga, zastarjele verzije, SQL injection. Nad
     migracijom iz `66d510a` (`git show 66d510a:vijesti/db/migrations/006_editorial.up.sql`, isto za `down`) pada 8 od 19 testova. Svjesno nepokriveno: istodobni prijelazi
     (PGlite ima jednu vezu; zaključavanje je `FOR UPDATE`, 517) i `anon` s potpisanim `sub`
     urednika (traži JWT tajnu; tko je ima, potpisuje i `authenticated`).

## S6 (2026-11-06)

600. **Portal je dio istog npm paketa** (`vijesti/portal/`, ovisnosti u `vijesti/package.json`, jedan
     `npm ci`). Portal uvozi čiste funkcije iz `engine/` (`clock`, `hrDate`, tipovi sadržaja) i
     `db/editorial.ts` (`parseEditorialError`) umjesto kopija; poseban paket bi tražio objavu ili
     workspace samo za to. Astro 7.4 + `@astrojs/cloudflare` 14 (`output: 'server'`, `base: '/vijesti'`,
     `session: false`, `imageService: 'passthrough'` da adapter ne traži KV ni Images binding).
601. **Rute:** `/vijesti/` (najnovije istaknuto + po kategorijama), `/vijesti/kategorija/<slug>`,
     `/vijesti/<slug>` (članak; slug je `articles.slug`, stabilan i kad urednik promijeni kategoriju),
     `/vijesti/admin`. Povučeni članci nisu na popisima.
602. **Metapodaci epizode dolaze iz `content.episode` objavljene verzije** (naslov, kanal, datum su
     snimka pri pisanju, odluka 417), ne iz `info.json` pri renderu: nula dodatnih zahtjeva i isti
     podaci koje je urednik odobrio. S CDN-a se čita samo `episode.json` (popis datoteka, 603).
603. **PostgREST klijent (`src/lib/rest.ts`) je jedini put do baze**, isti za produkciju i shim:
     `apikey`, `Authorization: Bearer <jwt ili anon>`, `Accept-Profile`/`Content-Profile: vijesti`.
     Javne stranice uvijek idu kao `anon` (RLS skriva nacrte), bez embeddinga (dva upita umjesto
     `select=…(…)`), prekid 4 s, greška = 503 `no-store`.
604. **Lokalni PostgREST-shim** (`portal/dev/rest-shim.ts`) nad PGliteom: samo podskup (popis
     relacija i rpc funkcija s tipovima argumenata, filteri eq/neq/gt/gte/lt/lte/in/is, order, limit,
     offset), identifikatori po regexu, vrijednosti kao parametri, svaki zahtjev kroz `asUser`,
     zahtjevi u redu (PGlite ima jednu vezu). Greške u obliku PostgREST-a (P0001 → 400, 42501 → 401
     anon / 403 prijavljen, 406 bez profila). Služi i lažni CDN nad `engine/test/fixtures`, medij
     isječka je tišina (e2e bez mreže). Seed (`portal/dev/seed.ts`, < 1 s) ide kroz postojeće `--fake`
     LLM-ove i rpc funkcije: objavljen, ispravljen, povučen, u pregledu s neriješenom rečenicom,
     odobren; urednik i admin u `staff`, kanali u `allowed_channels`. `POST /__shim/reset` = novi seed.
605. **Isječak:** `<audio controls preload="none">` sa `<cdn>/data/<id>/<datoteka>#t=<od>,<do>`.
     `audio.mp3` postoji samo za audio epizode (data_service.dart `resolveMedia`); za video epizode
     isječak pušta `video_h264.mp4` (H.264/AAC, `<audio>` svira zvučni zapis). Datoteka se bira iz
     `episode.json` `files`; bez popisa (404, prekid 1,5 s) nema playera, ostaje poveznica u
     aplikaciju. Vrijeme citata vodi na `domovina.ai/v/<id>/t/<sek>`, „Poslušaj cijeli razgovor”
     na prvi citat. Sve baze su iz konfiguracije (`src/lib/config.ts`, wrangler `vars`).
606. **Lažna prijava samo uz `VIJESTI_AUTH_MODE=local` pri buildu.** `astro.config.mjs` zamjenjuje
     `__VIJESTI_AUTH_MODE__` konstantom; grana `local` i modul `auth-local` ispadaju iz produkcijskog
     builda (nepoznata vrijednost ruši build). Lokalni token je nepotpisan (`alg: none`): prihvaća ga
     samo shim, pravi PostgREST provjerava potpis JWT tajnom i odbija ga, pa ni build u krivom načinu
     ne daje pristup produkciji. Produkcija: supabase-js (poveznica e-poštom, Google), JWT ide u
     PostgREST, uloga se čita iz `staff`. Test: `portal/test/build.test.ts` (produkcijski build bez
     oznake, lokalni s njom).
607. **Admin je ljuska + vanilla TS u pregledniku** (`src/scripts/admin/`): poslužitelj ne vidi JWT,
     podaci idu izravno u PostgREST, DOM samo kroz `textContent`. Radnje šalju id zadnje verzije
     (odluka 517); greške se prikazuju po prefiksu koda (`src/lib/errors.ts`).
608. **Cache-Control:** popisi `max-age=60, s-maxage=300, swr=600`, članak `max-age=60, s-maxage=600,
     swr=3600`, 404 `s-maxage=60`, greška i admin `no-store` (+ `X-Robots-Tag: noindex`). Odgovor
     Workera Cloudflare sam ne cachira: rubni cache (Cache API ili pravilo) i purge pri ispravku su S7.
609. **Izgled:** tokeni iz brenda (navy #002F6C, crvena #FF0000, krem #FAF7F2, tamna #111318/#E2E2E9),
     `prefers-color-scheme`, mobile first, CSS inline (`inlineStylesheets: 'always'`). Fontovi
     self-hostani pod `/vijesti/fonts/`: Inter 400/600 kao woff2 (konverzija srezanog Intera iz
     aplikacije), Playfair Display Bold kao NEIZMIJENJEN ttf (OFL Reserved Font Name, isto pravilo kao
     u aplikaciji), preload naslovnog fonta, `font-display: swap`.
610. **Povučen članak:** stranica 200 + `noindex`, naslov „Članak je povučen”, datum i razlog iz
     `public_corrections`, bez teksta i bez naslova nacrta (odluka 525).

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

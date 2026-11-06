# Nacrti vijesti iz podcasta

Generirano 2026-11-06T09:31:16.425Z iz baze `.cache/eval-fake.pglite`. Prag ocjene 0.5 je PRIVREMEN (odluka 315); raspon riječi 300–500 (docs/stil.md V10). Citati su umetnuti iz `moments.quote`; generator ih ne piše (odluka 417).

## Sažetak

Nacrta: 5.

| clanak | prica | verzija | autor | kategorija | rijeci | recenica | podrzanih | nepodrzanih | uklonjeno | stil |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | video-x3w2BVZJ9vQ | 2 | engine:verify | vjera | 321 | 9 | 9 | 0 | 0 | 0 |
| 3 | video-MGLq9v3AtvE | 2 | engine:verify | znanost-tehnologija | 328 | 8 | 8 | 0 | 0 | 3 |
| 5 | video-b-nls1ck8EE | 2 | engine:verify | vjera | 344 | 8 | 8 | 0 | 0 | 1 |
| 7 | video-P9sLks-f2mQ | 2 | engine:verify | vjera | 328 | 6 | 6 | 0 | 0 | 4 |
| 9 | video-pIx_7N-6HJ4 | 2 | engine:verify | vjera | 334 | 9 | 9 | 0 | 0 | 5 |

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT a.id AS clanak, s.slug AS prica, v.version AS verzija, v.created_by AS autor, v.category AS kategorija, v.word_count AS rijeci, (v.verify->'summary'->>'sentences')::int AS recenica, (v.verify->'summary'->>'supported')::int AS podrzanih, (v.verify->'summary'->>'unsupported')::int AS nepodrzanih, (v.verify->'summary'->>'removed')::int AS uklonjeno, (v.verify->'summary'->>'style')::int AS stil FROM vijesti.articles a JOIN vijesti.stories s ON s.id = a.story_id JOIN vijesti.article_versions v ON v.article_id = a.id AND v.version = (SELECT max(x.version) FROM vijesti.article_versions x WHERE x.article_id = a.id) WHERE a.format = 'vijest' ORDER BY a.id"`

## Epizode uzorka bez nacrta

_(nema redaka)_

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT e.video_id, e.channel AS kanal, (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.quote_check <> 'failed') AS prihvacenih, (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.score_version = 'score-moments/1+f1') AS ocijenjenih, (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.score_version = 'score-moments/1+f1' AND m.score >= 0.5) AS iznad_praga FROM vijesti.eval_sample e WHERE NOT EXISTS (SELECT 1 FROM vijesti.stories s WHERE s.slug = 'video-' || e.video_id) ORDER BY e.channel, e.video_id"`

## Fr. Michael Kong u podcastu Catholic Futurist: So so our followers at the

- Epizoda: Should Future Priests Be TikTok Creators? | Catholic Futurist · Catholic Futurist · 11. kolovoza 2026. · https://domovina.ai/v/x3w2BVZJ9vQ
- Članak 1, verzija 2 (engine:verify, verify-article/1+d1), kategorija `vjera`
- Riječi: 321 (u rasponu)
- Provjera: 9 rečenica, podržanih 9, nepodržanih 0, uklonjeno 0, stilskih napomena 0

**Fr. Michael Kong govorio je u epizodi podcasta Catholic Futurist objavljenoj 11. kolovoza 2026. o temi: So so our followers at the moment is like TikTok is 8,000 and Instagram.**

Prema riječima govornika Fr. Michael Kong, So so our followers at the moment is like TikTok is 8,000 and Instagram is 3,500 but without any hashtag or any advertisement type of thing.

> „So, so our followers at the moment is like, TikTok is 8,000 and Instagram is 3,500, but without any hashtag or any advertisement type of thing.”
> – Fr. Michael Kong, 6:33 · https://domovina.ai/v/x3w2BVZJ9vQ/t/393 · izvornik (en), ne prijevod

Prema riječima govornika Fr. Michael Kong, But currently because it's all short attention so like within three seconds how can we catch people's eyes so that they can actually try to oh okay try.

> „But currently, because it's all short attention, so like within three seconds, how can we catch people's eyes so that they can actually try to, oh, okay, try to listen to.”
> – Fr. Michael Kong, 3:41 · https://domovina.ai/v/x3w2BVZJ9vQ/t/221 · izvornik (en), ne prijevod

Prema riječima govornika Fr. Michael Kong, I'm not sure because recently I also went back to Korea and met other formators in a different diocesan seminary and I was surprised amazed at during the.

Prema riječima govornika Fr. Michael Kong, I don't really worry about okay whether this evangelization or spreading the gospel is successful or not on that because even Jesus himself there were five thousand people.

Prema riječima govornika Fr. Michael Kong, So he goes to the marketplace talks to people and obviously there's a lot of noise and different things but people come didn't like it left.

Prema riječima govornika Fr. Michael Kong, I think there was also kind of debate or sharing opinion I would say that whether this AI technology is helpful for those artists to create their work.

Prema riječima govornika Fr. Michael Kong, like media type rather than paintings or any other things because I found that there's a few filmmakers try to explain and try to share their opinions and.

### Provjera

Bez napomena.

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x WHERE v.id = 2 AND x->>'status' = 'unsupported'"`

## Matija Stepanić u podcastu DOMOVINA: Pa ne znamo znači kad će

- Epizoda: cc_01 | Building a Real-Time Event Ticketing App: Senko Rašić & Matija Stepanić (CroAI Code Club) · DOMOVINA · 26. veljače 2026. · https://domovina.ai/v/MGLq9v3AtvE
- Članak 3, verzija 2 (engine:verify, verify-article/1+d1), kategorija `znanost-tehnologija`
- Riječi: 328 (u rasponu)
- Provjera: 8 rečenica, podržanih 8, nepodržanih 0, uklonjeno 0, stilskih napomena 3

**Matija Stepanić govorio je u epizodi podcasta DOMOVINA objavljenoj 26. veljače 2026. o temi: Pa ne znamo znači kad će se to dogoditi ali ideja je da znači.**

Prema riječima govornika Matija Stepanić, Pa ne znamo znači kad će se to dogoditi ali ideja je da znači ovaj event će trajati negdje negdje do 8 9 koliko će imati smisla Jer.

> „Pa, ne znamo, znači, kad će se to dogoditi, ali ideja je da, znači, ovaj event će trajati negdje, negdje do 8, 9, koliko će imati smisla. Jer realno, aplikacija kao takva je, ono, izmišljena, pa onda u stvari samo idemo vidjeti što možemo, kako da može Claude, ono, automatizirano pokretati”
> – Matija Stepanić, 4:58 · https://domovina.ai/v/MGLq9v3AtvE/t/298

Prema riječima govornika Matija Stepanić, koliko godina kad je još bio ono najobičniji nekakav autocomplete u VS Codeu i to je u stvari bio početak nekakvog AI-assisted codinga Danas jedni druge kopiraju to.

> „koliko godina, kad je još bio, ono, najobičniji nekakav autocomplete u VS Codeu, i to je u stvari bio početak nekakvog AI-assisted codinga. Danas jedni druge kopiraju, to je nekakva mrtva utrka svih tih LLM-ova, par velikih kompanija, i realno, oni jedni druge prekopiravaju, što se vidjelo prije godinu dana kad”
> – Matija Stepanić, 5:56 · https://domovina.ai/v/MGLq9v3AtvE/t/356

Prema riječima govornika Matija Stepanić, na vidjelo Zato jer nismo ono uložili sad da bi ono ubacili Jedino što imamo pustio sam na neki research jedan chat kao nek se napravi evo to.

Prema riječima govornika Matija Stepanić, eura I ono što je evo zadnji session što je u stvari isto dobro pitanje Tko od vas ne razumije ovo tu Ili nikad nije vidio i nikad.

Prema riječima govornika Matija Stepanić, Tako je ali stack overflow je na kraju bio ono progooglaj pronađi probaj koliko ima upvoteova pokreni pa mi ne radi pa Copy-paste Copy-paste da Ali na kraju.

Prema riječima govornika Senko Rašić, link na GitHub page možete isto to downloadati probati raditi pull requestove i slično Tko se to ne da može nam dovikivati promptove šta da mi probamo ili.

### Provjera

- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x WHERE v.id = 4 AND x->>'status' = 'unsupported'"`

## Goran Jeras u podcastu DOMOVINA: jer imao sam nešto iskustva s

- Epizoda: #002 - Zadruge i budućnost bankarstva - Goran Jeras (ZEF i EEB) i Matija S. - 13.3.2026. - [Podcast] · DOMOVINA · 26. ožujka 2026. · https://domovina.ai/v/b-nls1ck8EE
- Članak 5, verzija 2 (engine:verify, verify-article/1+d1), kategorija `vjera`
- Riječi: 344 (u rasponu)
- Provjera: 8 rečenica, podržanih 8, nepodržanih 0, uklonjeno 0, stilskih napomena 1

**Goran Jeras govorio je u epizodi podcasta DOMOVINA objavljenoj 26. ožujka 2026. o temi: jer imao sam nešto iskustva s programiranjem s razumijevanjem kako tehnologija softverska tehnologija funkcionira.**

Prema riječima govornika Goran Jeras, jer imao sam nešto iskustva s programiranjem s razumijevanjem kako tehnologija softverska tehnologija funkcionira Međutim onda kako se razvijala kako je došla ona financijska kriza 2008 i 2009.

> „jer imao sam nešto iskustva s programiranjem, s razumijevanjem kako tehnologija, softverska tehnologija funkcionira. Međutim, onda kako se razvijala, kako je došla ona financijska kriza 2008. i 2009. godine, onda sam se počeo baviti bankarskim rizicima i tu sam prvi put počeo shvaćati, razumijevati što se događa ispod haube”
> – Goran Jeras, 4:31 · https://domovina.ai/v/b-nls1ck8EE/t/271

Prema riječima govornika Goran Jeras, iz koje je originalno došla štednja banka ne zna da je to taj već posuđeni novac Banka to vidi kao novi novac Znači banka sad odjednom misli da.

> „iz koje je originalno došla štednja, banka ne zna da je to taj već posuđeni novac. Banka to vidi kao novi novac. Znači, banka sad odjednom misli da u opticaju postoji, ako je ono inicijalno bilo 100 kuna ili eura, i sad su te 100 kuna napravile krug, banka kad ponovo dobije od treće osobe novi depozit, misli da je to novih 100 eura i da sad ima 200”
> – Goran Jeras, 11:08 · https://domovina.ai/v/b-nls1ck8EE/t/668

Prema riječima govornika Goran Jeras, špekulativnije fondove ili kripto Međutim nekako vrlo malo ljudi uopće zna što je to novac ako se gleda sama neka ono ljudi novac doživljavaju kao vrijednost doživljavaju ga.

Prema riječima govornika Goran Jeras, Počeli smo definirati pravila toga i definiranjem pravila toga smo došli do toga što danas imamo Međutim trebamo biti svjesni da je to kao i board game samo.

Prema riječima govornika Goran Jeras, I tu smo evo tu smo krenuli s tim ciljem i dan-danas u njemu ustrajemo ali cilj je postao i puno širi od toga Znači zadruga je danas.

Prema riječima govornika Goran Jeras, Ja sam fizičar i spletom okolnosti sam završio u bankarstvu znači nisam nikad bio formalno obrazovan za financije i ekonomiju Međutim praktički još za vrijeme studija počeo sam.

### Provjera

- Stil (first_person): prvo ili drugo lice (V1)

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x WHERE v.id = 6 AND x->>'status' = 'unsupported'"`

## Ana Papac u podcastu Iva Kraljevic: Do dvije tisuće dvadeset dva kada

- Epizoda: "Djeca koja jedu samo brašno i vodu" Ana Papac, Udruga Zdenac · Iva Kraljevic · 26. lipnja 2026. · https://domovina.ai/v/P9sLks-f2mQ
- Članak 7, verzija 2 (engine:verify, verify-article/1+d1), kategorija `vjera`
- Riječi: 328 (u rasponu)
- Provjera: 6 rečenica, podržanih 6, nepodržanih 0, uklonjeno 0, stilskih napomena 4

**Ana Papac govorio je u epizodi podcasta Iva Kraljevic objavljenoj 26. lipnja 2026. o temi: Do dvije tisuće dvadeset dva kada kada sam ja tada sam dobila posao diplomirala.**

Prema riječima govornika Ana Papac, Do dvije tisuće dvadeset dva kada kada sam ja tada sam dobila posao diplomirala sam pravo i dobila sam posao u jednoj državnoj tvrtki činilo se da je.

> „Do dvije tisuće dvadeset dva kada kada sam ja tada sam dobila posao diplomirala sam pravo i dobila sam posao u jednoj državnoj tvrtki činilo se da je sve se posložilo da evo imam lijep posao, siguran što je danas sigurnost ali evo čovjek tada nekako to misli da je Zdenac je organizirao tečaj talent for you odnosno nije išli smo, organizirao mogućnost odlaska na tečaj talenta for you i ja sam se odazvala i sjećam se to je bila negdje veljača, veljača dvije tisuće dvadeset dva godine da i na tom tečaju kako je to onako tečaj koji te dobro onako pročešlja i protrese i otkrije čovjek svoje talente koji su vrlo često zakopani.”
> – Ana Papac, 7:33 · https://domovina.ai/v/P9sLks-f2mQ/t/453

Prema riječima govornika Ana Papac, Evo moje ime je Ana Papac dolazim inače iz Vinkovaca iz mogu reći velike obitelji mama tata imam dvije sestre i brata odrasla sam i osnovno školsko obrazovanje.

> „Evo, moje ime je Ana Papac, dolazim inače iz Vinkovaca, iz, mogu reći, velike obitelji, mama, tata, imam dvije sestre i brata, odrasla sam i osnovno školsko obrazovanje, sam završila osnovnu i srednju školu u Vinkovcima i nakon toga dolazim na studij prava u Zagreb i tu se susrećem sa udrugom Zdenac.”
> – Ana Papac, 2:05 · https://domovina.ai/v/P9sLks-f2mQ/t/125

Prema riječima govornika Ana Papac, Međutim negdje dvije tisuće i mislim da je to bila sedamnaesta ili osamnaesta godina kako sam bila aktivna u svojoj župi presvetog srca isusova u vinkovcima župnik mi.

Prema riječima govornika Ana Papac, Ja sam zapravo tad sebi posvijestila nešto što sam ja zapravo dugi niz godina željela ali što zbog nedostatka financija nezavršenog studija niz nekakvih tako otegotnih okolnosti jednostavno.

### Provjera

- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x WHERE v.id = 8 AND x->>'status' = 'unsupported'"`

## fra Ante Vučković u podcastu Mreže Riječi: Zamor i odmak od iskonskog razumijevanja

- Epizoda: Jedno ti nedostaje: EP 65 - Večera je spremna - fra Ante Vučković i Stanko Stojić · Mreže Riječi · 3. studenoga 2026. · https://domovina.ai/v/pIx_7N-6HJ4
- Članak 9, verzija 2 (engine:verify, verify-article/1+d1), kategorija `vjera`
- Riječi: 334 (u rasponu)
- Provjera: 9 rečenica, podržanih 9, nepodržanih 0, uklonjeno 0, stilskih napomena 5

**fra Ante Vučković govorio je u epizodi podcasta Mreže Riječi objavljenoj 3. studenoga 2026. o temi: Zamor i odmak od iskonskog razumijevanja teksta Zamor koji je došao nakon 2000 godina.**

Prema riječima govornika fra Ante Vučković, Zamor i odmak od iskonskog razumijevanja teksta Zamor koji je došao nakon 2000 godina I možda naše vrijeme sad pokazuje neko novo buđenje s evo nekim vrlo neočekivanim.

> „Zamor i odmak od iskonskog razumijevanja teksta. Zamor koji je došao nakon 2000 godina. I možda naše vrijeme sad pokazuje neko novo buđenje s, evo, nekim vrlo neočekivanim fenomenima kao što su, ne znam, veliki broj novokrštenika,”
> – fra Ante Vučković, 10:57 · https://domovina.ai/v/pIx_7N-6HJ4/t/657

Prema riječima govornika Stanko Stojić, Hvaljen Isus i Marija dragi gledatelji i slušatelji i štioci Markova evanđelja Franjo i ja dođosmo evo do sredine 14 poglavlja i teme o pashalnoj večeri odnosno pripremi.

> „Hvaljen Isus i Marija, dragi gledatelji i slušatelji, i štioci Markova evanđelja. Franjo i ja dođosmo, evo, do sredine 14. poglavlja i teme o pashalnoj večeri, odnosno pripremi za pashalnu večeru.”
> – Stanko Stojić, 0:13 · https://domovina.ai/v/pIx_7N-6HJ4/t/13

Prema riječima govornika fra Ante Vučković, To je otprilike generalno rečeno ono što se tiče svih Židova Ali evo mi se ovdje susrećemo s upitom učenika Isusu Gdje hoćeš blagovati Pashu da odemo i.

Prema riječima govornika fra Ante Vučković, To bi bilo namještanje koje uopće nije primjereno svemu što smo dosad saznali o Njemu Mi znamo da je On poznavao unaprijed što će se dogoditi To se.

Prema riječima govornika fra Ante Vučković, Ne diže paniku da Tako da priprema za Pashu je priprema za Njegovu posljednju večeru s učenicima To će biti spoj onoga što Pasha znači Židovima i onoga.

Prema riječima govornika Stanko Stojić, Jasno Sad netko će reći Kako vi to znate Pa možemo reći da znamo zato što ako proučavamo Bibliju u cjelini i ove tekstove Novog zavjeta onda na.

Prema riječima govornika fra Ante Vučković, dovoljno utemeljujućih snažnih argumenata kojima bi mogli reći Ovo je doba ribe a sad dolazi doba vodenjaka jer se oslanjaju na nešto što je vrlo rubno i što.

### Provjera

- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)
- Stil (first_person): prvo ili drugo lice (V1)

Reprodukcija: `npm run eval:report -- --db '.cache/eval-fake.pglite' --query "SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x WHERE v.id = 10 AND x->>'status' = 'unsupported'"`

# Engleski share i OG slike — četiri tiha kvara

**Datum:** 15.09.2026. · **Verzije:** worker v2.0.149, Flutter v2.0.150–151
**Repoi:** `domovina.ai` (worker + Flutter), `fetch.domovina.tv` (generator + upload)

Prijava je bila dvodijelna i obje su polovice bile točne: na WhatsApp kartici se
vidio prazan kvadratić umjesto ikone sata, a engleski share URL je davao
hrvatski preview. Iza toga su bila **četiri** odvojena kvara, od kojih tri nisu
imala nikakav simptom osim krajnjeg ishoda.

Zajednička crta: nijedan nije rušio ništa. Nema greške u konzoli, nema crvenog
testa, nema iznimke u logu. Sve je izgledalo kao da radi.

---

## 1. Kvadratić nije bila neučitana ikona

`generate_og_sections.py` je u kompozit pisao znak `⏱` (U+23F1) fontom
`/System/Library/Fonts/Helvetica.ttc`. Helvetica taj glyph **nema**, pa ga je
Pillow renderirao kao `.notdef` — prazan pravokutnik.

Mjerenje koje to dokazuje (ista bbox za sve nepostojeće glyphove, različita za
postojeći):

```python
from PIL import ImageFont
f = ImageFont.truetype('/System/Library/Fonts/Helvetica.ttc', 28, index=1)
f.getmask('⏱').getbbox()   # (2, 0, 19, 20)  ← .notdef
f.getmask('⏰').getbbox()   # (2, 0, 19, 20)  ← .notdef, isti
f.getmask('▶').getbbox()   # (2, 0, 19, 20)  ← .notdef, isti
f.getmask('•').getbbox()   # (2, 0,  8,  6)  ← stvarni glyph
```

Zašto se previdjelo: isti znak `⏱` **ispravno** izlazi u OG *tekstu*
(`og:title`), jer ga ondje renderira primateljev sustav. Na kartici je dakle
uredan sat u naslovu i kvadratić u slici — što ne izgleda kao problem fonta.

**Odbačeno:** `Apple Symbols.ttf` i `Arial Unicode.ttf` imaju taj glyph
(provjereno), ali to samo premješta ovisnost na drugi font na drugom stroju.
Ikona se sada **crta** (`draw_clock_icon` — brojčanik, dvije kazaljke, krunica);
vektor ne može tiho pasti na fallback koji se vidi tek u tuđoj aplikaciji.

**Opseg:** 65 759 slika. Regenerirane, uploadane, purgeane.

## 2. Worker nije poznavao `/en`

`/en` sufiks postoji u `lib/router/app_router.dart` od uvođenja per-epizoda
jezika, i komentar uz rutu izričito kaže zašto: crawleri droppaju query
parametre pri normalizaciji, pa `?lang=en` ne preživi reshare.

`web/_worker.js` ga nije imao ni u jednom matcheru. `/v/<id>/t/<sec>/en` nije
matchao ništa → `ytId` ostaje null → SPA fallback → generički OG naslovnice, na
hrvatskom.

Stranica se pritom otvarala savršeno, seek je radio, jezik se prebacivao. Kriv
je bio samo preview — dio koji autor nikad ne vidi jer gleda svoju stranicu, ne
tuđu karticu.

**Podatkovni oblik koji je trebalo naučiti:** EN nije polje u istom dokumentu
nego **zaseban fajl** (`data/<id>/article.en.json`, `summary.en.json`), a unutar
njega su i HR i `*_en` polja. Fallback se zato radi **po polju** (`pickLang`),
ne po dokumentu — prijevodi su parcijalni (sekcija može imati `subtitle_en` bez
`screenshot_description_en`).

Ne prevodi se: naslov epizode (izvorni YouTube naslov) i `inLanguage` u JSON-LD
(audio je hrvatski bez obzira na jezik stranice).

## 3. Manifest sekcija bio je zaleđen godinu dana

Ovo se otkrilo slučajno: novi manifest v1.1 bio je uploadan na R2, a CDN je i
dalje vraćao v1.0.

```
cache-control: public, max-age=31536000, immutable
```

Uzrok je razmimoilaženje imena kroz mapiranje ključeva:

```
{base}.og-sections/manifest.json   →   images/{id}/og-sections.json
         ↑ pipeline ime                         ↑ app ključ
```

`isContentMutable()` i `cacheControlFor()` provjeravaju `basename === "manifest.json"`
— a nakon mapiranja basename je `og-sections.json`. Provjera je promašila, pa je
manifest prvim uploadom postao immutable na godinu dana. Posljedica: nove
sekcije — i cijela `sections_en` mapa — nikad ne stižu do workera, **iako su
slike na R2**.

Komentar iznad te funkcije je cijelo vrijeme točno opisivao namjeru
(„`manifest.json` → raste s novim sekcijama"); promašila je izvedba.

Uz to: regenerirane `og-t-*.jpg` su također immutable, pa ih postojeći uploader
preskače kao „već na R2". Dodan `--force-og` (analogno postojećem `--force-mp4`)
koji radi re-upload **i** CDN purge.

## 4. EN članak pripada drugoj generaciji od hrvatskog

`discover_videos` bira leksikografski najveći `*.article.json`. Prijevod je
često rađen nad **starijim** člankom (drugi datum/model) i idući run ga nije
ponovio:

```
…diarized_2026-07-30_opus.article.json              ← odabrani HR
…diarized_2026-07-24_gemini-3.5-flash.article.en.json ← jedini EN
```

Derivacija EN putanje iz odabrane HR (`.article.json` → `.article.en.json`)
promašila je **8 od 47** prevedenih epizoda. Simptom: `sections_en: {}` u
manifestu, bez ijedne greške. `find_article_en` sada traži bilo koji
`{video_base}*.article.en.json` neovisno o HR izboru.

**Posljedica koja NIJE kvar:** kad su HR i EN članak iz različitih generacija,
isti timestamp može pasti u različite sekcije, pa HR i EN preview govore o
različitim temama (vidljivo na `pDrMN_ysSDA`). Isto se vidi i u aplikaciji, jer
i ona za EN renderira `article.en.json` — dakle preview je konzistentan s
prikazom. Poravnalo bi se tek ponovnim prevođenjem nad aktualnim člankom.

---

## Flutter strana: share link nije nosio jezik

Odvojena prijava istog dana, ista klasa problema.

Tri call-sitea su gradila share URL kao interpolirani string i svi su ispuštali
jezični segment. Kvar je preživio jer ga je **web maskirao**: adresnu traku
održava `url_sync`, koji `/en` uredno piše, pa je link prepisan iz trake bio
ispravan. Gumb „Kopiraj poveznicu" je bio jedini pokvaren put — a u iOS/Android
aplikaciji adresne trake nema, pa je ondje bio i jedini put uopće.

Korisnik je kvar prijavio točno tom razlikom.

Popravak: `lib/services/share_links.dart` → `episodeShareUrl(...)` kao jedini
gradilac. Usput se pokazalo da je prag „prvih 5 s nije trenutak" bio kopiran u
dva ekrana a u trećem ga nije bilo, i da se `?p=<slug>` nije enkodirao.

### Railovi: jezik se nagađa, pa traži dva uvjeta

Izvan episode ekrana nema `EpisodeLanguageScope`. Naivno „uzmi preferirani
jezik" bilo bi gore od buga: `/v/<id>/en` za neprevedenu epizodu tehnički radi
ali padne na hrvatski, pa bi link obećavao engleski i otvarao hrvatski.

EN se zato nudi samo kad vrijedi **oboje** — korisnik ga je izabrao **i** znamo
da prijevod postoji. Za drugi uvjet postoji `pipeline.has_article_en` u
listingu, ali CLAUDE.md pravilo kaže da te zastavice lažu u oba smjera, pa je
izmjeren njezin profil prije oslanjanja:

| | |
|---|---|
| zastavica podignuta | 42 epizode |
| od toga bez `article.en.json` na CDN-u | **0** |
| ima prijevod, a zastavica šuti | **5** |

Profil je „nikad ne laže pozitivno, ponekad šuti" — dovoljno za odluku koja
samo **nudi**, nedovoljno za tvrdnju da prijevoda nema. Tih 5 epizoda svjesno
dobiva hrvatski link.

Reprodukcija mjerenja:

```bash
# za svaki kanal iz channels/data/index.json
curl -s "https://cdn.domovina.ai/channels/data/$ch.json" \
  | jq -r '.videos[] | select(.pipeline.has_article_en or .pipeline.has_translation_en) | .id'
# pa usporedi s HEAD-om data/<id>/article.en.json
```

### Dva ruba koja su se pokazala tek pri izvedbi

**Preferencija je bila samo async.** `loadPreferredLanguage()` je Future, a
odluka o jeziku pada u trenutku klika. Dodan `PreferredEpisodeLanguage`
singleton po uzoru na `PlaybackSpeed`; `main()` ga učita prije `runApp`.
Ključno: `savePreferredLanguage` ga **sama** osvježava — pet call-siteova piše
preferenciju, i da je osvježavanje na njima, prvi novi bi ga zaboravio.

**Kartica ne bi primijetila promjenu jezika.** `push` drži ekran ispod
montiranim (navigacijski stog iz v2.0.148), pa kartica preživi promjenu jezika
na ekranu iznad bez rebuilda — URL izračunat u `build` ostao bi na starom
jeziku. `ShareContextMenu.lazy` gradi URL pri kliku. Kanali i osobe ostaju na
običnom konstruktoru; njihov link ne ovisi o stanju.

---

## Zamka u verifikaciji: dva cache zapisa po URL-u

`cdn.domovina.ai` šalje `Vary: Origin`, pa svaki URL ima **dva** cache zapisa.
Provjera samo jednim zahtjevom daje lažno uvjerljiv rezultat.

Pri backfillu je provjera s `Origin: https://domovina.ai` dala 150/150
„svježe" — dok purge dokazano **nije** bio gotov (proces je ubijen zbog memorije
baš na ulasku u purge fazu). Objašnjenje: te URL-ove uglavnom nitko nije ni
tražio s tim Originom, pa je svaki zahtjev bio MISS i povlačio svjež objekt iz
R2 — ishod izgleda identično uspjelom purgeu.

Onaj koji mjeri stvarni slučaj je **goli** zahtjev, bez Origina — WhatsApp ga ne
šalje:

```bash
curl -s -H "Origin: https://domovina.ai" "$URL" | md5 -q   # zapis aplikacije
curl -s -A "WhatsApp/2.23" "$URL" | md5 -q                 # zapis crawlera
md5 -q "$LOKALNI"                                          # istina
```

`cf-cache-status: HIT` i `age: 0` ne dokazuju ništa o tome je li sadržaj nov.

Purge je na kraju odrađen zasebnim streamanim skriptom: **131 654 zapisa, 4389
batcheva, 0 neuspjelih** (~12 min; CF prima 30 URL-ova po pozivu). Završna
provjera 60/60 svježe kroz oba zapisa.

---

## Dopuna 27.10.2026.: `/hr` sufiks vodio na naslovnicu

`/v/<id>/t/<sec>/en` je radio, a `/v/<id>/t/<sec>/hr` je padao na
`errorPageBuilder` (naslovnicu) jer `/hr` ruta nikad nije postojala: hrvatski je
izvornik i kanonski URL nema sufiks. Ljudi ga ipak upisuju po analogiji s `/en`.

- **Flutter** (`lib/router/app_router.dart`, top-level `redirect`, regex
  `_hrSuffix`): `/v|m/<id>[/t/<sec>]/hr` → isti put bez `/hr`, query ostaje.
  Redirect usput zove `savePreferredLanguage(hr)`. Bez toga bi zapamćena EN
  preferencija (`loadPreferredLanguage` u `initState` ekrana epizode) odmah
  prebacila ekran na engleski, pa bi `/hr` u praksi otvarao engleski čim je
  korisnik ikad birao EN. Odbačeno: zasebne `/hr` GoRoute rute (četiri kopije
  pageBuildera) i parametar „forsiraj HR" na `EpisodeScreen`.
- **Worker** (`web/_worker.js`): matcheri primaju `(\/(?:en|hr))?`, a jezik je EN
  samo za `=== '/en'`. Canonical za `/hr` je adresa bez sufiksa (provjereno na
  produkciji v2.0.204).
- Za redirect nema testa: `test/nav_contract_test.dart` gradi vlastiti router,
  ne `createRouter()`.

## Što je ostalo otvoreno

- **Native čeka nightly build.** Flutter popravak (v2.0.150–151) na iOS/Android
  stiže tek kroz noćni build u 01:00 → TestFlight / Play internal. Ondje je
  kvar bio najgori (nema adresne trake), pa provjeriti na uređaju.
- **5 epizoda s prijevodom bez zastavice** dobiva hrvatski share link s
  kartice. Popravak je u pipelineu (zastavica se ne piše dosljedno), ne ovdje.
- **HR/EN sekcije se razilaze** za epizode gdje je prijevod rađen nad starijim
  člankom. Poravnalo bi se ponovnim prevođenjem nad aktualnim.
- **`og-share.jpg` (Tier A) nema EN varijantu** — za `/v/<id>/en` bez timestampa
  slika je episode-level, s hrvatskim naslovom. Naslov epizode se ionako ne
  prevodi, pa je to vjerojatno ispravno, ali nije odlučeno namjerno.

## Vezani dokumenti

- `docs/2026-09-04-navigacija-i-scroll-restoration.md` — zašto `push` drži
  ekran ispod živim (uzrok ruba s karticom)
- `docs/web-delivery-and-rendering.md` — cache strategija i COEP kontekst
- `fetch.domovina.tv/docs/PIPELINE.md` § KORAK 9.6 — generator OG sekcija
- CLAUDE.md § „Social sharing" — pravila izvedena iz ovoga

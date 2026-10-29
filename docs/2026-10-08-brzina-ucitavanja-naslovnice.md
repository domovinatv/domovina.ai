# Brzina učitavanja naslovnice i offline — mjerenje i plan

**Datum:** 8.10.2026. · **Status (9.10.2026.):** frontend za sve korake
implementiran i LIVE od v2.0.173; `home.json`, skraćeni listinzi i `search.json`
čekaju pipeline — vidi §0
**Reprodukcija svih brojki:** `python3 scripts/measure-home-payload.py`
(+ `curl` naredbe u §2.3)

## 0. Stanje implementacije (9.10.2026., LIVE v2.0.173)

| korak | frontend | pipeline (`fetch.domovina.tv`) |
|---|---|---|
| Q1 listinzi bez `?v=` | gotovo (`CdnConfig.channelsIndexUrl`) | — (preporuka: ne mijenjati `generated_at` bez promjene sadržaja) |
| Q2 prefetch po svježini, pool | gotovo (`ChannelCache.prefetchAll`) | — |
| Q3 dokazivo konačan hero | gotovo (`HomeFeed.heroPoolComplete`) | — |
| P1 `home.json` | čita ga uz fallback (`HomeSnapshot`) | isporučeno (9.10., v1, 85 epizoda, `max-age=60`) |
| P2 skraćeni listing + `search.json` | čita v1 i v2 (`VideoPipeline.fromBits`, `SearchCorpus`) | `search.json` isporučen (9.10.); listing v2 čeka |
| O1 disk cache | gotovo (`CdnJsonCache`, `cdn_store*.dart`) | — |
| §8 `episode.json` po epizodi | čita ga uz fallback (`EpisodeBundle`) — LIVE v2.0.174 | **treba napraviti** |
| §8 predučitavanje po namjeri | gotovo (`EpisodePrefetch`) — LIVE v2.0.174 | — |
| §8 članak prije titlova | gotovo (`loadWithProgress(onTimeline:)`) — LIVE v2.0.174 | — |

Testovi: `test/home_feed_hero_pool_test.dart`, `test/home_snapshot_test.dart`,
`test/slim_listing_test.dart`, `test/cdn_json_cache_test.dart`.

Provjereno u pregledniku nad lokalnim release `--wasm` buildom: prvo otvaranje
spremi 51 zapis u Cache Storage (`domovina-cdn-v1`: index + 50 listinga;
`home.json`/`search.json` vraćaju 404 i ne spremaju se), a pri ponovnom
otvaranju svih 50 kanala stigne iz cachea u istoj sekundi u kojoj je prefetch
krenuo.

Dok pipeline ne isporuči P1/P2, korisnik dobiva Q1–Q3 i O1. P1/P2 se mogu
isporučiti bilo kojim redom i bez koordiniranog deploya — klijent na 404 ili
nepoznatu verziju pada na stari put.

## 1. TL;DR

Naslovnica pri **svakom** otvaranju povuče `index.json` i **svih 50 listinga
kanala**: 51 zahtjev, **6,9 MB sirovog JSON-a, 1,30 MB preko žice** (brotli).
Za prvi ekran stvarno treba ~120 najnovijih epizoda sa 6 polja — to je
**~10 KB** brotlija. Ostatak je tekst za lokalnu pretragu (sažetak, teme,
govornici) i ponavljanje istih stvari 3 316 puta.

Tri stvari čine sporu mrežu bolnom, i nijedna nije „previše kanala":

1. **Cijeli korpus ide prije prvog ekrana** — hero se otkriva tek kad je
   prefetch gotov ili nakon 6 s grace prozora (`lib/screens/home/home_screen.dart`).
2. **Ništa se ne pamti između posjeta** — 5-minutni `?v=` cache-buster mijenja
   URL, pa preglednik ne može ni pitati „je li se promijenilo"; native
   (`package:http`) nema HTTP cache uopće. Shell aplikacije se pri ponovnom
   posjetu revalidira (304), JSON se uvijek skida iznova — **na ponovnom posjetu
   JSON je praktički jedini promet**.
3. **Batchevi s barijerom** — `prefetchAll` ide po 6 kanala i čeka najsporiji u
   svakoj šestorki prije sljedeće (9 sekvencijalnih rundi), i to abecednim
   redom, pa najsvježiji kanali ne stižu prvi.

Najveći dobici, po omjeru uloženo/dobiveno:

| # | Zahvat | Gdje | Trud | Efekt |
|---|---|---|---|---|
| Q1 | Makni `?v=` s listinga, oslanjaj se na ETag/304 | frontend | sati | ponovni posjet: 1,30 MB → ~0 (samo promijenjeni kanali) |
| Q2 | Prefetch po svježini + pool umjesto batch barijere | frontend | sati | rail „Najnovije" točan nakon prvih par kanala |
| Q3 | Hero/railovi „dokazivo konačni" iz `index.json` (ne čekaju sve) | frontend | dan | hero bez 6 s čekanja |
| P1 | `home.json` — gotov feed naslovnice | pipeline + frontend | 1–2 dana | prvi ekran: 1,30 MB → ~10 KB |
| P2 | Slim listinzi + zaseban search korpus | pipeline + frontend | 2–3 dana | listinzi 1,30 MB → 0,19 MB |
| O1 | SWR disk cache (web + native) | frontend | 3–5 dana | instant naslovnica iz diska + offline čitanje |

## 2. Mjerenje (8.10.2026.)

### 2.1 Što naslovnica povuče

`home_screen.dart` u `initState` zove `channelCache.loadIndex()` pa
`prefetchAll(index.channels)` — **sve** kanale, neovisno o tome što je na
ekranu.

| | zahtjeva | sirovo | gzip | brotli |
|---|---|---|---|---|
| `channels/data/index.json` | 1 | 0,042 MB | 0,007 MB | 0,006 MB |
| `channels/data/<id>.json` × 50 | 50 | 6,886 MB | 1,331 MB | 1,082 MB (q11) / **1,304 MB** (izmjereno s CDN-a) |
| `mcp.domovina.ai/api/persons` | 1 | — | — | 0,007 MB |

3 316 epizoda u listinzima. Najveći listing: `nanovoroeni.json` 0,61 MB sirovo
(316 epizoda). Rast je linearan s brojem epizoda: ~2,1 KB sirovo / ~0,4 KB
brotli po epizodi → pri 10 000 epizoda ~21 MB sirovo / ~4 MB preko žice.

### 2.2 Na što odlaze bajtovi

Listinzi su pretty-printani: 6,886 → 5,402 MB samo micanjem razmaka (22 %).
Unutar compact listinga, po polju epizode:

| polje | MB | udio | treba li naslovnici? |
|---|---|---|---|
| `abstract` | 1,937 | 36,2 % | ne — samo lokalna pretraga (`search_overlay.dart`) |
| `pipeline` | 0,719 | 13,5 % | da, ali 9 bool ključeva → 1 bitmask |
| `topics` | 0,640 | 12,0 % | ne — pretraga + sponzorski izlog |
| `speakers` | 0,621 | 11,6 % | ne na naslovnici |
| `title_hr` | 0,261 | 4,9 % | duplikat `title` u većini zapisa |
| `thumbnail` | 0,235 | 4,4 % | ne — klijent ga ionako gradi iz ID-a (`CdnConfig.thumbnailUrl`) |
| `youtube_url` | 0,212 | 4,0 % | ne — izvodi se iz ID-a |
| `duration_display` | 0,092 | 1,7 % | izvodi se iz `duration_seconds` |

**Polja koja naslovnica zaista koristi** (`home_feed.dart`, kartice, hero):
`id`, `title`, `date`, `duration_seconds`, `magisterium_score`, `pipeline`.

### 2.3 Cache zaglavlja — stara pretpostavka više ne vrijedi

```bash
curl -sI https://cdn.domovina.ai/channels/data/hnb.json | grep -i 'cache-control\|etag'
#   cache-control: public, max-age=60, must-revalidate
#   etag: "e305…"
curl -s -o /dev/null -w '%{http_code} %{size_download}\n' \
  -H 'If-None-Match: "<etag iz gornjeg>"' https://cdn.domovina.ai/channels/data/hnb.json
#   304 0
```

Komentar u `lib/services/cdn_config.dart` (i memory zapis) kaže da uploader
stavlja `immutable` na **sve** pa listinzi trebaju `?v=` bucket. Danas listinzi
nose `max-age=60, must-revalidate` + ETag, i uvjetni zahtjev uredno vraća
**304 s 0 bajtova**. Per-epizoda datoteke (`data/<id>/info.json`, slike) i dalje
su `immutable`, što je za njih ispravno.

Posljedica: `?v=` je od zaštite postao kočnica — svakih 5 min novi URL znači
novi cache zapis u pregledniku, bez ETag-a, pa puni download. **Prije nego se
makne, provjeriti edge TTL za `/channels/*`** (Cache Rule na zoni): ako edge
drži listing satima, gubitkom bustera korisnik vidi stari listing. Provjera:
`curl -sI …/index.json` dvaput u razmaku > 60 s i gledati `age:` /
`cf-cache-status`. Ako je TTL predug — Cache Rule za `/channels/*` na
„respect origin" (60 s).

### 2.4 Shell aplikacije, za usporedbu

| | brotli |
|---|---|
| `main.dart.wasm` | 1,60 MB |
| `canvaskit/skwasm.wasm` (Chromium) / `skwasm_heavy.wasm` (Safari, Firefox) | 1,52 / 2,28 MB |
| `main.dart.js` (fallback bez WasmGC) | 1,49 MB |

Pri **prvom** posjetu shell (~3,1–3,9 MB) je veći od JSON-a i JSON nije jedini
problem. Pri **ponovnom** posjetu shell je 304 (bootstrap) ili iz cachea
(`canvaskit/*` immutable), a JSON se uvijek skida cijeli. Zato je Q1 najjeftiniji
dobitak za korisnike koji se vraćaju, a P1 za nove.

### 2.5 Što to znači na sporoj mreži (procjena, ne mjerenje)

Chromeovi throttling profili: „Fast 3G" ≈ 1,6 Mbit/s uz ~560 ms RTT, „Slow 3G"
≈ 0,4 Mbit/s uz ~2 s RTT. Samo JSON listinga (1,30 MB) + 9 sekvencijalnih
batch rundi:

| | prijenos | runde | ukupno |
|---|---|---|---|
| Fast 3G | ~6,5 s | 9 × ~0,6 s | **~12 s** |
| Slow 3G | ~26 s | 9 × ~2 s | **~44 s** |
| s `home.json` (10 KB, 1 zahtjev) | < 0,1 s / ~0,2 s | 1 | **~0,7 s / ~2,2 s** |

Dodatno, ne izmjereno: dekodiranje 6,9 MB JSON-a na glavnoj niti (web nema
`compute` isolate) na slabom mobitelu i na EON TV boxu. Vrijedi izmjeriti
DevTools Performance snimkom prije i nakon P2.

## 3. Plan

Raspored: frontend-only zahvati (Q) odmah, bez čekanja pipelinea; pipeline
zahvati (P) iz `fetch.domovina.tv` sesije; offline (O) na kraju, jer se najlakše
gradi nad malim i stabilnim datotekama koje P1/P2 proizvedu.

### Q1 — makni `?v=` s listinga (ETag revalidacija)

- `CdnConfig.channelsIndexUrl/channelUrl` bez `?v=`. Preglednik tada nakon
  60 s pošalje `If-None-Match` i dobije 304 za svaki kanal koji se nije
  promijenio. Pipeline dnevno dira mali broj kanala, pa ponovni posjet pada s
  1,30 MB na zbroj stvarno promijenjenih listinga.
- **Ograničenje (izmjereno 8.10.):** svih 50 listinga ima `last-modified`
  iz zadnja 24 h — noćni run (~02 h) prepisuje sve, i svaki nosi
  `generated_at`, pa se ETag (MD5 sadržaja) mijenja svaki dan i kad kanal
  nema novih epizoda. Q1 zato štedi na ponovnim posjetima **unutar dana**;
  prvi posjet dana i dalje skida sve. Popravak je u pipelineu: ne mijenjati
  `generated_at` ni ne uploadati listing kojem se `videos` nisu promijenili
  (usporedi hash bez tog polja). Tada 304 vrijedi danima.
- `bustCache()` ostaje za drugi pokušaj nakon 404 (`DataService._get`) i probe
  URL-ove — tamo štiti od cachiranog 404, što je drugi problem.
- Native nema HTTP cache — Q1 tamo ne pomaže sam; pokriva ga O1.
- **Preduvjet:** provjera edge TTL-a iz §2.3.

### Q2 — prefetch po svježini, pool bez barijere

- Sortirati kanale po `latest_video.date` (podatak je već u `index.json`) —
  isto kao što `findVideoAsync` već radi.
- Umjesto `Future.wait` po šestorki: pool od 6 aktivnih zahtjeva, sljedeći
  kreće čim jedan završi. Spori kanal više ne blokira ostalih pet.
- `notifyListeners` je već po kanalu, pa railovi rastu glatko.

### Q3 — „dokazivo konačni" railovi

`index.json` nosi datum najnovije epizode svakog kanala. Kad je N-ta epizoda
„Najnovije" novija od `latest_video.date` **svakog još neučitanog** kanala,
rail je konačan — nijedan kanal koji stiže kasnije ga ne može promijeniti. Isto
za hero tier 1 (≤ 14 dana): kad su učitani svi kanali s
`latest_video.date` unutar 14 dana, tier 1 bazen je potpun.

To zamjenjuje grace prozor od 6 s točnim uvjetom. U praksi: hero latcha nakon
~10 najsvježijih kanala umjesto nakon svih 50. Pravilo „hero se otkriva tek kad
je izbor konačan" ostaje — samo se konačnost računa umjesto čeka.

### P1 — `channels/data/home.json` (pipeline)

Gotov izbor epizoda za naslovnicu, uz `index.json`, s istim cache zaglavljima
(`max-age=60, must-revalidate`, ne `immutable`). Ugovor v1 (izvor istine je
doc komentar u `lib/models/home_snapshot.dart`):

```json
{
  "version": 1,
  "generated_at": "2026-10-09T02:30:00Z",
  "episodes": [
    {"c": "<channel_id>", "id": "<youtube_id>", "title": "…", "title_hr": "…",
     "date": "2026-10-05", "duration_seconds": 3041, "magisterium_score": 85,
     "p": 31}
  ]
}
```

`episodes` je unija, bez duplikata:

1. sve epizode s datumom unutar zadnjih **45 dana** (hero tier 1 je 14 dana,
   „Upravo stiglo" 30);
2. do **20** epizoda s `has_magisterium` i `magisterium_score ≥ 70`, najbolji
   score prvi, bilo koji datum (hero tier 2);
3. **30** najnovijih epizoda s `has_article` (rail „Najnovije" kad zadnjih 45
   dana ima malo obrađenih).

`title_hr` samo kad se razlikuje od `title`. `p` je bitmask `pipeline`
zastavica — tablica bitova u `VideoPipeline.fromBits`
(`lib/models/channel_detail.dart`); redoslijed se ne smije mijenjati, samo
nadopunjavati.

**Provjera ugovora (9.10.2026.):** nad stvarnim listinzima, za 40 dana
unatrag kroz 13 mjeseci (svaki 10. dan, katalog odrezan na taj datum), hero
izbor, „Najnovije" i „Upravo stiglo" nad ovim bazenom identični su onima nad
cijelim katalogom — 40/40. Današnji `home.json`: 85 epizoda, 19,8 KB sirovo,
**5,6 KB brotli** (naspram 1,30 MB listinga). Jedina razlika: „Zašto?" dijalog
za tier 2 broji kandidate u bazenu, ne u katalogu.

Algoritam hero izbora ostaje u klijentu — pipeline daje bazen, ne odluku.
Puni listinzi se i dalje učitavaju u pozadini (pretraga, „Novo od praćenih",
favoriti), ali hero i railovi ne čekaju na njih.

### P2 — skraćeni listinzi + `search.json` (pipeline)

**Listing v2** (`channels/data/<id>.json`): `"version": "2.0"` — **string**,
ne broj: build prije 9.10.2026. čita `json['version'] as String?` i na broju
baca, pa cijeli kanal ne bi učitao. Po epizodi samo `id`,
`title`, `title_hr` (kad se razlikuje), `date`, `duration_seconds`,
`magisterium_score`, `p` (bitmask umjesto `pipeline` objekta), te `source` /
`sound_link` kad postoje. Bez `abstract`, `topics`, `speakers`, `thumbnail`,
`youtube_url`, `duration_display`, `views`, `likes`. Compact JSON (bez
uvlaka). Izmjereno: **5,40 → 0,63 MB sirovo, 1,06 → 0,19 MB brotli**.

Klijent to već podnosi: `VideoPipeline.fromBits` za `p`, `durationDisplay` se
računa iz `duration_seconds` (isti oblik: `20:14`, `1:40:06`), a thumbnail se
ionako gradi iz ID-a (`CdnConfig.thumbnailUrl`). Novi klijent prima i broj
za `version`, ali zbog starih buildova pipeline piše string.

**`channels/data/search.json`** (ugovor u `lib/models/search_corpus.dart`):

```json
{"version": 1, "generated_at": "…",
 "episodes": {"<youtube_id>": {"a": "sažetak", "t": ["tema"], "s": ["govornik"]}}}
```

`s` su `suggested_name` govornika. Učitava ga samo pretraga (`search_overlay`)
i sponzorski izlog (`ChannelCache.loadChannelWithText`); tekst se upiše u
epizode listinga, pa ostatak koda ne zna odakle je stigao. ~0,66 MB brotli.

**Prijelaz — redoslijed je bitan:**

1. Pipeline počne pisati `search.json` (v1 listinzi i dalje nose tekst;
   klijent ga ne dira jer listing ima prednost).
2. Ovaj frontend ide u produkciju (web) i u store (native).
3. Tek kad stari native buildovi ispadnu iz upotrebe, listinzi prelaze na v2.
   Stari build (prije ovog frontenda) na v2 listingu ne puca — `pipeline`
   objekt mu nedostaje pa sve epizode vidi kao neobrađene, a pretraga gubi
   sažetke. Zato v2 tek kad je udio starih buildova zanemariv (RevenueCat /
   store statistika verzija).

### O1 — stale-while-revalidate disk cache + offline (gotovo)

`CdnJsonCache` (`lib/services/cdn_json_cache.dart`) nad pohranom
`CdnStore` (`lib/services/cdn_store.dart`):

- **Web:** Cache Storage API iz prozora (`domovina-cdn-v1`), bez service
  workera. Odabran umjesto IndexedDB-a jer je promise-based i čuva cijeli
  odgovor jednim pozivom. Greške (privatni prozor, kvota) = „nema zapisa".
- **Native:** datoteke u `<app support>/cdn_cache/{mutable,immutable}/`,
  pisanje preko `.tmp` + rename.
- **Promjenjive datoteke** (index, listinzi, `home.json`, `search.json`):
  spremljeno odmah → revalidacija jednom po sesiji → na drugačije tijelo
  `onUpdate` (cache zamijeni i notificira). Native šalje `If-None-Match`; web
  NE (zaglavlje nije CORS-safelisted → preflight na svaki zahtjev, a CDN ionako
  ne izlaže `etag`), nego obični GET koji preglednik sam pretvori u uvjetni i
  usporedi tijela.
- **Nepromjenjive** (`DataService._get`: info, summary, article, magisterium,
  srt, words…): cache-first, **samo native** (web ih ima u HTTP cacheu kao
  `immutable`), gornja granica 40 MB, izbacuje najdavnije čitane.
- **404 i greške se ne spremaju.**
- **Ugašeno** u debug buildu i uz `?nocache=1` na webu — tada je ponašanje
  točno kao prije.

Naslovnica se pri ponovnom otvaranju i offline crta iz spremljenog; posjećene
epizode se na nativeu čitaju offline. Media (video/audio) nije dio ovoga.

Što nije napravljeno: gumb „Očisti spremljene podatke" u `/account`
(`CdnJsonCache.clear()` postoji, treba ARB stringove i mjesto u UI-ju).

## 4. Što NE raditi

- **Paginirati listinge po kanalu kao prvi korak.** Kanal stranica sortira i
  filtrira lokalno; slim listing (P2) od 0,19 MB za sve kanale je dovoljno mali
  da paginacija ne isplati složenost. Vratiti se tome iznad ~20 000 epizoda.
- **Ručni cache u localStorageu** — 5 MB limit, sinkroni I/O na glavnoj niti,
  i upravo onaj oblik cachea koji je ranije stvarao glavobolje.
- **Prebacivati naslovnicu na API/bazu.** Statični JSON na CDN-u je razlog
  zašto aplikacija skalira; problem je oblik podataka, ne mjesto.

## 5. Redoslijed (ažurirano 9.10.2026.)

1. ~~Provjera edge TTL-a~~ — izmjereno 9.10.: `HIT` uz `age: 34`, nakon isteka
   `REVALIDATED`; edge poštuje `max-age=60`.
2. Deploy ovog frontenda (Q1–Q3, O1, čitači za P1/P2). Mjeriti DevTools
   „Fast 3G" prije/poslije.
3. Pipeline: `home.json` (P1) i `search.json` (P2 korak 1), te ne mijenjati
   `generated_at`/ne uploadati listing kojem se `videos` nisu promijenili.
4. Pipeline: listinzi v2 kad stari native buildovi ispadnu iz upotrebe.

## 6. Otvorena pitanja

- Koliko kanala se **sadržajno** promijeni dnevno. `last-modified` to ne
  govori (noćni run prepiše svih 50) — treba usporediti `videos` dvaju dana.
- Parse cost na EON-u i slabom mobitelu — izmjeriti prije i poslije P2.
- `home.json` 404 CDN cachira do 4 h: prvi dan nakon što ga pipeline počne
  pisati, dio klijenata ga vidi tek s tim zakašnjenjem (padaju na stari put,
  ništa ne puca). Purge nakon prvog uploada skraćuje to — u obje `Vary: Origin`
  varijante.

- **Bijeli ekran prije prvog Flutter framea** — RIJEŠENO u v2.0.175–178:
  splash ostaje dok Flutter platno nije stvarno nacrtano, u boji teme, s
  citatima iz Evanđelja u krugu. Mjerenja, odluke i otvoreno (fontovi ~0,7 MB,
  edge cache `main.dart.wasm`): `docs/2026-10-09-boot-splash.md`.

## 7. Zašto ne Worker koji drži JSON u memoriji (odluka 9.10.2026.)

Razmatrano: Cloudflare Worker koji sve listinge drži u memoriji i frontendu
servira samo potrebno. Odbačeno za naslovnicu, jer:

- **Memorija Workera nije globalna.** Svaki datacentar vrti više kratkoživućih
  izolata; globalna varijabla živi u jednom, a izbacivanje nije pod našom
  kontrolom.
- **Hladan start plaća sve.** Novi izolat mora povući 51 datoteku (6,9 MB) i
  parsirati ih prije prvog odgovora. Uz naš promet po datacentru velik dio
  zahtjeva pogađa hladan izolat, pa bi korisnik čekao dulje nego danas.
- **CPU limit.** Parsiranje 5–7 MB JSON-a je desetke ms CPU-a — preko 10 ms
  besplatnog plana, a na plaćenom se plaća po hladnom startu.
- **Robusnost.** Statičan CDN put nema koda koji može pasti; Worker na
  kritičnom putu bi ga uveo.
- **Ne rješava offline ni ponovni posjet** — to je klijentski posao (O1).

Pogled koji ne ovisi o korisniku (`home.json`, skraćeni listinzi) jeftinije je
izračunati jednom u noćnom runu i servirati kao statičnu datoteku — to je ista
„orkestracija", samo pomaknuta na build-time.

**Gdje Worker ima smisla:** upiti s parametrima koji se ne daju izračunati
unaprijed — razrješavanje po ID-evima (favoriti, „Nastavi slušati"),
stranice/sortiranje kanala, personalizirani feed. Tada bez stanja: čita
pripremljene statične datoteke (nikad 6,9 MB izvora), odgovor sprema u
`caches.default` (izračun jednom po datacentru, kao OG injekcija u
`web/_worker.js`), a klijent uvijek ima statičan fallback. Pretraga po tekstu
ostaje na Meiliju / `domovina-rag`.

## 8. Ekran epizode: jedna datoteka, predučitavanje, članak prije titlova (9.10.2026.)

Pitanje je bilo može li se u pozadini učitati sve epizode na koje se s
naslovnice može kliknuti. Mjerenje je pokazalo da je prvi problem drugdje:
**broj zahtjeva**, ne bajtovi.

### 8.1 Mjerenje

`python3 scripts/measure-episode-bundle.py 12` (12 najnovijih epizoda s
člankom, 9.10.2026.):

- ekran epizode (`EpisodeData.load`) traži 17 datoteka + do 3 HEAD probea
  medije. Svaki 404 se ponavlja s cache-busterom (`DataService._get`), pa je to
  **28,8 zahtjeva po otvaranju** u prosjeku, većinom uzaludnih;
- na uzorku od 100 nasumičnih epizoda s člankom legacy Magisterium varijante
  gotovo ne postoje (`article.magisterium.json` 12/100, `_full*` 6/100,
  `_batch*` 0/100, EN prijevodi 1/100, `words.json` 1/100);
- bajtova je malo (~106 KB brotli), od toga su `diarized.srt` + `words.json`
  ~66 KB, a trebaju tek kad krene reprodukcija.

Predučitati sve klikabilne epizode (30–50) bilo bi ~1 000 zahtjeva, ~600 od
njih 404, i 3–5 MB uz naslovnicu — na sporoj mreži upravo ondje gdje boli.

### 8.2 `data/<id>/episode.json` (pipeline) — jedan zahtjev umjesto ~29

Hibrid, ne „sve u jednu datoteku": u njoj je ono što treba za prvi prikaz
(`info`, `summary`, `outline`, `article`, `article.magisterium` kad postoji) i
**izmjereni popis datoteka** koje za epizodu postoje. Titlovi, vrijeme po
riječi i EN prijevodi ostaju zasebni i traže se samo ako su na popisu. Puni
ugovor: doc komentar u `lib/models/episode_bundle.dart`.

Isto mjerenje: bundle je **32,6 KB brotli** u prosjeku (16–59 KB), a broj
zahtjeva pada s **28,8 na 3** (bundle + datoteke s popisa koje nisu u
njemu; kod najnovijih epizoda `diarized.srt` i `words.json`). Skripta ne
broji `sponsors_in_video.json`, koji ekran traži zasebno. Sve u jednoj datoteci (sa SRT-om i `words.json`) bilo bi
~3× veće, a ekran bi čekao bajtove koje prvi prikaz ne treba.

Klijent (`DataService._get`, `_bundle`): bundle ide kroz
`CdnJsonCache.getMutable` u zaseban, ograničen bucket (`StoreBucket.episode`:
native 20 MB LRU, web 150 zapisa), jer je promjenjiv — pipeline ga prepisuje
kad stigne nova datoteka. Datoteka koje NEMA na popisu klijent ne traži: 404 iz
izmjerenog popisa je istina, za razliku od 404 s CDN-a (vidi CLAUDE.md
„Cachiran 404"). Medija se čita s popisa, bez HEAD probea. Bez bundlea (404,
nepoznata verzija) ostaje stari put — zauvijek, za epizode koje backfill nije
pokrio.

Cijena dok pipeline ne isporuči bundle: jedan zahtjev više po otvaranju
(`episode.json` 404, koji edge cachira), prije starog puta.

**Rule za pipeline**: bundle se regenerira kao ZADNJI korak svakog uploada u
`data/<id>/` (prijevod, Magisterium, `words.json`, medija). Datoteka koje nema
na popisu klijent ne vidi dok se bundle ne obnovi.

### 8.3 Predučitavanje po namjeri (frontend, `EpisodePrefetch`)

- **mirovanje**: 2 s nakon što se hero latcha — prvi hero pick i prve 3 iz
  „Nastavi slušati";
- **namjera**: miš iznad kartice ili prst na njoj (`PrefetchOnIntent` oko
  `EpisodeRailCard` i `HeroSection`); dodir prethodi `onTap`-u ~100–300 ms;
- samo prvi prikaz (`DataService.prefetchFirstPaint`): s bundleom jedan
  zahtjev, bez njega `info`/`summary`/`outline`/`article`;
- najviše 2 epizode odjednom, 40 po sesiji, ništa uz Save-Data ili 2G
  (`network_hints.dart`; Safari/Firefox taj API nemaju pa se tamo ne gasi);
- odgovori ostaju u memoriji `DataService` (LRU, 80 odgovora) koja dijeli i
  zahtjeve u letu — klik usred predučitavanja ne šalje isti zahtjev dvaput.
  Na nativeu idu i u disk cache (offline).

### 8.4 Članak prije titlova

`EpisodeData.loadWithProgress(onTimeline:)`: epizoda s člankom vraća se čim
stigne sve osim `diarized.srt`/`words.json`; puni podaci stižu kao zamjena
(`EpisodeScreen._data`). `_EpisodeContent` titlove čita samo u `build`, pa
zamjena ne dira player. Epizoda bez članka čeka sve, jer bi joj kartica faze
bez transkripta krivo pokazala „u obradi". Jednostavni prikaz i TV i dalje
koriste `EpisodeData.load`.

Testovi: `test/episode_bundle_test.dart`, `test/data_service_stale_404_test.dart`.

### 8.5 Tamni placeholder u hero karuselu

Prijava 9.10.: slika se pojavi, pa neko vrijeme stoji tamni placeholder.
Uzrok: `HeroCarousel` kroz `AnimatedSwitcher` svakih 7 s montira NOVU
`HeroSection`, a njena slika (`thumb-1280.webp`) tek tada kreće s mreže; dok ne
stigne, vidi se `surfaceContainerHighest` (u tamnoj temi gotovo crn). Popravak:
`Offstage` sloj u karuselu drži `CachedThumbnail` svih pickova montiran od
prvog prikaza, s istim parametrima kao `HeroSection._coverImage`, pa je ključ u
ImageCacheu isti i rotacija sliku dobije iz memorije. Provjereno nad lokalnim
release buildom: sve `thumb-1280` hero slike kreću u istom trenutku, a ne tek
na rotaciji. Na sporoj mreži nije izmjereno.

Zamka pri mjerenju: u kartici koja nije vidljiva (`document.visibilityState ==
"hidden"`) Flutter ne crta frameove, pa slike ne kreću desecima sekundi. To nije
kvar aplikacije; tako je 9.10. izgledalo kao da produkcija drži slike 33 s.

> **Dopuna 29.10.2026.:** stari `episode.json` iz Cache Storagea i CF pravilo
> koje mu je davalo `browser_ttl` 3600 skrivali su naknadno dodani Magisterium.
> Vidi `docs/2026-10-29-zastarjeli-episode-json-i-gumb-osvjezi.md`.

# Istaknuti trenuci (reels) u playeru — 26.10.2026.

LIVE od v2.0.197 (`8493395`, `1ee7d71`). Producent je `fetch.domovina.tv`
(kandidati + 9:16 render), ugovor u
`fetch.domovina.tv/docs/2026-10-25-reels-kandidati.md`.

## Što korisnik vidi

- **Trake na seek baru** za SVE kandidate (odluka korisnika): renderirani
  isječak = puna bijela traka (`onSurface`), kandidat bez videa = tanja,
  prigušena. Crtaju se iznad tracka i preko crta poglavlja; sponzori su ispod.
- **„Istaknuti trenuci"** u panelu playera (`VideoPanel`) i u `_PlayerTab`
  (`/m/`, audio-only): redak po trenutku, poredano po vremenu. Tap = skok u
  epizodu; renderirani ima poster i „Pogledaj". Redak koji svira je istaknut.
- **Vertikalni player** (`showReelViewer`, fade, ne scale): epizoda se
  pauzira; „Pogledaj u cijeloj epizodi" skoči na trenutak, X vrati epizodu u
  prijašnje stanje (svirala → svira dalje). „Kopiraj poveznicu" =
  `episodeShareUrl(id, seconds: start)` (jezik u putanji).
- Na detaljnom ekranu tap na trenutak skrola i **članak** na sekciju u koju
  pada početak trenutka (`_sectionAt`, isto pravilo kao oznake sponzora).

Kod: `lib/models/episode_reels.dart`, `lib/widgets/episode_reels.dart`,
`DataService.loadReels`, testovi `test/episode_reels_test.dart`.

```mermaid
flowchart LR
  B[episode.json files] -->|ima reels.json?| L[DataService.loadReels]
  L -->|getMutable, SWR| R[EpisodeReels]
  R --> M[trake na seek baru]
  R --> S[Istaknuti trenuci]
  S -->|tap| J[seek + scroll članka]
  S -->|Pogledaj| V[9:16 modal]
  V -->|u cijeloj epizodi| J
```

## Odluke i zašto

| Odluka | Razlog |
|---|---|
| `reels.json` samo kad ga `episode.json` navodi; bez bundlea nema reelova | datoteka postoji za ~11 epizoda; bez vrata bi svaka druga platila 404 + retry s cache-busterom |
| `reels.json` je **promjenjiv** (CDN `max-age=60, must-revalidate` + ETag od 26.10.), klijent ga čita kroz `CdnJsonCache.getMutable`, ne `_get` | pipeline ga prepisuje (poster backfill, novi renderi). S `immutable` (kako je bio) preglednik bi staru verziju držao godinu dana. Promijenjeno PRIJE nego ga je ijedan klijent dohvatio |
| poster = `render.poster_url` (540×960 WebP, ~18 kB), nikad `storyboard_url` | storyboard je kontaktni list od 6 kadrova (1128×1024); rezanje u klijentu ovisi o rasporedu |
| bez 720p varijante | odluka korisnika: sve ostaje 1080p (H.264 High@L4.0, ~4,3 Mbps, ~35 MB / 66 s) |
| traka i poglavlja u istom scrollu | 8 redaka je ~450 px; iznad scrolla su pojeli visinu panela |
| popis poglavlja u panelu playera samo kad epizoda NEMA reelova (`_showChapterList`) | uz reelove je treća kopija istih poglavlja (lijevi sidebar + sekcije članka) i njegov auto-scroll odvlačio je panel s trenutka koji je korisnik upravo tapnuo. v2.0.197 ga je ugasio svugdje (`_kShowChapterList = false`) — reelove ima desetak epizoda, pa je panel za ostatak kataloga ostao prazan ispod kontrola |
| bez novih analitičkih događaja | inače bi trebalo mijenjati pravne dokumente (CLAUDE.md, Vlastita analitika) |

## Zamke

- **Slider uvlači track** za `max(overlay, thumb)` radijus s obje strane
  (`BaseSliderTrackShape.getPreferredRect`, Flutter 3.47, kad `padding` nije
  zadan). Markeri preko cijele širine odstupali su do 14 px — u dvosatnoj
  epizodi ~5 min. Sad se crta u uvučenom rasponu (`_kSeekOverlayRadius` u
  panelu, 16 u `_PlayerTab`); popravak vrijedi i za poglavlja i sponzore.
- `primary` za trake se utopio u track i crte poglavlja (ista svijetloplava u
  tamnoj temi); crvena i zlatna su zauzete za sponzore → `onSurface`.
- Kratak trenutak (66 s u satu) je ~6 px; najmanja širina trake je 6 px.
- Tekst je na canvasu: chrome-devtools `wait_for` ga ne nalazi; klik ide
  sintetičkim `PointerEvent` na `flutter-view`, stanje provjeri preko
  `<video>` elemenata (`paused`, `currentTime`, `currentSrc`).
- Storyboard je pokazivao „4.569 €" umjesto 5.000 € (snimljen usred animacije
  brojača); video je bio ispravan. Popravljeno u pipelineu.

## Ugovor na koji se klijent oslanja

`reels.json` u `episode.json.files`; zapis treba `start_sec < end_sec` i
`title` (inače se preskače); video samo uz https `render.url`;
`render.poster_url` opcionalan. Renderirani zapisi su od `select_reels.js`
popravka (fetch `b6fc6d00`) zaključani pri ponovnom izboru; kandidati bez
rendera smiju se promijeniti, vremena su uvijek apsolutna u epizodi.

### `render.premium` — režirani isječak

Prvi je `ja70p_gJWZA` #1 („Puška mu se raspala…", 1:02:07): Opus je režirao
ilustracije usidrene na izgovorene riječi (crtež puške, ravnalo „1 m", tihi
citat), dok standardni reelovi imaju samo tekstualne kartice. Jedini signal
je `render.premium` **kao objekt** (`{ beats, tail_sec }`); izostanak ili
druga vrijednost (`true`) = standardni. Polje je aditivno i opcionalno.
Model: `EpisodeReel.isPremium`.

Odluke (Matija, 26.10.2026.):

- **Oznaka je chip „Režirano"** (`Icons.auto_awesome`, `secondaryContainer`)
  ispred vremena u retku, s tooltipom. Riječ „Premium" je namjerno izbjegnuta:
  uz DOMOVINA Plus pretplatu čita se kao zaključan, plaćeni sadržaj.
- **Redoslijed ostaje po vremenu** — oznaka ne diže režirani reel na vrh
  (prvi prijedlog je bio obratno). Test to čuva.
- **Traka na seek baru se ne mijenja**: primary, tertiary i zlatna su
  zauzete, a nova nijansa u traci od 4 px je šum.
- Poster ostaje čist kadar bez kartica (fetch `posterSec()`); poster iz
  ključnog kadra (`render.poster_sec` override) bio bi posao fetch sesije.

Provjereno u Braveu na lokalnom buildu: chip samo na „Puška…" retku, ostalih
sedam bez njega, „Pogledaj" pušta `reels/1-95dd6512.mp4`.

## Otvoreno

- **Native neprovjereno**: iOS (libmpv), Android, Android TV (EON A11,
  Philips A8) — drugi `Player` u modalu, pauza/nastavak glavnog, poster.
- TV ekran epizode nema reelove; oznake „trenutak iz ove sekcije" u članku.
- Posebna share ruta `/v/<id>/reel/<rank>` (worker OG + AASA + Android
  filter) nije napravljena; dijeli se `/t/<sec>`.
- U lijevom sidebaru je viđena narančasta oznaka na 17:50 nakon skokova —
  vjerojatno postojeće `scrollTimestamp` stanje, nije istraženo.

## Dijeljenje reela (v2.0.201)

Gumb **Podijeli** u 9:16 playeru otvara `showReelShareSheet`
(`lib/widgets/reel_share_sheet.dart`). Korisnik je tražio OBA formata:

| Redak | Što | Veličina |
|---|---|---|
| Pošalji vertikalni video (9:16) | `render.url` kao DATOTEKA kroz `shareFile` (WhatsApp…), uz tekst `episodeShareUrl(id, seconds: start)` | 30–35 MB (1080p) |
| Kopiraj vezu na video | izravni `render.url` | — |
| Preuzmi vodoravni isječak (16:9) | cutter `rangeDownloadUrl(start, ceil(end))`, isto kao poglavlja | ~27 kB/s → ~2 MB/min |
| Kopiraj vezu na vodoravni isječak (16:9) | cutter `rangeInlineUrl` | — |

Odluke i zamke:

- **Preuzimanje kreće na otvaranje lista**, a „Pošalji" se omogući tek kad su
  bajtovi tu — `navigator.share` mora pasti u svježu gestu (isti razlog kao
  e-knjiga). Pamti se samo zadnji reel (35 MB u memoriji).
- CDN za `data/<id>/reels/*.mp4` šalje `access-control-allow-origin: *`
  (izmjereno 26.10. na `DOfcONrRyDY`, `f2HIRJPHHK4`, `ja70p_gJWZA`), pa
  `http.get` iz browsera radi.
- Snackbar ide u **messenger 9:16 modala** (proslijeđen parametrom) — list je
  ruta iznad modala, pa bi `ScaffoldMessenger.of` iz lista našao korijenski
  Scaffold ispod modala.
- `isScrollControlled` + scroll: šest redaka se u zadanih 9/16 visine
  prelijevalo za 87 px (uhvatio `test/reel_share_sheet_test.dart`).
- Desktop browser ne zna dijeliti datoteke → `shareFile` preuzme MP4.
- **v2.0.202**: prva verzija je do kraja preuzimanja pisala samo „Pripremam
  video…" — na mobitelu je izgledalo kao zaglavljen list (prijava korisnika
  26.10.; zatvori-pa-otvori je „popravljao" jer je preuzimanje u međuvremenu
  završilo). Sada: `http.Client.send` + stream (http 1.6 na webu ide kroz
  `fetch` i čita tijelo kao stream) → postotak i veličina u retku; stanje je
  `ChangeNotifier` izvan lista koji redak sluša izravno; reel se pauzira dok
  je list otvoren da `<video>` ne vuče isti fajl usporedno. Ništa se ne
  generira — reel je gotov na CDN-u, samo je 1080p ~15× veći od 16:9 cutter
  isječka (360p). Ako je i s napretkom presporo, jedini pravi lijek je manji
  render (720p je korisnik ranije odbio).

Otvoreno: **nijedan put nije isproban na uređaju** — posebno iOS Safari
`navigator.share` s 35 MB videom i što WhatsApp napravi s 1080p datotekom
(vjerojatno ga sažme).

Vezani dokumenti: `docs/2026-09-15-ebook-epub-na-frontendu.md` (isti
obrazac dijeljenja datoteke), `docs/2026-09-24-sponzori-u-snimci-frontend.md` (isti
obrazac trake i oznaka), `docs/2026-10-08-brzina-ucitavanja-naslovnice.md` §8
(`episode.json`).

## Engleski tekst — `reels.en.json` (v2.0.214, 29.10.2026.)

Do v2.0.214 su na `/v/<id>/en` reelsi bili jedini hrvatski tekst u playeru.
Pipeline od 29.10. objavljuje `data/<id>/reels.en.json` (ugovor:
`fetch.domovina.tv/docs/2026-10-29-reels-en.md`): **ista shema, prevedene
vrijednosti pod istim ključevima**, bez `render` bloka i bez `rejected`.

- `DataService.loadReels` vuče EN fajl **uz** HR, ali samo kad ga
  `episode.json` navodi. Vuče ga i HR korisniku (~18 KB, samo epizode s
  reelovima), da promjena jezika ne čeka mrežu i da `_reels` ne treba
  ponovno učitavanje po jeziku.
- `EpisodeReels.fromJson(json, en: …)` spaja po `rank`; EN zapis bez HR para
  nema učinka. `forLanguage(en)` vraća **isti objekt** pri svakom pozivu
  (`late final`), jer ga ekrani zovu u buildu — nova lista na svakom buildu
  bi `didUpdateWidget` ispod čitao kao promjenu.
- Pad na HR je **po polju** (`titleEn ?? title`), a video, poster i
  režiranost uvijek iz `reels.json`. Pokvaren ili nedostupan EN fajl ostavlja
  reelove hrvatskima, ne ruši ih.
- `cards[].anchor` u EN fajlu ostaje HR (sidro na `words.json`); klijent
  kartice ionako ne čita.

Govornici: `summary.en.json` → `speakers[].suggested_name_en` (generička imena
poput „Sudionica iz publike”). `SummarySpeaker.displayNameFor(en)` /
`roleLabelFor(en)` koriste bedž preko videa, panel playera, sažetak i
jednostavni prikaz. Link na `/p/<slug>` ostaje po **izvornom** imenu. Bedž
govornika jezik dobiva kao parametar iz `EpisodeVideo.build`, jer media_kitova
fullscreen ruta crta isti widget izvan `EpisodeLanguageScope`-a; rotacijska
fullscreen ruta scope dobiva eksplicitno (v2.0.213).

Otvoreno:

- Epizode prevedene prije 29.10. nemaju `suggested_name_en` (na
  `QkcpHsj43rE` piše „Sudionica iz publike · Interlocutor”) dok fetch strana
  ne prevede sažetak ponovno s `--force`.
- EN 9:16 video ne postoji (kartice i titl su upisani u sliku); na EN
  stranici se pušta HR video uz EN tekst. Odluka je u ugovoru iznad.
- Jednom (prvo otvaranje `/v/QkcpHsj43rE/t/3342/en`, 29.10.) stranica je
  pala na HR i URL je izgubio `/en`; drugi pokušaj istog URL-a radio je.
  Nije reproducirano ni istraženo.

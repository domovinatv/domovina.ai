# Web delivery, rendering & caching

> Naučeno tijekom debug sesije 2026-06-29/30 (v2.0.61 → v2.0.64). Tri teme koje
> se zajedno objašnjavaju jer su se manifestirale kao **jedan** simptom
> ("homepage bez slika"), a imale tri različita uzroka.

DOMOVINA.ai je Flutter web app na Cloudflare Pages. Sav per-episode/per-channel
sadržaj loada se runtime s `cdn.domovina.ai`. Render je `--wasm` (skwasm GPU) s
canvaskit/dart2js fallbackom. Ova kombinacija (Flutter crta sve sam na canvas +
SW caching + cross-origin CDN) ima nekoliko ne-očiglednih zamki.

---

## 1. Channel list rendering & "scroll lag"

### Problem
Home je renderirao **sve kanale (44+) eager** u jednom `SliverToBoxAdapter` →
`Wrap`. Svaka `ChannelCard` živi u stablu i sudjeluje u **rasterizaciji svakog
scroll frame-a**. Na webu (skwasm) to je skupo jer se sadržaj re-rasterizira po
frameu na glavnoj niti → vidljiv jank. (Na nativnom iOS/Android isti eager build
je jeftin — bolji GPU pipeline + raster na zasebnoj niti.)

### Ključni uvid
Lag NIJE bio broj kartica per se — to je **per-frame raster** trošak, ne
build/layout trošak (koji se plaća jednom). Ali kako lista raste (44 → 100+),
lazy rendering postaje nužan. Riješeno seljenjem punog popisa s home-a.

### Rješenje — `/channels` lazy surface
`lib/screens/channels/all_channels_screen.dart`:
- **Lazy `SliverList` po REDOVIMA**, NE `SliverGrid`. Razlog: kanal kartice imaju
  varijabilnu visinu (banner vs square layout, 1–2 linije naziva), a `SliverGrid`
  forsira uniformnu visinu ćelije → clipanje. Red drži prirodne visine
  (top-aligned), `SliverList` recycle-a off-screen redove.
- Dijakritik-aware filter (`localMatchScore` iz `lib/utils/text_search.dart`).
- Home sad ima samo lagani **"Svi kanali (N) →" CTA** koji vodi na `/channels`.

```mermaid
flowchart LR
  subgraph before["PRIJE — sve na home-u"]
    H1[Home CustomScrollView] --> W["SliverToBoxAdapter<br/>Wrap: 44 ChannelCard<br/>EAGER, svi paintani"]
  end
  subgraph after["POSLIJE — odvojeno"]
    H2[Home CustomScrollView] --> CTA["'Svi kanali 44 →' CTA<br/>lagano"]
    CTA -->|navigate| CH["/channels AllChannelsScreen"]
    CH --> SL["SliverList po redovima<br/>LAZY, recycle off-screen<br/>+ dijakritik filter"]
  end
```

**Pravilo:** za duge liste varijabilne visine na webu koristi `SliverList` po
redovima (ne `SliverGrid`), i ne drži ih sve u home scroll viewportu.

---

## 2. Prefetch race condition ("0/44 kanala, nema slika")

### Simptom
Homepage bez hero slike i thumbnaila; header zaglavljen na "Učitavam 0/44
kanala…". Intermitentno: na iOS Safari/5G radilo, na desktopu ne. Pojavilo se
nakon deploya koji je **olakšao** home (CTA umjesto 44 kartice).

### Root cause — latentni race
`channelCache.prefetchAll()` (loada per-channel detalje s kojih dolaze
hero/thumbnail podaci) zvao se iz `onChannelsLoaded` **iza** ovog reda:

```dart
if (!_simpleModeLoaded) return;   // ⟵ vrati PRIJE prefetchAll
_channelCache.prefetchAll(channels);
```

`onChannelsLoaded` okida post-frame callback kad index stigne. `_simpleModeLoaded`
postaje `true` tek kad async `loadSimpleModePref()` završi. **Dva neovisna async
toka → race.** Ako index stigne prije pref-a → early return preskoči prefetch
ZAUVIJEK (callback okida samo jednom) → 0/44, prazne slike.

Lakši home build je promijenio frame-timing pa je "loš" ishod postao čest na
desktopu. iOS/5G je imao drukčiji timing → "dobar" ishod → "radi na mobitelu".

```mermaid
sequenceDiagram
  participant I as loadIndex()
  participant S as loadSimpleModePref()
  participant O as onChannelsLoaded (post-frame)
  participant P as prefetchAll()

  Note over I,S: dva NEOVISNA async toka (race)
  rect rgba(255,80,80,0.12)
    Note over O,P: PRIJE (buggy) — index stigne prvi
    I->>O: index ready → post-frame
    O->>O: _simpleModeLoaded == false?
    O--xP: if(!loaded) return — prefetch PRESKOČEN
    S-->>O: (prekasno; callback se ne ponavlja)
  end
  rect rgba(80,200,120,0.12)
    Note over I,P: POSLIJE (fix) — prefetch vezan na index
    I->>P: _indexFuture.then(prefetchAll)  // deterministički
    Note right of P: neovisno o simpleMode i build timingu
  end
```

### Fix
Prefetch vezan na index future u `initState`, potpuno odvojen od build-timinga i
simpleMode-a. `prefetchAll` ima vlastiti guard protiv dvostrukog pokretanja.

```dart
_indexFuture = _channelCache.loadIndex();
_indexFuture.then((index) => _channelCache.prefetchAll(index.channels));
```

**Pravilo:** background prefetch/side-effecte NE vezuj za nepovezane async
preffove ni za widget build/post-frame timing. Veži ih na konkretan future
(ovdje: index) ili u `initState`. Inače latentni race čeka da ga promjena
timinga otkrije.

---

## 3. Service Worker staleness & cache busting

### Simptom
Nakon deploya, postojeći browseri serviraju **staru** verziju — čak i s hard
refreshom i "Disable cache" u Network tabu. Tek **gašenje i ponovno pokretanje
browsera** dovuče novu verziju.

### Zašto hard refresh ne pomaže
Service Worker **presreće fetcheve** i servira iz svog `CacheStorage`, neovisno o
HTTP cacheu. "Disable cache" gasi BROWSER HTTP cache, NE SW cache. Hard refresh
(većinom) zaobiđe HTTP cache ali ne pouzdano i SW. Novi SW ide u **"waiting"**
stanje i preuzme tek kad se **svi tabovi zatvore** → zato restart browsera radi.

### Što se zapravo dogodilo
Stari **offline-first caching SW** (iz ranijih buildova) zaostao je u browserima.
Flutter 3.41 je promijenio default `flutter build web` da generira
**self-unregistering "tombstone" SW** (`install→skipWaiting`,
`activate→registration.unregister()+navigate`) — de-facto `pwa-strategy=none`,
iako te zastavice NEMA u repou. Taj tombstone makne stari SW, ali tek kad stari
pusti kontrolu (restart).

```mermaid
stateDiagram-v2
  [*] --> LegacyControlling: stari caching SW iz ranijih buildova
  LegacyControlling --> NewWaiting: deploy → novi tombstone SW se instalira
  NewWaiting --> LegacyControlling: hard refresh / disable cache<br/>(NE pomaže — stari SW i dalje kontrolira)
  NewWaiting --> Activated: svi tabovi zatvoreni (restart)<br/>ILI controllerchange→reload
  Activated --> NoSW: tombstone unregistra sebe
  NoSW --> [*]: bez caching SW → svaki deploy svjež
```

### Cache header strategija (živi u `web/_worker.js`, NE u `_headers`)
> KRITIČNO: `web/_headers` se NE aplicira kad worker rukuje requestom kroz
> `env.ASSETS.fetch()` (Cloudflare Pages Advanced Mode contract). Cache headere
> MORAŠ postaviti u workeru.

| Resurs | Cache-Control | Zašto |
|---|---|---|
| HTML (index/SPA rute) | `no-store` | uvijek svjež entry-point |
| `flutter_bootstrap.js`, `main.dart.{js,wasm,mjs}`, `flutter.js`, `skwasm*`, `manifest.json`, `favicon.png` | `public, max-age=0, must-revalidate` + `CDN-Cache-Control: no-store` | isti URL na svaki rebuild → ETag revalidate (304 ili novi bytes) |
| Hashed asseti (`canvaskit/*`, `assets/*`) | `immutable, max-age=31536000` | URL se mijenja kad se sadržaj promijeni |

### Mitigacija dodana v2.0.64
Guarded `controllerchange → reload` u `web/index.html` — kad se stari SW makne
(controller se promijeni), reload JEDNOM, pa legacy korisnici ne moraju restartati
browser. Guard na `navigator.serviceWorker.controller` → samo korisnici koji
STVARNO imaju stari SW reloadaju; čisti/novi nemaju controller → nema suvišnog
reloada.

### ⚠️ Otvoreno pitanje — iOS background audio
Persistent SW je bio **namjerno** vraćen (2026-05-17) jer je nužan za iOS
cross-app background audio (PWA install → standalone privilegije). Flutter 3.41 ga
je tiho maknuo. **Treba re-verificirati radi li iOS background audio još.** Ako
ne → treba CUSTOM persistentni SW (registriran radi iOS audija) ali bez agresivnog
app-shell cachiranja, ILI offline-first + skipWaiting/claim/reload. Vidi
`feedback_no_service_worker` memoriju.

---

## 4. Debugging Flutter web slika — decision tree

Kad slike (thumbnaili/hero/screenshotovi) ne crtaju, NE pretpostavljaj uzrok —
prođi ovim redom. Svaki je bio razmatran u ovoj sesiji; samo zadnja dva su bili
stvarni uzroci.

```mermaid
flowchart TD
  A[Slike crne/prazne] --> B{CDN fajl<br/>vraća 200?}
  B -->|404| B1[CDN/pipeline problem<br/>— ne app]
  B -->|200| C{CORS header<br/>access-control-allow-origin?}
  C -->|nema| C1[Dodaj CORS na CDN]
  C -->|ima *| D{Podaci uopće<br/>stignu? hero/rail<br/>popunjeni?}
  D -->|ne, 'Učitavam 0/44'| D1["PREFETCH RACE<br/>(sekcija 2)"]
  D -->|da, ali slike crne| E{Konzola:<br/>'webGLVersion is -1'?}
  E -->|da| E1["HEADLESS browser bez WebGL<br/>→ canvaskit CPU fallback<br/>→ network slike NE crtaju<br/>ARTEFAKT TESTA, ne app"]
  E -->|ne, pravi browser| F{iOS WebKit, crne/sive<br/>tek nakon POVRATKA?}
  F -->|da| F1["&lt;img&gt; dekoder: naturalWidth 0<br/>→ WebBitmapImage<br/>(docs/2026-11-07-slike-webkit-img-decode.md)"]
  F -->|ne| E2[Stvarni paint bug<br/>— istraži dalje]
```

- **iOS WebKit (7.11.2026.)**: `ImageCodecException: Failed to create image
  from Image.decode` pri ponovnom prikazu slike — enginov `<img>` dekoder.
  Web zato crta `WebBitmapImage` (`createImageBitmap`); dijagnostika s iPhonea
  kroz `scripts/serve-debug-web.py` + Tailscale. Vidi
  `docs/2026-11-07-slike-webkit-img-decode.md`.

### Glavne zamke iz ove sesije
- **COEP `credentialless`** (worker emita COOP/COEP za skwasm SharedArrayBuffer)
  djelovao je kao sumnjivac, ALI nije bio — `fetch` + `createImageBitmap` +
  `<img crossorigin>` svi rade u page kontekstu pod COEP-om. Provjeri JS probe-om
  prije nego okriviš COEP.
- **Headless/automation Chrome nema WebGL** (`webGLVersion is -1`) → canvaskit
  CPU-only → slike izgledaju puknuto. NIJE app bug. Verificiraj LOGIKU preko
  konzolnih logova (`ChannelCache: done, 44/44 cached`) i Network 200, vizualni
  paint slika prepusti pravom browseru. Vidi `feedback_headless_browser_no_webgl`
  memoriju.

---

## 5. Debugging Flutter web fontova — je li font uopće registriran?

Izmjereno 25.8.2026. Prijava je glasila „font ne radi dobro, negdje slovo
nestane". Stvarni nalaz je bio veći: **Playfair i Lora se na webu uopće nisu
primjenjivali**, a nestali glyphovi bili su posljedica toga (async Noto fallback
stiže po glyphu). Popravak i pravilo su u `CLAUDE.md`; ovdje je metoda kojom se
to utvrdi, jer je pogrešno zaključivanje ovdje jeftino i tiho.

### Zašto je zamka tiha

Flutter na webu **ne javlja grešku** kad fontFamily ne postoji — samo padne na
fallback. Vizualno to izgleda kao „font je malo drukčiji", ne kao kvar. A
`document.fonts` pritom uredno kaže da je font učitan, jer CSS sloj i Flutterov
canvas sloj **nisu isti font registar**.

```mermaid
flowchart TD
  L["&lt;link&gt; Google Fonts<br/>u index.html"] --> CSS[CSS @font-face<br/>document.fonts]
  CSS --> DOM["DOM tekst<br/>(boot-intro splash)"]
  CSS -.->|"NE stiže"| SK
  GF["google_fonts paket<br/>fetch + loadFontFromList"] --> SK[Flutter FontCollection<br/>canvaskit / skwasm]
  SK --> CANVAS[Flutter tekst<br/>na canvasu]
  SK -.->|"family nije registriran"| FB["fallback font<br/>+ async Noto po glyphu"]
  FB --> CANVAS
```

Stari HTML renderer je crtao tekst DOM-om, pa je lijeva grana radila. Otkako ga
nema (Flutter 3.29+), `<link>` hrani samo DOM.

### Probe koje razdvajaju slojeve

U konzoli (radi i dok je canvas još prazan — a u automation browseru to traje
20–30 s, vidi §4):

```js
// 1. Koji renderer? Ako je falsy → skwasm (--wasm build).
!!window.flutterCanvasKit

// 2. Vidi li CSS sloj font? (ovo NE dokazuje da ga Flutter koristi)
document.fonts.check('40px "Playfair Display"')

// 3. Je li font stvarno drukčiji od fallbacka? Usporedi širine.
//    Ako playfair == serif, @font-face nije primijenjen ni u DOM-u.
const w = ff => { const s = document.createElement('span');
  s.textContent = 'Spremi Susreo'; s.style.cssText =
  'position:absolute;visibility:hidden;font-size:40px;white-space:nowrap;font-family:'+ff;
  document.body.appendChild(s); const r = s.getBoundingClientRect().width;
  s.remove(); return Math.round(r); };
({ playfair: w('"Playfair Display",serif'), serif: w('serif') })
```

**Dokaz za canvas sloj postoji samo vizualno**: zumiraj naslov i wordmark. Serif
s jakim kontrastom debljine = Playfair radi. Sans = ne radi, bez obzira što
`document.fonts` tvrdi. Probe 2 i 3 su nužni, ali nisu dovoljni.

### Vezani dokumenti
- `CLAUDE.md` → „Fontovi na webu — `<link>` u index.html NE oblikuje Flutter
  tekst" (pravilo + `AppTypography._usedVariants` obveza)
- `docs/tech-stack-assessment-flutter-vs-expo.md` — još jedna stavka u kolonu
  „web zamke su omeđene i dokumentirane"

---

## 6. COEP zabranjuje SVAKI tuđi iframe (YouTube, i sve buduće)

### Simptom
Ugrađeni YouTube player crn, poruka **„www.youtube-nocookie.com refused to
connect"** (izmjereno 26.8.2026. na produkciji, v2.0.143).

### Uzrok — naš header, ne YouTubeov
YouTube na `/embed/<id>` vraća `200` **bez** `X-Frame-Options` i **bez**
`frame-ancestors` — dakle ništa s njegove strane ne brani ugrađivanje:

```bash
curl -sI -H "Referer: https://domovina.ai/" \
  https://www.youtube-nocookie.com/embed/<ytId> | grep -iE "http/|x-frame|frame-ancestors"
# → HTTP/2 200, i ništa drugo
```

Brani **naš** `web/_worker.js`, koji za HTML odgovore šalje:

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: credentialless
```

Pod COEP-om **ugniježđeni dokument mora sam poslati COEP** da bi bio ugradiv.
YouTube ga ne šalje → browser odbije frame. `credentialless` je pritom već
blaža varijanta od `require-corp`, ali za *iframeove* ne pomaže: ona samo
skida zahtjev za CORP-om s pod-resursa.

### Zašto COEP uopće postoji ovdje
`SharedArrayBuffer` je iza cross-origin izolacije, a Flutterov bootstrap bira
renderer po `window.crossOriginIsolated`:

| izolacija | binary | raster |
|---|---|---|
| da | `canvaskit/skwasm_heavy.wasm` (5,1 MB) | zasebna nit |
| ne | `canvaskit/skwasm.wasm` (3,5 MB) | **glavna nit** |

Glavna nit je točno uzrok janka opisanog u §1, pa se izolacija ne skida bez
razloga — cijena je 1,6 MB više downloada, dobitak je raster izvan glavne niti.

### Rješenje: `credentialless` iframe + feature detection
`<iframe credentialless>` (Chrome/Edge 110+) je jedini način da dokument pod
COEP-om ugradi frame koji COEP ne šalje. Atribut se MORA postaviti **prije**
`src` — čita se pri pokretanju navigacije.

Safari i Firefox ga ne podržavaju, pa se ondje embed **ne smije ni ponuditi**:
`youtube_embed_web.dart` vraća `supported == false` kad je stranica izolirana a
atribut nepodržan, i facade tada otvori youtube.com u novoj kartici umjesto da
korisnik dobije crnu plohu.

```dart
supported = !crossOriginIsolated || ('credentialless' in HTMLIFrameElement.prototype)
```

### Što ovo znači za buduće integracije
**Rule**: dok worker šalje COEP, **nijedan** tuđi iframe ne radi u Safariju ni
Firefoxu — ni YouTube, ni Cal.com booking widget, ni hostani checkout. Integracija
treće strane zato ide preko **API-ja**, ne iframea (kao što `cal_booking_native.dart`
već radi nad Cal.com API-jem v2). Ako neka budućnost traži iframe na svim
browserima, odluka je: skinuti COOP/COEP i pristati na jednodretveni skwasm.

Napomena: isti je kvar tiho nosio i postojeći „YouTube mode" gumb u
`video_panel.dart` — bio je neupotrebljiv otkad postoji, samo ga nitko nije
otvorio na izoliranoj stranici. Feature detection ga sad sakrije umjesto da
ponudi nešto što ne radi.

### Što ugrađeni player NE može — reklame

Pitanje koje se vraća: u **Braveu** na `/v/<id>` nema YouTube reklama, u
**Chromeu/Edgeu** ih ima. Nije razlika u našem kodu.

- Naš embed je **pravi `<iframe>`** u DOM-u stranice (`HtmlElementView` →
  `web.HTMLIFrameElement`), **ne webview**. Ponaša se kao YouTube bilo gdje.
- Brave blokira oglase **na razini mreže**, prije nego išta dođe do naše
  stranice. Isti naš kod, tri browsera, tri ishoda.
- Ne možemo utjecati: iframe je cross-origin (`youtube-nocookie.com`), pa
  same-origin policy ne da čitati ni mijenjati njegov DOM. Službeni IFrame
  Player API daje `play`/`pause`/`seek` i stanja, ali oglase **ne izlaže niti
  preskače** — namjerno.
- Zaobilaženje bi ionako kršilo YouTube ToS i pravilo iz CLAUDE.md.

**Pravi put do „bez reklama" je `mediaReady`**: naša CDN kopija
(`video_h264.mp4`) nema oglasa jer je streamamo sami, i čim sjedne, embed
nestaje a primarno postaje naš player. Dakle rješenje je **skratiti vrijeme do
obrade** (`docs/2026-08-26-episode-processing-status.md` §6.3 — backlog 14–25
dana), ne adblock.

Protuteža koju ne treba zaboraviti: naš CDN video je **360p**, a embed daje puni
izvor **do 4K**. Embed nije samo privremeni most nego i kvaliteta koju ne hostamo
— zato „YouTube mode" gumb postoji i na epizodama koje imaju našu mediju.

### Vezano
- `lib/widgets/youtube_embed_web.dart` — detekcija + atribut
- `docs/2026-08-26-episode-processing-status.md` — zašto epizoda uopće nudi YouTube
- §1 gore — jank zbog rastera na glavnoj niti (razlog da COEP ostane)

---

## Brze dijagnostičke komande

```bash
# CDN slika — postoji + CORS?
curl -sI -H "Origin: https://domovina.ai" https://cdn.domovina.ai/images/<ytId>/thumbnail.png \
  | grep -iE "http|access-control|cache-control"

# Bootstrap revalidira? (mora biti max-age=0, must-revalidate)
curl -sI https://domovina.ai/flutter_bootstrap.js | grep -i cache-control

# Service worker stanje (u browser konzoli)
await navigator.serviceWorker.getRegistrations()
navigator.serviceWorker.controller?.scriptURL
await caches.keys()

# COEP — je li stranica cross-origin izolirana? (u browser konzoli)
crossOriginIsolated                              // true → skwasm_heavy, tuđi iframe traži credentialless
'credentialless' in HTMLIFrameElement.prototype  // false u Safariju/Firefoxu

# Brani li YouTube ugradnju? (spoiler: ne brani — COEP je naš)
curl -sI https://www.youtube-nocookie.com/embed/<ytId> | grep -iE "http/|x-frame|frame-ancestors"
```

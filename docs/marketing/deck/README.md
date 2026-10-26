# Deck — izvor

`domovina-seed.html` je izvor seed decka. Objavljuje se kao Artifact; da URL
ostane isti, republish ide **na istu putanju** (ili iz druge sesije s `url`
parametrom).

**Živi URL**: https://claude.ai/code/artifact/5b532553-08b3-497e-8e14-f57f9c886dc1

Strategija, priprema po fondu i zabranjene tvrdnje:
[`../vc-pitch-strategija.md`](../vc-pitch-strategija.md).

## Pravila

- **Bez emojija** (brand pravilo iz `pitch-deck` repoa).
- Navy `#002F6C` + zlato `#C8912A` / `#E3AF35`; Fraunces + Inter.
- Nijedna brojka bez izvora. Sve što nije potvrđeno ide na slajd 12, ne van.
- Slajd rizika (**14**) se **ne briše** da deck izgleda jače.
- **Rule (nijedan primjer nije izmišljen)**: slajd 4 crta pravu epizodu iz
  korpusa, s pravim poglavljima i klikabilnom poveznicom. Maketa je najjači
  signal da je deck generiran; provjerljiv primjer je najjači protusignal.
  Novi primjer se vadi iz MCP-a (`get_episode`), ne piše rukom.

## Slike

Artifact je jedna samostalna HTML datoteka — **relativne putanje do slika ne
rade** pri objavi. Screenshotovi se zato ugrađuju kao `data:` URI. Izvori žive u
`shots/` (JPEG, dulja stranica 1160 px, kvaliteta ~74) da se mogu zamijeniti:

```bash
sips -Z 1160 shot.png --out s.png
sips -s format jpeg -s formatOptions 74 s.png --out shots/shot-home.jpg
```

Uzeti su sa **žive produkcije**, ne iz lokalnog builda. Flutter na
`domovina.ai` traži ~30 s do prvog painta u automatiziranom Chromeu — prerani
screenshot je prazna stranica, ne puknuta stranica.

Ponovno snimanje: `node scripts/deck-shots.mjs` (headed sistemski Chrome,
1440×817 @2x, 45 s po stranici).

**Rule (prije zamjene pogledaj što je na slici)**: 26.10.2026. novi shotovi
NISU ugrađeni. Naslovnica od v2.0.200 nema glasanje, a opis ispod slike i dalje
tvrdi „the public creator vote”. Epizoda je na dnu nosila „Sponzorski trenuci —
DOMOVINA TV · Prikupljeno 0 €” (bug iz
`../../plans/2026-10-06-mvp-sponzorski-trenuci-zakljucak.md`, backend 1) i
„Uključi zvuk” preko videa. Opis i slika mijenjaju se zajedno.

## Layout

Deck mora stati u ekran bez scrolla na **svakoj** projektorskoj rezoluciji od
1024×768 naviše. Provjereno mjerenjem 26.8.2026. na 1024×768, 1152×720,
1280×720, 1366×768, 1440×900, 1600×900 i 1920×1080 — nula prelijevanja.

- **Rule (gustoća se ne piše u px nego u tokenima)**: `--gap`, `--gap-s`,
  `--cellpad`, `--lipad`, `--srcgap` u `:root`, stisnu se na `max-height:880px`
  i `max-height:800px`. Novi razmak na slajdu ide kroz njih; hardkodirani
  `margin-top` preživi na 1080p i pukne na 720p.
- **Rule (ne ugnježđuj grid u grid za natuknice)**: `ul.plain li` je hanging
  indent (`padding-left` + apsolutna `::before`), ne `display:grid`. Prethodna
  grid izvedba je unutar dvostupčanog `ul.plain.split` razriješila `auto 1fr`
  obrnuto — crtica 409 px, tekst 89 px — i napuhala slajd 12 za 797 px.
- **Rule (labela se ne dimenzionira prema onome na što pokazuje)**: vremenska
  os na slajdu 4 nosi samo `00:00` / `1:44:04`, a objašnjenje je `.tcall` pune
  širine. Ranija flex labela proporcionalna svom segmentu dobila je 114 px.
- Snap je `proximity`, ne `mandatory`, a **Dalje** stranicu viši od ekrana
  prelistava kroz nju prije nego prijeđe na sljedeću — inače je donja polovica
  nedostupna iz kontrola.

## PDF

```bash
node scripts/deck-pdf.mjs                  # build/marketing/domovina-seed.pdf
node scripts/deck-pdf.mjs --size 1920x1080 # veća projektorska kutija
node scripts/deck-pdf.mjs --out ~/Desktop/domovina-seed.pdf
```

Izlaz ide u `build/` — **nije u gitu, i tako ostaje**: repo je javan, a deck ide
fondovima izravno. Print stilovi žive u `@media print` bloku na dnu `<style>` u
samom decku, pa je render na ekranu nepromijenjen.

Troja vrata, jer PDF laže na tri načina i sva tri se vide tek kad ga netko
otvori pred fondom. Pad = izlaz 1 i **PDF se ne piše** (`--skip-gate` gazi):

| vrata | mjeri | zašto |
|---|---|---|
| prelijevanje | `rect.height - visina > 0` na 1024×768, 1280×720, 1920×1080 | isti prag kao orakl; headless Playwright postavlja viewport točno, pa iframe iz prošlog kruga nije potreban |
| broj stranica | `/Count` iz stabla stranica == broj `.slide` sekcija | jedan piksel viška po slajdu daje 32 stranice, svaka druga prazna — PDF se pritom uredno otvori |
| veličina stranice | `/MediaBox` == 960×540 pt | broj stranica prođe i kad je kutija kriva; deck prelomljen u A4 portret je uredan PDF i neupotrebljiv na projektoru |

Exit kodovi su ugovor, kao kod `voting-drift-check`: **0** prošlo, **1** deck
pada na vratima, **2** ne mogu provjeriti (nema chromiuma, deck se ne učita,
PDF nečitljiv). Ne miješati „ne znam" s „deck je puknuo".

**Rule (`--size` mora ući kroz `addStyleTag`)**: `preferCSSPageSize` daje CSS-u
zadnju riječ, a deck ima `@page{size:1280px 720px}` tvrdo upisan — dok se
zatraženi format nije ubrizgavao kao kasnije print pravilo, `--size 1920x1080`
je tiho davao stranicu od 960×540 pt. Uhvatila su ga vrata veličine.

**Rule (čeka se `document.fonts.ready`)**: Fraunces i Inter dolaze s Google
Fontsa. Bez tog čekanja prvi izvoz padne na Georgiju i to se vidi tek u gotovom
PDF-u. Provjera ide `pdffonts` — u ispravnom izvozu su ugrađeni samo Fraunces i
Inter rezovi.

**Poznato**: slajd 9 povlači `TimesNewRomanPS-BoldMT` za **jedan znak** — strelicu
`→` u „€45M → €1M", koje Fraunces nema. Renderira se uredno jer Times tu jest,
ali glif ovisi o stroju koji izvozi; ista klasa problema kao `⏱` u OG slikama.

Chromium: skripta prvo pokuša Playwrightov headless shell, pa njegov puni
chromium, pa **sistemski Chrome**. Na ovom stroju prolazi tek treći — cache je
imao shell krive revizije (1223 uz playwright koji traži 1208), a `chromium-1208`
je raspakiran bez svog frameworka i gasio se uz „Target page, context or browser
has been closed". Uz taj ispad render ovisi o lokalno instaliranom Chromeu, ne o
verziji prikovanoj u `package.json`.

## Zašto ovo uopće ima orakl

Mjerenja iz prolaza 26.–27.8.2026. — koje su provjere mehaničke, koliko su
slajdova stvarno probile i zašto: [`../../2026-08-26-pitch-deck-orakl.md`](../../2026-08-26-pitch-deck-orakl.md).
Taj dokument je ulaz za `provjeri.sh` pitch vertikale u `claude-tmux-teams`,
koji još nije napisan.

## Otvoreno

Vidi „Sljedeći krug" u [`../vc-pitch-strategija.md`](../vc-pitch-strategija.md).

Nakon svakog republisha **pomakni share pin** — vanjski čitatelji inače ostaju
na staroj verziji.

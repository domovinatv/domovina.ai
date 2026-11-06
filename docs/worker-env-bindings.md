# Worker — brend kroz env bindinge

**Datum:** 18. 9. 2026. **Opseg:** `web/_worker.js`, `wrangler.toml`.

Cloudflare Pages worker (`web/_worker.js`) je do sada imao brend upisan u
konstante: host stranice i CDN-a, person/MCP API, Apple Team ID, iOS bundle
ID, Android paket i potpisni otisci, ime brenda u OG/meta/JSON-LD. Od ovog
koraka sve to dolazi iz **env bindinga Pages projekta**, s defaultima koji su
današnje DOMOVINA.ai vrijednosti. Rezultat: **jedan worker, dva Pages
projekta** (DOMOVINA.ai i Podcasterium), bez grananja u kodu i bez kopije
datoteke. Plan i pravilo: `podcasterium-app/docs/02-brand-layer-and-rebranding.md` (sestrinski repo) §1.2 u
repou `podcasterium-app` (tamo, ne ovdje).

## Kako radi

- `brandFromEnv(env)` na vrhu `web/_worker.js` čita bindinge i vraća objekt
  brenda; `fetch()` ga poziva **na početku svakog zahtjeva** i rezultat
  dodjeljuje modulnim varijablama `SITE`, `CDN`, `PERSON_API`, `PERSONS_API`,
  `APP_NAME` te objektu `BRAND` (zastavice, App Links vrijednosti).
- Env je isti za sve zahtjeve jednog deploya, pa je ponovna dodjela
  idempotentna; time ostatak datoteke (51 mjesto `SITE`, 29 mjesta `CDN`)
  ostaje netaknut umjesto da se brend provlači kroz svaki helper.
- `.well-known` odgovori (`assetlinksJson`, `aasaJson`, `webauthnJson`) i
  ključevi sitemap cachea (`sitemapCacheUrl`, `sitemapLastCacheUrl`) više
  nisu modulne konstante nego funkcije — inače bi se izračunali jednom, iz
  defaulta, prije nego je `fetch()` vidio env.
- **Bez ijednog bindinga izlaz workera je bajt-identičan** onome prije
  promjene, za svaku rutu. Provjereno 18. 9. 2026. Node harnessom koji je
  stari i novi worker (isti `ASSETS` mock, isti canned CDN/API odgovori,
  `env = {}`) pokrenuo kroz 29 ruta — status, zaglavlja i tijelo jednaki u
  29/29.

Bindinzi su **stringovi** (Pages ne poznaje druge tipove). Zastavice se
uspoređuju kao string: samo točno `"true"` uključuje; `"1"`, `"TRUE"`,
`"yes"` isključuju. Popisi su zarezom odvojeni; prazan string = default.

## Bindinzi

| Binding | Default (DOMOVINA.ai) | Rute / mjesta koja dira |
| :-- | :-- | :-- |
| `SITE` | `https://domovina.ai` | canonical, `og:url`, `og:logo`, hreflang i JSON-LD URL-ovi na `/v/*`, `/m/*`, `/p/*`, `/c/*`, `/c/*/doniraj`, `/glasanje*`; sve `<loc>` u `/sitemap.xml` i ključevi Cache API-ja (`__cache/…`); host u AASA komentaru airKUNA unosa |
| `CDN` | `https://cdn.domovina.ai` | dohvat `info.json`, `summary*.json`, `article*.json`, `og-sections.json`, HEAD `og-share.jpg`; `og:image`/`og:video` na `/v/*`; avatar osobe na `/p/*`; `channels/data/*.json` za `/c/*` i sitemap |
| `PERSON_API` | `https://mcp.domovina.ai/api/person` | profil osobe za `/p/<slug>` |
| `PERSONS_API` | `https://mcp.domovina.ai/api/persons` | popis osoba za `/sitemap.xml` |
| `APP_NAME` | `DOMOVINA.ai` | sufiks `<title>`, `og:site_name`, `og:image:alt`/`twitter:image:alt`, JSON-LD `publisher`/`provider`, fallback naslova i kanala epizode, tekst opisa na `/p/*`, `/c/*`, `/glasanje*` |
| `APPLE_TEAM_ID` | `6SCK58757K` | `appID` i `webcredentials.apps` u `/.well-known/apple-app-site-association` (i airKUNA `appID`) |
| `IOS_BUNDLE_ID` | `ai.domovina` | isto (drugi dio `appID`) |
| `ANDROID_PACKAGE` | `ai.domovina` | `package_name` u `/.well-known/assetlinks.json` |
| `ANDROID_SHA256` | dva otiska (Play App Signing key, upload key) — vidi `wrangler.toml` | `sha256_cert_fingerprints` u `/.well-known/assetlinks.json`; zarezom odvojeno |
| `WEBAUTHN_ORIGINS` | 15 origina domovina/pinka ekosustava — vidi `wrangler.toml` | `origins` u `/.well-known/webauthn`; zarezom odvojeno |
| `CATALOG_API` | `https://domovina.ai/api/katalog/v1` (prazno kad je postavljen `SITE`, tj. drugi brend) | bazni URL kataloga za `/dani/*` OG, `/dani/` u sitemapu i OG Tier 2 kanala na `/c/*`; prazan string gasi sve troje |

Tajne koje worker već čita iz env-a i **nisu** brend (ostaju Pages secrets po
projektu): `CAL_API_KEY`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`.

## Service binding `KATALOG` (od S11 kataloga, 6. 11. 2026.)

`[[services]] binding = "KATALOG"`, `service = "domovina-katalog"` u
`wrangler.toml`. Worker `domovina-katalog` (`katalog/`) živi na ruti
`domovina.ai/api/katalog/*`, a ruta ne može biti meta same-zone `fetch()`-a iz
Pages workera (vratio bi se u Pages i dobio SPA HTML), pa `catalogGet` u
`web/_worker.js` zove katalog SAMO kroz binding. Služi:

- `/dani/<datum>`: `og:description` s brojem epizoda i imenima kanala;
- `/c/<tier2-slug>`: OG s imenom i brojem epizoda, a nepostojeći slug dobiva
  `X-Robots-Tag: noindex`.

Bez bindinga (drugi brend, greška, timeout 800 ms) obje rute padaju na
statične tagove odnosno plain SPA; ništa ne puca. Provjera nakon deploya:
`curl -s https://domovina.ai/dani/<jučer> | grep -o '<meta property="og:description"[^>]*>'`
mora spominjati epizode, `curl -s https://domovina.ai/c/tribina | grep -o '<meta property="og:title"[^>]*>'`
mora sadržavati „Tribina”.

## Zastavice

| Zastavica | Default | `"false"` isključuje |
| :-- | :-- | :-- |
| `FEATURE_VOTING` | `true` | rutu `/glasanje` i `/glasanje/<slug>` (padaju na SPA fallback s generičkim OG-om) **i** oba `/glasanje*` unosa u AASA `components` |
| `FEATURE_CAL` | `true` | Cal.com proxy `/api/cal/slots` i `/api/cal/book` (padaju na SPA fallback kao svaka nepoznata ruta) |
| `FEATURE_AIRKUNA` | `true` | airKUNA wallet unos u `assetlinks.json` (`com.airkuna.wallet`) i u AASA `details` |

Zastavice ne diraju Android intent filter u `AndroidManifest.xml` — on je
allowlist u appu, a ne u workeru (vidi `CLAUDE.md`, „Universal/App Links”).
Brend koji gasi `FEATURE_VOTING` mora `/glasanje` maknuti i iz manifesta pri
generiranju platformskih direktorija.

## Što nije parametrizirano (namjerno)

- **Jezik**: `hr_HR`, `inLanguage: 'hr'`, hrvatski opisi na `/p/*`, `/c/*`,
  `/glasanje*`, hrvatska množina (`croPlural`). To je i18n workera, zaseban
  korak; ovdje se mijenja samo ime brenda unutar tih rečenica.
- **Cal.com konstante** (`CAL_EVENT_TYPE_ID`, `CAL_TIMEZONE`): drugi brend
  gasi proxy zastavicom, ne mijenja event type.
- **Putanje brend asseta** (`/og-image.png`, `/og-image-square.png`,
  `/icons/Icon-512.png`): relativne na `SITE`; svaki brend ih generira na
  istim putanjama (`web/og-image.png`, `web/icons/`).
- **`apple-itunes-app` meta i App Store ID**: nisu u workeru nego u
  `web/index.html`, koji se generira po brendu u kasnijem koraku.
- **Supabase shema** `domovina_ai` u `fetchVoteCandidate`: živi iza
  `FEATURE_VOTING`.

## Postavljanje za drugi brend (primjer Podcasterium)

U Pages projektu drugog brenda (Settings → Environment variables, Production
i Preview) postaviti:

```
SITE=https://podcasterium.com
CDN=https://cdn.podcasterium.com
PERSON_API=https://api.podcasterium.com/api/person
PERSONS_API=https://api.podcasterium.com/api/persons
APP_NAME=Podcasterium
APPLE_TEAM_ID=<team id>
IOS_BUNDLE_ID=com.podcasterium
ANDROID_PACKAGE=com.podcasterium
ANDROID_SHA256=<otisak1>,<otisak2>
WEBAUTHN_ORIGINS=https://podcasterium.com,https://www.podcasterium.com
FEATURE_VOTING=false
FEATURE_CAL=false
FEATURE_AIRKUNA=false
```

DOMOVINA.ai projekt **ne postavlja ništa** — defaulti su njegove vrijednosti.
Komentirani popis istih bindinga stoji i u `wrangler.toml`.

## Provjera

- `node --check web/_worker.js` — sintaksa.
- `node scripts/test-social-tags.mjs https://<host>` nakon deploya — OG tagovi
  na živom hostu (mrežni test, ne unit).
- `scripts/deploy.sh` i dalje provjerava da AASA excluda `/auth/*` — taj
  tripwire ne ovisi o brendu.
- Pri promjeni defaulta: promijeniti na **tri** mjesta — `brandFromEnv()` u
  `web/_worker.js`, komentirani blok u `wrangler.toml`, tablica gore.

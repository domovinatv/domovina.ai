/**
 * Cloudflare Pages Advanced Mode Worker — domovina.ai
 *
 * Odgovornosti:
 *  1. SPA routing — sve HTML rute vraćaju index.html (Flutter preuzima routing)
 *  2. Statički asseti — proslijeđuju se direktno iz Pages ASSETS bindinga
 *  3. OG/social tagovi — za /v/<ytId> i /?v=<ytId> fetchamo info.json + summary.json
 *     s CDN-a i injectamo bogate meta tagove PRIJE nego crawler dobije odgovor.
 *     Isti obrazac za /p/<slug> (person hub), /c/<slug> (kanal) i
 *     /c/<slug>/doniraj|/support (Zid podrške), /c/<slug>/oglasi i
 *     /v/<ytId>/sponzoriraj (izlog sponzorskih trenutaka).
 *  4. JSON-LD — VideoObject (/v/), ProfilePage+Person (/p/), PodcastSeries+
 *     ItemList (/c/), DonateAction (/c/…/doniraj) za Google rich-result kartice
 *  5. COEP/COOP headeri — potrebni za Flutter Skwasm (WebAssembly renderer)
 *
 * NAPOMENA: web/_redirects nije prisutan — worker je jedini izvor SPA routinga.
 * Ako se vrati _redirects sa SPA fallbackom, ASSETS.fetch() će za bilo koji
 * nepostojeći .html vratiti index.html sa 200 OK, što ruši detekciju pretty
 * URL-ova (social-test.html, /v/<id>.html, ...) — worker bi krivo vratio
 * index.html bez OG injection.
 */

// --- Brend iz env bindinga ------------------------------------------------
// Jedan worker, više Pages projekata: svaki brend (DOMOVINA.ai, Podcasterium…)
// postavlja svoje bindinge u vlastitom Pages projektu (Settings → Variables).
// Bez ijednog bindinga vrijede današnje DOMOVINA.ai vrijednosti, pa je izlaz
// workera bez env-a bajt-identičan onome prije parametrizacije. Popis
// bindinga s defaultima: wrangler.toml i docs/worker-env-bindings.md.
//
// Zastavice (FEATURE_*) su stringovi 'true'/'false' — Pages env bindinzi su
// uvijek stringovi, pa se uspoređuju kao string, ne kao boolean. Popisi
// (ANDROID_SHA256, WEBAUTHN_ORIGINS) su zarezom odvojeni stringovi.
// PRIVREMENO (26.10.2026.): glasanje je skriveno u aplikaciji
// (`FeatureFlags.voting: false` u domovina_brand.dart), pa worker ne smije
// davati OG kartu glasanja ni slati /glasanje* u native app kroz AASA.
// Nadjačava env FEATURE_VOTING; vraćanje = false, zajedno s flagom u Dartu.
const VOTING_HIDDEN = true;

function brandFromEnv(env) {
  const e = env || {};
  const flag = (name) => (e[name] ?? 'true') === 'true';
  const list = (value, fallback) => (typeof value === 'string' && value.trim()
    ? value.split(',').map((s) => s.trim()).filter(Boolean)
    : fallback);
  return {
    SITE: e.SITE ?? 'https://domovina.ai',
    CDN: e.CDN ?? 'https://cdn.domovina.ai',
    // Person-hub agregat (domovina-rag) — isti no-auth/CORS JSON wrapper kao /api/search.
    // GET .../api/person/<slug> → { name, slug, avatar_url, channel_count, episode_count, ... }.
    // Vidi lib/services/person_service.dart + lib/models/person_hub.dart.
    PERSON_API: e.PERSON_API ?? 'https://mcp.domovina.ai/api/person',
    // Enumerabilan popis osoba za sitemap (virtualni kanali). Isporučuje ga F2 u
    // domovina-rag; dok ga nema, fetchJson vrati null i /p/ unosi jednostavno
    // izostanu iz sitemapa. Vidi docs/plans/virtualni-kanali.md §4.1.
    PERSONS_API: e.PERSONS_API ?? 'https://mcp.domovina.ai/api/persons',
    // Ime brenda: <title> sufiks, og:site_name, JSON-LD publisher/provider i
    // fallback za naslov/kanal epizode.
    APP_NAME: e.APP_NAME ?? 'DOMOVINA.ai',
    // Universal/App Links (.well-known) — vidi komentare uz assetlinksJson i
    // aasaJson ispod.
    APPLE_TEAM_ID: e.APPLE_TEAM_ID ?? '6SCK58757K',
    IOS_BUNDLE_ID: e.IOS_BUNDLE_ID ?? 'ai.domovina',
    ANDROID_PACKAGE: e.ANDROID_PACKAGE ?? 'ai.domovina',
    // SHA-256 otisci potpisnih certifikata (velika slova, ":"-odvojeni), više
    // njih odvojeno zarezom. Redoslijed: Play App Signing key, pa upload key.
    ANDROID_SHA256: list(e.ANDROID_SHA256, [
      '15:C6:2D:19:7B:A1:37:66:3D:07:43:99:B0:DF:C0:66:FA:9B:18:0E:3E:A7:43:34:CD:C4:7A:77:13:16:80:A8',
      'F6:2C:30:D2:83:FB:BF:E4:B4:2C:51:AC:A8:08:AD:94:55:FB:1E:78:94:72:D9:30:73:96:AE:05:67:13:A1:3A',
    ]),
    // WebAuthn Related Origins (/.well-known/webauthn) — vidi webauthnJson.
    WEBAUTHN_ORIGINS: list(e.WEBAUTHN_ORIGINS, [
      'https://domovina.ai',
      'https://www.domovina.ai',
      'https://wallet.domovina.ai',
      'https://pay.domovina.ai',
      'https://mpt.domovina.ai',
      'https://pinka.finance',
      'https://www.pinka.finance',
      'https://app.pinka.finance',
      'https://pinka-app.pages.dev',
      'https://pinka.io',
      'https://www.pinka.io',
      'https://domovina.energy',
      'https://www.domovina.energy',
      'https://domovina.tv',
      'https://www.domovina.tv',
    ]),
    // Brend-specifični blokovi; 'false' ih isključuje.
    FEATURE_VOTING: flag('FEATURE_VOTING') && !VOTING_HIDDEN, // „Izborni dan" /glasanje* (OG + AASA)
    FEATURE_CAL: flag('FEATURE_CAL'),         // Cal.com proxy /api/cal/*
    FEATURE_AIRKUNA: flag('FEATURE_AIRKUNA'), // airKUNA wallet u assetlinks + AASA
  };
}

// Aktivni brend. fetch() ga na početku SVAKOG zahtjeva postavi iz env-a. Env
// je isti za sve zahtjeve jednog deploya (Pages bindinzi), pa je ponovna
// dodjela modulnim varijablama idempotentna — i jeftinija od provlačenja
// brenda kroz svaki inject*/sitemap helper ispod. Modulni default (bez env-a)
// pokriva samo pozive helpera mimo fetch() (Node harness).
let BRAND = brandFromEnv();
let { SITE, CDN, PERSON_API, PERSONS_API, APP_NAME } = BRAND;
// Kvadratni avatar osobe na CDN-u (900×900 PNG); produkcija slike je posao
// fetch.domovina.tv — worker ga samo koristi ako postoji (HEAD provjera).
const personAvatarUrl = (slug) => `${CDN}/persons/images/${slug}/avatar_square.png`;

// --- Cal.com booking ("15 min DOMOVINA.ai", stepanic/15min) ---------------
// eventTypeId je stabilan (dohvaćen iz /v2/event-types). Ključ dolazi SAMO iz
// env.CAL_API_KEY (Pages secret) — nikad hardkodiran jer je _worker.js u gitu.
const CAL_API = 'https://api.cal.com/v2';
const CAL_EVENT_TYPE_ID = 1787504;
const CAL_TIMEZONE = 'Europe/Zagreb';
// Permisivni CORS — native app + lokalni web dev (localhost) zovu cross-origin.
// U produkciji je web same-origin pa CORS ne smeta.
const CAL_CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Max-Age': '86400',
};

async function handleCalProxy(request, env, path) {
  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: CAL_CORS });
  }
  const key = env.CAL_API_KEY;
  const jsonHeaders = {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    ...CAL_CORS,
  };
  const err = (message, status) =>
    new Response(JSON.stringify({ status: 'error', message }), { status, headers: jsonHeaders });

  try {
    if (path === '/api/cal/slots' && request.method === 'GET') {
      const u = new URL(request.url);
      const start = u.searchParams.get('start');
      const end = u.searchParams.get('end');
      const tz = u.searchParams.get('timeZone') || CAL_TIMEZONE;
      if (!start || !end) return err('start i end su obavezni', 400);
      const api = `${CAL_API}/slots?eventTypeId=${CAL_EVENT_TYPE_ID}`
        + `&start=${encodeURIComponent(start)}&end=${encodeURIComponent(end)}`
        + `&timeZone=${encodeURIComponent(tz)}`;
      const headers = { 'cal-api-version': '2024-09-04' };
      if (key) headers['Authorization'] = `Bearer ${key}`;
      const res = await fetch(api, { headers });
      return new Response(await res.text(), { status: res.status, headers: jsonHeaders });
    }

    if (path === '/api/cal/book' && request.method === 'POST') {
      if (!key) return err('CAL_API_KEY nije konfiguriran na serveru', 500);
      const input = await request.json();
      if (!input.start || !input.name || !input.email) {
        return err('start, name i email su obavezni', 400);
      }
      const payload = {
        start: input.start,
        eventTypeId: CAL_EVENT_TYPE_ID,
        attendee: {
          name: input.name,
          email: input.email,
          timeZone: input.timeZone || CAL_TIMEZONE,
          language: input.language || 'hr',
        },
      };
      if (input.notes) payload.bookingFieldsResponses = { notes: input.notes };
      const res = await fetch(`${CAL_API}/bookings`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${key}`,
          'cal-api-version': '2024-08-13',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload),
      });
      return new Response(await res.text(), { status: res.status, headers: jsonHeaders });
    }

    return err('nepoznata Cal.com ruta', 404);
  } catch (e) {
    return err(String(e), 500);
  }
}

// .well-known — serviramo iz workera (NE iz ASSETS) jer:
//   1. apple-app-site-association nema ekstenziju → fall-through na SPA fallback
//   2. flutter build web zna preskočiti `.`-prefiksirane direktorije (web/.well-known/
//      ne dospije pouzdano u build/web)
// Oba služe i App Links verifikaciji (Android autoVerify, iOS applinks) i
// passkey/WebAuthn (Android Credential Manager preko assetlinks; iOS webcredentials).
//
// Fingerprints (SHA-256, velika slova, ":"-odvojeni):
//   1. Play App Signing key — potpisuje APK-ove koje Play isporučuje uređajima
//      (izvor: androidpublisher generatedApks API, certificateSha256Hash).
//   2. Upload key (android/upload-keystore.jks) — lokalno buildani release
//      APK-ovi (adb install na EON/test uređaje).
// Apple Team ID (6SCK58757K) je već upisan.
//
// Vrijednosti dolaze iz brenda (ANDROID_PACKAGE, ANDROID_SHA256); airKUNA
// unos postoji samo uz FEATURE_AIRKUNA.
const assetlinksJson = (b) => JSON.stringify([
  {
    relation: [
      'delegate_permission/common.handle_all_urls',
      'delegate_permission/common.get_login_creds',
    ],
    target: {
      namespace: 'android_app',
      package_name: b.ANDROID_PACKAGE,
      sha256_cert_fingerprints: b.ANDROID_SHA256,
    },
  },
  ...(b.FEATURE_AIRKUNA ? [{
    // airKUNA wallet — App Links za /c/* donacijske rute (path scope je u
    // appu, assetlinks verificira samo app↔domena vezu). Otisak = EAS-managed
    // keystore @airkuna/airkuna (Build Credentials 5E0UbnSkow, 2026-07-22).
    relation: ['delegate_permission/common.handle_all_urls'],
    target: {
      namespace: 'android_app',
      package_name: 'com.airkuna.wallet',
      sha256_cert_fingerprints: [
        '4F:E5:92:94:62:BE:29:59:57:44:B1:56:56:73:85:13:FA:D2:80:B6:A8:AB:A4:CA:F0:69:49:63:66:33:C9:C7',
      ],
    },
  }] : []),
], null, 2);

// Auth callback rute su ISKLJUČENE iz universal linkova: OAuth/magic-link
// povratak (GoTrue → https://domovina.ai/auth/callback#…) je cross-origin
// redirect pa bi ga iOS inače oteo i otvorio native app umjesto da web
// prijava završi u Safariju. Native app ima vlastiti flow (ai.domovina://).
// NB: Apple CDN + uređaji cachiraju AASA — promjena se propagira tek nakon
// reinstalacije appa ili refresha (do ~tjedan dana).
//
// appID = APPLE_TEAM_ID.IOS_BUNDLE_ID iz brenda; /glasanje* unosi samo uz
// FEATURE_VOTING, airKUNA unos samo uz FEATURE_AIRKUNA.
const aasaJson = (b) => JSON.stringify({
  applinks: {
    apps: [],
    details: [
      {
        appID: `${b.APPLE_TEAM_ID}.${b.IOS_BUNDLE_ID}`,
        components: [
          { '/': '/auth/*', exclude: true, comment: 'web OAuth/magic-link callback ostaje u browseru' },
          { '/': '/login-callback', exclude: true, comment: 'isti AuthCallbackScreen (legacy ruta)' },
          { '/': '/youtube-claim/*', exclude: true, comment: 'Google OAuth callback za channel claim — web-only' },
          // Javne content rute se navode EKSPLICITNO iako ih `*` ispod ionako
          // hvata: popis je ugovor s AndroidManifest intent filterom (koji
          // nema exclude sintaksu pa mora biti allowlist). CLAUDE.md: nova
          // javna ruta ide u OBA popisa. Stoji NAKON exclusiona — auth rute
          // ostaju isključene jer components matcha prvo pravilo.
          ...(b.FEATURE_VOTING ? [
            { '/': '/glasanje', comment: 'Izborni dan — javna ljestvica glasanja' },
            { '/': '/glasanje/*', comment: 'deep-link/share na kandidata' },
          ] : []),
          { '/': '*' },
        ],
        // Legacy fallback za iOS < 13 (noviji iOS čita components).
        paths: ['NOT /auth/*', 'NOT /login-callback', 'NOT /youtube-claim/*', '*'],
      },
      ...(b.FEATURE_AIRKUNA ? [{
        // airKUNA wallet — hvata SAMO donacijske linkove (/c/<slug>/...).
        // Naveden nakon ai.domovina: kad su oba appa instalirana, glavni app
        // ima prednost; airkuna-only korisnici dobivaju Doniraj flow.
        // Android assetlinks za com.airkuna.wallet čeka signing cert prvog
        // EAS builda (airkuna A4).
        appID: `${b.APPLE_TEAM_ID}.com.airkuna.wallet`,
        components: [{ '/': '/c/*', comment: `${new URL(b.SITE).host} kampanje → airKUNA Doniraj` }],
        paths: ['/c/*'],
      }] : []),
    ],
  },
  webcredentials: {
    apps: [`${b.APPLE_TEAM_ID}.${b.IOS_BUNDLE_ID}`],
  },
}, null, 2);

// WebAuthn Related Origin Requests (WebAuthn L3). Lets passkeys created under
// RP ID `domovina.ai` be used natively from OTHER registrable domains in the
// ecosystem (pinka.finance, domovina.energy, …) — not just *.domovina.ai
// subdomains. Each listed origin may request assertions with RP ID domovina.ai.
// Served at https://domovina.ai/.well-known/webauthn.
// See pay.domovina.ai/docs/plans/cross-domain-wallet-passkey.md (Phase D).
// Origins list comes from the brand (WEBAUTHN_ORIGINS).
const webauthnJson = (b) => JSON.stringify({
  origins: b.WEBAUTHN_ORIGINS,
}, null, 2);

function wellKnownResponse(body) {
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'public, max-age=3600',
    },
  });
}

/**
 * `web/cast-receiver.html` — Google Cast Web Receiver (CAF), plan
 * docs/plans/2026-10-17-cast-na-tv.md, iteracija C.
 *
 * Namjerno BEZ COOP/COEP (za razliku od htmlResponse): Flutter ih treba zbog
 * skwasm dretvi, a receiver nije Flutter. CAF skripta s gstatica šalje CORP
 * cross-origin pa bi radila i pod COEP-om, ali slike koje pošiljatelj navede
 * (logo sponzora, poster) ne šalju ni CORP ni CORS — pod COEP-om bi ih
 * preglednik u televizoru odbio.
 *
 * Asset se traži po pretty URL-u (`/cast-receiver`), pa po `.html`; preusmjerenje
 * se ne slijedi — televizoru vraćamo 200 ili pravu grešku, nikad 308.
 */
async function handleCastReceiver(request, env, url) {
  let res = null;
  for (const p of ['/cast-receiver', '/cast-receiver.html']) {
    res = await env.ASSETS.fetch(
      new Request(`${url.origin}${p}`, { headers: request.headers, redirect: 'manual' }),
    );
    if (res.ok || res.status === 304) break;
  }
  if (!res.ok && res.status !== 304) return res;
  const headers = new Headers({
    'Content-Type': 'text/html;charset=UTF-8',
    // Deploy mijenja receiver na istom URL-u — uvijek revalidiraj (ETag → 304).
    'Cache-Control': 'public, max-age=0, must-revalidate',
  });
  const etag = res.headers.get('ETag');
  if (etag) headers.set('ETag', etag);
  return new Response(res.status === 304 ? null : res.body, { status: res.status, headers });
}

export default {
  async fetch(request, env) {
    // Brend za ovaj zahtjev — iz Pages env bindinga, defaulti = DOMOVINA.ai.
    BRAND = brandFromEnv(env);
    ({ SITE, CDN, PERSON_API, PERSONS_API, APP_NAME } = BRAND);

    const url = new URL(request.url);
    const path = url.pathname;

    // .well-known (App Links + passkey/WebAuthn) — prije svega ostalog.
    if (path === '/.well-known/assetlinks.json') return wellKnownResponse(assetlinksJson(BRAND));
    if (path === '/.well-known/apple-app-site-association') return wellKnownResponse(aasaJson(BRAND));
    if (path === '/.well-known/webauthn') return wellKnownResponse(webauthnJson(BRAND));

    // Sitemap — MORA biti prije ASSETS grane ispod: `/sitemap.xml` ima
    // ekstenziju pa bi ga `/\.\w{1,8}$/` poslao u env.ASSETS.fetch() i dobio
    // 404 (fajl ne postoji u web/). Jedna ruta, jedan urlset.
    if (path === '/sitemap.xml') return handleSitemap();

    // Cal.com booking proxy — drži CAL_API_KEY server-side (env secret), NIKAD
    // u web bundleu. Slotovi su javni (reflektiraju Google Calendar kolizije),
    // booking POST traži ključ. Flutter app zove same-origin /api/cal/*.
    // Bez FEATURE_CAL ruta pada dalje kao svaka nepoznata (SPA fallback).
    if (BRAND.FEATURE_CAL && (path === '/api/cal/slots' || path === '/api/cal/book')) {
      return handleCalProxy(request, env, path);
    }

    // Google Cast receiver — MORA biti prije ASSETS grane: `.html` bi inače
    // otišao u env.ASSETS.fetch(), a Pages pretty-URL pravilo ga 308-ica na
    // `/cast-receiver`. URL registriran u Cast konzoli treba odgovoriti 200.
    if (path === '/cast-receiver.html' || path === '/cast-receiver') {
      return handleCastReceiver(request, env, url);
    }

    // Statički asseti (JS, CSS, slike, fontovi...) — direktno iz ASSETS.
    // KRITIČNO: env.ASSETS.fetch ne aplicira web/_headers automatski kad
    // worker rukuje requestom (CF Pages Advanced Mode contract). Bootstrap
    // fajlovi (main.dart.js, flutter*.js, manifest.json) bi inače dobili
    // default Cache-Control od ~14400s pa bi iOS Safari servirao stari
    // main.dart.js (~3.3MB) tjednima nakon deploya. Patchamo ih ovdje na
    // no-cache + must-revalidate (ETag negotiation = 304 na unchanged).
    // Hashed bundle assets (canvaskit, assets/*) ostaju s default
    // CF cachiranjem koje je sigurno jer im se URL mijenja na rebuild.
    if (/\.\w{1,8}$/.test(path)) {
      const res = await env.ASSETS.fetch(request);
      // Bootstrap entry-pointi koji se mijenjaju na svaki rebuild ali zadržavaju
      // isti URL — moraju revalidate-ati. Skwasm build dodaje main.dart.wasm i
      // *.mjs runtime loadere uz dart2js fallback.
      if (/^\/(main\.dart\.(?:js|wasm|mjs)|flutter\.js|flutter_bootstrap\.js|skwasm(?:_heavy)?\.(?:js|wasm|worker\.js)|manifest\.json|favicon\.png)$/.test(path)) {
        const headers = new Headers(res.headers);
        headers.set('Cache-Control', 'public, max-age=0, must-revalidate');
        // CDN edge sloj: i CF mora poštovati no-store da ne servira iz vlastitog cache-a
        headers.set('CDN-Cache-Control', 'no-store');
        return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
      }
      return res;
    }

    // Trailing-slash kanonikalizacija — 301 na verziju bez "/".
    // Bez ovoga route matcheri ispod (/v/<id>, /v/<id>/t/<n>, /m/<id>) i
    // pretty-URL .html lookup propuste request s "/" sufiksom pa fall-through
    // na SPA fallback servira generic OG tagove. New URL preservira search +
    // hash, pa query params (?utm_source=..., ?ref=..., interni app params)
    // ostaju netaknuti kroz redirect.
    if (path !== '/' && path.endsWith('/')) {
      const canonicalUrl = new URL(request.url);
      canonicalUrl.pathname = path.replace(/\/+$/, '');
      return Response.redirect(canonicalUrl.toString(), 301);
    }

    // Izvuci YouTube ID iz URL-a:
    //   /v/<ytId>               — permalink format (detailed view)
    //   /v/<ytId>/t/<sec>       — timestamp clip share (path-based za pouzdan crawler cache)
    //   /m/<ytId>               — mobile simplified view (isti OG, canonical → /v/<id>)
    //   /?v=<ytId>              — query param format
    //   …/en                    — engleska varijanta SVIH gornjih (osim /?v=)
    //
    // `/en` sufiks (a ne ?lang=en) postoji upravo zato što crawleri droppaju
    // query parametre — vidi komentar uz rutu u lib/router/app_router.dart.
    // Do 15.9.2026. ga je Flutter router imao, a ovaj worker NIJE: svaki
    // engleski share (/v/<id>/t/<sec>/en) padao je kroz sve matchere na SPA
    // fallback i dobivao generički OG naslovnice, na hrvatskom.
    let ytId = null;
    let tSec = null;
    let viewMode = 'v'; // 'v' = detailed, 'm' = simple
    let lang = 'hr';    // 'hr' = original, 'en' = prijevod iz *.en.json
    const tMatch = path.match(/^\/v\/([A-Za-z0-9_-]{6,20})\/t\/(\d+)(\/en)?$/);
    const vMatch = !tMatch && path.match(/^\/v\/([A-Za-z0-9_-]{6,20})(\/en)?$/);
    const mtMatch = !tMatch && !vMatch && path.match(/^\/m\/([A-Za-z0-9_-]{6,20})\/t\/(\d+)(\/en)?$/);
    const mMatch = !tMatch && !vMatch && !mtMatch && path.match(/^\/m\/([A-Za-z0-9_-]{6,20})(\/en)?$/);
    if (tMatch) {
      ytId = tMatch[1];
      tSec = parseInt(tMatch[2], 10);
      if (tMatch[3]) lang = 'en';
    } else if (vMatch) {
      ytId = vMatch[1];
      if (vMatch[2]) lang = 'en';
    } else if (mtMatch) {
      ytId = mtMatch[1];
      tSec = parseInt(mtMatch[2], 10);
      viewMode = 'm';
      if (mtMatch[3]) lang = 'en';
    } else if (mMatch) {
      ytId = mMatch[1];
      viewMode = 'm';
      if (mMatch[2]) lang = 'en';
    } else if (path === '/' || path === '') {
      ytId = url.searchParams.get('v');
    }

    // Dohvati index.html iz statičkih asseta (paralelno s metadatom)
    const indexPromise = env.ASSETS.fetch(
      new Request(`${url.origin}/index.html`, { headers: request.headers }),
    );

    if (ytId) {
      // Fetch info + summary + article + og-sections manifest + og-share check
      // paralelno. article.json i og-sections.json su opcionalni (stariji videi
      // ih možda nemaju) — fetchJson vraća null na 404 pa fallback radi sam.
      // og-sections.json je Tier B manifest: { sections: { "<sec>": "og-t-<sec>.jpg" } }
      // — file po section-u, 1200×630 JPEG ~100KB (WhatsApp-safe < 600KB).
      // EN varijante su ZASEBNI fajlovi (summary.en.json / article.en.json), a u
      // njima su i HR i *_en polja — pa je fallback na HR unutar istog dokumenta.
      // Fajl ne postoji za neprevedene epizode → fetchJson vraća null i padamo
      // na hrvatski original.
      const summaryPath = lang === 'en' ? 'summary.en.json' : 'summary.json';
      const articlePath = lang === 'en' ? 'article.en.json' : 'article.json';
      const [info, summaryLocalized, summaryHr, articleLocalized, articleHr, ogSections, hasOgShare] = await Promise.all([
        fetchJson(`${CDN}/data/${ytId}/info.json`),
        fetchJson(`${CDN}/data/${ytId}/${summaryPath}`),
        lang === 'en' ? fetchJson(`${CDN}/data/${ytId}/summary.json`) : Promise.resolve(null),
        // article + og-sections fetchamo SAMO za timestamp shareove — base
        // /v/<id> koristi episode-level og-share.jpg.
        (typeof tSec === 'number') ? fetchJson(`${CDN}/data/${ytId}/${articlePath}`) : Promise.resolve(null),
        (typeof tSec === 'number' && lang === 'en') ? fetchJson(`${CDN}/data/${ytId}/article.json`) : Promise.resolve(null),
        (typeof tSec === 'number') ? fetchJson(`${CDN}/images/${ytId}/og-sections.json`) : Promise.resolve(null),
        headOk(`${CDN}/images/${ytId}/og-share.jpg`),
      ]);
      const summary = summaryLocalized || summaryHr;
      const article = articleLocalized || articleHr;

      // Section-specific og:image override. Manifest mape:
      //   sections    → { "<startSec>": "og-t-<sec>.jpg" }
      //   sections_en → { "<startSec>": "og-t-<sec>-en.jpg" }  (manifest v1.1+)
      // findArticleSection vraća section s _start poljem koji odgovara ključu u manifestu.
      // EN bez svoje slike pada na HR sliku — pogrešan jezik u slici je i dalje
      // bolji od generičkog og-share.jpg bez tog trenutka.
      let sectionImageUrl = null;
      if (info && article && ogSections && typeof tSec === 'number') {
        const sec = findArticleSection(article, tSec, info.duration);
        if (sec && typeof sec._start === 'number') {
          const key = String(sec._start);
          const filename = (lang === 'en' ? ogSections.sections_en?.[key] : null)
            || ogSections.sections?.[key];
          if (filename) {
            sectionImageUrl = `${CDN}/images/${ytId}/${filename}`;
          }
        }
      }

      if (info) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(injectEpisodeTags(indexHtml, ytId, info, summary, article, hasOgShare, tSec, viewMode, sectionImageUrl, lang), 'public, max-age=3600, s-maxage=3600');
      }
      // info ne postoji — Flutter će prikazati grešku, servamo plain index
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // Karta sponzorskih trenutaka epizode — /v/<id>/sponzoriraj. Zasebna
    // grana jer bi OG epizode obećavao gledanje, a stranica je ponuda brandu.
    // Bez cijena u OG-u: odgovor se edge-cachira 1 h, a cijene i stanje
    // trenutaka žive u bazi. Ruta mora ostati usklađena s app_router.dart.
    const sponsorVMatch = path.match(/^\/v\/([A-Za-z0-9_-]{6,20})\/sponzoriraj$/);
    if (sponsorVMatch) {
      const id = sponsorVMatch[1];
      const [info, summary] = await Promise.all([
        fetchJson(`${CDN}/data/${id}/info.json`),
        fetchJson(`${CDN}/data/${id}/summary.json`),
      ]);
      if (info) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(
          injectSponsorEpisodeTags(indexHtml, id, info, summary),
          'public, max-age=3600, s-maxage=3600',
        );
      }
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // Person-hub profil — /p/<slug>. Slug se koristi DOSLOVNO (bez `-`↔`_`
    // transformacije koju rade kanali) jer je primarni ključ u bazi. Fetchamo
    // agregat s domovina-rag i injectamo osobno-specifične OG tagove PRIJE nego
    // crawler (WhatsApp/Facebook/…) dobije odgovor — inače dijeli generički
    // domovina.ai preview.
    const pMatch = path.match(/^\/p\/([a-z0-9-]{2,80})$/);
    if (pMatch) {
      const slug = pMatch[1];
      // Avatar provjeravamo paralelno s profilom — HEAD je jeftin i edge-cachiran
      // (cacheTtl 3600), a inače bi og:image za osobe bez `avatar_url` uvijek
      // padao na generički brend banner.
      const [person, hasCdnAvatar] = await Promise.all([
        fetchJson(`${PERSON_API}/${encodeURIComponent(slug)}`),
        headOk(personAvatarUrl(slug)),
      ]);
      if (person && person.name) {
        const indexHtml = await (await indexPromise).text();
        return htmlResponse(injectPersonTags(indexHtml, slug, person, hasCdnAvatar), 'public, max-age=3600, s-maxage=3600');
      }
      // Slug ne postoji (404) ili API nedostupan — Flutter pokaže prazno stanje.
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // Kanal — /c/<slug> i Zid podrške /c/<slug>/doniraj | /c/<slug>/support.
    // Slug koristi crtice, CDN channel id podvlake — isti mapping kao
    // lib/router/app_router.dart (slug.replaceAll('-', '_')). /c/<slug>/oglasi
    // je izlog sponzorskih trenutaka. Ostale /c/ podrute (npr.
    // /c/<slug>/claim) namjerno padaju na SPA fallback.
    const cSupportMatch = path.match(/^\/c\/([a-z0-9-]{2,80})\/(doniraj|support)$/);
    // Izlog sponzorskih trenutaka — /c/<slug>/oglasi.
    const cAdsMatch = !cSupportMatch && path.match(/^\/c\/([a-z0-9-]{2,80})\/oglasi$/);
    const cMatch = !cSupportMatch && !cAdsMatch && path.match(/^\/c\/([a-z0-9-]{2,80})$/);
    if (cSupportMatch || cAdsMatch || cMatch) {
      const slug = (cSupportMatch || cAdsMatch || cMatch)[1];
      const channelId = slug.replace(/-/g, '_');
      const channel = await fetchJson(
        `${CDN}/channels/data/${channelId}.json?${channelCacheBuster()}`,
      );
      if (channel && channel.name) {
        const indexHtml = await (await indexPromise).text();
        if (cAdsMatch) {
          return htmlResponse(
            injectSponsorStoreTags(indexHtml, slug, channel),
            'public, max-age=3600, s-maxage=3600',
          );
        }
        if (cSupportMatch) {
          // Kampanja preko ISTOG RPC-a koji app zove (PinkaClient
          // .campaignForSubject): refs = [UC… id, interni channel id].
          const campaign = await fetchCampaign(
            env,
            [extractUcId(channel), channelId].filter(Boolean),
          );
          return htmlResponse(
            injectSupportTags(indexHtml, slug, cSupportMatch[2], channel, campaign),
            'public, max-age=3600, s-maxage=3600',
          );
        }
        return htmlResponse(
          injectChannelTags(indexHtml, slug, channel),
          'public, max-age=3600, s-maxage=3600',
        );
      }
      // Kanal ne postoji na CDN-u ili je listing nedostupan — plain SPA.
      return htmlResponse(await (await indexPromise).text(), 'no-store');
    }

    // „Izborni dan" — /glasanje (statični OG) i /glasanje/<slug> (kandidat).
    // Ruta je javna i dijeljiva (plan §8.1), pa crawler mora dobiti smislen
    // preview i kad kandidat nije razrješiv (baza nedostupna, nepoznat slug,
    // buduća /glasanje/kola arhiva) — tada se servira opći OG glasanja.
    // Bez FEATURE_VOTING ruta pada dalje na SPA fallback (generički OG).
    const gSlugMatch = path.match(/^\/glasanje\/([a-z0-9][a-z0-9-]{0,79})$/);
    if (BRAND.FEATURE_VOTING && (path === '/glasanje' || gSlugMatch)) {
      const slug = gSlugMatch ? gSlugMatch[1] : null;
      const candidate = slug ? await fetchVoteCandidate(env, slug) : null;
      const indexHtml = await (await indexPromise).text();
      return htmlResponse(
        injectVotingTags(indexHtml, slug, candidate),
        'public, max-age=3600, s-maxage=3600',
      );
    }

    // Cloudflare Pages "pretty URLs" — provjeri postoji li <path>.html.
    // Bez _redirects ovaj lookup je pouzdan (404 ako fajl ne postoji).
    if (path !== '/' && !path.endsWith('/')) {
      const htmlReq = new Request(`${url.origin}${path}.html`, { headers: request.headers });
      const htmlRes = await env.ASSETS.fetch(htmlReq);
      if (htmlRes.ok) return htmlRes;
    }

    // Bez video ID-a i bez .html match-a — SPA fallback (Flutter router)
    return htmlResponse(await (await indexPromise).text(), 'no-store');
  },
};

// Origin the pipeline writes into absolute URLs inside the CDN data. A brand
// with its own CDN name on the same bucket (cdn.podcasterium.com) rewrites
// them, so its pages never load from this host. Mirrors CdnConfig.rebase.
const DATA_CDN_ORIGIN = 'https://cdn.domovina.ai';

async function fetchJson(url) {
  try {
    const res = await fetch(url, { cf: { cacheTtl: 300, cacheEverything: true } });
    if (!res.ok) return null;
    if (CDN === DATA_CDN_ORIGIN) return await res.json();
    const text = await res.text();
    return JSON.parse(text.split(`${DATA_CDN_ORIGIN}/`).join(`${CDN}/`));
  } catch (_) {}
  return null;
}

async function headOk(url) {
  try {
    const res = await fetch(url, { method: 'HEAD', cf: { cacheTtl: 3600, cacheEverything: true } });
    return res.ok;
  } catch (_) {
    return false;
  }
}

// --- Sitemap ---------------------------------------------------------------
//
// JEDAN urlset na `/sitemap.xml`: `/`, `/channels`, sve `/c/<slug>`, sve
// `/p/<slug>` iz `/api/persons` i sve `/v/<id>` epizode (danas 3153). Dinamički
// jer bi statički fajl zastario između deployeva — novi videi stižu na CDN bez
// rebuilda appa.
//
// Zamka koju build mora zaobići: popis epizoda postoji SAMO u per-kanal
// JSON-ovima (`channels/data/<id>.json`, ~160 KB × 48 ≈ 7 MB). Naivan build bi
// po SVAKOM zahtjevu tražio 50 subrequestova i parsanje 7 MB — račun je na
// Workers Paid (1000 subrequestova, 30 s CPU) pa to nije zid, ali je nepotrebna
// cijena na svaki dohvat sitemapa. Zato build ide kroz Cache API u dva sloja
// (`caches.default` NE troši subrequest budžet):
//
//   1. gotov XML — `__cache/sitemap.xml`, 1 h → pogodak = 0 subrequestova i
//      0 parsanja; tom putanjom ide praktički svaki zahtjev
//   2. per-kanal fragment `<url>` blokova — `__cache/sitemap-frag/<id>/<datum>`,
//      7 dana; ključ nosi datum zadnjeg videa pa kanal koji je dobio novi video
//      prirodno promaši i jedini se ponovno dohvaća. Satni rebuild zato košta
//      2 + (broj promijenjenih kanala) subrequestova, tipično 2–5.
//
// Jedna invokacija dohvaća najviše SITEMAP_MAX_CHANNEL_FETCH kanala — gornja
// granica posla po zahtjevu, s puno rezerve do limita. Ako nakon
// toga fragmenti nisu svi topli (prazan cache: prvi zahtjev nakon deploya, jer
// `purge_everything` u deploy skripti briše i Cache API), servira se zadnji
// POTPUN build (`__cache/sitemap-last.xml`, 24 h); ako ni njega nema, servira se
// djelomičan XML s eksplicitnim XML komentarom i taj se NE sprema kao potpun.
// Sljedeći zahtjev nastavlja gdje je stao — nema tihog capa.
const sitemapCacheUrl = () => `${SITE}/__cache/sitemap.xml`;
const sitemapLastCacheUrl = () => `${SITE}/__cache/sitemap-last.xml`;
const sitemapFragmentUrl = (channelId, stamp) =>
  `${SITE}/__cache/sitemap-frag/${channelId}/${stamp}`;
// Koliko kanala smije dohvatiti JEDNA invokacija: 40 → 42 subrequesta (od 1000
// na Workers Paid) i ~6,5 MB parsanja u najgorem slučaju (30 s CPU budžeta).
// Prazan cache se time zagrije u 2 zahtjeva umjesto 6. Ako broj kanala naraste
// preko ~100, spusti ovu brojku umjesto da dižeš cijenu jedne invokacije.
const SITEMAP_MAX_CHANNEL_FETCH = 40;
const SITEMAP_TTL = 3600;
const SITEMAP_LAST_TTL = 86400;
const SITEMAP_FRAGMENT_TTL = 604800;

/** `caches.default` ako runtime ima Cache API (nema ga u Node unit harnessu). */
function edgeCache() {
  try {
    return (typeof caches !== 'undefined' && caches.default) ? caches.default : null;
  } catch (_) {
    return null;
  }
}

async function cacheGetText(cache, key) {
  if (!cache) return null;
  try {
    const hit = await cache.match(new Request(key));
    return hit ? await hit.text() : null;
  } catch (_) {
    return null;
  }
}

async function cachePutText(cache, key, text, maxAge) {
  if (!cache) return;
  try {
    await cache.put(new Request(key), new Response(text, {
      headers: {
        'Content-Type': 'application/xml; charset=UTF-8',
        'Cache-Control': `public, max-age=${maxAge}`,
      },
    }));
  } catch (_) {}
}

/** GET /sitemap.xml — cache-first, build tek na promašaj. */
async function handleSitemap() {
  const cache = edgeCache();
  const cached = await cacheGetText(cache, sitemapCacheUrl());
  if (cached) return xmlResponse(cached);
  return buildSitemap(cache);
}

/** Channel id (`slijedi_svoj_poziv_2`) → /c/ slug (`slijedi-svoj-poziv-2`). */
function channelSlug(id) {
  return String(id || '').replace(/_/g, '-');
}

/** W3C datum (YYYY-MM-DD) za <lastmod>; null ako oblik nije prepoznat. */
function lastmodDate(value) {
  if (typeof value !== 'string') return null;
  const m = value.match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : null;
}

async function buildSitemap(cache) {
  const [index, personIndex] = await Promise.all([
    fetchJson(`${CDN}/channels/data/index.json?${channelCacheBuster()}`),
    fetchJson(PERSONS_API),
  ]);

  const generated = lastmodDate(index?.generated_at);
  // Filtriramo na oblik id-a koji /c/ ruta uopće može poslužiti.
  const channels = (Array.isArray(index?.channels) ? index.channels : [])
    .filter((ch) => /^[a-z0-9_]{2,80}$/.test(String(ch?.id ?? '')));
  const persons = Array.isArray(personIndex?.persons)
    ? personIndex.persons
    : (Array.isArray(personIndex) ? personIndex : []);

  const urls = [
    { loc: `${SITE}/`, lastmod: generated, changefreq: 'daily', priority: '1.0' },
    { loc: `${SITE}/channels`, lastmod: generated, changefreq: 'daily', priority: '0.8' },
  ];

  for (const ch of channels) {
    urls.push({
      loc: `${SITE}/c/${channelSlug(ch.id)}`,
      lastmod: lastmodDate(ch?.latest_video?.date) || generated,
      changefreq: 'weekly',
      priority: '0.7',
    });
  }

  for (const p of persons) {
    const slug = typeof p?.slug === 'string' ? p.slug : '';
    // Isti oblik sluga koji hvata /p/ ruta; opt-out osoba (tombstone u
    // domovina-rag) ne smije u sitemap — profil ostaje živ, ali neindeksiran.
    if (!/^[a-z0-9-]{2,80}$/.test(slug)) continue;
    if (p?.optout === true) continue;
    urls.push({
      loc: `${SITE}/p/${slug}`,
      lastmod: lastmodDate(p?.latest_episode?.date),
      changefreq: 'weekly',
      priority: '0.6',
    });
  }

  // Epizode: prvo sve iz fragment cachea (bez ijednog subrequesta), pa dohvat
  // najviše SITEMAP_MAX_CHANNEL_FETCH kanala koji fale.
  const stamps = channels.map(
    (ch) => lastmodDate(ch?.latest_video?.date) || generated || 'none',
  );
  const fragments = await Promise.all(
    channels.map((ch, i) => cacheGetText(cache, sitemapFragmentUrl(ch.id, stamps[i]))),
  );
  const pending = [];
  fragments.forEach((f, i) => { if (f === null) pending.push(i); });
  await Promise.all(pending.slice(0, SITEMAP_MAX_CHANNEL_FETCH).map(async (i) => {
    const frag = await channelEpisodeFragment(channels[i].id);
    if (frag === null) return; // CDN promašaj → ostaje rupa, build nije potpun
    fragments[i] = frag;
    await cachePutText(
      cache, sitemapFragmentUrl(channels[i].id, stamps[i]), frag, SITEMAP_FRAGMENT_TTL,
    );
  }));

  const holes = fragments.filter((f) => f === null).length;
  const body = [urls.map(urlXml).join('\n'), ...fragments.filter(Boolean)].join('\n');
  const xml = '<?xml version="1.0" encoding="UTF-8"?>\n'
    + '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
    + (holes > 0
      ? `  <!-- djelomican build: ${holes} kanal(a) jos nije u cacheu; `
        + 'sljedeci zahtjev nastavlja -->\n'
      : '')
    + `${body}\n</urlset>\n`;

  if (holes > 0) {
    // Radije zadnji POTPUN build (stariji, ali cjelovit) nego djelomičan.
    const last = await cacheGetText(cache, sitemapLastCacheUrl());
    return xmlResponse(last || xml);
  }

  await cachePutText(cache, sitemapCacheUrl(), xml, SITEMAP_TTL);
  await cachePutText(cache, sitemapLastCacheUrl(), xml, SITEMAP_LAST_TTL);
  return xmlResponse(xml);
}

/**
 * `<url>` blokovi svih epizoda jednog kanala; null kad listing nije dostupan
 * (razlikuje se od "kanal bez videa", koji vrati prazan string).
 */
async function channelEpisodeFragment(channelId) {
  const channel = await fetchJson(
    `${CDN}/channels/data/${channelId}.json?${channelCacheBuster()}`,
  );
  if (!channel || !Array.isArray(channel.videos)) return null;

  const seen = new Set();
  const urls = [];
  for (const v of channel.videos) {
    const id = typeof v?.id === 'string' ? v.id : '';
    // Isti oblik ID-a koji hvata /v/ ruta gore.
    if (!/^[A-Za-z0-9_-]{6,20}$/.test(id) || seen.has(id)) continue;
    seen.add(id);
    urls.push({
      loc: `${SITE}/v/${id}`,
      lastmod: lastmodDate(v?.date),
      changefreq: 'monthly',
      priority: '0.5',
    });
  }
  return urls.map(urlXml).join('\n');
}

function urlXml(u) {
  return `  <url>\n    <loc>${xmlEscape(u.loc)}</loc>`
    + (u.lastmod ? `\n    <lastmod>${xmlEscape(u.lastmod)}</lastmod>` : '')
    + (u.changefreq ? `\n    <changefreq>${u.changefreq}</changefreq>` : '')
    + (u.priority ? `\n    <priority>${u.priority}</priority>` : '')
    + '\n  </url>';
}

function xmlResponse(body) {
  return new Response(body, {
    status: 200,
    headers: {
      'Content-Type': 'application/xml; charset=UTF-8',
      'Cache-Control': `public, max-age=${SITEMAP_TTL}, s-maxage=${SITEMAP_TTL}`,
    },
  });
}

/**
 * XML escape — obavezan jer u sitemap ulaze slugovi/ID-evi iz vanjskih izvora
 * (CDN listing, /api/persons). Uz 5 predefiniranih entiteta uklanjamo i
 * kontrolne znakove koje XML 1.0 uopće ne dopušta (parser bi pukao, ne samo
 * krivo prikazao).
 */
function xmlEscape(s) {
  return String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;')
    .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');
}

/**
 * Generira bogati description s fallback hijerarhijom:
 *   1. summary.summary.abstract_hr  (AI sažetak na hrvatskom — najbolja kvaliteta)
 *   2. info.description             (sirov YouTube opis — često sadrži linkove/hashtagove)
 */
function pickDescription(info, summary, lang) {
  const abstract = (lang === 'en' ? summary?.summary?.abstract_en : null)
    || summary?.summary?.abstract_hr;
  if (abstract && abstract.trim().length > 50) return abstract.trim();
  return (info.description || '').replace(/\s+/g, ' ').trim();
}

/**
 * EN polje ako postoji i nije prazno, inače HR — isti ugovor kao `pickLang`
 * u lib/services/episode_language.dart. Prijevodi su parcijalni (sekcija može
 * imati subtitle_en a nemati screenshot_description_en), pa se fallback radi
 * PO POLJU, ne po dokumentu.
 */
function pickLang(lang, hr, en) {
  if (lang === 'en' && typeof en === 'string' && en.trim().length > 0) return en;
  return hr;
}

/** List-varijanta `pickLang`. */
function pickLangList(lang, hr, en) {
  if (lang === 'en' && Array.isArray(en) && en.length > 0) return en;
  return hr;
}

/** Copy koji nije iz podataka nego iz chrome-a — po jeziku share URL-a. */
const SHARE_COPY = {
  hr: {
    from: (t) => `iz "${t}"`,
    chapterPart: (title, range, t) => `Dio "${title}" (${range}) iz: ${t}.`,
    moment: (clock, t) => `Trenutak na ${clock} iz: ${t}.`,
    momentTitle: (clock) => `Trenutak na ${clock}`,
    channelLabel: 'Kanal',
    durationLabel: 'Trajanje',
    locale: 'hr_HR',
    htmlLang: 'hr',
  },
  en: {
    from: (t) => `from "${t}"`,
    chapterPart: (title, range, t) => `Part "${title}" (${range}) of: ${t}.`,
    moment: (clock, t) => `Moment at ${clock} from: ${t}.`,
    momentTitle: (clock) => `Moment at ${clock}`,
    channelLabel: 'Channel',
    durationLabel: 'Duration',
    locale: 'en_US',
    htmlLang: 'en',
  },
};

/** "20260319" → "2026-03-19" */
function formatUploadDate(yyyymmdd) {
  if (!yyyymmdd || !/^\d{8}$/.test(yyyymmdd)) return null;
  return `${yyyymmdd.slice(0, 4)}-${yyyymmdd.slice(4, 6)}-${yyyymmdd.slice(6, 8)}`;
}

/** Sekunde → "H:MM:SS" ili "M:SS" za prikaz u OG title/description */
function formatClock(seconds) {
  const s = Math.max(0, Math.floor(seconds));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (n) => n.toString().padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

/** Pronađi chapter koji obuhvaća timestamp; vrati null ako nema chaptera ili tSec izvan range. */
function findChapter(chapters, tSec) {
  if (!Array.isArray(chapters) || chapters.length === 0 || tSec == null) return null;
  return chapters.find((c) =>
    typeof c.start_time === 'number' &&
    typeof c.end_time === 'number' &&
    tSec >= c.start_time &&
    tSec < c.end_time,
  ) || null;
}

/** "HH:MM:SS" → sekunde */
function clockToSec(clock) {
  if (!clock || typeof clock !== 'string') return null;
  const parts = clock.split(':').map((n) => parseInt(n, 10));
  if (parts.some((n) => Number.isNaN(n))) return null;
  if (parts.length === 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length === 2) return parts[0] * 60 + parts[1];
  return null;
}

/**
 * Pronađi article section koji obuhvaća tSec.
 * Article sections imaju AI-generirane subtitle/description/keywords/entities —
 * znatno bogatije od info.chapters (samo title).
 *
 * Algoritam: poravnaj sve sections po timestampu, pa zadnji čiji secStart <= tSec
 * (do sljedećeg sectiona ili kraja videa) je match.
 */
function findArticleSection(article, tSec, videoDuration) {
  if (!article || !Array.isArray(article.iterations) || tSec == null) return null;
  const flat = [];
  for (const it of article.iterations) {
    if (!Array.isArray(it.sections)) continue;
    for (const s of it.sections) {
      const start = clockToSec(s.screenshot_timestamp);
      if (start != null) flat.push({ start, section: s });
    }
  }
  if (flat.length === 0) return null;
  flat.sort((a, b) => a.start - b.start);
  // Pronađi zadnji section s start <= tSec
  let match = null;
  for (let i = 0; i < flat.length; i++) {
    const next = flat[i + 1];
    const end = next ? next.start : (typeof videoDuration === 'number' ? videoDuration : Infinity);
    if (tSec >= flat[i].start && tSec < end) {
      match = { ...flat[i].section, _start: flat[i].start, _end: end };
      break;
    }
  }
  return match;
}

/** Sekunde → ISO-8601 duration npr. 2661 → "PT44M21S" */
function isoDuration(seconds) {
  if (!seconds || seconds <= 0) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  let out = 'PT';
  if (h > 0) out += `${h}H`;
  if (m > 0) out += `${m}M`;
  if (s > 0 || (h === 0 && m === 0)) out += `${s}S`;
  return out;
}

function injectEpisodeTags(indexHtml, ytId, info, summary, article, hasOgShare, tSec, viewMode, sectionImageUrl, lang = 'hr') {
  const copy = SHARE_COPY[lang] || SHARE_COPY.hr;
  // Naslov epizode NIJE preveden — to je izvorni YouTube naslov (pipeline ga ne
  // prevodi). Prevodi se samo AI-generirani sloj: abstract, subtitle, opisi.
  const baseTitle = info.title || APP_NAME;
  const rawDesc = pickDescription(info, summary, lang);
  const baseDesc = rawDesc.length > 300 ? rawDesc.slice(0, 297) + '…' : rawDesc;

  // Match prioritet za timestamp share:
  //   1. Article section — najbogatiji (AI subtitle + screenshot_description + keywords)
  //   2. info.chapters    — basic (samo title + range)
  //   3. Plain timestamp  — samo sat (mm:ss)
  const section = (typeof tSec === 'number')
    ? findArticleSection(article, tSec, info.duration)
    : null;
  const chapter = (typeof tSec === 'number' && !section)
    ? findChapter(info.chapters, tSec)
    : null;
  const clock = (typeof tSec === 'number') ? formatClock(tSec) : null;
  let title = baseTitle;
  let desc = baseDesc;
  // Specifični tagovi za section/chapter — fallback su summary.key_topics u glavnom blocku ispod.
  let overrideTopicTags = null;

  if (section) {
    // Section subtitle je već specifičan ("Uvod i predstavljanje X"), ne treba mu cijeli baseTitle.
    // Skratimo subtitle ako je predug, da stane u 95 chara s clock+epname.
    const sub = pickLang(lang, section.subtitle, section.subtitle_en)
      || '';
    const subClean = sub.replace(/\s+/g, ' ').trim();
    const subShort = subClean.length > 80 ? subClean.slice(0, 77) + '…' : subClean;
    title = `${clock} · ${subShort}`;
    const range = `${formatClock(section._start)}–${formatClock(section._end)}`;
    const sectionDesc = (
      pickLang(lang, section.screenshot_description, section.screenshot_description_en)
      || pickLang(lang, section.content, section.content_en)
      || ''
    ).replace(/\s+/g, ' ').trim();
    desc = `${sectionDesc} — ${copy.from(baseTitle)} (${range})`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
    // Bogatiji article:tag-ovi za ovaj specifični trenutak.
    const tags = [];
    const kw = pickLangList(lang, section.keywords, section.keywords_en);
    const ent = pickLangList(lang, section.entities, section.entities_en);
    if (Array.isArray(kw)) tags.push(...kw);
    if (Array.isArray(ent)) tags.push(...ent);
    if (tags.length > 0) overrideTopicTags = tags.slice(0, 8);
  } else if (chapter) {
    title = `${clock} · ${chapter.title} — ${baseTitle}`;
    const range = `${formatClock(chapter.start_time)}–${formatClock(chapter.end_time)}`;
    desc = `${copy.chapterPart(chapter.title, range, baseTitle)} ${baseDesc}`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
  } else if (typeof tSec === 'number') {
    title = `${clock} — ${baseTitle}`;
    desc = `${copy.moment(clock, baseTitle)} ${baseDesc}`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
  }

  // og:image prioritet:
  //   1. og-t-<sec>.jpg (1200×630 JPEG ~100KB, WhatsApp-safe < 600KB) —
  //      Tier B pipeline output, section-specific frame s brand overlayem.
  //      Aktivira se kad og-sections.json manifest listira fajl za taj section.
  //   2. og-share.jpg (1200×630 JPEG ~100KB) — episode-level brand image.
  //   3. thumbnail.png (1280×720 PNG) — YouTube native, krajnji fallback.
  let thumb, thumbMime, thumbW, thumbH;
  if (sectionImageUrl) {
    thumb = sectionImageUrl;
    thumbMime = 'image/jpeg';
    thumbW = 1200;
    thumbH = 630;
  } else if (hasOgShare) {
    thumb = `${CDN}/images/${ytId}/og-share.jpg`;
    thumbMime = 'image/jpeg';
    thumbW = 1200;
    thumbH = 630;
  } else {
    thumb = `${CDN}/images/${ytId}/thumbnail.png`;
    thumbMime = 'image/png';
    thumbW = 1280;
    thumbH = 720;
  }
  // KRITIČNO: canonical mora biti pun path s /t/<sec> da svaki clip ima vlastiti
  // crawler cache entry (Facebook/LinkedIn/WhatsApp). Bez ovoga svi timestampovi
  // dijele isti preview.
  // Canonical uvijek pokazuje na /v/ (ne /m/) — SEO konsolidacija: /m/ je samo
  // alternativni view, ne distinct content. og:url, pak, prati share URL da
  // crawleri ne dignu canonical preko og:url-a i poremete cache.
  // `/en` je zasebna jezična varijanta ISTOG sadržaja — svaka ima svoj canonical
  // (self-referencing) i obje se međusobno navode preko hreflang. Da EN pokazuje
  // canonical na HR, tražili bismo od Googlea da EN varijantu ne indeksira.
  const langSuffix = lang === 'en' ? '/en' : '';
  const basePath = (typeof tSec === 'number')
    ? `/v/${ytId}/t/${tSec}`
    : `/v/${ytId}`;
  const canonical = `${SITE}${basePath}${langSuffix}`;
  const ogUrl = (viewMode === 'm')
    ? `${SITE}/m/${ytId}${typeof tSec === 'number' ? `/t/${tSec}` : ''}${langSuffix}`
    : canonical;
  const altLinks = [
    `  <link rel="alternate" hreflang="hr" href="${SITE}${basePath}">`,
    `  <link rel="alternate" hreflang="en" href="${SITE}${basePath}/en">`,
    `  <link rel="alternate" hreflang="x-default" href="${SITE}${basePath}">`,
  ].join('\n');
  const channel = info.channel || APP_NAME;
  const releaseDate = formatUploadDate(info.upload_date);
  const isoDur = isoDuration(info.duration);
  const videoUrl = `${CDN}/data/${ytId}/video.mp4`;
  // Varijanta epizode ima sintetički ID (`OspwepfLO_2`); YouTube zna samo
  // pravi ID izvorne epizode iz `_variant_of`. CDN/og URL-ovi ostaju na ytId.
  const ytUrl = info.webpage_url
    || `https://www.youtube.com/watch?v=${info._variant_of || ytId}`;

  // Tagovi — section override (section-specifični keywords+entities) > summary.key_topics > info.tags.
  const topicTags = overrideTopicTags
    || (summary?.summary?.key_topics?.length
      ? summary.summary.key_topics.slice(0, 6)
      : (info.tags || []).slice(0, 6));

  const articleTags = topicTags.map((t) => `  <meta property="article:tag" content="${x(t)}">`).join('\n');

  const tags = `
  <title>${x(title)} – ${APP_NAME}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">
${altLinks}

  <meta property="og:type" content="video.other">
  <meta property="og:locale" content="${copy.locale}">
  <meta property="og:locale:alternate" content="${lang === 'en' ? 'hr_HR' : 'en_US'}">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${ogUrl}">
  <meta property="og:image" content="${thumb}">
  <meta property="og:image:type" content="${thumbMime}">
  <meta property="og:image:width" content="${thumbW}">
  <meta property="og:image:height" content="${thumbH}">
  <meta property="og:image:alt" content="${x(title)}">
  <meta property="og:video" content="${videoUrl}">
  <meta property="og:video:secure_url" content="${videoUrl}">
  <meta property="og:video:type" content="video/mp4">${
    info.duration ? `\n  <meta property="og:video:duration" content="${info.duration}">` : ''
  }${
    releaseDate ? `\n  <meta property="og:video:release_date" content="${releaseDate}">` : ''
  }${
    typeof tSec === 'number' ? `\n  <meta property="og:video:start_time" content="${tSec}">` : ''
  }
  <meta property="article:author" content="${x(channel)}">${
    releaseDate ? `\n  <meta property="article:published_time" content="${releaseDate}">` : ''
  }
${articleTags}

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${thumb}">
  <meta name="twitter:image:alt" content="${x(title)}">
  <meta name="twitter:label1" content="${copy.channelLabel}">
  <meta name="twitter:data1" content="${x(channel)}">${
    info.duration_string ? `\n  <meta name="twitter:label2" content="${copy.durationLabel}">\n  <meta name="twitter:data2" content="${x(info.duration_string)}">` : ''
  }

  <script type="application/ld+json">
${jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl, tSec, chapter, section, baseTitle, ytId, lang })}
  </script>`;

  // Ukloni default tagove + bilo koji prethodni JSON-LD; pa injectaj video-specifične.
  // Crawler uvijek čita PRVI match — mora biti naš, ne default.
  let html = indexHtml;
  html = html
    .replace(/<title>[^<]*<\/title>/gi, '')
    .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|description)[^"']*["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']alternate["'][^>]*hreflang=[^>]*>/gi, '')
    .replace(/<script\s+type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
  // <html lang> mora pratiti jezik stranice — čitaju ga tražilice, prevoditelji
  // i screen readeri. index.html je statično `hr`.
  html = html.replace(/<html([^>]*?)\slang=["'][^"']*["']/i, `<html$1 lang="${copy.htmlLang}"`);
  return html.replace('</head>', `${tags}\n</head>`);
}

/**
 * Hrvatski broj + imenica po slavenskom plural pravilu:
 *   1  → one   (1 epizoda, 21 epizoda)
 *   2–4 → few  (2 epizode, 23 epizode)
 *   else → many (5 epizoda, 11 epizoda)
 * Iznimke: 11–14 uvijek "many".
 */
function croPlural(n, one, few, many) {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

/**
 * Injektira OG/JSON-LD tagove za person-hub profil (/p/<slug>).
 * Cilj: kad se link dijeli na WhatsApp/Facebook, preview pokaže IME osobe i
 * broj epizoda/kanala — ne generički domovina.ai opis.
 */
function injectPersonTags(indexHtml, slug, person, hasCdnAvatar) {
  const name = (person.name || '').trim() || 'Govornik';
  const epCount = Number(person.episode_count) || (Array.isArray(person.episodes) ? person.episodes.length : 0);
  const chCount = Number(person.channel_count) || (Array.isArray(person.channels) ? person.channels.length : 0);

  const mentionCount = Number(person.mention_episode_count)
    || (Array.isArray(person.mentions) ? person.mentions.length : 0);
  const mentionChCount = Array.isArray(person.mention_channels) ? person.mention_channels.length : 0;

  const epWord = croPlural(epCount, 'epizodi', 'epizode', 'epizoda'); // "u N epizodi/epizode/epizoda"
  const chWord = croPlural(chCount, 'kanalu', 'kanala', 'kanala');   // "na N kanalu/kanala"

  const title = `${name} — podcast profil`;
  // Osoba koja se SAMO spominje (nikad gost — povijesna/pokojna figura) nema
  // gostovanja; "gost u 0 epizoda" bi bio i netočan i odbojan u previewu.
  const mentionOnly = epCount === 0 && mentionCount > 0;
  const mEpWord = croPlural(mentionCount, 'epizodi', 'epizode', 'epizoda');
  const mChWord = croPlural(mentionChCount, 'kanalu', 'kanala', 'kanala');
  // Gramatika: "gost u 1 epizodi", "gost u 2 epizode", "gost u 6 epizoda";
  //            "na 1 kanalu", "na 6 kanala".
  const desc = mentionOnly
    ? `Gdje se u podcastima spominje ${name} — ${mentionCount} ${mEpWord} `
      + `na ${mentionChCount} ${mChWord}, sa skokom na točan trenutak spomena. `
      + `AI sažetci, transkripti i analiza podcasta na ${APP_NAME}.`
    : `Sve epizode u kojima ${name} govori — gost u ${epCount} ${epWord} `
      + `na ${chCount} ${chWord}. AI sažetci, transkripti i analiza podcasta na ${APP_NAME}.`;

  const canonical = `${SITE}/p/${slug}`;

  // og:image prioritet:
  //   1. person.avatar_url — eksplicitno postavljena slika iz domovina-rag
  //   2. CDN persons/images/<slug>/avatar_square.png — kad ju je pipeline
  //      producirao (HEAD provjera u ruti gore)
  //   3. brend og-image.png
  // WhatsApp voli 1200×630; za kvadratni avatar padamo na summary karticu.
  const explicitAvatar = typeof person.avatar_url === 'string' && person.avatar_url.startsWith('http');
  const hasAvatar = explicitAvatar || hasCdnAvatar === true;
  const avatar = explicitAvatar ? person.avatar_url : personAvatarUrl(slug);
  const image = hasAvatar ? avatar : `${SITE}/og-image.png`;
  const twitterCard = hasAvatar ? 'summary' : 'summary_large_image';

  // Split imena za og profile:first_name/last_name (best-effort).
  const parts = name.split(/\s+/);
  const firstName = parts[0] || name;
  const lastName = parts.length > 1 ? parts.slice(1).join(' ') : '';

  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'ProfilePage',
    mainEntity: {
      '@type': 'Person',
      name,
      url: canonical,
      ...(hasAvatar ? { image: avatar } : {}),
      subjectOf: mentionOnly
        ? {
          '@type': 'ItemList',
          numberOfItems: mentionCount,
          name: `Epizode u kojima se spominje ${name}`,
        }
        : {
          '@type': 'ItemList',
          numberOfItems: epCount,
          name: `Epizode u kojima govori ${name}`,
        },
    },
    publisher: {
      '@type': 'Organization',
      name: APP_NAME,
      logo: { '@type': 'ImageObject', url: `${SITE}/icons/Icon-512.png` },
    },
  }, null, 2);

  const tags = `
  <title>${x(title)} – ${APP_NAME}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="profile">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(name)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${x(image)}">
  <meta property="og:image:alt" content="${x(name)} — ${APP_NAME}">
  <meta property="profile:first_name" content="${x(firstName)}">${
    lastName ? `\n  <meta property="profile:last_name" content="${x(lastName)}">` : ''
  }
  <meta property="profile:username" content="${x(slug)}">

  <meta name="twitter:card" content="${twitterCard}">
  <meta name="twitter:title" content="${x(name)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:image:alt" content="${x(name)} — ${APP_NAME}">
  <meta name="twitter:label1" content="Epizode">
  <meta name="twitter:data1" content="${epCount}">
  <meta name="twitter:label2" content="Kanali">
  <meta name="twitter:data2" content="${chCount}">

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  // Ukloni default tagove + prethodni JSON-LD; injectaj person-specifične.
  let html = indexHtml;
  html = html
    .replace(/<title>[^<]*<\/title>/gi, '')
    .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|profile:|description)[^"']*["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<script\s+type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
  return html.replace('</head>', `${tags}\n</head>`);
}

/**
 * Isti 5-min bucket cache-buster kao CdnConfig._channelCacheBuster u appu —
 * channel listing JSON se mijenja s novim videima, a uploader stavlja
 * Cache-Control: immutable na sve fajlove, pa bi bez bustera edge servirao
 * stale listing danima.
 */
function channelCacheBuster() {
  return 'v=' + Math.floor(Date.now() / 300000);
}

/** "https://www.youtube.com/channel/UCxxx" → "UCxxx"; null kad ga nema. */
function extractUcId(channel) {
  const m = (channel.youtube_channel_url || '').match(/\/channel\/(UC[A-Za-z0-9_-]+)/);
  return m ? m[1] : null;
}

/**
 * Aktivna pinka kampanja za kanal — isti SECURITY DEFINER RPC koji app zove
 * (pinka_finance.active_campaign_for_subject; vidi lib/pinka_sdk/src/
 * pinka_client.dart). Anon key je javan (već zapečen u web bundle preko
 * --dart-define), ali ga držimo u Pages env (SUPABASE_URL + SUPABASE_ANON_KEY)
 * da ne živi u gitu. Bez env-a ili na grešci → null: doniraj stranica i dalje
 * dobije channel-specifične tagove, samo bez detalja kampanje.
 */
async function fetchCampaign(env, refs) {
  const base = (env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = env.SUPABASE_ANON_KEY;
  if (!base || !key || refs.length === 0) return null;
  try {
    const res = await fetch(`${base}/rest/v1/rpc/active_campaign_for_subject`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        'Content-Profile': 'pinka_finance',
      },
      body: JSON.stringify({
        p_subject_type: 'podcast_channel',
        p_subject_refs: refs,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const row = Array.isArray(data) ? data[0] : data;
    return row && typeof row === 'object' ? row : null;
  } catch (_) {
    return null;
  }
}

/**
 * Kandidat glasanja za /glasanje/<slug> — čita se PostgREST-om izravno iz
 * `domovina_ai.vote_candidates`, koji je `select`-om otvoren za `anon`
 * (domovina-api migracija 20260808120100_channel_voting_rls.sql). Nema RPC-a
 * „daj mi jednog kandidata", a `round_leaderboard` traži kolo i vraća cijelu
 * ljestvicu — za jedan OG naslov je to preskupo.
 *
 * NAMJERNO bez rezultata glasanja: `net`/`rank` se mijenjaju kroz dan, a
 * odgovor se edge-cachira sat vremena — preview bi lagao. Opisujemo kandidata,
 * ne trenutno stanje ljestvice (isti obrazac kao iznosi na /doniraj).
 *
 * Bez env-a ili na grešci → null: ruta i dalje dobije opće OG tagove glasanja.
 */
async function fetchVoteCandidate(env, slug) {
  const base = (env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = env.SUPABASE_ANON_KEY;
  if (!base || !key) return null;
  try {
    const q = `${base}/rest/v1/vote_candidates`
      + `?slug=eq.${encodeURIComponent(slug)}`
      + '&select=slug,display_name,avatar_url,tags,voditelji,subscribers,status'
      + '&limit=1';
    const res = await fetch(q, {
      headers: {
        'apikey': key,
        'Authorization': `Bearer ${key}`,
        // Tablica živi u domovina_ai shemi, ne u public.
        'Accept-Profile': 'domovina_ai',
      },
      cf: { cacheTtl: 300, cacheEverything: true },
    });
    if (!res.ok) return null;
    const rows = await res.json();
    const row = Array.isArray(rows) ? rows[0] : null;
    return row && row.display_name ? row : null;
  } catch (_) {
    return null;
  }
}

/**
 * OG/JSON-LD za „Izborni dan" (/glasanje i /glasanje/<slug>).
 *
 * [candidate] null → opći OG ljestvice; inače kandidat-specifičan naslov.
 * Canonical za nerazrješiv slug pada na `/glasanje` da nepostojeći kandidati ne
 * ulaze u indeks; og:url uvijek prati stvarni share URL (isti razlog kao /m/).
 */
function injectVotingTags(indexHtml, slug, candidate) {
  const ogUrl = slug ? `${SITE}/glasanje/${slug}` : `${SITE}/glasanje`;
  const canonical = candidate ? ogUrl : `${SITE}/glasanje`;

  const baseDesc = 'Ljestvica je javna: pogledaj koji se podcasti natječu za '
    + 'sljedeće mjesto u AI obradi. Glasa se e-Osobnom — jedan čovjek, jedan '
    + 'glas svaka 24 sata, u kolima od 14 dana.';

  let title = 'Izborni dan — glasaj koji podcast ide sljedeći';
  let desc = baseDesc;
  if (candidate) {
    const name = (candidate.display_name || '').trim();
    const hosts = Array.isArray(candidate.voditelji)
      ? candidate.voditelji.filter(Boolean).slice(0, 3).join(', ')
      : '';
    title = `Glasaj za ${name} — Izborni dan`;
    desc = `${name}${hosts ? ` (${hosts})` : ''} je kandidat za sljedeći kanal `
      + `koji ulazi u AI obradu na ${APP_NAME}. ${baseDesc}`;
    if (desc.length > 300) desc = desc.slice(0, 297) + '…';
  }

  // Avatar kandidata je kvadratan (CDN registry/avatars/<slug>.jpg) → twitter
  // "summary"; bez njega brend banner 1200×630 → "summary_large_image".
  const avatar = typeof candidate?.avatar_url === 'string'
    && candidate.avatar_url.startsWith('https://')
    ? candidate.avatar_url
    : null;
  const image = avatar || `${SITE}/og-image.png`;
  const twitterCard = avatar ? 'summary' : 'summary_large_image';

  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: title,
    description: desc,
    url: canonical,
    inLanguage: 'hr',
    ...(candidate ? {
      about: {
        '@type': 'PodcastSeries',
        name: (candidate.display_name || '').trim(),
        ...(avatar ? { image: avatar } : {}),
      },
      potentialAction: {
        '@type': 'VoteAction',
        name: title,
        target: { '@type': 'EntryPoint', urlTemplate: ogUrl },
      },
    } : {}),
    publisher: {
      '@type': 'Organization',
      name: APP_NAME,
      logo: { '@type': 'ImageObject', url: `${SITE}/icons/Icon-512.png` },
    },
  }, null, 2);

  const tags = `
  <title>${x(title)} – ${APP_NAME}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="website">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${ogUrl}">
  <meta property="og:image" content="${x(image)}">${
    avatar ? '' : '\n  <meta property="og:image:type" content="image/png">'
      + '\n  <meta property="og:image:width" content="1200">'
      + '\n  <meta property="og:image:height" content="630">'
  }
  <meta property="og:image:alt" content="${x(title)}">

  <meta name="twitter:card" content="${twitterCard}">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:image:alt" content="${x(title)}">

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  return stripHeadMeta(indexHtml).replace('</head>', `${tags}\n</head>`);
}

/**
 * Ukloni default <title>/meta/canonical/JSON-LD iz index.html prije injecta —
 * crawler uvijek čita PRVI match pa naš mora biti jedini.
 */
function stripHeadMeta(html) {
  return html
    .replace(/<title>[^<]*<\/title>/gi, '')
    .replace(/<meta\s[^>]*(?:property|name)=["'](?:og:|twitter:|article:|profile:|description)[^"']*["'][^>]*>/gi, '')
    .replace(/<link\s[^>]*rel=["']canonical["'][^>]*>/gi, '')
    .replace(/<script\s+type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi, '');
}

/**
 * OG/JSON-LD za kanal (/c/<slug>) — PodcastSeries s epizodama kao
 * workExample. Podaci iz CDN channels/data/<id>.json.
 */
function injectChannelTags(indexHtml, slug, ch) {
  const name = (ch.name || '').trim();
  const epCount = Number(ch.video_count)
    || (Array.isArray(ch.videos) ? ch.videos.length : 0);
  const epWord = croPlural(epCount, 'epizoda', 'epizode', 'epizoda');
  const hours = Math.round((Number(ch.total_duration_seconds) || 0) / 3600);
  const hourWord = croPlural(hours, 'sat', 'sata', 'sati');

  const title = `${name} — AI obrada podcasta`;
  const chDesc = (ch.description || '').replace(/\s+/g, ' ').trim();
  let desc = chDesc
    || `AI-obrađene epizode kanala ${name}: ${epCount} ${epWord}`
      + `${hours > 0 ? `, ≈ ${hours} ${hourWord} sadržaja` : ''}. `
      + `Sažetci, transkripti, poglavlja i Magisterium analiza na ${APP_NAME}.`;
  if (desc.length > 300) desc = desc.slice(0, 297) + '…';

  const canonical = `${SITE}/c/${slug}`;
  // Avatari su kvadratni (900×900) → twitter "summary" kartica, ne large.
  const image = ch.avatar_cover || ch.avatar_square || `${SITE}/og-image.png`;
  const twitterCard = (ch.avatar_cover || ch.avatar_square)
    ? 'summary' : 'summary_large_image';

  const episodes = (Array.isArray(ch.videos) ? ch.videos : []).slice(0, 10);
  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'PodcastSeries',
    name,
    url: canonical,
    description: desc,
    inLanguage: 'hr',
    ...(image ? { image } : {}),
    ...(ch.youtube_channel_url ? { sameAs: ch.youtube_channel_url } : {}),
    publisher: {
      '@type': 'Organization',
      name: APP_NAME,
      logo: { '@type': 'ImageObject', url: `${SITE}/icons/Icon-512.png` },
    },
    workExample: episodes.map((v) => ({
      '@type': 'PodcastEpisode',
      name: v.title_hr || v.title,
      url: `${SITE}/v/${v.id}`,
      ...(v.date ? { datePublished: v.date } : {}),
      ...(v.duration_seconds
        ? { timeRequired: isoDuration(v.duration_seconds) } : {}),
    })),
  }, null, 2);

  const tags = `
  <title>${x(title)} – ${APP_NAME}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="website">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${canonical}">
  <meta property="og:image" content="${x(image)}">
  <meta property="og:image:alt" content="${x(name)} — ${APP_NAME}">

  <meta name="twitter:card" content="${twitterCard}">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:image:alt" content="${x(name)} — ${APP_NAME}">
  <meta name="twitter:label1" content="Epizode">
  <meta name="twitter:data1" content="${epCount}">${
    hours > 0 ? `\n  <meta name="twitter:label2" content="Sadržaj">\n  <meta name="twitter:data2" content="≈ ${hours} ${hourWord}">` : ''
  }

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  return stripHeadMeta(indexHtml).replace('</head>', `${tags}\n</head>`);
}

/**
 * OG/JSON-LD za Zid podrške (/c/<slug>/doniraj | /support) — DonateAction.
 * NAMJERNO bez iznosa (mijenjaju se, a odgovor se edge-cachira 1h); opisujemo
 * mehanizam (SEPA + on-chain EURe) i javnu Gnosis Safe adresu kampanje.
 * Canonical uvijek /doniraj (HR primarna); og:url prati stvarni share path.
 */
function injectSupportTags(indexHtml, slug, variant, ch, campaign) {
  const name = (ch.name || '').trim();
  const canonical = `${SITE}/c/${slug}/doniraj`;
  const ogUrl = `${SITE}/c/${slug}/${variant}`;

  const campTitle = (campaign?.title || '').replace(/\s+/g, ' ').trim();
  const title = campTitle || `Podrži ${name} — Zid podrške`;
  const campDesc = (campaign?.description || '').replace(/\s+/g, ' ').trim();
  let desc = campDesc
    || `Podrži kanal ${name} izravno: SEPA uplata (EPC QR) ili on-chain EURe `
      + 'donacija na javni Gnosis Safe kampanje. Svaki doprinos dobiva '
      + 'kvadratić na Zidu podrške.';
  if (desc.length > 300) desc = desc.slice(0, 297) + '…';

  const cover = campaign?.cover_image_url || null;
  const image = cover || ch.avatar_cover || ch.avatar_square
    || `${SITE}/og-image.png`;
  const twitterCard = cover ? 'summary_large_image' : 'summary';
  const safe = (campaign?.destination_address || '').trim() || null;

  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'DonateAction',
    name: title,
    description: desc,
    url: canonical,
    recipient: {
      '@type': 'Organization',
      name,
      url: `${SITE}/c/${slug}`,
      ...(ch.youtube_channel_url ? { sameAs: ch.youtube_channel_url } : {}),
      ...(safe ? {
        identifier: {
          '@type': 'PropertyValue',
          propertyID: 'gnosis-safe',
          name: 'Gnosis Safe kampanje (EURe, chain 100)',
          value: safe,
        },
      } : {}),
    },
    target: {
      '@type': 'EntryPoint',
      urlTemplate: canonical,
      actionPlatform: [
        'https://schema.org/DesktopWebPlatform',
        'https://schema.org/MobileWebPlatform',
      ],
    },
    provider: { '@type': 'Organization', name: APP_NAME, url: SITE },
  }, null, 2);

  const tags = `
  <title>${x(title)} – ${APP_NAME}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${canonical}">

  <meta property="og:type" content="website">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="${APP_NAME}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${ogUrl}">
  <meta property="og:image" content="${x(image)}">
  <meta property="og:image:alt" content="${x(title)}">

  <meta name="twitter:card" content="${twitterCard}">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:image:alt" content="${x(title)}">
  <meta name="twitter:label1" content="Kanal">
  <meta name="twitter:data1" content="${x(name)}">
  <meta name="twitter:label2" content="Načini podrške">
  <meta name="twitter:data2" content="SEPA · EURe (Gnosis)">

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  return stripHeadMeta(indexHtml).replace('</head>', `${tags}\n</head>`);
}

/**
 * OG za izlog sponzorskih trenutaka kanala (/c/<slug>/oglasi). Publika je
 * brand, ne slušatelj: naslov govori što se kupuje. Bez cijena (edge cache).
 */
function injectSponsorStoreTags(indexHtml, slug, ch) {
  const name = (ch.name || '').trim();
  const url = `${SITE}/c/${slug}/oglasi`;
  const title = `Oglašavanje na kanalu ${name}`;
  const desc = `Izaberite trenutak u epizodi kanala ${name} i Vaš brand bit će `
    + 'označen kao sponzor upravo tog dijela. Samoposluga: plaćanje SEPA '
    + 'uplatom, oglas ide uživo čim uplata stigne, račun se izdaje automatski.';
  const image = ch.avatar_cover || ch.avatar_square || `${SITE}/og-image.png`;
  return injectSponsorTags(indexHtml, { title, desc, url, image, name, slug });
}

/** OG za kartu sponzorskih trenutaka epizode (/v/<id>/sponzoriraj). */
function injectSponsorEpisodeTags(indexHtml, id, info, summary) {
  const epTitle = ((summary?.summary?.title_hr) || info.title || '')
    .replace(/\s+/g, ' ').trim();
  const url = `${SITE}/v/${id}/sponzoriraj`;
  const title = `Sponzorirajte trenutak: ${epTitle}`;
  const desc = 'Odaberite trenutak u ovoj epizodi i Vaš brand bit će označen '
    + 'kao sponzor tog dijela, uz naslov sekcije koju sponzorirate. Plaćanje '
    + 'SEPA uplatom, oglas ide uživo automatski.';
  const image = `${CDN}/images/${id}/og-share.jpg`;
  return injectSponsorTags(indexHtml, { title, desc, url, image, name: info.channel || '' });
}

function injectSponsorTags(indexHtml, { title, desc, url, image, name }) {
  const jsonLd = JSON.stringify({
    '@context': 'https://schema.org',
    '@type': 'WebPage',
    name: title,
    description: desc,
    url,
    publisher: { '@type': 'Organization', name: APP_NAME, url: SITE },
  }, null, 2);
  const tags = `
  <title>${x(title)} – ${x(APP_NAME)}</title>
  <meta name="description" content="${x(desc)}">
  <link rel="canonical" href="${url}">

  <meta property="og:type" content="website">
  <meta property="og:locale" content="hr_HR">
  <meta property="og:site_name" content="${x(APP_NAME)}">
  <meta property="og:logo" content="${SITE}/og-image-square.png">
  <meta property="og:title" content="${x(title)}">
  <meta property="og:description" content="${x(desc)}">
  <meta property="og:url" content="${url}">
  <meta property="og:image" content="${x(image)}">
  <meta property="og:image:alt" content="${x(title)}">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${x(title)}">
  <meta name="twitter:description" content="${x(desc)}">
  <meta name="twitter:image" content="${x(image)}">
  <meta name="twitter:label1" content="Kanal">
  <meta name="twitter:data1" content="${x(name)}">

  <script type="application/ld+json">
${jsonLd}
  </script>`;

  return stripHeadMeta(indexHtml).replace('</head>', `${tags}\n</head>`);
}

function jsonLdVideoObject({ title, desc, thumb, canonical, releaseDate, isoDur, channel, ytUrl, videoUrl, tSec, chapter, section, baseTitle, ytId, lang = 'hr' }) {
  const copy = SHARE_COPY[lang] || SHARE_COPY.hr;
  const obj = {
    '@context': 'https://schema.org',
    '@type': 'VideoObject',
    name: typeof tSec === 'number' ? (baseTitle || title) : title,
    description: desc,
    thumbnailUrl: thumb,
    contentUrl: videoUrl,
    embedUrl: typeof tSec === 'number' ? `${SITE}/v/${ytId}` : canonical,
    url: typeof tSec === 'number' ? `${SITE}/v/${ytId}` : canonical,
    sameAs: ytUrl,
    // Govorni sadržaj je hrvatski bez obzira na jezik stranice — toggle prevodi
    // samo AI-generirani tekst (vidi lib/services/episode_language.dart).
    inLanguage: 'hr',
    publisher: {
      '@type': 'Organization',
      name: APP_NAME,
      logo: {
        '@type': 'ImageObject',
        url: `${SITE}/icons/Icon-512.png`,
      },
    },
    author: { '@type': 'Person', name: channel },
  };
  if (releaseDate) obj.uploadDate = releaseDate;
  if (isoDur) obj.duration = isoDur;

  // Schema.org Clip — signaliziraj Googleu da je ovo specifični trenutak.
  // Vidi: https://developers.google.com/search/docs/appearance/structured-data/video#clip
  // Prioritet imena: section.subtitle > chapter.title > generički "Trenutak na X".
  if (typeof tSec === 'number') {
    let clipName;
    let clipEnd;
    if (section) {
      clipName = (pickLang(lang, section.subtitle, section.subtitle_en) || '')
        .replace(/\s+/g, ' ').trim() || copy.momentTitle(formatClock(tSec));
      if (typeof section._end === 'number' && Number.isFinite(section._end)) {
        clipEnd = Math.floor(section._end);
      }
    } else if (chapter) {
      clipName = chapter.title;
      if (typeof chapter.end_time === 'number') clipEnd = Math.floor(chapter.end_time);
    } else {
      clipName = copy.momentTitle(formatClock(tSec));
    }
    const clip = {
      '@type': 'Clip',
      name: clipName,
      url: canonical,
      startOffset: tSec,
    };
    if (typeof clipEnd === 'number') clip.endOffset = clipEnd;
    obj.hasPart = clip;
  }

  return JSON.stringify(obj, null, 2);
}

function htmlResponse(html, cacheControl) {
  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html;charset=UTF-8',
      'Cache-Control': cacheControl,
      // Skwasm (Flutter WebAssembly renderer) zahtijeva ove headere
      // za SharedArrayBuffer koji koristi za multi-threading.
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    },
  });
}

/** HTML escape za umetanje u atribute */
function x(s) {
  return (s || '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

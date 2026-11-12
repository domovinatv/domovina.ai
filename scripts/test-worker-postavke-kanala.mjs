/**
 * Postavke kanala S6: web/_worker.js (OG, JSON-LD, noindex, sitemap, og:video)
 * i web/cast-receiver-gate.js (Cast receiver odbija povučen kanal), s LAŽNIM
 * bindingom KATALOG i lažnim CDN-om. Bez mreže.
 *
 * Kanali u lažnom `GET /settings` (oblik iz katalog/src/api/v1.ts settingsMap):
 *   UC_W  povučen (channel_enabled off)
 *   UC_D  obrisan (tombstone, deleted_at)
 *   UC_C  search_engines, cdn_playback, share_clips, english_translation off
 *   UC_A  article_summary off (+ ovisni ključevi, kako ih katalog preslika)
 *   UC_N  nema ga u mapi = sve uključeno
 *
 * Korištenje:  node scripts/test-worker-postavke-kanala.mjs
 */
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const INDEX_HTML = await readFile(path.join(root, 'web/index.html'), 'utf8');
const worker = (await import(pathToFileURL(path.join(root, 'web/_worker.js')).href)).default;
await import(pathToFileURL(path.join(root, 'web/cast-receiver-gate.js')).href);
const gate = globalThis.DomovinaCastGate;

const CATALOG = 'https://domovina.ai/api/katalog/v1';
const CDN = 'https://cdn.domovina.ai';
const uc = (c) => `UC${c.repeat(22)}`;
const UC_W = uc('w');
const UC_D = uc('d');
const UC_C = uc('c');
const UC_A = uc('a');
const UC_N = uc('n');

const SETTINGS = {
  version: '1',
  catalog: '300',
  settings: {
    [UC_W]: { status: 'withdrawn', off: ['article_summary', 'channel_enabled', 'cdn_playback'] },
    [UC_D]: { status: 'deleted', off: ['channel_enabled'], deleted_at: '2026-11-12T22:30:00.000Z' },
    [UC_C]: { status: 'active', off: ['cdn_playback', 'english_translation', 'search_engines', 'share_clips'] },
    [UC_A]: { status: 'active', off: ['article_summary', 'ebook', 'english_translation', 'magisterium', 'news_portal', 'share_clips'] },
  },
};

// Epizode: ID → UC kanala. Svaka ima isti AI sadržaj, pa razlika u izlazu
// dolazi samo od postavki.
const EPISODES = {
  epWithdrwn1: { uc: UC_W, channel: 'Povučeni kanal' },
  epDeleted01: { uc: UC_D, channel: 'Obrisani kanal' },
  epCustom001: { uc: UC_C, channel: 'Kanal C' },
  epNoAi00001: { uc: UC_A, channel: 'Kanal A' },
  epNormal001: { uc: UC_N, channel: 'Kanal N' },
};
const SECRET = 'TAJNI-SADRZAJ-EPIZODE';
const info = (id) => ({
  id,
  title: `Naslov ${SECRET} ${id}`,
  description: `YouTube opis epizode ${id}, dovoljno dug da prođe kao opis u OG-u bez sažetka.`,
  channel: EPISODES[id].channel,
  channel_id: EPISODES[id].uc,
  webpage_url: `https://www.youtube.com/watch?v=${id}`,
  duration: 3600,
  upload_date: '20261101',
});
const summary = (en) => ({
  summary: {
    abstract_hr: `AI sažetak ${SECRET} na hrvatskom, dovoljno dug da ga pickDescription uzme kao opis.`,
    ...(en ? { abstract_en: `AI summary ${SECRET} in English, long enough to be used as the description.`, title_en: 'English title' } : {}),
    key_topics: ['tema'],
  },
});
const article = {
  iterations: [{ sections: [
    { screenshot_timestamp: '00:00:00', subtitle: 'Uvod', content: 'Uvodni dio.' },
    { screenshot_timestamp: '00:10:00', subtitle: `Sekcija ${SECRET}`, content: 'Sadržaj sekcije.', subtitle_en: 'Section EN' },
  ] }],
};
const OG_SECTIONS = { sections: { 600: 'og-t-600.jpg' }, sections_en: { 600: 'og-t-600-en.jpg' } };

// Kanali na CDN-u (Tier 1 listing + index.json).
const LISTINGS = {
  povuceni_kanal: { name: 'Povučeni kanal', uc: UC_W, videos: ['epWithdrwn1'] },
  obrisani_kanal: { name: 'Obrisani kanal', uc: UC_D, videos: ['epDeleted01'] },
  kanal_c: { name: 'Kanal C', uc: UC_C, videos: ['epCustom001'] },
  kanal_n: { name: 'Kanal N', uc: UC_N, videos: ['epNormal001'] },
};
const listing = (id) => {
  const l = LISTINGS[id];
  return {
    name: l.name,
    video_count: l.videos.length,
    youtube_channel_url: `https://www.youtube.com/channel/${l.uc}`,
    videos: l.videos.map((v) => ({ id: v, title: 'x', date: '2026-11-01' })),
  };
};

globalThis.fetch = async (input, init = {}) => {
  const u = new URL(String(typeof input === 'string' ? input : input.url));
  const p = u.pathname;
  const ok = (body) => new Response(JSON.stringify(body), { status: 200 });
  if (u.origin === CDN) {
    let m = p.match(/^\/data\/([^/]+)\/(.+)$/);
    if (m && EPISODES[m[1]]) {
      if (m[2] === 'info.json') return ok(info(m[1]));
      if (m[2] === 'summary.json') return ok(summary(false));
      if (m[2] === 'summary.en.json') return ok(summary(true));
      if (m[2] === 'article.json' || m[2] === 'article.en.json') return ok(article);
    }
    m = p.match(/^\/images\/([^/]+)\/(.+)$/);
    if (m && EPISODES[m[1]]) {
      if (m[2] === 'og-sections.json') return ok(OG_SECTIONS);
      if (m[2] === 'og-share.jpg' && init.method === 'HEAD') return new Response(null, { status: 200 });
    }
    if (p === '/channels/data/index.json') {
      return ok({
        generated_at: '2026-11-12T10:00:00Z',
        channels: Object.keys(LISTINGS).map((id) => ({
          id, name: LISTINGS[id].name,
          youtube_channel_url: `https://www.youtube.com/channel/${LISTINGS[id].uc}`,
          latest_video: { date: '2026-11-01' },
        })),
      });
    }
    m = p.match(/^\/channels\/data\/([a-z0-9_]+)\.json$/);
    if (m && LISTINGS[m[1]]) return ok(listing(m[1]));
  }
  if (u.origin === 'https://domovina.ai' && p === '/api/katalog/v1/settings') return ok(SETTINGS);
  return new Response('not found', { status: 404 });
};

const assets = { fetch: async () => new Response(INDEX_HTML, { status: 200 }) };

/** Lažni katalog: /settings → SETTINGS; /channels/<slug> → `channels[slug]`. */
function fakeKatalog({ settings = SETTINGS, channels = {} } = {}) {
  const calls = [];
  return {
    calls,
    fetch: async (req) => {
      calls.push(req.url);
      const u = new URL(req.url);
      const j = (b, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { 'Content-Type': 'application/json' } });
      if (u.pathname.endsWith('/settings')) return settings ? j(settings) : j({ error: 'x' }, 500);
      const m = u.pathname.match(/\/channels\/([^/]+)$/);
      if (m && channels[m[1]]) return j(channels[m[1]]);
      return j({ ok: false, error: 'channel_not_found' }, 404);
    },
  };
}

async function get(p, env = { KATALOG: fakeKatalog() }) {
  const res = await worker.fetch(new Request(`https://domovina.ai${p}`), { ASSETS: assets, ...env });
  return { res, html: await res.text() };
}

const meta = (html, attr, val) => {
  const m = html.match(new RegExp(`<meta[^>]+${attr}=["']${val}["'][^>]+content=["']([^"']*)["']`, 'i'));
  return m ? m[1] : null;
};
const has = (html, attr, val) => new RegExp(`<meta[^>]+${attr}=["']${val}["']`, 'i').test(html);
const canonical = (html) => (html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']*)["']/i) || [])[1] ?? null;
const hreflangs = (html) => [...html.matchAll(/<link[^>]+hreflang=["']([^"']+)["']/gi)].map((m) => m[1]);
const ldJson = (html) => {
  const m = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/);
  return m ? JSON.parse(m[1]) : null;
};

let passed = 0;
let failed = 0;
function check(label, good, detail = '') {
  if (good) { passed++; console.log(`  \x1b[32m✓\x1b[0m ${label}`); }
  else { failed++; console.log(`  \x1b[31m✗\x1b[0m ${label}${detail ? `  — ${detail}` : ''}`); }
}
function section(t) { console.log(`\n\x1b[1m── ${t}\x1b[0m`); }

// ── 1. Povučen kanal: sve varijante /v/ i /m/ ────────────────────────────────
section('povučen kanal: /v/ i /m/ (sve varijante) bez sadržaja epizode');
for (const p of [
  '/v/epWithdrwn1', '/v/epWithdrwn1/en', '/v/epWithdrwn1/hr', '/v/epWithdrwn1/t/600',
  '/v/epWithdrwn1/t/600/en', '/m/epWithdrwn1', '/m/epWithdrwn1/t/600/en', '/v/epWithdrwn1/sponzoriraj',
]) {
  const { res, html } = await get(p);
  const en = p.endsWith('/en');
  const title = meta(html, 'property', 'og:title') || '';
  const ld = ldJson(html);
  check(`${p}: 200 + noindex`, res.status === 200 && res.headers.get('x-robots-tag') === 'noindex', `${res.status} ${res.headers.get('x-robots-tag')}`);
  check(`${p}: naslov o povlačenju`, en
    ? title === 'The owner has withdrawn this content from DOMOVINA.ai'
    : title === 'Vlasnik je povukao ovaj sadržaj s DOMOVINA.ai', title);
  check(`${p}: nigdje sadržaj epizode`, !html.includes(SECRET) && !html.includes('AI sažetak') && !html.includes('YouTube opis epizode'));
  check(`${p}: generička slika`, meta(html, 'property', 'og:image') === 'https://domovina.ai/og-image.png', meta(html, 'property', 'og:image'));
  check(`${p}: bez og:video i hreflang`, !has(html, 'property', 'og:video') && hreflangs(html).length === 0);
  check(`${p}: JSON-LD WebPage, ne VideoObject`, ld && ld['@type'] === 'WebPage' && !('contentUrl' in ld), ld && ld['@type']);
  check(`${p}: canonical = traženi URL`, canonical(html) === `https://domovina.ai${p}`, canonical(html));
  check(`${p}: cache 5 min`, res.headers.get('cache-control') === 'public, max-age=300, s-maxage=300', res.headers.get('cache-control'));
}
{
  const { html } = await get('/v/epWithdrwn1');
  const ld = ldJson(html);
  check('povučen: opis spominje YouTube', (meta(html, 'property', 'og:description') || '').includes('YouTube'));
  check('povučen: JSON-LD relatedLink na YouTube', ld && ld.relatedLink === 'https://www.youtube.com/watch?v=epWithdrwn1', ld && ld.relatedLink);
  check('povučen: <html lang="hr">', /<html[^>]*\slang="hr"/.test(html));
  const en = await get('/v/epWithdrwn1/en');
  check('povučen /en: <html lang="en"> + en_US', /<html[^>]*\slang="en"/.test(en.html) && meta(en.html, 'property', 'og:locale') === 'en_US');
}

// ── 2. Obrisan kanal ─────────────────────────────────────────────────────────
section('obrisan kanal: datum brisanja, bez YouTubea');
{
  const { res, html } = await get('/v/epDeleted01/t/600');
  const ld = ldJson(html);
  // 22:30 UTC 12. 11. = 23:30 u Zagrebu, isti dan; datum je zagrebački.
  check('naslov s datumom dd. mm. gggg.', meta(html, 'property', 'og:title') === 'Kanal je trajno uklonjen s DOMOVINA.ai 12. 11. 2026.', meta(html, 'property', 'og:title'));
  check('noindex', res.headers.get('x-robots-tag') === 'noindex');
  check('bez YouTubea (odluka 507)', !/youtube/i.test(html.match(/<head>[\s\S]*<\/head>/i)?.[0].replace(/<script src[^>]*>/g, '') ?? '') && !(ld && ld.relatedLink));
  check('bez sadržaja epizode', !html.includes(SECRET));
  const en = await get('/m/epDeleted01/en');
  check('EN naslov', meta(en.html, 'property', 'og:title') === 'This channel was permanently removed from DOMOVINA.ai on 12. 11. 2026.', meta(en.html, 'property', 'og:title'));
}

// ── 3. /c/<slug> ─────────────────────────────────────────────────────────────
section('/c/<slug>: povučen i obrisan Tier 1 kanal, sve podrute');
for (const p of ['/c/povuceni-kanal', '/c/povuceni-kanal/doniraj', '/c/povuceni-kanal/support', '/c/povuceni-kanal/oglasi']) {
  const { res, html } = await get(p);
  check(`${p}: povučen OG + noindex`, meta(html, 'property', 'og:title') === 'Vlasnik je povukao ovaj sadržaj s DOMOVINA.ai'
    && res.headers.get('x-robots-tag') === 'noindex', meta(html, 'property', 'og:title'));
  check(`${p}: ime kanala u opisu, YouTube kanala u JSON-LD`, (meta(html, 'property', 'og:description') || '').includes('Povučeni kanal')
    && ldJson(html)?.relatedLink === `https://www.youtube.com/channel/${UC_W}`);
  check(`${p}: bez PodcastSeries`, ldJson(html)?.['@type'] === 'WebPage');
}
{
  const { res, html } = await get('/c/obrisani-kanal');
  check('/c/obrisani-kanal: datum + noindex', meta(html, 'property', 'og:title') === 'Kanal je trajno uklonjen s DOMOVINA.ai 12. 11. 2026.'
    && res.headers.get('x-robots-tag') === 'noindex', meta(html, 'property', 'og:title'));
  check('/c/obrisani-kanal: bez relatedLink', !ldJson(html)?.relatedLink);
}

section('/c/<slug>: listing obrisan (S9), katalog vraća tombstone');
{
  const k = fakeKatalog({
    channels: {
      'nestali-kanal': {
        version: '1', catalog: '300', state: 'deleted', deleted_at: '2026-11-10T09:00:00.000Z',
        item: { slug: 'nestali-kanal', name: 'Nestali kanal', tier: 1, processed_count: 0, youtube_channel_id: null },
      },
      'tier-dva-povucen': {
        version: '1', catalog: '300', state: 'withdrawn',
        item: { slug: 'tier-dva-povucen', name: 'Tier dva', tier: 2, processed_count: 4, youtube_channel_id: uc('t') },
      },
      'tier-dva-skriven': {
        version: '1', catalog: '300',
        item: { slug: 'tier-dva-skriven', name: 'Skriven', tier: 2, processed_count: 4, youtube_channel_id: UC_C },
      },
    },
  });
  const a = await get('/c/nestali-kanal', { KATALOG: k });
  check('tombstone: naslov s datumom', meta(a.html, 'property', 'og:title') === 'Kanal je trajno uklonjen s DOMOVINA.ai 10. 11. 2026.', meta(a.html, 'property', 'og:title'));
  check('tombstone: ime iz tombstonea + noindex', (meta(a.html, 'property', 'og:description') || '').includes('Nestali kanal') && a.res.headers.get('x-robots-tag') === 'noindex');
  const b = await get('/c/tier-dva-povucen', { KATALOG: k });
  check('Tier 2 povučen (state iz kataloga)', meta(b.html, 'property', 'og:title') === 'Vlasnik je povukao ovaj sadržaj s DOMOVINA.ai'
    && ldJson(b.html)?.relatedLink === `https://www.youtube.com/channel/${uc('t')}`);
  const c = await get('/c/tier-dva-skriven', { KATALOG: k });
  check('Tier 2 sa search_engines off: običan OG + noindex', meta(c.html, 'property', 'og:title') === 'Skriven — AI obrada podcasta'
    && c.res.headers.get('x-robots-tag') === 'noindex', `${meta(c.html, 'property', 'og:title')} ${c.res.headers.get('x-robots-tag')}`);
}

// ── 4. Ključevi na aktivnom kanalu ───────────────────────────────────────────
section('kanal C: search_engines, cdn_playback, share_clips, english_translation off');
{
  const v = await get('/v/epCustom001');
  const ld = ldJson(v.html);
  check('noindex', v.res.headers.get('x-robots-tag') === 'noindex');
  check('običan OG epizode (nije povučen)', (meta(v.html, 'property', 'og:title') || '').startsWith('Naslov'));
  check('bez og:video', !has(v.html, 'property', 'og:video') && !has(v.html, 'property', 'og:video:secure_url'));
  check('JSON-LD VideoObject bez contentUrl', ld && ld['@type'] === 'VideoObject' && !('contentUrl' in ld), JSON.stringify(ld && ld.contentUrl));
  check('bez hreflang i og:locale:alternate', hreflangs(v.html).length === 0 && !has(v.html, 'property', 'og:locale:alternate'));

  const t = await get('/v/epCustom001/t/600');
  check('/t/: bez og-t slike (share_clips)', meta(t.html, 'property', 'og:image') === `${CDN}/images/epCustom001/og-share.jpg`, meta(t.html, 'property', 'og:image'));

  const en = await get('/v/epCustom001/t/600/en');
  check('/en: canonical na HR (odluka 503)', canonical(en.html) === 'https://domovina.ai/v/epCustom001/t/600', canonical(en.html));
  check('/en: HR OG (locale, lang, opis)', meta(en.html, 'property', 'og:locale') === 'hr_HR' && /<html[^>]*\slang="hr"/.test(en.html)
    && !en.html.includes('in English'));
  check('/en: bez hreflang en', !hreflangs(en.html).includes('en'));
  const m = await get('/m/epCustom001/en');
  check('/m/…/en: og:url bez /en', meta(m.html, 'property', 'og:url') === 'https://domovina.ai/m/epCustom001', meta(m.html, 'property', 'og:url'));

  const c = await get('/c/kanal-c');
  check('/c/kanal-c: običan OG + noindex', (meta(c.html, 'property', 'og:title') || '').startsWith('Kanal C') && c.res.headers.get('x-robots-tag') === 'noindex');
}

section('kanal A: article_summary off → opis s YouTubea, bez AI sekcije');
{
  const v = await get('/v/epNoAi00001');
  const desc = meta(v.html, 'property', 'og:description') || '';
  check('opis iz info.json, ne AI sažetak', desc.startsWith('YouTube opis epizode') && !v.html.includes('AI sažetak'), desc);
  check('indeksira se (search_engines uključen)', !v.res.headers.get('x-robots-tag'));
  check('og:video ostaje (cdn_playback uključen)', has(v.html, 'property', 'og:video'));
  const t = await get('/v/epNoAi00001/t/600');
  check('/t/: bez naslova AI sekcije', !t.html.includes('Sekcija') && meta(t.html, 'property', 'og:title').startsWith('10:00'), meta(t.html, 'property', 'og:title'));
}

section('kanal bez postavki: izlaz kao prije (i bez bindinga)');
{
  for (const p of ['/v/epNormal001', '/v/epNormal001/t/600/en', '/m/epNormal001', '/c/kanal-n']) {
    const a = await get(p);
    const b = await get(p, {});
    check(`${p}: bajt-identično s bindingom i bez`, a.html === b.html && a.res.headers.get('cache-control') === b.res.headers.get('cache-control')
      && !a.res.headers.get('x-robots-tag'));
  }
  const v = await get('/v/epNormal001/t/600/en');
  check('normalan /en: hreflang hr+en+x-default', hreflangs(v.html).join(',') === 'hr,en,x-default', hreflangs(v.html).join(','));
  check('normalan /t/: og-t-600-en.jpg', meta(v.html, 'property', 'og:image') === `${CDN}/images/epNormal001/og-t-600-en.jpg`);
  check('normalan: og:video + contentUrl', has(v.html, 'property', 'og:video') && ldJson(v.html)?.contentUrl === `${CDN}/data/epNormal001/video.mp4`);
}

section('fail-open: katalog nedostupan → povučen kanal se prikazuje normalno');
{
  const k = fakeKatalog({ settings: null });
  const { res, html } = await get('/v/epWithdrwn1', { KATALOG: k });
  check('/settings 500: običan OG, bez noindexa', (meta(html, 'property', 'og:title') || '').startsWith('Naslov') && !res.headers.get('x-robots-tag'));
}

section('donacije / sponzorski trenuci isključeni na aktivnom kanalu');
{
  const s = { version: '1', catalog: '301', settings: { [UC_N]: { status: 'active', off: ['donations', 'paid_sponsor_moments'] } } };
  const k = fakeKatalog({ settings: s });
  const d = await get('/c/kanal-n/doniraj', { KATALOG: k });
  check('/doniraj: OG kanala, ne zid + noindex', (meta(d.html, 'property', 'og:title') || '').startsWith('Kanal N') && d.res.headers.get('x-robots-tag') === 'noindex', meta(d.html, 'property', 'og:title'));
  const o = await get('/c/kanal-n/oglasi', { KATALOG: k });
  check('/oglasi: OG kanala + noindex', (meta(o.html, 'property', 'og:title') || '').startsWith('Kanal N') && o.res.headers.get('x-robots-tag') === 'noindex');
  const sp = await get('/v/epNormal001/sponzoriraj', { KATALOG: k });
  check('/v/…/sponzoriraj: plain SPA + noindex', sp.html === INDEX_HTML && sp.res.headers.get('x-robots-tag') === 'noindex');
  const c = await get('/c/kanal-n', { KATALOG: k });
  check('/c/kanal-n i dalje indeksiran', !c.res.headers.get('x-robots-tag'));
}

// ── 5. Sitemap ───────────────────────────────────────────────────────────────
section('sitemap bez povučenih, obrisanih i search_engines=false kanala');
{
  const { res, html: xml } = await get('/sitemap.xml');
  check('200 XML', res.status === 200 && xml.startsWith('<?xml'));
  check('kanal N i njegova epizoda su unutra', xml.includes('/c/kanal-n<') && xml.includes('/v/epNormal001<'));
  for (const [c, ep] of [['povuceni-kanal', 'epWithdrwn1'], ['obrisani-kanal', 'epDeleted01'], ['kanal-c', 'epCustom001']]) {
    check(`bez /c/${c} i /v/${ep}`, !xml.includes(`/c/${c}<`) && !xml.includes(`/v/${ep}<`));
  }
  const plain = await get('/sitemap.xml', {});
  check('bez bindinga (fail-open): svi kanali', ['povuceni-kanal', 'obrisani-kanal', 'kanal-c', 'kanal-n'].every((c) => plain.html.includes(`/c/${c}<`)));
}

// ── 6. Cast receiver ─────────────────────────────────────────────────────────
section('Cast receiver: vrata postavki (odluka 110)');
{
  const opts = { fetch: globalThis.fetch, siteOrigin: 'https://domovina.ai', cdnFallback: CDN, now: 0 };
  const media = (id, extra = {}) => ({ contentId: `${CDN}/data/${id}/video_h264.mp4`, customData: { v: 1, videoId: id }, ...extra });
  const d = async (m) => gate.decide(m, opts);
  check('povučen → odbijen', JSON.stringify(await d(media('epWithdrwn1'))) === '{"allowed":false,"reason":"withdrawn"}');
  check('obrisan → odbijen', (await d(media('epDeleted01'))).reason === 'deleted');
  check('cdn_playback off → odbijen', JSON.stringify(await d(media('epCustom001'))) === '{"allowed":false,"reason":"cdn_playback"}');
  check('article_summary off → pušta', (await d(media('epNoAi00001'))).allowed === true);
  check('kanal bez postavki → pušta', JSON.stringify(await d(media('epNormal001'))) === '{"allowed":true,"reason":"active"}');
  check('ID iz contentId bez customData', (await d({ contentId: `${CDN}/data/epWithdrwn1/audio.mp3` })).allowed === false);
  check('bez ID-a → pušta', (await d({ contentId: 'https://example.com/x.mp4' })).reason === 'no_video_id');
  const failing = { ...opts, fetch: async () => { throw new Error('mreža'); } };
  check('mrežna greška → pušta (fail-open)', (await gate.decide(media('epWithdrwn1'), failing)).allowed === true);
  const urls = [];
  await gate.decide(media('epNormal001'), { ...opts, now: 120 * 60000, fetch: async (u) => { urls.push(u); return globalThis.fetch(u); } });
  check('settings s ?t=<minuta>', urls.includes('https://domovina.ai/api/katalog/v1/settings?t=120'), urls.join(' '));
  const html = await readFile(path.join(root, 'web/cast-receiver.html'), 'utf8');
  check('receiver učitava gate skriptu', html.includes('<script src="/cast-receiver-gate.js'));
}

console.log(`\nUkupno: ${passed}/${passed + failed} prošlo`);
process.exit(failed ? 1 : 0);

/**
 * Katalog S10: OG za Tier 2 kanal (/c/<slug>) u web/_worker.js, s LAŽNIM
 * bindingom KATALOG. Bez mreže: worker se importa u Node, `env.ASSETS` vraća
 * web/index.html, `globalThis.fetch` glumi CDN listinge, `env.KATALOG.fetch`
 * glumi katalog. Statični put (bez bindinga) na pravom serveru provjerava
 * scripts/test-social-tags.mjs; ovdje je sve što bez bindinga nije vidljivo.
 *
 * Korištenje:  node scripts/test-worker-katalog-kanal.mjs
 */
import { readFile } from 'node:fs/promises';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const INDEX_HTML = await readFile(path.join(root, 'web/index.html'), 'utf8');
const worker = (await import(pathToFileURL(path.join(root, 'web/_worker.js')).href)).default;

const CATALOG = 'https://domovina.ai/api/katalog/v1';
// Tier 1 listing koji „postoji" na CDN-u; sve ostalo je 404.
const TIER1_ID = 'radio_mreznica';
const TIER1_LISTING = {
  name: 'Radio Mrežnica',
  video_count: 2,
  avatar_square: 'https://cdn.domovina.ai/channels/images/radio_mreznica/avatar_square.jpg',
  videos: [{ id: 'abcdefghijk', title: 'Prva', date: '2026-11-05', duration_seconds: 600 }],
};

globalThis.fetch = async (input) => {
  const u = String(typeof input === 'string' ? input : input.url);
  if (u.startsWith(`https://cdn.domovina.ai/channels/data/${TIER1_ID}.json`)) {
    return new Response(JSON.stringify(TIER1_LISTING), { status: 200 });
  }
  return new Response('not found', { status: 404 });
};

const assets = { fetch: async () => new Response(INDEX_HTML, { status: 200 }) };

const card = (over = {}) => ({
  version: '1',
  catalog: '8',
  item: {
    slug: 'tribina', name: 'Tribina', tier: 2, lang: null, avatar: null,
    youtube_channel_id: 'UCjTiZ9ebMJumhPMsciuevxg', processed_count: 6,
    latest_published_date: '2026-11-05', unregistered: false, ...over,
  },
  meta: { rows_read: 4 },
});

/** Lažni binding: bilježi URL-ove; `handler(url)` vraća Response ili baca. */
function fakeKatalog(handler) {
  const calls = [];
  return {
    calls,
    fetch: async (req) => {
      calls.push(req.url);
      return handler(req.url);
    },
  };
}
const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { 'Content-Type': 'application/json' },
});

async function get(p, env) {
  const res = await worker.fetch(new Request(`https://domovina.ai${p}`), { ASSETS: assets, ...env });
  return { res, html: await res.text() };
}

const meta = (html, attr, val) => {
  const m = html.match(new RegExp(`<meta[^>]+${attr}=["']${val}["'][^>]+content=["']([^"']*)["']`, 'i'));
  return m ? m[1] : null;
};
const canonical = (html) => (html.match(/<link[^>]+rel=["']canonical["'][^>]+href=["']([^"']*)["']/i) || [])[1] ?? null;
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

// Referenca: današnje ponašanje (bez bindinga) za nepostojeći listing.
const plain = await get('/c/tribina', {});

section('bez bindinga: plain SPA kao prije S10');
check('200', plain.res.status === 200, String(plain.res.status));
check('no-store', plain.res.headers.get('cache-control') === 'no-store');
check('bez X-Robots-Tag', !plain.res.headers.get('x-robots-tag'));
check('tijelo = index.html', plain.html === INDEX_HTML);

section('Tier 1: listing postoji → katalog se NE zove, izlaz bajt-identičan');
{
  const k = fakeKatalog(() => json(card()));
  const a = await get('/c/radio-mreznica', { KATALOG: k });
  const b = await get('/c/radio-mreznica', {});
  check('KATALOG nije pozvan', k.calls.length === 0, k.calls.join(' '));
  check('isto tijelo s bindingom i bez', a.html === b.html);
  check('isti Cache-Control', a.res.headers.get('cache-control') === b.res.headers.get('cache-control'));
  check('Tier 1 OG naslov', meta(a.html, 'property', 'og:title') === 'Radio Mrežnica — AI obrada podcasta');
}

section('Tier 2: katalog nađe kanal (bez avatara, 6 epizoda)');
{
  const k = fakeKatalog(() => json(card()));
  const { res, html } = await get('/c/tribina', { KATALOG: k });
  const desc = meta(html, 'property', 'og:description') || '';
  check('jedan poziv na /channels/tribina', k.calls.length === 1 && k.calls[0] === `${CATALOG}/channels/tribina`, k.calls.join(' '));
  check('200', res.status === 200);
  check('Cache-Control 1 h', res.headers.get('cache-control') === 'public, max-age=3600, s-maxage=3600', res.headers.get('cache-control'));
  check('bez X-Robots-Tag', !res.headers.get('x-robots-tag'));
  check('<title>', /<title>Tribina — AI obrada podcasta – DOMOVINA\.ai<\/title>/.test(html));
  check('og:title', meta(html, 'property', 'og:title') === 'Tribina — AI obrada podcasta');
  check('og:description', desc === 'AI-obrađene epizode kanala Tribina: 6 epizoda, zadnja objavljena 5. studenoga 2026. Sažetci, transkripti i poglavlja na DOMOVINA.ai.', desc);
  check('meta description = og', meta(html, 'name', 'description') === desc);
  check('canonical', canonical(html) === 'https://domovina.ai/c/tribina');
  check('og:url', meta(html, 'property', 'og:url') === 'https://domovina.ai/c/tribina');
  check('og:image = og-image.png', meta(html, 'property', 'og:image') === 'https://domovina.ai/og-image.png');
  check('og:image:width 1200', meta(html, 'property', 'og:image:width') === '1200');
  check('twitter:card large', meta(html, 'name', 'twitter:card') === 'summary_large_image');
  check('twitter:data1 = 6', meta(html, 'name', 'twitter:data1') === '6');
  check('og:title jednom', (html.match(/property="og:title"/g) || []).length === 1);
  check('canonical jednom', (html.match(/rel="canonical"/g) || []).length === 1);
  const ld = ldJson(html);
  check('JSON-LD PodcastSeries', ld && ld['@type'] === 'PodcastSeries' && ld.url === 'https://domovina.ai/c/tribina');
  check('JSON-LD sameAs YouTube', ld && ld.sameAs === 'https://www.youtube.com/channel/UCjTiZ9ebMJumhPMsciuevxg');
  check('JSON-LD inLanguage hr (lang null)', ld && ld.inLanguage === 'hr');
  check('jedan JSON-LD blok', (html.match(/application\/ld\+json/g) || []).length === 1);
}

section('Tier 2: avatar, množina, bez datuma');
{
  const avatar = 'https://cdn.domovina.ai/channels/images/sbs/avatar.jpg';
  const k = fakeKatalog(() => json(card({ name: 'SBS Croatian', slug: 'sbs-croatian', avatar, processed_count: 3, latest_published_date: null, lang: 'en' })));
  const { html } = await get('/c/sbs-croatian', { KATALOG: k });
  const desc = meta(html, 'property', 'og:description') || '';
  check('og:image = avatar', meta(html, 'property', 'og:image') === avatar);
  check('twitter:card summary', meta(html, 'name', 'twitter:card') === 'summary');
  check('bez og:image:width uz avatar', meta(html, 'property', 'og:image:width') === null);
  check('„3 epizode." bez datuma', desc === 'AI-obrađene epizode kanala SBS Croatian: 3 epizode. Sažetci, transkripti i poglavlja na DOMOVINA.ai.', desc);
  check('JSON-LD inLanguage en', ldJson(html)?.inLanguage === 'en');

  const k1 = fakeKatalog(() => json(card({ processed_count: 1, latest_published_date: '2026-01-31' })));
  const one = await get('/c/tribina', { KATALOG: k1 });
  check('„1 epizoda, … 31. siječnja 2026."', (meta(one.html, 'property', 'og:description') || '').startsWith('AI-obrađene epizode kanala Tribina: 1 epizoda, zadnja objavljena 31. siječnja 2026. '));

  const kBad = fakeKatalog(() => json(card({ avatar: 'javascript:alert(1)', youtube_channel_id: 'nije-uc' })));
  const bad = await get('/c/tribina', { KATALOG: kBad });
  check('ne-https avatar odbačen', meta(bad.html, 'property', 'og:image') === 'https://domovina.ai/og-image.png');
  check('neispravan YT id bez sameAs', ldJson(bad.html) && !('sameAs' in ldJson(bad.html)));
}

section('Tier 2: escape imena');
{
  const k = fakeKatalog(() => json(card({ name: 'A "B" <script>x</script> & C' })));
  const { html } = await get('/c/tribina', { KATALOG: k });
  check('nema sirovog <script>x', !html.includes('<script>x</script>'));
  check('og:title escapan', meta(html, 'property', 'og:title') === 'A &quot;B&quot; &lt;script&gt;x&lt;/script&gt; &amp; C — AI obrada podcasta');
  check('JSON-LD čitljiv', ldJson(html)?.name === 'A "B" <script>x</script> & C');
}

section('Tier 2: 0 obrađenih epizoda → tagovi + noindex');
{
  const k = fakeKatalog(() => json(card({ processed_count: 0, latest_published_date: null })));
  const { res, html } = await get('/c/tribina', { KATALOG: k });
  check('X-Robots-Tag noindex', res.headers.get('x-robots-tag') === 'noindex');
  check('opis bez broja', meta(html, 'property', 'og:description') === 'Kanal Tribina na DOMOVINA.ai: AI sažetci, transkripti i poglavlja epizoda podcasta.');
  check('bez twitter:data1', meta(html, 'name', 'twitter:data1') === null);
}

section('katalog 404 channel_not_found → SPA + noindex');
{
  const k = fakeKatalog(() => json({ ok: false, error: 'channel_not_found' }, 404));
  const { res, html } = await get('/c/nema-ga', { KATALOG: k });
  check('200 SPA', res.status === 200 && html === INDEX_HTML);
  check('no-store', res.headers.get('cache-control') === 'no-store');
  check('X-Robots-Tag noindex', res.headers.get('x-robots-tag') === 'noindex');
}

section('degradacija: drugi 404, 5xx, nečitljivo, baca, timeout → točno kao bez bindinga');
for (const [label, handler, slow] of [
  ['404 bez channel_not_found', () => json({ error: 'not_found' }, 404)],
  ['500', () => json({ ok: false }, 500)],
  ['HTML umjesto JSON-a', () => new Response('<!doctype html>', { status: 200 })],
  ['krivi version', () => json({ ...card(), version: '2' })],
  ['bez imena', () => json(card({ name: '  ' }))],
  ['binding baca', () => { throw new Error('boom'); }],
  ['timeout (2 s)', () => new Promise((r) => setTimeout(() => r(json(card())), 2000)), true],
]) {
  const k = fakeKatalog(handler);
  const t0 = Date.now();
  const { res, html } = await get('/c/tribina', { KATALOG: k });
  const ms = Date.now() - t0;
  const same = res.status === 200 && html === plain.html
    && res.headers.get('cache-control') === 'no-store' && !res.headers.get('x-robots-tag');
  check(`${label}: plain SPA`, same, `${res.status} ${res.headers.get('cache-control')} ${res.headers.get('x-robots-tag')}`);
  if (slow) check(`${label}: odustaje do ~800 ms`, ms < 1500, `${ms} ms`);
}

section('podrute i brendovi ne zovu katalog');
{
  const k = fakeKatalog(() => json(card()));
  await get('/c/tribina/oglasi', { KATALOG: k });
  await get('/c/tribina/doniraj', { KATALOG: k });
  await get('/c/tribina/claim', { KATALOG: k });
  check('/oglasi, /doniraj, /claim: 0 poziva', k.calls.length === 0, k.calls.join(' '));
  const kb = fakeKatalog(() => json(card()));
  const r = await get('/c/tribina', { KATALOG: kb, SITE: 'https://podcasterium.com' });
  check('brend sa SITE bez CATALOG_API: 0 poziva', kb.calls.length === 0);
  check('brend sa SITE bez CATALOG_API: plain SPA', r.html === INDEX_HTML && r.res.headers.get('cache-control') === 'no-store');
  const kc = fakeKatalog(() => json(card()));
  await get('/vijesti/nesto', { KATALOG: kc });
  check('/vijesti: 0 poziva', kc.calls.length === 0);
}

section('/dani/ kroz zajednički catalogGet i dalje radi');
{
  const k = fakeKatalog(() => json({
    version: '1', catalog: '8', next: null,
    items: [
      { id: 'abcdefghijk', title: 'Jedan', channel: { name: 'Tribina' } },
      { id: 'bcdefghijkl', title: 'Dva', channel: { name: 'SBS Croatian' } },
    ],
  }));
  const { html } = await get('/dani/2026-11-04', { KATALOG: k });
  check('poziv na /days/2026-11-04?limit=100', k.calls[0] === `${CATALOG}/days/2026-11-04?limit=100`, k.calls.join(' '));
  check('opis s brojem i kanalima', (meta(html, 'property', 'og:description') || '').startsWith('2 epizode objavljene 4. studenoga 2026. — kanali: Tribina, SBS Croatian.'), meta(html, 'property', 'og:description'));
  const k5 = fakeKatalog(() => json({ error: 'x' }, 500));
  const d5 = await get('/dani/2026-11-04', { KATALOG: k5 });
  check('/dani/ uz 500: statični opis', (meta(d5.html, 'property', 'og:description') || '').startsWith('Sve epizode objavljene 4. studenoga 2026.'));
}

console.log(`\nUkupno: ${passed}/${passed + failed} prošlo`);
process.exit(failed ? 1 : 0);

// SEO portala nad seedom (S7, odluke 700–705): JSON-LD, canonical, OG, sitemap,
// news sitemap i RSS. XML se čita kroz preglednik (DOMParser), bez dodatnih paketa.
import type { Page } from '@playwright/test';
import { expect, resetSeed, test, type SeedArticle, type SeedState } from './fixtures.js';

let seed: Record<SeedState, SeedArticle>;

test.beforeAll(async () => {
  seed = await resetSeed();
});

const SITE = 'https://domovina.ai';

/** Dohvati XML rutu i parsiraj je u pregledniku; vraća <loc> i grešku parsera. */
async function xml(page: Page, path: string, select: string) {
  const res = await page.request.get(path);
  expect(res.status(), path).toBe(200);
  const text = await res.text();
  const parsed = await page.evaluate(
    ({ text, select }) => {
      const doc = new DOMParser().parseFromString(text, 'application/xml');
      return {
        error: doc.getElementsByTagName('parsererror').length > 0,
        root: doc.documentElement.nodeName,
        values: [...doc.getElementsByTagNameNS('*', select)].map((n) => n.textContent),
      };
    },
    { text, select },
  );
  return { ...parsed, contentType: res.headers()['content-type'] ?? '', cache: res.headers()['cache-control'] ?? '' };
}

test.describe('stranica članka', () => {
  test('NewsArticle JSON-LD je prisutan, parsira se i opisuje članak', async ({ page }) => {
    await page.goto(`/vijesti/${seed.corrected.slug}`);
    const raw = await page.locator('script[type="application/ld+json"]').textContent();
    const ld = JSON.parse(raw ?? '') as Record<string, unknown> & {
      author: { '@type': string; name: string };
      publisher: { name: string; logo: { url: string } };
      isBasedOn: { url: string };
      correction?: unknown[];
    };
    const url = `${SITE}/vijesti/${seed.corrected.slug}`;
    expect(ld['@type']).toBe('NewsArticle');
    expect(ld.headline).toBe(await page.getByTestId('article-title').textContent());
    expect(ld.url).toBe(url);
    expect(ld.author['@type']).toBe('Organization');
    expect(ld.publisher.name).toBe('DOMOVINA.ai');
    expect(ld.publisher.logo.url).toBe(`${SITE}/icons/Icon-512.png`);
    expect(ld.isBasedOn.url).toBe(`${SITE}/v/${seed.corrected.videoId}`);
    expect(Date.parse(String(ld.dateModified))).toBeGreaterThanOrEqual(Date.parse(String(ld.datePublished)));
    expect(ld.correction).toHaveLength(1);

    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', url);
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', /max-image-preview:large/);
    await expect(page.locator('meta[property="og:type"]')).toHaveAttribute('content', 'article');
    await expect(page.locator('meta[property="og:url"]')).toHaveAttribute('content', url);
    // Lažni CDN nema og-share.jpg: zamjenska slika aplikacije, nikad prazno.
    await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', `${SITE}/og-image.png`);
    await expect(page.locator('meta[name="twitter:card"]')).toHaveAttribute('content', 'summary_large_image');
  });

  test('povučen članak nema JSON-LD ni canonical', async ({ page }) => {
    await page.goto(`/vijesti/${seed.retracted.slug}`);
    await expect(page.locator('script[type="application/ld+json"]')).toHaveCount(0);
    await expect(page.locator('link[rel="canonical"]')).toHaveCount(0);
    await expect(page.locator('meta[name="robots"]')).toHaveAttribute('content', /noindex/);
  });

  test('naslovnica i kategorija imaju canonical i RSS poveznicu', async ({ page }) => {
    await page.goto('/vijesti/');
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', `${SITE}/vijesti/`);
    await expect(page.locator('link[rel="alternate"][type="application/rss+xml"]')).toHaveAttribute(
      'href',
      `${SITE}/vijesti/rss.xml`,
    );
    await page.goto('/vijesti/kategorija/vjera');
    await expect(page.locator('link[rel="canonical"]')).toHaveAttribute('href', `${SITE}/vijesti/kategorija/vjera`);
  });
});

test.describe('sitemap, news sitemap, RSS', () => {
  test('sitemap: objavljeni članci, bez povučenog i nacrta', async ({ page }) => {
    const s = await xml(page, '/vijesti/sitemap.xml', 'loc');
    expect(s.error).toBe(false);
    expect(s.root).toBe('urlset');
    expect(s.contentType).toContain('application/xml');
    expect(s.cache).toContain('s-maxage');
    expect(s.values).toContain(`${SITE}/vijesti/`);
    expect(s.values).toContain(`${SITE}/vijesti/impresum`);
    expect(s.values).toContain(`${SITE}/vijesti/${seed.published.slug}`);
    expect(s.values).toContain(`${SITE}/vijesti/${seed.corrected.slug}`);
    for (const st of ['retracted', 'review', 'approved'] as const) {
      expect(s.values).not.toContain(`${SITE}/vijesti/${seed[st].slug}`);
    }
  });

  test('news sitemap: svježi članci s naslovom, bez povučenog', async ({ page }) => {
    const s = await xml(page, '/vijesti/news-sitemap.xml', 'loc');
    expect(s.error).toBe(false);
    expect(s.values.sort()).toEqual(
      [`${SITE}/vijesti/${seed.published.slug}`, `${SITE}/vijesti/${seed.corrected.slug}`].sort(),
    );
    const t = await xml(page, '/vijesti/news-sitemap.xml', 'title');
    expect(t.values).toContain(seed.published.title);
  });

  test('RSS: ispravan XML, stavke vode na članke, bez povučenog', async ({ page }) => {
    const s = await xml(page, '/vijesti/rss.xml', 'link');
    expect(s.error).toBe(false);
    expect(s.root).toBe('rss');
    expect(s.contentType).toContain('application/rss+xml');
    expect(s.values).toContain(`${SITE}/vijesti/${seed.published.slug}`);
    expect(s.values).not.toContain(`${SITE}/vijesti/${seed.retracted.slug}`);
  });
});

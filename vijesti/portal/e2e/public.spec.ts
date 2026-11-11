// Javne stranice portala nad seedom (odluke 601–605, 608–610).
import { expect, resetSeed, test, type SeedArticle, type SeedState } from './fixtures.js';

let seed: Record<SeedState, SeedArticle>;

test.beforeAll(async () => {
  seed = await resetSeed();
});

/** Nema horizontalnog scrolla: sadržaj nije širi od viewporta. */
async function noHorizontalScroll(page: import('@playwright/test').Page) {
  const { scroll, client } = await page.evaluate(() => ({
    scroll: document.documentElement.scrollWidth,
    client: document.documentElement.clientWidth,
  }));
  expect(scroll, 'scrollWidth ≤ clientWidth').toBeLessThanOrEqual(client);
}

test.describe('naslovnica', () => {
  test('istaknuti članak, kategorije i kartice vode na članak', async ({ page }) => {
    const res = await page.goto('/vijesti/');
    expect(res?.status()).toBe(200);
    expect(res?.headers()['cache-control']).toContain('s-maxage=300');
    const lead = page.getByTestId('lead-story');
    await expect(lead).toBeVisible();
    const slugs = [seed.published.slug, seed.corrected.slug];
    expect(slugs).toContain(await lead.getAttribute('data-slug'));
    await expect(page.getByTestId('category-section').first()).toBeVisible();
    // Povučen, u pregledu i odobren (neobjavljen) članak nisu na popisu.
    const all = await page.locator('[data-slug]').evaluateAll((els) => els.map((e) => e.getAttribute('data-slug')));
    for (const s of [seed.retracted.slug, seed.review.slug, seed.approved.slug]) expect(all).not.toContain(s);

    const card = page.getByTestId('article-card').first();
    const slug = await card.getAttribute('data-slug');
    await card.locator('h3 a').click();
    await expect(page).toHaveURL(new RegExp(`/vijesti/${slug ?? ''}$`));
    await expect(page.getByTestId('article-title')).toBeVisible();
  });

  test('stranica kategorije prikazuje kartice te kategorije', async ({ page }) => {
    await page.goto('/vijesti/');
    const section = page.getByTestId('category-section').first();
    const category = await section.getAttribute('data-category');
    await section.locator('h2 a').click();
    await expect(page.getByTestId('category-title')).toBeVisible();
    await expect(page).toHaveURL(new RegExp(`/vijesti/kategorija/${category ?? ''}$`));
    await expect(page.getByTestId('article-card').first()).toBeVisible();
  });
});

test.describe('članak', () => {
  test('naslov, uvod, citati, isječak, izvor, AI oznaka; bez JS-a', async ({ page }) => {
    const scripts: string[] = [];
    const failed: string[] = [];
    page.on('response', (r) => {
      if (r.status() >= 400) failed.push(`${String(r.status())} ${r.url()}`);
    });
    page.on('request', (r) => {
      if (r.resourceType() === 'script') scripts.push(r.url());
    });
    const res = await page.goto(`/vijesti/${seed.published.slug}`);
    expect(res?.status()).toBe(200);
    expect(res?.headers()['cache-control']).toContain('s-maxage=600');
    await expect(page.getByTestId('article-title')).toHaveText(seed.published.title);
    await expect(page.getByTestId('article-lead')).not.toBeEmpty();
    await expect(page).toHaveTitle(new RegExp(seed.published.title.slice(0, 20).replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));

    const quotes = page.getByTestId('quote');
    expect(await quotes.count()).toBeGreaterThan(0);
    const q = quotes.first();
    await expect(q.getByTestId('quote-speaker')).not.toBeEmpty();
    await expect(q.getByTestId('quote-time')).toHaveText(/^\d{1,2}:\d{2}(:\d{2})?$/);
    const timeHref = (await q.getByTestId('quote-time').getAttribute('href')) ?? '';
    expect(timeHref).toMatch(new RegExp(`^https://domovina\\.ai/v/${seed.published.videoId}/t/\\d+$`));

    const audio = q.getByTestId('quote-audio');
    await expect(audio).toHaveAttribute('preload', 'none');
    const src = (await audio.getAttribute('src')) ?? '';
    expect(src).toMatch(
      new RegExp(`^http://127\\.0\\.0\\.1:8790/cdn/data/${seed.published.videoId}/(audio\\.mp3|video_h264\\.mp4)#t=\\d+(\\.\\d+)?,\\d+(\\.\\d+)?$`),
    );
    const [, from, to] = /#t=([\d.]+),([\d.]+)$/.exec(src) ?? [];
    expect(Number(to)).toBeGreaterThan(Number(from));

    // „Poslušaj cijeli razgovor” vodi na prvi citat u aplikaciji.
    const listen = page.getByTestId('listen-full');
    await expect(listen).toHaveText('Poslušaj cijeli razgovor');
    const firstSec = /\/t\/(\d+)$/.exec(timeHref)?.[1];
    await expect(listen).toHaveAttribute('href', `https://domovina.ai/v/${seed.published.videoId}/t/${firstSec ?? ''}`);

    const source = page.getByTestId('episode-source');
    await expect(source.getByTestId('episode-title')).not.toBeEmpty();
    await expect(source.getByTestId('episode-channel')).not.toBeEmpty();
    await expect(source.getByTestId('episode-date')).toHaveAttribute('datetime', /^\d{4}-\d{2}-\d{2}$/);
    await expect(page.getByTestId('ai-label')).toContainText('umjetna inteligencija');
    await expect(page.getByTestId('corrections')).toHaveCount(0);
    // Indeksira se (odluka 700): robots bez noindex, uz veliki pregled slike za Discover.
    await expect(page.locator('meta[name=robots]')).toHaveAttribute('content', 'index, follow, max-image-preview:large');

    // Ikona je pod /vijesti (inače preglednik traži /favicon.ico s korijena).
    await expect(page.locator('link[rel=icon]')).toHaveAttribute('href', '/vijesti/favicon.png');
    expect((await page.request.get('/vijesti/favicon.png')).status()).toBe(200);
    expect(failed).toEqual([]);

    // Javna stranica nema JS bundle (ni <script> ni zahtjev za skriptom).
    expect(await page.locator('script:not([type="application/ld+json"])').count()).toBe(0);
    expect(scripts).toEqual([]);
  });

  test('isječak se može pustiti (medij dolazi s lažnog CDN-a)', async ({ page }) => {
    await page.goto(`/vijesti/${seed.published.slug}`);
    const audio = page.getByTestId('quote-audio').first();
    const ok = await audio.evaluate(
      (el: HTMLAudioElement) =>
        new Promise<boolean>((resolve) => {
          el.addEventListener('loadedmetadata', () => {
            resolve(true);
          });
          el.addEventListener('error', () => {
            resolve(false);
          });
          el.load();
        }),
    );
    expect(ok).toBe(true);
  });

  test('ispravljen članak pokazuje dnevnik ispravaka', async ({ page }) => {
    await page.goto(`/vijesti/${seed.corrected.slug}`);
    await expect(page.getByTestId('article')).toHaveAttribute('data-status', 'corrected');
    const corrections = page.getByTestId('corrections');
    await expect(corrections).toBeVisible();
    await expect(corrections.getByTestId('correction')).toHaveCount(1);
    await expect(corrections).toContainText('Ispravljen je opis teme u uvodu');
    await page.getByRole('link', { name: 'ispravljeno' }).click();
    await expect(page).toHaveURL(/#ispravci$/);
  });

  test('povučen članak: obavijest i razlog, bez teksta, noindex', async ({ page }) => {
    const res = await page.goto(`/vijesti/${seed.retracted.slug}`);
    expect(res?.status()).toBe(200);
    await expect(page.getByTestId('article-title')).toHaveText('Članak je povučen');
    await expect(page.getByTestId('retraction-notice')).toBeVisible();
    await expect(page.getByTestId('retraction-reason')).not.toBeEmpty();
    await expect(page.getByTestId('article-body')).toHaveCount(0);
    await expect(page.getByTestId('quote')).toHaveCount(0);
    await expect(page.locator('body')).not.toContainText(seed.retracted.title);
    await expect(page.locator('meta[name=robots]')).toHaveAttribute('content', /noindex/);
  });

  test('nepostojeći slug je 404', async ({ page }) => {
    const res = await page.goto('/vijesti/ovaj-clanak-ne-postoji-123');
    expect(res?.status()).toBe(404);
    await expect(page.getByTestId('not-found')).toBeVisible();
    await expect(page.locator('meta[name=robots]')).toHaveAttribute('content', /noindex/);
  });

  test('članak u pregledu i odobren (neobjavljen) nisu javni', async ({ page }) => {
    for (const a of [seed.review, seed.approved]) {
      const res = await page.goto(`/vijesti/${a.slug}`);
      expect(res?.status(), a.state).toBe(404);
      await expect(page.locator('body')).not.toContainText(a.title);
    }
  });
});

test.describe('izgled', () => {
  test('tamna tema prati prefers-color-scheme', async ({ page }) => {
    await page.emulateMedia({ colorScheme: 'light' });
    await page.goto(`/vijesti/${seed.published.slug}`);
    const light = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    await page.emulateMedia({ colorScheme: 'dark' });
    const dark = await page.evaluate(() => getComputedStyle(document.body).backgroundColor);
    expect(light).toBe('rgb(250, 247, 242)');
    expect(dark).toBe('rgb(17, 19, 24)');
    const color = await page.evaluate(() => getComputedStyle(document.querySelector('h1') ?? document.body).color);
    expect(color).not.toBe('rgb(0, 0, 0)');
  });

  test('mobilna širina 390 px: bez horizontalnog scrolla', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 });
    for (const path of ['/vijesti/', `/vijesti/${seed.published.slug}`, `/vijesti/${seed.corrected.slug}`, `/vijesti/${seed.retracted.slug}`]) {
      await page.goto(path);
      await noHorizontalScroll(page);
    }
  });
});

test.describe('O istoj temi u drugim podcastima', () => {
  test('RAG veze vode u aplikaciju na sekundu teme; bez veza bloka nema', async ({ page }) => {
    await page.goto(`/vijesti/${seed.published.slug}`);
    const block = page.getByTestId('related');
    await expect(block).toBeVisible();
    await expect(block.getByRole('heading')).toHaveText('O istoj temi u drugim podcastima');
    const links = block.getByTestId('related-link');
    await expect(links).toHaveCount(2);
    // Tema s vremenom: tekst je tema, poveznica nosi /t/<sekunda>, uz naslov epizode i datum.
    await expect(links.nth(0)).toHaveText('Obitelj kao temelj zajednice');
    await expect(links.nth(0)).toHaveAttribute('href', /\/v\/pIx_7N-6HJ4\/t\/754$/);
    await expect(block.locator('li').nth(0)).toContainText('Mreže riječi: obitelj i zajednica');
    await expect(block.locator('li').nth(0).locator('time')).toHaveAttribute('datetime', '2026-08-14');
    // Sažetak cijele epizode (t = 0, bez teme): tekst je naslov epizode, bez /t/.
    await expect(links.nth(1)).toHaveText('Catholic Futurist: tehnologija i vjera');
    await expect(links.nth(1)).toHaveAttribute('href', /\/v\/x3w2BVZJ9vQ$/);

    // Ispravljen članak u seedu nema `related`: blok se ne crta prazan.
    await page.goto(`/vijesti/${seed.corrected.slug}`);
    await expect(page.getByTestId('article-body')).toBeVisible();
    await expect(page.getByTestId('related')).toHaveCount(0);
  });
});

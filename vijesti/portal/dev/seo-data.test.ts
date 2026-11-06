// Podaci za sitemap i news sitemap nad lokalnim seedom (odluke 703, 704):
// povučen članak i nacrti nikad nisu u popisu, lastmod ispravljenog je ispravak.
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { articlesSince, sitemapArticles } from '../src/lib/public-data.js';
import { createRest } from '../src/lib/rest.js';
import { LOCAL_ANON_KEY } from './ids.js';
import { createRestShim, type RestShim } from './rest-shim.js';
import { seededDb, type SeededArticle } from './seed.js';
import { fetchViaShim } from './via-shim.js';

describe('SEO podaci nad seedom', () => {
  let shim: RestShim;
  let articles: SeededArticle[];
  const rest = () =>
    createRest({ url: 'http://127.0.0.1:8790', anonKey: LOCAL_ANON_KEY, fetch: fetchViaShim(shim) });
  const slugOf = (state: SeededArticle['state']) => articles.find((a) => a.state === state)?.slug;

  beforeAll(async () => {
    const s = await seededDb();
    articles = s.articles;
    shim = createRestShim({ db: s.db, reset: async () => (await seededDb()).db });
  });
  afterAll(async () => {
    await shim.db().close();
  });

  it('sitemap: objavljen i ispravljen, bez povučenog i nacrta; lastmod ispravljenog je ispravak', async () => {
    const list = await sitemapArticles(rest(), 100);
    expect(list.map((a) => a.slug).sort()).toEqual([slugOf('published'), slugOf('corrected')].sort());
    const fixed = list.find((a) => a.slug === slugOf('corrected'));
    const r = await shim
      .db()
      .query<{ created_at: Date }>(
        `SELECT c.created_at FROM vijesti.corrections c JOIN vijesti.articles a ON a.id = c.article_id WHERE a.slug = $1`,
        [slugOf('corrected')],
      );
    expect(fixed?.lastmod).toBe(r.rows[0]?.created_at.toISOString());
    expect(new Date(fixed?.lastmod ?? 0).getTime()).toBeGreaterThanOrEqual(new Date(fixed?.publishedAt ?? 0).getTime());
    const plain = list.find((a) => a.slug === slugOf('published'));
    expect(plain?.lastmod).toBe(new Date(plain?.publishedAt ?? 0).toISOString());
    expect(await sitemapArticles(rest(), 1)).toHaveLength(1);
  });

  it('news: članci objavljeni od zadanog trenutka, s naslovom; povučen nikad', async () => {
    const since = new Date(Date.now() - 48 * 3600 * 1000).toISOString();
    const recent = await articlesSince(rest(), since, 1000);
    expect(recent.map((c) => c.slug).sort()).toEqual([slugOf('published'), slugOf('corrected')].sort());
    expect(recent.every((c) => c.title.length > 0)).toBe(true);
    const future = new Date(Date.now() + 3600 * 1000).toISOString();
    expect(await articlesSince(rest(), future, 1000)).toEqual([]);
  });
});

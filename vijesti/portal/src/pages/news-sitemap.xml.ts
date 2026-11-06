// /vijesti/news-sitemap.xml: Google News sitemap, članci objavljeni u zadnjih
// 48 h (datum prve objave, ne ispravka); povučeni nikad (odluka 704).
import type { APIRoute } from 'astro';
import { articlesSince } from '../lib/public-data.js';
import { portalConfig, publicRest } from '../lib/runtime.js';
import { canonicalUrl, inNewsWindow, NEWS_SITEMAP_MAX_URLS, NEWS_WINDOW_MS, newsSitemapXml } from '../lib/seo.js';
import { xmlError, xmlResponse } from '../lib/xml-response.js';

export const GET: APIRoute = async () => {
  const cfg = portalConfig();
  const base = import.meta.env.BASE_URL;
  const now = new Date();
  try {
    const since = new Date(now.getTime() - NEWS_WINDOW_MS).toISOString();
    const cards = inNewsWindow(await articlesSince(publicRest(cfg), since, NEWS_SITEMAP_MAX_URLS), now);
    const entries = cards.flatMap((c) =>
      c.publishedAt ? [{ loc: canonicalUrl(cfg.siteBase, base, c.slug), title: c.title, publishedAt: c.publishedAt }] : [],
    );
    return xmlResponse(newsSitemapXml(entries), 'application/xml');
  } catch (e) {
    return xmlError('news sitemap', e);
  }
};

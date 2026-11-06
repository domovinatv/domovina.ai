// /vijesti/rss.xml: RSS 2.0, zadnjih 30 objavljenih (i ispravljenih) članaka
// s leadom kao opisom; povučeni nikad (odluka 705).
import type { APIRoute } from 'astro';
import { latestArticles } from '../lib/public-data.js';
import { portalConfig, publicRest } from '../lib/runtime.js';
import { canonicalUrl, RSS_ITEMS, rssXml } from '../lib/seo.js';
import { xmlError, xmlResponse } from '../lib/xml-response.js';

export const GET: APIRoute = async () => {
  const cfg = portalConfig();
  const base = import.meta.env.BASE_URL;
  try {
    const cards = await latestArticles(publicRest(cfg), RSS_ITEMS);
    const xml = rssXml({
      siteUrl: canonicalUrl(cfg.siteBase, base),
      selfUrl: canonicalUrl(cfg.siteBase, base, 'rss.xml'),
      now: new Date(),
      items: cards.map((c) => ({
        link: canonicalUrl(cfg.siteBase, base, c.slug),
        title: c.title,
        description: c.lead,
        publishedAt: c.publishedAt,
        category: c.category,
      })),
    });
    return xmlResponse(xml, 'application/rss+xml');
  } catch (e) {
    return xmlError('RSS', e);
  }
};

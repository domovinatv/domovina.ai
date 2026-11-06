// /vijesti/sitemap.xml: naslovnica, kategorije, pravne stranice i svi objavljeni
// (i ispravljeni) članci; povučeni nikad (odluka 703).
import type { APIRoute } from 'astro';
import { CATEGORY_SLUGS } from '../lib/categories.js';
import { sitemapArticles } from '../lib/public-data.js';
import { portalConfig, publicRest } from '../lib/runtime.js';
import { canonicalUrl, LEGAL_PAGES, SITEMAP_MAX_URLS, sitemapXml, type SitemapEntry } from '../lib/seo.js';
import { xmlError, xmlResponse } from '../lib/xml-response.js';

export const GET: APIRoute = async () => {
  const cfg = portalConfig();
  const base = import.meta.env.BASE_URL;
  const fixed: SitemapEntry[] = [
    { loc: canonicalUrl(cfg.siteBase, base) },
    ...CATEGORY_SLUGS.map((c) => ({ loc: canonicalUrl(cfg.siteBase, base, 'kategorija', c) })),
    ...LEGAL_PAGES.map((p) => ({ loc: canonicalUrl(cfg.siteBase, base, p.slug) })),
  ];
  try {
    const articles = await sitemapArticles(publicRest(cfg), SITEMAP_MAX_URLS - fixed.length);
    const entries = articles.map((a) => ({ loc: canonicalUrl(cfg.siteBase, base, a.slug), lastmod: a.lastmod }));
    return xmlResponse(sitemapXml([...fixed, ...entries]), 'application/xml');
  } catch (e) {
    return xmlError('sitemap', e);
  }
};

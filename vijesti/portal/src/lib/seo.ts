// SEO portala (S7, odluke 700–707): canonical, OG slika, NewsArticle JSON-LD,
// sitemap, Google News sitemap i RSS. Čiste funkcije bez mreže; podatke daje
// `public-data.ts`, rute ih samo spajaju.
import type { EpisodeMeta } from '../../../engine/write/content.js';
import { categoryLabel } from './categories.js';
import { appEpisodeUrl, portalPath } from './urls.js';

/** Ime publikacije (Google News `news:name`, RSS, `publisher` nije isto: to je DOMOVINA.ai). */
export const PUBLICATION_NAME = 'DOMOVINA.ai Vijesti';
export const PUBLICATION_LANG = 'hr';
export const SITE_DESCRIPTION = 'Vijesti iz hrvatskih podcasta: doslovni citati uz snimku, uz pregled urednika.';
/** Autor svakog članka je redakcija, ne osoba (odluka 701). */
export const AUTHOR_NAME = 'Uredništvo DOMOVINA.ai Vijesti';
/** Google News sitemap: samo članci objavljeni u zadnjih 48 h (odluka 704). */
export const NEWS_WINDOW_MS = 48 * 3600 * 1000;
/** Najviše URL-ova u jednoj sitemap datoteci (protokol: 50 000; News: 1000). */
export const SITEMAP_MAX_URLS = 50_000;
export const NEWS_SITEMAP_MAX_URLS = 1000;
export const RSS_ITEMS = 30;
/** Pravne stranice portala (odluka 710); u sitemapu i u podnožju. */
export const LEGAL_PAGES = [
  { slug: 'impresum', title: 'Impresum' },
  { slug: 'kako-nastaju-clanci', title: 'Kako nastaju članci' },
  { slug: 'ispravci', title: 'Ispravci i povlačenje' },
] as const;

/** Apsolutni URL na javnoj domeni: `siteBase` + putanja portala. */
export function absoluteUrl(siteBase: string, path: string): string {
  return `${siteBase.replace(/\/+$/, '')}${path.startsWith('/') ? path : `/${path}`}`;
}

/** Canonical stranice portala: apsolutni URL bez upita i bez kose crte na kraju (osim naslovnice). */
export function canonicalUrl(siteBase: string, base: string, ...parts: string[]): string {
  return absoluteUrl(siteBase, portalPath(base, ...parts));
}

/** Postojeća OG slika epizode iz pipelinea (1200×630 JPEG), ista kao za `/v/<id>`. */
export function episodeOgImageUrl(cdnBase: string, videoId: string): string {
  return `${cdnBase}/images/${encodeURIComponent(videoId)}/og-share.jpg`;
}

/** Zamjenska slika kad epizoda nema `og-share.jpg` (ista kao naslovnica aplikacije). */
export function fallbackOgImageUrl(siteBase: string): string {
  return absoluteUrl(siteBase, '/og-image.png');
}

export function publisherLogoUrl(siteBase: string): string {
  return absoluteUrl(siteBase, '/icons/Icon-512.png');
}

/** ISO 8601 u UTC; null za prazno ili nečitljivo. */
export function isoTime(t: string | null | undefined): string | null {
  if (!t) return null;
  const d = new Date(t);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

/**
 * `dateModified`: zadnji ispravak (ne povlačenje), inače trenutak objave. Nova
 * verzija koju urednik još nije objavio ne mijenja javni tekst, pa ni datum.
 */
export function dateModified(
  publishedAt: string | null,
  corrections: readonly { kind: string; created_at: string }[],
): string | null {
  const times = [publishedAt, ...corrections.filter((c) => c.kind !== 'retraction').map((c) => c.created_at)]
    .map(isoTime)
    .filter((t): t is string => t !== null)
    .sort();
  return times.at(-1) ?? null;
}

export interface NewsArticleInput {
  url: string;
  title: string;
  lead: string | null;
  category: string | null;
  publishedAt: string | null;
  corrections: readonly { kind: string; description: string; created_at: string }[];
  image: string;
  episode: EpisodeMeta;
  siteBase: string;
  appBase: string;
  impresumUrl: string;
}

/** `NewsArticle` (schema.org) za objavljen ili ispravljen članak. */
export function newsArticleJsonLd(a: NewsArticleInput): Record<string, unknown> {
  const published = isoTime(a.publishedAt);
  const modified = dateModified(a.publishedAt, a.corrections);
  const fixes = a.corrections.filter((c) => c.kind !== 'retraction');
  const ep = a.episode;
  return {
    '@context': 'https://schema.org',
    '@type': 'NewsArticle',
    mainEntityOfPage: { '@type': 'WebPage', '@id': a.url },
    url: a.url,
    headline: a.title,
    ...(a.lead ? { description: a.lead } : {}),
    image: [a.image],
    ...(published ? { datePublished: published } : {}),
    ...(modified ? { dateModified: modified } : {}),
    inLanguage: PUBLICATION_LANG,
    ...(a.category ? { articleSection: categoryLabel(a.category) } : {}),
    author: { '@type': 'Organization', name: AUTHOR_NAME, url: a.impresumUrl },
    publisher: {
      '@type': 'Organization',
      name: 'DOMOVINA.ai',
      url: absoluteUrl(a.siteBase, '/'),
      logo: { '@type': 'ImageObject', url: publisherLogoUrl(a.siteBase), width: 512, height: 512 },
    },
    isBasedOn: {
      '@type': 'PodcastEpisode',
      url: appEpisodeUrl(a.appBase, ep.videoId),
      ...(ep.title ? { name: ep.title } : {}),
      ...(ep.date ? { datePublished: ep.date } : {}),
      ...(ep.channelName ? { partOfSeries: { '@type': 'PodcastSeries', name: ep.channelName } } : {}),
    },
    ...(fixes.length > 0
      ? {
          correction: fixes.map((c) => ({
            '@type': 'CorrectionComment',
            text: c.description,
            datePublished: isoTime(c.created_at),
          })),
        }
      : {}),
  };
}

/** JSON za `<script type="application/ld+json">`: `<` kao `<`, da tekst ne zatvori skriptu. */
export function jsonLdText(obj: unknown): string {
  return JSON.stringify(obj).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
}

const XML_ESC: Record<string, string> = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' };

/** Tekst za XML; kontrolni znakovi koje XML 1.0 ne dopušta se brišu. */
export function xmlEscape(s: string): string {
  // eslint-disable-next-line no-control-regex
  return s.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]/g, '').replace(/[&<>"']/g, (c) => XML_ESC[c] ?? c);
}

export interface SitemapEntry {
  loc: string;
  lastmod?: string | null;
}

export function sitemapXml(entries: readonly SitemapEntry[]): string {
  const urls = entries.slice(0, SITEMAP_MAX_URLS).map((e) => {
    const lastmod = isoTime(e.lastmod);
    return `<url><loc>${xmlEscape(e.loc)}</loc>${lastmod ? `<lastmod>${lastmod}</lastmod>` : ''}</url>`;
  });
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    ...urls,
    '</urlset>',
    '',
  ].join('\n');
}

export interface NewsEntry {
  loc: string;
  title: string;
  publishedAt: string;
}

/** Članci u prozoru od 48 h do `now` (uključivo), najnoviji prvi. */
export function inNewsWindow<T extends { publishedAt: string | null }>(list: readonly T[], now: Date): T[] {
  const from = now.getTime() - NEWS_WINDOW_MS;
  return list
    .filter((a) => {
      const t = a.publishedAt ? new Date(a.publishedAt).getTime() : NaN;
      return !Number.isNaN(t) && t >= from && t <= now.getTime();
    })
    .sort((a, b) => new Date(b.publishedAt ?? 0).getTime() - new Date(a.publishedAt ?? 0).getTime());
}

/** Google News sitemap (`xmlns:news`). Prazan je ispravan: `urlset` bez `url`. */
export function newsSitemapXml(entries: readonly NewsEntry[]): string {
  const urls = entries.slice(0, NEWS_SITEMAP_MAX_URLS).flatMap((e) => {
    const date = isoTime(e.publishedAt);
    if (!date) return [];
    return [
      `<url><loc>${xmlEscape(e.loc)}</loc><news:news><news:publication><news:name>${xmlEscape(PUBLICATION_NAME)}</news:name>` +
        `<news:language>${PUBLICATION_LANG}</news:language></news:publication>` +
        `<news:publication_date>${date}</news:publication_date><news:title>${xmlEscape(e.title)}</news:title></news:news></url>`,
    ];
  });
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:news="http://www.google.com/schemas/sitemap-news/0.9">',
    ...urls,
    '</urlset>',
    '',
  ].join('\n');
}

export interface RssItem {
  link: string;
  title: string;
  description: string;
  publishedAt: string | null;
  category: string | null;
}

/** RFC 822 datum za RSS (`Fri, 06 Nov 2026 10:00:00 GMT`). */
export function rfc822(t: string | null | undefined): string | null {
  const iso = isoTime(t);
  return iso ? new Date(iso).toUTCString() : null;
}

export function rssXml(opts: { siteUrl: string; selfUrl: string; items: readonly RssItem[]; now: Date }): string {
  const items = opts.items.slice(0, RSS_ITEMS).map((i) => {
    const date = rfc822(i.publishedAt);
    return [
      '<item>',
      `<title>${xmlEscape(i.title)}</title>`,
      `<link>${xmlEscape(i.link)}</link>`,
      `<guid isPermaLink="true">${xmlEscape(i.link)}</guid>`,
      `<description>${xmlEscape(i.description)}</description>`,
      date ? `<pubDate>${date}</pubDate>` : '',
      i.category ? `<category>${xmlEscape(categoryLabel(i.category))}</category>` : '',
      '</item>',
    ].join('');
  });
  const newest = opts.items.map((i) => rfc822(i.publishedAt)).find((d) => d !== null) ?? opts.now.toUTCString();
  return [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">',
    '<channel>',
    `<title>${xmlEscape(PUBLICATION_NAME)}</title>`,
    `<link>${xmlEscape(opts.siteUrl)}</link>`,
    `<description>${xmlEscape(SITE_DESCRIPTION)}</description>`,
    `<language>${PUBLICATION_LANG}</language>`,
    `<lastBuildDate>${newest}</lastBuildDate>`,
    `<atom:link href="${xmlEscape(opts.selfUrl)}" rel="self" type="application/rss+xml"/>`,
    ...items,
    '</channel>',
    '</rss>',
    '',
  ].join('\n');
}

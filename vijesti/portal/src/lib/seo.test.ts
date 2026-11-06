// SEO portala (S7, odluke 700–707): čiste funkcije bez mreže.
import { describe, expect, it } from 'vitest';
import type { EpisodeMeta } from '../../../engine/write/content.js';
import { DEFAULT_CONFIG, missingLegal, readConfig, readLegal } from './config.js';
import { REST_PAGE, selectAll } from './public-data.js';
import type { Rest } from './rest.js';
import {
  canonicalUrl,
  dateModified,
  episodeOgImageUrl,
  inNewsWindow,
  jsonLdText,
  newsArticleJsonLd,
  newsSitemapXml,
  rfc822,
  rssXml,
  sitemapXml,
  xmlEscape,
} from './seo.js';

const EPISODE: EpisodeMeta = {
  videoId: 'pIx_7N-6HJ4',
  title: 'Razgovor o obitelji',
  channel: 'mreze_rijeci',
  channelName: 'Mreže riječi',
  date: '2026-10-30',
  lang: 'hr',
  speakers: [],
};

describe('canonical i slike', () => {
  it('apsolutni canonical pod /vijesti, bez kose crte na kraju osim naslovnice', () => {
    expect(canonicalUrl('https://domovina.ai', '/vijesti')).toBe('https://domovina.ai/vijesti/');
    expect(canonicalUrl('https://domovina.ai/', '/vijesti/', 'naslov-abc')).toBe('https://domovina.ai/vijesti/naslov-abc');
    expect(canonicalUrl('https://domovina.ai', '/vijesti', 'kategorija', 'vjera')).toBe(
      'https://domovina.ai/vijesti/kategorija/vjera',
    );
  });
  it('OG slika epizode je postojeći og-share.jpg pipelinea', () => {
    expect(episodeOgImageUrl('https://cdn.domovina.ai', 'pIx_7N-6HJ4')).toBe(
      'https://cdn.domovina.ai/images/pIx_7N-6HJ4/og-share.jpg',
    );
  });
});

describe('NewsArticle JSON-LD', () => {
  const base = {
    url: 'https://domovina.ai/vijesti/naslov-pIx_7N-6HJ4',
    title: 'Naslov',
    lead: 'Lead.',
    category: 'drustvo',
    publishedAt: '2026-11-06T10:00:00+00:00',
    image: 'https://cdn.domovina.ai/images/pIx_7N-6HJ4/og-share.jpg',
    episode: EPISODE,
    siteBase: 'https://domovina.ai',
    appBase: 'https://domovina.ai',
    impresumUrl: 'https://domovina.ai/vijesti/impresum',
  };

  it('autor je redakcija, publisher DOMOVINA.ai s logom, izvor je epizoda', () => {
    const j = newsArticleJsonLd({ ...base, corrections: [] });
    expect(j).toMatchObject({
      '@context': 'https://schema.org',
      '@type': 'NewsArticle',
      headline: 'Naslov',
      description: 'Lead.',
      inLanguage: 'hr',
      articleSection: 'Društvo',
      datePublished: '2026-11-06T10:00:00.000Z',
      dateModified: '2026-11-06T10:00:00.000Z',
      author: { '@type': 'Organization', url: 'https://domovina.ai/vijesti/impresum' },
      publisher: { '@type': 'Organization', name: 'DOMOVINA.ai', logo: { url: 'https://domovina.ai/icons/Icon-512.png' } },
      isBasedOn: {
        '@type': 'PodcastEpisode',
        url: 'https://domovina.ai/v/pIx_7N-6HJ4',
        name: 'Razgovor o obitelji',
        partOfSeries: { name: 'Mreže riječi' },
      },
      image: [base.image],
    });
    expect(j).not.toHaveProperty('correction');
    expect((j.author as { '@type': string })['@type']).not.toBe('Person');
  });

  it('dateModified je zadnji ispravak; povlačenje se ne broji', () => {
    const corrections = [
      { kind: 'fact', description: 'Ispravak.', created_at: '2026-11-06T12:00:00Z' },
      { kind: 'retraction', description: 'Povučeno.', created_at: '2026-11-07T12:00:00Z' },
    ];
    const j = newsArticleJsonLd({ ...base, corrections });
    expect(j.dateModified).toBe('2026-11-06T12:00:00.000Z');
    expect(j.correction).toEqual([
      { '@type': 'CorrectionComment', text: 'Ispravak.', datePublished: '2026-11-06T12:00:00.000Z' },
    ]);
    expect(dateModified(null, [])).toBeNull();
    expect(dateModified('2026-11-06T10:00:00Z', [{ kind: 'quote', created_at: 'nije datum' }])).toBe(
      '2026-11-06T10:00:00.000Z',
    );
  });

  it('JSON-LD tekst ne može zatvoriti <script> i ostaje ispravan JSON', () => {
    const j = newsArticleJsonLd({ ...base, title: 'A </script><script>alert(1)</script>', corrections: [] });
    const text = jsonLdText(j);
    expect(text).not.toContain('</script');
    expect(text).not.toContain('<');
    expect((JSON.parse(text) as { headline: string }).headline).toBe('A </script><script>alert(1)</script>');
  });
});

describe('sitemap, news sitemap, RSS', () => {
  it('XML escape i kontrolni znakovi', () => {
    expect(xmlEscape(`a&b<c>"d'\u0001`)).toBe('a&amp;b&lt;c&gt;&quot;d&apos;');
  });

  it('sitemap: loc i lastmod u UTC, bez lastmod kad ga nema', () => {
    const xml = sitemapXml([
      { loc: 'https://domovina.ai/vijesti/' },
      { loc: 'https://domovina.ai/vijesti/a?b&c', lastmod: '2026-11-06T10:00:00+01:00' },
    ]);
    expect(xml).toContain('<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">');
    expect(xml).toContain('<url><loc>https://domovina.ai/vijesti/</loc></url>');
    expect(xml).toContain('<loc>https://domovina.ai/vijesti/a?b&amp;c</loc><lastmod>2026-11-06T09:00:00.000Z</lastmod>');
  });

  it('prozor vijesti je 48 h unatrag do sada, najnovije prvo', () => {
    const now = new Date('2026-11-06T12:00:00Z');
    const list = [
      { id: 'staro', publishedAt: '2026-11-04T11:59:59Z' },
      { id: 'rub', publishedAt: '2026-11-04T12:00:00Z' },
      { id: 'novo', publishedAt: '2026-11-06T11:00:00Z' },
      { id: 'buducnost', publishedAt: '2026-11-06T12:00:01Z' },
      { id: 'bez', publishedAt: null },
    ];
    expect(inNewsWindow(list, now).map((a) => a.id)).toEqual(['novo', 'rub']);
  });

  it('news sitemap: ime i jezik publikacije, datum prve objave, naslov', () => {
    const xml = newsSitemapXml([
      { loc: 'https://domovina.ai/vijesti/a', title: 'Naslov & više', publishedAt: '2026-11-06T10:00:00Z' },
      { loc: 'https://domovina.ai/vijesti/b', title: 'Bez datuma', publishedAt: 'x' },
    ]);
    expect(xml).toContain('xmlns:news="http://www.google.com/schemas/sitemap-news/0.9"');
    expect(xml).toContain('<news:name>DOMOVINA.ai Vijesti</news:name><news:language>hr</news:language>');
    expect(xml).toContain('<news:publication_date>2026-11-06T10:00:00.000Z</news:publication_date>');
    expect(xml).toContain('<news:title>Naslov &amp; više</news:title>');
    expect(xml).not.toContain('Bez datuma');
    expect(newsSitemapXml([])).toContain('</urlset>');
  });

  it('RSS 2.0: kanal, atom:link self, stavke s guid i RFC 822 datumom', () => {
    const xml = rssXml({
      siteUrl: 'https://domovina.ai/vijesti/',
      selfUrl: 'https://domovina.ai/vijesti/rss.xml',
      now: new Date('2026-11-06T12:00:00Z'),
      items: [
        {
          link: 'https://domovina.ai/vijesti/a',
          title: 'Naslov',
          description: 'Lead <b>',
          publishedAt: '2026-11-06T10:00:00Z',
          category: 'vjera',
        },
      ],
    });
    expect(xml).toContain('<rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">');
    expect(xml).toContain('<atom:link href="https://domovina.ai/vijesti/rss.xml" rel="self" type="application/rss+xml"/>');
    expect(xml).toContain('<guid isPermaLink="true">https://domovina.ai/vijesti/a</guid>');
    expect(xml).toContain('<description>Lead &lt;b&gt;</description>');
    expect(xml).toContain('<pubDate>Fri, 06 Nov 2026 10:00:00 GMT</pubDate>');
    expect(xml).toContain('<category>Vjera</category>');
    expect(xml).toContain('<lastBuildDate>Fri, 06 Nov 2026 10:00:00 GMT</lastBuildDate>');
    expect(rfc822(null)).toBeNull();
  });
});

describe('PostgREST stranice', () => {
  it('selectAll ide stranicu po stranicu (limit/offset) do kraja ili do gornje granice', async () => {
    const total = REST_PAGE * 2 + 5;
    const calls: Record<string, string>[] = [];
    const rest: Rest = {
      select: <T>(_rel: string, q: Record<string, string>) => {
        calls.push(q);
        const off = Number(q.offset);
        const n = Math.max(0, Math.min(Number(q.limit), total - off));
        return Promise.resolve(Array.from({ length: n }, (_, i) => ({ id: off + i })) as T[]);
      },
      rpc: () => Promise.reject(new Error('nije potrebno')),
    };
    expect(await selectAll(rest, 'articles', { select: 'id' }, 100_000)).toHaveLength(total);
    expect(calls.map((c) => c.offset)).toEqual(['0', String(REST_PAGE), String(REST_PAGE * 2)]);
    calls.length = 0;
    expect(await selectAll(rest, 'articles', { select: 'id' }, 1500)).toHaveLength(1500);
    expect(calls.map((c) => c.limit)).toEqual([String(REST_PAGE), '500']);
  });
});

describe('pravna konfiguracija', () => {
  it('prazna polja čekaju izdavača; zadano su sva prazna', () => {
    expect(missingLegal(DEFAULT_CONFIG.legal)).toEqual([
      'publisherName',
      'publisherAddress',
      'editorInChief',
      'contactEmail',
      'aemRegistration',
    ]);
    const legal = readLegal({ VIJESTI_EDITOR_IN_CHIEF: ' Ime Prezime ', VIJESTI_CONTACT_EMAIL: '' });
    expect(legal.editorInChief).toBe('Ime Prezime');
    expect(legal.contactEmail).toBeNull();
    expect(readConfig({ VIJESTI_SITE_BASE: 'https://primjer.hr/' }).siteBase).toBe('https://primjer.hr');
  });
});

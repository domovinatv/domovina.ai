// Čitanje javnih stranica kroz javne poglede (odluke 509, 524, 525): uvijek kao
// `anon`, pa RLS sam skriva nacrte, starije verzije i necitirane trenutke.
import type { ArticleContent, ContentBlock, EpisodeMeta } from '../../../engine/write/content.js';
import { eq, inList, type FetchFn, type Rest } from './rest.js';
import { episodeBundleUrl, pickClipMedia } from './urls.js';

export interface ArticleRow {
  id: number;
  slug: string;
  status: 'published' | 'corrected' | 'retracted';
  published_at: string | null;
  published_version_id: number | null;
  updated_at: string;
}

export interface VersionRow {
  id: number;
  article_id: number;
  version: number;
  title: string;
  lead: string | null;
  category: string | null;
  content: ArticleContent | null;
  created_at: string;
}

export interface MomentRow {
  id: number;
  video_id: string;
  start_ms: number;
  end_ms: number;
  speaker: string;
  speaker_name: string | null;
  quote: string;
  quote_lang: string;
}

export interface CorrectionRow {
  id: number;
  article_id: number;
  version_id: number | null;
  kind: 'quote' | 'fact' | 'attribution' | 'other' | 'retraction';
  description: string;
  created_at: string;
}

export interface ArticleCard {
  slug: string;
  title: string;
  lead: string;
  category: string | null;
  publishedAt: string | null;
  corrected: boolean;
  episodeTitle: string | null;
  channelName: string | null;
}

const ARTICLE_COLS = 'id,slug,status,published_at,published_version_id,updated_at';
const VERSION_COLS = 'id,article_id,version,title,lead,category,content,created_at';
const MOMENT_COLS = 'id,video_id,start_ms,end_ms,speaker,speaker_name,quote,quote_lang';
const LISTED = inList(['published', 'corrected']);

function toCard(a: ArticleRow, v: VersionRow): ArticleCard {
  return {
    slug: a.slug,
    title: v.title,
    lead: v.lead ?? '',
    category: v.category,
    publishedAt: a.published_at,
    corrected: a.status === 'corrected',
    episodeTitle: v.content?.episode.title ?? null,
    channelName: v.content?.episode.channelName ?? null,
  };
}

async function cards(rest: Rest, articles: ArticleRow[]): Promise<ArticleCard[]> {
  const ids = articles.flatMap((a) => (a.published_version_id === null ? [] : [a.published_version_id]));
  if (ids.length === 0) return [];
  const versions = await rest.select<VersionRow>('public_article_versions', { select: VERSION_COLS, id: inList(ids) });
  const byId = new Map(versions.map((v) => [v.id, v]));
  return articles.flatMap((a) => {
    const v = a.published_version_id === null ? undefined : byId.get(a.published_version_id);
    return v ? [toCard(a, v)] : [];
  });
}

/** Najnoviji objavljeni (i ispravljeni) članci; povučeni nisu na popisima. */
export async function latestArticles(rest: Rest, limit = 30): Promise<ArticleCard[]> {
  const articles = await rest.select<ArticleRow>('articles', {
    select: ARTICLE_COLS,
    status: LISTED,
    order: 'published_at.desc.nullslast,id.desc',
    limit: String(limit),
  });
  return cards(rest, articles);
}

/** Članci kategorije (kategorija je u objavljenoj verziji, ne u članku). */
export async function categoryArticles(rest: Rest, category: string, limit = 30): Promise<ArticleCard[]> {
  const versions = await rest.select<{ article_id: number }>('public_article_versions', {
    select: 'article_id',
    category: eq(category),
  });
  if (versions.length === 0) return [];
  const articles = await rest.select<ArticleRow>('articles', {
    select: ARTICLE_COLS,
    id: inList(versions.map((v) => v.article_id)),
    status: LISTED,
    order: 'published_at.desc.nullslast,id.desc',
    limit: String(limit),
  });
  return cards(rest, articles);
}

/** Grupiranje za naslovnicu: kategorije redom prve pojave (najsvježija prva). */
export function groupByCategory(list: readonly ArticleCard[]): { category: string; articles: ArticleCard[] }[] {
  const groups = new Map<string, ArticleCard[]>();
  for (const c of list) {
    const key = c.category ?? 'drustvo';
    const g = groups.get(key);
    if (g) g.push(c);
    else groups.set(key, [c]);
  }
  return [...groups].map(([category, articles]) => ({ category, articles }));
}

export type ArticlePage =
  | {
      kind: 'published';
      article: ArticleRow;
      version: VersionRow;
      content: ArticleContent;
      episode: EpisodeMeta;
      moments: Map<number, MomentRow>;
      corrections: CorrectionRow[];
    }
  | { kind: 'retracted'; article: ArticleRow; retraction: CorrectionRow | null; corrections: CorrectionRow[] };

/** Citirani trenutci bloka redom pojave. */
export function quotedMomentIds(blocks: readonly ContentBlock[]): number[] {
  return blocks.flatMap((b) => (b.type === 'quote' && b.moment_id !== null ? [b.moment_id] : []));
}

export async function articleBySlug(rest: Rest, slug: string): Promise<ArticlePage | null> {
  const [article] = await rest.select<ArticleRow>('articles', { select: ARTICLE_COLS, slug: eq(slug), limit: '1' });
  if (!article) return null;
  const corrections = await rest.select<CorrectionRow>('public_corrections', {
    select: 'id,article_id,version_id,kind,description,created_at',
    article_id: eq(article.id),
    order: 'created_at.asc,id.asc',
  });
  if (article.status === 'retracted') {
    const retraction = [...corrections].reverse().find((c) => c.kind === 'retraction') ?? null;
    return { kind: 'retracted', article, retraction, corrections };
  }
  if (article.published_version_id === null) return null;
  const [version] = await rest.select<VersionRow>('public_article_versions', {
    select: VERSION_COLS,
    id: eq(article.published_version_id),
  });
  if (!version?.content) return null;
  const ids = quotedMomentIds(version.content.blocks);
  const moments =
    ids.length === 0
      ? []
      : await rest.select<MomentRow>('public_moments', { select: MOMENT_COLS, id: inList(ids) });
  return {
    kind: 'published',
    article,
    version,
    content: version.content,
    episode: version.content.episode,
    moments: new Map(moments.map((m) => [m.id, m])),
    corrections,
  };
}

/**
 * Datoteka za isječke epizode iz `episode.json` na CDN-u (odluka 605). Greška,
 * 404 ili prekid daju null: članak se prikazuje bez playera, s poveznicom.
 */
export async function clipMediaFile(
  doFetch: FetchFn,
  cdnBase: string,
  videoId: string,
  timeoutMs = 1500,
): Promise<string | null> {
  try {
    const res = await doFetch(episodeBundleUrl(cdnBase, videoId), { signal: AbortSignal.timeout(timeoutMs) });
    if (!res.ok) return null;
    const j = (await res.json()) as { files?: unknown };
    const files = Array.isArray(j.files) ? j.files.filter((f): f is string => typeof f === 'string') : null;
    return pickClipMedia(files);
  } catch {
    return null;
  }
}

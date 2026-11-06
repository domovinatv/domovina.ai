// Urednički API nad PostgREST-om (odluka 500): čitanje kroz poglede uz RLS,
// pisanje samo kroz rpc funkcije migracije 006. Svaka funkcija koja ga prima
// dobiva id ZADNJE verzije (odluka 517, `stale_version:`).
import type { ArticleContent } from '../../../../engine/write/content.js';
import { eq, inList, type Rest } from '../../lib/rest.js';

export type Status = 'draft' | 'review' | 'approved' | 'published' | 'corrected' | 'rejected' | 'retracted';

export interface EditorArticle {
  id: number;
  slug: string;
  status: Status;
  approved_version_id: number | null;
  published_version_id: number | null;
  updated_at: string;
}

export interface SentenceCheck {
  n: number;
  part: 'title' | 'lead' | 'block';
  block: number | null;
  text: string;
  status: 'supported' | 'unsupported';
  supported_by: number[];
  metadata: boolean;
  problems: { code: string; detail?: string }[];
}

export interface VerifyJson {
  version: string;
  base_version: number;
  sentences: SentenceCheck[];
  removed: { text: string; code: string; detail: string }[];
  style: { code: string; detail: string; part: string; block: number | null }[];
  summary: { sentences: number; supported: number; unsupported: number; removed: number; style: number };
}

export interface EditorVersion {
  id: number;
  article_id: number;
  version: number;
  title: string;
  lead: string | null;
  category: string | null;
  content: ArticleContent | null;
  verify: VerifyJson | null;
  word_count: number | null;
  prompt_version: string | null;
  created_by: string | null;
  created_at: string;
}

export interface Resolution {
  version_id: number;
  n: number;
  resolution: 'verified' | 'no_claim';
  note: string;
  created_at: string;
}

export interface EventRow {
  id: number;
  from_status: Status | null;
  to_status: Status;
  version_id: number | null;
  actor_label: string;
  note: string | null;
  created_at: string;
}

export interface EditorMoment {
  id: number;
  video_id: string;
  start_ms: number;
  end_ms: number;
  speaker: string;
  speaker_name: string | null;
  quote: string;
  quote_check: 'exact' | 'fuzzy' | 'srt_only' | 'failed';
  quote_lang: string;
}

export interface CorrectionRow {
  id: number;
  version_id: number | null;
  kind: string;
  description: string;
  created_at: string;
}

export interface QueueItem {
  article: EditorArticle;
  title: string;
  version: number;
}

export interface ArticleBundle {
  article: EditorArticle;
  /** Od najnovije prema najstarijoj. */
  versions: EditorVersion[];
  latest: EditorVersion;
  /** Razrješenja zadnje verzije. */
  resolutions: Resolution[];
  moments: EditorMoment[];
  events: EventRow[];
  corrections: CorrectionRow[];
}

export type Block = { type: 'p'; text: string } | { type: 'quote'; moment_id: number };

export const QUEUE_STATUSES: readonly Status[] = ['draft', 'review', 'approved'];
export const ARCHIVE_STATUSES: readonly Status[] = ['published', 'corrected', 'rejected', 'retracted'];

const ARTICLE_COLS = 'id,slug,status,approved_version_id,published_version_id,updated_at';
const VERSION_COLS =
  'id,article_id,version,title,lead,category,content,verify,word_count,prompt_version,created_by,created_at';

/** Rečenice zadnje verzije koje čekaju urednika (nisu `supported`, nemaju razrješenje). */
export function pendingSentences(v: EditorVersion, resolutions: readonly Resolution[]): SentenceCheck[] {
  const done = new Set(resolutions.filter((r) => r.version_id === v.id).map((r) => r.n));
  return (v.verify?.sentences ?? []).filter((s) => s.status !== 'supported' && !done.has(s.n));
}

/**
 * Što objavljenom članku treba za ispravak (`correct_article`): nova verzija
 * nakon objavljene, automatska provjera te verzije i razrješenje označenih
 * rečenica. `null` = članak nije objavljen pa ispravka nema.
 */
export type CorrectionState = 'needs_edit' | 'needs_verify' | 'needs_resolution' | 'ready';

export function correctionState(b: Pick<ArticleBundle, 'article' | 'latest' | 'resolutions'>): CorrectionState | null {
  if (b.article.status !== 'published' && b.article.status !== 'corrected') return null;
  if (b.latest.id === b.article.published_version_id) return 'needs_edit';
  if (!b.latest.verify) return 'needs_verify';
  return pendingSentences(b.latest, b.resolutions).length > 0 ? 'needs_resolution' : 'ready';
}

/** Blokovi za `save_editor_version` iz sadržaja verzije (citat bez trenutka ispada). */
export function editableBlocks(v: EditorVersion): Block[] {
  return (v.content?.blocks ?? []).flatMap((b): Block[] =>
    b.type === 'p' ? [{ type: 'p', text: b.text }] : b.moment_id === null ? [] : [{ type: 'quote', moment_id: b.moment_id }],
  );
}

export function createEditorApi(rest: Rest) {
  return {
    async role(userId: string): Promise<'editor' | 'admin' | null> {
      const rows = await rest.select<{ role: 'editor' | 'admin' }>('staff', { select: 'role', user_id: eq(userId) });
      return rows[0]?.role ?? null;
    },

    async queue(statuses: readonly Status[]): Promise<QueueItem[]> {
      const articles = await rest.select<EditorArticle>('articles', {
        select: ARTICLE_COLS,
        status: inList(statuses),
        order: 'updated_at.desc,id.desc',
        limit: '200',
      });
      if (articles.length === 0) return [];
      const versions = await rest.select<{ article_id: number; version: number; title: string }>(
        'editor_article_versions',
        { select: 'article_id,version,title', article_id: inList(articles.map((a) => a.id)), order: 'version.desc' },
      );
      const latest = new Map<number, { version: number; title: string }>();
      for (const v of versions) if (!latest.has(v.article_id)) latest.set(v.article_id, v);
      return articles.map((a) => ({
        article: a,
        title: latest.get(a.id)?.title ?? `Članak ${String(a.id)}`,
        version: latest.get(a.id)?.version ?? 0,
      }));
    },

    async article(id: number): Promise<ArticleBundle | null> {
      const [article] = await rest.select<EditorArticle>('articles', { select: ARTICLE_COLS, id: eq(id) });
      if (!article) return null;
      const versions = await rest.select<EditorVersion>('editor_article_versions', {
        select: VERSION_COLS,
        article_id: eq(id),
        order: 'version.desc',
      });
      const latest = versions[0];
      if (!latest) return null;
      const videoId = latest.content?.episode.videoId ?? null;
      const [resolutions, moments, events, corrections] = await Promise.all([
        rest.select<Resolution>('sentence_resolutions', {
          select: 'version_id,n,resolution,note,created_at',
          version_id: eq(latest.id),
        }),
        videoId === null
          ? Promise.resolve([] as EditorMoment[])
          : rest.select<EditorMoment>('public_moments', {
              select: 'id,video_id,start_ms,end_ms,speaker,speaker_name,quote,quote_check,quote_lang',
              video_id: eq(videoId),
              quote_check: 'neq.failed',
              order: 'start_ms.asc',
            }),
        rest.select<EventRow>('article_events', {
          select: 'id,from_status,to_status,version_id,actor_label,note,created_at',
          article_id: eq(id),
          order: 'id.asc',
        }),
        rest.select<CorrectionRow>('public_corrections', {
          select: 'id,version_id,kind,description,created_at',
          article_id: eq(id),
          order: 'created_at.asc',
        }),
      ]);
      return { article, versions, latest, resolutions, moments, events, corrections };
    },

    transition: (articleId: number, to: 'review' | 'draft' | 'rejected', note: string | null) =>
      rest.rpc<null>('transition_article', { p_article_id: articleId, p_to: to, p_note: note }),
    approve: (articleId: number, latestVersionId: number, note: string | null) =>
      rest.rpc<null>('approve_article', { p_article_id: articleId, p_version_id: latestVersionId, p_note: note }),
    publish: (articleId: number, note: string | null) =>
      rest.rpc<null>('publish_article', { p_article_id: articleId, p_note: note }),
    saveVersion: (v: {
      articleId: number;
      latestVersionId: number;
      title: string;
      lead: string;
      category: string;
      blocks: readonly Block[];
    }) =>
      rest.rpc<number>('save_editor_version', {
        p_article_id: v.articleId,
        p_base_version_id: v.latestVersionId,
        p_title: v.title,
        p_lead: v.lead,
        p_category: v.category,
        p_blocks: v.blocks,
      }),
    resolve: (latestVersionId: number, n: number, resolution: 'verified' | 'no_claim', note: string) =>
      rest.rpc<null>('resolve_sentence', { p_version_id: latestVersionId, p_n: n, p_resolution: resolution, p_note: note }),
    correct: (articleId: number, latestVersionId: number, kind: string, description: string) =>
      rest.rpc<number>('correct_article', {
        p_article_id: articleId,
        p_version_id: latestVersionId,
        p_kind: kind,
        p_description: description,
      }),
    retract: (articleId: number, reason: string) =>
      rest.rpc<number>('retract_article', { p_article_id: articleId, p_reason: reason }),
  };
}

export type EditorApi = ReturnType<typeof createEditorApi>;

// Priča, članak i verzije u bazi (odluke 419–421). Svaka generacija i svaka
// izmjena je NOVA `article_versions` stavka s `run_id`, `created_by` i
// `article_sources` za svaki trenutak izvora; verzije se nikad ne mijenjaju.
import type { SqlDb } from '../../db/sql.js';
import { SCORE_VERSION } from '../score/formula.js';
import type { ArticleContent, SourceMoment } from './content.js';
import { slugify } from './text.js';

export const ARTICLE_FORMAT = 'vijest';
export const ARTICLE_LANG = 'hr';

/** Jedna priča po epizodi dok nema grupiranja (S9): `video-<videoId>`. */
export function storySlug(videoId: string): string {
  return `video-${videoId}`;
}

/** Javni slug: naslov prve verzije + ID videa (jedinstven i kad se naslovi poklope). */
export function articleSlug(title: string, videoId: string): string {
  const base = slugify(title, 60);
  return base ? `${base}-${videoId}` : videoId;
}

interface MomentRow {
  id: number | string;
  video_id: string;
  start_ms: number;
  speaker: string;
  speaker_name: string | null;
  quote: string;
  quote_lang: string;
  claim: string | null;
  entities: string[];
  score: number | null;
  position?: number;
}

function toSource(r: MomentRow, position: number): SourceMoment {
  return {
    id: Number(r.id),
    position,
    videoId: r.video_id,
    startMs: r.start_ms,
    speaker: r.speaker,
    speakerName: r.speaker_name,
    quote: r.quote,
    quoteLang: r.quote_lang,
    claim: r.claim,
    entities: r.entities,
    score: r.score,
  };
}

const MOMENT_COLS = 'm.id, m.video_id, m.start_ms, m.speaker, m.speaker_name, m.quote, m.quote_lang, m.claim, m.entities, m.score';

/**
 * Prihvaćeni trenuci epizode s ocjenom trenutne verzije ≥ praga, najbolji
 * prvi (isti broj: raniji u snimci). `position` je 0; dodjeljuje ga generator.
 */
export async function loadEligibleMoments(db: SqlDb, videoId: string, threshold: number): Promise<SourceMoment[]> {
  const res = await db.query<MomentRow>(
    `SELECT ${MOMENT_COLS} FROM vijesti.moments m
     WHERE m.video_id = $1 AND m.quote_check <> 'failed' AND m.score_version = $2 AND m.score >= $3
     ORDER BY m.score DESC, m.start_ms, m.id`,
    [videoId, SCORE_VERSION, threshold],
  );
  return res.rows.map((r) => toSource(r, 0));
}

export interface NewVersion {
  videoId: string;
  title: string;
  lead: string;
  body: string;
  category: string;
  content: ArticleContent;
  wordCount: number;
  promptVersion: string;
  runId: number | null;
  createdBy: string;
  sources: readonly { momentId: number; position: number }[];
  verify?: unknown;
}

export interface SavedVersion {
  storyId: number;
  articleId: number;
  versionId: number;
  version: number;
  slug: string;
}

async function one<T>(p: Promise<{ rows: T[] }>, what: string): Promise<T> {
  const row = (await p).rows[0];
  if (!row) throw new Error(`${what}: nema retka`);
  return row;
}

/** Priča i članak se stvaraju pri prvoj verziji; svaka iduća dobiva broj +1. Jedna transakcija. */
export async function saveArticleVersion(db: SqlDb, v: NewVersion): Promise<SavedVersion> {
  await db.exec('BEGIN');
  try {
    const story = await one(
      db.query<{ id: number | string }>(
        `INSERT INTO vijesti.stories (slug, title) VALUES ($1, $2)
         ON CONFLICT (slug) DO UPDATE SET updated_at = now() RETURNING id`,
        [storySlug(v.videoId), v.title],
      ),
      'stories',
    );
    const storyId = Number(story.id);
    const article = await one(
      db.query<{ id: number | string; slug: string }>(
        `INSERT INTO vijesti.articles (story_id, format, lang, slug) VALUES ($1, $2, $3, $4)
         ON CONFLICT (story_id, format, lang) DO UPDATE SET updated_at = now() RETURNING id, slug`,
        [storyId, ARTICLE_FORMAT, ARTICLE_LANG, articleSlug(v.title, v.videoId)],
      ),
      'articles',
    );
    const articleId = Number(article.id);
    const next = await one(
      db.query<{ n: number | string }>(
        'SELECT COALESCE(max(version), 0) + 1 AS n FROM vijesti.article_versions WHERE article_id = $1',
        [articleId],
      ),
      'article_versions',
    );
    const version = Number(next.n);
    const ins = await one(
      db.query<{ id: number | string }>(
        `INSERT INTO vijesti.article_versions
           (article_id, version, title, body, lead, category, content, word_count, prompt_version,
            verify, run_id, created_by)
         VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9, $10::jsonb, $11, $12) RETURNING id`,
        [
          articleId,
          version,
          v.title,
          v.body,
          v.lead,
          v.category,
          JSON.stringify(v.content),
          v.wordCount,
          v.promptVersion,
          v.verify === undefined ? null : JSON.stringify(v.verify),
          v.runId,
          v.createdBy,
        ],
      ),
      'article_versions',
    );
    const versionId = Number(ins.id);
    for (const s of v.sources) {
      await db.query('INSERT INTO vijesti.article_sources (version_id, moment_id, position) VALUES ($1, $2, $3)', [
        versionId,
        s.momentId,
        s.position,
      ]);
    }
    await db.exec('COMMIT');
    return { storyId, articleId, versionId, version, slug: article.slug };
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

export interface StoredVersion {
  articleId: number;
  versionId: number;
  version: number;
  title: string;
  lead: string | null;
  body: string;
  category: string | null;
  content: ArticleContent | null;
  wordCount: number | null;
  promptVersion: string | null;
  verify: unknown;
  createdBy: string | null;
  runId: number | null;
  /** Redom `position`. */
  sources: SourceMoment[];
}

interface VersionRow {
  article_id: number | string;
  id: number | string;
  version: number;
  title: string;
  lead: string | null;
  body: string;
  category: string | null;
  content: ArticleContent | null;
  word_count: number | null;
  prompt_version: string | null;
  verify: unknown;
  created_by: string | null;
  run_id: number | string | null;
}

/** Zadnja verzija članka sa svojim izvorima; null kad članak nema verzija. */
export async function loadLatestVersion(db: SqlDb, articleId: number): Promise<StoredVersion | null> {
  const res = await db.query<VersionRow>(
    `SELECT article_id, id, version, title, lead, body, category, content, word_count, prompt_version,
            verify, created_by, run_id
     FROM vijesti.article_versions WHERE article_id = $1 ORDER BY version DESC LIMIT 1`,
    [articleId],
  );
  const r = res.rows[0];
  if (!r) return null;
  const src = await db.query<MomentRow & { position: number }>(
    `SELECT ${MOMENT_COLS}, s.position FROM vijesti.article_sources s
     JOIN vijesti.moments m ON m.id = s.moment_id
     WHERE s.version_id = $1 ORDER BY s.position, m.id`,
    [r.id],
  );
  return {
    articleId: Number(r.article_id),
    versionId: Number(r.id),
    version: r.version,
    title: r.title,
    lead: r.lead,
    body: r.body,
    category: r.category,
    content: r.content,
    wordCount: r.word_count,
    promptVersion: r.prompt_version,
    verify: r.verify,
    createdBy: r.created_by,
    runId: r.run_id === null ? null : Number(r.run_id),
    sources: src.rows.map((m) => toSource(m, m.position)),
  };
}

/** Članak formata `vijest` za epizodu (priča `video-<id>`); null kad ga nema. */
export async function findArticleId(db: SqlDb, videoId: string): Promise<number | null> {
  const res = await db.query<{ id: number | string }>(
    `SELECT a.id FROM vijesti.articles a JOIN vijesti.stories s ON s.id = a.story_id
     WHERE s.slug = $1 AND a.format = $2 AND a.lang = $3`,
    [storySlug(videoId), ARTICLE_FORMAT, ARTICLE_LANG],
  );
  const r = res.rows[0];
  return r ? Number(r.id) : null;
}

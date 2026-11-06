// Urednički tok članka (migracija 006, odluke 500–520): tanak sloj nad SQL
// funkcijama koje Supabase izlaže kao `rpc`. Sva pravila (uloga, dopušten
// prijelaz, provjera verzije) su u bazi; ovaj modul samo zove funkcije i
// prevodi greške u kodove.
import type { SqlDb } from './sql.js';

export const ARTICLE_STATUSES = [
  'draft',
  'review',
  'approved',
  'published',
  'corrected',
  'rejected',
  'retracted',
] as const;
export type ArticleStatus = (typeof ARTICLE_STATUSES)[number];

/** Isti popis kao `vijesti.article_transitions` (test provjerava podudaranje). */
export const TRANSITIONS: readonly (readonly [ArticleStatus, ArticleStatus])[] = [
  ['draft', 'review'],
  ['draft', 'rejected'],
  ['review', 'draft'],
  ['review', 'approved'],
  ['review', 'rejected'],
  ['approved', 'review'],
  ['approved', 'published'],
  ['published', 'corrected'],
  ['corrected', 'corrected'],
  ['published', 'retracted'],
  ['corrected', 'retracted'],
  ['rejected', 'draft'],
];

/** Stanja u kojima čitatelj vidi članak (tijelo samo u published/corrected). */
export const PUBLIC_STATUSES: readonly ArticleStatus[] = ['published', 'corrected', 'retracted'];

export type CorrectionKind = 'quote' | 'fact' | 'attribution' | 'other';
export type SentenceResolution = 'verified' | 'no_claim';
export type StaffRole = 'editor' | 'admin';

/** Kodovi grešaka iz SQL funkcija: poruka počinje `kod:` (odluka 511). */
export const EDITORIAL_ERROR_CODES = [
  'forbidden',
  'not_found',
  'invalid_transition',
  'invalid_state',
  'invalid_input',
  'invalid_quote',
  'stale_version',
  'not_verified',
  'unresolved',
  'already_resolved',
  'channel_not_allowed',
  'last_admin',
  'append_only',
  'immutable',
] as const;
export type EditorialErrorCode = (typeof EDITORIAL_ERROR_CODES)[number];

export interface EditorialError {
  code: EditorialErrorCode;
  message: string;
}

/** Kod greške po prefiksu do prve dvotočke; null za grešku koja nije urednička. */
export function parseEditorialError(e: unknown): EditorialError | null {
  const message = e instanceof Error ? e.message : typeof e === 'string' ? e : null;
  if (message === null) return null;
  const i = message.indexOf(':');
  if (i <= 0) return null;
  const code = message.slice(0, i);
  return (EDITORIAL_ERROR_CODES as readonly string[]).includes(code)
    ? { code: code as EditorialErrorCode, message: message.slice(i + 1).trim() }
    : null;
}

async function call<T>(db: SqlDb, sql: string, params: unknown[]): Promise<T | undefined> {
  return (await db.query<{ r: T }>(sql, params)).rows[0]?.r;
}

/** U pregled, natrag u nacrt, odbijanje (traži bilješku) ili ponovno otvaranje. */
export async function transitionArticle(
  db: SqlDb,
  articleId: number,
  to: 'review' | 'draft' | 'rejected',
  note?: string,
): Promise<void> {
  await db.query('SELECT vijesti.transition_article($1, $2, $3)', [articleId, to, note ?? null]);
}

/** review → approved za zadnju verziju (provjerena, sve rečenice riješene). */
export async function approveArticle(db: SqlDb, articleId: number, versionId: number, note?: string): Promise<void> {
  await db.query('SELECT vijesti.approve_article($1, $2, $3)', [articleId, versionId, note ?? null]);
}

/** approved → published (kanal mora biti na popisu dopuštenih). */
export async function publishArticle(db: SqlDb, articleId: number, note?: string): Promise<void> {
  await db.query('SELECT vijesti.publish_article($1, $2)', [articleId, note ?? null]);
}

export type EditorBlock = { type: 'p'; text: string } | { type: 'quote'; moment_id: number };

export interface EditorVersion {
  articleId: number;
  /** Verzija koju je urednik uređivao; mora biti zadnja (inače `stale_version`). */
  baseVersionId: number;
  title: string;
  lead: string;
  category: string;
  blocks: readonly EditorBlock[];
}

/** Nova verzija bez provjere; vraća `article_versions.id`. */
export async function saveEditorVersion(db: SqlDb, v: EditorVersion): Promise<number> {
  const id = await call<number | string>(
    db,
    'SELECT vijesti.save_editor_version($1, $2, $3, $4, $5, $6::jsonb) AS r',
    [v.articleId, v.baseVersionId, v.title, v.lead, v.category, JSON.stringify(v.blocks)],
  );
  return Number(id);
}

export async function resolveSentence(
  db: SqlDb,
  versionId: number,
  n: number,
  resolution: SentenceResolution,
  note: string,
): Promise<void> {
  await db.query('SELECT vijesti.resolve_sentence($1, $2, $3, $4)', [versionId, n, resolution, note]);
}

/** Ispravak objavljenog članka; vraća `corrections.id`. */
export async function correctArticle(
  db: SqlDb,
  articleId: number,
  versionId: number,
  kind: CorrectionKind,
  description: string,
): Promise<number> {
  return Number(
    await call<number | string>(db, 'SELECT vijesti.correct_article($1, $2, $3, $4) AS r', [
      articleId,
      versionId,
      kind,
      description,
    ]),
  );
}

/** Povlačenje objavljenog članka; vraća `corrections.id`. */
export async function retractArticle(db: SqlDb, articleId: number, reason: string): Promise<number> {
  return Number(await call<number | string>(db, 'SELECT vijesti.retract_article($1, $2) AS r', [articleId, reason]));
}

export async function setStaffRole(db: SqlDb, userId: string, role: StaffRole): Promise<void> {
  await db.query('SELECT vijesti.set_staff_role($1::uuid, $2)', [userId, role]);
}

export async function removeStaff(db: SqlDb, userId: string): Promise<void> {
  await db.query('SELECT vijesti.remove_staff($1::uuid)', [userId]);
}

export async function allowChannel(db: SqlDb, channel: string, note?: string): Promise<void> {
  await db.query('SELECT vijesti.allow_channel($1, $2)', [channel, note ?? null]);
}

export async function disallowChannel(db: SqlDb, channel: string): Promise<void> {
  await db.query('SELECT vijesti.disallow_channel($1)', [channel]);
}

export interface ArticleEvent {
  fromStatus: ArticleStatus | null;
  toStatus: ArticleStatus;
  versionId: number | null;
  actor: string | null;
  actorLabel: string;
  note: string | null;
}

/** Dnevnik prijelaza članka redom nastanka. */
export async function loadArticleEvents(db: SqlDb, articleId: number): Promise<ArticleEvent[]> {
  const res = await db.query<{
    from_status: ArticleStatus | null;
    to_status: ArticleStatus;
    version_id: number | string | null;
    actor: string | null;
    actor_label: string;
    note: string | null;
  }>(
    `SELECT from_status, to_status, version_id, actor, actor_label, note
     FROM vijesti.article_events WHERE article_id = $1 ORDER BY id`,
    [articleId],
  );
  return res.rows.map((r) => ({
    fromStatus: r.from_status,
    toStatus: r.to_status,
    versionId: r.version_id === null ? null : Number(r.version_id),
    actor: r.actor,
    actorLabel: r.actor_label,
    note: r.note,
  }));
}

/**
 * Izvrši `fn` kao čitatelj (`null` → uloga `anon`) ili prijavljeni korisnik
 * (`authenticated` s `sub` = userId), isto kao PostgREST: u transakciji
 * `SET LOCAL ROLE` + `request.jwt.claims`. Greška vraća transakciju.
 */
export async function asUser<T>(db: SqlDb, userId: string | null, fn: (db: SqlDb) => Promise<T>): Promise<T> {
  const role = userId === null ? 'anon' : 'authenticated';
  const claims = userId === null ? { role } : { sub: userId, role };
  await db.exec('BEGIN');
  try {
    await db.exec(`SET LOCAL ROLE ${role}`);
    await db.query("SELECT set_config('request.jwt.claims', $1, true)", [JSON.stringify(claims)]);
    const out = await fn(db);
    await db.exec('COMMIT');
    return out;
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

// Čitanje prihvaćenih trenutaka i zapis ocjena (migracija 003, odluka 311).
// Ponovno ocjenjivanje u jednoj transakciji prvo briše ocjene svih trenutaka
// videa pa upisuje nove: trenutak koji model izostavi ostaje BEZ ocjene, nikad
// sa starom ocjenom druge verzije.
import type { SqlDb } from '../../db/sql.js';
import type { ScoreParts } from './formula.js';
import type { MomentScore } from './prompt.js';

export interface StoredMoment {
  id: number;
  videoId: string;
  startMs: number;
  speaker: string;
  quote: string;
  claim: string | null;
  entities: string[];
  quoteCheck: 'exact' | 'fuzzy' | 'srt_only';
  quoteLang: string;
}

interface Row {
  id: number | string;
  video_id: string;
  start_ms: number;
  speaker: string;
  quote: string;
  claim: string | null;
  entities: string[];
  quote_check: StoredMoment['quoteCheck'];
  quote_lang: string;
}

/** Trenuci koji su prošli provjeru citata (`quote_check` ≠ `failed`), redom snimke. */
export async function loadAcceptedMoments(db: SqlDb, videoId: string): Promise<StoredMoment[]> {
  const res = await db.query<Row>(
    `SELECT id, video_id, start_ms, speaker, quote, claim, entities, quote_check, quote_lang
     FROM vijesti.moments WHERE video_id = $1 AND quote_check <> 'failed'
     ORDER BY start_ms, id`,
    [videoId],
  );
  return res.rows.map((r) => ({
    id: Number(r.id),
    videoId: r.video_id,
    startMs: r.start_ms,
    speaker: r.speaker,
    quote: r.quote,
    claim: r.claim,
    entities: r.entities,
    quoteCheck: r.quote_check,
    quoteLang: r.quote_lang,
  }));
}

export interface ScoreRow {
  momentId: number;
  score: number;
  parts: ScoreParts;
  reasons: MomentScore['reasons'];
  speakerName: string | null;
}

export interface SaveScoresResult {
  /** Trenuci videa kojima je obrisana prethodna ocjena. */
  cleared: number;
  updated: number;
}

export async function saveScores(
  db: SqlDb,
  videoId: string,
  rows: readonly ScoreRow[],
  meta: { version: string; runId: number },
): Promise<SaveScoresResult> {
  await db.exec('BEGIN');
  try {
    const cleared = await db.query<{ id: number }>(
      `UPDATE vijesti.moments SET score = NULL, score_parts = NULL, score_reasons = NULL,
         score_version = NULL, score_run_id = NULL, scored_at = NULL
       WHERE video_id = $1 AND score IS NOT NULL RETURNING id`,
      [videoId],
    );
    let updated = 0;
    for (const r of rows) {
      const res = await db.query<{ id: number }>(
        `UPDATE vijesti.moments SET score = $3, score_parts = $4::jsonb, score_reasons = $5::jsonb,
           score_version = $6, score_run_id = $7, scored_at = now(),
           speaker_name = COALESCE($8, speaker_name)
         WHERE id = $1 AND video_id = $2 AND quote_check <> 'failed' RETURNING id`,
        [
          r.momentId,
          videoId,
          r.score,
          JSON.stringify(r.parts),
          JSON.stringify(r.reasons),
          meta.version,
          meta.runId,
          r.speakerName,
        ],
      );
      if (res.rows.length !== 1) {
        throw new Error(`trenutak ${String(r.momentId)} nije prihvaćen trenutak videa ${videoId}`);
      }
      updated++;
    }
    await db.exec('COMMIT');
    return { cleared: cleared.rows.length, updated };
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

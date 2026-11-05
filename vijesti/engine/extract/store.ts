// Zapis trenutaka u `vijesti.moments` (odluka 207). Ponovno izvlačenje istog
// videa zamjenjuje prethodne trenutke, osim onih na koje se netko već poziva
// (članak preko `article_sources`, priča preko `story_moments`).
import type { SqlDb } from '../../db/sql.js';
import type { QuoteCheck, QuoteMatch, RejectReason } from '../verify/quote.js';

export interface MomentRow {
  videoId: string;
  startMs: number;
  endMs: number;
  speaker: string;
  quote: string;
  quoteCheck: QuoteCheck;
  quoteMatch: QuoteMatch | null;
  rejectReason: RejectReason | null;
  quoteLang: string;
  claim: string;
  topics: string[];
  entities: string[];
  cueFrom: number;
  cueTo: number;
  runId: number;
}

export interface SaveResult {
  deleted: number;
  inserted: number;
  /** Isti (video, raspon, citat) već postoji (zadržan citirani ili duplikat u prolazu). */
  skipped: number;
}

export async function saveMoments(db: SqlDb, videoId: string, rows: MomentRow[]): Promise<SaveResult> {
  await db.exec('BEGIN');
  try {
    const del = await db.query<{ id: number }>(
      `DELETE FROM vijesti.moments m
       WHERE m.video_id = $1
         AND NOT EXISTS (SELECT 1 FROM vijesti.article_sources s WHERE s.moment_id = m.id)
         AND NOT EXISTS (SELECT 1 FROM vijesti.story_moments sm WHERE sm.moment_id = m.id)
       RETURNING m.id`,
      [videoId],
    );
    let inserted = 0;
    // Prihvaćeni trenuci idu prvi: odbačen trenutak s istim ključem (video,
    // raspon, citat), npr. isti citat uz krivog govornika, inače bi ON CONFLICT
    // zadržao njega, a valjani preskočio (odluka 214).
    const ordered = [...rows.filter((r) => r.quoteCheck !== 'failed'), ...rows.filter((r) => r.quoteCheck === 'failed')];
    for (const r of ordered) {
      if (r.videoId !== videoId) throw new Error(`trenutak za ${r.videoId} u zapisu za ${videoId}`);
      const res = await db.query<{ id: number }>(
        `INSERT INTO vijesti.moments
           (video_id, start_ms, end_ms, speaker, quote, quote_check, quote_match, reject_reason,
            quote_lang, claim, topics, entities, cue_from, cue_to, run_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15)
         ON CONFLICT (video_id, start_ms, end_ms, quote) DO NOTHING
         RETURNING id`,
        [
          r.videoId,
          r.startMs,
          r.endMs,
          r.speaker,
          r.quote,
          r.quoteCheck,
          r.quoteMatch,
          r.rejectReason,
          r.quoteLang,
          r.claim,
          r.topics,
          r.entities,
          r.cueFrom,
          r.cueTo,
          r.runId,
        ],
      );
      inserted += res.rows.length;
    }
    await db.exec('COMMIT');
    return { deleted: del.rows.length, inserted, skipped: rows.length - inserted };
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

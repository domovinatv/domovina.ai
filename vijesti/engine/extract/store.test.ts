import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';
import { migrateUp } from '../../db/migrate.js';
import { saveMoments, type MomentRow } from './store.js';

const base: MomentRow = {
  videoId: 'v1',
  startMs: 1000,
  endMs: 5000,
  speaker: 'SPEAKER_00',
  quote: 'ovo je isti citat',
  quoteCheck: 'exact',
  quoteMatch: 'exact',
  rejectReason: null,
  quoteLang: 'hr',
  claim: 'tvrdnja',
  topics: [],
  entities: [],
  cueFrom: 3,
  cueTo: 3,
  runId: 0,
};

describe('saveMoments', () => {
  it('odbačen i prihvaćen trenutak s istim ključem: ostaje prihvaćeni, bez obzira na redoslijed', async () => {
    const db = new PGlite();
    await db.waitReady;
    await migrateUp(db);
    const run = await db.query<{ id: number }>(
      `INSERT INTO vijesti.runs (step, model) VALUES ('extract', 'fake') RETURNING id`,
    );
    const runId = run.rows[0]?.id ?? 0;
    const failed: MomentRow = {
      ...base,
      runId,
      speaker: 'SPEAKER_01',
      quoteCheck: 'failed',
      quoteMatch: null,
      rejectReason: 'speaker_mismatch',
    };
    const ok: MomentRow = { ...base, runId };
    expect(await saveMoments(db, 'v1', [failed, ok])).toEqual({ deleted: 0, inserted: 1, skipped: 1 });
    const rows = await db.query<{ quote_check: string; speaker: string }>(
      'SELECT quote_check, speaker FROM vijesti.moments WHERE video_id = $1',
      ['v1'],
    );
    expect(rows.rows).toEqual([{ quote_check: 'exact', speaker: 'SPEAKER_00' }]);
    // Ponovno, obrnutim redom: isti ishod (idempotentno).
    expect(await saveMoments(db, 'v1', [ok, failed])).toEqual({ deleted: 1, inserted: 1, skipped: 1 });
    await db.close();
  });
});

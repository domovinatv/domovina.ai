import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';
import { runExtractCli, runScoreCli, runVerifyCli, runWriteCli } from '../engine/cli.js';
import { exportSql } from './export-to-prod.js';
import { migrateUp } from './migrate.js';

const VIDEO = 'MGLq9v3AtvE';

describe('prijenos u produkciju (odluka 804)', () => {
  it('lažni tok → SQL → prazna shema: isti retci, okidači ne dupliraju dnevnik, sekvence poravnate', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vijesti-export-'));
    const src = join(dir, 'src');
    try {
      await runExtractCli({ videoId: VIDEO, fake: true, db: src });
      await runScoreCli({ videoId: VIDEO, fake: true, db: src });
      await runWriteCli({ videoId: VIDEO, fake: true, db: src });
      await runVerifyCli({ target: { videoId: VIDEO }, fake: true, db: src });
      const a = new PGlite(src);
      const { sql, counts } = await exportSql(a);
      await a.close();
      expect(counts.articles).toBe(1);
      expect(counts.article_versions).toBe(2);
      expect(counts.moments).toBeGreaterThan(0);

      const prod = new PGlite();
      await migrateUp(prod);
      // psql meta-naredba nije SQL; PGlite je ne zna.
      await prod.exec(sql.replace('\\set ON_ERROR_STOP on\n', ''));
      for (const [t, n] of Object.entries(counts)) {
        const r = await prod.query<{ n: number }>(`SELECT count(*)::int AS n FROM vijesti.${t}`);
        expect([t, r.rows[0]?.n]).toEqual([t, n]);
      }
      // Sljedeći run dobiva ID iza prenesenih.
      const max = await prod.query<{ m: number }>('SELECT max(id)::int AS m FROM vijesti.runs');
      const next = await prod.query<{ id: number }>(
        "INSERT INTO vijesti.runs (step, model) VALUES ('t', 'm') RETURNING id",
      );
      expect(next.rows[0]?.id).toBeGreaterThan(max.rows[0]?.m ?? 0);
      // Drugi prijenos istih redaka pada (nema prepisivanja).
      await expect(prod.exec(sql.replace('\\set ON_ERROR_STOP on\n', ''))).rejects.toThrow();
      await prod.close();
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  }, 60_000);
});

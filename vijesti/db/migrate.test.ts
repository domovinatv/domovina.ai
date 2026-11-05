import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { appliedVersions, loadMigrations, migrateDown, migrateUp } from './migrate.js';

const TABLES = [
  'article_sources',
  'article_versions',
  'articles',
  'corrections',
  'moments',
  'runs',
  'schema_migrations',
  'stories',
  'story_moments',
];

async function tables(db: PGlite): Promise<string[]> {
  const res = await db.query<{ table_name: string }>(
    `SELECT table_name FROM information_schema.tables
     WHERE table_schema = 'vijesti' ORDER BY table_name`,
  );
  return res.rows.map((r) => r.table_name);
}

describe('migracije na PGlite', () => {
  let db: PGlite;
  beforeEach(async () => {
    db = new PGlite();
    await db.waitReady;
  });
  afterEach(async () => {
    await db.close();
  });

  it('gore → dolje → gore', async () => {
    expect(await migrateUp(db)).toEqual([1]);
    expect(await tables(db)).toEqual(TABLES);
    expect(await migrateUp(db)).toEqual([]);

    expect(await migrateDown(db, { steps: Infinity })).toEqual([1]);
    expect(await tables(db)).toEqual(['schema_migrations']);
    expect(await appliedVersions(db)).toEqual([]);

    expect(await migrateUp(db)).toEqual([1]);
    expect(await tables(db)).toEqual(TABLES);
    expect(await appliedVersions(db)).toEqual([1]);
  });

  it('migracija koja padne ne ostavlja ništa (transakcija)', async () => {
    const migrations = [
      ...(await loadMigrations()),
      {
        version: 2,
        name: 'pokvarena',
        up: 'CREATE TABLE vijesti.privremena (id int); SELECT nepostojeci_stupac FROM vijesti.runs;',
        down: 'DROP TABLE vijesti.privremena;',
      },
    ];
    await expect(migrateUp(db, { migrations })).rejects.toThrow(/nepostojeci_stupac/);
    expect(await appliedVersions(db)).toEqual([1]);
    expect(await tables(db)).not.toContain('privremena');
  });

  describe('ograničenja', () => {
    beforeEach(async () => {
      await migrateUp(db);
    });

    const moment = (over: Record<string, unknown> = {}) => {
      const m = {
        video_id: 'pIx_7N-6HJ4',
        start_ms: 51750,
        end_ms: 55590,
        speaker: 'SPEAKER_01',
        quote: 'Dakle, počeli smo srijedom.',
        quote_check: 'exact',
        ...over,
      };
      return db.query<{ id: number }>(
        `INSERT INTO vijesti.moments (video_id, start_ms, end_ms, speaker, quote, quote_check)
         VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
        [m.video_id, m.start_ms, m.end_ms, m.speaker, m.quote, m.quote_check],
      );
    };

    it('quote_check prima samo exact | fuzzy | srt_only | failed', async () => {
      for (const [i, ok] of ['exact', 'fuzzy', 'srt_only', 'failed'].entries()) {
        await moment({ quote_check: ok, start_ms: i * 10_000, end_ms: i * 10_000 + 1 });
      }
      await expect(moment({ quote_check: 'maybe', start_ms: 99_000, end_ms: 99_001 })).rejects.toThrow(
        /moments_quote_check_check/,
      );
    });

    it('raspon, prazan citat i duplikat se odbijaju', async () => {
      await expect(moment({ end_ms: 51750 })).rejects.toThrow(/check/i);
      await expect(moment({ start_ms: -1 })).rejects.toThrow(/check/i);
      await expect(moment({ quote: '   ' })).rejects.toThrow(/check/i);
      await moment();
      await expect(moment()).rejects.toThrow(/unique|duplicate/i);
    });

    it('citiran trenutak se ne može obrisati; verzija i izvori idu s člankom', async () => {
      const m = (await moment()).rows[0]?.id;
      const s = await db.query<{ id: number }>(
        `INSERT INTO vijesti.stories (slug, title) VALUES ('test', 'Test') RETURNING id`,
      );
      const a = await db.query<{ id: number }>(
        `INSERT INTO vijesti.articles (story_id, format, slug) VALUES ($1, 'vijest', 'test') RETURNING id`,
        [s.rows[0]?.id],
      );
      const v = await db.query<{ id: number }>(
        `INSERT INTO vijesti.article_versions (article_id, version, title, body)
         VALUES ($1, 1, 'Naslov', 'Tijelo') RETURNING id`,
        [a.rows[0]?.id],
      );
      await db.query('INSERT INTO vijesti.article_sources (version_id, moment_id) VALUES ($1, $2)', [
        v.rows[0]?.id,
        m,
      ]);
      await expect(db.query('DELETE FROM vijesti.moments WHERE id = $1', [m])).rejects.toThrow(
        /foreign key/i,
      );
      await expect(
        db.query(`UPDATE vijesti.articles SET status = 'objavljeno' WHERE id = $1`, [a.rows[0]?.id]),
      ).rejects.toThrow(/articles_status_check/);
      await db.query('DELETE FROM vijesti.articles WHERE id = $1', [a.rows[0]?.id]);
      const left = await db.query('SELECT 1 FROM vijesti.article_sources');
      expect(left.rows).toHaveLength(0);
    });

    it('runs: failed_calls ne može biti veći od calls', async () => {
      await expect(
        db.query(`INSERT INTO vijesti.runs (step, model, calls, failed_calls) VALUES ('x', 'm', 1, 2)`),
      ).rejects.toThrow(/check/i);
    });
  });
});

describe('loadMigrations', () => {
  let dir = '';
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'vijesti-mig-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('svaka migracija u repou ima up i down, brojevi rastu', async () => {
    const ms = await loadMigrations();
    expect(ms.map((m) => m.version)).toEqual([...ms.keys()].map((i) => i + 1));
  });

  it('migracija bez down datoteke je greška', async () => {
    await writeFile(join(dir, '001_samo_gore.up.sql'), 'SELECT 1;');
    await expect(loadMigrations(dir)).rejects.toThrow(/up i down/);
  });

  it('krivo ime .sql datoteke je greška', async () => {
    await writeFile(join(dir, 'init.sql'), 'SELECT 1;');
    await expect(loadMigrations(dir)).rejects.toThrow(/ime migracije/);
  });
});

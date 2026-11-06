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
  'eval_channels',
  'eval_sample',
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
    expect(await migrateUp(db)).toEqual([1, 2, 3, 4, 5]);
    expect(await tables(db)).toEqual(TABLES);
    expect(await migrateUp(db)).toEqual([]);

    expect(await migrateDown(db, { steps: Infinity })).toEqual([5, 4, 3, 2, 1]);
    expect(await tables(db)).toEqual(['schema_migrations']);
    // Odluka 108: nakon „dolje” u shemi ostaje samo knjigovodstvo runnera, bez
    // ijednog drugog objekta (sekvence, indeksi, tipovi).
    const leftovers = await db.query<{ relname: string }>(
      `SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
       WHERE n.nspname = 'vijesti' ORDER BY c.relname`,
    );
    expect(leftovers.rows.map((r) => r.relname)).toEqual([
      'schema_migrations',
      'schema_migrations_pkey',
    ]);
    const types = await db.query(
      `SELECT 1 FROM pg_type t JOIN pg_namespace n ON n.oid = t.typnamespace
       WHERE n.nspname = 'vijesti' AND t.typname NOT LIKE '%schema_migrations'`,
    );
    expect(types.rows).toHaveLength(0);
    expect(await appliedVersions(db)).toEqual([]);

    expect(await migrateUp(db)).toEqual([1, 2, 3, 4, 5]);
    expect(await tables(db)).toEqual(TABLES);
    expect(await appliedVersions(db)).toEqual([1, 2, 3, 4, 5]);
  });

  it('migracija koja padne ne ostavlja ništa (transakcija)', async () => {
    const migrations = [
      ...(await loadMigrations()),
      {
        version: 99,
        name: 'pokvarena',
        up: 'CREATE TABLE vijesti.privremena (id int); SELECT nepostojeci_stupac FROM vijesti.runs;',
        down: 'DROP TABLE vijesti.privremena;',
      },
    ];
    await expect(migrateUp(db, { migrations })).rejects.toThrow(/nepostojeci_stupac/);
    expect(await appliedVersions(db)).toEqual([1, 2, 3, 4, 5]);
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
      // Migracija 002: quote_match i reject_reason moraju pratiti quote_check.
      const check = m.quote_check;
      const match =
        'quote_match' in over
          ? over.quote_match
          : check === 'exact' || check === 'fuzzy'
            ? check
            : check === 'srt_only'
              ? 'exact'
              : null;
      const reason = 'reject_reason' in over ? over.reject_reason : check === 'failed' ? 'not_found' : null;
      return db.query<{ id: number }>(
        `INSERT INTO vijesti.moments
           (video_id, start_ms, end_ms, speaker, quote, quote_check, quote_match, reject_reason)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING id`,
        [m.video_id, m.start_ms, m.end_ms, m.speaker, m.quote, m.quote_check, match, reason],
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

    it('articles.status prima svih šest stanja iz plana', async () => {
      const s = await db.query<{ id: number }>(
        `INSERT INTO vijesti.stories (slug, title) VALUES ('st', 'St') RETURNING id`,
      );
      const states = ['draft', 'review', 'approved', 'published', 'corrected', 'rejected'];
      for (const [i, st] of states.entries()) {
        await db.query(
          `INSERT INTO vijesti.articles (story_id, format, lang, slug, status)
           VALUES ($1, $2, 'hr', $3, $4)`,
          [s.rows[0]?.id, `f${String(i)}`, `slug-${String(i)}`, st],
        );
      }
      await expect(
        db.query(
          `INSERT INTO vijesti.articles (story_id, format, slug, lang) VALUES ($1, 'x', 'y', 'de')`,
          [s.rows[0]?.id],
        ),
      ).rejects.toThrow(/articles_lang_check/);
    });

    it('quote_check NULL se odbija (NOT NULL uz CHECK)', async () => {
      await expect(moment({ quote_check: null })).rejects.toThrow(/null/i);
    });

    it('002: failed ⇔ reject_reason; quote_match prati quote_check', async () => {
      await moment({ quote_check: 'failed', start_ms: 1, end_ms: 2 });
      await expect(
        moment({ quote_check: 'failed', reject_reason: null, start_ms: 3, end_ms: 4 }),
      ).rejects.toThrow(/moments_reject_reason_consistent/);
      await expect(
        moment({ quote_check: 'exact', reject_reason: 'not_found', start_ms: 5, end_ms: 6 }),
      ).rejects.toThrow(/moments_reject_reason_consistent/);
      await expect(
        moment({ quote_check: 'failed', reject_reason: '  ', start_ms: 7, end_ms: 8 }),
      ).rejects.toThrow(/moments_reject_reason_check/);
      await expect(
        moment({ quote_check: 'exact', quote_match: 'fuzzy', start_ms: 9, end_ms: 10 }),
      ).rejects.toThrow(/moments_quote_match_consistent/);
      await expect(
        moment({ quote_check: 'srt_only', quote_match: null, start_ms: 11, end_ms: 12 }),
      ).rejects.toThrow(/moments_quote_match_consistent/);
      await expect(
        moment({ quote_check: 'failed', quote_match: 'exact', start_ms: 13, end_ms: 14 }),
      ).rejects.toThrow(/moments_quote_match_consistent/);
      await moment({ quote_check: 'srt_only', quote_match: 'fuzzy', start_ms: 15, end_ms: 16 });
    });

    it('002 dolje vraća shemu iz 001, gore je opet stavlja', async () => {
      expect(await migrateDown(db, { steps: 3 })).toEqual([5, 4, 3]);
      const cols = async () =>
        (
          await db.query<{ column_name: string }>(
            `SELECT column_name FROM information_schema.columns
             WHERE table_schema = 'vijesti' AND table_name = 'moments' ORDER BY column_name`,
          )
        ).rows.map((r) => r.column_name);
      const withS2 = await cols();
      expect(withS2).toEqual(expect.arrayContaining(['claim', 'reject_reason', 'quote_match', 'cue_from', 'cue_to']));
      expect(await migrateDown(db)).toEqual([2]);
      const without = await cols();
      expect(without.filter((c) => !withS2.includes(c))).toEqual([]);
      expect(withS2.filter((c) => !without.includes(c)).sort()).toEqual(
        ['claim', 'cue_from', 'cue_to', 'quote_match', 'reject_reason'],
      );
      const cons = await db.query(
        `SELECT 1 FROM pg_constraint WHERE conname LIKE 'moments_%consistent'`,
      );
      expect(cons.rows).toHaveLength(0);
      expect(await migrateUp(db, { to: 2 })).toEqual([2]);
      expect(await cols()).toEqual(withS2);
    });

    it('002 dolje → gore s podacima: exact/fuzzy se vraćaju, failed/srt_only ruše migraciju bez traga', async () => {
      expect(await migrateDown(db, { steps: 3 })).toEqual([5, 4, 3]);
      await moment({ quote_check: 'exact', start_ms: 1, end_ms: 2 });
      await moment({ quote_check: 'fuzzy', start_ms: 3, end_ms: 4 });
      expect(await migrateDown(db)).toEqual([2]);
      expect(await migrateUp(db, { to: 2 })).toEqual([2]);
      const got = await db.query<{ quote_check: string; quote_match: string }>(
        'SELECT quote_check, quote_match FROM vijesti.moments ORDER BY start_ms',
      );
      expect(got.rows).toEqual([
        { quote_check: 'exact', quote_match: 'exact' },
        { quote_check: 'fuzzy', quote_match: 'fuzzy' },
      ]);
      // srt_only nakon 002 dolje više ne zna je li tekst bio točan: ne izmišlja se.
      await moment({ quote_check: 'srt_only', start_ms: 5, end_ms: 6 });
      expect(await migrateDown(db)).toEqual([2]);
      await expect(migrateUp(db, { to: 2 })).rejects.toThrow(/moments_quote_match_consistent/);
      expect(await appliedVersions(db)).toEqual([1]);
    });

    const scoreCols = async () =>
      (
        await db.query<{ column_name: string }>(
          `SELECT column_name FROM information_schema.columns
           WHERE table_schema = 'vijesti' AND table_name = 'moments' AND column_name LIKE 'score%'
           ORDER BY column_name`,
        )
      ).rows.map((r) => r.column_name);
    const setScore = (id: number, score: number | null, over: Record<string, unknown> = {}) =>
      db.query(
        `UPDATE vijesti.moments SET score = $2, score_parts = $3::jsonb, score_reasons = $4::jsonb,
           score_version = $5, scored_at = $6 WHERE id = $1`,
        [
          id,
          score,
          'parts' in over ? over.parts : score === null ? null : '{"novelty":0.5}',
          'reasons' in over ? over.reasons : score === null ? null : '{"novelty":"x"}',
          'version' in over ? over.version : score === null ? null : 'score-moments/1+f1',
          'at' in over ? over.at : score === null ? null : new Date().toISOString(),
        ],
      );

    it('003: ocjena 0–1, s verzijom, sastavnicama i razlozima, nikad za odbačen citat', async () => {
      expect(await scoreCols()).toEqual([
        'score',
        'score_parts',
        'score_reasons',
        'score_run_id',
        'score_version',
        'scored_at',
      ]);
      const ok = Number((await moment({ start_ms: 1, end_ms: 2 })).rows[0]?.id);
      const failed = Number((await moment({ quote_check: 'failed', start_ms: 3, end_ms: 4 })).rows[0]?.id);
      await setScore(ok, 0);
      await setScore(ok, 1);
      await setScore(ok, 0.42);
      await expect(setScore(ok, 1.01)).rejects.toThrow(/moments_score_range/);
      await expect(setScore(ok, -0.01)).rejects.toThrow(/moments_score_range/);
      await expect(setScore(ok, 0.5, { version: null })).rejects.toThrow(/moments_score_consistent/);
      await expect(setScore(ok, 0.5, { parts: null })).rejects.toThrow(/moments_score_consistent/);
      await expect(setScore(ok, 0.5, { reasons: null })).rejects.toThrow(/moments_score_consistent/);
      await expect(setScore(ok, 0.5, { at: null })).rejects.toThrow(/moments_score_consistent/);
      await expect(setScore(ok, null, { version: 'v' })).rejects.toThrow(/moments_score_consistent/);
      await expect(setScore(ok, 0.5, { version: ' ' })).rejects.toThrow(/moments_score_version_check/);
      await expect(setScore(failed, 0.5)).rejects.toThrow(/moments_score_not_failed/);
      await setScore(ok, null);
    });

    it('003 dolje briše stupce i ocjene, gore ih vraća prazne; 001 score bez skale se briše', async () => {
      const id = Number((await moment({ start_ms: 1, end_ms: 2 })).rows[0]?.id);
      await setScore(id, 0.7);
      expect(await migrateDown(db, { steps: 3 })).toEqual([5, 4, 3]);
      expect(await scoreCols()).toEqual(['score']);
      const after = await db.query<{ score: number | null }>('SELECT score FROM vijesti.moments WHERE id = $1', [id]);
      expect(after.rows[0]?.score).toBeNull();
      // Bez skale (001/002) score može biti bilo što; 003 gore to briše jer nema verziju.
      await db.query('UPDATE vijesti.moments SET score = 7 WHERE id = $1', [id]);
      expect(await migrateUp(db)).toEqual([3, 4, 5]);
      const back = await db.query<{ score: number | null; score_version: string | null }>(
        'SELECT score, score_version FROM vijesti.moments WHERE id = $1',
        [id],
      );
      expect(back.rows[0]).toEqual({ score: null, score_version: null });
      const idx = await db.query(`SELECT 1 FROM pg_indexes WHERE indexname = 'moments_score_idx'`);
      expect(idx.rows).toHaveLength(1);
    });

    it('004: tokens_estimated na runs i tablice uzorka; dolje ih briše, gore vraća', async () => {
      const run = await db.query<{ tokens_estimated: boolean }>(
        `INSERT INTO vijesti.runs (step, model) VALUES ('extract', 'agy:m') RETURNING tokens_estimated`,
      );
      expect(run.rows[0]?.tokens_estimated).toBe(false);
      await db.query(
        `INSERT INTO vijesti.eval_sample (video_id, channel, episode_date, has_words, pick)
         VALUES ('a', 'kanal', '2026-11-01', true, 'fresh')`,
      );
      await expect(
        db.query(`INSERT INTO vijesti.eval_sample (video_id, channel, has_words, pick) VALUES ('b', 'k', true, 'x')`),
      ).rejects.toThrow(/check/i);
      await expect(
        db.query(
          `INSERT INTO vijesti.eval_channels (channel, listed, episodes_30d, window_end) VALUES ('k', 2, 3, '2026-11-06')`,
        ),
      ).rejects.toThrow(/check/i);
      expect(await migrateDown(db, { steps: 2 })).toEqual([5, 4]);
      const col = await db.query(
        `SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'vijesti' AND table_name = 'runs' AND column_name = 'tokens_estimated'`,
      );
      expect(col.rows).toHaveLength(0);
      expect((await tables(db)).filter((t) => t.startsWith('eval_'))).toEqual([]);
      expect(await migrateUp(db)).toEqual([4, 5]);
      expect((await tables(db)).filter((t) => t.startsWith('eval_'))).toEqual(['eval_channels', 'eval_sample']);
    });

    it('005: sadržaj verzije je sav ili ništa; verify traži sadržaj; dolje briše stupce, gore ih vraća', async () => {
      const s = await db.query<{ id: number }>(`INSERT INTO vijesti.stories (slug, title) VALUES ('p', 'P') RETURNING id`);
      const a = await db.query<{ id: number }>(
        `INSERT INTO vijesti.articles (story_id, format, slug) VALUES ($1, 'vijest', 'p') RETURNING id`,
        [s.rows[0]?.id],
      );
      const art = a.rows[0]?.id;
      // Urednička verzija bez strukture smije postojati (sve NULL).
      await db.query(`INSERT INTO vijesti.article_versions (article_id, version, title, body) VALUES ($1, 1, 'N', 'T')`, [art]);
      await db.query(
        `INSERT INTO vijesti.article_versions (article_id, version, title, body, lead, category, content, word_count, verify)
         VALUES ($1, 2, 'N', 'T', 'L', 'vijest-dana', '{}'::jsonb, 320, '{}'::jsonb)`,
        [art],
      );
      await expect(
        db.query(
          `INSERT INTO vijesti.article_versions (article_id, version, title, body, content) VALUES ($1, 3, 'N', 'T', '{}'::jsonb)`,
          [art],
        ),
      ).rejects.toThrow(/article_versions_content_consistent/);
      await expect(
        db.query(`INSERT INTO vijesti.article_versions (article_id, version, title, body, verify) VALUES ($1, 3, 'N', 'T', '{}'::jsonb)`, [
          art,
        ]),
      ).rejects.toThrow(/article_versions_verify_needs_content/);
      await expect(
        db.query(
          `INSERT INTO vijesti.article_versions (article_id, version, title, body, lead, category, content, word_count)
           VALUES ($1, 3, 'N', 'T', 'L', 'Društvo', '{}'::jsonb, 1)`,
          [art],
        ),
      ).rejects.toThrow(/check/i);
      expect(await migrateDown(db)).toEqual([5]);
      const cols = await db.query(
        `SELECT 1 FROM information_schema.columns
         WHERE table_schema = 'vijesti' AND table_name = 'article_versions' AND column_name IN ('content', 'verify', 'lead')`,
      );
      expect(cols.rows).toHaveLength(0);
      expect(await migrateUp(db)).toEqual([5]);
      const back = await db.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM vijesti.article_versions WHERE content IS NULL AND verify IS NULL`,
      );
      expect(back.rows[0]?.n).toBe(2);
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

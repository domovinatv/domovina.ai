// Generator „vijest iz podcasta” nad fixtureima: lažni LLM, PGlite, bez mreže.
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createSqlRunRecorder } from '../../db/runs.js';
import {
  parseVerifyArgs,
  parseWriteArgs,
  runExtractCli,
  runScoreCli,
  runVerifyCli,
  runWriteCli,
  UsageError,
  VIJESTI_ROOT,
} from '../cli.js';
import { createFakeLlmClient } from '../llm/fake.js';
import { parseLlmJson } from '../llm/validate.js';
import { NEWS_SCORE_THRESHOLD } from '../score/formula.js';
import { fixtureCdn, scoredDb as scoredFixtureDb } from '../test/scored-db.js';
import { fakeWriteResponse, createFakeWriteLlm } from './fake-llm.js';
import { CATEGORIES, PROMPT_VERSION, STIL_SHA256, SYSTEM_PROMPT, WORD_RANGE, WriteOutputSchema } from './prompt.js';
import { articleSlug, storySlug } from './store.js';
import { hrDate, slugify, splitSentences, wordCount } from './text.js';
import { prepareWrite, runWrite } from './vijest.js';

const VIDEO = 'MGLq9v3AtvE';
const CHANNEL = 'domovina_tv';
const cdn = fixtureCdn;
const scoredDb = () => scoredFixtureDb(VIDEO, CHANNEL);

describe('stilski vodič', () => {
  it('stil.md i sistemska uputa su usklađeni (oznake, kategorije, sha256)', () => {
    const stil = readFileSync(join(VIJESTI_ROOT, 'docs', 'stil.md'), 'utf8');
    const rules = [...stil.matchAll(/^\*\*(V\d+)\. /gm)].map((m) => m[1]);
    const prompt = [...SYSTEM_PROMPT.matchAll(/^(V\d+) /gm)].map((m) => m[1]);
    expect(rules).toHaveLength(14);
    expect(prompt).toEqual(rules);
    const cats = [...stil.matchAll(/^\| `([a-z-]+)` \|/gm)].map((m) => m[1]);
    expect(cats).toEqual([...CATEGORIES]);
    // Promjena vodiča traži pregled upute i novi STIL_SHA256 (i PROMPT_VERSION kad se mijenja pravilo).
    expect(createHash('sha256').update(stil).digest('hex')).toBe(STIL_SHA256);
  });
});

describe('tekst', () => {
  it('rečenice: kratice, redni brojevi, navodnici', () => {
    expect(splitSentences('Dr. Ivan Horvat kaže da je 11. kolovoza 2026. bilo hladno. Fra Ante se slaže.')).toEqual([
      'Dr. Ivan Horvat kaže da je 11. kolovoza 2026. bilo hladno.',
      'Fra Ante se slaže.',
    ]);
    expect(splitSentences('Rekao je „Ovo je kraj. Novi početak.” Zatim je otišao.')).toEqual([
      'Rekao je „Ovo je kraj. Novi početak.”',
      'Zatim je otišao.',
    ]);
    expect(splitSentences('Prema riječima govornika Fr. Michael Kong, to je to. Kraj?')).toEqual([
      'Prema riječima govornika Fr. Michael Kong, to je to.',
      'Kraj?',
    ]);
  });

  it('riječi, slug, datum', () => {
    expect(wordCount('Pater Stjepan-Ivan, 8,000 ljudi; don’t')).toBe(5);
    expect(slugify('Đuro Šimić: „Velika” promjena u Zagrebu!')).toBe('duro-simic-velika-promjena-u-zagrebu');
    expect(articleSlug('Naslov', 'a_B-1')).toBe('naslov-a_B-1');
    expect(storySlug('a_B-1')).toBe('video-a_B-1');
    expect(hrDate('2026-11-06')).toBe('6. studenoga 2026.');
    expect(hrDate(null)).toBeNull();
  });
});

describe('runWrite nad fixtureom', () => {
  let db: PGlite;
  beforeEach(async () => {
    db = await scoredDb();
  });
  afterEach(async () => {
    await db.close();
  });

  it('lažni generator prolazi shemu; verzija 1 s izvorima, sadržajem i run zapisom', async () => {
    const prep = await prepareWrite({ cdn: cdn(), db }, { videoId: VIDEO, channel: CHANNEL });
    expect(prep.prompt).not.toBeNull();
    expect(prep.moments.length).toBeGreaterThan(0);
    expect(prep.episode).toMatchObject({ videoId: VIDEO, channel: CHANNEL, lang: 'hr' });
    const parsed = parseLlmJson(fakeWriteResponse(prep.prompt ?? ''), WriteOutputSchema);
    expect(CATEGORIES).toContain(parsed.category);

    const recorder = createSqlRunRecorder(db);
    const r = await runWrite({ cdn: cdn(), llm: createFakeWriteLlm(recorder), recorder, db }, { videoId: VIDEO, channel: CHANNEL });
    expect(r).toMatchObject({ calls: 1, outOfRange: false, missingRefs: [] });
    expect(r.saved?.version).toBe(1);
    expect(r.wordCount).toBeGreaterThanOrEqual(WORD_RANGE.min);
    expect(r.wordCount).toBeLessThanOrEqual(WORD_RANGE.max);

    const v = await db.query<{
      created_by: string;
      prompt_version: string;
      category: string;
      word_count: number;
      body: string;
      content: { blocks: { type: string; moment_id?: number }[]; episode: { videoId: string } };
      run_status: string;
      format: string;
      lang: string;
      slug: string;
    }>(
      `SELECT v.created_by, v.prompt_version, v.category, v.word_count, v.body, v.content, r.status AS run_status,
              a.format, a.lang, s.slug
       FROM vijesti.article_versions v JOIN vijesti.articles a ON a.id = v.article_id
       JOIN vijesti.stories s ON s.id = a.story_id JOIN vijesti.runs r ON r.id = v.run_id`,
    );
    const row = v.rows[0];
    expect(v.rows).toHaveLength(1);
    expect(row).toMatchObject({
      created_by: 'engine:write',
      prompt_version: PROMPT_VERSION,
      run_status: 'ok',
      format: 'vijest',
      lang: 'hr',
      slug: `video-${VIDEO}`,
      word_count: r.wordCount,
    });
    const src = await db.query<{ moment_id: number; position: number; quote: string }>(
      `SELECT s.moment_id::int AS moment_id, s.position, m.quote FROM vijesti.article_sources s
       JOIN vijesti.moments m ON m.id = s.moment_id ORDER BY s.position`,
    );
    expect(src.rows.map((x) => x.position)).toEqual(prep.moments.map((_, i) => i + 1));
    // Citat-blok je referenca na izvor; tekst citata u `body` dolazi iz moments.quote.
    const quoteIds = (row?.content.blocks ?? []).filter((b) => b.type === 'quote').map((b) => b.moment_id);
    expect(quoteIds.length).toBeGreaterThan(0);
    for (const id of quoteIds) {
      const m = src.rows.find((x) => x.moment_id === id);
      expect(m).toBeDefined();
      expect(row?.body).toContain(`„${m?.quote ?? ''}”`);
    }
    const scores = await db.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM vijesti.moments WHERE video_id = $1 AND score >= $2`,
      [VIDEO, NEWS_SCORE_THRESHOLD],
    );
    expect(prep.eligible).toBe(scores.rows[0]?.n);

    // Druga generacija = verzija 2 istog članka.
    const again = await runWrite({ cdn: cdn(), llm: createFakeWriteLlm(recorder), recorder, db }, { videoId: VIDEO, channel: CHANNEL });
    expect(again.saved).toMatchObject({ articleId: r.saved?.articleId, version: 2 });
  });

  it('epizoda bez trenutka iznad praga: nema članka, poziva ni runa', async () => {
    await db.query('UPDATE vijesti.moments SET score = $1 WHERE score IS NOT NULL', [NEWS_SCORE_THRESHOLD - 0.01]);
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeWriteLlm(recorder);
    const r = await runWrite({ cdn: cdn(), llm, recorder, db }, { videoId: VIDEO, channel: CHANNEL });
    expect(r).toMatchObject({ saved: null, calls: 0, runId: null, eligible: 0 });
    expect(llm.calls).toBe(0);
    expect((await db.query(`SELECT 1 FROM vijesti.runs WHERE step = 'write'`)).rows).toHaveLength(0);
    expect((await db.query('SELECT 1 FROM vijesti.articles')).rows).toHaveLength(0);
  });

  it('izlaz izvan sheme (kategorija izvan popisa): poziv neuspio, ništa upisano', async () => {
    const recorder = createSqlRunRecorder(db);
    const bad = JSON.stringify({ title: 'Naslov', lead: 'Lead.', body: [{ type: 'p', text: 'a' }, { type: 'quote', moment: 1 }], category: 'zabava' });
    const llm = createFakeLlmClient({ recorder, byName: { 'write-vijest': { text: bad, usage: { tokensIn: 1, tokensOut: 1 } } } });
    await expect(runWrite({ cdn: cdn(), llm, recorder, db }, { videoId: VIDEO, channel: CHANNEL })).rejects.toThrow(/shemu/);
    const runs = await db.query<{ status: string; failed_calls: number }>(`SELECT status, failed_calls FROM vijesti.runs WHERE step = 'write'`);
    expect(runs.rows).toEqual([{ status: 'failed', failed_calls: 1 }]);
    expect((await db.query('SELECT 1 FROM vijesti.article_versions')).rows).toHaveLength(0);
  });
});

describe('CLI write i verify', () => {
  it('parseWriteArgs i parseVerifyArgs', () => {
    expect(parseWriteArgs(['write', 'abc', '--fake', '--channel', 'k', '--db', '/x'])).toEqual({
      videoId: 'abc',
      fake: true,
      channel: 'k',
      db: '/x',
    });
    expect(parseVerifyArgs(['verify', '12', '--db', '/x'])).toEqual({ target: { articleId: 12 }, fake: false, db: '/x' });
    expect(parseVerifyArgs(['verify', 'MGLq9v3AtvE']).target).toEqual({ videoId: 'MGLq9v3AtvE' });
    expect(() => parseVerifyArgs(['verify', 'a', '--channel', 'k'])).toThrow(UsageError);
    expect(() => parseWriteArgs(['write'])).toThrow(UsageError);
  });

  it('extract → score → write → verify, sve --fake u istoj PGlite datoteci', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vijesti-write-cli-'));
    try {
      const dbPath = join(dir, 'db');
      await runExtractCli({ videoId: VIDEO, fake: true, db: dbPath });
      await runScoreCli({ videoId: VIDEO, fake: true, db: dbPath });
      const w = await runWriteCli({ videoId: VIDEO, fake: true, db: dbPath });
      expect(w.saved?.version).toBe(1);
      const v = await runVerifyCli({ target: { videoId: VIDEO }, fake: true, db: dbPath });
      expect(v).toMatchObject({ articleId: w.saved?.articleId, baseVersion: 1 });
      expect(v.saved.version).toBe(2);
      expect(v.result.summary.sentences).toBeGreaterThan(2);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

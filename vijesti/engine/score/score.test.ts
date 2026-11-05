// Ocjena vijesti (odluke 306–313): obilježja, formula, shema izlaza, tok nad
// PGlite i fixtureima, idempotentnost i izlaz modela koji ne odgovara trenucima.
import { readFileSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { parseScoreArgs, PERSONS_FIXTURE, runExtractCli, runScoreCli, UsageError } from '../cli.js';
import { createCdnClient } from '../cdn/loader.js';
import type { ChannelListing } from '../cdn/schemas.js';
import { createFakeExtractLlm } from '../extract/fake-llm.js';
import { prepareExtract, runExtract } from '../extract/run.js';
import { estimatePrompts } from '../llm/estimate.js';
import { createFakeLlmClient } from '../llm/fake.js';
import { toGeminiSchema } from '../llm/gemini.js';
import { MemoryRunRecorder } from '../llm/runs.js';
import { LlmSchemaError } from '../llm/types.js';
import { createFakeCdn, type FakeCdnOptions } from '../test/fake-cdn.js';
import { FIXTURES_DIR } from '../test/fixtures-refresh.js';
import { buildNoveltyContext, findChannel } from './context.js';
import { createFakeScoreLlm, fakeScoreResponse } from './fake-llm.js';
import { concreteFeatures, concreteFeatureScore } from './features.js';
import { combineScore, personScore, SCORE_VERSION, WEIGHTS } from './formula.js';
import { buildPersonIndex, parsePersons, type Person } from './persons.js';
import { PROMPT_NAME, PROMPT_VERSION, ScoreOutputSchema, type MomentScore } from './prompt.js';
import { matchScores, prepareScore, runScore, ScoreMismatchError } from './run.js';

const PERSONS = parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons;
const persons = buildPersonIndex(PERSONS);
const cdn = (o: FakeCdnOptions = {}) => createCdnClient({ fetch: createFakeCdn(o).fetch });

async function freshDb(): Promise<PGlite> {
  const db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  return db;
}

async function extract(db: PGlite, ids: string[]): Promise<void> {
  for (const id of ids) {
    const recorder = createSqlRunRecorder(db);
    await runExtract({ cdn: cdn(), llm: createFakeExtractLlm(recorder), recorder, db }, { videoId: id });
  }
}

interface ScoredRow {
  id: number;
  score: number | null;
  score_version: string | null;
  score_parts: Record<string, unknown> | null;
  score_reasons: Record<string, string> | null;
  speaker_name: string | null;
  quote_check: string;
}

async function rows(db: PGlite, videoId: string): Promise<ScoredRow[]> {
  const r = await db.query<ScoredRow>(
    `SELECT id::int AS id, score, score_version, score_parts, score_reasons, speaker_name, quote_check
     FROM vijesti.moments WHERE video_id = $1 ORDER BY start_ms, id`,
    [videoId],
  );
  return r.rows;
}

const score = (id: number, over: Partial<MomentScore> = {}): MomentScore => ({
  id,
  novelty: 0.5,
  concreteness: 0.5,
  speaker: 0.5,
  public_role: null,
  reasons: { novelty: 'n', concreteness: 'c', speaker: 's' },
  ...over,
});
const text = (scores: unknown[]) => ({ text: JSON.stringify({ scores }), usage: { tokensIn: 1000, tokensOut: 200 } });
const range = (n: number) => Array.from({ length: n }, (_, i) => i + 1);

describe('konkretnost: obilježja (odluka 309)', () => {
  it('brojka, broj riječima, datum, najava; godina je datum, ne brojka', () => {
    expect(concreteFeatures('Plaće su porasle 12 posto u 2025. godini.', [])).toEqual({
      numbers: 1,
      numberWords: 1,
      dates: 1,
      entities: 0,
      announcement: false,
    });
    expect(concreteFeatures('Vlada je najavila novi zakon u studenom.', ['Vlada'])).toMatchObject({
      dates: 1,
      entities: 1,
      announcement: true,
    });
    expect(concreteFeatures('They banned it in March, after the election.', [])).toMatchObject({
      dates: 1,
      announcement: true,
    });
    expect(concreteFeatures('Sastanak je 12. 3. u Zagrebu.', [])).toMatchObject({ dates: 1 });
  });

  it('lažni pogoci: student, siječe, banka, „jedan od”, „one of”', () => {
    const f = concreteFeatures('Studenti kažu da jedan od njih siječe kruh, a banka šuti; one of them agrees.', []);
    expect(f).toEqual({ numbers: 0, numberWords: 0, dates: 0, entities: 0, announcement: false });
  });

  it('entiteti bez duplikata; ocjena obilježja 0–1', () => {
    expect(concreteFeatures('x', ['HNB', 'hnb', ' ', 'Zagreb']).entities).toBe(2);
    const none = concreteFeatures('Mislim da je to lijepo.', []);
    expect(concreteFeatureScore(none)).toBe(0);
    expect(concreteFeatureScore({ ...none, entities: 1 })).toBe(0.1);
    expect(concreteFeatureScore({ numbers: 3, numberWords: 0, dates: 2, entities: 5, announcement: true })).toBe(1);
  });
});

describe('formula (odluka 310)', () => {
  const none = concreteFeatures('Mislim da je to lijepo.', []);

  it('težine se zbrajaju u 1; krajnosti daju 0 i 1', () => {
    expect(WEIGHTS.novelty + WEIGHTS.concreteness + WEIGHTS.speaker).toBeCloseTo(1, 12);
    const all = { numbers: 1, numberWords: 0, dates: 1, entities: 2, announcement: true };
    const top = combineScore(
      { novelty: 1, concreteness: 1, speaker: 1, public_role: 'ministar' },
      all,
      { slug: 's', name: 'S', episodes: 9, channels: 5 },
      'S',
    );
    expect(top.score).toBe(1);
    expect(combineScore({ novelty: 0, concreteness: 0, speaker: 0, public_role: null }, none, null, null).score).toBe(0);
  });

  it('primjer: 0,45·0,8 + 0,4·(0,6·0,5 + 0,4·0,35) + 0,15·(0,5·0,2) = 0,551', () => {
    const f = concreteFeatures('Bilo je 300 ljudi.', []);
    expect(concreteFeatureScore(f)).toBe(0.35);
    const r = combineScore({ novelty: 0.8, concreteness: 0.5, speaker: 0.2, public_role: null }, f, null, 'Ana Anić');
    expect(r.score).toBe(0.551);
    expect(r.parts).toMatchObject({
      novelty: 0.8,
      concreteness: 0.44,
      speaker: 0.1,
      llm: { novelty: 0.8, concreteness: 0.5, speaker: 0.2 },
      features: { numbers: 1, score: 0.35 },
      person: null,
      speaker_name: 'Ana Anić',
    });
  });

  it('osoba iz kataloga: 0,5 + 0,5·min(1, kanali/5)', () => {
    expect(personScore(null)).toBe(0);
    expect(personScore({ slug: 'a', name: 'A', episodes: 3, channels: 1 })).toBe(0.6);
    expect(personScore({ slug: 'a', name: 'A', episodes: 21, channels: 12 })).toBe(1);
  });

  it('sastavnica izvan 0–1 baca (zadnja ograda iza sheme)', () => {
    expect(() => combineScore({ novelty: 1.2, concreteness: 0, speaker: 0, public_role: null }, none, null, null)).toThrow(
      RangeError,
    );
    expect(() => combineScore({ novelty: Number.NaN, concreteness: 0, speaker: 0, public_role: null }, none, null, null)).toThrow(
      RangeError,
    );
  });
});

describe('shema izlaza score-moments', () => {
  it('JSON Schema za Gemini nosi granice 0–1', () => {
    const json = JSON.stringify(toGeminiSchema(ScoreOutputSchema));
    expect(json).toContain('"minimum":0');
    expect(json).toContain('"maximum":1');
  });

  it('lažni klijent: valjan izlaz prolazi; ocjena izvan 0–1 i prazan razlog padaju na shemi', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: 'fake' });
    const bad = [
      [score(1, { novelty: 1.5 })],
      [score(1, { concreteness: -0.1 })],
      [score(1, { reasons: { novelty: ' ', concreteness: 'c', speaker: 's' } })],
      [{ ...score(1), reasons: undefined }],
      [score(0)],
    ];
    const llm = createFakeLlmClient({ recorder, queue: [text([score(1)]), ...bad.map((b) => text(b))] });
    const req = { prompt: 'p', schema: ScoreOutputSchema, runId, name: 'nepoznato' };
    expect((await llm.generate(req)).scores).toHaveLength(1);
    for (let i = 0; i < bad.length; i++) await expect(llm.generate(req)).rejects.toBeInstanceOf(LlmSchemaError);
    expect(recorder.get(runId)).toMatchObject({ calls: 6, failedCalls: 5 });
  });

  it('matchScores: nepostojeći i ponovljen broj bacaju, izostavljeni se vraćaju', () => {
    expect(matchScores([score(1), score(2)], 2).missing).toEqual([]);
    expect(matchScores([score(2)], 3).missing).toEqual([1, 3]);
    expect(() => matchScores([score(1), score(4)], 3)).toThrow(/nepostojeći t4/);
    expect(() => matchScores([score(1), score(1)], 3)).toThrow(/ponovljeni t1/);
  });
});

describe('runScore nad fixtureima (PGlite, lažni LLM)', () => {
  let db: PGlite;
  beforeEach(async () => {
    db = await freshDb();
  });
  afterEach(async () => {
    await db.close();
  });

  it('b-nls1ck8EE: jedan poziv, svi prihvaćeni trenuci ocijenjeni, kontekst ranije epizode kanala', async () => {
    await extract(db, ['MGLq9v3AtvE', 'b-nls1ck8EE']);
    // Odbačen citat se ne ocjenjuje i ne ide u prompt.
    await db.query(
      `INSERT INTO vijesti.moments (video_id, start_ms, end_ms, speaker, quote, quote_check, reject_reason, claim)
       VALUES ('b-nls1ck8EE', 1, 2, 'SPEAKER_01', 'izmišljen citat', 'failed', 'not_found', 'x')`,
    );
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeScoreLlm(recorder);
    const prep = await prepareScore({ cdn: cdn(), db, persons }, { videoId: 'b-nls1ck8EE' });
    expect(prep.moments).toHaveLength(10);
    expect(prep.prompt?.match(/^\[t\d+ /gm)).toHaveLength(10);
    expect(prep.prompt).not.toContain('izmišljen citat');
    // Kontekst: MGLq9v3AtvE (26.2.) je ranija epizoda kanala domovina_tv.
    expect(prep.context.prior.map((p) => p.videoId)).toEqual(['MGLq9v3AtvE']);
    expect(prep.context.sources).toEqual({ summary: 1, listing: 0 });
    expect(prep.context.priorMoments).toHaveLength(12);
    expect(prep.prompt).toContain('[2026-02-26]');
    expect(prep.prompt).toContain('- SPEAKER_01: Goran Jeras (gost u ovoj epizodi)');

    const r = await runScore({ cdn: cdn(), llm, recorder, db, persons }, { videoId: 'b-nls1ck8EE' });
    expect(r).toMatchObject({
      channel: 'domovina_tv',
      calls: 1,
      moments: 10,
      scored: 10,
      missing: [],
      cleared: 0,
      priorEpisodes: 1,
      priorMoments: 12,
      speakersMatched: 0,
      speakers: 1,
      version: SCORE_VERSION,
    });
    expect(llm.calls).toBe(1);
    expect(r.ranked.map((m) => m.score)).toEqual([...r.ranked.map((m) => m.score)].sort((a, b) => b - a));
    const run = await db.query<{ step: string; prompt_version: string; status: string; calls: number; video_id: string }>(
      'SELECT step, prompt_version, status, calls, video_id FROM vijesti.runs WHERE id = $1',
      [r.runId],
    );
    expect(run.rows[0]).toEqual({
      step: 'score',
      prompt_version: PROMPT_VERSION,
      status: 'ok',
      calls: 1,
      video_id: 'b-nls1ck8EE',
    });
    const got = await rows(db, 'b-nls1ck8EE');
    for (const m of got) {
      if (m.quote_check === 'failed') {
        expect(m.score).toBeNull();
        continue;
      }
      expect(m.score).toBeGreaterThanOrEqual(0);
      expect(m.score).toBeLessThanOrEqual(1);
      expect(m.score_version).toBe('score-moments/1+f1');
      expect(m.score_parts).toMatchObject({ speaker_name: 'Goran Jeras', person: null, weights: WEIGHTS });
      expect(Object.keys(m.score_reasons ?? {}).sort()).toEqual(['concreteness', 'novelty', 'speaker']);
      expect(m.speaker_name).toBe('Goran Jeras');
    }
  });

  it('ponovno ocjenjivanje je idempotentno: iste ocjene, isti broj redaka, novi run', async () => {
    await extract(db, ['MGLq9v3AtvE']);
    const recorder = createSqlRunRecorder(db);
    const deps = { cdn: cdn(), llm: createFakeScoreLlm(recorder), recorder, db, persons };
    const a = await runScore(deps, { videoId: 'MGLq9v3AtvE' });
    const first = await rows(db, 'MGLq9v3AtvE');
    const b = await runScore(deps, { videoId: 'MGLq9v3AtvE' });
    const second = await rows(db, 'MGLq9v3AtvE');
    expect(a).toMatchObject({ scored: 12, cleared: 0, priorEpisodes: 0 });
    expect(b).toMatchObject({ scored: 12, cleared: 12 });
    expect(b.runId).toBe((a.runId ?? 0) + 1);
    expect(second.map((m) => [m.id, m.score])).toEqual(first.map((m) => [m.id, m.score]));
    expect(second).toHaveLength(12);
  });

  it('epizoda bez trenutaka: nema poziva ni runa', async () => {
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeScoreLlm(recorder);
    const r = await runScore({ cdn: cdn(), llm, recorder, db, persons }, { videoId: 'x3w2BVZJ9vQ' });
    expect(r).toMatchObject({ runId: null, calls: 0, moments: 0, scored: 0, channel: 'catholic_futurist' });
    expect(llm.calls).toBe(0);
    const runs = await db.query(`SELECT 1 FROM vijesti.runs WHERE step = 'score'`);
    expect(runs.rows).toHaveLength(0);
  });

  it('nepostojeći ili ponovljen id: izlaz odbijen cijeli, run failed, stare ocjene ostaju', async () => {
    await extract(db, ['MGLq9v3AtvE']);
    const recorder = createSqlRunRecorder(db);
    await runScore({ cdn: cdn(), llm: createFakeScoreLlm(recorder), recorder, db, persons }, { videoId: 'MGLq9v3AtvE' });
    const before = await rows(db, 'MGLq9v3AtvE');
    const llm = createFakeLlmClient({
      recorder,
      queue: [text([...range(12).map((n) => score(n)), score(13)]), text([...range(12).map((n) => score(n)), score(5)])],
    });
    for (const msg of [/nepostojeći t13/, /ponovljeni t5/]) {
      const err = await runScore({ cdn: cdn(), llm, recorder, db, persons }, { videoId: 'MGLq9v3AtvE' }).catch(
        (e: unknown) => e,
      );
      expect(err).toBeInstanceOf(ScoreMismatchError);
      expect((err as Error).message).toMatch(msg);
    }
    expect(await rows(db, 'MGLq9v3AtvE')).toEqual(before);
    const runs = await db.query<{ status: string; error: string; calls: number }>(
      `SELECT status, error, calls FROM vijesti.runs WHERE step = 'score' ORDER BY id`,
    );
    expect(runs.rows.map((r) => r.status)).toEqual(['ok', 'failed', 'failed']);
    expect(runs.rows[1]?.error).toMatch(/t13/);
    expect(llm.requests.map((q) => q.name)).toEqual([PROMPT_NAME, PROMPT_NAME]);
  });

  it('izostavljen trenutak ostaje bez ocjene (i bez stare), run failed s popisom', async () => {
    await extract(db, ['MGLq9v3AtvE']);
    const recorder = createSqlRunRecorder(db);
    await runScore({ cdn: cdn(), llm: createFakeScoreLlm(recorder), recorder, db, persons }, { videoId: 'MGLq9v3AtvE' });
    const llm = createFakeLlmClient({ recorder, queue: [text(range(12).filter((n) => n !== 4).map((n) => score(n)))] });
    const r = await runScore({ cdn: cdn(), llm, recorder, db, persons }, { videoId: 'MGLq9v3AtvE' });
    expect(r).toMatchObject({ scored: 11, missing: [4], cleared: 12 });
    const got = await rows(db, 'MGLq9v3AtvE');
    expect(got.map((m) => m.score === null)).toEqual(range(12).map((n) => n === 4));
    const run = await db.query<{ status: string; error: string }>('SELECT status, error FROM vijesti.runs WHERE id = $1', [
      r.runId,
    ]);
    expect(run.rows[0]).toEqual({ status: 'failed', error: '1 trenutaka bez ocjene: t4' });
  });

  it('ocjena izvan 0–1 od modela: LlmSchemaError, poziv neuspio, ništa upisano', async () => {
    await extract(db, ['MGLq9v3AtvE']);
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeLlmClient({ recorder, queue: [text(range(12).map((n) => score(n, { novelty: n === 3 ? 1.5 : 0.5 })))] });
    await expect(
      runScore({ cdn: cdn(), llm, recorder, db, persons }, { videoId: 'MGLq9v3AtvE' }),
    ).rejects.toBeInstanceOf(LlmSchemaError);
    expect((await rows(db, 'MGLq9v3AtvE')).every((m) => m.score === null)).toBe(true);
    const run = await db.query<{ status: string; calls: number; failed_calls: number; tokens_in: number }>(
      `SELECT status, calls, failed_calls, tokens_in::int AS tokens_in FROM vijesti.runs WHERE step = 'score'`,
    );
    // Tokeni neuspjelog poziva su plaćeni i broje se (odluka 107).
    expect(run.rows[0]).toEqual({ status: 'failed', calls: 1, failed_calls: 1, tokens_in: 1000 });
  });

  it('govornik iz kataloga: prompt ga navodi, ocjena nosi osobu', async () => {
    await extract(db, ['b-nls1ck8EE']);
    const extra: Person = { slug: 'goran-jeras', name: 'Goran Jeras', episode_count: 3, channel_count: 2 };
    const idx = buildPersonIndex([...PERSONS, extra]);
    const recorder = createSqlRunRecorder(db);
    const r = await runScore(
      { cdn: cdn(), llm: createFakeScoreLlm(recorder), recorder, db, persons: idx },
      { videoId: 'b-nls1ck8EE', channel: 'domovina_tv' },
    );
    expect(r.speakersMatched).toBe(1);
    const got = await rows(db, 'b-nls1ck8EE');
    expect(got[0]?.score_parts).toMatchObject({
      person: { slug: 'goran-jeras', episodes: 3, channels: 2, score: 0.7 },
      llm: { speaker: 0.6 },
      speaker: 0.65,
    });
    const prep = await prepareScore({ cdn: cdn(), db, persons: idx }, { videoId: 'b-nls1ck8EE' });
    expect(prep.prompt).toContain('u katalogu osoba: Goran Jeras, 3 epizoda na 2 kanala');
  });
});

describe('kontekst novosti (odluka 307)', () => {
  const base = JSON.parse(readFileSync(join(FIXTURES_DIR, 'channels', 'domovina_tv.json'), 'utf8')) as ChannelListing;
  const target = base.videos.find((v) => v.id === 'b-nls1ck8EE');
  const v = (id: string, date: string | null, abstract = `Sažetak ${id}.`) => ({
    ...target,
    id,
    title: `Naslov ${id}`,
    title_hr: `Naslov ${id}`,
    date,
    abstract,
  });
  const listing: ChannelListing = {
    ...base,
    videos: [
      v('later000001', '2026-04-01'),
      v('b-nls1ck8EE', '2026-03-26'),
      v('samedate001', '2026-03-26'),
      ...range(10).map((n) => v(`synthetic${String(n).padStart(2, '0')}`, `2026-03-${String(n).padStart(2, '0')}`, n === 10 ? 'x'.repeat(500) : `Sažetak ${String(n)}.`)),
      v('nodate00001', null),
      ...base.videos.filter((x) => x.id === 'MGLq9v3AtvE'),
    ],
  };
  const overrides = { 'channels/data/domovina_tv.json': JSON.stringify(listing) };

  it('zadnjih 8 strogo ranijih, najnovije prvo; bez summaryja točke iz listinga; tvrdnje iz SVIH ranijih', async () => {
    const db = await freshDb();
    try {
      await extract(db, ['MGLq9v3AtvE']);
      const c = cdn({ overrides });
      const ctx = await buildNoveltyContext({ cdn: c, db }, { videoId: 'b-nls1ck8EE', listing });
      expect(ctx.date).toBe('2026-03-26');
      expect(ctx.prior.map((p) => p.videoId)).toEqual(
        [10, 9, 8, 7, 6, 5, 4, 3].map((n) => `synthetic${String(n).padStart(2, '0')}`),
      );
      expect(ctx.sources).toEqual({ summary: 0, listing: 8 });
      expect(ctx.prior[0]?.points[0]).toHaveLength(401);
      expect(ctx.prior[1]?.points).toEqual(['Sažetak 9.']);
      // MGLq9v3AtvE nije među 8 epizoda, ali njegove tvrdnje jesu (raniji datum).
      expect(ctx.priorMoments).toHaveLength(12);
      expect(ctx.priorMoments.every((m) => m.date === '2026-02-26')).toBe(true);

      const fewer = await buildNoveltyContext({ cdn: c, db }, { videoId: 'b-nls1ck8EE', listing, priorEpisodes: 2, priorMoments: 3 });
      expect(fewer.prior).toHaveLength(2);
      expect(fewer.priorMoments).toHaveLength(3);
      const undated = await buildNoveltyContext({ cdn: c, db }, { videoId: 'nodate00001', listing });
      expect(undated).toMatchObject({ date: null, prior: [], priorMoments: [] });
    } finally {
      await db.close();
    }
  });

  it('findChannel: po listinzima, uz ispravan i pogrešan slug', async () => {
    expect((await findChannel(cdn(), 'pIx_7N-6HJ4'))?.slug).toBe('mreze_rijeci');
    expect((await findChannel(cdn(), 'b-nls1ck8EE', 'domovina_tv'))?.slug).toBe('domovina_tv');
    expect(await findChannel(cdn(), 'nepostojeci1')).toBeNull();
    await expect(findChannel(cdn(), 'b-nls1ck8EE', 'mreze_rijeci')).rejects.toThrow(/nije u listingu/);
    await expect(findChannel(cdn(), 'b-nls1ck8EE', 'nema_kanala')).rejects.toThrow(/ne postoji/);
  });
});

describe('lažni score LLM i procjena bez poziva', () => {
  it('deterministički, prolazi shemu, ocjenjuje svaki trenutak iz prompta', async () => {
    const db = await freshDb();
    try {
      await extract(db, ['pIx_7N-6HJ4']);
      const prep = await prepareScore({ cdn: cdn(), db, persons }, { videoId: 'pIx_7N-6HJ4' });
      const prompt = prep.prompt ?? '';
      expect(fakeScoreResponse(prompt)).toBe(fakeScoreResponse(prompt));
      const out = ScoreOutputSchema.parse(JSON.parse(fakeScoreResponse(prompt)));
      expect(out.scores.map((s) => s.id)).toEqual(range(20));

      // Procjena za `npm run eval`: promptovi bez poziva modela.
      const ex = await prepareExtract(cdn(), { videoId: 'pIx_7N-6HJ4' });
      expect(ex.prompts).toHaveLength(10);
      const e = estimatePrompts(
        [...ex.prompts.map((p) => ({ prompt: p.prompt, system: ex.system })), { prompt, system: prep.system }],
        1000,
        { inPerMTok: 0.75, outPerMTok: 3.75 },
      );
      expect(e.calls).toBe(11);
      expect(e.tokensIn).toBeGreaterThan(1000);
      expect(e.costUsd).toBeGreaterThan(0);
    } finally {
      await db.close();
    }
  });
});

describe('CLI score', () => {
  it('parseScoreArgs', () => {
    expect(parseScoreArgs(['score', 'abc', '--fake', '--channel', 'domovina_tv', '--db', '/x'])).toEqual({
      videoId: 'abc',
      fake: true,
      channel: 'domovina_tv',
      db: '/x',
    });
    expect(() => parseScoreArgs(['score'])).toThrow(UsageError);
    expect(() => parseScoreArgs(['score', 'a', '--lang', 'hr'])).toThrow(UsageError);
    expect(() => parseScoreArgs(['extract', 'a'])).toThrow(UsageError);
  });

  it('extract --fake pa score --fake u istoj PGlite datoteci; drugo ocjenjivanje isto', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vijesti-score-cli-'));
    try {
      const dbPath = join(dir, 'db');
      await runExtractCli({ videoId: 'MGLq9v3AtvE', fake: true, db: dbPath });
      const a = await runScoreCli({ videoId: 'MGLq9v3AtvE', fake: true, db: dbPath });
      const b = await runScoreCli({ videoId: 'MGLq9v3AtvE', fake: true, db: dbPath });
      expect(a).toMatchObject({ calls: 1, scored: 12, channel: 'domovina_tv' });
      expect(b).toMatchObject({ calls: 1, scored: 12, cleared: 12 });
      expect(b.ranked.map((m) => m.score)).toEqual(a.ranked.map((m) => m.score));
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

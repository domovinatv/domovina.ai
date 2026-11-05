import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createCdnClient } from '../cdn/loader.js';
import { parseExtractArgs, runExtractCli, UsageError } from '../cli.js';
import { createFakeLlmClient } from '../llm/fake.js';
import { toGeminiSchema } from '../llm/gemini.js';
import { MemoryRunRecorder } from '../llm/runs.js';
import { LlmSchemaError } from '../llm/types.js';
import { createFakeCdn } from '../test/fake-cdn.js';
import { verifyQuote } from '../verify/quote.js';
import { createFakeExtractLlm, fakeExtractResponse } from './fake-llm.js';
import { QuoteLangError } from './lang.js';
import {
  buildExtractPrompt,
  CUE_LINE_RE,
  ExtractOutputSchema,
  PROMPT_NAME,
  PROMPT_VERSION,
} from './prompt.js';
import { runExtract } from './run.js';
import { splitSections } from './sections.js';

const cdn = () => createCdnClient({ fetch: createFakeCdn().fetch });

async function freshDb(): Promise<PGlite> {
  const db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  return db;
}

async function count(db: PGlite, videoId: string): Promise<number> {
  const r = await db.query<{ n: number }>(
    'SELECT count(*)::int AS n FROM vijesti.moments WHERE video_id = $1',
    [videoId],
  );
  return r.rows[0]?.n ?? -1;
}

describe('sekcije i prompt', () => {
  it('pIx_7N-6HJ4: 10 sekcija članka, svaki cue u točno jednoj, uzlazno', async () => {
    const ep = await cdn().loadEpisode('pIx_7N-6HJ4');
    const sections = splitSections(ep.cues, ep.article);
    expect(sections).toHaveLength(10);
    expect(sections[0]?.startMs).toBe(0);
    const ids = sections.flatMap((s) => s.cueIds);
    expect(ids).toEqual(ep.cues.map((_, i) => i));
    for (const s of sections) {
      for (const id of s.cueIds) {
        const c = ep.cues[id];
        expect(c && c.startMs >= s.startMs && c.startMs < s.endMs).toBe(true);
      }
    }
  });

  it('citat preko granice sekcije prolazi (provjera ne zna za sekcije, prozor 5 s)', async () => {
    const ep = await cdn().loadEpisode('pIx_7N-6HJ4');
    const sections = splitSections(ep.cues, ep.article);
    let n = 0;
    for (const [k, s] of sections.entries()) {
      const next = sections[k + 1];
      const a = s.cueIds.at(-1);
      const b = next?.cueIds[0];
      if (a === undefined || b === undefined) continue;
      const ca = ep.cues[a];
      const cb = ep.cues[b];
      if (!ca?.speaker || ca.speaker !== cb?.speaker || cb.startMs - ca.endMs > 5000) continue;
      const quote = `${ca.tokens.slice(-3).join(' ')} ${cb.tokens.slice(0, 3).join(' ')}`;
      // Model vidi samo svoju sekciju, pa navodi samo zadnji cue; citat izlazi u sljedeću.
      const r = verifyQuote(ep.cues, { cueFrom: a, cueTo: a, speaker: ca.speaker, quote });
      if (r.check === 'failed' && r.reason === 'negation_cut') continue;
      expect(r, quote).toMatchObject({ check: 'exact', span: { cueFrom: a, cueTo: b } });
      n++;
    }
    expect(n).toBeGreaterThan(0);
  });

  it('bez članka: fiksni prozori od 10 min', async () => {
    const ep = await cdn().loadEpisode('pIx_7N-6HJ4');
    const sections = splitSections(ep.cues, null);
    expect(sections.map((s) => s.startMs)).toEqual([0, 600_000]);
  });

  it('prompt: numerirani retci [cN HH:MM:SS SPEAKER_XX] i jezik snimke', async () => {
    const ep = await cdn().loadEpisode('x3w2BVZJ9vQ', { lang: 'en' });
    const section = splitSections(ep.cues, ep.article)[0];
    if (!section) throw new Error('nema sekcije');
    const prompt = buildExtractPrompt({ cues: ep.cues, section, lang: 'en', title: 'T' });
    expect(prompt).toContain('[c0 00:00:00 SPEAKER_00] For me, as a priest');
    expect(prompt).toContain('DOSLOVAN citat na engleskom');
    const lines = prompt.split('\n').filter((l) => CUE_LINE_RE.test(l));
    expect(lines).toHaveLength(section.cueIds.length);
    expect(PROMPT_VERSION).toMatch(/^extract-moments\/\d+$/);
  });
});

describe('poziv modela kroz zod shemu', () => {
  const valid = {
    moments: [
      {
        cue_from: 3,
        cue_to: 4,
        speaker: 'SPEAKER_01',
        quote: 'neki citat od pet riječi',
        claim: 'Sažetak.',
        topics: ['t'],
        entities: [],
      },
    ],
  };

  it('valjan izlaz prolazi, poziv se broji u run', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'fake' });
    const llm = createFakeLlmClient({
      recorder,
      byName: { [PROMPT_NAME]: { text: JSON.stringify(valid), usage: { tokensIn: 10, tokensOut: 5 } } },
    });
    const out = await llm.generate({ prompt: 'p', schema: ExtractOutputSchema, runId, name: PROMPT_NAME });
    expect(out.moments[0]?.cue_from).toBe(3);
    expect(recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 0 });
  });

  it.each([
    ['ms umjesto cueova', { moments: [{ ...valid.moments[0], cue_from: undefined, start_ms: 1000 }] }],
    ['krivi govornik', { moments: [{ ...valid.moments[0], speaker: 'Ivan' }] }],
    ['prazan citat', { moments: [{ ...valid.moments[0], quote: '   ' }] }],
    ['bez claim', { moments: [{ ...valid.moments[0], claim: undefined }] }],
    ['cue kao string', { moments: [{ ...valid.moments[0], cue_to: 'c4' }] }],
  ])('neispravan izlaz (%s) baca LlmSchemaError i broji se kao neuspio', async (_n, bad) => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'fake' });
    const llm = createFakeLlmClient({ recorder, queue: [{ text: JSON.stringify(bad), usage: { tokensIn: 1, tokensOut: 1 } }] });
    await expect(
      llm.generate({ prompt: 'p', schema: ExtractOutputSchema, runId, name: PROMPT_NAME }),
    ).rejects.toThrow(LlmSchemaError);
    expect(recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1 });
  });

  it('shema ide Geminiju kao JSON Schema bez polja za vrijeme', () => {
    const json = JSON.stringify(toGeminiSchema(ExtractOutputSchema));
    expect(json).toContain('"cue_from"');
    expect(json).toContain('"required"');
    expect(json).not.toMatch(/_ms"/);
  });

  it('lažni extract LLM je deterministički i prolazi shemu', () => {
    const prompt = '[c7 00:00:01 SPEAKER_00] kratko\n[c8 00:00:02 SPEAKER_01] ovo je dovoljno dug redak';
    const a = fakeExtractResponse(prompt);
    expect(a).toBe(fakeExtractResponse(prompt));
    expect(ExtractOutputSchema.parse(JSON.parse(a))).toMatchObject({
      moments: [{ cue_from: 8, cue_to: 8, speaker: 'SPEAKER_01', quote: 'ovo je dovoljno dug redak' }],
    });
  });
});

describe('runExtract --fake nad 5 fixturea (PGlite)', () => {
  let db: PGlite;
  beforeAll(async () => {
    db = await freshDb();
  });
  afterAll(async () => {
    await db.close();
  });

  const expected = {
    'pIx_7N-6HJ4': { lang: 'hr', sections: 10, moments: 20, exact: 20, srt_only: 0 },
    'P9sLks-f2mQ': { lang: 'hr', sections: 5, moments: 10, exact: 0, srt_only: 10 },
    x3w2BVZJ9vQ: { lang: 'en', sections: 9, moments: 18, exact: 18, srt_only: 0 },
    MGLq9v3AtvE: { lang: 'hr', sections: 6, moments: 12, exact: 12, srt_only: 0 },
    'b-nls1ck8EE': { lang: 'hr', sections: 5, moments: 10, exact: 10, srt_only: 0 },
  } as const;

  it.each(Object.entries(expected))('%s', async (id, e) => {
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeExtractLlm(recorder);
    const r = await runExtract({ cdn: cdn(), llm, recorder, db }, { videoId: id });
    expect(r).toMatchObject({
      lang: e.lang,
      sections: e.sections,
      calls: e.sections,
      failedSections: 0,
      moments: e.moments,
      byCheck: { exact: e.exact, fuzzy: 0, srt_only: e.srt_only, failed: 0 },
    });
    expect(await count(db, id)).toBe(e.moments);
    expect(await recorder.totals(r.runId)).toMatchObject({ status: 'ok', calls: e.sections, failedCalls: 0 });
    const run = await db.query<{ prompt_version: string; video_id: string }>(
      'SELECT prompt_version, video_id FROM vijesti.runs WHERE id = $1',
      [r.runId],
    );
    expect(run.rows[0]).toEqual({ prompt_version: PROMPT_VERSION, video_id: id });
    // Vrijeme trenutka je iz titla: unutar cuea koji je naveden.
    const rows = await db.query<{ start_ms: number; end_ms: number; quote_lang: string; run_id: string }>(
      'SELECT start_ms, end_ms, quote_lang, run_id::text FROM vijesti.moments WHERE video_id = $1',
      [id],
    );
    for (const row of rows.rows) {
      expect(row.end_ms).toBeGreaterThan(row.start_ms);
      expect(row.quote_lang).toBe(e.lang);
      expect(row.run_id).toBe(String(r.runId));
    }
  });

  it('dva pokretanja → isti broj redaka; citirani trenutak ostaje', async () => {
    const id = 'pIx_7N-6HJ4';
    const recorder = createSqlRunRecorder(db);
    const run = () => runExtract({ cdn: cdn(), llm: createFakeExtractLlm(recorder), recorder, db }, { videoId: id });
    await run();
    const before = await count(db, id);
    const cited = await db.query<{ id: number }>(
      'SELECT id FROM vijesti.moments WHERE video_id = $1 ORDER BY start_ms LIMIT 1',
      [id],
    );
    const momentId = cited.rows[0]?.id;
    const story = await db.query<{ id: number }>(
      `INSERT INTO vijesti.stories (slug, title) VALUES ('s2', 'S2') RETURNING id`,
    );
    const art = await db.query<{ id: number }>(
      `INSERT INTO vijesti.articles (story_id, format, slug) VALUES ($1, 'vijest', 's2') RETURNING id`,
      [story.rows[0]?.id],
    );
    const ver = await db.query<{ id: number }>(
      `INSERT INTO vijesti.article_versions (article_id, version, title, body) VALUES ($1, 1, 't', 'b') RETURNING id`,
      [art.rows[0]?.id],
    );
    await db.query('INSERT INTO vijesti.article_sources (version_id, moment_id) VALUES ($1, $2)', [
      ver.rows[0]?.id,
      momentId,
    ]);
    const second = await run();
    expect(await count(db, id)).toBe(before);
    expect(second).toMatchObject({ deleted: before - 1, inserted: before - 1, skipped: 1 });
    const still = await db.query('SELECT 1 FROM vijesti.moments WHERE id = $1', [momentId]);
    expect(still.rows).toHaveLength(1);
  });
});

describe('engleska epizoda x3w2BVZJ9vQ', () => {
  it('engine bira en; citat iz HR diarized.srt (prijevoda) ispada failed', async () => {
    const client = cdn();
    const en = await client.loadEpisode('x3w2BVZJ9vQ', { lang: 'en' });
    const hr = await client.loadEpisode('x3w2BVZJ9vQ');
    expect(en.srtFile).toBe('diarized.en.srt');
    expect(hr.srtFile).toBe('diarized.srt');
    const hrCue = hr.cues[2];
    if (!hrCue) throw new Error('nema cuea');
    // Isti indeks i govornik, tekst iz hrvatskog prijevoda.
    expect(verifyQuote(en.cues, { cueFrom: 2, cueTo: 2, speaker: hrCue.speaker ?? '', quote: hrCue.text })).toMatchObject({
      check: 'failed',
      reason: 'not_found',
    });

    const db = await freshDb();
    try {
      const recorder = createSqlRunRecorder(db);
      const answer = {
        moments: [
          { cue_from: 2, cue_to: 2, speaker: hrCue.speaker, quote: hrCue.text, claim: 'c', topics: [], entities: [] },
        ],
      };
      const llm = createFakeLlmClient({
        recorder,
        byName: { [PROMPT_NAME]: { text: JSON.stringify(answer), usage: { tokensIn: 0, tokensOut: 0 } } },
      });
      const r = await runExtract({ cdn: client, llm, recorder, db }, { videoId: 'x3w2BVZJ9vQ' });
      expect(r).toMatchObject({ lang: 'en', langSource: 'pair', srtFile: 'diarized.en.srt' });
      expect(r.byCheck).toEqual({ exact: 0, fuzzy: 0, srt_only: 0, failed: r.sections });
      expect(r.reasons).toEqual({ not_found: r.sections });
      const rows = await db.query<{ quote_check: string; reject_reason: string; quote_lang: string }>(
        `SELECT DISTINCT quote_check, reject_reason, quote_lang FROM vijesti.moments`,
      );
      expect(rows.rows).toEqual([{ quote_check: 'failed', reject_reason: 'not_found', quote_lang: 'en' }]);
      // Prompt je dobio engleski izvornik, ne prijevod.
      expect(llm.requests[0]?.prompt).toContain('For me, as a priest');
      expect(llm.requests[0]?.prompt).not.toContain('Za mene je to svećenik');
    } finally {
      await db.close();
    }
  });

  it('--lang hr se odbija prije ijednog poziva modela', async () => {
    const recorder = new MemoryRunRecorder();
    const llm = createFakeExtractLlm(recorder);
    const db = await freshDb();
    try {
      await expect(
        runExtract({ cdn: cdn(), llm, recorder, db }, { videoId: 'x3w2BVZJ9vQ', lang: 'hr' }),
      ).rejects.toThrow(QuoteLangError);
      await expect(
        runExtract({ cdn: cdn(), llm, recorder, db }, { videoId: 'pIx_7N-6HJ4', lang: 'en' }),
      ).rejects.toThrow(/titl nije na jeziku en/);
      expect(llm.calls).toBe(0);
      expect(recorder.runs.size).toBe(0);
    } finally {
      await db.close();
    }
  });
});

describe('neuspio izlaz modela', () => {
  it('sekcija s izlazom koji ne prolazi shemu: run failed, ostale sekcije se zapisuju', async () => {
    const db = await freshDb();
    try {
      const recorder = createSqlRunRecorder(db);
      const good = createFakeExtractLlm(recorder);
      let n = 0;
      const llm = {
        model: 'mješoviti',
        generate: ((req) => {
          n++;
          if (n === 1) return Promise.reject(new LlmSchemaError('loše', '{}'));
          return good.generate(req);
        }) as typeof good.generate,
      };
      const r = await runExtract({ cdn: cdn(), llm, recorder, db }, { videoId: 'b-nls1ck8EE' });
      expect(r).toMatchObject({ sections: 5, calls: 5, failedSections: 1, moments: 8 });
      expect(await recorder.totals(r.runId)).toMatchObject({ status: 'failed' });
    } finally {
      await db.close();
    }
  });
});

describe('CLI', () => {
  it('parseExtractArgs', () => {
    expect(parseExtractArgs(['extract', 'abc', '--fake', '--lang', 'en', '--db', '/x'])).toEqual({
      videoId: 'abc',
      fake: true,
      lang: 'en',
      db: '/x',
    });
    expect(() => parseExtractArgs(['extract'])).toThrow(UsageError);
    expect(() => parseExtractArgs(['extract', 'a', '--lang'])).toThrow(UsageError);
    expect(() => parseExtractArgs(['extract', 'a', '--nesto'])).toThrow(UsageError);
    expect(() => parseExtractArgs(['run', 'a'])).toThrow(UsageError);
  });

  it('extract --fake piše u PGlite datoteku; drugo pokretanje daje isti broj redaka', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vijesti-cli-'));
    try {
      const args = { videoId: 'MGLq9v3AtvE', fake: true, db: join(dir, 'db') };
      const a = await runExtractCli(args);
      const b = await runExtractCli(args);
      expect(a).toMatchObject({ moments: 12, inserted: 12, deleted: 0 });
      expect(b).toMatchObject({ moments: 12, inserted: 12, deleted: 12 });
      expect(b.runId).toBe(a.runId + 1);
      const db = new PGlite(args.db);
      try {
        expect(await count(db, 'MGLq9v3AtvE')).toBe(12);
      } finally {
        await db.close();
      }
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

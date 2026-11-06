// `npm run eval` i izvještaj nad 5 fixturea: bez mreže, bez LLM-a, bez tmuxa.
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import type { z } from 'zod';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createCdnClient } from '../cdn/loader.js';
import { UsageError } from '../cli.js';
import { createFakeExtractLlm } from '../extract/fake-llm.js';
import { runExtract } from '../extract/run.js';
import { MemoryRunRecorder } from '../llm/runs.js';
import { LlmResponseError, LlmTimeoutError, type GenerateRequest, type LlmClient } from '../llm/types.js';
import { PROMPT_NAME as SCORE_PROMPT_NAME } from '../score/prompt.js';
import { buildPersonIndex, parsePersons } from '../score/persons.js';
import { createFakeCdn, type FakeCdnOptions } from '../test/fake-cdn.js';
import { PERSONS_FIXTURE } from '../cli.js';
import {
  FIXTURE_CHANNELS,
  parseEvalArgs,
  parseReportArgs,
  runEvalCli,
  runDraftsCli,
  runReportCli,
  type EvalArgs,
} from './cli.js';
import { createFakeEvalLlm } from './fake-llm.js';
import { buildEvalReport, momentLink, readOnlyQuery, reproduceCommand } from './report.js';
import { BudgetExceededError, budgetedLlm, EXIT_OVER_BUDGET, runEval, type EvalOptions } from './run.js';
import { countInflow, sampleChannel, spread } from './sample.js';

const NOW = new Date('2026-11-06T12:00:00Z');
const cdn = (o: FakeCdnOptions = {}) => createCdnClient({ fetch: createFakeCdn(o).fetch });

let dir = '';
beforeEach(async () => {
  dir = await mkdtemp(join(tmpdir(), 'vijesti-eval-'));
});
afterEach(async () => {
  await rm(dir, { recursive: true, force: true });
});

function args(over: Partial<EvalArgs> = {}): EvalArgs {
  const db = join(dir, 'eval.pglite');
  return {
    channels: [...FIXTURE_CHANNELS],
    limit: 5,
    maxCalls: null,
    fake: true,
    dryRun: false,
    db,
    log: `${db}.log`,
    attempts: 2,
    resample: false,
    now: NOW,
    ...over,
  };
}

async function freshDb(): Promise<PGlite> {
  const db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  return db;
}

describe('uzorak', () => {
  it('spread i dotok 30 dana', () => {
    expect(spread(10, 4)).toEqual([0, 2, 5, 7]);
    expect(spread(3, 5)).toEqual([0, 1, 2]);
    expect(spread(0, 2)).toEqual([]);
    const v = (date: string | null) => ({ id: 'x', title: 't', date });
    // Prozor (2026-10-07, 2026-11-06]: granica 30 dana unatrag nije unutra.
    expect(countInflow([v('2026-11-06'), v('2026-10-08'), v('2026-10-07'), v(null), v('2026-11-07')], NOW)).toBe(2);
  });

  it('fixture domovina_tv: svježa i starija, obje s words.json', async () => {
    const s = await sampleChannel(cdn(), 'domovina_tv', { limit: 2, now: NOW });
    expect(s.episodes.map((e) => [e.videoId, e.pick, e.hasWords])).toEqual([
      ['b-nls1ck8EE', 'fresh', true],
      ['MGLq9v3AtvE', 'older', true],
    ]);
    expect(s.inflow).toMatchObject({ channel: 'domovina_tv', listed: 2, episodes30d: 0, windowEnd: '2026-11-06' });
    await expect(sampleChannel(cdn(), 'nema_kanala', { limit: 2, now: NOW })).rejects.toThrow(/ne postoji/);
  });

  it('deterministički; words.json ima prednost; bez titla se odbija; polovica bez dosta kandidata puni se iz druge', async () => {
    const ids = Array.from({ length: 10 }, (_, i) => `vid${String(i).padStart(4, '0')}x`);
    const listing = {
      version: '1.0',
      id: 'test_kanal',
      name: 'Test kanal',
      videos: ids.map((id, i) => ({ id, title: id, date: `2026-10-${String(30 - i).padStart(2, '0')}` })),
    };
    const bundle = (files: string[]) => JSON.stringify({ version: 1, files, inline: {} });
    const overrides: Record<string, string | null> = { 'channels/data/test_kanal.json': JSON.stringify(listing) };
    ids.forEach((id, i) => {
      const files = i === 1 ? [] : ['diarized.srt', ...(i % 2 === 1 || i === 6 ? ['words.json'] : [])];
      overrides[`data/${id}/episode.json`] = bundle(files);
    });
    const one = await sampleChannel(cdn({ overrides }), 'test_kanal', { limit: 4, now: NOW });
    const two = await sampleChannel(cdn({ overrides }), 'test_kanal', { limit: 4, now: NOW });
    expect(two).toEqual(one);
    // Svježa polovica 0–4, kandidati 0–3 (1 bez titla), words: 3; starija 5–9, kandidati 5,6,7,8.
    expect(one.episodes.map((e) => [e.videoId.slice(3, 7), e.pick, e.hasWords])).toEqual([
      ['0003', 'fresh', true],
      ['0000', 'fresh', false],
      ['0005', 'older', true],
      ['0006', 'older', true],
    ]);
    expect(one.rejected).toEqual([{ videoId: ids[1], channel: 'test_kanal', reason: 'nema diarized.srt' }]);
    expect(one.inflow.episodes30d).toBe(10);
    const big = await sampleChannel(cdn({ overrides }), 'test_kanal', { limit: 12, now: NOW });
    expect(big.episodes).toHaveLength(9);
  });
});

describe('npm run eval -- --fake (5 fixturea)', () => {
  it('suhi prolaz: procjena 50 poziva, ništa pozvano ni upisano', async () => {
    let made = 0;
    const res = await runEvalCli(args({ dryRun: true }), {
      llm: (r) => {
        made++;
        return createFakeEvalLlm(r);
      },
    });
    expect(res.exitCode).toBe(0);
    expect(made).toBe(0);
    expect(res.estimate).toMatchObject({ episodes: 5, todo: 5, done: 0, calls: 50, costUsd: 0 });
    expect(res.estimate.apiEquivalentUsd).toBeGreaterThan(0);
    expect(res.text).toMatch(/poziva: 50\n/);
    expect(res.text).toMatch(/--dry-run: ništa nije pozvano ni upisano/);
    expect(await runReportCli({ db: args().db, out: null, query: 'SELECT count(*) AS n FROM vijesti.eval_sample' })).toMatch(
      /\| 0 \|/,
    );
  });

  it('iznad --max-calls: exit 3 prije ijednog poziva', async () => {
    let made = 0;
    const res = await runEvalCli(args({ maxCalls: 49 }), {
      llm: (r) => {
        made++;
        return createFakeEvalLlm(r);
      },
    });
    expect(res.exitCode).toBe(EXIT_OVER_BUDGET);
    expect(made).toBe(0);
    expect(res.text).toMatch(/STOP: procjena 50 poziva je iznad --max-calls 49/);
  });

  it('pravi prolaz pa nastavak: drugi put 0 poziva; log ima redak po epizodi; izvještaj radi bez mreže', async () => {
    const a = args({ maxCalls: 50 });
    const first = await runEvalCli(a);
    expect(first.exitCode).toBe(0);
    expect(first.callsMade).toBe(50);
    expect(first.outcomes.map((o) => [o.videoId, o.extract, o.score, o.error])).toEqual([
      ['x3w2BVZJ9vQ', 'ok', 'ok', null],
      ['MGLq9v3AtvE', 'ok', 'ok', null],
      ['b-nls1ck8EE', 'ok', 'ok', null],
      ['P9sLks-f2mQ', 'ok', 'ok', null],
      ['pIx_7N-6HJ4', 'ok', 'ok', null],
    ]);
    const second = await runEvalCli(a);
    expect(second.callsMade).toBe(0);
    expect(second.estimate).toMatchObject({ done: 5, todo: 0, calls: 0 });
    expect(second.text).toMatch(/uzorak iz baze/);
    const log = (await readFile(a.log, 'utf8')).trim().split('\n');
    expect(log).toHaveLength(5);
    expect(log[0]).toMatch(/\tx3w2BVZJ9vQ\tcatholic_futurist\textract=ok\tscore=ok\twrite=ok\tverify=ok \(\d+ nepodržanih, \d+ uklonjeno\)\tpoziva=12\t$/);

    const out = join(dir, 'izvjestaj.md');
    const md = await runReportCli({ db: a.db, out, query: null }, NOW);
    expect(await readFile(out, 'utf8')).toBe(md);
    expect(md).toMatch(/^# Mjerenje F0/);
    expect(md).toMatch(/prag 0\.5 je PRIVREMEN \(odluka 315\)/);
    for (const h of [
      'Uzorak',
      'Trenuci po epizodi',
      'Provjera citata: ishod',
      'Provjera citata: razlog odbijanja',
      'Ocjena: udio iznad praga',
      '10 najboljih trenutaka',
      '10 najlošijih trenutaka',
      'Dotok i procjena „vijesti dnevno”',
      'Trošak i trajanje',
    ]) {
      expect(md).toContain(`\n## ${h}\n`);
    }
    expect(md).toContain('| catholic_futurist | x3w2BVZJ9vQ | 2026-08-11 | da | 18 | 18 | 18 |');
    expect(md).toContain('Izvučenih epizoda: 5 od 5.');
    expect(md.match(/^\d+\. \*\*0\.\d+\*\* · .* · https:\/\/domovina\.ai\/v\/[\w-]+\/t\/\d+$/gm)).toHaveLength(20);
    expect(md).toContain('- mreze_rijeci: 0.03 epizoda dnevno × 1/1 epizoda uzorka s vijesti = 0.03 vijesti dnevno');
    expect(md).toContain('(PROCJENA iz znakova)');
    expect(md).toMatch(/\| extract \| fake-eval \| 5 \| 35 \| 0 \|/);
    // Svaka tablica ima naredbu reprodukcije, i naredba daje istu tablicu.
    const cmds = [...md.matchAll(/Reprodukcija: `npm run eval:report -- --db '[^']+' --query "([^"]+)"`/g)];
    expect(cmds.length).toBe(10);
    const quoteSql = cmds.find((m) => m[1]?.includes('AS ishod'))?.[1] ?? '';
    const table = await runReportCli({ db: a.db, out: null, query: quoteSql });
    expect(md).toContain(table);

    // Nacrti (odluka 435): po jedan za svaku epizodu s trenutkom ≥ praga, citati iz moments.quote s linkom.
    const drafts = await runDraftsCli({ db: a.db, out: null }, NOW);
    expect(drafts).toMatch(/^# Nacrti vijesti iz podcasta/);
    expect(drafts).toContain('Nacrta: 5.');
    expect(drafts.match(/^- Članak \d+, verzija 2 \(engine:verify, verify-article\/1\+d1\)/gm)).toHaveLength(5);
    expect(drafts.match(/^> – .*https:\/\/domovina\.ai\/v\/[\w-]+\/t\/\d+/gm)?.length).toBeGreaterThanOrEqual(5);
    const sumSql = [...drafts.matchAll(/Reprodukcija: `npm run eval:report -- --db '[^']+' --query "([^"]+)"`/g)][0]?.[1] ?? '';
    expect(drafts).toContain(await runReportCli({ db: a.db, out: null, query: sumSql }));
  });

  it('greška jedne epizode ne ruši uzorak; nastavak pokuša još jednom pa odustane', async () => {
    const a = args({ maxCalls: 100 });
    // P9sLks-f2mQ nema titla (ne može se pokrenuti); ocjena Catholic Futurista uvijek padne.
    const env = {
      fakeCdn: { overrides: { 'data/P9sLks-f2mQ/diarized.srt': null } },
      llm: (r: MemoryRunRecorder | ReturnType<typeof createSqlRunRecorder>): LlmClient => {
        const inner = createFakeEvalLlm(r);
        return {
          model: inner.model,
          async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
            if (req.name === SCORE_PROMPT_NAME && req.prompt.includes('Kanal: Catholic Futurist')) {
              await r.recordCall(req.runId, { model: inner.model, tokensIn: 0, tokensOut: 0, costUsd: 0, ok: false });
              throw new LlmResponseError('Vertex HTTP 500: lažna greška', 500);
            }
            return inner.generate(req);
          },
        };
      },
    };
    const first = await runEvalCli(a, env);
    expect(first.exitCode).toBe(0);
    const by = new Map(first.outcomes.map((o) => [o.videoId, o]));
    expect(by.get('P9sLks-f2mQ')?.error).toMatch(/titl/);
    expect(by.get('x3w2BVZJ9vQ')).toMatchObject({ extract: 'ok', error: 'Vertex HTTP 500: lažna greška' });
    expect(by.get('pIx_7N-6HJ4')).toMatchObject({ extract: 'ok', score: 'ok', error: null });
    expect(first.text).toMatch(/s greškom 2/);

    const second = await runEvalCli(a, env);
    expect(second.callsMade).toBe(1);
    expect(second.estimate).toMatchObject({ todo: 1, done: 3, unrunnable: 1 });
    const third = await runEvalCli(a, env);
    expect(third.callsMade).toBe(0);
    expect(third.estimate).toMatchObject({ todo: 0, gaveUp: 1 });
    const log = (await readFile(a.log, 'utf8')).trim().split('\n');
    expect(log.filter((l) => l.includes('\tx3w2BVZJ9vQ\t'))).toHaveLength(2);
  });

  it('budgetedLlm: poziv preko ograde se ne šalje', async () => {
    const rec = new MemoryRunRecorder();
    const llm = budgetedLlm(createFakeEvalLlm(rec), 0);
    const runId = await rec.startRun({ step: 'extract', model: llm.model });
    await expect(llm.generate({ prompt: 'x', schema: {} as z.ZodType, runId })).rejects.toBeInstanceOf(
      BudgetExceededError,
    );
    expect(rec.get(runId).calls).toBe(0);
    expect(llm.used).toBe(0);
  });

  it('runEval bez spremanja uzorka u suhom prolazu; isti uzorak dvaput', async () => {
    const db = await freshDb();
    try {
      const recorder = createSqlRunRecorder(db);
      const persons = buildPersonIndex(parsePersons(await readFile(PERSONS_FIXTURE, 'utf8')).persons);
      const opts: EvalOptions = {
        channels: ['mreze_rijeci'],
        limit: 3,
        maxCalls: null,
        dryRun: true,
        attempts: 2,
        resample: false,
        now: NOW,
      };
      const deps = {
        cdn: cdn(),
        db,
        recorder,
        persons,
        llm: () => createFakeEvalLlm(recorder),
        backend: 'agy' as const,
        pricing: { inPerMTok: 0, outPerMTok: 0 },
      };
      const r = await runEval(deps, opts);
      expect(r.estimate).toMatchObject({ episodes: 1, calls: 13, seconds: 780, costUsd: 0 });
      expect(r.text).toMatch(/trajanje: ~13 min 0 s \(60 s po pozivu, serijski\)/);
      expect(r.text).toMatch(/\$0 \(pretplata\); API-ekvivalent po Vertex cjeniku \$0\.\d\d \(procjena\)/);
      expect((await db.query('SELECT 1 FROM vijesti.eval_sample')).rows).toHaveLength(0);
      expect((await runEval(deps, opts)).plans).toEqual(r.plans);
    } finally {
      await db.close();
    }
  });
});

describe('izvještaj i argumenti', () => {
  it('prazna baza: izvještaj bez ijednog retka ne pada', async () => {
    const db = await freshDb();
    try {
      const md = await buildEvalReport(db, { dbPath: '/x', generatedAt: NOW });
      expect(md).toContain('Izvučenih epizoda: 0 od 0.');
      expect(md).toContain('_(nema ocijenjenih trenutaka)_');
      expect(md).toContain('Po izvučenoj epizodi (0): nema podataka.');
      await expect(readOnlyQuery(db, 'DELETE FROM vijesti.moments')).rejects.toThrow(/read-only/);
    } finally {
      await db.close();
    }
  });

  it('link i naredba reprodukcije', () => {
    expect(momentLink('pIx_7N-6HJ4', 51_750)).toBe('https://domovina.ai/v/pIx_7N-6HJ4/t/51');
    expect(reproduceCommand('/d b', 'SELECT 1\n  FROM x')).toBe(`npm run eval:report -- --db '/d b' --query "SELECT 1 FROM x"`);
  });

  it('parseEvalArgs i parseReportArgs', () => {
    const p = parseEvalArgs(['--channels', 'a, b', '--limit', '3', '--max-calls', '500', '--now', '2026-11-01'], NOW);
    expect(p).toMatchObject({ channels: ['a', 'b'], limit: 3, maxCalls: 500, fake: false, dryRun: false, attempts: 2 });
    expect(p.db.endsWith('.cache/eval.pglite')).toBe(true);
    expect(p.log).toBe(`${p.db}.log`);
    expect(p.now.toISOString()).toBe('2026-11-01T12:00:00.000Z');
    expect(parseEvalArgs(['--fake'], NOW)).toMatchObject({ channels: FIXTURE_CHANNELS, maxCalls: null, limit: 5 });
    expect(parseEvalArgs(['--fake'], NOW).db.endsWith('.cache/eval-fake.pglite')).toBe(true);
    expect(parseEvalArgs(['--channels', 'a', '--dry-run'], NOW).maxCalls).toBeNull();
    expect(() => parseEvalArgs(['--max-calls', '5'], NOW)).toThrow(/--channels je obavezan/);
    expect(() => parseEvalArgs(['--channels', 'a'], NOW)).toThrow(/--max-calls je obavezan/);
    expect(() => parseEvalArgs(['--fake', '--limit', '0'], NOW)).toThrow(UsageError);
    expect(() => parseEvalArgs(['--fake', '--now', '6.11.2026.'], NOW)).toThrow(/YYYY-MM-DD/);
    expect(() => parseEvalArgs(['--fake', '--bla'], NOW)).toThrow(/nepoznata opcija/);
    expect(parseReportArgs(['report', '--db', '/x', '--query', 'SELECT 1'])).toEqual({ db: '/x', out: null, query: 'SELECT 1' });
    expect(parseReportArgs(['report', '--fake']).db.endsWith('eval-fake.pglite')).toBe(true);
    expect(() => parseReportArgs(['--db', '/x'])).toThrow(UsageError);
  });
});

describe('izvlačenje: timeout sekcije (odluka 406)', () => {
  function timeoutLlm(rec: ReturnType<typeof createSqlRunRecorder>, failAt: Set<number>): LlmClient {
    const inner = createFakeExtractLlm(rec);
    let n = 0;
    return {
      model: inner.model,
      async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
        if (failAt.has(n++)) {
          await rec.recordCall(req.runId, { model: inner.model, tokensIn: 0, tokensOut: 0, costUsd: 0, ok: false });
          throw new LlmTimeoutError('agy: nema odgovora');
        }
        return inner.generate(req);
      },
    };
  }

  it('jedan timeout = neuspjela sekcija, ostale se upisuju; dva zaredom prekidaju', async () => {
    const db = await freshDb();
    try {
      const rec = createSqlRunRecorder(db);
      const one = await runExtract(
        { cdn: cdn(), llm: timeoutLlm(rec, new Set([2, 5])), recorder: rec, db },
        { videoId: 'pIx_7N-6HJ4' },
      );
      expect(one).toMatchObject({ calls: 10, failedSections: 2 });
      expect(one.inserted).toBeGreaterThan(0);
      expect((await rec.totals(one.runId)).status).toBe('failed');
      await expect(
        runExtract({ cdn: cdn(), llm: timeoutLlm(rec, new Set([3, 4])), recorder: rec, db }, { videoId: 'pIx_7N-6HJ4' }),
      ).rejects.toBeInstanceOf(LlmTimeoutError);
    } finally {
      await db.close();
    }
  });
});

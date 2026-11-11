// Backend `agy` nad lažnim tmux/datotečnim slojem: ni tmux ni agy se ne pokreću.
import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import {
  AgyStartError,
  AgyTimeoutError,
  buildAgyRequest,
  createAgyClient,
  createTmuxAgyIo,
  unwrapAgyOutput,
  type AgyIo,
} from './agy.js';
import { createLlmFromConfig, describeLlmConfig, llmConfigFromEnv } from './config.js';
import { estimateTokens } from './estimate.js';
import { MemoryRunRecorder } from './runs.js';
import { LlmSchemaError } from './types.js';

const Schema = z.object({ n: z.number().int().min(0).max(10), why: z.string().min(1) });

/** Što „agy” napravi kad dobije uputu: sadržaj izlazne datoteke ili ništa (šuti). */
type Responder = (stem: string, request: string) => string | null;

interface FakeOptions {
  respond: Responder;
  /** Odgovor na zahtjev za popravak sintakse. */
  repair?: (stem: string) => string | null;
  /** Prvi capture nakon pokretanja pita za povjerenje. */
  trustPrompt?: boolean;
  /** agy se nikad ne pokrene (nema „for shortcuts”). */
  neverReady?: boolean;
  /** Prvi /clear prođe kao tekst: stari upit ostane na ekranu. */
  clearFailsOnce?: boolean;
}

function fakeIo(o: FakeOptions) {
  let now = 1_000_000;
  const files = new Map<string, { text: string; mtimeMs: number }>();
  const sessions = new Set<string>();
  const log: string[] = [];
  let screen = '';
  let active = 0;
  let maxActive = 0;
  let clearFailed = false;
  const dirOf = new Map<string, string>();
  const io: AgyIo = {
    hasSession: (s) => Promise.resolve(sessions.has(s)),
    newSession(s, cwd, command) {
      sessions.add(s);
      dirOf.set(s, cwd);
      log.push(`new ${s} ${cwd} ${command}`);
      screen = o.neverReady ? 'loading' : o.trustPrompt ? 'Do you trust the contents of this folder?' : '? for shortcuts';
      return Promise.resolve();
    },
    sendText(s, text) {
      if (text === '/clear') {
        log.push('clear');
        if (o.clearFailsOnce && !clearFailed && screen.includes('Read the file req-')) {
          clearFailed = true;
        } else screen = '? for shortcuts';
        return Promise.resolve();
      }
      const ask = /^Read the file (req-[^ ]+)\.md/.exec(text);
      const rep = /^The file (req-[^ ]+)\.json is not valid JSON/.exec(text);
      const dir = dirOf.get(s) ?? '';
      if (ask?.[1]) {
        const stem = ask[1];
        active++;
        maxActive = Math.max(maxActive, active);
        log.push(`ask ${stem}`);
        screen = `> ${text}`;
        const out = o.respond(stem, files.get(`${dir}/${stem}.md`)?.text ?? '');
        if (out !== null) files.set(`${dir}/${stem}.json`, { text: out, mtimeMs: now });
      } else if (rep?.[1]) {
        log.push(`repair ${rep[1]}`);
        const out = o.repair?.(rep[1]) ?? null;
        if (out !== null) files.set(`${dir}/${rep[1]}.json`, { text: out, mtimeMs: now + 1 });
      } else log.push(`text ${text}`);
      return Promise.resolve();
    },
    sendKey(_s, key) {
      log.push(`key ${key}`);
      if (key === 'Enter' && screen.includes('trust the contents')) screen = '? for shortcuts';
      return Promise.resolve();
    },
    capture: () => Promise.resolve(screen),
    killSession(s) {
      sessions.delete(s);
      log.push(`kill ${s}`);
      return Promise.resolve();
    },
    mkdir: () => Promise.resolve(),
    writeFile(p, text) {
      files.set(p, { text, mtimeMs: now });
      return Promise.resolve();
    },
    readFile(p) {
      const f = files.get(p);
      return f ? Promise.resolve(f.text) : Promise.reject(new Error(`nema ${p}`));
    },
    stat(p) {
      const f = files.get(p);
      return Promise.resolve(f ? { size: f.text.length, mtimeMs: f.mtimeMs } : null);
    },
    rm(p) {
      if (p.endsWith('.md')) {
        active--;
        log.push(`rm ${p.split('/').pop() ?? ''}`);
      }
      files.delete(p);
      return Promise.resolve();
    },
    sleep(ms) {
      now += ms;
      return Promise.resolve();
    },
    now: () => now,
  };
  return { io, files, log, maxActive: () => maxActive };
}

function client(o: FakeOptions, extra: { timeoutMs?: number } = {}) {
  const fake = fakeIo(o);
  const recorder = new MemoryRunRecorder();
  const llm = createAgyClient({
    io: fake.io,
    recorder,
    dir: '/agy/agyvij',
    tag: 't',
    timeoutMs: extra.timeoutMs ?? 60_000,
  });
  return { ...fake, recorder, llm };
}

const OK = JSON.stringify({ n: 3, why: 'konkretna brojka' });

describe('agy backend (lažni tmux)', () => {
  it('uspjeh: sesija, povjerenje, upit u datoteci sa shemom, izlaz kroz zod; tokeni su procjena', async () => {
    let seen = '';
    const c = client({
      trustPrompt: true,
      respond: (_stem, request) => {
        seen = request;
        return OK;
      },
    });
    const runId = await c.recorder.startRun({ step: 'extract', model: c.llm.model });
    const out = await c.llm.generate({ prompt: 'ULAZNI TEKST', system: 'Uputa sustava.', schema: Schema, runId });
    expect(out).toEqual({ n: 3, why: 'konkretna brojka' });
    expect(c.llm.model).toBe('agy:gemini-3.8-flash-high');
    expect(c.log[0]).toBe('new agyvij /agy/agyvij agy --model gemini-3.8-flash-high --dangerously-skip-permissions');
    expect(c.log).toContain('key Enter');
    expect(c.log.indexOf('clear')).toBeLessThan(c.log.findIndex((l) => l.startsWith('ask ')));
    expect(seen).toContain('# UPUTA\n\nUputa sustava.');
    expect(seen).toContain('# SHEMA');
    expect(seen).toContain('"why"');
    expect(seen).toContain('# ULAZ\n\nULAZNI TEKST');
    expect(c.files.size).toBe(0);
    const r = c.recorder.get(runId);
    expect(r).toMatchObject({ calls: 1, failedCalls: 0, costUsd: 0, tokensEstimated: true });
    expect(r.tokensIn).toBe(estimateTokens(seen));
    expect(r.tokensOut).toBe(estimateTokens(OK));
  });

  it('ograđivač ```json se skida, proza oko objekta ne', () => {
    expect(unwrapAgyOutput('\uFEFF```json\n{"a":1}\n```')).toBe('{"a":1}');
    expect(unwrapAgyOutput('```\n{"a":1}```')).toBe('{"a":1}');
    expect(unwrapAgyOutput('Evo: {"a":1}')).toBe('Evo: {"a":1}');
  });

  it('timeout: Escape dvaput, neuspio poziv, poruka kaže da i odbijen upit izgleda ovako', async () => {
    const c = client({ respond: () => null }, { timeoutMs: 30_000 });
    const runId = await c.recorder.startRun({ step: 'extract', model: c.llm.model });
    const err = await c.llm.generate({ prompt: 'x', schema: Schema, runId }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(AgyTimeoutError);
    expect((err as Error).message).toMatch(/nema odgovora nakon 30 s.*odbijen upit/);
    expect(c.log.filter((l) => l === 'key Escape')).toHaveLength(2);
    expect(c.recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1, tokensOut: 0, tokensEstimated: true });
    expect(c.files.size).toBe(0);
  });

  it('ne-JSON: dva zahtjeva za popravak sintakse pa LlmSchemaError; popravljen izlaz prolazi', async () => {
    const bad = client({ respond: () => 'Evo JSON-a: {"n": 3', repair: () => 'i dalje {"n": 3' });
    const runId = await bad.recorder.startRun({ step: 'extract', model: bad.llm.model });
    const err = await bad.llm.generate({ prompt: 'x', schema: Schema, runId }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(LlmSchemaError);
    expect((err as Error).message).toMatch(/nije valjan JSON ni nakon 2 popravka/);
    expect(bad.log.filter((l) => l.startsWith('repair '))).toHaveLength(2);
    expect(bad.recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1 });

    const fixed = client({ respond: () => '{"n": 3, "why": "x"', repair: () => OK });
    const id2 = await fixed.recorder.startRun({ step: 'extract', model: fixed.llm.model });
    expect(await fixed.llm.generate({ prompt: 'x', schema: Schema, runId: id2 })).toEqual({ n: 3, why: 'konkretna brojka' });
    expect(fixed.log.filter((l) => l.startsWith('repair '))).toHaveLength(1);
    expect(fixed.recorder.get(id2)).toMatchObject({ calls: 1, failedCalls: 0 });
  });

  it('JSON izvan sheme: LlmSchemaError odmah, bez popravka, poziv neuspio', async () => {
    const c = client({ respond: () => JSON.stringify({ n: 11, why: '' }) });
    const runId = await c.recorder.startRun({ step: 'score', model: c.llm.model });
    const err = await c.llm.generate({ prompt: 'x', schema: Schema, runId }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(LlmSchemaError);
    expect((err as Error).message).toMatch(/ne prolazi shemu/);
    expect(c.log.some((l) => l.startsWith('repair '))).toBe(false);
    expect(c.recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1 });
  });

  it('dva istodobna poziva idu jedan za drugim; greška prvog ne blokira drugi', async () => {
    let i = 0;
    const c = client({ respond: () => (i++ === 0 ? JSON.stringify({ n: 99, why: 'x' }) : OK) });
    const runId = await c.recorder.startRun({ step: 'extract', model: c.llm.model });
    const [a, b] = await Promise.allSettled([
      c.llm.generate({ prompt: 'prvi', schema: Schema, runId }),
      c.llm.generate({ prompt: 'drugi', schema: Schema, runId }),
    ]);
    expect(a.status).toBe('rejected');
    expect(b).toEqual({ status: 'fulfilled', value: { n: 3, why: 'konkretna brojka' } });
    expect(c.maxActive()).toBe(1);
    const asks = c.log.flatMap((l, k) => (l.startsWith('ask ') ? [k] : []));
    const firstRm = c.log.findIndex((l) => l.startsWith('rm '));
    expect(asks).toHaveLength(2);
    expect(firstRm).toBeGreaterThan(asks[0] ?? -1);
    expect(firstRm).toBeLessThan(asks[1] ?? -1);
    expect(c.recorder.get(runId)).toMatchObject({ calls: 2, failedCalls: 1 });
  });

  it('sesija se ne digne: AgyStartError, sesija ubijena, poziv se ne broji', async () => {
    const c = client({ neverReady: true, respond: () => OK });
    const runId = await c.recorder.startRun({ step: 'extract', model: c.llm.model });
    await expect(c.llm.generate({ prompt: 'x', schema: Schema, runId })).rejects.toBeInstanceOf(AgyStartError);
    expect(c.log).toContain('kill agyvij');
    expect(c.recorder.get(runId).calls).toBe(0);
  });

  it('/clear koji ne očisti ekran: sesija ispočetka prije idućeg upita', async () => {
    const c = client({ clearFailsOnce: true, respond: () => OK });
    const runId = await c.recorder.startRun({ step: 'extract', model: c.llm.model });
    await c.llm.generate({ prompt: 'a', schema: Schema, runId });
    await c.llm.generate({ prompt: 'b', schema: Schema, runId });
    expect(c.log.filter((l) => l.startsWith('new '))).toHaveLength(2);
    expect(c.log).toContain('kill agyvij');
    expect(c.recorder.get(runId)).toMatchObject({ calls: 2, failedCalls: 0 });
  });

  it('pravi tmux sloj cilja sesiju s = (točno ime, bez prefix matchinga)', async () => {
    const calls: string[][] = [];
    const io = createTmuxAgyIo({
      sendDelayMs: 0,
      exec: (args) => {
        calls.push(args);
        return Promise.resolve({ code: 0, stdout: 'ekran' });
      },
    });
    expect(await io.hasSession('agyvij')).toBe(true);
    await io.sendText('agyvij', '/clear');
    expect(await io.capture('agyvij')).toBe('ekran');
    await io.killSession('agyvij');
    expect(calls).toEqual([
      ['has-session', '-t', '=agyvij'],
      ['send-keys', '-t', '=agyvij:', '-l', '/clear'],
      ['send-keys', '-t', '=agyvij:', 'Enter'],
      ['capture-pane', '-p', '-t', '=agyvij:'],
      ['kill-session', '-t', '=agyvij'],
    ]);
  });

  it('buildAgyRequest bez systema ima zadanu uputu', () => {
    expect(buildAgyRequest({ prompt: 'p', schema: Schema })).toMatch(/^# UPUTA\n\nOdgovori isključivo JSON/);
  });
});

describe('agy u konfiguraciji', () => {
  it('VIJESTI_LLM_BACKEND=agy: pretplata $0, zadana sesija agyvij, opis bez tajni', () => {
    const cfg = llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'agy', VIJESTI_AGY_DIR: '/tmp/agy' });
    expect(cfg.backend).toBe('agy');
    expect(cfg.pricing).toEqual({ inPerMTok: 0, outPerMTok: 0 });
    expect(cfg.pricingSource).toBe('subscription');
    expect(cfg.agy).toEqual({ session: 'agyvij', model: 'gemini-3.8-flash-high', dir: '/tmp/agy', timeoutMs: 600_000 });
    expect(describeLlmConfig(cfg)).toMatch(/^agy tmux=agyvij model=gemini-3.8-flash-high .*\$0 \(pretplata\)/);
    const llm = createLlmFromConfig(cfg, {
      fetch: () => Promise.reject(new Error('mreža')),
      recorder: new MemoryRunRecorder(),
      agyIo: fakeIo({ respond: () => OK }).io,
    });
    expect(llm.model).toBe('agy:gemini-3.8-flash-high');
    expect(llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'agy', VIJESTI_AGY_TIMEOUT_SEC: '90' }).agy.timeoutMs).toBe(90_000);
    expect(() => llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'agy', VIJESTI_AGY_TIMEOUT_SEC: '0' })).toThrow(/TIMEOUT/);
    expect(() => llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'gpt' })).toThrow(/vertex, studio, agy, claude/);
  });

  it('runs.tokens_estimated: agy poziv označi run, Vertex poziv ne', async () => {
    const db = new PGlite();
    try {
      await db.waitReady;
      await migrateUp(db);
      const rec = createSqlRunRecorder(db);
      const a = await rec.startRun({ step: 'extract', model: 'agy:m' });
      await rec.recordCall(a, { model: 'agy:m', tokensIn: 10, tokensOut: 2, costUsd: 0, ok: true, tokensEstimated: true });
      await rec.recordCall(a, { model: 'agy:m', tokensIn: 1, tokensOut: 1, costUsd: 0, ok: true });
      const v = await rec.startRun({ step: 'extract', model: 'gemini' });
      await rec.recordCall(v, { model: 'gemini', tokensIn: 10, tokensOut: 2, costUsd: 0.1, ok: true });
      expect(await rec.totals(a)).toMatchObject({ calls: 2, tokensIn: 11, tokensEstimated: true });
      expect((await rec.totals(v)).tokensEstimated).toBe(false);
    } finally {
      await db.close();
    }
  });
});

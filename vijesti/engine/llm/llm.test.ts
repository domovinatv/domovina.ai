import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { FIXTURES_DIR } from '../test/fixtures-refresh.js';
import { DEFAULT_GEMINI_MODEL, llmConfigFromEnv } from './config.js';
import { createFakeLlmClient, FakeLlmMissingError, loadRecordedResponses } from './fake.js';
import { createGeminiClient, toGeminiSchema, type LlmFetch } from './gemini.js';
import { MemoryRunRecorder } from './runs.js';
import { LlmResponseError, LlmSchemaError } from './types.js';

/** Shema trenutka kakvu će S2 tražiti od modela (ovdje samo za test klijenta). */
const MomentsSchema = z.object({
  moments: z.array(
    z.object({
      start_ms: z.number().int().nonnegative(),
      end_ms: z.number().int().positive(),
      speaker: z.string().regex(/^SPEAKER_\d{2}$/),
      quote: z.string().min(1),
      topics: z.array(z.string()).default([]),
    }),
  ),
});

const recorded = () => loadRecordedResponses(join(FIXTURES_DIR, 'llm'));

describe('lažni klijent', () => {
  it('vraća validiran snimljeni odgovor i broji poziv', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'fake' });
    const llm = createFakeLlmClient({ recorder, byName: await recorded() });
    const out = await llm.generate({ prompt: 'p', schema: MomentsSchema, runId, name: 'moments-ok' });
    expect(out.moments[0]?.speaker).toBe('SPEAKER_01');
    expect(recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 0, tokensIn: 1834, tokensOut: 212 });
  });

  it('nevaljan odgovor baca LlmSchemaError, poziv se broji kao neuspio', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'fake' });
    const llm = createFakeLlmClient({ recorder, byName: await recorded() });
    const p = llm.generate({ prompt: 'p', schema: MomentsSchema, runId, name: 'moments-invalid' });
    await expect(p).rejects.toBeInstanceOf(LlmSchemaError);
    await expect(p).rejects.toThrow(/moments\.0\.start_ms/);
    expect(recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1, tokensOut: 96 });
  });

  it('izlaz koji nije JSON baca; nema tihog popravka', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'x', model: 'fake' });
    const llm = createFakeLlmClient({
      recorder,
      queue: [{ text: '```json\n{"moments": []}\n```', usage: { tokensIn: 1, tokensOut: 1 } }],
    });
    await expect(llm.generate({ prompt: 'p', schema: MomentsSchema, runId })).rejects.toThrow(
      /nije JSON/,
    );
  });

  it('bez snimke baca FakeLlmMissingError; red ide redom', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'x', model: 'fake' });
    const llm = createFakeLlmClient({
      recorder,
      queue: [
        { text: '{"moments":[]}', usage: { tokensIn: 0, tokensOut: 0 } },
      ],
    });
    expect(await llm.generate({ prompt: 'a', schema: MomentsSchema, runId })).toEqual({ moments: [] });
    await expect(
      llm.generate({ prompt: 'b', schema: MomentsSchema, runId, name: 'nepoznato' }),
    ).rejects.toBeInstanceOf(FakeLlmMissingError);
    expect(llm.requests.map((r) => r.prompt)).toEqual(['a', 'b']);
  });
});

interface Captured {
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
}

function geminiFetch(
  status: number,
  response: unknown,
  captured: Captured[],
): LlmFetch {
  return (url, init) => {
    captured.push({ url, headers: init.headers, body: JSON.parse(init.body) as Record<string, unknown> });
    const text = typeof response === 'string' ? response : JSON.stringify(response);
    return Promise.resolve({ status, ok: status >= 200 && status < 300, text: () => Promise.resolve(text) });
  };
}

const okResponse = (text: string, finishReason = 'STOP') => ({
  candidates: [
    {
      content: { role: 'model', parts: [{ text: 'razmišljam…', thought: true }, { text }] },
      finishReason,
    },
  ],
  usageMetadata: {
    promptTokenCount: 1200,
    candidatesTokenCount: 300,
    thoughtsTokenCount: 500,
    totalTokenCount: 2000,
  },
  modelVersion: 'gemini-3.5-flash',
});

describe('Gemini klijent (lažni fetch)', () => {
  const pricing = { inPerMTok: 0.5, outPerMTok: 3 };

  it('oblik zahtjeva: model u URL-u, ključ samo u zaglavlju, JSON shema u generationConfig', async () => {
    const captured: Captured[] = [];
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'gemini-3.5-flash' });
    const llm = createGeminiClient({
      fetch: geminiFetch(200, okResponse('{"moments":[]}'), captured),
      apiKey: 'tajni-kljuc',
      model: 'gemini-3.5-flash',
      recorder,
      pricing,
    });
    await llm.generate({ prompt: 'Izvuci trenutke.', system: 'Ti si urednik.', schema: MomentsSchema, runId, temperature: 0 });
    const req = captured[0];
    expect(req?.url).toBe(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent',
    );
    expect(req?.url).not.toContain('tajni-kljuc');
    expect(req?.headers['x-goog-api-key']).toBe('tajni-kljuc');
    expect(req?.body).toMatchObject({
      contents: [{ role: 'user', parts: [{ text: 'Izvuci trenutke.' }] }],
      systemInstruction: { parts: [{ text: 'Ti si urednik.' }] },
      generationConfig: { responseMimeType: 'application/json', temperature: 0 },
    });
    const schema = (req?.body.generationConfig as { responseJsonSchema: Record<string, unknown> })
      .responseJsonSchema;
    expect(schema).toEqual(toGeminiSchema(MomentsSchema));
    expect(schema).not.toHaveProperty('$schema');
    expect(schema).toMatchObject({ type: 'object', required: ['moments'] });
  });

  it('parsira usage: thinking tokeni idu u izlaz, trošak po cijeni iz konfiguracije', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'm' });
    const llm = createGeminiClient({
      fetch: geminiFetch(200, okResponse('{"moments":[]}'), []),
      apiKey: 'k',
      model: 'm',
      recorder,
      pricing,
    });
    expect(await llm.generate({ prompt: 'p', schema: MomentsSchema, runId })).toEqual({ moments: [] });
    const r = recorder.get(runId);
    expect(r).toMatchObject({ calls: 1, failedCalls: 0, tokensIn: 1200, tokensOut: 800 });
    expect(r.costUsd).toBeCloseTo((1200 * 0.5 + 800 * 3) / 1e6, 12);
  });

  it('izlaz koji ne prolazi shemu baca, tokeni se svejedno broje', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'extract', model: 'm' });
    const llm = createGeminiClient({
      fetch: geminiFetch(200, okResponse('{"moments":[{"quote":""}]}'), []),
      apiKey: 'k',
      model: 'm',
      recorder,
    });
    await expect(llm.generate({ prompt: 'p', schema: MomentsSchema, runId })).rejects.toBeInstanceOf(
      LlmSchemaError,
    );
    expect(recorder.get(runId)).toMatchObject({ calls: 1, failedCalls: 1, tokensIn: 1200, costUsd: null });
  });

  it('HTTP greška, prekinut i blokiran odgovor su LlmResponseError', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'x', model: 'm' });
    const client = (status: number, body: unknown) =>
      createGeminiClient({ fetch: geminiFetch(status, body, []), apiKey: 'k', model: 'm', recorder, retry: { retries: 0 } });
    const gen = (status: number, body: unknown) =>
      client(status, body).generate({ prompt: 'p', schema: MomentsSchema, runId });
    await expect(gen(429, { error: { message: 'quota' } })).rejects.toThrow(/HTTP 429/);
    await expect(gen(200, okResponse('{"moments":[', 'MAX_TOKENS'))).rejects.toThrow(/MAX_TOKENS/);
    await expect(gen(200, { promptFeedback: { blockReason: 'SAFETY' } })).rejects.toThrow(/SAFETY/);
    await expect(gen(200, 'nije json')).rejects.toBeInstanceOf(LlmResponseError);
    expect(recorder.get(runId)).toMatchObject({ calls: 4, failedCalls: 4 });
  });

  it('prekid (fetch ili tijelo baci) se broji kao neuspio poziv i baca dalje', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'x', model: 'm' });
    const dead: LlmFetch = () => Promise.reject(new Error('ECONNRESET'));
    const cut: LlmFetch = () =>
      Promise.resolve({ status: 200, ok: true, text: () => Promise.reject(new Error('prekinuto')) });
    for (const [fetch, msg] of [[dead, /ECONNRESET/], [cut, /prekinuto/]] as const) {
      const llm = createGeminiClient({ fetch, apiKey: 'k', model: 'm', recorder });
      await expect(llm.generate({ prompt: 'p', schema: MomentsSchema, runId })).rejects.toThrow(msg);
    }
    expect(recorder.get(runId)).toMatchObject({ calls: 2, failedCalls: 2, tokensIn: 0 });
  });

  it('HTTP greška ne odaje ključ u poruci', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'x', model: 'm' });
    const llm = createGeminiClient({
      fetch: geminiFetch(500, { error: { message: 'interno' } }, []),
      apiKey: 'tajni-kljuc',
      model: 'm',
      recorder,
      retry: { retries: 0 },
    });
    const err = await llm.generate({ prompt: 'p', schema: MomentsSchema, runId }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(LlmResponseError);
    expect((err as Error).message).not.toContain('tajni-kljuc');
    expect((err as LlmResponseError).status).toBe(500);
  });

  it('bez ključa se klijent ne stvara', () => {
    expect(() =>
      createGeminiClient({ fetch: geminiFetch(200, {}, []), apiKey: '', model: 'm', recorder: new MemoryRunRecorder() }),
    ).toThrow(/GEMINI_API_KEY/);
  });

  it('pozivi se broje u vijesti.runs (PGlite)', async () => {
    const db = new PGlite();
    try {
      await migrateUp(db);
      const recorder = createSqlRunRecorder(db);
      const runId = await recorder.startRun({ step: 'extract', model: 'm', videoId: 'pIx_7N-6HJ4' });
      const good = createGeminiClient({
        fetch: geminiFetch(200, okResponse('{"moments":[]}'), []),
        apiKey: 'k',
        model: 'm',
        recorder,
        pricing,
      });
      const bad = createGeminiClient({
        fetch: geminiFetch(200, okResponse('{}'), []),
        apiKey: 'k',
        model: 'm',
        recorder,
        pricing,
      });
      await good.generate({ prompt: 'p', schema: MomentsSchema, runId });
      await expect(bad.generate({ prompt: 'p', schema: MomentsSchema, runId })).rejects.toThrow();
      await recorder.finishRun(runId, { status: 'failed', error: 'shema' });
      const t = await recorder.totals(runId);
      expect(t).toMatchObject({ status: 'failed', calls: 2, failedCalls: 1, tokensIn: 2400, tokensOut: 1600 });
      expect(t.costUsd).toBeCloseTo(2 * (1200 * 0.5 + 800 * 3) / 1e6, 6);

      // Bez cijene ukupni trošak postaje nepoznat (NULL), ne nula.
      const run2 = await recorder.startRun({ step: 'extract', model: 'm' });
      await recorder.recordCall(run2, { model: 'm', tokensIn: 1, tokensOut: 1, costUsd: 0.1, ok: true });
      await recorder.recordCall(run2, { model: 'm', tokensIn: 1, tokensOut: 1, costUsd: null, ok: true });
      expect((await recorder.totals(run2)).costUsd).toBeNull();
      await expect(
        recorder.recordCall(9999, { model: 'm', tokensIn: 0, tokensOut: 0, costUsd: null, ok: true }),
      ).rejects.toThrow(/nepoznat run/);
    } finally {
      await db.close();
    }
  });
});

describe('konfiguracija', () => {
  it('zadani model, ključ i cijena iz okoline', () => {
    expect(DEFAULT_GEMINI_MODEL).toBe('gemini-3.8-flash');
    expect(llmConfigFromEnv({}, Date.UTC(2026, 10, 5))).toMatchObject({
      backend: 'vertex',
      apiKey: '',
      model: DEFAULT_GEMINI_MODEL,
      pricing: { inPerMTok: 0.75, outPerMTok: 3.75 },
      pricingSource: 'default',
    });
    expect(
      llmConfigFromEnv({
        GEMINI_API_KEY: ' k ',
        VIJESTI_GEMINI_MODEL: 'gemini-x',
        VIJESTI_GEMINI_PRICE_IN_PER_MTOK: '0.3',
        VIJESTI_GEMINI_PRICE_OUT_PER_MTOK: '2.5',
      }),
    ).toMatchObject({
      backend: 'studio',
      apiKey: 'k',
      model: 'gemini-x',
      pricing: { inPerMTok: 0.3, outPerMTok: 2.5 },
      pricingSource: 'env',
    });
    // AI Studio bez cijene u okolini: trošak nepoznat (odluka 107), ne izmišljen.
    expect(llmConfigFromEnv({ GEMINI_API_KEY: 'k' })).toMatchObject({ pricing: null, pricingSource: null });
  });

  it('pola cijene ili neispravan broj je greška', () => {
    expect(() => llmConfigFromEnv({ VIJESTI_GEMINI_PRICE_IN_PER_MTOK: '1' })).toThrow(/i ulaz i izlaz/);
    expect(() =>
      llmConfigFromEnv({ VIJESTI_GEMINI_PRICE_IN_PER_MTOK: 'x', VIJESTI_GEMINI_PRICE_OUT_PER_MTOK: '1' }),
    ).toThrow(/nenegativan/);
  });
});

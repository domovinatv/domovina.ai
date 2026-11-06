// Vertex backend, retry, obje varijante sheme i konfiguracija (odluke 300–305).
// Bez mreže: fetch i gcloud su lažni.
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import {
  createLlmFromConfig,
  defaultPricing,
  describeLlmConfig,
  llmConfigFromEnv,
} from './config.js';
import { estimatePrompts, estimateTokens } from './estimate.js';
import {
  buildGeminiBody,
  createGeminiClient,
  toGeminiSchema,
  toOpenApiSchema,
  vertexEndpointUrl,
  type LlmFetch,
} from './gemini.js';
import { MemoryRunRecorder } from './runs.js';
import { LlmResponseError } from './types.js';
import { createGcloudTokenProvider, gcloudTokenArgs, staticTokenProvider } from './vertex-auth.js';

const Out = z.object({
  items: z.array(
    z.object({
      id: z.number().int().positive(),
      score: z.number().min(0).max(1),
      note: z.string().nullable(),
      kind: z.enum(['a', 'b']),
    }),
  ),
});

interface Call {
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
}

const ok = (text: string) => ({
  candidates: [{ content: { parts: [{ text }] }, finishReason: 'STOP' }],
  usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 10, thoughtsTokenCount: 5 },
});

/** Odgovori redom; zadnji se ponavlja. */
function seqFetch(responses: { status: number; body: unknown }[], calls: Call[]): LlmFetch {
  let i = 0;
  return (url, init) => {
    calls.push({ url, headers: init.headers, body: JSON.parse(init.body) as Record<string, unknown> });
    const r = responses[Math.min(i++, responses.length - 1)] ?? { status: 500, body: '' };
    const text = typeof r.body === 'string' ? r.body : JSON.stringify(r.body);
    return Promise.resolve({ status: r.status, ok: r.status >= 200 && r.status < 300, text: () => Promise.resolve(text) });
  };
}

const TOKEN = 'ya29.lazni-token-koji-se-ne-smije-vidjeti';
const GOOD = '{"items":[{"id":1,"score":0.5,"note":null,"kind":"a"}]}';

function vertexClient(fetch: LlmFetch, recorder: MemoryRunRecorder, extra: Record<string, unknown> = {}) {
  const sleeps: number[] = [];
  const llm = createGeminiClient({
    backend: 'vertex',
    fetch,
    model: 'gemini-3.8-flash',
    recorder,
    pricing: { inPerMTok: 0.75, outPerMTok: 3.75 },
    vertex: { project: 'proj-x', location: 'global', tokens: staticTokenProvider(TOKEN) },
    retry: {
      retries: 2,
      baseDelayMs: 1000,
      sleep: (ms) => {
        sleeps.push(ms);
        return Promise.resolve();
      },
    },
    ...extra,
  });
  return { llm, sleeps };
}

describe('Vertex backend', () => {
  it('URL global/eu/regija kao pipeline; Bearer token, bez ključa i bez tokena u URL-u', async () => {
    expect(vertexEndpointUrl('p', 'global', 'gemini-3.8-flash')).toBe(
      'https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models/gemini-3.8-flash:generateContent',
    );
    expect(vertexEndpointUrl('p', 'eu', 'm')).toBe(
      'https://aiplatform.eu.rep.googleapis.com/v1/projects/p/locations/eu/publishers/google/models/m:generateContent',
    );
    expect(vertexEndpointUrl('p', 'europe-west4', 'm')).toMatch(
      /^https:\/\/europe-west4-aiplatform\.googleapis\.com\/v1\/projects\/p\/locations\/europe-west4\//,
    );
    expect(() => vertexEndpointUrl('p', 'evil.com/x', 'm')).toThrow(/lokacija/);

    const calls: Call[] = [];
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: 'gemini-3.8-flash' });
    const { llm } = vertexClient(seqFetch([{ status: 200, body: ok(GOOD) }], calls), recorder);
    const out = await llm.generate({ prompt: 'p', system: 's', schema: Out, runId, temperature: 0 });
    expect(out.items[0]?.score).toBe(0.5);
    const c = calls[0];
    expect(c?.url).toBe(vertexEndpointUrl('proj-x', 'global', 'gemini-3.8-flash'));
    expect(c?.url).not.toContain(TOKEN);
    expect(c?.headers.authorization).toBe(`Bearer ${TOKEN}`);
    expect(c?.headers).not.toHaveProperty('x-goog-api-key');
    // Isto tijelo kao AI Studio.
    expect(c?.body).toEqual(buildGeminiBody({ prompt: 'p', system: 's', schema: Out, temperature: 0 }));
    const r = recorder.get(runId);
    expect(r).toMatchObject({ calls: 1, failedCalls: 0, tokensIn: 100, tokensOut: 15 });
    expect(r.costUsd).toBeCloseTo((100 * 0.75 + 15 * 3.75) / 1e6, 12);
  });

  it('429 i 5xx: dva ponovna pokušaja s backoffom, svaki pokušaj je poziv', async () => {
    const calls: Call[] = [];
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: 'm' });
    const { llm, sleeps } = vertexClient(
      seqFetch(
        [
          { status: 429, body: { error: { message: 'RESOURCE_EXHAUSTED' } } },
          { status: 503, body: 'unavailable' },
          { status: 200, body: ok(GOOD) },
        ],
        calls,
      ),
      recorder,
    );
    await llm.generate({ prompt: 'p', schema: Out, runId });
    expect(calls).toHaveLength(3);
    expect(sleeps).toEqual([1000, 2000]);
    expect(recorder.get(runId)).toMatchObject({ calls: 3, failedCalls: 2, tokensIn: 100 });
  });

  it('nakon iscrpljenih pokušaja baca LlmResponseError; 400 se ne ponavlja; token nije u poruci', async () => {
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: 'm' });
    const calls: Call[] = [];
    const { llm } = vertexClient(
      seqFetch([{ status: 429, body: `quota for ${TOKEN}` }], calls),
      recorder,
    );
    const err = await llm.generate({ prompt: 'p', schema: Out, runId }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(LlmResponseError);
    expect((err as Error).message).toMatch(/Vertex HTTP 429/);
    expect((err as Error).message).not.toContain(TOKEN);
    expect(calls).toHaveLength(3);

    const calls400: Call[] = [];
    const { llm: bad } = vertexClient(seqFetch([{ status: 400, body: 'Unknown name "responseJsonSchema"' }], calls400), recorder);
    await expect(bad.generate({ prompt: 'p', schema: Out, runId })).rejects.toThrow(/HTTP 400.*responseJsonSchema/);
    expect(calls400).toHaveLength(1);
    expect(recorder.get(runId)).toMatchObject({ calls: 4, failedCalls: 4 });
  });

  it('401 poništava keširani token, sljedeći poziv traži novi', async () => {
    let n = 0;
    const tokens = createGcloudTokenProvider({
      execFile: () => Promise.resolve({ stdout: `tok-${String(++n)}-abcdefgh\n` }),
    });
    const calls: Call[] = [];
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: 'm' });
    const llm = createGeminiClient({
      backend: 'vertex',
      fetch: seqFetch([{ status: 401, body: 'expired' }, { status: 200, body: ok(GOOD) }], calls),
      model: 'm',
      recorder,
      vertex: { project: 'p', location: 'global', tokens },
      retry: { retries: 0 },
    });
    await expect(llm.generate({ prompt: 'p', schema: Out, runId })).rejects.toThrow(/HTTP 401/);
    await llm.generate({ prompt: 'p', schema: Out, runId });
    expect(calls.map((c) => c.headers.authorization)).toEqual(['Bearer tok-1-abcdefgh', 'Bearer tok-2-abcdefgh']);
  });

  it('bez projekta se klijent ne stvara', () => {
    expect(() =>
      createGeminiClient({
        backend: 'vertex',
        fetch: seqFetch([], []),
        model: 'm',
        recorder: new MemoryRunRecorder(),
      }),
    ).toThrow(/VIJESTI_VERTEX_PROJECT/);
  });
});

describe('shema: responseJsonSchema ili responseSchema (odluka 303)', () => {
  it('zadano responseJsonSchema = JSON Schema bez $schema', () => {
    const body = buildGeminiBody({ prompt: 'p', schema: Out });
    const gc = body.generationConfig as Record<string, unknown>;
    expect(gc.responseMimeType).toBe('application/json');
    expect(gc.responseJsonSchema).toEqual(toGeminiSchema(Out));
    expect(gc).not.toHaveProperty('responseSchema');
  });

  it('responseSchema = OpenAPI podskup: tipovi velikim slovima, nullable, enum, granice', () => {
    const body = buildGeminiBody({ prompt: 'p', schema: Out }, 'responseSchema');
    const gc = body.generationConfig as Record<string, unknown>;
    expect(gc).not.toHaveProperty('responseJsonSchema');
    const s = gc.responseSchema as Record<string, unknown>;
    expect(s).toEqual(toOpenApiSchema(toGeminiSchema(Out)));
    expect(s).toMatchObject({
      type: 'OBJECT',
      required: ['items'],
      propertyOrdering: ['items'],
      properties: {
        items: {
          type: 'ARRAY',
          items: {
            type: 'OBJECT',
            required: ['id', 'score', 'note', 'kind'],
            properties: {
              id: { type: 'INTEGER' },
              score: { type: 'NUMBER', minimum: 0, maximum: 1 },
              note: { type: 'STRING', nullable: true },
              kind: { type: 'STRING', enum: ['a', 'b'] },
            },
          },
        },
      },
    });
    // Ključevi koje API ne zna ne smiju otići.
    const flat = JSON.stringify(s);
    for (const k of ['additionalProperties', '$schema', 'anyOf', 'exclusiveMinimum', '"null"']) {
      expect(flat).not.toContain(k);
    }
  });

  it('klijent šalje izabranu varijantu i oba puta validira izlaz istom zod shemom', async () => {
    for (const field of ['responseJsonSchema', 'responseSchema'] as const) {
      const calls: Call[] = [];
      const recorder = new MemoryRunRecorder();
      const runId = await recorder.startRun({ step: 'score', model: 'm' });
      const { llm } = vertexClient(
        seqFetch([{ status: 200, body: ok('{"items":[{"id":1,"score":1.5,"note":null,"kind":"a"}]}') }], calls),
        recorder,
        { schemaField: field },
      );
      await expect(llm.generate({ prompt: 'p', schema: Out, runId })).rejects.toThrow(/shemu/);
      expect(Object.keys(calls[0]?.body.generationConfig as object)).toContain(field);
    }
  });
});

describe('gcloud token', () => {
  it('argumenti, keš 50 min, jedan proces za istodobne pozive', async () => {
    expect(gcloudTokenArgs('a@b.hr')).toEqual(['auth', 'print-access-token', '--account=a@b.hr']);
    expect(gcloudTokenArgs(null)).toEqual(['auth', 'print-access-token']);
    let t = 0;
    const seen: string[][] = [];
    const p = createGcloudTokenProvider({
      account: 'a@b.hr',
      now: () => t,
      execFile: (file, args) => {
        seen.push([file, ...args]);
        return Promise.resolve({ stdout: `token-${String(seen.length)}-xxxxxxxx\n` });
      },
    });
    const [a, b] = await Promise.all([p.token(), p.token()]);
    expect(a).toBe('token-1-xxxxxxxx');
    expect(b).toBe(a);
    t = 49 * 60_000;
    expect(await p.token()).toBe(a);
    t = 51 * 60_000;
    expect(await p.token()).toBe('token-2-xxxxxxxx');
    expect(p.fetches).toBe(2);
    expect(seen[0]).toEqual(['gcloud', 'auth', 'print-access-token', '--account=a@b.hr']);
  });

  it('greška gcloud-a nosi stderr, nikad stdout; prazan izlaz je greška', async () => {
    const failing = createGcloudTokenProvider({
      account: 'a@b.hr',
      execFile: () => Promise.reject(new Error('ERROR: Reauthentication required.')),
    });
    await expect(failing.token()).rejects.toThrow(/a@b\.hr.*Reauthentication/);
    const empty = createGcloudTokenProvider({ execFile: () => Promise.resolve({ stdout: '\n' }) });
    await expect(empty.token()).rejects.toThrow(/nije vratio token/);
  });
});

describe('konfiguracija backenda (odluke 300, 304)', () => {
  const NOV = Date.UTC(2026, 10, 5);
  it('zadano vertex bez GEMINI_API_KEY, studio s njim; izričit izbor pobjeđuje', () => {
    expect(llmConfigFromEnv({}, NOV)).toMatchObject({
      backend: 'vertex',
      vertex: { project: '', account: null, location: 'global' },
      schemaField: 'responseJsonSchema',
    });
    expect(llmConfigFromEnv({ GEMINI_API_KEY: 'k' }, NOV).backend).toBe('studio');
    expect(llmConfigFromEnv({ GEMINI_API_KEY: 'k', VIJESTI_LLM_BACKEND: 'vertex' }, NOV).backend).toBe('vertex');
    expect(
      llmConfigFromEnv(
        {
          VIJESTI_VERTEX_PROJECT: 'p',
          VIJESTI_VERTEX_ACCOUNT: 'a@b.hr',
          VIJESTI_VERTEX_LOCATION: 'eu',
          VIJESTI_GEMINI_SCHEMA_FIELD: 'responseSchema',
        },
        NOV,
      ),
    ).toMatchObject({
      vertex: { project: 'p', account: 'a@b.hr', location: 'eu' },
      schemaField: 'responseSchema',
      pricing: { inPerMTok: 0.825, outPerMTok: 4.125 },
    });
    expect(() => llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'openai' })).toThrow(/vertex, studio, agy/);
    expect(() => llmConfigFromEnv({ VIJESTI_GEMINI_SCHEMA_FIELD: 'schema' })).toThrow(/responseJsonSchema/);
  });

  it('cijena se sama udvostručuje 1.1.2027.; nepoznat model ili studio: nepoznata', () => {
    expect(defaultPricing('vertex', 'gemini-3.8-flash', 'global', Date.UTC(2026, 11, 31, 23, 59))).toEqual({
      inPerMTok: 0.75,
      outPerMTok: 3.75,
    });
    expect(defaultPricing('vertex', 'gemini-3.8-flash', 'global', Date.UTC(2027, 0, 1))).toEqual({
      inPerMTok: 1.5,
      outPerMTok: 7.5,
    });
    expect(defaultPricing('vertex', 'gemini-9-pro', 'global', NOV)).toBeNull();
    expect(defaultPricing('studio', 'gemini-3.8-flash', 'global', NOV)).toBeNull();
    // Cijena iz okoline pobjeđuje zadanu.
    expect(
      llmConfigFromEnv({ VIJESTI_GEMINI_PRICE_IN_PER_MTOK: '1', VIJESTI_GEMINI_PRICE_OUT_PER_MTOK: '2' }, NOV),
    ).toMatchObject({ pricing: { inPerMTok: 1, outPerMTok: 2 }, pricingSource: 'env' });
  });

  it('createLlmFromConfig: vertex s lažnim tokenom; opis bez tajni', async () => {
    const cfg = llmConfigFromEnv({ VIJESTI_VERTEX_PROJECT: 'p', VIJESTI_VERTEX_ACCOUNT: 'a@b.hr' }, NOV);
    const calls: Call[] = [];
    const recorder = new MemoryRunRecorder();
    const runId = await recorder.startRun({ step: 'score', model: cfg.model });
    const llm = createLlmFromConfig(cfg, {
      fetch: seqFetch([{ status: 200, body: ok(GOOD) }], calls),
      recorder,
      tokens: staticTokenProvider(TOKEN),
    });
    await llm.generate({ prompt: 'p', schema: Out, runId });
    expect(calls[0]?.url).toBe(vertexEndpointUrl('p', 'global', 'gemini-3.8-flash'));
    expect(recorder.get(runId).costUsd).toBeCloseTo((100 * 0.75 + 15 * 3.75) / 1e6, 12);
    const d = describeLlmConfig(cfg);
    expect(d).toContain('vertex p/global kao a@b.hr');
    expect(d).not.toContain(TOKEN);
    const studio = llmConfigFromEnv({ GEMINI_API_KEY: 'tajni-kljuc-12345' }, NOV);
    expect(describeLlmConfig(studio)).not.toContain('tajni-kljuc');
  });
});

describe('procjena bez poziva (odluka 305)', () => {
  it('tokeni ≈ znakovi / 3, trošak po cijeni', () => {
    expect(estimateTokens('abcdef')).toBe(2);
    expect(estimateTokens('abcdefg')).toBe(3);
    const e = estimatePrompts([{ prompt: 'x'.repeat(3000), system: 'y'.repeat(300) }, { prompt: 'z'.repeat(600) }], 500, {
      inPerMTok: 0.75,
      outPerMTok: 3.75,
    });
    expect(e).toMatchObject({ calls: 2, tokensIn: 1300, tokensOut: 1000 });
    expect(e.costUsd).toBeCloseTo((1300 * 0.75 + 1000 * 3.75) / 1e6, 12);
    expect(estimatePrompts([{ prompt: 'a' }], 1, null).costUsd).toBeNull();
  });
});

// Gemini klijent preko REST-a (generateContent) s injektiranim fetchom.
// Dva backenda s istim tijelom zahtjeva (odluka 300):
//   studio  AI Studio, ključ u zaglavlju `x-goog-api-key`, nikad u URL-u;
//   vertex  Vertex AI, `Authorization: Bearer <token>` iz ubrizganog izvora.
// Ključ i token se nikad ne logiraju i ne ulaze u poruke grešaka.
import { z } from 'zod';
import type { RunRecorder } from './runs.js';
import {
  costUsd,
  LlmResponseError,
  type GenerateRequest,
  type LlmClient,
  type LlmPricing,
  type LlmUsage,
} from './types.js';
import { parseLlmJson } from './validate.js';

export interface LlmFetchResponse {
  status: number;
  ok: boolean;
  text(): Promise<string>;
}
export type LlmFetch = (
  url: string,
  init: { method: 'POST'; headers: Record<string, string>; body: string },
) => Promise<LlmFetchResponse>;

export const GEMINI_API_BASE = 'https://generativelanguage.googleapis.com';

export type GeminiBackend = 'studio' | 'vertex';
/** Polje za shemu izlaza (odluke 110, 303): JSON Schema ili OpenAPI podskup. */
export type GeminiSchemaField = 'responseJsonSchema' | 'responseSchema';
export const GEMINI_SCHEMA_FIELDS: readonly GeminiSchemaField[] = ['responseJsonSchema', 'responseSchema'];

/** Izvor OAuth tokena za Vertex. `invalidate` nakon 401 da sljedeći poziv uzme novi. */
export interface AccessTokenProvider {
  token(): Promise<string>;
  invalidate(): void;
}

export interface VertexTarget {
  project: string;
  /** `global` (zadano), multi-regija `eu`/`us` ili regija (`europe-west4`). */
  location: string;
  tokens: AccessTokenProvider;
}

export interface RetryPolicy {
  /** Ponovni pokušaji nakon prvog (zadano 2). */
  retries: number;
  /** Čekanje prije n-tog ponovnog pokušaja: baseDelayMs × 2^(n−1). */
  baseDelayMs: number;
  sleep: (ms: number) => Promise<void>;
}

export const DEFAULT_RETRY: RetryPolicy = {
  retries: 2,
  baseDelayMs: 2000,
  sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
};

export interface GeminiClientOptions {
  fetch: LlmFetch;
  model: string;
  recorder: RunRecorder;
  pricing?: LlmPricing | null;
  /** Zadano `studio` kad je `apiKey` zadan (i prazan), inače `vertex`. */
  backend?: GeminiBackend;
  /** AI Studio ključ (backend `studio`). */
  apiKey?: string;
  /** Vertex projekt, lokacija i token (backend `vertex`). */
  vertex?: VertexTarget;
  /** Samo za `studio` (testovi). */
  baseUrl?: string;
  schemaField?: GeminiSchemaField;
  retry?: Partial<RetryPolicy>;
}

const ResponseSchema = z.object({
  candidates: z
    .array(
      z.object({
        content: z
          .object({
            parts: z
              .array(z.object({ text: z.string().optional(), thought: z.boolean().optional() }))
              .default([]),
          })
          .optional(),
        finishReason: z.string().optional(),
      }),
    )
    .default([]),
  usageMetadata: z
    .object({
      promptTokenCount: z.number().default(0),
      candidatesTokenCount: z.number().default(0),
      thoughtsTokenCount: z.number().default(0),
    })
    .optional(),
  promptFeedback: z.object({ blockReason: z.string().optional() }).optional(),
});

/** Zod → JSON Schema za `responseJsonSchema`, bez `$schema` ključa. */
export function toGeminiSchema(schema: z.ZodType): Record<string, unknown> {
  const json = z.toJSONSchema(schema, { target: 'draft-2020-12' }) as Record<string, unknown>;
  delete json.$schema;
  return json;
}

const OPENAPI_KEEP = new Set([
  'description',
  'title',
  'enum',
  'format',
  'minimum',
  'maximum',
  'minItems',
  'maxItems',
  'minLength',
  'maxLength',
  'pattern',
  'required',
]);

function isObj(v: unknown): v is Record<string, unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v);
}

/**
 * JSON Schema (iz `toGeminiSchema`) → `Schema` objekt API-ja (OpenAPI 3.0 podskup)
 * za `responseSchema`: tip velikim slovima, `null` u tipu/anyOf → `nullable`,
 * `const` → `enum`, svojstva koja API ne zna (`additionalProperties`,
 * `exclusiveMinimum`, `default`…) se izbacuju. Izlaz se i dalje validira zodom,
 * pa izbačena ograničenja ne prolaze tiho.
 */
export function toOpenApiSchema(json: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  const anyOf = json.anyOf;
  if (Array.isArray(anyOf)) {
    const parts = anyOf.filter(isObj);
    const nonNull = parts.filter((p) => p.type !== 'null');
    const nullable = nonNull.length < parts.length;
    if (nonNull.length === 1 && nonNull[0]) {
      const inner = toOpenApiSchema(nonNull[0]);
      return nullable ? { ...inner, nullable: true } : inner;
    }
    out.anyOf = nonNull.map((p) => toOpenApiSchema(p));
    if (nullable) out.nullable = true;
  }
  const type = json.type;
  if (typeof type === 'string') {
    if (type === 'null') out.nullable = true;
    else out.type = type.toUpperCase();
  } else if (Array.isArray(type)) {
    const types = type.filter((t): t is string => typeof t === 'string');
    const nonNull = types.filter((t) => t !== 'null');
    if (nonNull[0] !== undefined) out.type = nonNull[0].toUpperCase();
    if (nonNull.length < types.length) out.nullable = true;
  }
  if ('const' in json) out.enum = [json.const];
  for (const [k, v] of Object.entries(json)) {
    if (OPENAPI_KEEP.has(k)) out[k] = v;
  }
  if (isObj(json.properties)) {
    const props: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(json.properties)) {
      if (isObj(v)) props[k] = toOpenApiSchema(v);
    }
    out.properties = props;
    out.propertyOrdering = Object.keys(props);
  }
  if (isObj(json.items)) out.items = toOpenApiSchema(json.items);
  return out;
}

/** Tijelo `generateContent`, isto za oba backenda. */
export function buildGeminiBody(
  req: Pick<GenerateRequest<z.ZodType>, 'prompt' | 'schema' | 'system' | 'temperature'>,
  schemaField: GeminiSchemaField = 'responseJsonSchema',
): Record<string, unknown> {
  const json = toGeminiSchema(req.schema);
  return {
    contents: [{ role: 'user', parts: [{ text: req.prompt }] }],
    ...(req.system !== undefined && { systemInstruction: { parts: [{ text: req.system }] } }),
    generationConfig: {
      responseMimeType: 'application/json',
      ...(schemaField === 'responseJsonSchema'
        ? { responseJsonSchema: json }
        : { responseSchema: toOpenApiSchema(json) }),
      ...(req.temperature !== undefined && { temperature: req.temperature }),
    },
  };
}

const MULTI_REGIONS = new Set(['eu', 'us']);
const LOCATION_RE = /^[a-z0-9-]+$/;

/** URL kao u pipelineu (`fetch.domovina.tv/lib/vertex_auth.js`). */
export function vertexEndpointUrl(project: string, location: string, model: string): string {
  if (!LOCATION_RE.test(location)) throw new Error(`neispravna Vertex lokacija: ${location}`);
  const host =
    location === 'global'
      ? 'aiplatform.googleapis.com'
      : MULTI_REGIONS.has(location)
        ? `aiplatform.${location}.rep.googleapis.com`
        : `${location}-aiplatform.googleapis.com`;
  return (
    `https://${host}/v1/projects/${encodeURIComponent(project)}/locations/${location}` +
    `/publishers/google/models/${encodeURIComponent(model)}:generateContent`
  );
}

export function usageFrom(body: z.infer<typeof ResponseSchema>): LlmUsage {
  const u = body.usageMetadata;
  return {
    tokensIn: u?.promptTokenCount ?? 0,
    // „Thinking” tokeni se naplaćuju kao izlaz.
    tokensOut: (u?.candidatesTokenCount ?? 0) + (u?.thoughtsTokenCount ?? 0),
  };
}

/** 429 (kvota globalnog bazena) i 5xx se ponavljaju; ostalo ne. */
export function isRetryableStatus(status: number): boolean {
  return status === 429 || (status >= 500 && status <= 599);
}

function redact(text: string, secrets: readonly string[]): string {
  let out = text;
  for (const s of secrets) if (s.length >= 8) out = out.split(s).join('[skriveno]');
  return out;
}

export function createGeminiClient(opts: GeminiClientOptions): LlmClient {
  const backend: GeminiBackend = opts.backend ?? (opts.apiKey !== undefined ? 'studio' : 'vertex');
  const apiKey = opts.apiKey ?? '';
  const vertex = opts.vertex;
  let url: string;
  if (backend === 'studio') {
    if (!apiKey) throw new Error('GEMINI_API_KEY nije postavljen (vijesti/.env)');
    const base = (opts.baseUrl ?? GEMINI_API_BASE).replace(/\/+$/, '');
    url = `${base}/v1beta/models/${encodeURIComponent(opts.model)}:generateContent`;
  } else {
    if (!vertex?.project) throw new Error('VIJESTI_VERTEX_PROJECT nije postavljen (vijesti/.env)');
    url = vertexEndpointUrl(vertex.project, vertex.location || 'global', opts.model);
  }
  const pricing = opts.pricing ?? null;
  const schemaField = opts.schemaField ?? 'responseJsonSchema';
  const retry: RetryPolicy = { ...DEFAULT_RETRY, ...opts.retry };
  const label = backend === 'vertex' ? 'Vertex' : 'Gemini';

  return {
    model: opts.model,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      const body = JSON.stringify(buildGeminiBody(req, schemaField));
      const record = (usage: LlmUsage, ok: boolean) =>
        opts.recorder.recordCall(req.runId, {
          model: opts.model,
          ...usage,
          costUsd: costUsd(usage, pricing),
          ok,
        });

      for (let attempt = 0; ; attempt++) {
        // Token prije zahtjeva: ako ga nema, zahtjev nije poslan i nije poziv.
        const secret = backend === 'vertex' && vertex ? await vertex.tokens.token() : apiKey;
        const headers: Record<string, string> =
          backend === 'vertex'
            ? { 'content-type': 'application/json', authorization: `Bearer ${secret}` }
            : { 'content-type': 'application/json', 'x-goog-api-key': secret };
        let res: LlmFetchResponse;
        let text: string;
        try {
          res = await opts.fetch(url, { method: 'POST', headers, body });
          text = await res.text();
        } catch (e) {
          // Prekid (mreža, timeout, odgovor prekinut usred tijela) se broji kao
          // neuspio poziv (odluka 107); tokeni nisu poznati. Ne ponavlja se.
          await record({ tokensIn: 0, tokensOut: 0 }, false);
          throw e;
        }
        if (!res.ok) {
          // Svaki pokušaj je poziv (odluke 107, 117, 302).
          await record({ tokensIn: 0, tokensOut: 0 }, false);
          if (res.status === 401 && vertex) vertex.tokens.invalidate();
          if (isRetryableStatus(res.status) && attempt < retry.retries) {
            await retry.sleep(retry.baseDelayMs * 2 ** attempt);
            continue;
          }
          throw new LlmResponseError(
            `${label} HTTP ${String(res.status)}: ${redact(text.slice(0, 300), [secret])}`,
            res.status,
          );
        }

        let parsed: z.infer<typeof ResponseSchema>;
        try {
          parsed = ResponseSchema.parse(JSON.parse(text));
        } catch (e) {
          await record({ tokensIn: 0, tokensOut: 0 }, false);
          throw new LlmResponseError(`${label}: nečitljiv odgovor (${(e as Error).message})`, res.status);
        }
        const usage = usageFrom(parsed);
        const cand = parsed.candidates[0];
        const out = (cand?.content?.parts ?? [])
          .filter((p) => p.thought !== true && p.text !== undefined)
          .map((p) => p.text)
          .join('');
        if (!cand || out === '' || (cand.finishReason && cand.finishReason !== 'STOP')) {
          await record(usage, false);
          const why = parsed.promptFeedback?.blockReason ?? cand?.finishReason ?? 'nema kandidata';
          throw new LlmResponseError(`${label}: nema upotrebljivog izlaza (${why})`, res.status);
        }
        try {
          const data = parseLlmJson(out, req.schema);
          await record(usage, true);
          return data;
        } catch (e) {
          await record(usage, false);
          throw e;
        }
      }
    },
  };
}

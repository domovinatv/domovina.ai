// Konfiguracija LLM-a iz okoline (vijesti/.env). Ključ i token se nikad ne logiraju.
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  createGeminiClient,
  GEMINI_SCHEMA_FIELDS,
  type AccessTokenProvider,
  type GeminiBackend,
  type GeminiSchemaField,
  type LlmFetch,
  type RetryPolicy,
} from './gemini.js';
import type { RunRecorder } from './runs.js';
import type { LlmClient, LlmPricing } from './types.js';
import { createGcloudTokenProvider } from './vertex-auth.js';

/** Model pipelinea od 15.9.2026. (`fetch.domovina.tv/gemini.conf`), odluka 301. */
export const DEFAULT_GEMINI_MODEL = 'gemini-3.8-flash';
export const DEFAULT_VERTEX_LOCATION = 'global';
export const ENV_FILE = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.env');

export interface VertexConfig {
  project: string;
  account: string | null;
  location: string;
}

export interface LlmConfig {
  backend: GeminiBackend;
  apiKey: string;
  model: string;
  pricing: LlmPricing | null;
  /** Odakle je cijena: env, zadani cjenik u kodu (odluka 304) ili nepoznata. */
  pricingSource: 'env' | 'default' | null;
  vertex: VertexConfig;
  schemaField: GeminiSchemaField;
}

/** Učita vijesti/.env u process.env ako postoji (Node 22+ `loadEnvFile`). */
export function loadDotEnv(path: string = ENV_FILE): boolean {
  if (!existsSync(path)) return false;
  process.loadEnvFile(path);
  return true;
}

function price(env: Record<string, string | undefined>, key: string): number | null {
  const raw = env[key]?.trim();
  if (!raw) return null;
  const n = Number(raw);
  if (!Number.isFinite(n) || n < 0) throw new Error(`${key} nije nenegativan broj: ${raw}`);
  return n;
}

/**
 * Zadani cjenik Vertexa (USD / M tokena), odluka 304. Izvor:
 * cloud.google.com/vertex-ai/generative-ai/pricing, prepisano i provjereno u
 * `fetch.domovina.tv/gemini.conf` 28.9.2026. gemini-3.8-flash na `global`:
 * $0,75 / $3,75 PROMOTIVNO do 31.12.2026.; od 1.1.2027. $1,50 / $7,50, bez
 * ikakve promjene u kodu (zato je datum u tablici). Ne-global lokacije (`eu`,
 * `us`) su +10 %. AI Studio nema zadanu cijenu (nije provjerena).
 */
export const VERTEX_PRICES: Record<
  string,
  { promoUntilUtc: number; promo: LlmPricing; regular: LlmPricing }
> = {
  'gemini-3.8-flash': {
    promoUntilUtc: Date.UTC(2027, 0, 1),
    promo: { inPerMTok: 0.75, outPerMTok: 3.75 },
    regular: { inPerMTok: 1.5, outPerMTok: 7.5 },
  },
};
export const NON_GLOBAL_PRICE_FACTOR = 1.1;

export function defaultPricing(
  backend: GeminiBackend,
  model: string,
  location: string,
  nowMs: number = Date.now(),
): LlmPricing | null {
  if (backend !== 'vertex') return null;
  const p = VERTEX_PRICES[model];
  if (!p) return null;
  const base = nowMs < p.promoUntilUtc ? p.promo : p.regular;
  const f = location === 'global' ? 1 : NON_GLOBAL_PRICE_FACTOR;
  // Zaokruženo na 6 decimala da 0,75 × 1,1 ne postane 0,8250000000000001.
  const r = (n: number) => Math.round(n * f * 1e6) / 1e6;
  return { inPerMTok: r(base.inPerMTok), outPerMTok: r(base.outPerMTok) };
}

export function llmConfigFromEnv(
  env: Record<string, string | undefined> = process.env,
  nowMs: number = Date.now(),
): LlmConfig {
  const apiKey = env.GEMINI_API_KEY?.trim() ?? '';
  const rawBackend = env.VIJESTI_LLM_BACKEND?.trim();
  let backend: GeminiBackend;
  if (!rawBackend) backend = apiKey ? 'studio' : 'vertex';
  else if (rawBackend === 'vertex' || rawBackend === 'studio') backend = rawBackend;
  else throw new Error(`VIJESTI_LLM_BACKEND mora biti vertex ili studio: ${rawBackend}`);

  const rawField = env.VIJESTI_GEMINI_SCHEMA_FIELD?.trim();
  let schemaField: GeminiSchemaField = 'responseJsonSchema';
  if (rawField) {
    if (!(GEMINI_SCHEMA_FIELDS as readonly string[]).includes(rawField)) {
      throw new Error(`VIJESTI_GEMINI_SCHEMA_FIELD mora biti ${GEMINI_SCHEMA_FIELDS.join(' ili ')}: ${rawField}`);
    }
    schemaField = rawField as GeminiSchemaField;
  }

  const model = env.VIJESTI_GEMINI_MODEL?.trim() || DEFAULT_GEMINI_MODEL;
  const vertex: VertexConfig = {
    project: env.VIJESTI_VERTEX_PROJECT?.trim() ?? '',
    account: env.VIJESTI_VERTEX_ACCOUNT?.trim() || null,
    location: env.VIJESTI_VERTEX_LOCATION?.trim() || DEFAULT_VERTEX_LOCATION,
  };

  const inPer = price(env, 'VIJESTI_GEMINI_PRICE_IN_PER_MTOK');
  const outPer = price(env, 'VIJESTI_GEMINI_PRICE_OUT_PER_MTOK');
  if ((inPer === null) !== (outPer === null)) {
    throw new Error('cijena modela treba i ulaz i izlaz (VIJESTI_GEMINI_PRICE_*_PER_MTOK)');
  }
  let pricing: LlmPricing | null;
  let pricingSource: LlmConfig['pricingSource'] = null;
  if (inPer !== null && outPer !== null) {
    pricing = { inPerMTok: inPer, outPerMTok: outPer };
    pricingSource = 'env';
  } else {
    pricing = defaultPricing(backend, model, vertex.location, nowMs);
    if (pricing) pricingSource = 'default';
  }
  return { backend, apiKey, model, pricing, pricingSource, vertex, schemaField };
}

export interface LlmClientDeps {
  fetch: LlmFetch;
  recorder: RunRecorder;
  /** Zadano gcloud s `VIJESTI_VERTEX_ACCOUNT` (testovi daju lažni). */
  tokens?: AccessTokenProvider;
  retry?: Partial<RetryPolicy>;
}

/** Pravi Gemini klijent po konfiguraciji (CLI, eval). */
export function createLlmFromConfig(cfg: LlmConfig, deps: LlmClientDeps): LlmClient {
  if (cfg.backend === 'studio') {
    return createGeminiClient({
      backend: 'studio',
      fetch: deps.fetch,
      apiKey: cfg.apiKey,
      model: cfg.model,
      pricing: cfg.pricing,
      recorder: deps.recorder,
      schemaField: cfg.schemaField,
      ...(deps.retry && { retry: deps.retry }),
    });
  }
  return createGeminiClient({
    backend: 'vertex',
    fetch: deps.fetch,
    model: cfg.model,
    pricing: cfg.pricing,
    recorder: deps.recorder,
    schemaField: cfg.schemaField,
    vertex: {
      project: cfg.vertex.project,
      location: cfg.vertex.location,
      tokens: deps.tokens ?? createGcloudTokenProvider({ account: cfg.vertex.account }),
    },
    ...(deps.retry && { retry: deps.retry }),
  });
}

/** Jedan redak za ispis prije pokretanja (bez ključa i tokena). */
export function describeLlmConfig(cfg: LlmConfig): string {
  const where =
    cfg.backend === 'vertex'
      ? `vertex ${cfg.vertex.project || '(bez projekta)'}/${cfg.vertex.location}${cfg.vertex.account ? ` kao ${cfg.vertex.account}` : ''}`
      : 'studio';
  const p = cfg.pricing
    ? `$${String(cfg.pricing.inPerMTok)}/$${String(cfg.pricing.outPerMTok)} po M (${cfg.pricingSource ?? '?'})`
    : 'cijena nepoznata';
  return `${where}  model=${cfg.model}  shema=${cfg.schemaField}  ${p}`;
}

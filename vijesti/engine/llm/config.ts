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
import {
  createAgyClient,
  createTmuxAgyIo,
  DEFAULT_AGY_MODEL,
  DEFAULT_AGY_ROOT,
  DEFAULT_AGY_SESSION,
  DEFAULT_AGY_TIMEOUT_MS,
  type AgyIo,
} from './agy.js';
import { createClaudeClient, DEFAULT_CLAUDE_MODEL, DEFAULT_CLAUDE_TIMEOUT_MS, type ClaudeExec } from './claude.js';
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

/** `agy`: Gemini kroz Antigravity CLI u tmuxu, na pretplati (odluke 315, 400). */
/** `claude`: Claude Code CLI (`claude -p`) na pretplati, odluka 802. */
export type LlmBackend = GeminiBackend | 'agy' | 'claude';
export const LLM_BACKENDS: readonly LlmBackend[] = ['vertex', 'studio', 'agy', 'claude'];

export interface ClaudeConfig {
  model: string;
  timeoutMs: number;
}

export interface AgyConfig {
  session: string;
  /** Model unutar agyja (`--model`), npr. `gemini-3.8-flash-high`. */
  model: string;
  dir: string;
  timeoutMs: number;
}

export interface LlmConfig {
  backend: LlmBackend;
  apiKey: string;
  model: string;
  pricing: LlmPricing | null;
  /** Odakle je cijena: env, zadani cjenik u kodu (odluka 304), pretplata (agy, $0) ili nepoznata. */
  pricingSource: 'env' | 'default' | 'subscription' | null;
  vertex: VertexConfig;
  agy: AgyConfig;
  claude: ClaudeConfig;
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
  backend: LlmBackend,
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
  let backend: LlmBackend;
  if (!rawBackend) backend = apiKey ? 'studio' : 'vertex';
  else if ((LLM_BACKENDS as readonly string[]).includes(rawBackend)) backend = rawBackend as LlmBackend;
  else throw new Error(`VIJESTI_LLM_BACKEND mora biti ${LLM_BACKENDS.join(', ')}: ${rawBackend}`);

  const session = env.VIJESTI_AGY_SESSION?.trim() || DEFAULT_AGY_SESSION;
  const rawTimeout = env.VIJESTI_AGY_TIMEOUT_SEC?.trim();
  const timeoutSec = rawTimeout ? Number(rawTimeout) : DEFAULT_AGY_TIMEOUT_MS / 1000;
  if (!Number.isFinite(timeoutSec) || timeoutSec <= 0) {
    throw new Error(`VIJESTI_AGY_TIMEOUT_SEC nije pozitivan broj: ${rawTimeout ?? ''}`);
  }
  const agy: AgyConfig = {
    session,
    model: env.VIJESTI_AGY_MODEL?.trim() || DEFAULT_AGY_MODEL,
    dir: env.VIJESTI_AGY_DIR?.trim() || `${DEFAULT_AGY_ROOT}/${session}`,
    timeoutMs: timeoutSec * 1000,
  };

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
  if (backend === 'agy' || backend === 'claude') {
    // Pretplata (Google AI Pro / Claude): stvarni trošak je $0; env cijena se ne primjenjuje.
    pricing = { inPerMTok: 0, outPerMTok: 0 };
    pricingSource = 'subscription';
  } else if (inPer !== null && outPer !== null) {
    pricing = { inPerMTok: inPer, outPerMTok: outPer };
    pricingSource = 'env';
  } else {
    pricing = defaultPricing(backend, model, vertex.location, nowMs);
    if (pricing) pricingSource = 'default';
  }
  const rawClaudeTimeout = env.VIJESTI_CLAUDE_TIMEOUT_SEC?.trim();
  const claudeTimeoutSec = rawClaudeTimeout ? Number(rawClaudeTimeout) : DEFAULT_CLAUDE_TIMEOUT_MS / 1000;
  if (!Number.isFinite(claudeTimeoutSec) || claudeTimeoutSec <= 0) {
    throw new Error(`VIJESTI_CLAUDE_TIMEOUT_SEC nije pozitivan broj: ${rawClaudeTimeout ?? ''}`);
  }
  const claude: ClaudeConfig = {
    model: env.VIJESTI_CLAUDE_MODEL?.trim() || DEFAULT_CLAUDE_MODEL,
    timeoutMs: claudeTimeoutSec * 1000,
  };
  return { backend, apiKey, model, pricing, pricingSource, vertex, agy, claude, schemaField };
}

export interface LlmClientDeps {
  fetch: LlmFetch;
  recorder: RunRecorder;
  /** Zadano gcloud s `VIJESTI_VERTEX_ACCOUNT` (testovi daju lažni). */
  tokens?: AccessTokenProvider;
  retry?: Partial<RetryPolicy>;
  /** Zadano pravi tmux (testovi daju lažni sloj). */
  agyIo?: AgyIo;
  /** Zadano pravi `claude` proces (testovi daju lažni). */
  claudeExec?: ClaudeExec;
}

/** Pravi Gemini klijent po konfiguraciji (CLI, eval). */
export function createLlmFromConfig(cfg: LlmConfig, deps: LlmClientDeps): LlmClient {
  if (cfg.backend === 'claude') {
    return createClaudeClient({
      recorder: deps.recorder,
      model: cfg.claude.model,
      timeoutMs: cfg.claude.timeoutMs,
      ...(deps.claudeExec && { exec: deps.claudeExec }),
    });
  }
  if (cfg.backend === 'agy') {
    return createAgyClient({
      io: deps.agyIo ?? createTmuxAgyIo(),
      recorder: deps.recorder,
      model: cfg.agy.model,
      session: cfg.agy.session,
      dir: cfg.agy.dir,
      timeoutMs: cfg.agy.timeoutMs,
    });
  }
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
  if (cfg.backend === 'claude') {
    return (
      `claude -p model=${cfg.claude.model} timeout=${String(cfg.claude.timeoutMs / 1000)} s  ` +
      `$0 (pretplata, troši Claude kvotu), tokeni izmjereni`
    );
  }
  if (cfg.backend === 'agy') {
    return (
      `agy tmux=${cfg.agy.session} model=${cfg.agy.model} dir=${cfg.agy.dir} ` +
      `timeout=${String(cfg.agy.timeoutMs / 1000)} s  $0 (pretplata), tokeni = procjena iz znakova`
    );
  }
  const where =
    cfg.backend === 'vertex'
      ? `vertex ${cfg.vertex.project || '(bez projekta)'}/${cfg.vertex.location}${cfg.vertex.account ? ` kao ${cfg.vertex.account}` : ''}`
      : 'studio';
  const p = cfg.pricing
    ? `$${String(cfg.pricing.inPerMTok)}/$${String(cfg.pricing.outPerMTok)} po M (${cfg.pricingSource ?? '?'})`
    : 'cijena nepoznata';
  return `${where}  model=${cfg.model}  shema=${cfg.schemaField}  ${p}`;
}

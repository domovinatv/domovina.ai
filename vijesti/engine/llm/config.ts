// Konfiguracija LLM-a iz okoline (vijesti/.env). Ključ se nikad ne logira.
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { LlmPricing } from './types.js';

export const DEFAULT_GEMINI_MODEL = 'gemini-3.5-flash';
export const ENV_FILE = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '.env');

export interface LlmConfig {
  apiKey: string;
  model: string;
  pricing: LlmPricing | null;
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

export function llmConfigFromEnv(env: Record<string, string | undefined> = process.env): LlmConfig {
  const inPer = price(env, 'VIJESTI_GEMINI_PRICE_IN_PER_MTOK');
  const outPer = price(env, 'VIJESTI_GEMINI_PRICE_OUT_PER_MTOK');
  if ((inPer === null) !== (outPer === null)) {
    throw new Error('cijena modela treba i ulaz i izlaz (VIJESTI_GEMINI_PRICE_*_PER_MTOK)');
  }
  return {
    apiKey: env.GEMINI_API_KEY?.trim() ?? '',
    model: env.VIJESTI_GEMINI_MODEL?.trim() || DEFAULT_GEMINI_MODEL,
    pricing: inPer !== null && outPer !== null ? { inPerMTok: inPer, outPerMTok: outPer } : null,
  };
}

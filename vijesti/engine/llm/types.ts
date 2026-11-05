import type { z } from 'zod';

export interface GenerateRequest<S extends z.ZodType> {
  prompt: string;
  /** Zod shema izlaza; Geminiju ide kao JSON Schema, odgovor se njome validira. */
  schema: S;
  /** `vijesti.runs.id`: svaki poziv se broji u svoj prolaz. */
  runId: number;
  system?: string;
  temperature?: number;
  /** Ime poziva (npr. `extract-moments`); lažni klijent po njemu bira snimku. */
  name?: string;
}

export interface LlmClient {
  readonly model: string;
  /** Validiran izlaz. Odgovor koji ne prolazi shemu baca `LlmSchemaError`. */
  generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>>;
}

export interface LlmUsage {
  tokensIn: number;
  tokensOut: number;
}

export interface LlmPricing {
  /** USD po milijun ulaznih tokena. */
  inPerMTok: number;
  /** USD po milijun izlaznih tokena (uključuje „thinking” tokene). */
  outPerMTok: number;
}

export function costUsd(usage: LlmUsage, pricing: LlmPricing | null): number | null {
  if (!pricing) return null;
  return (usage.tokensIn * pricing.inPerMTok + usage.tokensOut * pricing.outPerMTok) / 1_000_000;
}

/** Izlaz modela nije JSON ili ne prolazi shemu. Nikad se ne popravlja tiho. */
export class LlmSchemaError extends Error {
  constructor(
    message: string,
    readonly raw: string,
  ) {
    super(message);
    this.name = 'LlmSchemaError';
  }
}

/** HTTP greška ili odgovor bez upotrebljivog teksta (blokiran, prekinut). */
export class LlmResponseError extends Error {
  constructor(
    message: string,
    readonly status?: number,
  ) {
    super(message);
    this.name = 'LlmResponseError';
  }
}

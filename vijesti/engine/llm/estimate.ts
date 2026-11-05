// Procjena tokena i troška iz izgrađenih promptova, BEZ poziva modela (za
// `npm run eval` prije pokretanja, odluka 305). Gemini tokenizator nije
// dostupan offline; omjer znakova po tokenu je pretpostavka dok prvi pravi
// poziv ne da `usageMetadata.promptTokenCount` za usporedbu.
import { costUsd, type LlmPricing } from './types.js';

/** Znakova po tokenu: konzervativno (hrvatski s dijakritikom troši više tokena od engleskog). */
export const CHARS_PER_TOKEN = 3;

export function estimateTokens(text: string): number {
  return Math.ceil(text.length / CHARS_PER_TOKEN);
}

export interface PromptEstimate {
  calls: number;
  tokensIn: number;
  /** Pretpostavljeni izlaz po pozivu × broj poziva (uključuje „thinking”). */
  tokensOut: number;
  costUsd: number | null;
}

export function estimatePrompts(
  prompts: readonly { prompt: string; system?: string | undefined }[],
  outTokensPerCall: number,
  pricing: LlmPricing | null,
): PromptEstimate {
  const tokensIn = prompts.reduce(
    (n, p) => n + estimateTokens(p.prompt) + (p.system ? estimateTokens(p.system) : 0),
    0,
  );
  const tokensOut = prompts.length * outTokensPerCall;
  return { calls: prompts.length, tokensIn, tokensOut, costUsd: costUsd({ tokensIn, tokensOut }, pricing) };
}

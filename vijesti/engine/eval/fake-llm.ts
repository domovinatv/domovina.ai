// Lažni LLM za `npm run eval -- --fake`: izvlačenje, ocjena, članak i provjera
// iz istih determinističkih funkcija kao `extract --fake`, `score --fake`,
// `write --fake` i `verify --fake` (odluke 209, 313, 424), po imenu poziva.
// Tokeni se procjenjuju iz znakova i run se označi kao procjena, kao kod
// agyja, pa izvještaj na --fake uzorku prolazi istu granu kao pravi agy
// uzorak (odluka 410). Trošak 0.
import type { z } from 'zod';
import { fakeExtractResponse } from '../extract/fake-llm.js';
import { PROMPT_NAME as EXTRACT_PROMPT_NAME } from '../extract/prompt.js';
import { estimateTokens } from '../llm/estimate.js';
import type { RunRecorder } from '../llm/runs.js';
import type { GenerateRequest, LlmClient } from '../llm/types.js';
import { parseLlmJson } from '../llm/validate.js';
import { fakeScoreResponse } from '../score/fake-llm.js';
import { PROMPT_NAME as SCORE_PROMPT_NAME } from '../score/prompt.js';
import { fakeVerifyResponse } from '../verify/article-fake-llm.js';
import { PROMPT_NAME as VERIFY_PROMPT_NAME } from '../verify/article-prompt.js';
import { fakeWriteResponse } from '../write/fake-llm.js';
import { PROMPT_NAME as WRITE_PROMPT_NAME } from '../write/prompt.js';

export const FAKE_EVAL_MODEL = 'fake-eval';

export function createFakeEvalLlm(recorder: RunRecorder): LlmClient & { calls: number } {
  const client = {
    model: FAKE_EVAL_MODEL,
    calls: 0,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      client.calls++;
      let text: string;
      if (req.name === EXTRACT_PROMPT_NAME) text = fakeExtractResponse(req.prompt);
      else if (req.name === SCORE_PROMPT_NAME) text = fakeScoreResponse(req.prompt);
      else if (req.name === WRITE_PROMPT_NAME) text = fakeWriteResponse(req.prompt);
      else if (req.name === VERIFY_PROMPT_NAME) text = fakeVerifyResponse(req.prompt);
      else throw new Error(`lažni eval LLM ne zna poziv ${req.name ?? '(bez imena)'}`);
      const usage = {
        tokensIn: estimateTokens(req.prompt) + (req.system ? estimateTokens(req.system) : 0),
        tokensOut: estimateTokens(text),
      };
      const record = (ok: boolean) =>
        recorder.recordCall(req.runId, { model: FAKE_EVAL_MODEL, ...usage, costUsd: 0, ok, tokensEstimated: true });
      try {
        const data = parseLlmJson(text, req.schema);
        await record(true);
        return data;
      } catch (e) {
        await record(false);
        throw e;
      }
    },
  };
  return client;
}

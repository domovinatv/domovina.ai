// Gemini klijent preko REST-a (generateContent) s injektiranim fetchom.
// Ključ ide u zaglavlje `x-goog-api-key`, nikad u URL (ne smije u logove).
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

export interface GeminiClientOptions {
  fetch: LlmFetch;
  apiKey: string;
  model: string;
  recorder: RunRecorder;
  pricing?: LlmPricing | null;
  baseUrl?: string;
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

export function usageFrom(body: z.infer<typeof ResponseSchema>): LlmUsage {
  const u = body.usageMetadata;
  return {
    tokensIn: u?.promptTokenCount ?? 0,
    // „Thinking” tokeni se naplaćuju kao izlaz.
    tokensOut: (u?.candidatesTokenCount ?? 0) + (u?.thoughtsTokenCount ?? 0),
  };
}

export function createGeminiClient(opts: GeminiClientOptions): LlmClient {
  if (!opts.apiKey) throw new Error('GEMINI_API_KEY nije postavljen (vijesti/.env)');
  const base = (opts.baseUrl ?? GEMINI_API_BASE).replace(/\/+$/, '');
  const url = `${base}/v1beta/models/${encodeURIComponent(opts.model)}:generateContent`;
  const pricing = opts.pricing ?? null;

  return {
    model: opts.model,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      const body = {
        contents: [{ role: 'user', parts: [{ text: req.prompt }] }],
        ...(req.system !== undefined && { systemInstruction: { parts: [{ text: req.system }] } }),
        generationConfig: {
          responseMimeType: 'application/json',
          responseJsonSchema: toGeminiSchema(req.schema),
          ...(req.temperature !== undefined && { temperature: req.temperature }),
        },
      };
      const record = (usage: LlmUsage, ok: boolean) =>
        opts.recorder.recordCall(req.runId, {
          model: opts.model,
          ...usage,
          costUsd: costUsd(usage, pricing),
          ok,
        });

      const res = await opts.fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'x-goog-api-key': opts.apiKey },
        body: JSON.stringify(body),
      });
      const text = await res.text();
      if (!res.ok) {
        await record({ tokensIn: 0, tokensOut: 0 }, false);
        throw new LlmResponseError(`Gemini HTTP ${String(res.status)}: ${text.slice(0, 300)}`, res.status);
      }

      let parsed: z.infer<typeof ResponseSchema>;
      try {
        parsed = ResponseSchema.parse(JSON.parse(text));
      } catch (e) {
        await record({ tokensIn: 0, tokensOut: 0 }, false);
        throw new LlmResponseError(`Gemini: nečitljiv odgovor (${(e as Error).message})`, res.status);
      }
      const usage = usageFrom(parsed);
      const cand = parsed.candidates[0];
      const out = (cand?.content?.parts ?? [])
        .filter((p) => p.thought !== true && p.text !== undefined)
        .map((p) => p.text)
        .join('');
      if (!cand || out === '' || (cand.finishReason && cand.finishReason !== 'STOP')) {
        await record(usage, false);
        const why =
          parsed.promptFeedback?.blockReason ?? cand?.finishReason ?? 'nema kandidata';
        throw new LlmResponseError(`Gemini: nema upotrebljivog izlaza (${why})`, res.status);
      }
      try {
        const data = parseLlmJson(out, req.schema);
        await record(usage, true);
        return data;
      } catch (e) {
        await record(usage, false);
        throw e;
      }
    },
  };
}

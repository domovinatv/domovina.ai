// Lažni LlmClient: vraća snimljene odgovore (tekst modela + potrošnju) i
// validira ih ISTOM funkcijom kao pravi klijent. Svaki poziv se broji.
import { readFile, readdir } from 'node:fs/promises';
import { join } from 'node:path';
import { z } from 'zod';
import type { RunRecorder } from './runs.js';
import type { GenerateRequest, LlmClient } from './types.js';
import { parseLlmJson } from './validate.js';

export const RecordedResponseSchema = z.object({
  /** Sirovi tekst koji bi model vratio (JSON kao string). */
  text: z.string(),
  usage: z.object({ tokensIn: z.number(), tokensOut: z.number() }).default({
    tokensIn: 0,
    tokensOut: 0,
  }),
});
export type RecordedResponse = z.infer<typeof RecordedResponseSchema>;

export class FakeLlmMissingError extends Error {
  constructor(name: string | undefined) {
    super(`lažni LLM nema snimljen odgovor${name ? ` za „${name}”` : ''}`);
    this.name = 'FakeLlmMissingError';
  }
}

export interface FakeLlmOptions {
  recorder: RunRecorder;
  /** Odgovori po imenu poziva (`req.name`). */
  byName?: Record<string, RecordedResponse>;
  /** Odgovori redom, za pozive bez imena ili bez snimke po imenu. */
  queue?: RecordedResponse[];
  model?: string;
}

export interface FakeLlmClient extends LlmClient {
  /** Svi zahtjevi, redom (prompt, ime). */
  readonly requests: { name: string | undefined; prompt: string; runId: number }[];
}

export function createFakeLlmClient(opts: FakeLlmOptions): FakeLlmClient {
  const queue = [...(opts.queue ?? [])];
  const model = opts.model ?? 'fake';
  const requests: FakeLlmClient['requests'] = [];
  return {
    model,
    requests,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      requests.push({ name: req.name, prompt: req.prompt, runId: req.runId });
      const rec = (req.name !== undefined ? opts.byName?.[req.name] : undefined) ?? queue.shift();
      if (!rec) throw new FakeLlmMissingError(req.name);
      try {
        const data = parseLlmJson(rec.text, req.schema);
        await opts.recorder.recordCall(req.runId, { model, ...rec.usage, costUsd: null, ok: true });
        return data;
      } catch (e) {
        await opts.recorder.recordCall(req.runId, { model, ...rec.usage, costUsd: null, ok: false });
        throw e;
      }
    },
  };
}

/** Učita snimke iz direktorija: `<ime>.json` = `{"text": "...", "usage": {...}}`. */
export async function loadRecordedResponses(dir: string): Promise<Record<string, RecordedResponse>> {
  const out: Record<string, RecordedResponse> = {};
  for (const file of (await readdir(dir)).filter((f) => f.endsWith('.json')).sort()) {
    const raw: unknown = JSON.parse(await readFile(join(dir, file), 'utf8'));
    out[file.replace(/\.json$/, '')] = RecordedResponseSchema.parse(raw);
  }
  return out;
}

/**
 * Lažni klijent koji odgovor DETERMINISTIČKI gradi iz zahtjeva (`write --fake`,
 * `verify --fake`): isti `parseLlmJson`, isto brojanje poziva, trošak 0.
 */
export function createResponderLlm(
  model: string,
  recorder: RunRecorder,
  respond: (req: GenerateRequest<z.ZodType>) => string,
): LlmClient & { calls: number } {
  const client = {
    model,
    calls: 0,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      client.calls++;
      const usage = { tokensIn: 0, tokensOut: 0 };
      try {
        const data = parseLlmJson(respond(req), req.schema);
        await recorder.recordCall(req.runId, { model, ...usage, costUsd: 0, ok: true });
        return data;
      } catch (e) {
        await recorder.recordCall(req.runId, { model, ...usage, costUsd: 0, ok: false });
        throw e;
      }
    },
  };
  return client;
}

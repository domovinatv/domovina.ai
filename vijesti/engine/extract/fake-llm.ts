// Lažni LLM za `vijesti extract --fake` (odluka 209): iz redaka transkripta u
// promptu DETERMINISTIČKI sastavi odgovor (1–2 najdulja cuea s oznakom
// govornika kao doslovne citate) i pusti ga kroz istu validaciju i isto
// brojanje poziva kao pravi klijent. Ne zove mrežu.
import type { z } from 'zod';
import type { RunRecorder } from '../llm/runs.js';
import type { GenerateRequest, LlmClient } from '../llm/types.js';
import { parseLlmJson } from '../llm/validate.js';
import { CUE_LINE_RE, type ExtractedMoment } from './prompt.js';

export const FAKE_EXTRACT_MODEL = 'fake-extract';

interface Line {
  id: number;
  speaker: string;
  text: string;
}

function parseLines(prompt: string): Line[] {
  const out: Line[] = [];
  for (const raw of prompt.split('\n')) {
    const m = CUE_LINE_RE.exec(raw);
    if (!m) continue;
    out.push({ id: Number(m[1]), speaker: m[3] ?? '', text: m[4] ?? '' });
  }
  return out;
}

/** Odgovor koji bi „model” vratio za prompt (JSON tekst). */
export function fakeExtractResponse(prompt: string): string {
  const candidates = parseLines(prompt)
    .filter((l) => /^SPEAKER_\d{2}$/.test(l.speaker) && l.text.trim().split(/\s+/).length >= 4)
    // Najdulji prvi; kod iste duljine raniji (stabilno, deterministički).
    .sort((a, b) => b.text.length - a.text.length || a.id - b.id);
  const count = candidates.length >= 6 ? 2 : Math.min(1, candidates.length);
  const moments: ExtractedMoment[] = candidates
    .slice(0, count)
    .sort((a, b) => a.id - b.id)
    .map((l) => ({
      cue_from: l.id,
      cue_to: l.id,
      speaker: l.speaker,
      quote: l.text,
      claim: `Izjava iz retka c${String(l.id)}.`,
      topics: ['lažni odgovor'],
      entities: [],
    }));
  return JSON.stringify({ moments });
}

export function createFakeExtractLlm(recorder: RunRecorder): LlmClient & { calls: number } {
  const client = {
    model: FAKE_EXTRACT_MODEL,
    calls: 0,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      client.calls++;
      const text = fakeExtractResponse(req.prompt);
      const usage = { tokensIn: 0, tokensOut: 0 };
      try {
        const data = parseLlmJson(text, req.schema);
        await recorder.recordCall(req.runId, { model: FAKE_EXTRACT_MODEL, ...usage, costUsd: 0, ok: true });
        return data;
      } catch (e) {
        await recorder.recordCall(req.runId, { model: FAKE_EXTRACT_MODEL, ...usage, costUsd: 0, ok: false });
        throw e;
      }
    },
  };
  return client;
}

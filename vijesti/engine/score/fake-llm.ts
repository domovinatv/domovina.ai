// Lažni LLM za `vijesti score --fake` (odluka 313): iz prompta
// DETERMINISTIČKI sastavi ocjenu svakog trenutka i pusti je kroz istu
// validaciju i isto brojanje poziva kao pravi klijent. Brojke su bez
// vrijednosti za mjerenje; dokazuju tok.
import type { z } from 'zod';
import type { RunRecorder } from '../llm/runs.js';
import type { GenerateRequest, LlmClient } from '../llm/types.js';
import { parseLlmJson } from '../llm/validate.js';
import { MOMENT_LINE_RE, type MomentScore } from './prompt.js';

export const FAKE_SCORE_MODEL = 'fake-score';

function fold(s: string): string {
  return s.toLowerCase().replace(/đ/g, 'd').normalize('NFD').replace(/\p{M}/gu, '');
}

function contentWords(s: string): string[] {
  return fold(s)
    .split(/[^\p{L}\p{N}]+/u)
    .filter((w) => w.length >= 5);
}

const r2 = (n: number) => Math.round(n * 100) / 100;

export function fakeScoreResponse(prompt: string): string {
  const lines = prompt.split('\n');
  const priorStart = lines.findIndex((l) => l.startsWith('Ranije epizode'));
  const taskStart = lines.findIndex((l) => l.startsWith('Zadatak:'));
  const prior = new Set(contentWords(lines.slice(priorStart + 1, taskStart).join(' ')));
  const catalog = new Set(
    lines
      .filter((l) => l.startsWith('- SPEAKER_') && l.includes('u katalogu osoba'))
      .map((l) => /^- (SPEAKER_\d+):/.exec(l)?.[1] ?? ''),
  );
  const scores: MomentScore[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = MOMENT_LINE_RE.exec(lines[i] ?? '');
    if (!m) continue;
    const quote = /^Citat: „(.*)”$/.exec(lines[i + 1] ?? '')?.[1] ?? '';
    const ws = contentWords(quote);
    const seen = ws.length === 0 ? 0 : ws.filter((w) => prior.has(w)).length / ws.length;
    const speaker = m[2] ?? '';
    scores.push({
      id: Number(m[1]),
      novelty: r2(1 - seen),
      concreteness: /\d/.test(quote) ? 0.8 : 0.3,
      speaker: catalog.has(speaker) ? 0.6 : 0.2,
      public_role: null,
      reasons: {
        novelty: `Lažna ocjena: ${String(Math.round(seen * 100))} % riječi već u ranijim epizodama.`,
        concreteness: /\d/.test(quote) ? 'Lažna ocjena: citat ima brojku.' : 'Lažna ocjena: citat bez brojke.',
        speaker: catalog.has(speaker) ? 'Lažna ocjena: govornik je u katalogu.' : 'Lažna ocjena: govornik nije u katalogu.',
      },
    });
  }
  return JSON.stringify({ scores });
}

export function createFakeScoreLlm(recorder: RunRecorder): LlmClient & { calls: number } {
  const client = {
    model: FAKE_SCORE_MODEL,
    calls: 0,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      client.calls++;
      const text = fakeScoreResponse(req.prompt);
      const usage = { tokensIn: 0, tokensOut: 0 };
      try {
        const data = parseLlmJson(text, req.schema);
        await recorder.recordCall(req.runId, { model: FAKE_SCORE_MODEL, ...usage, costUsd: 0, ok: true });
        return data;
      } catch (e) {
        await recorder.recordCall(req.runId, { model: FAKE_SCORE_MODEL, ...usage, costUsd: 0, ok: false });
        throw e;
      }
    },
  };
  return client;
}

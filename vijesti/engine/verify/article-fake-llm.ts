// Lažni provjeravatelj za `verify --fake` i `npm run eval -- --fake` (odluka
// 424): iz prompta DETERMINISTIČKI uz svaku rečenicu stavi trenutak s najviše
// zajedničkih osnova (barem dvije), inače podatke o epizodi, inače „nepodržano”.
// `lyingVerifyResponse` za testove kaže „podržano t1” za sve: deterministički
// pod mora uhvatiti grešku i tada.
import { createResponderLlm } from '../llm/fake.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import { contentStems } from './article-checks.js';
import { SENTENCE_LINE_RE, VERIFY_MOMENT_LINE_RE, type SentenceVerdict } from './article-prompt.js';

export const FAKE_VERIFY_MODEL = 'fake-verify';

function parse(prompt: string) {
  const lines = prompt.split('\n');
  const moments: { n: number; stems: Set<string> }[] = [];
  const sentences: { n: number; text: string }[] = [];
  const metaEnd = lines.findIndex((l) => l.startsWith('Trenuci'));
  const meta = contentStems(lines.slice(0, metaEnd).join(' '));
  for (let i = 0; i < lines.length; i++) {
    const m = VERIFY_MOMENT_LINE_RE.exec(lines[i] ?? '');
    if (m) {
      const block: string[] = [];
      for (let j = i + 1; j < lines.length && (lines[j] ?? '') !== ''; j++) block.push(lines[j] ?? '');
      moments.push({ n: Number(m[1]), stems: contentStems(block.join(' ')) });
      continue;
    }
    const s = SENTENCE_LINE_RE.exec(lines[i] ?? '');
    if (s) sentences.push({ n: Number(s[1]), text: s[3] ?? '' });
  }
  return { moments, sentences, meta };
}

export function fakeVerifyResponse(prompt: string): string {
  const { moments, sentences, meta } = parse(prompt);
  const out: SentenceVerdict[] = sentences.map((s) => {
    const st = contentStems(s.text);
    let best: { n: number; hit: number } | null = null;
    for (const m of moments) {
      let hit = 0;
      for (const x of st) if (m.stems.has(x)) hit++;
      if (hit >= 2 && (!best || hit > best.hit)) best = { n: m.n, hit };
    }
    if (best) return { id: s.n, supported_by: [best.n], metadata: false, reason: null };
    if ([...st].some((x) => meta.has(x))) return { id: s.n, supported_by: [], metadata: true, reason: null };
    return { id: s.n, supported_by: [], metadata: false, reason: 'Lažna provjera: nijedan trenutak nema zajedničkih riječi.' };
  });
  return JSON.stringify({ sentences: out });
}

/** Provjeravatelj koji laže: svaka rečenica „podržana trenutkom t1”. */
export function lyingVerifyResponse(prompt: string): string {
  const { sentences } = parse(prompt);
  return JSON.stringify({
    sentences: sentences.map((s) => ({ id: s.n, supported_by: [1], metadata: false, reason: null })),
  });
}

export function createFakeVerifyLlm(recorder: RunRecorder): LlmClient & { calls: number } {
  return createResponderLlm(FAKE_VERIFY_MODEL, recorder, (req) => fakeVerifyResponse(req.prompt));
}

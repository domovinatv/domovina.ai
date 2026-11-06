// Lažni generator za `write --fake` i `npm run eval -- --fake` (odluka 424):
// iz prompta DETERMINISTIČKI složi vijest od riječi citata i pusti je kroz
// istu shemu. Dokazuje tok (sheme, verzije, izvori, verify), ne kvalitetu.
import { createResponderLlm } from '../llm/fake.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import { CATEGORIES, WORD_RANGE, WRITE_MOMENT_LINE_RE, type Category, type WriteBlock } from './prompt.js';
import { hrDate, wordCount } from './text.js';

export const FAKE_WRITE_MODEL = 'fake-write';

interface ParsedMoment {
  n: number;
  score: number;
  name: string;
  quote: string;
}

function field(lines: string[], prefix: string): string | null {
  const l = lines.find((x) => x.startsWith(prefix));
  const v = l?.slice(prefix.length).trim();
  return v && !v.startsWith('(') ? v : null;
}

/** Prvih `n` riječi bez interpunkcije na rubovima (u odlomku nema navodnika ni granica rečenica; `8,000` ostaje). */
function firstWords(s: string, n: number): string {
  return s
    .split(/\s+/)
    .map((t) => t.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ''))
    .filter(Boolean)
    .slice(0, n)
    .join(' ');
}

function category(text: string): Category {
  const t = text.toLowerCase();
  if (/crkv|vjer|svećen|papa|church|faith|priest|god\b/.test(t)) return 'vjera';
  if (/\bai\b|umjetn|tehnolog|technolog|internet|digital/.test(t)) return 'znanost-tehnologija';
  return CATEGORIES[CATEGORIES.length - 1] ?? 'drustvo';
}

export function fakeWriteResponse(prompt: string): string {
  const lines = prompt.split('\n');
  const channel = field(lines, 'Kanal:') ?? 'nepoznatog kanala';
  const date = hrDate(field(lines, 'Datum:'));
  const moments: ParsedMoment[] = [];
  for (let i = 0; i < lines.length; i++) {
    const m = WRITE_MOMENT_LINE_RE.exec(lines[i] ?? '');
    if (!m) continue;
    const name = /^Govornik: (.*)$/.exec(lines[i + 1] ?? '')?.[1] ?? 'ime nepoznato';
    const quote = /^Citat \(\w+\): „(.*)”$/.exec(lines[i + 2] ?? '')?.[1] ?? '';
    moments.push({ n: Number(m[1]), score: Number(m[4]), name, quote });
  }
  const ranked = [...moments].sort((a, b) => b.score - a.score || a.n - b.n);
  const top = ranked[0];
  if (!top) return JSON.stringify({ title: 'x', lead: 'x', body: [], category: 'drustvo' });

  const title = `${top.name} u podcastu ${channel}: ${firstWords(top.quote, 6)}`;
  const lead = `${top.name} govorio je u epizodi podcasta ${channel}${date ? ` objavljenoj ${date}` : ''} o temi: ${firstWords(top.quote, 14)}.`;
  const body: WriteBlock[] = [];
  let count = wordCount(lead);
  const quoted = new Set(ranked.slice(0, 2).map((m) => m.n));
  for (const m of ranked) {
    const para = `Prema riječima govornika ${m.name}, ${firstWords(m.quote, 28)}.`;
    const add = wordCount(para) + (quoted.has(m.n) ? wordCount(m.quote) : 0);
    if (count + add > WORD_RANGE.max - 10) continue;
    body.push({ type: 'p', text: para });
    if (quoted.has(m.n)) body.push({ type: 'quote', moment: m.n });
    count += add;
    if (count >= WORD_RANGE.min + 20) break;
  }
  if (body.length < 2) body.push({ type: 'quote', moment: top.n });
  return JSON.stringify({ title, lead, body, category: category(moments.map((m) => m.quote).join(' ')) });
}

export function createFakeWriteLlm(recorder: RunRecorder): LlmClient & { calls: number } {
  return createResponderLlm(FAKE_WRITE_MODEL, recorder, (req) => fakeWriteResponse(req.prompt));
}

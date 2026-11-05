// Mjerenje rizika provjere citata bez pravog modela (S2, odluka 212).
// „Pravi citat” se simulira iz titla: svaki cue i svaki par uzastopnih cueova
// istog govornika kao doslovan citat s točnim cue referencama, plus varijante
// koje model tipično radi. Brojke iz ovog modula fiksira `measure.test.ts`,
// ispisuje ih `npm run verify:measure`.
import { wordsStats, type TimedCue, type WordsStats } from '../cdn/words.js';
import { createCdnClient } from '../cdn/loader.js';
import { createFakeCdn } from '../test/fake-cdn.js';
import { normalizeWords } from './normalize.js';
import { FILLERS, verifyQuote, type QuoteClaim, type VerifyResult } from './quote.js';

export interface MeasureFixture {
  id: string;
  /** Jezik izvornog para (`diarized.<lang>.srt`); bez njega `diarized.srt`. */
  lang?: string;
}

/** Svih 5 fixturea S1, svaki na jeziku snimke (odluka 200). */
export const MEASURE_FIXTURES: readonly MeasureFixture[] = [
  { id: 'pIx_7N-6HJ4' },
  { id: 'P9sLks-f2mQ' },
  { id: 'x3w2BVZJ9vQ', lang: 'en' },
  { id: 'MGLq9v3AtvE' },
  { id: 'b-nls1ck8EE' },
];

export async function loadFixtureCues(f: MeasureFixture): Promise<TimedCue[]> {
  const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
  const ep = await cdn.loadEpisode(f.id, f.lang ? { lang: f.lang } : {});
  return ep.cues;
}

export const VARIANTS = [
  'verbatim',
  'no_fillers',
  'no_discourse',
  'repunct',
  'half_half',
  'no_diacritics',
] as const;
export type Variant = (typeof VARIANTS)[number];

export const VARIANT_LABEL: Record<Variant, string> = {
  verbatim: 'doslovan cue / par cueova',
  no_fillers: '(a1) bez glasova oklijevanja (hm, eh…)',
  no_discourse: '(a2) i bez „ovaj, znači, dakle, ono”',
  repunct: '(b) druga interpunkcija i velika slova',
  half_half: '(c) od pola cuea do pola sljedećeg',
  no_diacritics: '(d) bez dijakritike (ASCII)',
};

/** Poštapalice u širem smislu koje model izbacuje, a nisu na popisu FILLERS (odluka 204). */
const DISCOURSE = new Set(['ovaj', 'znaci', 'dakle', 'ono']);

export interface Sample {
  variant: Variant;
  claim: QuoteClaim;
}

function words(c: TimedCue): string[] {
  return c.tokens;
}

function contentCount(text: string): number {
  return normalizeWords(text).filter((w) => !FILLERS.has(w.t)).length;
}

/** Cueovi koji mogu biti citat: ima govornika i ≥ 4 riječi bez poštapalica. */
function quotable(c: TimedCue | undefined): c is TimedCue & { speaker: string } {
  return !!c && c.speaker !== null && contentCount(c.text) >= 4;
}

/** Interpunkcija i velika slova kako ih model „popravlja”: bez zareza, rečenica s velikim. */
function repunct(text: string): string {
  const s = text.replace(/[,;:]/g, '').replace(/\s+/g, ' ').trim().toLowerCase();
  return `„${s.charAt(0).toUpperCase()}${s.slice(1).replace(/[.!?…]+$/, '')}.”`;
}

function stripDiacritics(text: string): string {
  return text.normalize('NFD').replace(/\p{M}+/gu, '').replace(/đ/g, 'd').replace(/Đ/g, 'D');
}

/** Izbacuje glasove oklijevanja, a uz `discourse` i `ovaj`, `znači`, `dakle`, `ono`. */
function dropFillers(ws: string[], discourse: boolean): string[] {
  return ws.filter((w) => {
    const n = normalizeWords(w);
    const t = n.length === 1 ? n[0]?.t : undefined;
    return !(t !== undefined && (FILLERS.has(t) || (discourse && DISCOURSE.has(t))));
  });
}

/**
 * Svi uzorci za jedan titl, deterministički. Doslovni: svaki citabilan cue, i
 * svaki par uzastopnih citabilnih cueova istog govornika. Varijante (a), (b),
 * (d) idu nad istim uzorcima; (c) samo nad parovima (pola jednog + pola drugog).
 */
export function samples(cues: readonly TimedCue[]): Sample[] {
  const out: Sample[] = [];
  const add = (cueFrom: number, cueTo: number, speaker: string, ws: string[], variant: Variant) => {
    const quote = ws.join(' ');
    if (contentCount(quote) < 4) return;
    out.push({ variant, claim: { cueFrom, cueTo, speaker, quote } });
  };
  const spans: [number, number][] = [];
  cues.forEach((c, i) => {
    if (quotable(c)) spans.push([i, i]);
    const n = cues[i + 1];
    if (quotable(c) && quotable(n) && n.speaker === c.speaker) spans.push([i, i + 1]);
  });
  for (const [a, b] of spans) {
    const first = cues[a];
    if (!first?.speaker) continue;
    const ws = cues.slice(a, b + 1).flatMap(words);
    const text = ws.join(' ');
    add(a, b, first.speaker, ws, 'verbatim');
    const nf = dropFillers(ws, false);
    if (nf.length !== ws.length) add(a, b, first.speaker, nf, 'no_fillers');
    const nd = dropFillers(ws, true);
    if (nd.length !== nf.length) add(a, b, first.speaker, nd, 'no_discourse');
    add(a, b, first.speaker, [repunct(text)], 'repunct');
    const ascii = stripDiacritics(text);
    if (ascii !== text) add(a, b, first.speaker, [ascii], 'no_diacritics');
    if (b === a + 1) {
      const x = words(first);
      const y = words(cues[b] ?? first);
      add(a, b, first.speaker, [...x.slice(Math.floor(x.length / 2)), ...y.slice(0, Math.ceil(y.length / 2))], 'half_half');
    }
  }
  return out;
}

export type Outcome = 'exact' | 'fuzzy' | 'srt_only' | `failed:${string}`;

export function outcome(r: VerifyResult): Outcome {
  return r.check === 'failed' ? `failed:${r.reason}` : r.check;
}

export interface Tally {
  fixture: string;
  variant: Variant;
  n: number;
  by: Record<string, number>;
}

export function tally(fixture: string, cues: readonly TimedCue[]): Tally[] {
  const rows = new Map<Variant, Tally>();
  for (const s of samples(cues)) {
    const t = rows.get(s.variant) ?? { fixture, variant: s.variant, n: 0, by: {} };
    const o = outcome(verifyQuote(cues, s.claim));
    t.n++;
    t.by[o] = (t.by[o] ?? 0) + 1;
    rows.set(s.variant, t);
  }
  return VARIANTS.flatMap((v) => rows.get(v) ?? []);
}

export async function measureAll(): Promise<Tally[]> {
  const out: Tally[] = [];
  for (const f of MEASURE_FIXTURES) out.push(...tally(f.id, await loadFixtureCues(f)));
  return out;
}

/** Tablica u markdownu: po fixtureu i varijanti, udio prolaza i razlozi pada. */
export function formatTable(rows: readonly Tally[]): string {
  const pct = (k: number, n: number) => (n === 0 ? '–' : `${String(Math.round((1000 * k) / n) / 10)} %`);
  const lines = [
    '| fixture | varijanta | n | exact | fuzzy | srt_only | prolazi | failed (razlozi) |',
    '|---|---|---:|---:|---:|---:|---:|---|',
  ];
  for (const r of rows) {
    const g = (k: string) => r.by[k] ?? 0;
    const pass = g('exact') + g('fuzzy') + g('srt_only');
    const fails = Object.entries(r.by)
      .filter(([k]) => k.startsWith('failed:'))
      .sort((a, b) => b[1] - a[1])
      .map(([k, v]) => `${k.slice(7)} ${String(v)}`)
      .join(', ');
    lines.push(
      `| ${r.fixture} | ${VARIANT_LABEL[r.variant]} | ${String(r.n)} | ${String(g('exact'))} | ${String(g('fuzzy'))} | ${String(g('srt_only'))} | ${pct(pass, r.n)} | ${fails || '–'} |`,
    );
  }
  return lines.join('\n');
}

export interface WordsAlignment extends WordsStats {
  fixture: string;
  /** Riječi u cueovima s vremenima. */
  words: number;
  /** Riječi s krajem ≤ početka (citat koji počinje i završava na njima → srt_only). */
  zeroLength: number;
  /** Riječi izvan granica svog cuea (±1 ms) ili s početkom prije prethodne. */
  outOfOrder: number;
  /** Cueovi s `a = 1` (sve riječi usidrene). */
  fullyAnchored: number;
}

/**
 * Rizik „SRT tekst ↔ words vremena”. words.json nosi samo parove (početak,
 * kraj), ne tekst (docs/research/2026-11-05-oblik-cdn-datoteka.md), pa se
 * riječ ne može usporediti s riječi titla; mjeri se koliko cueova nema
 * vremena (citat preko njih je `srt_only`) i jesu li vremena uvjerljiva.
 */
export function wordsAlignment(fixture: string, cues: readonly TimedCue[]): WordsAlignment {
  let words = 0;
  let zeroLength = 0;
  let outOfOrder = 0;
  let fullyAnchored = 0;
  for (const c of cues) {
    if (c.anchored === 1) fullyAnchored++;
    let prev = -Infinity;
    for (const w of c.words ?? []) {
      words++;
      if (w.endMs <= w.startMs) zeroLength++;
      if (w.startMs < c.startMs - 1 || w.endMs > c.endMs + 1 || w.startMs < prev) outOfOrder++;
      prev = w.startMs;
    }
  }
  return { fixture, ...wordsStats(cues), words, zeroLength, outOfOrder, fullyAnchored };
}

export function formatAlignment(rows: readonly WordsAlignment[]): string {
  const lines = [
    '| fixture | cueova | s vremenima | count_mismatch | bez words | a = 1 | riječi | riječi od 0 ms | izvan cuea / unatrag |',
    '|---|---:|---:|---:|---:|---:|---:|---:|---:|',
  ];
  for (const r of rows) {
    const cells = [r.cues, r.ok, r.countMismatch, r.missing, r.fullyAnchored, r.words, r.zeroLength, r.outOfOrder];
    lines.push(`| ${r.fixture} | ${cells.map(String).join(' | ')} |`);
  }
  return lines.join('\n');
}

// Provjera citata (odluke 202–206). Citat koji je model vratio mora postojati
// kao NEPREKINUT niz riječi u titlu, unutar prozora oko cueova koje je model
// naveo, i izgovoriti ga mora govornik kojeg je model naveo. Vrijeme citata
// dolazi iz titla (words.json ili granice cuea), nikad iz modela.
import type { TimedCue } from '../cdn/words.js';
import { normalizeTokens } from './normalize.js';

export type QuoteCheck = 'exact' | 'fuzzy' | 'srt_only' | 'failed';
export type QuoteMatch = 'exact' | 'fuzzy';
export type RejectReason =
  | 'bad_cue_ref'
  | 'span_too_long'
  | 'ellipsis'
  | 'too_short'
  | 'not_found'
  | 'outside_window'
  | 'speaker_mismatch';

export interface QuoteClaim {
  /** Indeks cuea u `cues` (redni broj u promptu, `c<N>`). */
  cueFrom: number;
  cueTo: number;
  speaker: string;
  quote: string;
}

export interface VerifyOptions {
  /** Prozor oko [početak cue_from, kraj cue_to]. Zadano 5000 ms (odluka 203). */
  windowMs?: number;
  /** Najmanje tokena citata bez poštapalica. Zadano 4 (odluka 205). */
  minTokens?: number;
  /** Najdulji raspon cue_from..cue_to u ms. Zadano 120 000 (odluka 205). */
  maxSpanMs?: number;
}

export const DEFAULT_WINDOW_MS = 5000;
export const DEFAULT_MIN_TOKENS = 4;
export const DEFAULT_MAX_SPAN_MS = 120_000;

/**
 * ZATVOREN popis poštapalica koje smiju biti u titlu, a izostati iz citata
 * (odluka 204). Samo glasovi oklijevanja: nijedna riječ koja išta znači.
 * Namjerno NISU tu: `ovaj`, `ono` (pokazne zamjenice), `dakle`, `znaci`,
 * `mislim`, `kao`, `mhm`/`aha` (= da), `em` (em… em), `er` (= jer), `e`, `a`.
 */
export const FILLERS: ReadonlySet<string> = new Set([
  'hm', 'hmm', 'hmmm', 'mm', 'mmm', 'eh', 'ehm', 'ee', 'eee', 'eem', 'aa', 'aaa', 'ah',
  'uh', 'uhm', 'um', 'umm', 'erm',
]);

/** Najkraća riječ (obje strane) kojoj se dopušta razlika jednog znaka. */
export const FUZZY_MIN_TOKEN_LEN = 6;
/** Razlika smije biti samo u zadnja 3 znaka dulje riječi (nastavak). */
export const FUZZY_TAIL = 3;
/** Najviše jedna izmijenjena riječ na svakih 10 riječi citata (floor). */
export const FUZZY_TOKENS_PER_EDIT = 10;

export interface QuoteSpan {
  cueFrom: number;
  cueTo: number;
  startMs: number;
  endMs: number;
}

export type VerifyResult =
  | {
      check: Exclude<QuoteCheck, 'failed'>;
      match: QuoteMatch;
      span: QuoteSpan;
      /** Izbrisane poštapalice iz titla i riječi s razlikom jednog znaka. */
      fillersSkipped: number;
      charEdits: number;
    }
  | {
      check: 'failed';
      reason: RejectReason;
      /** Granice cueova koje je model naveo; `null` kad reference ne valjaju. */
      range: { startMs: number; endMs: number } | null;
      detail?: string;
    };

interface Tok {
  t: string;
  cue: number;
  /** Indeks riječi u `cue.tokens` (za vrijeme iz words.json). */
  word: number;
}

function tokensOf(cues: readonly TimedCue[], from: number, to: number): Tok[] {
  const out: Tok[] = [];
  for (let c = from; c <= to; c++) {
    const cue = cues[c];
    if (!cue) continue;
    cue.tokens.forEach((w, wi) => {
      for (const t of normalizeTokens(w)) out.push({ t, cue: c, word: wi });
    });
  }
  return out;
}

/**
 * Razlika točno jednog znaka (zamjena, umetanje ili brisanje) u nastavku
 * riječi duljine ≥ 6, bez znamenaka. Početak riječi se ne smije mijenjati
 * (`legalno` ≠ `ilegalno`), ni sredina (`predati` ≠ `prodati`).
 */
export function oneCharTailEdit(a: string, b: string): boolean {
  if (a === b) return false;
  if (a.length < FUZZY_MIN_TOKEN_LEN || b.length < FUZZY_MIN_TOKEN_LEN) return false;
  if (/\d/.test(a) || /\d/.test(b)) return false;
  const [long, short] = a.length >= b.length ? [a, b] : [b, a];
  if (long.length - short.length > 1) return false;
  let i = 0;
  while (i < short.length && long[i] === short[i]) i++;
  if (i < long.length - FUZZY_TAIL) return false;
  if (long.length === short.length) return long.slice(i + 1) === short.slice(i + 1);
  return long.slice(i + 1) === short.slice(i);
}

interface Found {
  from: number;
  to: number;
  fillers: number;
  edits: number;
}

/**
 * Poravnanje citata s titlom od pozicije `start`. Dopušteno: brisanje
 * poštapalica iz titla UNUTAR raspona, i do `budget` riječi s razlikom jednog
 * znaka. Ništa drugo (nema umetanja, zamjene riječi ni brisanja drugih riječi).
 */
function alignAt(tr: Tok[], q: string[], start: number, budget: number): Found | null {
  let k = start;
  let fillers = 0;
  let edits = 0;
  for (let j = 0; j < q.length; j++) {
    const want = q[j] ?? '';
    for (;;) {
      const got = tr[k]?.t;
      if (got === undefined) return null;
      if (got === want) break;
      // Poštapalica se preskače samo usred citata, ne prije prve riječi.
      if (j > 0 && FILLERS.has(got)) {
        fillers++;
        k++;
        continue;
      }
      if (edits < budget && oneCharTailEdit(got, want)) {
        edits++;
        break;
      }
      return null;
    }
    k++;
  }
  return { from: start, to: k - 1, fillers, edits };
}

/** Sva pojavljivanja, redom: prvo točna (bez ikakve izmjene), zatim ostala. */
function occurrences(tr: Tok[], q: string[], budget: number): Found[] {
  const exact: Found[] = [];
  const fuzzy: Found[] = [];
  for (let s = 0; s < tr.length; s++) {
    const f = alignAt(tr, q, s, budget);
    if (!f) continue;
    if (f.fillers === 0 && f.edits === 0) exact.push(f);
    else fuzzy.push(f);
  }
  return [...exact, ...fuzzy];
}

function countEllipses(text: string): number {
  return (text.match(/…|\.{3,}/g) ?? []).length;
}

function cueBounds(cues: readonly TimedCue[], from: number, to: number) {
  const startMs = cues[from]?.startMs ?? 0;
  const endMs = Math.max(cues[to]?.endMs ?? 0, startMs + 1);
  return { startMs, endMs };
}

export function verifyQuote(
  cues: readonly TimedCue[],
  claim: QuoteClaim,
  opts: VerifyOptions = {},
): VerifyResult {
  const windowMs = opts.windowMs ?? DEFAULT_WINDOW_MS;
  const minTokens = opts.minTokens ?? DEFAULT_MIN_TOKENS;
  const maxSpanMs = opts.maxSpanMs ?? DEFAULT_MAX_SPAN_MS;
  const { cueFrom, cueTo } = claim;
  const valid =
    Number.isInteger(cueFrom) &&
    Number.isInteger(cueTo) &&
    cueFrom >= 0 &&
    cueTo >= cueFrom &&
    cueTo < cues.length;
  if (!valid) {
    return {
      check: 'failed',
      reason: 'bad_cue_ref',
      range: null,
      detail: `c${String(cueFrom)}..c${String(cueTo)} (cueova: ${String(cues.length)})`,
    };
  }
  const range = cueBounds(cues, cueFrom, cueTo);
  const fail = (reason: RejectReason, detail?: string): VerifyResult => ({
    check: 'failed',
    reason,
    range,
    ...(detail !== undefined && { detail }),
  });
  if (range.endMs - range.startMs > maxSpanMs) return fail('span_too_long');
  const q = normalizeTokens(claim.quote);
  if (q.filter((t) => !FILLERS.has(t)).length < minTokens) return fail('too_short');
  const budget = Math.floor(q.length / FUZZY_TOKENS_PER_EDIT);

  // Prozor: svi cueovi koji se preklapaju s [početak − W, kraj + W].
  const lo = range.startMs - windowMs;
  const hi = range.endMs + windowMs;
  let wFrom = cueFrom;
  while (wFrom > 0 && (cues[wFrom - 1]?.endMs ?? -Infinity) >= lo) wFrom--;
  let wTo = cueTo;
  while (wTo < cues.length - 1 && (cues[wTo + 1]?.startMs ?? Infinity) <= hi) wTo++;

  const tr = tokensOf(cues, wFrom, wTo);
  const found = occurrences(tr, q, budget);
  if (found.length === 0) {
    // Globalna pretraga samo razlikuje razlog; ishod je svejedno `failed`.
    const all = tokensOf(cues, 0, cues.length - 1);
    return fail(occurrences(all, q, budget).length > 0 ? 'outside_window' : 'not_found');
  }
  for (const f of found) {
    const first = tr[f.from];
    const last = tr[f.to];
    if (!first || !last) continue;
    let sameSpeaker = true;
    for (let c = first.cue; c <= last.cue; c++) {
      if (cues[c]?.speaker !== claim.speaker) sameSpeaker = false;
    }
    if (!sameSpeaker) continue;
    // Tri točke u titlu znače prekinut govor. U citatu smiju biti samo
    // koliko ih ima u titlu tog raspona; više znači izostavljanje (odluka 205).
    let spanEllipses = 0;
    for (let c = first.cue; c <= last.cue; c++) spanEllipses += countEllipses(cues[c]?.text ?? '');
    if (countEllipses(claim.quote) > spanEllipses) return fail('ellipsis');
    const match: QuoteMatch = f.fillers === 0 && f.edits === 0 ? 'exact' : 'fuzzy';
    const firstCue = cues[first.cue];
    const lastCue = cues[last.cue];
    const ws = firstCue?.words?.[first.word];
    const we = lastCue?.words?.[last.word];
    let allTimed = true;
    for (let c = first.cue; c <= last.cue; c++) {
      if (!cues[c]?.words) allTimed = false;
    }
    const timed = allTimed && ws && we && we.endMs > ws.startMs;
    const span: QuoteSpan = timed
      ? { cueFrom: first.cue, cueTo: last.cue, startMs: ws.startMs, endMs: we.endMs }
      : { cueFrom: first.cue, cueTo: last.cue, ...cueBounds(cues, first.cue, last.cue) };
    return {
      check: timed ? match : 'srt_only',
      match,
      span,
      fillersSkipped: f.fillers,
      charEdits: f.edits,
    };
  }
  return fail('speaker_mismatch');
}

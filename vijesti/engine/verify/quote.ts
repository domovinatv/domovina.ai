// Provjera citata (odluke 202–206, 210–214). Citat koji je model vratio mora
// postojati kao NEPREKINUT niz riječi u titlu, slovo po slovo (bez obzira na
// velika slova i interpunkciju), unutar prozora oko cueova koje je model
// naveo, izgovoriti ga mora govornik kojeg je model naveo, i ne smije počinjati
// odmah iza niječnice tog govornika. Jedina dopuštena razlika su poštapalice
// iz titla. Vrijeme citata dolazi iz titla (words.json ili granice cuea),
// nikad iz modela.
import type { TimedCue } from '../cdn/words.js';
import { normalizeWords, type NormToken } from './normalize.js';

export type QuoteCheck = 'exact' | 'fuzzy' | 'srt_only' | 'failed';
export type QuoteMatch = 'exact' | 'fuzzy';
export type RejectReason =
  | 'bad_cue_ref'
  | 'span_too_long'
  | 'ellipsis'
  | 'too_short'
  | 'not_found'
  | 'outside_window'
  | 'speaker_mismatch'
  | 'word_form'
  | 'negation_cut';

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

/**
 * Razlika jednog znaka u nastavku riječi više NIJE dopuštena (odluka 210):
 * u hrvatskom nastavak nosi lice, vrijeme i broj (`mislim`/`mislis`,
 * `trebalo`/`trebamo`), a na fixtureima i druge riječi (`svijest`/`svijet`,
 * `postaje`/`postoje`, `influence`/`influencer`, `thousand`/`thousands`).
 * Pravilo ostaje samo za dijagnozu: citat koji se od titla razlikuje u
 * nastavku ili dijakritici do jedne riječi na 10 (najmanje jedne) je
 * `failed: word_form`, ne `not_found`, da S3 vidi koliko ih model radi.
 */
export const FUZZY_MIN_TOKEN_LEN = 6;
/** Razlika smije biti samo u zadnja 3 znaka dulje riječi (nastavak). */
export const FUZZY_TAIL = 3;
/** Dijagnoza `word_form`: do jedne izmijenjene riječi na 10 (najmanje 1). */
export const FUZZY_TOKENS_PER_EDIT = 10;

/**
 * Niječnice koje niječu riječ iza sebe (odluka 211). Citat koji počinje odmah
 * iza jedne od njih (isti govornik, bez interpunkcije između) obrće značenje:
 * „nije istina da …” → „istina da …”. Uspoređuje se oblik bez dijakritike.
 */
export const NEGATIONS: ReadonlySet<string> = new Set([
  // hr
  'ne', 'ni', 'niti', 'nit', 'nisam', 'nisi', 'nije', 'nismo', 'niste', 'nisu', 'necu', 'neces',
  'nece', 'necemo', 'necete', 'nemoj', 'nemojte', 'nikad', 'nikada', 'nimalo',
  // en
  'not', 'no', 'never', 'nor', 'neither', 'dont', 'doesnt', 'didnt', 'isnt', 'arent', 'wasnt',
  'werent', 'cant', 'cannot', 'couldnt', 'wouldnt', 'shouldnt', 'wont', 'havent', 'hasnt',
  'hadnt', 'aint',
]);

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
    }
  | {
      check: 'failed';
      reason: RejectReason;
      /** Granice cueova koje je model naveo; `null` kad reference ne valjaju. */
      range: { startMs: number; endMs: number } | null;
      detail?: string;
    };

interface Tok extends NormToken {
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
      for (const n of normalizeWords(w)) out.push({ ...n, cue: c, word: wi });
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
  /** Izmijenjene riječi, `titl→citat`. */
  diffs: string[];
}

/**
 * Poravnanje citata s titlom od pozicije `start`. Dopušteno: brisanje
 * poštapalica iz titla UNUTAR raspona. Do `budget` riječi koje se razlikuju
 * samo u dijakritici ili jednom znaku nastavka broji se u `edits` (samo za
 * dijagnozu `word_form`; takvo poravnanje ne prolazi). Ništa drugo (nema
 * umetanja, zamjene riječi ni brisanja drugih riječi).
 */
function alignAt(tr: Tok[], q: NormToken[], start: number, budget: number): Found | null {
  let k = start;
  let fillers = 0;
  let edits = 0;
  const diffs: string[] = [];
  for (let j = 0; j < q.length; j++) {
    const want = q[j];
    if (!want) return null;
    for (;;) {
      const got = tr[k];
      if (got === undefined) return null;
      if (got.t === want.t && got.d === want.d) break;
      // Poštapalica se preskače samo usred citata, ne prije prve riječi.
      if (j > 0 && FILLERS.has(got.t)) {
        fillers++;
        k++;
        continue;
      }
      if (edits < budget && (got.t === want.t || oneCharTailEdit(got.t, want.t))) {
        edits++;
        diffs.push(`${got.d}→${want.d}`);
        break;
      }
      return null;
    }
    k++;
  }
  return { from: start, to: k - 1, fillers, edits, diffs };
}

/** Sva pojavljivanja, redom: točna, pa s poštapalicama, pa s izmjenom riječi. */
function occurrences(tr: Tok[], q: NormToken[], budget: number): Found[] {
  const exact: Found[] = [];
  const fuzzy: Found[] = [];
  const edited: Found[] = [];
  for (let s = 0; s < tr.length; s++) {
    const f = alignAt(tr, q, s, budget);
    if (!f) continue;
    if (f.edits > 0) edited.push(f);
    else if (f.fillers > 0) fuzzy.push(f);
    else exact.push(f);
  }
  return [...exact, ...fuzzy, ...edited];
}

/** Riječ titla završava interpunkcijom (zarez, točka, crtica…) → odvojena je. */
const TRAILING_PUNCT = /[^\p{L}\p{M}\p{N}'’]$/u;

/** Između dva susjedna tokena titla stoji interpunkcija (kraj riječi `a`). */
function separated(cues: readonly TimedCue[], a: Tok, b: Tok): boolean {
  if (a.cue === b.cue && a.word === b.word) return false;
  return TRAILING_PUNCT.test(cues[a.cue]?.tokens[a.word] ?? '');
}

/**
 * Niječnica istog govornika neposredno uz citat (odluka 211), preko
 * poštapalica i granice cuea, bez interpunkcije između. Vraća je ili `null`.
 * `side` su tokeni titla od citata prema van: ispred početka (najbliži prvi)
 * ili iza kraja. Ispred: „nije | istina da …”; iza: „… pa možda i | ne”.
 */
function negationNext(cues: readonly TimedCue[], edge: Tok, side: Tok[], dir: 'before' | 'after'): string | null {
  const speaker = cues[edge.cue]?.speaker;
  let inner = edge;
  for (const p of side) {
    if (cues[p.cue]?.speaker !== speaker) return null;
    if (dir === 'before' ? separated(cues, p, inner) : separated(cues, inner, p)) return null;
    if (NEGATIONS.has(p.t)) return p.d;
    if (!FILLERS.has(p.t)) return null;
    inner = p;
  }
  return null;
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
  const q = normalizeWords(claim.quote);
  if (q.filter((w) => !FILLERS.has(w.t)).length < minTokens) return fail('too_short');
  const budget = Math.max(1, Math.floor(q.length / FUZZY_TOKENS_PER_EDIT));

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
    if (f.edits > 0) return fail('word_form', f.diffs.join(', '));
    // Tri točke u titlu znače prekinut govor. U citatu smiju biti samo
    // koliko ih ima u titlu tog raspona; više znači izostavljanje (odluka 205).
    let spanEllipses = 0;
    for (let c = first.cue; c <= last.cue; c++) spanEllipses += countEllipses(cues[c]?.text ?? '');
    if (countEllipses(claim.quote) > spanEllipses) return fail('ellipsis');
    // Tokeni uz citat: iz prozora, a na rubu prozora i iz susjednog cuea.
    const before = [...(wFrom > 0 ? tokensOf(cues, wFrom - 1, wFrom - 1) : []), ...tr.slice(0, f.from)];
    const after = [...tr.slice(f.to + 1), ...(wTo + 1 < cues.length ? tokensOf(cues, wTo + 1, wTo + 1) : [])];
    const neg =
      negationNext(cues, first, before.slice(-8).reverse(), 'before') ??
      negationNext(cues, last, after.slice(0, 8), 'after');
    if (neg !== null) return fail('negation_cut', neg);
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
    // Nađeni citat smije izaći iz navedenih cueova samo unutar prozora, ali
    // dugi susjedni cueovi bi ga razvukli preko granice raspona (odluka 214).
    if (span.endMs - span.startMs > maxSpanMs) return fail('span_too_long', 'nađeni citat');
    return {
      check: timed ? match : 'srt_only',
      match,
      span,
      fillersSkipped: f.fillers,
    };
  }
  return fail('speaker_mismatch');
}

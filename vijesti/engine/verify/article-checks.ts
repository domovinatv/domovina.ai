// Deterministički pod provjere članka (odluke 426–431): vrijedi i kad LLM
// provjeravatelj laže „podržano”. Čiste funkcije nad tekstom, bez baze i modela.
//
// (a) tekst u navodnicima mora biti DOSLOVNO `moments.quote` trenutka iz izvora
//     (normalizacija samo razmaka i oblika navodnika/apostrofa, `normalizeQuote`);
//     ovo NIJE `normalize.ts`, koji uspoređuje citat s titlom riječ po riječ;
// (b) vlastita imena (niz od barem dvije riječi velikim početnim slovom) moraju
//     postojati u imenima govornika, entitetima i citatima podupirućih trenutaka
//     ili u metapodacima epizode;
// (c) svaki broj (znamenke i brojevi riječima) mora postojati ondje;
// (d) premalo leksičkog preklapanja s podupirućim trenucima = nepodržano.
import { NAME_TITLES } from '../score/persons.js';
import type { EpisodeMeta, SourceMoment } from '../write/content.js';
import { fold, hrDate } from '../write/text.js';

/** Verzija determinističkih pravila (ide u `verify-article/1+d1`). */
export const DETERMINISTIC_VERSION = 'd1';

/**
 * Najmanji udio sadržajnih osnova rečenice koje postoje u podupirućim
 * trenucima i metapodacima (odluka 430). Privremeno: druga faza S4
 * (adversarijalni testovi) i prvi pravi prolaz ga mjere.
 */
export const MIN_LEXICAL_OVERLAP = 0.4;
/** Rečenica s manje sadržajnih osnova ne dobiva sud o preklapanju (premalo za omjer). */
export const MIN_OVERLAP_STEMS = 3;
/** Osnova = prvih N slova riječi bez dijakritike (gruba zamjena za stemer, hrvatski padeži). */
export const STEM_LEN = 5;

export type ProblemCode =
  | 'quote_not_verbatim'
  | 'quote_ref_missing'
  | 'quote_ref_not_source'
  | 'llm_unsupported'
  | 'verifier_omitted'
  | 'unknown_moment_ref'
  | 'unknown_name'
  | 'unknown_number'
  | 'low_overlap';

export interface Problem {
  code: ProblemCode;
  detail: string;
}

// ---------------------------------------------------------------- (a) citati

/** Samo razmaci, NFC i oblik navodnika/apostrofa. Interpunkcija i velika slova ostaju. */
export function normalizeQuote(s: string): string {
  return s
    .normalize('NFC')
    .replace(/[’‘ʼ`´]/g, "'")
    .replace(/[„“”«»"]/g, '"')
    .replace(/\s+/g, ' ')
    .trim();
}

const INLINE_QUOTE_RE = /[„“"«]([^„“”"«»]+)[”“"»]/g;

/** Tekstovi u navodnicima („…”, “…”, "…", «…»), bez samih navodnika. */
export function inlineQuotes(text: string): string[] {
  return [...text.matchAll(INLINE_QUOTE_RE)].map((m) => m[1] ?? '');
}

/** Navodnici u rečenici koji nisu doslovno citat nekog trenutka izvora. */
export function nonVerbatimQuotes(text: string, sources: readonly SourceMoment[]): string[] {
  const known = new Set(sources.map((m) => normalizeQuote(m.quote)));
  return inlineQuotes(text).filter((q) => !known.has(normalizeQuote(q)));
}

// ---------------------------------------------------------------- korpus

/** Tekst iz kojeg rečenica smije uzimati imena, brojeve i riječi. */
export interface Corpus {
  /** Citati, imena govornika, entiteti (b, c). */
  literal: string;
  /** Uz `literal` i tvrdnje trenutaka (hrvatski sažetak, važno za engleske epizode) (d). */
  lexical: string;
}

export function metaText(e: EpisodeMeta): string {
  return [
    e.title ?? '',
    e.channelName ?? '',
    e.channel ?? '',
    e.date ?? '',
    hrDate(e.date) ?? '',
    ...e.speakers.flatMap((s) => [s.name ?? '', s.role ?? '']),
  ].join('\n');
}

export function buildCorpus(support: readonly SourceMoment[], episode: EpisodeMeta): Corpus {
  const literal = [
    metaText(episode),
    ...support.flatMap((m) => [m.quote, m.speakerName ?? '', ...m.entities]),
  ].join('\n');
  return { literal, lexical: [literal, ...support.map((m) => m.claim ?? '')].join('\n') };
}

// ---------------------------------------------------------------- (c) brojevi

const THOUSANDS_SEP = /(\d)[.,](?=\d{3}(?!\d))/g;

function canonical(digits: string): string | null {
  const n = Number(digits.replace(THOUSANDS_SEP, '$1').replace(',', '.'));
  return Number.isFinite(n) ? String(n) : null;
}

const UNITS: Record<string, number> = {
  dva: 2, dvije: 2, dvoje: 2, dvaju: 2, tri: 3, troje: 3, triju: 3, cetiri: 4, cetvero: 4, pet: 5, petero: 5,
  sest: 6, sedam: 7, osam: 8, devet: 9, deset: 10, jedanaest: 11, dvanaest: 12, trinaest: 13, cetrnaest: 14,
  petnaest: 15, sesnaest: 16, sedamnaest: 17, osamnaest: 18, devetnaest: 19,
  two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10, eleven: 11, twelve: 12,
  thirteen: 13, fourteen: 14, fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
};
const TENS: Record<string, number> = {
  dvadeset: 20, trideset: 30, cetrdeset: 40, pedeset: 50, sezdeset: 60, sedamdeset: 70, osamdeset: 80,
  devedeset: 90, twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60, seventy: 70, eighty: 80, ninety: 90,
};
const MULTIPLIERS: Record<string, number> = {
  sto: 100, stotinu: 100, stotine: 100, hundred: 100, tisucu: 1000, tisuca: 1000, tisuce: 1000, thousand: 1000,
  milijun: 1e6, milijuna: 1e6, million: 1e6, milijarda: 1e9, milijarde: 1e9, milijardi: 1e9, billion: 1e9,
};

/**
 * Brojevi u tekstu, kanonski (`1.500` = `1500`, `3,5` = `3.5`). Brojevi
 * riječima od „dva” naviše (hr i en, „dvadeset pet”, „tri milijuna”); „jedan”
 * namjerno ne (`jedan od`). `parts` daje i sastavnice (`tri milijuna` → 3 i
 * 3000000), da korpus bude širok, a rečenica se provjerava po cijelom broju.
 */
export function numbersIn(text: string, opts: { parts?: boolean } = {}): string[] {
  const out = new Set<string>();
  // Razmak kao razdjelnik tisućica (pravopis: „8 000”) se briše, samo ispred točno tri znamenke.
  const joined = text.replace(/(\d)[ \u00a0\u202f](?=\d{3}(?!\d))/g, '$1');
  for (const m of joined.matchAll(/\d+(?:[.,]\d+)*/g)) {
    const c = canonical(m[0]);
    if (c !== null) out.add(c);
  }
  const toks = fold(text).split(/[^a-z]+/).filter(Boolean);
  for (let i = 0; i < toks.length; i++) {
    const t = toks[i] ?? '';
    let value: number | null = null;
    const parts: number[] = [];
    if (TENS[t] !== undefined) {
      value = TENS[t];
      const u = UNITS[toks[i + 1] ?? ''];
      if (u !== undefined && u < 10) {
        parts.push(value, u);
        value += u;
        i++;
      }
    } else if (UNITS[t] !== undefined) value = UNITS[t];
    else if (MULTIPLIERS[t] !== undefined) value = MULTIPLIERS[t];
    if (value === null) continue;
    const mul = MULTIPLIERS[toks[i + 1] ?? ''];
    if (mul !== undefined && value < mul) {
      parts.push(value, mul);
      value *= mul;
      i++;
    }
    out.add(String(value));
    if (opts.parts) for (const p of parts) out.add(String(p));
  }
  return [...out];
}

// ---------------------------------------------------------------- (b) imena

/** Riječi koje nisu ime čak i velikim slovom (titule iz score/persons.ts). */
const TITLE_TOKENS = NAME_TITLES;

/**
 * Dvije riječi su isto ime u drugom padežu kad dijele početak duljine barem
 * min(duljina) − 1 i barem 3 slova (`Horvat`/`Horvatu`, `Ivan`/`Ivanu`,
 * `Marko`/`Marka`), ili su jednake. `Marko`/`Marija` i `Kong`/`Kovač` nisu.
 */
export function sameNameToken(a: string, b: string): boolean {
  if (a === b) return true;
  const min = Math.min(a.length, b.length);
  if (min < 3) return false;
  let p = 0;
  while (p < min && a[p] === b[p]) p++;
  return p >= Math.max(3, min - 1);
}

/** Nizovi riječi velikim početnim slovom; zarez, točka-zarez, dvotočka i zagrade prekidaju niz. */
export function nameRuns(sentence: string): { tokens: string[]; initial: boolean }[] {
  const raw = sentence.split(/\s+/).filter(Boolean);
  const runs: { tokens: string[]; initial: boolean }[] = [];
  let cur: string[] = [];
  let curInitial = false;
  let seenWord = false;
  const flush = () => {
    if (cur.length > 0) runs.push({ tokens: cur, initial: curInitial });
    cur = [];
  };
  for (const r of raw) {
    const word = r.replace(/^[^\p{L}\p{N}]+/u, '').replace(/[^\p{L}\p{N}]+$/u, '');
    const breaks = /[,;:()\]”"»!?]$|[^.]\.$/u.test(r) && !TITLE_TOKENS.has(fold(word));
    if (!word) continue;
    if (TITLE_TOKENS.has(fold(word))) {
      seenWord = true;
      continue;
    }
    if (/^\p{Lu}/u.test(word)) {
      if (cur.length === 0) curInitial = !seenWord;
      cur.push(word);
    } else flush();
    seenWord = true;
    if (breaks) flush();
  }
  flush();
  return runs;
}

function nameTokenSet(text: string): string[] {
  return [...new Set(fold(text).split(/[^\p{L}\p{N}]+/u).filter((t) => t.length > 0))];
}

/**
 * Imena iz rečenice kojih nema u korpusu. Gleda se niz od barem dvije
 * riječi velikim slovom; na početku rečenice prva riječ može biti obična
 * riječ („Prema Ivanu Horvatu”), pa se tada provjerava i niz bez nje.
 * Pojedinačna riječ velikim slovom usred rečenice se NE provjerava (mjesto,
 * ustanova, „Bog”): odluka 428.
 */
export function unknownNames(sentence: string, corpus: string): string[] {
  const known = nameTokenSet(corpus);
  const ok = (toks: string[]) => toks.length > 0 && toks.every((t) => known.some((k) => sameNameToken(fold(t), k)));
  const bad: string[] = [];
  for (const run of nameRuns(sentence)) {
    if (run.tokens.length < 2 || ok(run.tokens)) continue;
    if (!run.initial) {
      bad.push(run.tokens.join(' '));
      continue;
    }
    // Na početku rečenice prva riječ može biti obična („Kaže Horvat”, „Prema Ivanu Horvatu”).
    const rest = run.tokens.slice(1);
    if (!ok(rest)) bad.push(rest.join(' '));
  }
  return bad;
}

// ---------------------------------------------------------------- (d) preklapanje

/**
 * Riječi izvještavanja i strukture članka koje izvor ne izgovara („kaže”,
 * „prema riječima”, „u podcastu”), kao osnove od STEM_LEN slova. Bez njih
 * bi svaka ispravno pripisana rečenica gubila preklapanje.
 */
const STOP_STEMS = new Set(
  [
    'prema', 'rijec', 'govor', 'kaze', 'rekao', 'rekla', 'reklo', 'smatr', 'istic', 'istak', 'nagla', 'navod',
    'naveo', 'navel', 'tvrdi', 'dodao', 'dodal', 'dodaj', 'objas', 'objav', 'podca', 'epizo', 'snimc', 'snimk',
    'takod', 'kako', 'koji', 'koja', 'koje', 'kojeg', 'kojem', 'kojoj', 'kojim', 'biti', 'bilo', 'bila', 'bili',
    'sada', 'samo', 'nije', 'nisu', 'moze', 'mogu', 'treba', 'izjav', 'temi', 'temu', 'tema', 'teme', 'gosti',
    'gost', 'izmed', 'ovaj', 'ova', 'ovo', 'ovom', 'tome', 'toga', 'svoj', 'svoje', 'jedan', 'jedna', 'jedno',
    'vise', 'manje', 'vrlo', 'gdje', 'kada', 'zato', 'nakon', 'prije', 'tijek', 'izmedu', 'sebe',
  ].map((w) => w.slice(0, STEM_LEN)),
);

/** Sadržajne osnove: riječi od 4+ slova (i brojevi) bez dijakritike, prvih STEM_LEN slova, bez STOP_STEMS. */
export function contentStems(text: string): Set<string> {
  const out = new Set<string>();
  for (const w of fold(text).split(/[^\p{L}\p{N}]+/u)) {
    if (!w) continue;
    const isNum = /^\d+$/.test(w);
    if (!isNum && w.length < 4) continue;
    const stem = w.slice(0, STEM_LEN);
    if (!isNum && STOP_STEMS.has(stem)) continue;
    out.add(stem);
  }
  return out;
}

/** Udio osnova rečenice koje postoje u korpusu; null kad rečenica ima premalo osnova. */
export function lexicalOverlap(sentence: string, corpus: string): number | null {
  const s = contentStems(sentence);
  if (s.size < MIN_OVERLAP_STEMS) return null;
  const c = contentStems(corpus);
  let hit = 0;
  for (const x of s) if (c.has(x)) hit++;
  return Math.round((hit / s.size) * 1000) / 1000;
}

// ---------------------------------------------------------------- sve zajedno

export interface SentenceCheck {
  problems: Problem[];
  overlap: number | null;
}

/** (b), (c), (d) za jednu rečenicu nad podupirućim trenucima i metapodacima. */
export function checkSentence(
  text: string,
  support: readonly SourceMoment[],
  episode: EpisodeMeta,
  opts: { overlap: boolean },
): SentenceCheck {
  const corpus = buildCorpus(support, episode);
  const problems: Problem[] = [];
  for (const n of unknownNames(text, corpus.literal)) {
    problems.push({ code: 'unknown_name', detail: `ime „${n}” nije u izvoru ni u podacima o epizodi` });
  }
  const known = new Set(numbersIn(corpus.literal, { parts: true }));
  for (const n of numbersIn(text)) {
    if (!known.has(n)) problems.push({ code: 'unknown_number', detail: `broj ${n} nije u izvoru ni u podacima o epizodi` });
  }
  const overlap = opts.overlap ? lexicalOverlap(text, corpus.lexical) : null;
  if (overlap !== null && overlap < MIN_LEXICAL_OVERLAP) {
    problems.push({
      code: 'low_overlap',
      detail: `preklapanje s izvorom ${overlap.toFixed(3)} < ${String(MIN_LEXICAL_OVERLAP)}`,
    });
  }
  return { problems, overlap };
}

// ---------------------------------------------------------------- stil (upozorenja)

export interface StyleIssue {
  code: 'title_punctuation' | 'title_quotes' | 'clickbait' | 'opinion' | 'superlative' | 'first_person' | 'emoji' | 'caps';
  detail: string;
}

const CLICKBAIT = ['šokantno', 'nevjerojatno', 'nećete vjerovati', 'evo zašto', 'otkriveno'];
const OPINION = ['hrabro', 'nažalost', 'srećom', 'važno je istaknuti', 'jasno je da'];
const SUPERLATIVE = ['najveći', 'najveća', 'najveće', 'povijesni', 'povijesna', 'ključni', 'ključna', 'revolucionarn'];

function has(text: string, phrases: readonly string[]): string[] {
  const t = text.toLowerCase();
  return phrases.filter((p) => new RegExp(`(^|[^\\p{L}])${p}`, 'u').test(t));
}

/** Upozorenja po stilskom vodiču (V1, V3, V8, V9, V12). Ne mijenjaju potporu i ne brišu ništa. */
export function styleIssues(text: string, opts: { title: boolean; corpus: string }): StyleIssue[] {
  const out: StyleIssue[] = [];
  if (opts.title && /[?!]/.test(text)) out.push({ code: 'title_punctuation', detail: 'naslov s upitnikom ili uskličnikom (V3)' });
  if (opts.title && inlineQuotes(text).length > 0) out.push({ code: 'title_quotes', detail: 'naslov s navodnicima (V3)' });
  for (const p of has(text, CLICKBAIT)) out.push({ code: 'clickbait', detail: `„${p}” (V3)` });
  for (const p of has(text, OPINION)) out.push({ code: 'opinion', detail: `„${p}” (V9)` });
  const prose = text.replace(INLINE_QUOTE_RE, ' ');
  for (const p of has(prose, SUPERLATIVE)) out.push({ code: 'superlative', detail: `„${p}” bez navodnika (V8)` });
  if (/(^|[^\p{L}])(mi|nas|naš|naša|naše|ja|vi|vas|vaš)(?=[^\p{L}]|$)/iu.test(prose)) {
    out.push({ code: 'first_person', detail: 'prvo ili drugo lice (V1)' });
  }
  if (/\p{Extended_Pictographic}/u.test(text)) out.push({ code: 'emoji', detail: 'emoji (V12)' });
  for (const w of prose.match(/(?<!\p{L})\p{Lu}{4,}(?!\p{L})/gu) ?? []) {
    if (!opts.corpus.includes(w)) out.push({ code: 'caps', detail: `„${w}” velikim slovima (V12)` });
  }
  return out;
}

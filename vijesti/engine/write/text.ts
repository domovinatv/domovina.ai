// Tekstne pomoćne funkcije za članak (generator i provjera): rečenice, broj
// riječi, slug, datum i vrijeme u snimci. Determinističke, bez modela.

/** Mala slova, bez dijakritike (`đ → d`). */
export function fold(s: string): string {
  return s.toLowerCase().replace(/đ/g, 'd').normalize('NFD').replace(/\p{M}/gu, '');
}

/** Broj s razdjelnicima (`8,000`, `3.5`) je jedna riječ; inače slova/znamenke s crticom ili apostrofom unutra. */
const WORD_RE = /\p{N}+(?:[.,]\p{N}+)*(?![\p{L}])|[\p{L}\p{N}]+(?:[-'’][\p{L}\p{N}]+)*/gu;

/** Riječi kako ih čitatelj broji: niz slova/znamenki, s crticom ili apostrofom unutra. */
export function wordCount(text: string): number {
  return text.match(WORD_RE)?.length ?? 0;
}

/** Riječi teksta (isti uzorak kao `wordCount`). */
export function words(text: string): string[] {
  return text.match(WORD_RE) ?? [];
}

/**
 * Kratice iza kojih točka ne završava rečenicu (mala slova, bez točke).
 * Titule iz `NAME_TITLES` (score/persons.ts) i uobičajene kratice.
 */
const ABBREVIATIONS = new Set([
  'dr', 'fra', 'fr', 'don', 'prof', 'doc', 'izv', 'mr', 'mag', 'ing', 'dipl', 'mons', 'msgr', 'vlč', 'vlc',
  'sv', 'br', 'npr', 'tj', 'itd', 'sl', 'god', 'st', 'gosp', 'gđa', 'gđica', 'tzv', 'odn', 'usp', 'pok', 'ul',
  'mrs', 'ms', 'rev', 'jr', 'sr', 'vs', 'etc',
]);

const OPEN_QUOTES = new Set(['„', '“', '"']);
const CLOSE_QUOTES = new Set(['”', '“', '"']);

/**
 * Dijeli tekst na rečenice. Granica je `.`, `!`, `?` ili `…` iza kojih dolazi
 * razmak i veliko slovo, znamenka ili otvoreni navodnik, i to izvan navodnika.
 * Ne dijeli iza kratice (`dr.`, `fra`, `npr.`), iza inicijala (`p.`) ni iza
 * rednog broja ispred malog slova (`11. kolovoza`), jer mu ne slijedi veliko slovo.
 */
export function splitSentences(text: string): string[] {
  const out: string[] = [];
  const t = text.trim();
  let start = 0;
  let inQuote = false;
  for (let i = 0; i < t.length; i++) {
    const c = t[i] ?? '';
    if (inQuote) {
      if (!CLOSE_QUOTES.has(c)) continue;
      inQuote = false;
      // Citat koji završava rečenicu: `… početak.” Zatim` (znak ispred zatvorenog navodnika).
      if (!/[.!?…]/.test(t[i - 1] ?? '')) continue;
      let k = i + 1;
      if (!/\s/.test(t[k] ?? '')) continue;
      while (k < t.length && /\s/.test(t[k] ?? '')) k++;
      if (k >= t.length || !/[\p{Lu}\p{N}„“"]/u.test(t[k] ?? '')) continue;
      out.push(t.slice(start, i + 1).trim());
      start = k;
      i = k - 1;
      continue;
    }
    if (OPEN_QUOTES.has(c)) {
      inQuote = true;
      continue;
    }
    if (c !== '.' && c !== '!' && c !== '?' && c !== '…') continue;
    // Više znakova zaredom (`?!`, `...`) i zatvoreni navodnik idu uz rečenicu.
    let j = i + 1;
    while (j < t.length && /[.!?…”"»)]/.test(t[j] ?? '')) j++;
    if (j >= t.length) break;
    if (!/\s/.test(t[j] ?? '')) continue;
    let k = j;
    while (k < t.length && /\s/.test(t[k] ?? '')) k++;
    const next = t[k] ?? '';
    if (!/[\p{Lu}\p{N}„“"]/u.test(next)) continue;
    if (c === '.') {
      const before = /([\p{L}]+)$/u.exec(t.slice(start, i))?.[1] ?? '';
      if (ABBREVIATIONS.has(before.toLowerCase()) || before.length === 1) continue;
    }
    out.push(t.slice(start, j).trim());
    start = k;
    i = k - 1;
  }
  const rest = t.slice(start).trim();
  if (rest) out.push(rest);
  return out;
}

/** Transliteriran slug: mala slova, bez dijakritike, crtice, do `max` znakova po granici riječi. */
export function slugify(s: string, max = 60): string {
  const base = fold(s)
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  if (base.length <= max) return base;
  const cut = base.slice(0, max);
  const at = cut.lastIndexOf('-');
  return (at > 20 ? cut.slice(0, at) : cut).replace(/-+$/g, '');
}

const MONTHS_GEN = [
  'siječnja', 'veljače', 'ožujka', 'travnja', 'svibnja', 'lipnja',
  'srpnja', 'kolovoza', 'rujna', 'listopada', 'studenoga', 'prosinca',
];

/** `2026-11-06` → `6. studenoga 2026.`; nevaljan datum → null. */
export function hrDate(iso: string | null): string | null {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(iso ?? '');
  if (!m) return null;
  const month = MONTHS_GEN[Number(m[2]) - 1];
  if (!month) return null;
  return `${String(Number(m[3]))}. ${month} ${m[1] ?? ''}.`;
}

/** Vrijeme u snimci `H:MM:SS` (ili `M:SS` ispod sata). */
export function clock(ms: number): string {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const mm = String(Math.floor((s % 3600) / 60)).padStart(h > 0 ? 2 : 1, '0');
  const ss = String(s % 60).padStart(2, '0');
  return h > 0 ? `${String(h)}:${mm}:${ss}` : `${mm}:${ss}`;
}

/** `00:12:34` kao u promptu ocjene. */
export function hms(ms: number): string {
  const s = Math.floor(ms / 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(Math.floor(s / 3600))}:${p(Math.floor((s % 3600) / 60))}:${p(s % 60)}`;
}

/** Link na trenutak u aplikaciji (kao `momentLink` u izvještaju). */
export function momentUrl(videoId: string, startMs: number): string {
  return `https://domovina.ai/v/${videoId}/t/${String(Math.floor(startMs / 1000))}`;
}

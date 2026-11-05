// Normalizacija teksta za usporedbu citata s titlom (odluke 202, 210, 213). Ista
// funkcija ide na citat i na riječi titla, pa razlike u pisanju (velika
// slova, interpunkcija, apostrofi) ne utječu na poklapanje.
//
// Svaki token ima dva oblika: `t` bez dijakritike (za pretragu i dijagnozu)
// i `d` s dijakritikom (za presudu). `kriza`/`križa`, `nas`/`naš` i
// `mladih`/`mlađih` imaju isti `t`, a različito znače, pa točno poklapanje
// traži jednak `d` (odluka 210).

/** Apostrofi se brišu (don't → dont), ne pretvaraju u razmak. */
const APOSTROPHES = /['’‘ʼ`´]/g;
/** Sve što nije slovo, kombinirajući znak ili znamenka je razmak. */
const NON_WORD = /[^\p{L}\p{M}\p{N}]+/gu;
const COMBINING = /\p{M}+/gu;
/**
 * Razdjelnik tisućica unutar broja se briše (odluka 213): `300,000`,
 * `300.000` i `300000` su isti broj. Samo ispred točno tri znamenke, pa
 * decimalni `3,5` i vrijeme `12.30` ostaju dva tokena.
 */
const THOUSANDS_SEP = /(\d)[.,](?=\d{3}(?!\d))/g;

export interface NormToken {
  /** Bez dijakritike, `đ → d`. */
  t: string;
  /** S dijakritikom (NFC), mala slova. */
  d: string;
}

/**
 * Jedna riječ (ili cijeli tekst) → tokeni u oba oblika. Oba oblika nastaju iz
 * istog rastava, pa su uvijek poravnati. Prazno → [].
 */
export function normalizeWords(raw: string): NormToken[] {
  const s = raw
    .toLowerCase()
    .normalize('NFD')
    .replace(APOSTROPHES, '')
    .replace(THOUSANDS_SEP, '$1')
    .replace(NON_WORD, ' ')
    .trim();
  if (s === '') return [];
  const out: NormToken[] = [];
  for (const w of s.split(/\s+/)) {
    // đ nema rastav u NFD-u (nije d + kvačica), pa ide eksplicitno.
    const t = w.replace(COMBINING, '').replace(/đ/g, 'd');
    if (t === '') continue;
    out.push({ t, d: w.normalize('NFC') });
  }
  return out;
}

export function normalizeTokens(raw: string): string[] {
  return normalizeWords(raw).map((w) => w.t);
}

export function normalizeText(raw: string): string {
  return normalizeTokens(raw).join(' ');
}

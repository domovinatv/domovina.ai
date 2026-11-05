// Normalizacija teksta za usporedbu citata s titlom (odluka 202). Ista
// funkcija ide na citat i na riječi titla, pa razlike u pisanju (velika
// slova, dijakritika, interpunkcija, apostrofi) ne utječu na poklapanje.

/** Apostrofi se brišu (don't → dont), ne pretvaraju u razmak. */
const APOSTROPHES = /['’‘ʼ`´]/g;
/** Sve što nije slovo ili znamenka je razmak. */
const NON_WORD = /[^\p{L}\p{N}]+/gu;
const COMBINING = /\p{M}+/gu;

/** Jedna riječ (ili cijeli tekst) → normalizirani tokeni. Prazno → []. */
export function normalizeTokens(raw: string): string[] {
  const s = raw
    .toLowerCase()
    // đ nema rastav u NFD-u (nije d + kvačica), pa ide eksplicitno.
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(COMBINING, '')
    .replace(APOSTROPHES, '')
    .replace(NON_WORD, ' ')
    .trim();
  return s === '' ? [] : s.split(/\s+/);
}

export function normalizeText(raw: string): string {
  return normalizeTokens(raw).join(' ');
}

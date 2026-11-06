// Nazivi kategorija za čitatelja. Ključevi su zatvoreni popis generatora
// (`engine/write/prompt.ts` CATEGORIES); test provjerava podudaranje.

export const CATEGORY_LABELS = {
  politika: 'Politika',
  gospodarstvo: 'Gospodarstvo',
  vjera: 'Vjera',
  zdravlje: 'Zdravlje',
  obrazovanje: 'Obrazovanje',
  'znanost-tehnologija': 'Znanost i tehnologija',
  kultura: 'Kultura',
  sport: 'Sport',
  svijet: 'Svijet',
  drustvo: 'Društvo',
} as const;

export type CategorySlug = keyof typeof CATEGORY_LABELS;

export const CATEGORY_SLUGS = Object.keys(CATEGORY_LABELS) as CategorySlug[];

export function isCategory(s: string | null | undefined): s is CategorySlug {
  return typeof s === 'string' && Object.hasOwn(CATEGORY_LABELS, s);
}

export function categoryLabel(s: string | null | undefined): string {
  return isCategory(s) ? CATEGORY_LABELS[s] : 'Vijesti';
}

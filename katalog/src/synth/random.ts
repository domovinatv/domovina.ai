// Zajednički dijelovi sintetičkih raspodjela (S4): PRNG sa sjemenom i abeceda
// ID-eva. Čist modul bez Node i Workers API-ja, da ga uvoze i vitest (workerd)
// i `scripts/synth.ts` (Node 24, type stripping).

/** mulberry32: mali PRNG sa sjemenom, da je raspodjela ista u svakom pokretanju. */
export function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** Abeceda YouTube ID-eva (64 znaka). */
export const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

const DAY_MS = 86_400_000;

/** `YYYY-MM-DD` za UTC dan `days` dana nakon `startMs`. */
export function isoDay(startMs: number, days: number): string {
  return new Date(startMs + days * DAY_MS).toISOString().slice(0, 10);
}

/** Broj dana između dva UTC datuma u milisekundama. */
export function daysBetween(fromMs: number, toMs: number): number {
  return Math.round((toMs - fromMs) / DAY_MS);
}

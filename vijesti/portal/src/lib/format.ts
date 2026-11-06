// Prikaz vremena i datuma. Vrijeme u snimci je isti `clock` kao u engineu i
// bazi (`vijesti._clock`): m:ss ispod sata, h:mm:ss iznad.
import { clock, hrDate } from '../../../engine/write/text.js';

export { clock, hrDate };

const ZAGREB = new Intl.DateTimeFormat('en-CA', {
  timeZone: 'Europe/Zagreb',
  year: 'numeric',
  month: '2-digit',
  day: '2-digit',
});

/** `YYYY-MM-DD` po zagrebačkom vremenu (objava u 23:30 UTC je sutrašnji datum). */
export function zagrebDay(iso: string | null | undefined): string | null {
  if (!iso) return null;
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : ZAGREB.format(d);
}

/** `6. studenoga 2026.` iz vremenske oznake (zagrebački dan). */
export function hrDateTime(iso: string | null | undefined): string | null {
  return hrDate(zagrebDay(iso));
}

/** Trajanje isječka za čitatelja: `0:22`. */
export function clipLength(startMs: number, endMs: number): string {
  return clock(Math.max(0, endMs - startMs));
}

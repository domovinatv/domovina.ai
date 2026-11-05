/** `HH:MM:SS` (article/outline) u ms. Neispravan zapis je greška. */
export function hmsToMs(hms: string): number {
  const m = /^(\d{2}):(\d{2}):(\d{2})$/.exec(hms);
  if (!m) throw new Error(`neispravno vrijeme: ${hms}`);
  return (Number(m[1]) * 3600 + Number(m[2]) * 60 + Number(m[3])) * 1000;
}

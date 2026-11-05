// Keyset kursor API-ja v1 (odluka 304): base64url bez paddinga nad JSON nizom
// od dva stringa. Epizode `[published_date, id]`, kanali `[latest_published_date,
// slug]`. Klijent ga ne čita ni ne gradi, samo vraća ono što je dobio u `next`.

/** Valjan kalendarski datum `YYYY-MM-DD` (isto pravilo kao CHECK u shemi, odluka 108). */
export function isIsoDate(value: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

export function encodeCursor(date: string, key: string): string {
  const bytes = new TextEncoder().encode(JSON.stringify([date, key]));
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/**
 * `[datum, ključ]` ili `null` kad kursor nije naš: nije base64url, nije JSON,
 * nije niz od točno dva neprazna stringa, prvi nije valjan datum, ili zapis
 * nije kanonski (isti kursor ima jedan zapis, pa i jedan ključ u cacheu).
 */
export function decodeCursor(cursor: string): readonly [string, string] | null {
  if (!/^[A-Za-z0-9_-]+$/.test(cursor)) return null;
  let value: unknown;
  try {
    const bin = atob(cursor.replace(/-/g, "+").replace(/_/g, "/"));
    const text = new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(
      Uint8Array.from(bin, (ch) => ch.charCodeAt(0)),
    );
    value = JSON.parse(text);
  } catch {
    return null;
  }
  if (!Array.isArray(value) || value.length !== 2) return null;
  const [date, key] = value as unknown[];
  if (typeof date !== "string" || typeof key !== "string" || key.length === 0) return null;
  if (!isIsoDate(date)) return null;
  if (encodeCursor(date, key) !== cursor) return null;
  return [date, key];
}

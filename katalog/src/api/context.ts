// Memorija konteksta kataloga u izolatu (odluke 502, 600). Kontekst = brend po
// hostu + verzija kataloga (`catalogContext`). Hit putanja ga čita odavde i ne
// ide u D1; miss ga uvijek ponovno čita iz D1 i osvježi memoriju.
//
// NIJE u `src/index.ts`: workerd svaki imenovani export glavnog modula čita kao
// entrypoint (odluka 312), a testovi trebaju `forgetCatalogContexts`.

/** Koliko dugo izolat vjeruje zapamćenom kontekstu (odluka 600). Manje od `max-age=60`. */
export const CONTEXT_TTL_MS = 30_000;

/**
 * Gornja granica broja zapamćenih hostova. Host dolazi iz zahtjeva, pa memorija
 * ne smije rasti bez granice; prijelaz granice briše sve (odluka 600).
 */
export const MAX_CONTEXTS = 32;

export interface CatalogContextValue {
  readonly brand: string;
  /** `max(id)` uspješnih uvoza kao string, `null` kad uvoza nema (odluka 300). */
  readonly catalog: string | null;
}

interface Entry extends CatalogContextValue {
  readonly expires: number;
}

const memory = new Map<string, Entry>();

export function contextKey(hostname: string, defaultBrand: string): string {
  return `${hostname}\u0000${defaultBrand}`;
}

/** Zapamćen kontekst ako još vrijedi u trenutku `nowMs`, inače `undefined`. */
export function recallContext(key: string, nowMs: number): CatalogContextValue | undefined {
  const e = memory.get(key);
  if (e === undefined) return undefined;
  if (nowMs >= e.expires) {
    memory.delete(key);
    return undefined;
  }
  return { brand: e.brand, catalog: e.catalog };
}

/** Zapamti kontekst pročitan iz D1. `brand_not_found` se ne pamti (odluka 600). */
export function rememberContext(key: string, value: CatalogContextValue, nowMs: number): void {
  if (!memory.has(key) && memory.size >= MAX_CONTEXTS) memory.clear();
  memory.set(key, { brand: value.brand, catalog: value.catalog, expires: nowMs + CONTEXT_TTL_MS });
}

/** Zaboravi jedan host (npr. brend je u međuvremenu nestao). */
export function forgetContext(key: string): void {
  memory.delete(key);
}

/** Zaboravi sve: ingest nakon nove verzije kataloga (u svom izolatu) i testovi. */
export function forgetCatalogContexts(): void {
  memory.clear();
}

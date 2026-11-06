// Dohvat s CDN-a za Node skripte (uvoznik, drift-check). Bez Node API-ja, pa ga
// uvoze i testovi u workerd poolu; `fetch` se može predati (stub u testu).
//
// Izdvojeno iz `scripts/import.mjs` (S2) bez promjene ponašanja: isti retry na
// 404, isti brojači u izvještaju.

export const CDN_BASE = "https://cdn.domovina.ai/";

export interface HttpStats {
  get: number;
  notFound: number;
  retried: number;
  missingAfterRetry: number;
}

export interface Cdn {
  readonly stats: HttpStats;
  /** `null` = nema ni nakon retryja s cache-busterom; sve osim 200/404 baca. */
  getText(path: string): Promise<string | null>;
  /** Kao `getText`, ali „nema” baca. */
  getRequired(path: string): Promise<string>;
}

/** Isti 5-minutni bucket kao `CdnConfig.bustCache` u aplikaciji. */
export const cacheBuster = (now: number = Date.now()): number => Math.floor(now / 300_000);

/**
 * Pravilo `DataService._get`: CDN cachira i 404 (u zasebnom `Vary: Origin` zapisu),
 * pa se 404 ponovi jednom s cache-busterom; tek drugi 404 znači „nema”.
 */
export interface CdnOptions {
  base?: string;
  fetch?: typeof fetch;
  /**
   * Odmah nakon uploada (pipeline, `ingest-episode`): edge zna držati stari listing
   * kanala ili 404 zapamćen pod 5-minutnim bucketom koji koristi i aplikacija dok
   * epizoda još nastaje. `fresh` zato putanje pod `channels/` uvijek, a 404 retry
   * svugdje, traži s jedinstvenim cache-busterom (`Date.now()`), pa ide do R2.
   */
  fresh?: boolean;
  /** Za test: izvor jedinstvenog bustera u `fresh` načinu. */
  now?: () => number;
}

export function createCdn(opts: CdnOptions = {}): Cdn {
  const base = opts.base ?? CDN_BASE;
  const doFetch = opts.fetch ?? ((input, init) => fetch(input, init));
  const fresh = opts.fresh ?? false;
  const now = opts.now ?? Date.now;
  const stats: HttpStats = { get: 0, notFound: 0, retried: 0, missingAfterRetry: 0 };

  async function getText(path: string): Promise<string | null> {
    const url = base + path;
    stats.get++;
    let res = await doFetch(fresh && path.startsWith("channels/") ? `${url}?cb=${now()}` : url);
    if (res.status === 404) {
      stats.notFound++;
      stats.retried++;
      stats.get++;
      res = await doFetch(`${url}?cb=${fresh ? now() : cacheBuster()}`);
      if (res.status === 404) {
        stats.missingAfterRetry++;
        return null;
      }
    }
    if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
    return res.text();
  }

  async function getRequired(path: string): Promise<string> {
    const text = await getText(path);
    if (text === null) throw new Error(`${base}${path}: 404 i nakon cache-bustera`);
    return text;
  }

  return { stats, getText, getRequired };
}

/** `fn` nad `items` s najviše `limit` istodobnih poziva; redoslijed izlaza = ulaza. */
export async function pool<T, R>(items: readonly T[], limit: number, fn: (item: T, i: number) => Promise<R>): Promise<R[]> {
  const out = new Array<R>(items.length);
  let next = 0;
  async function worker(): Promise<void> {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i] as T, i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/** Parser uz kontekst: InputError dobiva datoteku u poruci. */
export function parseWith<T>(parse: (raw: unknown) => T, text: string, label: string): T {
  try {
    return parse(JSON.parse(text));
  } catch (err) {
    throw new Error(`${label}: ${err instanceof Error ? err.message : String(err)}`, { cause: err });
  }
}

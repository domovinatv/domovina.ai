// Magisterium ocjena Tier 2 epizoda (odluka 1206). Tier 1 je dobiva iz listinga
// kanala; Tier 2 listing nema, pa je izvor `data/<id>/article.magisterium.json`
// `overall_score` — isto polje koje čita ekran epizode (`MagisteriumData`).
//
// Datoteka ima ~94 kB i CDN je ne cachira (`cf-cache-status: DYNAMIC`), a puni
// plan se gradi nakon svake obrađene epizode. Zato lokalni cache po ID-u, s
// veličinom datoteke iz key cachea kao ključem valjanosti: dohvaća se samo nova
// ili promijenjena (reobrada) datoteka.
import { pool, type Cdn } from "./cdn.ts";

export const MAGISTERIUM_FILE = "article.magisterium.json";

interface Entry {
  readonly size: number;
  readonly score: number | null;
}

/** `sizes` iz `.r2_keys_cache.json` → ID → veličina `article.magisterium.json`. */
export function magisteriumSizes(keyCacheText: string): Map<string, number> {
  const out = new Map<string, number>();
  const raw = JSON.parse(keyCacheText) as { sizes?: Record<string, unknown> };
  const suffix = `/${MAGISTERIUM_FILE}`;
  for (const [key, size] of Object.entries(raw.sizes ?? {})) {
    if (!key.startsWith("data/") || !key.endsWith(suffix) || typeof size !== "number") continue;
    out.set(key.slice(5, -suffix.length), size);
  }
  return out;
}

/** `overall_score` cijeli broj 0–100, inače `null`. Nečitljiv JSON → `null`. */
export function overallScore(text: string): number | null {
  try {
    const v = (JSON.parse(text) as { overall_score?: unknown }).overall_score;
    return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 100 ? v : null;
  } catch {
    return null;
  }
}

/** Gdje cache živi; u skriptama datoteka (`fileStore` u `magisterium-store.ts`), u testu memorija. */
export interface ScoreStore {
  /** `null` = cachea još nema. */
  read(): Promise<string | null>;
  write(text: string): Promise<void>;
}

async function readCache(store: ScoreStore): Promise<Map<string, Entry>> {
  try {
    const text = await store.read();
    if (text === null) return new Map();
    const raw = JSON.parse(text) as Record<string, Partial<Entry> | null>;
    const out = new Map<string, Entry>();
    for (const [id, e] of Object.entries(raw)) {
      if (e === null || typeof e.size !== "number") continue;
      if (e.score === null || typeof e.score === "number") out.set(id, { size: e.size, score: e.score });
    }
    return out;
  } catch {
    return new Map();
  }
}

export interface MagisteriumScores {
  readonly scores: ReadonlyMap<string, number | null>;
  readonly fetched: number;
  readonly cached: number;
}

/**
 * Ocjene za [ids] koji u key cacheu imaju `article.magisterium.json`. Pogodak u
 * cacheu (ista veličina) se ne dohvaća; dohvat koji padne ili vrati „nema” ne
 * ulazi u cache, pa se sljedeći put pokuša ponovno.
 */
export async function loadMagisteriumScores(opts: {
  readonly ids: readonly string[];
  readonly sizes: ReadonlyMap<string, number>;
  readonly cdn: Cdn;
  readonly store: ScoreStore;
  readonly concurrency: number;
}): Promise<MagisteriumScores> {
  const cache = await readCache(opts.store);
  const scores = new Map<string, number | null>();
  const misses: { id: string; size: number }[] = [];
  let cached = 0;
  for (const id of opts.ids) {
    const size = opts.sizes.get(id);
    if (size === undefined) continue;
    const hit = cache.get(id);
    if (hit !== undefined && hit.size === size) {
      scores.set(id, hit.score);
      cached += 1;
    } else misses.push({ id, size });
  }
  let fetched = 0;
  await pool(misses, opts.concurrency, async ({ id, size }) => {
    const text = await opts.cdn.getText(`data/${id}/${MAGISTERIUM_FILE}`);
    if (text === null) return;
    const score = overallScore(text);
    scores.set(id, score);
    cache.set(id, { size, score });
    fetched += 1;
  });
  if (fetched > 0) {
    const sorted = Object.fromEntries([...cache].sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)));
    await opts.store.write(`${JSON.stringify(sorted)}\n`);
  }
  return { scores, fetched, cached };
}

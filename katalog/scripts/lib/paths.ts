// Putanje ulaza koje dijele uvoznik i drift-check (Node, ne ide u workerd testove).
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

/** Korijen `katalog/`. */
export const KATALOG = resolve(dirname(fileURLToPath(import.meta.url)), "../..");
export const FETCH_REPO = resolve(KATALOG, "../../fetch.domovina.tv");

export const KEY_CACHE_PATH = process.env.KATALOG_KEY_CACHE_PATH
  ? resolve(process.env.KATALOG_KEY_CACHE_PATH)
  : join(FETCH_REPO, ".r2_keys_cache.json");

export const REGISTRY_PATH = process.env.KATALOG_REGISTRY_PATH
  ? resolve(process.env.KATALOG_REGISTRY_PATH)
  : join(FETCH_REPO, "data", "podcasts_registry.json");

/** Točni dani objave (`automatic/backfill_days.js`); opcionalan ulaz (odluka 1200). */
export const BACKFILL_PATH = process.env.KATALOG_BACKFILL_PATH
  ? resolve(process.env.KATALOG_BACKFILL_PATH)
  : join(FETCH_REPO, "automatic", "watchlist", "backfill.json");

/** Tekst datoteke ili `null` kad je nema (ENOENT); ostale greške se bacaju. */
export async function readOptionalText(path: string): Promise<string | null> {
  const { readFile } = await import("node:fs/promises");
  try {
    return await readFile(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

/**
 * Lokalni cache Magisterium ocjena Tier 2 epizoda (odluka 1206): ID → veličina
 * `article.magisterium.json` iz key cachea + `overall_score`. U `.cache/`
 * (gitignore); obrisan cache = jedan puni dohvat (~350 × ~94 kB).
 */
export const MAGISTERIUM_CACHE_PATH = process.env.KATALOG_MAGISTERIUM_CACHE_PATH
  ? resolve(process.env.KATALOG_MAGISTERIUM_CACHE_PATH)
  : join(KATALOG, ".cache", "magisterium-scores.json");

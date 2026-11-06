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

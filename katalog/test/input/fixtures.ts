// Fixturei kao stringovi (odluka 117): parser dobiva ono što bi dobio iz
// `JSON.parse(await res.text())`. Generira ih `npm run fixtures:refresh`.
import { InputError } from "../../src/input/index.ts";

type Raw = Record<string, string>;

// Opcije moraju biti literal na svakom pozivu (vite to parsira statički).
export const allFixtures: Raw = import.meta.glob<string>("../fixtures/**/*.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const channelIndex: Raw = import.meta.glob<string>("../fixtures/channels/index.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const listings: Raw = import.meta.glob<string>(
  ["../fixtures/channels/*.json", "!../fixtures/channels/index.json"],
  { query: "?raw", import: "default", eager: true },
);
const infos: Raw = import.meta.glob<string>("../fixtures/data/*/info.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const summaries: Raw = import.meta.glob<string>("../fixtures/data/*/summary.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const manifests: Raw = import.meta.glob<string>("../fixtures/data/*/episode.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const registry: Raw = import.meta.glob<string>("../fixtures/registry/podcasts_registry.json", {
  query: "?raw",
  import: "default",
  eager: true,
});
const keyCache: Raw = import.meta.glob<string>("../fixtures/r2_keys_cache.json", {
  query: "?raw",
  import: "default",
  eager: true,
});

/** `../fixtures/data/<id>/info.json` → `<id>`; `../fixtures/channels/<slug>.json` → `<slug>`. */
function keyOf(path: string): string {
  const parts = path.split("/");
  const file = parts.at(-1) ?? "";
  if (path.includes("/data/")) return parts.at(-2) ?? "";
  return file.replace(/\.json$/, "");
}

function parsed(raw: Raw): Map<string, unknown> {
  return new Map(Object.entries(raw).map(([path, text]) => [keyOf(path), JSON.parse(text) as unknown]));
}

function only(raw: Raw): unknown {
  const values = Object.values(raw);
  if (values.length !== 1 || values[0] === undefined) throw new Error(`očekivan 1 fixture, ima ${values.length}`);
  return JSON.parse(values[0]) as unknown;
}

export const fixtures = {
  index: () => only(channelIndex),
  listings: () => parsed(listings),
  infos: () => parsed(infos),
  summaries: () => parsed(summaries),
  manifests: () => parsed(manifests),
  registry: () => only(registry),
  keyCache: () => only(keyCache),
};

/** Duboka kopija fixturea za negativne testove (mijenja se bez dodira originala). */
export function clone<T>(value: T): T {
  return structuredClone(value);
}

/** Tier 2 epizode s `info.json`, `summary.json` i `episode.json` (sortirano). */
export const UNLISTED_IDS = [
  "0sxT3NF8yFg",
  "7N0gyXAfA4M",
  "A-oDNz3nvdQ",
  "CUJmOc91C64",
  "KLPD-Meu4e8",
  "UM2MWlNUp_1",
  "hmM9f_3Mqm4",
  "kYwKrihe2K0",
];
/** Tier 2 epizode bez `info.json` na R2: samo `summary.json`. */
export const NO_INFO_IDS = ["6dcab9c9837"];
export const LISTING_SLUGS = [
  "40_dana_za_zivot",
  "dijalog",
  "nanovoroeni",
  "podcast_cuspajz",
  "slijedi_svoj_poziv_1",
  "slijedi_svoj_poziv_2",
  "subclub",
];

/** Pozove `fn` i vrati InputError koji baci; sve drugo (i prolaz) je pad testa. */
export function inputError(fn: () => unknown): InputError {
  try {
    fn();
  } catch (e) {
    if (e instanceof InputError) return e;
    throw e;
  }
  throw new Error("očekivan InputError, parser je prošao");
}

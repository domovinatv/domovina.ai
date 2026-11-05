// `../fetch.domovina.tv/.r2_keys_cache.json`: `{v: 2, sizes: {<R2 ključ>: <bajtovi>}}`.
// Popis Tier 2 epizoda i njihove pipeline zastavice čitaju se iz ključeva
// (odluke 200–202); sadržaj datoteka ne.
import { InputError, PIPELINE_BITS, type PipelineBit } from "../input/index.ts";
import { asObject, ROOT } from "../input/read.ts";

/** Jedina verzija key cachea koju uvoznik zna čitati. */
export const KEY_CACHE_VERSION = 2;

const EPISODE_KEY = /^data\/([^/]+)\/(.+)$/;

/** Ključ cachea → popis datoteka po epizodi (`data/<id>/<datoteka>`). */
export function parseKeyCache(raw: unknown): Map<string, ReadonlySet<string>> {
  const o = asObject(raw, ROOT);
  if (o.v !== KEY_CACHE_VERSION) throw new InputError("v", `nepoznata verzija key cachea: ${JSON.stringify(o.v)}`);
  const sizes = asObject(o.sizes, "sizes");
  const out = new Map<string, Set<string>>();
  for (const key of Object.keys(sizes)) {
    const m = EPISODE_KEY.exec(key);
    if (m === null) continue;
    const [, id = "", file = ""] = m;
    const set = out.get(id);
    if (set === undefined) out.set(id, new Set([file]));
    else set.add(file);
  }
  return out;
}

/** ID-evi epizoda koje imaju `article.json` (pravilo `podcast.domovina.ai` `58fb664`). */
export function articleIds(files: ReadonlyMap<string, ReadonlySet<string>>): string[] {
  return [...files].filter(([, f]) => f.has("article.json")).map(([id]) => id).sort();
}

/**
 * Pipeline zastavice iz R2 imena datoteka, po pravilima `generate_channel_index.js`
 * (ondje nad lokalnim imenima): izmjereno 3411/3412 Tier 1 epizoda daje isti `flags`
 * kao listing (odluka 202).
 */
export function flagsFromFiles(files: ReadonlySet<string>): number {
  const summaryEn = files.has("summary.en.json");
  const articleEn = files.has("article.en.json");
  const p: Record<PipelineBit, boolean> = {
    has_transcript: files.has("diarized.srt"),
    has_diarized: files.has("diarized.srt"),
    has_summary: files.has("summary.json"),
    has_article: files.has("article.json"),
    has_magisterium: files.has("article.magisterium.json") || files.has("article.magisterium_batch.json"),
    has_translation_en: summaryEn && articleEn,
    has_summary_en: summaryEn,
    has_article_en: articleEn,
    has_magisterium_en: files.has("article.magisterium.en.json"),
  };
  return PIPELINE_BITS.reduce((acc, bit, i) => (p[bit] ? acc | (1 << i) : acc), 0);
}

/**
 * Eksperimentalna varijanta: ID je prvih 9 znakova drugog ID-a + `_<znamenka>`
 * (`0Oo1LHNiJ_2` uz `0Oo1LHNiJR4`). Vraća parove varijanta → osnovni ID; ne filtrira
 * (odluka 208).
 */
export function experimentalVariants(ids: Iterable<string>): { id: string; base: string }[] {
  const all = [...ids].sort();
  const byPrefix = new Map<string, string[]>();
  for (const id of all) {
    const list = byPrefix.get(id.slice(0, 9));
    if (list === undefined) byPrefix.set(id.slice(0, 9), [id]);
    else list.push(id);
  }
  const out: { id: string; base: string }[] = [];
  for (const id of all) {
    if (!/^.{9}_\d$/.test(id)) continue;
    const bases = (byPrefix.get(id.slice(0, 9)) ?? []).filter((b) => !/^.{9}_\d$/.test(b));
    if (bases.length === 1 && bases[0] !== undefined) out.push({ id, base: bases[0] });
  }
  return out;
}

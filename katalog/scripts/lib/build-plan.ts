// Plan uvoza iz stvarnih izvora: key cache (već pročitan) + registry (tekst) +
// CDN (index, listinzi, Tier 2 `info.json`/`summary.json`). Dijele ga uvoznik
// (`scripts/import.mjs`) i `drift-check --sync`, da `--sync` piše ISTE retke
// koje bi napisao uvoz. Bez Node API-ja: datoteke čita pozivatelj.
import {
  parseChannelIndex,
  parseChannelListing,
  parseEpisodeInfo,
  parseEpisodeSummary,
  parsePublishDates,
  parsePublishTimes,
  parseRegistry,
} from "../../src/input/index.ts";
import { articleIds } from "../../src/ingest/keys.ts";
import { buildPlan, type ImportPlan, type PlanReport, type Tier2Input } from "../../src/ingest/plan.ts";
import { readFile } from "node:fs/promises";
import { parseWith, pool, type Cdn, type HttpStats } from "./cdn.ts";
import { loadMagisteriumScores, MAGISTERIUM_FILE, magisteriumSizes } from "./magisterium-scores.ts";
import { fileStore } from "./magisterium-store.ts";

export const CONCURRENCY = 6;

export interface ImportReport extends PlanReport {
  readonly keyCache: {
    readonly path: string;
    readonly articleIds: number;
    readonly tier1Ids: number;
    readonly tier2Ids: number;
    readonly tier1WithoutArticle: number;
  };
  readonly http: HttpStats;
}

export interface BuildImportPlanInput {
  /** `parseKeyCache` nad `.r2_keys_cache.json`. */
  readonly filesById: ReadonlyMap<string, ReadonlySet<string>>;
  readonly keyCachePath: string;
  readonly registryText: string;
  readonly registryPath: string;
  /** `backfill.json` iz fetch repoa (`readOptionalText`); `null` = nema točnih dana (odluka 1200). */
  readonly publishDatesText?: string | null;
  readonly publishDatesPath?: string;
  /**
   * Lokalni cache Magisterium ocjena Tier 2 (odluka 1206). Bez njega Tier 2
   * ostaje bez ocjene (testovi, fixturei). Veličine čita iz [keyCachePath].
   */
  readonly magisteriumCachePath?: string;
  readonly cdn: Cdn;
  readonly concurrency?: number;
  readonly log?: (line: string) => void;
}

export async function buildImportPlan(input: BuildImportPlanInput): Promise<{ plan: ImportPlan; report: ImportReport }> {
  const { filesById, cdn } = input;
  const limit = input.concurrency ?? CONCURRENCY;
  const registry = parseWith(parseRegistry, input.registryText, input.registryPath);

  const index = parseWith(parseChannelIndex, await cdn.getRequired("channels/data/index.json"), "index.json");
  const listings = await pool(index.channels, limit, async (c) =>
    parseWith(parseChannelListing, await cdn.getRequired(`channels/data/${c.slug}.json`), `${c.slug}.json`),
  );
  const tier1Ids = new Set(listings.flatMap((l) => l.videos.map((v) => v.id)));
  const articles = articleIds(filesById);
  const tier2Ids = articles.filter((id) => !tier1Ids.has(id));
  input.log?.(`Tier 1: ${listings.length} listinga, ${tier1Ids.size} epizoda; Tier 2: ${tier2Ids.length} ID-eva`);

  const tier2 = await pool(tier2Ids, limit, async (id): Promise<Tier2Input> => {
    const [infoText, summaryText] = await Promise.all([
      cdn.getText(`data/${id}/info.json`),
      cdn.getText(`data/${id}/summary.json`),
    ]);
    return {
      id,
      info: infoText === null ? null : parseWith(parseEpisodeInfo, infoText, `data/${id}/info.json`),
      summary: summaryText === null ? null : parseWith(parseEpisodeSummary, summaryText, `data/${id}/summary.json`),
      files: filesById.get(id) ?? new Set(),
    };
  });

  if (input.magisteriumCachePath !== undefined) {
    const withFile = tier2.filter((t) => t.files.has(MAGISTERIUM_FILE)).map((t) => t.id);
    const m = await loadMagisteriumScores({
      ids: withFile,
      sizes: magisteriumSizes(await readFile(input.keyCachePath, "utf8")),
      cdn,
      store: fileStore(input.magisteriumCachePath),
      concurrency: limit,
    });
    for (let i = 0; i < tier2.length; i++) {
      const t = tier2[i];
      const score = t === undefined ? undefined : m.scores.get(t.id);
      if (t !== undefined && score !== undefined) tier2[i] = { ...t, magisteriumScore: score };
    }
    input.log?.(
      `Magisterium Tier 2: ${withFile.length} s datotekom, ${m.cached} iz cachea, ${m.fetched} dohvaćeno, ` +
        `${[...m.scores.values()].filter((s) => s !== null).length} s ocjenom`,
    );
  }

  const publishDates =
    input.publishDatesText === undefined || input.publishDatesText === null
      ? undefined
      : parseWith(parsePublishDates, input.publishDatesText, input.publishDatesPath ?? "backfill.json");
  const publishTimes =
    input.publishDatesText === undefined || input.publishDatesText === null
      ? undefined
      : parseWith(parsePublishTimes, input.publishDatesText, input.publishDatesPath ?? "backfill.json");
  input.log?.(
    `točni dani objave (backfill.json): ${publishDates?.size ?? "nema datoteke"}, s trenutkom: ${publishTimes?.size ?? 0}`,
  );
  const plan = buildPlan({
    index,
    listings,
    registry,
    tier2,
    ...(publishDates === undefined ? {} : { publishDates }),
    ...(publishTimes === undefined ? {} : { publishTimes }),
  });
  const report: ImportReport = {
    ...plan.report,
    keyCache: {
      path: input.keyCachePath,
      articleIds: articles.length,
      tier1Ids: tier1Ids.size,
      tier2Ids: tier2Ids.length,
      tier1WithoutArticle: [...tier1Ids].filter((id) => !filesById.get(id)?.has("article.json")).length,
    },
    http: cdn.stats,
  };
  return { plan, report };
}

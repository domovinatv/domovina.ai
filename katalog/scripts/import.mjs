#!/usr/bin/env node
// Uvoznik kataloga (S2): Tier 1 + Tier 2 s CDN-a u LOKALNI D1.
//
//   npm run migrate:local && npm run import
//   npm run import -- --dry-run          # samo izvještaj, bez upisa
//   npm run import -- --json report.json # izvještaj i u datoteku
//
// Ulaz (odluke 200–212):
//   Tier 1: `channels/data/index.json` + svi listinzi s CDN-a.
//   Tier 2: ID-evi s `data/<id>/article.json` u `../fetch.domovina.tv/.r2_keys_cache.json`
//           minus ID-evi iz Tier 1 listinga, pa `info.json` + `summary.json` s CDN-a.
//   Registry: `../fetch.domovina.tv/data/podcasts_registry.json` (samo čitanje).
// Upis: `getPlatformProxy` iz wranglera daje `env.DB` nad istim lokalnim D1 koji
// čita `wrangler d1 execute --local` (`.wrangler/state/v3`), pa upis ide kroz
// isti `applyPlan` kao test i `meta.changes` je po naredbi (odluka 213).
// Nikad `--remote`: `remoteBindings: false`.
//
// Node 24+ (parseri i ingest moduli se uvoze kao .ts, odluka 118).
import { readFile, writeFile } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const CDN = "https://cdn.domovina.ai/";
const CONCURRENCY = 6;
const SOURCE = "backfill";

const KATALOG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const FETCH_REPO = resolve(KATALOG, "../../fetch.domovina.tv");
const KEY_CACHE_PATH = process.env.KATALOG_KEY_CACHE_PATH
  ? resolve(process.env.KATALOG_KEY_CACHE_PATH)
  : join(FETCH_REPO, ".r2_keys_cache.json");
const REGISTRY_PATH = process.env.KATALOG_REGISTRY_PATH
  ? resolve(process.env.KATALOG_REGISTRY_PATH)
  : join(FETCH_REPO, "data", "podcasts_registry.json");

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const jsonIdx = args.indexOf("--json");
const JSON_OUT = jsonIdx >= 0 ? args[jsonIdx + 1] : null;

// ---- Dohvat ----------------------------------------------------------------

const http = { get: 0, notFound: 0, retried: 0, missingAfterRetry: 0 };

/** Isti 5-minutni bucket kao `CdnConfig.bustCache` u aplikaciji. */
const cacheBuster = () => Math.floor(Date.now() / 300_000);

/**
 * Pravilo `DataService._get`: CDN cachira i 404 (u zasebnom `Vary: Origin` zapisu),
 * pa se 404 ponovi jednom s cache-busterom; tek drugi 404 znači „nema”.
 * `null` = nema; sve osim 200/404 baca.
 */
async function getText(path) {
  const url = CDN + path;
  http.get++;
  let res = await fetch(url);
  if (res.status === 404) {
    http.notFound++;
    http.retried++;
    http.get++;
    res = await fetch(`${url}?cb=${cacheBuster()}`);
    if (res.status === 404) {
      http.missingAfterRetry++;
      return null;
    }
  }
  if (!res.ok) throw new Error(`${url}: HTTP ${res.status}`);
  return res.text();
}

async function getRequired(path) {
  const text = await getText(path);
  if (text === null) throw new Error(`${CDN}${path}: 404 i nakon cache-bustera`);
  return text;
}

async function pool(items, limit, fn) {
  const out = new Array(items.length);
  let next = 0;
  async function worker() {
    while (next < items.length) {
      const i = next++;
      out[i] = await fn(items[i], i);
    }
  }
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, worker));
  return out;
}

/** Parser uz kontekst: InputError dobiva datoteku u poruci. */
function parseWith(parse, text, label) {
  try {
    return parse(JSON.parse(text));
  } catch (err) {
    throw new Error(`${label}: ${err instanceof Error ? err.message : err}`, { cause: err });
  }
}

// ---- Izvještaj -------------------------------------------------------------

function printReport(r) {
  const line = (k, v) => console.log(`  ${k.padEnd(34)} ${v}`);
  const ids = (a) => (a.length === 0 ? "0" : `${a.length}  ${a.join(" ")}`);
  console.log("\nIzvještaj uvoza");
  line("epizode tier 1 / tier 2", `${r.episodes.tier1} / ${r.episodes.tier2}`);
  line("kanali tier 1 / tier 2 (unregistered)", `${r.channels.tier1} / ${r.channels.tier2} (${r.channels.unregistered})`);
  line("Tier 2 po putu kanala", JSON.stringify(r.tier2Via));
  const reasons = Object.entries(r.withoutChannel);
  line("epizode bez kanala", reasons.reduce((n, [, a]) => n + a.length, 0));
  for (const [reason, a] of reasons) line(`  ${reason}`, ids(a));
  line("bez datuma tier 1", ids(r.withoutDate.tier1));
  line("bez datuma tier 2", ids(r.withoutDate.tier2));
  line("Tier 2 na praćenom kanalu", r.tier2OnTier1Channel.length);
  for (const t of r.tier2OnTier1Channel) line("", `${t.id} → ${t.slug} (${t.via})`);
  line("Tier 2 bez info.json", ids(r.withoutInfoJson));
  line("info.json id ≠ ID mape", r.infoIdMismatch.map((m) => `${m.id}≠${m.infoId}`).join(" ") || "0");
  line("eksperimentalne varijante", r.experimentalVariants.map((v) => `${v.id}(${v.base})`).join(" ") || "0");
  line("video_count ≠ listing", r.videoCountMismatch.map((m) => m.slug).join(" ") || "0");
  line("Tier 2 ID u Tier 1 listingu", ids(r.tier2AlsoInTier1));
  if (r.keyCache) line("key cache: article / tier 1 / tier 2", `${r.keyCache.articleIds} / ${r.keyCache.tier1Ids} / ${r.keyCache.tier2Ids}`);
  if (r.keyCache) line("Tier 1 epizode bez article.json", r.keyCache.tier1WithoutArticle);
  if (r.written) line("promijenjeni retci (brand/kanal/ep.)", `${r.written.brands} / ${r.written.channels} / ${r.written.episodes}`);
  line("HTTP GET / 404 / retry / nema", `${r.http.get} / ${r.http.notFound} / ${r.http.retried} / ${r.http.missingAfterRetry}`);
}

// ---- Glavni tok ------------------------------------------------------------

async function main() {
  const P = await import("../src/input/index.ts");
  const K = await import("../src/ingest/keys.ts");
  const { buildPlan, DOMOVINA_BRAND } = await import("../src/ingest/plan.ts");
  const W = await import("../src/ingest/write.ts");
  const startedAt = new Date().toISOString();

  const filesById = K.parseKeyCache(JSON.parse(await readFile(KEY_CACHE_PATH, "utf8")));
  const registry = parseWith(P.parseRegistry, await readFile(REGISTRY_PATH, "utf8"), REGISTRY_PATH);

  const index = parseWith(P.parseChannelIndex, await getRequired("channels/data/index.json"), "index.json");
  const listings = await pool(index.channels, CONCURRENCY, async (c) =>
    parseWith(P.parseChannelListing, await getRequired(`channels/data/${c.slug}.json`), `${c.slug}.json`),
  );
  const tier1Ids = new Set(listings.flatMap((l) => l.videos.map((v) => v.id)));
  const articles = K.articleIds(filesById);
  const tier2Ids = articles.filter((id) => !tier1Ids.has(id));
  console.log(`Tier 1: ${listings.length} listinga, ${tier1Ids.size} epizoda; Tier 2: ${tier2Ids.length} ID-eva`);

  const tier2 = await pool(tier2Ids, CONCURRENCY, async (id) => {
    const [infoText, summaryText] = await Promise.all([
      getText(`data/${id}/info.json`),
      getText(`data/${id}/summary.json`),
    ]);
    return {
      id,
      info: infoText === null ? null : parseWith(P.parseEpisodeInfo, infoText, `data/${id}/info.json`),
      summary: summaryText === null ? null : parseWith(P.parseEpisodeSummary, summaryText, `data/${id}/summary.json`),
      files: filesById.get(id) ?? new Set(),
    };
  });

  const plan = buildPlan({ index, listings, registry, tier2 });
  const report = {
    ...plan.report,
    keyCache: {
      path: KEY_CACHE_PATH,
      articleIds: articles.length,
      tier1Ids: tier1Ids.size,
      tier2Ids: tier2Ids.length,
      tier1WithoutArticle: [...tier1Ids].filter((id) => !filesById.get(id)?.has("article.json")).length,
    },
    http,
  };

  if (DRY_RUN) {
    printReport(report);
    if (JSON_OUT) await writeFile(JSON_OUT, `${JSON.stringify(report, null, 2)}\n`);
    console.log("\n--dry-run: ništa nije upisano");
    return;
  }

  const { getPlatformProxy } = await import("wrangler");
  const proxy = await getPlatformProxy({ configPath: join(KATALOG, "wrangler.jsonc"), remoteBindings: false });
  const db = proxy.env.DB;
  try {
    const migrated = await db
      .prepare("SELECT count(*) AS n FROM pragma_table_info('episodes') WHERE name = 'variant_of'")
      .first();
    if (migrated?.n !== 1) throw new Error("lokalni D1 nije migriran: prvo `npm run migrate:local`");
    const runId = await W.startRun(db, SOURCE, startedAt);
    try {
      report.written = await W.applyPlan(db, DOMOVINA_BRAND, plan, startedAt);
      await W.finishRun(db, runId, "ok", new Date().toISOString(), report);
    } catch (err) {
      await W.finishRun(db, runId, "failed", new Date().toISOString(), {
        ...report,
        error: err instanceof Error ? err.message : String(err),
      });
      throw err;
    }
    report.ingestRunId = runId;
  } finally {
    await proxy.dispose();
  }
  printReport(report);
  console.log(`  ${"ingest_runs.id".padEnd(34)} ${report.ingestRunId}`);
  if (JSON_OUT) await writeFile(JSON_OUT, `${JSON.stringify(report, null, 2)}\n`);
}

main().catch((err) => {
  console.error(err instanceof Error ? (err.stack ?? err.message) : err);
  process.exit(1);
});

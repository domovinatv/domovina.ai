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
// Dohvat s CDN-a i izgradnja plana su u `scripts/lib/` (dijeli ih `drift-check --sync`).
import { readFile, writeFile } from "node:fs/promises";
import { join } from "node:path";

const SOURCE = "backfill";

const args = process.argv.slice(2);
const DRY_RUN = args.includes("--dry-run");
const jsonIdx = args.indexOf("--json");
const JSON_OUT = jsonIdx >= 0 ? args[jsonIdx + 1] : null;

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
  const { KATALOG, KEY_CACHE_PATH, REGISTRY_PATH } = await import("./lib/paths.ts");
  const { createCdn } = await import("./lib/cdn.ts");
  const { buildImportPlan } = await import("./lib/build-plan.ts");
  const K = await import("../src/ingest/keys.ts");
  const { DOMOVINA_BRAND } = await import("../src/ingest/plan.ts");
  const W = await import("../src/ingest/write.ts");
  const startedAt = new Date().toISOString();

  const filesById = K.parseKeyCache(JSON.parse(await readFile(KEY_CACHE_PATH, "utf8")));
  const { plan, report } = await buildImportPlan({
    filesById,
    keyCachePath: KEY_CACHE_PATH,
    registryText: await readFile(REGISTRY_PATH, "utf8"),
    registryPath: REGISTRY_PATH,
    cdn: createCdn(),
    log: (line) => console.log(line),
  });

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

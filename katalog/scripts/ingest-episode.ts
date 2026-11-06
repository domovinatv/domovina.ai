// Pipeline producer (S7): nakon uploada upiši epizode u katalog.
//
//   npm run ingest-episode -- <id> [<id> ...]      # retci tih epizoda + njihovih kanala
//   npm run ingest-episode -- --all                # cijeli plan (nightly; nepromijenjeni retci = 0 promjena)
//   ... --channels-out <datoteka>                  # mapa epizoda → kanal za episode.json
//   ... --dry-run --base http://localhost:8787 --json report.json
//
// Plan se gradi istim kodom kao `npm run import` i `drift-check --sync`
// (`scripts/lib/build-plan.ts`); zašto puni plan i za jednu epizodu, te exit
// kodovi: `scripts/lib/ingest-episodes.ts`. Poziva ga `run_pipeline.sh` (KORAK
// 13.5) u fetch.domovina.tv; neuspjeh ne ruši pipeline, a `drift-check --sync`
// u 08:45 popravi ono što je propušteno.
//
// CDN se čita u `fresh` načinu: listinzi kanala i 404 retry idu s jedinstvenim
// cache-busterom, jer se poziva sekundama nakon uploada.
//
// Token: env `INGEST_TOKEN`, inače redak `INGEST_TOKEN=` u `katalog/.dev.vars`.
// Vrijednost se nikad ne ispisuje. Node 24+ (type stripping, odluka 118).
import { readFile, rename, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parseArgs } from "node:util";
import { buildImportPlan } from "./lib/build-plan.ts";
import { createCdn } from "./lib/cdn.ts";
import { DEFAULT_BASE, EXIT_UNKNOWN, readKeyCacheText, redact, tokenFromDevVars } from "./lib/drift.ts";
import { formatIngestReport, runIngestEpisodes } from "./lib/ingest-episodes.ts";
import { KATALOG, KEY_CACHE_PATH, REGISTRY_PATH } from "./lib/paths.ts";

const YT_ID = /^[A-Za-z0-9_-]{6,}$/;
/** Pipeline ne smije visjeti na mreži: cijeli poziv ≤ 5 min (izmjereno: puni plan 3,3 s). */
const WATCHDOG_MS = 300_000;

async function resolveToken(): Promise<string | null> {
  const fromEnv = process.env.INGEST_TOKEN;
  if (fromEnv !== undefined && fromEnv !== "") return fromEnv;
  try {
    return tokenFromDevVars(await readFile(join(KATALOG, ".dev.vars"), "utf8"));
  } catch {
    return null;
  }
}

async function readOrNull(path: string): Promise<string | null> {
  try {
    return await readFile(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

async function main(): Promise<number> {
  let parsed;
  try {
    parsed = parseArgs({
      allowPositionals: true,
      options: {
        all: { type: "boolean", default: false },
        "dry-run": { type: "boolean", default: false },
        base: { type: "string", default: DEFAULT_BASE },
        "channels-out": { type: "string" },
        json: { type: "string" },
        verbose: { type: "boolean", default: false },
      },
    });
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    return EXIT_UNKNOWN;
  }
  const args = parsed.values;
  // `a,b c` i `a b` daju isto: pipeline zna predati popis sa zarezima.
  const ids = [...new Set(parsed.positionals.flatMap((p) => p.split(",")).map((s) => s.trim()).filter(Boolean))];
  const bad = ids.filter((id) => !YT_ID.test(id));
  if (bad.length > 0) {
    console.error(`neispravan ID: ${bad.join(", ")}`);
    return EXIT_UNKNOWN;
  }

  const token = await resolveToken();
  const mapPath = args["channels-out"] === undefined ? undefined : resolve(args["channels-out"]);
  const report = await runIngestEpisodes({
    base: args.base,
    token,
    fetch: (input, init) => fetch(input, { ...init, signal: AbortSignal.timeout(60_000) }),
    ids,
    all: args.all,
    dryRun: args["dry-run"],
    buildPlan: async () => {
      const { files } = readKeyCacheText(await readFile(KEY_CACHE_PATH, "utf8"));
      const { plan } = await buildImportPlan({
        filesById: files,
        keyCachePath: KEY_CACHE_PATH,
        registryText: await readFile(REGISTRY_PATH, "utf8"),
        registryPath: REGISTRY_PATH,
        cdn: createCdn({ fresh: true }),
        ...(args.verbose ? { log: (line: string) => { console.log(`  ${line}`); } } : {}),
      });
      return plan;
    },
    ...(mapPath === undefined
      ? {}
      : {
          channelMap: {
            read: () => readOrNull(mapPath),
            // Atomarno: bundle u istom runu ne smije pročitati pola datoteke.
            write: async (text: string) => {
              const tmp = `${mapPath}.tmp-${process.pid}`;
              await writeFile(tmp, text);
              await rename(tmp, mapPath);
            },
          },
        }),
  });

  const out = report.exitCode === EXIT_UNKNOWN ? console.error : console.log;
  for (const l of formatIngestReport(report)) out(l);
  if (args.json !== undefined) {
    try {
      await writeFile(args.json, `${JSON.stringify(report, null, 2)}\n`);
    } catch (err) {
      console.error(`--json ${args.json}: ${err instanceof Error ? err.message : String(err)}`);
      return EXIT_UNKNOWN;
    }
  }
  return report.exitCode;
}

setTimeout(() => {
  console.error(`katalog ingest-episode: prekoračeno ${WATCHDOG_MS / 1000} s, prekidam (exit 2)`);
  process.exit(EXIT_UNKNOWN);
}, WATCHDOG_MS).unref();

main().then(
  (code) => { process.exitCode = code; },
  async (err: unknown) => {
    const msg = err instanceof Error ? (err.stack ?? err.message) : String(err);
    console.error(redact(msg, await resolveToken().catch(() => null)));
    process.exitCode = EXIT_UNKNOWN;
  },
);

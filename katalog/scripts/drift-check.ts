// Tripwire: R2 članci (izvor istine) ↔ katalog u D1 (projekcija).
//
//   npm run drift-check                         # usporedi, ne piše
//   npm run drift-check -- --sync               # na drift pošalji puni plan na ingest, pa ponovno izmjeri
//   npm run drift-check -- --base http://localhost:8787 --json report.json --verbose
//
// R2 = ID-evi s `data/<id>/article.json` u `../../fetch.domovina.tv/.r2_keys_cache.json`
// (`KATALOG_KEY_CACHE_PATH` ga mijenja, isto kao u uvozniku). D1 = `GET
// {base}/api/katalog/v1/ingest/ids` (sve stranice). `--sync` gradi retke ISTIM
// kodom kao `npm run import` (`scripts/lib/build-plan.ts`) i šalje ih na
// `POST /ingest` (kanali prije epizoda, ≤ 200 / ≤ 500 po pozivu).
//
// Token: env `INGEST_TOKEN`, inače redak `INGEST_TOKEN=` u `katalog/.dev.vars`
// (gitignoran). Vrijednost se nikad ne ispisuje.
//
// Exit: 0 poravnato (ili popravljeno i konvergiralo), 1 drift (bez `--sync`),
// 2 ne mogu provjeriti. Pravila i zašto je `extra` samo informativan:
// `scripts/lib/drift.ts`. launchd omotač: `scripts/drift-check-launchd.sh`.
//
// Node 24+ (type stripping, odluka 118).
import { readFile, stat, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { buildImportPlan } from "./lib/build-plan.ts";
import { createCdn } from "./lib/cdn.ts";
import {
  DEFAULT_BASE,
  EXIT_UNKNOWN,
  formatReport,
  redact,
  runDriftCheck,
  tokenFromDevVars,
  type DriftReport,
} from "./lib/drift.ts";
import { KATALOG, KEY_CACHE_PATH, REGISTRY_PATH } from "./lib/paths.ts";

async function resolveToken(): Promise<string | null> {
  const fromEnv = process.env.INGEST_TOKEN;
  if (fromEnv !== undefined && fromEnv !== "") return fromEnv;
  try {
    return tokenFromDevVars(await readFile(join(KATALOG, ".dev.vars"), "utf8"));
  } catch {
    return null;
  }
}

async function main(): Promise<number> {
  let args;
  try {
    args = parseArgs({
      options: {
        sync: { type: "boolean", default: false },
        base: { type: "string", default: DEFAULT_BASE },
        json: { type: "string" },
        verbose: { type: "boolean", default: false },
      },
    }).values;
  } catch (err) {
    console.error(err instanceof Error ? err.message : String(err));
    return EXIT_UNKNOWN;
  }

  const token = await resolveToken();
  const report: DriftReport = await runDriftCheck({
    base: args.base,
    token,
    fetch: (input, init) => fetch(input, init),
    keyCachePath: KEY_CACHE_PATH,
    readKeyCache: () => readFile(KEY_CACHE_PATH, "utf8"),
    sync: args.sync,
    buildPlan: async (files) => {
      const { plan } = await buildImportPlan({
        filesById: files,
        keyCachePath: KEY_CACHE_PATH,
        registryText: await readFile(REGISTRY_PATH, "utf8"),
        registryPath: REGISTRY_PATH,
        cdn: createCdn(),
        ...(args.verbose ? { log: (line: string) => { console.log(`  ${line}`); } } : {}),
      });
      return plan;
    },
  });

  const lines = formatReport(report, args.verbose);
  if (args.verbose) {
    // Cache koji zaostaje skriva missing; starost je kontekst, ne uvjet.
    try {
      const age = (Date.now() - (await stat(KEY_CACHE_PATH)).mtimeMs) / 3_600_000;
      lines.splice(1, 0, `  ${"key cache starost".padEnd(22)} ${age.toFixed(1)} h`);
    } catch {
      /* nema datoteke: greška je već u izvještaju */
    }
  }
  const out = report.exitCode === EXIT_UNKNOWN ? console.error : console.log;
  for (const l of lines) out(l);

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

// Sve što izleti mimo `runDriftCheck` je „ne znam” (2), nikad drift (1).
main().then(
  (code) => { process.exitCode = code; },
  async (err: unknown) => {
    const msg = err instanceof Error ? (err.stack ?? err.message) : String(err);
    console.error(redact(msg, await resolveToken().catch(() => null)));
    process.exitCode = EXIT_UNKNOWN;
  },
);

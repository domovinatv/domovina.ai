// `npm run daily -- [--dry-run] [--days N] [--max-calls N] [--db path] [--notify-file path] [--fake]`
//
// Baza: `VIJESTI_DATABASE_URL` (produkcija kroz SSH tunel, uloga
// `vijesti_engine`, odluka 808) ili lokalni PGlite (`--db`, zadano
// .cache/daily.pglite). Na Postgresu se migracije NE pokreću: shema ide kroz
// paket `db/prod/` uz pristanak, a job odbija raditi nad shemom koja nije na
// zadnjoj migraciji iz repoa.
//
// Limit: `--max-calls` ili `VIJESTI_DAILY_MAX_CALLS` (zadano 150) po danu.
// Model: kao `npm run eval` (`VIJESTI_LLM_BACKEND`, vijesti/.env).
// Izlaz: 0 gotovo, 3 dio čeka sutra (limit), 1 greška. `--notify-file` dobiva
// HTML za `scripts/telegram-notify.rb` (šalje ga scripts/daily.sh).
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { loadMigrations, migrateUp } from '../../db/migrate.js';
import { connectPg } from '../../db/pg.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import type { SqlDb } from '../../db/sql.js';
import { createDiskCache } from '../cdn/cache.js';
import { createCdnClient, type CdnClient } from '../cdn/loader.js';
import { PERSONS_FIXTURE, UsageError, VIJESTI_ROOT } from '../cli.js';
import { createFakeEvalLlm } from '../eval/fake-llm.js';
import type { EvalBackend } from '../eval/run.js';
import { createLlmFromConfig, describeLlmConfig, llmConfigFromEnv, loadDotEnv } from '../llm/config.js';
import type { LlmClient } from '../llm/types.js';
import { buildPersonIndex, loadPersons, parsePersons } from '../score/persons.js';
import { createFakeCdn } from '../test/fake-cdn.js';
import { DEFAULT_DAILY_MAX_CALLS, DEFAULT_DAYS, runDaily, type DailyResult } from './run.js';

export const DEFAULT_DAILY_DB = join(VIJESTI_ROOT, '.cache', 'daily.pglite');
export const ADMIN_URL = 'https://domovina.ai/vijesti/admin';

export interface DailyArgs {
  dryRun: boolean;
  fake: boolean;
  days: number;
  maxCalls: number;
  db: string;
  notifyFile: string | null;
  log: string;
  now: Date;
}

function positiveInt(flag: string, v: string): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n < 1) throw new UsageError(`${flag} traži pozitivan cijeli broj, ne „${v}”`);
  return n;
}

export function parseDailyArgs(argv: string[], env: Record<string, string | undefined>, now = new Date()): DailyArgs {
  const values: Record<string, string> = {};
  const flags = new Set<string>();
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? '';
    if (a === '--dry-run' || a === '--fake') flags.add(a);
    else if (['--days', '--max-calls', '--db', '--notify-file', '--log', '--now'].includes(a)) {
      const v = argv[++i];
      if (v === undefined) throw new UsageError(`${a} traži vrijednost`);
      values[a] = v;
    } else throw new UsageError(`nepoznat argument: ${a}`);
  }
  const db = values['--db'] ?? DEFAULT_DAILY_DB;
  const max = values['--max-calls'] ?? env.VIJESTI_DAILY_MAX_CALLS;
  return {
    dryRun: flags.has('--dry-run'),
    fake: flags.has('--fake'),
    days: values['--days'] ? positiveInt('--days', values['--days']) : DEFAULT_DAYS,
    maxCalls: max ? positiveInt('--max-calls', max) : DEFAULT_DAILY_MAX_CALLS,
    db,
    notifyFile: values['--notify-file'] ?? null,
    log: values['--log'] ?? join(VIJESTI_ROOT, '.cache', 'daily.log'),
    now: values['--now'] ? new Date(`${values['--now']}T12:00:00Z`) : now,
  };
}

/** Postgres mora biti točno na zadnjoj migraciji iz repoa (engine je ne pokreće). */
export async function assertSchemaCurrent(db: SqlDb): Promise<void> {
  const latest = Math.max(...(await loadMigrations()).map((m) => m.version));
  const res = await db.query<{ v: number | string | null }>('SELECT max(version) AS v FROM vijesti.schema_migrations');
  const have = Number(res.rows[0]?.v ?? 0);
  if (have !== latest) {
    throw new Error(`baza je na migraciji ${String(have)}, repo na ${String(latest)}: prvo paket db/prod/ (npm run db:bundle -- --from ${String(have + 1)})`);
  }
}

export async function runDailyCli(
  args: DailyArgs,
  env: Record<string, string | undefined>,
  opts: { llm?: (r: ReturnType<typeof createSqlRunRecorder>) => LlmClient } = {},
): Promise<DailyResult> {
  const cdn: CdnClient = args.fake
    ? createCdnClient({ fetch: createFakeCdn().fetch })
    : createCdnClient({ fetch: (u, i) => fetch(u, i), cache: createDiskCache(join(VIJESTI_ROOT, '.cache', 'cdn')) });
  const personsFile = args.fake
    ? parsePersons(await readFile(PERSONS_FIXTURE, 'utf8'))
    : (await loadPersons({ fetch: (u, i) => fetch(u, i), cache: createDiskCache(join(VIJESTI_ROOT, '.cache')) })).file;
  const persons = buildPersonIndex(personsFile.persons);
  const cfg = args.fake ? null : llmConfigFromEnv(env);
  const backend: EvalBackend = cfg?.backend ?? 'fake';

  const url = env.VIJESTI_DATABASE_URL;
  let db: SqlDb & { close(): Promise<void> };
  if (url && !args.fake) {
    db = await connectPg(url);
    await assertSchemaCurrent(db);
  } else {
    await mkdir(dirname(args.db), { recursive: true });
    const lite = new PGlite(args.db);
    await lite.waitReady;
    await migrateUp(lite);
    db = lite;
  }
  try {
    const recorder = createSqlRunRecorder(db);
    const llm = (): LlmClient => {
      if (opts.llm) return opts.llm(recorder);
      if (!cfg) return createFakeEvalLlm(recorder);
      console.error(`LLM: ${describeLlmConfig(cfg)}`);
      return createLlmFromConfig(cfg, { fetch: (u, i) => fetch(u, i), recorder });
    };
    await mkdir(dirname(args.log), { recursive: true });
    const res = await runDaily(
      { cdn, db, recorder, persons, llm, backend, log: (line) => appendFile(args.log, `${line}\n`, 'utf8') },
      { now: args.now, days: args.days, maxCalls: args.maxCalls, dryRun: args.dryRun, attempts: 2, adminUrl: ADMIN_URL },
    );
    // Tihi dan (ništa novo, ništa ne čeka, bez greške) ne šalje ništa.
    const worth = res.newDrafts.length > 0 || res.queue.length > 0 || res.deferred.length > 0 || res.exitCode !== 0;
    if (args.notifyFile && worth && !args.dryRun) await writeFile(args.notifyFile, res.notify, 'utf8');
    return res;
  } finally {
    await db.close();
  }
}

async function main(argv: string[]): Promise<number> {
  loadDotEnv();
  try {
    const args = parseDailyArgs(argv, process.env);
    const res = await runDailyCli(args, process.env);
    console.log(res.text);
    return res.exitCode;
  } catch (e) {
    if (e instanceof UsageError) {
      console.error(e.message);
      return 2;
    }
    console.error(`dnevni job: ${(e as Error).message}`);
    return 1;
  }
}

if (process.argv[1]?.endsWith('daily/cli.ts')) {
  process.exitCode = await main(process.argv.slice(2));
}

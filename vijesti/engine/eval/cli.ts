// `npm run eval -- [--channels a,b] [--limit N] [--max-calls N] [--fake] [--dry-run]
//                  [--db path] [--log path] [--attempts N] [--resample] [--now YYYY-MM-DD]`
// `npm run eval:report -- [--fake] [--db path] [--out file.md] [--query "SQL"]`
// `npm run eval:drafts -- [--fake] [--db path] [--out file.md]`
//
// Uz izvlačenje i ocjenu eval piše članak i provjeru (odluka 434); nacrti iz
// baze idu u Markdown kroz `eval:drafts` (odluka 435).
//
// Odluke 405–412. Pravo pokretanje (ODGOĐENO, korisnik kaže kad; vidi
// engine/cli.ts i .env.example) ide s `VIJESTI_LLM_BACKEND=agy` i obaveznim
// `--max-calls`. Prvo uvijek `--dry-run`: ispiše procjenu i ne zove model.
//
// --fake      lažni CDN nad engine/test/fixtures, lažni LLM, osobe iz fixturea:
//             bez mreže; zadani kanali = kanali fixturea, zadana baza
//             .cache/eval-fake.pglite (nikad ista kao za pravi uzorak).
// --channels  slugovi kanala (bez --fake obavezno).
// --limit     epizoda po kanalu (zadano 5).
// --max-calls ograda: procjena iznad nje → exit 3 prije ijednog poziva; u radu
//             se poziv preko nje ne šalje (exit 3, nastavak sljedećim pokretanjem).
//             Bez --fake i bez --dry-run obavezno.
// --attempts  neuspjelih runova po koraku prije odustajanja (zadano 2).
// --resample  novi uzorak umjesto spremljenog u bazi.
// --now       kraj prozora dotoka (zadano danas).
// --log       jedan redak po obrađenoj epizodi (zadano <db>.log).
import { appendFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createDiskCache } from '../cdn/cache.js';
import { createCdnClient, type CdnClient, type FetchLike } from '../cdn/loader.js';
import { PERSONS_FIXTURE, UsageError, VIJESTI_ROOT } from '../cli.js';
import { createLlmFromConfig, describeLlmConfig, llmConfigFromEnv, loadDotEnv } from '../llm/config.js';
import type { LlmClient, LlmPricing } from '../llm/types.js';
import { buildPersonIndex, loadPersons, parsePersons } from '../score/persons.js';
import { createFakeCdn, type FakeCdnOptions } from '../test/fake-cdn.js';
import { createFakeEvalLlm } from './fake-llm.js';
import { buildDrafts } from './drafts.js';
import { buildEvalReport, markdownTable, readOnlyQuery } from './report.js';
import { runEval, type EvalBackend, type EvalResult } from './run.js';

export const DEFAULT_EVAL_DB = join(VIJESTI_ROOT, '.cache', 'eval.pglite');
export const DEFAULT_FAKE_EVAL_DB = join(VIJESTI_ROOT, '.cache', 'eval-fake.pglite');

/** Kanali čiji listinzi postoje u fixtureima. */
export const FIXTURE_CHANNELS = ['catholic_futurist', 'domovina_tv', 'iva_kraljevic', 'mreze_rijeci'];

export const EVAL_USAGE = [
  'upotreba: npm run eval -- [--channels a,b] [--limit N] [--max-calls N] [--fake] [--dry-run]',
  '                          [--db path] [--log path] [--attempts N] [--resample] [--now YYYY-MM-DD]',
  '          npm run eval:report -- [--fake] [--db path] [--out file.md] [--query "SQL"]',
  '          npm run eval:drafts -- [--fake] [--db path] [--out file.md]',
].join('\n');

export interface EvalArgs {
  channels: string[];
  limit: number;
  maxCalls: number | null;
  fake: boolean;
  dryRun: boolean;
  db: string;
  log: string;
  attempts: number;
  resample: boolean;
  now: Date;
}

export interface ReportArgs {
  db: string;
  out: string | null;
  query: string | null;
}

function positiveInt(flag: string, v: string): number {
  const n = Number(v);
  if (!Number.isInteger(n) || n < 1) throw new UsageError(`${flag} traži pozitivan cijeli broj: ${v}`);
  return n;
}

function scan(argv: string[], flags: readonly string[], valued: readonly string[]) {
  const set = new Set<string>();
  const values: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i] ?? '';
    if (flags.includes(a)) set.add(a);
    else if (valued.includes(a)) {
      const v = argv[++i];
      if (v === undefined || v.startsWith('--')) throw new UsageError(`${a} traži vrijednost`);
      values[a] = v;
    } else throw new UsageError(a.startsWith('--') ? `nepoznata opcija ${a}\n${EVAL_USAGE}` : `višak argumenta ${a}`);
  }
  return { set, values };
}

export function parseEvalArgs(argv: string[], today: Date = new Date()): EvalArgs {
  const { set, values } = scan(
    argv,
    ['--fake', '--dry-run', '--resample'],
    ['--channels', '--limit', '--max-calls', '--db', '--log', '--attempts', '--now'],
  );
  const fake = set.has('--fake');
  const dryRun = set.has('--dry-run');
  const channels = (values['--channels'] ?? '').split(',').map((s) => s.trim()).filter(Boolean);
  if (channels.length === 0) {
    if (!fake) throw new UsageError('--channels je obavezan bez --fake (npr. --channels domovina_tv,mreze_rijeci)');
    channels.push(...FIXTURE_CHANNELS);
  }
  const maxRaw = values['--max-calls'];
  const maxCalls = maxRaw === undefined ? null : positiveInt('--max-calls', maxRaw);
  if (maxCalls === null && !fake && !dryRun) {
    throw new UsageError('--max-calls je obavezan za pravi prolaz (prvo --dry-run za procjenu)');
  }
  const nowRaw = values['--now'];
  let now = today;
  if (nowRaw !== undefined) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(nowRaw)) throw new UsageError(`--now traži YYYY-MM-DD: ${nowRaw}`);
    now = new Date(`${nowRaw}T12:00:00Z`);
  }
  const db = values['--db'] ?? (fake ? DEFAULT_FAKE_EVAL_DB : DEFAULT_EVAL_DB);
  return {
    channels,
    limit: values['--limit'] === undefined ? 5 : positiveInt('--limit', values['--limit']),
    maxCalls,
    fake,
    dryRun,
    db,
    log: values['--log'] ?? `${db}.log`,
    attempts: values['--attempts'] === undefined ? 2 : positiveInt('--attempts', values['--attempts']),
    resample: set.has('--resample'),
    now,
  };
}

export type DraftsArgs = Omit<ReportArgs, 'query'>;

export function parseDraftsArgs(argv: string[]): DraftsArgs {
  const [first, ...rest] = argv;
  if (first !== 'drafts') throw new UsageError(EVAL_USAGE);
  const { set, values } = scan(rest, ['--fake'], ['--db', '--out']);
  return {
    db: values['--db'] ?? (set.has('--fake') ? DEFAULT_FAKE_EVAL_DB : DEFAULT_EVAL_DB),
    out: values['--out'] ?? null,
  };
}

export function parseReportArgs(argv: string[]): ReportArgs {
  const [first, ...rest] = argv;
  if (first !== 'report') throw new UsageError(EVAL_USAGE);
  const { set, values } = scan(rest, ['--fake'], ['--db', '--out', '--query']);
  return {
    db: values['--db'] ?? (set.has('--fake') ? DEFAULT_FAKE_EVAL_DB : DEFAULT_EVAL_DB),
    out: values['--out'] ?? null,
    query: values['--query'] ?? null,
  };
}

async function withDb<T>(path: string, fn: (db: PGlite) => Promise<T>): Promise<T> {
  await mkdir(dirname(path), { recursive: true });
  const db = new PGlite(path);
  try {
    await db.waitReady;
    await migrateUp(db);
    return await fn(db);
  } finally {
    await db.close();
  }
}

export interface EvalCliEnv {
  /** Pravi fetch za CDN i osobe (testovi ga ne daju). */
  fetch?: FetchLike;
  /** Lažni CDN s izmjenama (testovi). */
  fakeCdn?: FakeCdnOptions;
  /** Zamjenski LLM (testovi); zadano lažni uz --fake, inače iz vijesti/.env. */
  llm?: (recorder: ReturnType<typeof createSqlRunRecorder>) => LlmClient;
  env?: Record<string, string | undefined>;
}

export async function runEvalCli(args: EvalArgs, env: EvalCliEnv = {}): Promise<EvalResult> {
  const realFetch: FetchLike = env.fetch ?? ((url, init) => fetch(url, init));
  const cdn: CdnClient = args.fake
    ? createCdnClient({ fetch: createFakeCdn(env.fakeCdn).fetch })
    : createCdnClient({ fetch: realFetch, cache: createDiskCache(join(VIJESTI_ROOT, '.cache', 'cdn')) });
  const personsFile = args.fake
    ? parsePersons(await readFile(PERSONS_FIXTURE, 'utf8'))
    : (await loadPersons({ fetch: realFetch, cache: createDiskCache(join(VIJESTI_ROOT, '.cache')) })).file;
  const persons = buildPersonIndex(personsFile.persons);

  let backend: EvalBackend = 'fake';
  let pricing: LlmPricing | null = { inPerMTok: 0, outPerMTok: 0 };
  let cfg: ReturnType<typeof llmConfigFromEnv> | null = null;
  if (!args.fake) {
    if (!env.env) loadDotEnv();
    cfg = llmConfigFromEnv(env.env ?? process.env);
    backend = cfg.backend;
    pricing = cfg.pricing;
  }
  const realCfg = cfg;
  return withDb(args.db, async (db) => {
    const recorder = createSqlRunRecorder(db);
    const llm = (): LlmClient => {
      if (env.llm) return env.llm(recorder);
      if (args.fake || !realCfg) return createFakeEvalLlm(recorder);
      console.error(`LLM: ${describeLlmConfig(realCfg)}`);
      return createLlmFromConfig(realCfg, { fetch: (url, init) => fetch(url, init), recorder });
    };
    if (!args.dryRun) await mkdir(dirname(args.log), { recursive: true });
    return runEval(
      {
        cdn,
        db,
        recorder,
        persons,
        llm,
        backend,
        pricing,
        log: (line) => appendFile(args.log, `${line}\n`, 'utf8'),
      },
      {
        channels: args.channels,
        limit: args.limit,
        maxCalls: args.maxCalls,
        dryRun: args.dryRun,
        attempts: args.attempts,
        resample: args.resample,
        now: args.now,
      },
    );
  });
}

export async function runReportCli(args: ReportArgs, generatedAt?: Date): Promise<string> {
  return withDb(args.db, async (db) => {
    if (args.query !== null) return markdownTable(await readOnlyQuery(db, args.query));
    const md = await buildEvalReport(db, { dbPath: args.db, ...(generatedAt && { generatedAt }) });
    if (args.out) await writeFile(args.out, md, 'utf8');
    return md;
  });
}

export async function runDraftsCli(args: DraftsArgs, generatedAt?: Date): Promise<string> {
  return withDb(args.db, async (db) => {
    const md = await buildDrafts(db, { dbPath: args.db, ...(generatedAt && { generatedAt }) });
    if (args.out) await writeFile(args.out, md, 'utf8');
    return md;
  });
}

async function main(argv: string[]): Promise<number> {
  try {
    if (argv[0] === 'drafts') {
      const args = parseDraftsArgs(argv);
      const md = await runDraftsCli(args, new Date());
      console.log(args.out ? `nacrti: ${args.out}` : md);
      return 0;
    }
    if (argv[0] === 'report') {
      const args = parseReportArgs(argv);
      const md = await runReportCli(args, new Date());
      console.log(args.out ? `izvještaj: ${args.out}` : md);
      return 0;
    }
    const args = parseEvalArgs(argv);
    const res = await runEvalCli(args);
    console.log(res.text);
    if (!args.dryRun && res.exitCode === 0) {
      console.log(
        `log: ${args.log}\nizvještaj: npm run eval:report -- --db '${args.db}'\nnacrti: npm run eval:drafts -- --db '${args.db}' --out <file.md>`,
      );
    }
    return res.exitCode;
  } catch (e) {
    console.error(e instanceof UsageError ? e.message : `greška: ${(e as Error).message}`);
    return e instanceof UsageError ? 2 : 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = await main(process.argv.slice(2));
}


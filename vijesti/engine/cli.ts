// `npm run vijesti -- extract <videoId> [--fake] [--lang xx] [--db path]`
// `npm run vijesti -- score <videoId> [--fake] [--channel slug] [--db path]`
//
// --fake     lažni LLM (odluke 209, 313); za ID iz fixturea i lažni CDN nad
//            engine/test/fixtures (bez mreže), inače pravi CDN, samo čitanje.
//            `score --fake` čita osobe iz fixturea (bez mreže).
// --lang     jezik snimke (odluka 200), inače iz episode.json / zadano hr.
// --channel  slug kanala (inače se traži po listinzima, odluka 112).
// --db       PGlite direktorij, zadano vijesti/.cache/vijesti.pglite.
// Bez --fake ide pravi Gemini (Vertex ili AI Studio, vijesti/.env) i troši kvotu.
import { mkdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { migrateUp } from '../db/migrate.js';
import { createSqlRunRecorder } from '../db/runs.js';
import { createDiskCache } from './cdn/cache.js';
import { createCdnClient, type FetchLike } from './cdn/loader.js';
import { createFakeExtractLlm } from './extract/fake-llm.js';
import { formatReport, runExtract, type ExtractReport } from './extract/run.js';
import { createLlmFromConfig, describeLlmConfig, llmConfigFromEnv, loadDotEnv } from './llm/config.js';
import type { RunRecorder } from './llm/runs.js';
import type { LlmClient } from './llm/types.js';
import { createFakeScoreLlm } from './score/fake-llm.js';
import { buildPersonIndex, loadPersons, parsePersons } from './score/persons.js';
import { formatScoreReport, runScore, type ScoreReport } from './score/run.js';
import { createFakeCdn } from './test/fake-cdn.js';
import { FIXTURES, FIXTURES_DIR } from './test/fixtures-refresh.js';

export const VIJESTI_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
export const DEFAULT_DB_DIR = join(VIJESTI_ROOT, '.cache', 'vijesti.pglite');

export interface ExtractArgs {
  videoId: string;
  fake: boolean;
  lang?: string;
  db: string;
}

export class UsageError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'UsageError';
  }
}

export const USAGE = [
  'upotreba: vijesti extract <videoId> [--fake] [--lang xx] [--db path]',
  '          vijesti score <videoId> [--fake] [--channel slug] [--db path]',
].join('\n');

export interface ScoreArgs {
  videoId: string;
  fake: boolean;
  channel?: string;
  db: string;
}

function parseCommon(
  argv: string[],
  cmd: string,
  valued: readonly string[],
): { videoId: string; fake: boolean; db: string; values: Record<string, string> } {
  const [first, ...rest] = argv;
  if (first !== cmd) throw new UsageError(USAGE);
  let videoId: string | undefined;
  let fake = false;
  let db = DEFAULT_DB_DIR;
  const values: Record<string, string> = {};
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i] ?? '';
    if (a === '--fake') fake = true;
    else if (a === '--db' || valued.includes(a)) {
      const v = rest[++i];
      if (v === undefined || v.startsWith('--')) throw new UsageError(`${a} traži vrijednost`);
      if (a === '--db') db = v;
      else values[a.slice(2)] = v;
    } else if (a.startsWith('--')) throw new UsageError(`nepoznata opcija ${a}`);
    else if (videoId === undefined) videoId = a;
    else throw new UsageError(`višak argumenta ${a}`);
  }
  if (!videoId) throw new UsageError(USAGE);
  return { videoId, fake, db, values };
}

export function parseExtractArgs(argv: string[]): ExtractArgs {
  const { videoId, fake, db, values } = parseCommon(argv, 'extract', ['--lang']);
  return { videoId, fake, db, ...(values.lang !== undefined && { lang: values.lang }) };
}

export function parseScoreArgs(argv: string[]): ScoreArgs {
  const { videoId, fake, db, values } = parseCommon(argv, 'score', ['--channel']);
  return { videoId, fake, db, ...(values.channel !== undefined && { channel: values.channel }) };
}

export interface CliEnv {
  /** Pravi fetch za CDN i Gemini (testovi ga ne daju). */
  fetch?: FetchLike;
}

function cliCdn(args: { videoId: string; fake: boolean }, env: CliEnv) {
  const isFixture = FIXTURES.some((f) => f.id === args.videoId);
  const realFetch: FetchLike = env.fetch ?? ((url, init) => fetch(url, init));
  return args.fake && isFixture
    ? createCdnClient({ fetch: createFakeCdn().fetch })
    : createCdnClient({
        fetch: realFetch,
        cache: createDiskCache(join(VIJESTI_ROOT, '.cache', 'cdn')),
      });
}

/** Pravi Gemini iz vijesti/.env (Vertex ili AI Studio, odluka 300). */
function realLlm(recorder: RunRecorder): LlmClient {
  loadDotEnv();
  const cfg = llmConfigFromEnv();
  console.error(`LLM: ${describeLlmConfig(cfg)}`);
  return createLlmFromConfig(cfg, { fetch: (url, init) => fetch(url, init), recorder });
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

export async function runExtractCli(args: ExtractArgs, env: CliEnv = {}): Promise<ExtractReport> {
  const cdn = cliCdn(args, env);
  return withDb(args.db, async (db) => {
    const recorder = createSqlRunRecorder(db);
    const llm = args.fake ? createFakeExtractLlm(recorder) : realLlm(recorder);
    return runExtract({ cdn, llm, recorder, db }, { videoId: args.videoId, lang: args.lang });
  });
}

export const PERSONS_FIXTURE = join(FIXTURES_DIR, 'persons.json');

export async function runScoreCli(args: ScoreArgs, env: CliEnv = {}): Promise<ScoreReport> {
  const cdn = cliCdn(args, env);
  const personsFile = args.fake
    ? parsePersons(await readFile(PERSONS_FIXTURE, 'utf8'))
    : (
        await loadPersons({
          fetch: env.fetch ?? ((url, init) => fetch(url, init)),
          cache: createDiskCache(join(VIJESTI_ROOT, '.cache')),
        })
      ).file;
  const persons = buildPersonIndex(personsFile.persons);
  return withDb(args.db, async (db) => {
    const recorder = createSqlRunRecorder(db);
    const llm = args.fake ? createFakeScoreLlm(recorder) : realLlm(recorder);
    return runScore({ cdn, llm, recorder, db, persons }, { videoId: args.videoId, channel: args.channel });
  });
}

async function main(argv: string[]): Promise<number> {
  try {
    if (argv[0] === 'score') {
      console.log(formatScoreReport(await runScoreCli(parseScoreArgs(argv))));
    } else {
      console.log(formatReport(await runExtractCli(parseExtractArgs(argv))));
    }
    return 0;
  } catch (e) {
    console.error(e instanceof UsageError ? e.message : `greška: ${(e as Error).message}`);
    return e instanceof UsageError ? 2 : 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = await main(process.argv.slice(2));
}

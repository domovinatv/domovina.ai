// `npm run vijesti -- extract <videoId> [--fake] [--lang xx] [--db path]`
//
// --fake  lažni LLM (odluka 209); za ID iz fixturea i lažni CDN nad
//         engine/test/fixtures (bez mreže), inače pravi CDN, samo čitanje.
// --lang  jezik snimke (odluka 200), inače iz episode.json / zadano hr.
// --db    PGlite direktorij, zadano vijesti/.cache/vijesti.pglite.
// Bez --fake ide pravi Gemini (vijesti/.env) i troši kvotu.
import { mkdir } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';
import { migrateUp } from '../db/migrate.js';
import { createSqlRunRecorder } from '../db/runs.js';
import { createDiskCache } from './cdn/cache.js';
import { createCdnClient, type FetchLike } from './cdn/loader.js';
import { createFakeExtractLlm } from './extract/fake-llm.js';
import { formatReport, runExtract, type ExtractReport } from './extract/run.js';
import { createGeminiClient } from './llm/gemini.js';
import { llmConfigFromEnv, loadDotEnv } from './llm/config.js';
import type { LlmClient } from './llm/types.js';
import { createFakeCdn } from './test/fake-cdn.js';
import { FIXTURES } from './test/fixtures-refresh.js';

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

export const USAGE = 'upotreba: vijesti extract <videoId> [--fake] [--lang xx] [--db path]';

export function parseExtractArgs(argv: string[]): ExtractArgs {
  const [cmd, ...rest] = argv;
  if (cmd !== 'extract') throw new UsageError(USAGE);
  let videoId: string | undefined;
  let fake = false;
  let lang: string | undefined;
  let db = DEFAULT_DB_DIR;
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i] ?? '';
    if (a === '--fake') fake = true;
    else if (a === '--lang' || a === '--db') {
      const v = rest[++i];
      if (v === undefined || v.startsWith('--')) throw new UsageError(`${a} traži vrijednost`);
      if (a === '--lang') lang = v;
      else db = v;
    } else if (a.startsWith('--')) throw new UsageError(`nepoznata opcija ${a}`);
    else if (videoId === undefined) videoId = a;
    else throw new UsageError(`višak argumenta ${a}`);
  }
  if (!videoId) throw new UsageError(USAGE);
  return { videoId, fake, db, ...(lang !== undefined && { lang }) };
}

export interface CliEnv {
  /** Pravi fetch za CDN i Gemini (testovi ga ne daju). */
  fetch?: FetchLike;
}

export async function runExtractCli(args: ExtractArgs, env: CliEnv = {}): Promise<ExtractReport> {
  const isFixture = FIXTURES.some((f) => f.id === args.videoId);
  const realFetch: FetchLike = env.fetch ?? ((url, init) => fetch(url, init));
  const cdn =
    args.fake && isFixture
      ? createCdnClient({ fetch: createFakeCdn().fetch })
      : createCdnClient({
          fetch: realFetch,
          cache: createDiskCache(join(VIJESTI_ROOT, '.cache', 'cdn')),
        });
  await mkdir(dirname(args.db), { recursive: true });
  const db = new PGlite(args.db);
  try {
    await db.waitReady;
    await migrateUp(db);
    const recorder = createSqlRunRecorder(db);
    let llm: LlmClient;
    if (args.fake) {
      llm = createFakeExtractLlm(recorder);
    } else {
      loadDotEnv();
      const cfg = llmConfigFromEnv();
      llm = createGeminiClient({
        fetch: (url, init) => fetch(url, init),
        apiKey: cfg.apiKey,
        model: cfg.model,
        pricing: cfg.pricing,
        recorder,
      });
    }
    return await runExtract({ cdn, llm, recorder, db }, { videoId: args.videoId, lang: args.lang });
  } finally {
    await db.close();
  }
}

async function main(argv: string[]): Promise<number> {
  try {
    const args = parseExtractArgs(argv);
    const report = await runExtractCli(args);
    console.log(formatReport(report));
    return 0;
  } catch (e) {
    console.error(e instanceof UsageError ? e.message : `greška: ${(e as Error).message}`);
    return e instanceof UsageError ? 2 : 1;
  }
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = await main(process.argv.slice(2));
}

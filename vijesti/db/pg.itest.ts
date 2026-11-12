// Adapter `db/pg.ts` nad pravim Postgresom (`npm run test:pg`, odluka 808):
// privremeni klaster iz `initdb`, migracije kao vlasnik, pa cijeli tok enginea
// kao `vijesti_engine` kroz adapter. Ovo je ono što dnevni job radi nad
// produkcijom, samo s lažnim modelom i fixtureom.
import { execFileSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PERSONS_FIXTURE } from '../engine/cli.js';
import { stepStates } from '../engine/eval/run.js';
import { createFakeExtractLlm } from '../engine/extract/fake-llm.js';
import { runExtract } from '../engine/extract/run.js';
import { createFakeScoreLlm } from '../engine/score/fake-llm.js';
import { buildPersonIndex, parsePersons } from '../engine/score/persons.js';
import { runScore } from '../engine/score/run.js';
import { fixtureCdn } from '../engine/test/scored-db.js';
import { runVerify } from '../engine/verify/article.js';
import { createFakeVerifyLlm } from '../engine/verify/article-fake-llm.js';
import { createFakeWriteLlm } from '../engine/write/fake-llm.js';
import { loadLatestVersion } from '../engine/write/store.js';
import { runWrite } from '../engine/write/vijest.js';
import { migrateUp } from './migrate.js';
import { connectPg, type PgDb } from './pg.js';
import { createSqlRunRecorder } from './runs.js';

const VIDEO = 'MGLq9v3AtvE';
const CHANNEL = 'domovina_tv';
// `initdb` iz Homebrewova `libpq` nema server pokraj sebe; uzmi pravi Postgres.
const BREW_PG = '/opt/homebrew/opt/postgresql@17/bin';
const PG_BIN = process.env.VIJESTI_PG_BIN ?? (existsSync(join(BREW_PG, 'postgres')) ? BREW_PG : '');
const bin = (name: string) => (PG_BIN ? join(PG_BIN, name) : name);
const dir = mkdtempSync(join(tmpdir(), 'vijesti-pg-'));
const port = 54000 + Math.floor(Math.random() * 900);
const url = (user: string) => `postgres://${user}:x@localhost:${String(port)}/postgres?host=${encodeURIComponent(dir)}`;

beforeAll(() => {
  execFileSync(bin('initdb'), ['-D', join(dir, 'data'), '-U', 'postgres', '--auth=trust', '-E', 'UTF8', '--locale=C'], {
    stdio: 'ignore',
  });
  execFileSync(
    bin('pg_ctl'),
    ['-D', join(dir, 'data'), '-l', join(dir, 'log'), '-w', '-o', `-p ${String(port)} -k ${dir} -c listen_addresses=''`, 'start'],
    { stdio: 'ignore' },
  );
});

afterAll(() => {
  try {
    execFileSync(bin('pg_ctl'), ['-D', join(dir, 'data'), '-m', 'immediate', 'stop'], { stdio: 'ignore' });
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

describe('engine kroz pg adapter kao vijesti_engine', () => {
  let owner: PgDb;
  let engine: PgDb;
  afterAll(async () => {
    await engine.close();
    await owner.close();
  });

  it('migracije, pa izvlačenje → provjera bez vlasničkih prava', async () => {
    owner = await connectPg(url('postgres'));
    expect(await migrateUp(owner)).toEqual([1, 2, 3, 4, 5, 6, 7]);
    await owner.exec('ALTER ROLE vijesti_engine LOGIN');
    engine = await connectPg(url('vijesti_engine'));

    const recorder = createSqlRunRecorder(engine);
    const persons = buildPersonIndex(parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons);
    const deps = { cdn: fixtureCdn(), recorder, db: engine };
    await runExtract({ ...deps, llm: createFakeExtractLlm(recorder) }, { videoId: VIDEO });
    await runScore({ ...deps, llm: createFakeScoreLlm(recorder), persons }, { videoId: VIDEO, channel: CHANNEL });
    const w = await runWrite({ ...deps, llm: createFakeWriteLlm(recorder) }, { videoId: VIDEO, channel: CHANNEL });
    if (!w.saved) throw new Error('članak nije spremljen');
    await runVerify({ ...deps, llm: createFakeVerifyLlm(recorder) }, { articleId: w.saved.articleId });

    const v = await loadLatestVersion(engine, w.saved.articleId);
    expect(typeof v?.versionId).toBe('number');
    expect(v?.verify).not.toBeNull();
    expect(await stepStates(engine, VIDEO, 2)).toEqual({ extract: 'done', score: 'done', write: 'done', verify: 'done' });
    const q = await engine.query('SELECT article_id FROM vijesti.versions_awaiting_verify');
    expect(q.rows).toEqual([]);
    // Isti broj redaka kao kad sve radi vlasnik: RLS engineu ništa ne skriva.
    const asOwner = await owner.query<{ n: number }>('SELECT count(*) AS n FROM vijesti.moments');
    const asEngine = await engine.query<{ n: number }>('SELECT count(*) AS n FROM vijesti.moments');
    expect(asEngine.rows[0]?.n).toBe(asOwner.rows[0]?.n);
    expect(asEngine.rows[0]?.n).toBeGreaterThan(0);
  });
});

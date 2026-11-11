// Lokalni podaci portala (S6): migracije, trenuci iz fixturea kroz lažne
// LLM-ove (isti `--fake` putevi kao `npm run vijesti`), i pet članaka u
// različitim stanjima, sve kroz urednički tok (`asUser` + rpc funkcije), ne
// izravnim upisom stanja. Bez mreže: CDN je lažni CDN nad engine/test/fixtures.
import { cpSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import {
  allowChannel,
  approveArticle,
  asUser,
  correctArticle,
  publishArticle,
  resolveSentence,
  retractArticle,
  saveEditorVersion,
  transitionArticle,
  type EditorBlock,
} from '../../db/editorial.js';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createCdnClient } from '../../engine/cdn/loader.js';
import { PERSONS_FIXTURE } from '../../engine/cli.js';
import { createFakeExtractLlm } from '../../engine/extract/fake-llm.js';
import { runExtract } from '../../engine/extract/run.js';
import { createFakeScoreLlm } from '../../engine/score/fake-llm.js';
import { buildPersonIndex, parsePersons } from '../../engine/score/persons.js';
import { runScore } from '../../engine/score/run.js';
import { createFakeCdn } from '../../engine/test/fake-cdn.js';
import { runVerify } from '../../engine/verify/article.js';
import { createFakeVerifyLlm } from '../../engine/verify/article-fake-llm.js';
import { createFakeWriteLlm } from '../../engine/write/fake-llm.js';
import { loadLatestVersion, type StoredVersion } from '../../engine/write/store.js';
import type { RelatedItem } from '../../engine/rag/related.js';
import { runWrite } from '../../engine/write/vijest.js';
import { LOCAL_ADMIN_ID, LOCAL_EDITOR_ID } from './ids.js';

/** Stanje koje seed postavlja svakoj epizodi fixturea. */
export const SEED_PLAN = [
  { videoId: 'MGLq9v3AtvE', channel: 'domovina_tv', state: 'published' },
  { videoId: 'pIx_7N-6HJ4', channel: 'mreze_rijeci', state: 'corrected' },
  { videoId: 'P9sLks-f2mQ', channel: 'iva_kraljevic', state: 'retracted' },
  { videoId: 'b-nls1ck8EE', channel: 'domovina_tv', state: 'review' },
  { videoId: 'x3w2BVZJ9vQ', channel: 'catholic_futurist', state: 'approved' },
] as const;
/** RAG veze objavljenog članka iz seeda (`content.related`). */
export const SEED_RELATED: RelatedItem[] = [
  {
    videoId: 'pIx_7N-6HJ4',
    t: 754,
    channel: 'mreze_rijeci',
    episodeTitle: 'Mreže riječi: obitelj i zajednica',
    topic: 'Obitelj kao temelj zajednice',
    date: '2026-08-14',
    score: 0.71,
  },
  {
    videoId: 'x3w2BVZJ9vQ',
    t: 0,
    channel: 'catholic_futurist',
    episodeTitle: 'Catholic Futurist: tehnologija i vjera',
    topic: '',
    date: null,
    score: 0.64,
  },
];

export type SeedState = (typeof SEED_PLAN)[number]['state'];

export const SEED_RETRACTION_REASON =
  'Članak je povučen jer pripisuje izjavu pogrešnoj osobi. Ispričavamo se govorniku i čitateljima.';
export const SEED_CORRECTION_DESCRIPTION = 'Ispravljen je opis teme u uvodu: govornik nije govorio o politici.';
/** Rečenica bez potpore u snimci: članak u pregledu ima neriješenu rečenicu. */
export const SEED_FABRICATED = 'Vlada je najavila povećanje mirovina za umirovljenike od siječnja.';

export interface SeededArticle {
  videoId: string;
  channel: string;
  state: SeedState;
  articleId: number;
  slug: string;
  /** Zadnja verzija nakon seeda. */
  versionId: number;
  title: string;
}

interface Verify {
  sentences: { n: number; status: string }[];
}
const unsupported = (verify: unknown): number[] =>
  ((verify as Verify | null)?.sentences ?? []).filter((s) => s.status !== 'supported').map((s) => s.n);

const editorBlocks = (v: StoredVersion): EditorBlock[] =>
  (v.content?.blocks ?? []).flatMap((b): EditorBlock[] =>
    b.type === 'p' ? [{ type: 'p', text: b.text }] : b.moment_id === null ? [] : [{ type: 'quote', moment_id: b.moment_id }],
  );

/**
 * Automatska provjera zadnje verzije članka (lažni verify LLM), kao što bi je
 * napravio engine (`npm run vijesti -- verify`). Shim je nudi kao
 * `POST /__shim/verify?article=<id>` da e2e može nastaviti tok nakon uređivanja.
 */
export async function verifyArticle(db: PGlite, articleId: number): Promise<void> {
  const recorder = createSqlRunRecorder(db);
  await runVerify({ llm: createFakeVerifyLlm(recorder), recorder, db }, { articleId });
}

/** Napuni bazu (već migriranu ili praznu) lokalnim podacima; vraća članke. */
export async function seed(db: PGlite): Promise<SeededArticle[]> {
  await migrateUp(db);
  const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
  const persons = buildPersonIndex(parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons);
  const recorder = createSqlRunRecorder(db);
  await db.query(`INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor'), ($2, 'admin')`, [
    LOCAL_EDITOR_ID,
    LOCAL_ADMIN_ID,
  ]);
  const ed = <T>(fn: Parameters<typeof asUser<T>>[2]) => asUser(db, LOCAL_EDITOR_ID, fn);
  const latest = async (articleId: number) => {
    const v = await loadLatestVersion(db, articleId);
    if (!v) throw new Error(`članak ${String(articleId)} bez verzije`);
    return v;
  };
  const verify = (articleId: number) => verifyArticle(db, articleId);
  const resolveAll = async (v: StoredVersion) => {
    for (const n of unsupported(v.verify)) {
      await ed((d) => resolveSentence(d, v.versionId, n, 'verified', 'Provjereno na snimci (lokalni seed).'));
    }
  };

  const out: SeededArticle[] = [];
  for (const p of SEED_PLAN) {
    await runExtract({ cdn, llm: createFakeExtractLlm(recorder), recorder, db }, { videoId: p.videoId });
    await runScore(
      { cdn, llm: createFakeScoreLlm(recorder), recorder, db, persons },
      { videoId: p.videoId, channel: p.channel },
    );
    const w = await runWrite(
      {
        cdn,
        llm: createFakeWriteLlm(recorder),
        recorder,
        db,
        // Blok „O istoj temi u drugim podcastima” (odluka 803) bez mreže, samo
        // na objavljenom članku: e2e provjerava i prikaz i izostanak.
        ...(p.state === 'published' && { related: () => Promise.resolve(SEED_RELATED) }),
      },
      { videoId: p.videoId, channel: p.channel },
    );
    if (!w.saved) throw new Error(`seed: epizoda ${p.videoId} nema trenutak iznad praga`);
    const articleId = w.saved.articleId;
    await verify(articleId);
    let v = await latest(articleId);
    const channel = v.content?.episode.channel ?? p.channel;
    await asUser(db, LOCAL_ADMIN_ID, (d) => allowChannel(d, channel, 'lokalni seed'));

    await ed((d) => transitionArticle(d, articleId, 'review'));
    if (p.state === 'review') {
      // Urednik doda rečenicu bez potpore; provjera je označi i čeka razrješenje.
      await ed((d) =>
        saveEditorVersion(d, {
          articleId,
          baseVersionId: v.versionId,
          title: v.title,
          lead: v.lead ?? '',
          category: v.category ?? 'drustvo',
          blocks: [...editorBlocks(v), { type: 'p', text: SEED_FABRICATED }],
        }),
      );
      await verify(articleId);
      v = await latest(articleId);
    } else {
      await resolveAll(v);
      await ed((d) => approveArticle(d, articleId, v.versionId, 'Lokalni seed.'));
    }
    if (p.state === 'published' || p.state === 'corrected' || p.state === 'retracted') {
      await ed((d) => publishArticle(d, articleId));
    }
    if (p.state === 'corrected') {
      await ed((d) =>
        saveEditorVersion(d, {
          articleId,
          baseVersionId: v.versionId,
          title: v.title,
          lead: (v.lead ?? '').replace(/\.$/, ', kako je rekao u razgovoru.'),
          category: v.category ?? 'drustvo',
          blocks: editorBlocks(v),
        }),
      );
      await verify(articleId);
      v = await latest(articleId);
      await resolveAll(v);
      await ed((d) => correctArticle(d, articleId, v.versionId, 'fact', SEED_CORRECTION_DESCRIPTION));
    }
    if (p.state === 'retracted') {
      await ed((d) => retractArticle(d, articleId, SEED_RETRACTION_REASON));
    }
    const slug = (await db.query<{ slug: string }>('SELECT slug FROM vijesti.articles WHERE id = $1', [articleId]))
      .rows[0]?.slug;
    out.push({ ...p, channel, articleId, slug: slug ?? '', versionId: v.versionId, title: v.title });
  }
  return out;
}

/**
 * Postojeća lokalna baza (npr. `.cache/proba-claude.pglite`) umjesto seeda, za
 * pregled pravog nacrta u adminu. Čita se KOPIJA (`VIJESTI_DEV_DB` →
 * privremeni direktorij), pa radnje u adminu ne diraju izvornik. Lokalni
 * urednik i administrator se dodaju ako ih nema.
 */
async function existingDb(path: string): Promise<{ db: PGlite; articles: SeededArticle[] }> {
  const copy = join(mkdtempSync(join(tmpdir(), 'vijesti-dev-db-')), 'db');
  cpSync(path, copy, { recursive: true });
  const db = new PGlite(copy);
  await db.waitReady;
  await db.query(
    `INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor'), ($2, 'admin') ON CONFLICT (user_id) DO NOTHING`,
    [LOCAL_EDITOR_ID, LOCAL_ADMIN_ID],
  );
  const rows = (
    await db.query<{ id: number; slug: string; status: string }>('SELECT id, slug, status FROM vijesti.articles ORDER BY id')
  ).rows;
  console.log(`[shim] VIJESTI_DEV_DB=${path} (kopija ${copy})`);
  for (const r of rows) console.log(`[shim] #${String(r.id)} ${r.status} /vijesti/admin?clanak=${String(r.id)}`);
  return { db, articles: [] };
}

/** Nova baza u memoriji s lokalnim podacima (ili kopija `VIJESTI_DEV_DB`). */
export async function seededDb(): Promise<{ db: PGlite; articles: SeededArticle[] }> {
  const existing = process.env.VIJESTI_DEV_DB;
  if (existing) return existingDb(existing);
  const db = new PGlite();
  await db.waitReady;
  const articles = await seed(db);
  return { db, articles };
}

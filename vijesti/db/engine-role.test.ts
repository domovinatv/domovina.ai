// Migracija 007: uloga enginea `vijesti_engine` (odluka 808) i bug 807
// (`save_editor_version` je gubio `content.related`).
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, describe, expect, it } from 'vitest';
import { PERSONS_FIXTURE } from '../engine/cli.js';
import { createFakeExtractLlm } from '../engine/extract/fake-llm.js';
import { runExtract } from '../engine/extract/run.js';
import { createFakeScoreLlm } from '../engine/score/fake-llm.js';
import { buildPersonIndex, parsePersons } from '../engine/score/persons.js';
import { runScore } from '../engine/score/run.js';
import { fixtureCdn } from '../engine/test/scored-db.js';
import { runVerify } from '../engine/verify/article.js';
import { createFakeVerifyLlm } from '../engine/verify/article-fake-llm.js';
import { createFakeWriteLlm } from '../engine/write/fake-llm.js';
import type { ArticleContent } from '../engine/write/content.js';
import { loadLatestVersion } from '../engine/write/store.js';
import { runWrite } from '../engine/write/vijest.js';
import { asUser, saveEditorVersion, type EditorBlock } from './editorial.js';
import { migrateUp } from './migrate.js';
import { createSqlRunRecorder } from './runs.js';

const VIDEO = 'MGLq9v3AtvE';
const CHANNEL = 'domovina_tv';
const EDITOR = '11111111-1111-4111-8111-111111111111';
const RELATED = [
  {
    videoId: 'AAAAAAAAAAA',
    t: 120,
    channel: 'hnb',
    episodeTitle: 'Rizični kapital u regiji',
    topic: 'EU Inc',
    date: '2026-10-01',
    score: 0.67,
  },
];

let db: PGlite | null = null;
afterEach(async () => {
  await db?.close();
  db = null;
});

/** Cijeli tok enginea (izvlačenje → provjera) kao uloga `vijesti_engine`. */
async function engineFlow(): Promise<{ db: PGlite; articleId: number }> {
  const d = new PGlite();
  await d.waitReady;
  await migrateUp(d);
  await d.exec('SET ROLE vijesti_engine');
  const recorder = createSqlRunRecorder(d);
  const persons = buildPersonIndex(parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons);
  await runExtract({ cdn: fixtureCdn(), llm: createFakeExtractLlm(recorder), recorder, db: d }, { videoId: VIDEO });
  await runScore(
    { cdn: fixtureCdn(), llm: createFakeScoreLlm(recorder), recorder, db: d, persons },
    { videoId: VIDEO, channel: CHANNEL },
  );
  const w = await runWrite(
    { cdn: fixtureCdn(), llm: createFakeWriteLlm(recorder), recorder, db: d },
    { videoId: VIDEO, channel: CHANNEL },
  );
  if (!w.saved) throw new Error('članak nije spremljen');
  await runVerify({ llm: createFakeVerifyLlm(recorder), recorder, db: d }, { articleId: w.saved.articleId });
  return { db: d, articleId: w.saved.articleId };
}

describe('uloga enginea (007)', () => {
  it('engine prolazi izvlačenje, ocjenu, pisanje i provjeru bez vlasničkih prava', async () => {
    const flow = await engineFlow();
    db = flow.db;
    const who = await db.query<{ u: string }>('SELECT current_user AS u');
    expect(who.rows[0]?.u).toBe('vijesti_engine');
    const v = await loadLatestVersion(db, flow.articleId);
    expect(v?.verify).not.toBeNull();
    // Red provjere urednikovih verzija vidi (dnevni job ga čita prvi, odluka 806).
    const q = await db.query('SELECT article_id FROM vijesti.versions_awaiting_verify');
    expect(q.rows).toEqual([]);
  });

  it('engine ne vidi ništa izvan sheme vijesti', async () => {
    db = new PGlite();
    await db.waitReady;
    await db.exec('CREATE SCHEMA domovina_ai; CREATE TABLE domovina_ai.tajna (x int); INSERT INTO domovina_ai.tajna VALUES (1);');
    await migrateUp(db);
    await db.exec('SET ROLE vijesti_engine');
    await expect(db.query('SELECT x FROM domovina_ai.tajna')).rejects.toThrow(/permission denied/);
  });
});

describe('save_editor_version čuva related (bug 807)', () => {
  it('urednička verzija nosi related bazne verzije, a bez njega ga ne izmišlja', async () => {
    const flow = await engineFlow();
    db = flow.db;
    await db.exec('RESET ROLE');
    await db.query(`INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor')`, [EDITOR]);
    const d = db;
    const base = await loadLatestVersion(d, flow.articleId);
    if (!base?.content) throw new Error('bez sadržaja');
    const content = base.content;
    const blocks: EditorBlock[] = content.blocks.map((b) =>
      b.type === 'p' ? { type: 'p', text: b.text } : { type: 'quote', moment_id: b.moment_id ?? 0 },
    );
    const edit = (baseVersionId: number) =>
      asUser(d, EDITOR, (x) =>
        saveEditorVersion(x, {
          articleId: flow.articleId,
          baseVersionId,
          title: content.title,
          lead: content.lead,
          category: content.category,
          blocks,
        }),
      );

    // Bez related u bazi: ključ se ne pojavljuje.
    const v1 = await edit(base.versionId);
    const plain = (await loadLatestVersion(d, flow.articleId))?.content as ArticleContent;
    expect(plain).not.toHaveProperty('related');

    // Verzija s related (kao iz enginea nakon RAG-a), pa urednička izmjena.
    const withRelated = { ...plain, related: RELATED };
    const ins = await d.query<{ id: number }>(
      `INSERT INTO vijesti.article_versions
         (article_id, version, title, body, lead, category, content, word_count, prompt_version, created_by)
       SELECT article_id, version + 1, title, body, lead, category, $2::jsonb, word_count, 'test', 'engine:test'
       FROM vijesti.article_versions WHERE id = $1 RETURNING id`,
      [v1, JSON.stringify(withRelated)],
    );
    await d.query(
      `INSERT INTO vijesti.article_sources (version_id, moment_id, position)
       SELECT $2, moment_id, position FROM vijesti.article_sources WHERE version_id = $1`,
      [v1, ins.rows[0]?.id],
    );
    await edit(Number(ins.rows[0]?.id));
    const after = (await loadLatestVersion(d, flow.articleId))?.content as ArticleContent;
    expect(after.related).toEqual(RELATED);
  });
});

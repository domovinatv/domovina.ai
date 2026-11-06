// Urednički tok (migracija 006, odluke 500–520) nad pravim člankom iz lažnog
// generatora i lažne provjere: stanja, dnevnik, uloge i javno čitanje kroz RLS.
import type { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createFakeLlmClient } from '../engine/llm/fake.js';
import { fixtureCdn, scoredDb } from '../engine/test/scored-db.js';
import { runVerify } from '../engine/verify/article.js';
import { createFakeVerifyLlm } from '../engine/verify/article-fake-llm.js';
import type { ArticleContent } from '../engine/write/content.js';
import { loadLatestVersion } from '../engine/write/store.js';
import { prepareWrite, runWrite } from '../engine/write/vijest.js';
import {
  allowChannel,
  approveArticle,
  asUser,
  correctArticle,
  loadArticleEvents,
  parseEditorialError,
  publishArticle,
  resolveSentence,
  retractArticle,
  saveEditorVersion,
  setStaffRole,
  removeStaff,
  transitionArticle,
  TRANSITIONS,
  type EditorBlock,
  type EditorialErrorCode,
} from './editorial.js';
import { createSqlRunRecorder } from './runs.js';
import type { SqlDb } from './sql.js';

const VIDEO = 'MGLq9v3AtvE';
const CHANNEL = 'domovina_tv';
const EDITOR = '11111111-1111-4111-8111-111111111111';
const ADMIN = '22222222-2222-4222-8222-222222222222';
const STRANGER = '33333333-3333-4333-8333-333333333333';
const FABRICATED = 'Vlada je najavila povećanje mirovina za umirovljenike od siječnja.';

async function expectCode(p: Promise<unknown>, code: EditorialErrorCode): Promise<void> {
  const err = await p.then(
    () => null,
    (e: unknown) => e,
  );
  expect(err, `očekivana greška ${code}`).not.toBeNull();
  expect(parseEditorialError(err)?.code, String(err)).toBe(code);
}

interface Verify {
  sentences: { n: number; status: string }[];
}

const unsupported = (verify: unknown): number[] =>
  (verify as Verify).sentences.filter((s) => s.status !== 'supported').map((s) => s.n);

const words = (s: string, n: number) => s.split(/\s+/).slice(0, n).join(' ').replace(/[.,!?;:]+$/, '');

describe('urednički tok', () => {
  let db: PGlite;
  let articleId: number;
  let channel: string;

  const ed = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, EDITOR, fn);
  const admin = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, ADMIN, fn);
  const anon = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, null, fn);
  const latest = async () => {
    const v = await loadLatestVersion(db, articleId);
    if (!v) throw new Error('članak bez verzije');
    return v;
  };
  const status = async () =>
    (await db.query<{ status: string }>('SELECT status FROM vijesti.articles WHERE id = $1', [articleId])).rows[0]
      ?.status;
  const verify = async () => {
    const recorder = createSqlRunRecorder(db);
    return runVerify({ llm: createFakeVerifyLlm(recorder), recorder, db }, { articleId });
  };
  const resolveAll = async (versionId: number, verifyJson: unknown) => {
    for (const n of unsupported(verifyJson)) {
      await ed((d) => resolveSentence(d, versionId, n, 'verified', 'Provjereno na snimci.'));
    }
  };

  beforeEach(async () => {
    db = await scoredDb(VIDEO, CHANNEL);
    const prep = await prepareWrite({ cdn: fixtureCdn(), db }, { videoId: VIDEO, channel: CHANNEL });
    const m1 = prep.moments.find((m) => m.position === 1);
    if (!m1) throw new Error('fixture bez trenutka iznad praga');
    const name = m1.speakerName ?? 'Govornik';
    const channelName = prep.episode.channelName ?? '';
    const out = {
      title: `${name} u podcastu ${channelName}`,
      lead: `${name} govorio je u podcastu ${channelName} o temi: ${words(m1.quote, 12)}.`,
      body: [
        { type: 'p', text: `Prema riječima govornika ${name}, ${words(m1.quote, 20)}.` },
        { type: 'quote', moment: 1 },
        { type: 'p', text: FABRICATED },
      ],
      category: 'drustvo',
    };
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeLlmClient({
      recorder,
      byName: { 'write-vijest': { text: JSON.stringify(out), usage: { tokensIn: 0, tokensOut: 0 } } },
    });
    const w = await runWrite({ cdn: fixtureCdn(), llm, recorder, db }, { videoId: VIDEO, channel: CHANNEL });
    if (!w.saved) throw new Error('članak nije spremljen');
    articleId = w.saved.articleId;
    await verify();
    channel = (await latest()).content?.episode.channel ?? '';
    expect(channel).not.toBe('');
    // Prvi admin i urednik se upisuju izravno kao vlasnik baze (odluka 503).
    await db.query(`INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor'), ($2, 'admin')`, [EDITOR, ADMIN]);
  });
  afterEach(async () => {
    await db.close();
  });

  it('sretni put: nacrt → pregled → razrješenje → odobreno → objavljeno → izmjena + verify → ispravljeno', async () => {
    const v2 = await latest();
    const open = unsupported(v2.verify);
    expect(open.length).toBeGreaterThan(0);

    // Nacrt nije javan.
    expect((await anon((d) => d.query('SELECT id FROM vijesti.articles'))).rows).toHaveLength(0);
    expect((await anon((d) => d.query('SELECT id FROM vijesti.public_article_versions'))).rows).toHaveLength(0);

    // S nepotvrđenom rečenicom smije u pregled, ne smije u odobreno.
    await ed((d) => transitionArticle(d, articleId, 'review'));
    await expectCode(ed((d) => approveArticle(d, articleId, v2.versionId)), 'unresolved');
    await resolveAll(v2.versionId, v2.verify);
    await expectCode(
      ed((d) => resolveSentence(d, v2.versionId, open[0] ?? 0, 'no_claim', 'Opet.')),
      'already_resolved',
    );
    await ed((d) => approveArticle(d, articleId, v2.versionId, 'U redu.'));
    expect(await status()).toBe('approved');

    // Objava samo s dopuštenog kanala; kanale vodi admin.
    await expectCode(ed((d) => publishArticle(d, articleId)), 'channel_not_allowed');
    await expectCode(ed((d) => allowChannel(d, channel)), 'forbidden');
    await admin((d) => allowChannel(d, channel, 'pristanak kreatora'));
    await ed((d) => publishArticle(d, articleId));
    const pub = (
      await db.query<{ status: string; published_version_id: string; published_at: Date | null }>(
        'SELECT status, published_version_id, published_at FROM vijesti.articles WHERE id = $1',
        [articleId],
      )
    ).rows[0];
    expect(pub?.status).toBe('published');
    expect(Number(pub?.published_version_id)).toBe(v2.versionId);
    expect(pub?.published_at).not.toBeNull();

    // Javno: članak, samo objavljena verzija, bez provjere; vidljivi samo citirani trenutci (odluka 524).
    const pubVersions = await anon((d) => d.query<{ id: number | string }>('SELECT id FROM vijesti.public_article_versions'));
    expect(pubVersions.rows.map((r) => Number(r.id))).toEqual([v2.versionId]);
    await expect(anon((d) => d.query('SELECT verify FROM vijesti.article_versions'))).rejects.toThrow(
      /permission denied/,
    );
    const pubMoments = await anon((d) => d.query<{ n: number }>('SELECT count(*)::int AS n FROM vijesti.moments'));
    const quoted = new Set((v2.content as ArticleContent).blocks.flatMap((b) => (b.type === 'quote' ? [b.moment_id] : [])));
    expect(quoted.size).toBeGreaterThan(0);
    expect(pubMoments.rows[0]?.n).toBe(quoted.size);

    // Urednička izmjena objavljenog članka: nova verzija bez provjere, javno i dalje v2.
    const content = v2.content as ArticleContent;
    const blocks: EditorBlock[] = content.blocks
      .filter((b) => !(b.type === 'p' && b.text === FABRICATED))
      .map((b) => (b.type === 'p' ? { type: 'p', text: b.text } : { type: 'quote', moment_id: b.moment_id ?? 0 }));
    const v3 = await ed((d) =>
      saveEditorVersion(d, {
        articleId,
        baseVersionId: v2.versionId,
        title: content.title,
        lead: content.lead,
        category: content.category,
        blocks,
      }),
    );
    const v3row = await latest();
    expect(v3row).toMatchObject({ versionId: v3, version: v2.version + 1, verify: null, createdBy: `editor:${EDITOR}` });
    expect(v3row.body).not.toContain(FABRICATED);
    expect(v3row.sources.map((s) => [s.id, s.position])).toEqual(v2.sources.map((s) => [s.id, s.position]));
    expect(await status()).toBe('published');
    const queue = await ed((d) =>
      d.query<{ version_id: string }>('SELECT version_id FROM vijesti.versions_awaiting_verify'),
    );
    expect(queue.rows.map((r) => Number(r.version_id))).toEqual([v3]);
    await expect(anon((d) => d.query('SELECT 1 FROM vijesti.versions_awaiting_verify'))).rejects.toThrow(
      /permission denied/,
    );
    expect(
      (await asUser(db, STRANGER, (d) => d.query('SELECT 1 FROM vijesti.versions_awaiting_verify'))).rows,
    ).toHaveLength(0);

    // Ispravak traži provjeru te verzije; engine je radi, urednik razrješava.
    await expectCode(ed((d) => correctArticle(d, articleId, v3, 'fact', 'Uklonjena tvrdnja.')), 'not_verified');
    const r4 = await verify();
    const v4 = r4.saved.versionId;
    await resolveAll(v4, r4.result);
    const correctionId = await ed((d) =>
      correctArticle(d, articleId, v4, 'fact', 'Uklonjena neprovjerena tvrdnja o mirovinama.'),
    );
    expect(correctionId).toBeGreaterThan(0);
    expect(await status()).toBe('corrected');

    const after = await anon((d) =>
      Promise.all([
        d.query<{ id: string }>('SELECT id FROM vijesti.public_article_versions'),
        d.query<{ kind: string; description: string; version_id: string }>(
          'SELECT kind, description, version_id FROM vijesti.public_corrections',
        ),
      ]),
    );
    expect(after[0].rows.map((r) => Number(r.id))).toEqual([v4]);
    expect(after[1].rows).toEqual([
      { kind: 'fact', description: 'Uklonjena neprovjerena tvrdnja o mirovinama.', version_id: v4 },
    ]);
    await expect(anon((d) => d.query('SELECT created_by FROM vijesti.corrections'))).rejects.toThrow(
      /permission denied/,
    );

    // Dnevnik: nastanak (engine) i svaki prijelaz s korisnikom.
    const events = await loadArticleEvents(db, articleId);
    expect(events.map((e) => [e.fromStatus, e.toStatus, e.actor, e.actorLabel])).toEqual([
      [null, 'draft', null, 'engine:write'],
      ['draft', 'review', EDITOR, `editor:${EDITOR}`],
      ['review', 'approved', EDITOR, `editor:${EDITOR}`],
      ['approved', 'published', EDITOR, `editor:${EDITOR}`],
      ['published', 'corrected', EDITOR, `editor:${EDITOR}`],
    ]);
    expect(events.map((e) => e.versionId).slice(2)).toEqual([v2.versionId, v2.versionId, v4]);
    expect(events[2]?.note).toBe('U redu.');
    expect(events[4]?.note).toBe('Uklonjena neprovjerena tvrdnja o mirovinama.');
    // Čitatelj dnevnik ne vidi.
    expect((await anon((d) => d.query('SELECT 1 FROM vijesti.articles WHERE id = $1', [articleId]))).rows).toHaveLength(1);
    await expect(anon((d) => d.query('SELECT 1 FROM vijesti.article_events'))).rejects.toThrow(/permission denied/);
  });

  it('nedopušteni prijelazi se odbijaju, i vlasniku', async () => {
    const v = await latest();
    await expectCode(ed((d) => approveArticle(d, articleId, v.versionId)), 'invalid_transition');
    await expectCode(ed((d) => publishArticle(d, articleId)), 'invalid_transition');
    await expectCode(ed((d) => retractArticle(d, articleId, 'Razlog.')), 'invalid_transition');
    await expectCode(ed((d) => correctArticle(d, articleId, v.versionId, 'fact', 'Opis.')), 'invalid_transition');
    await expectCode(ed((d) => transitionArticle(d, articleId, 'draft')), 'invalid_transition');
    await expectCode(
      ed((d) => d.query(`SELECT vijesti.transition_article($1, 'published', NULL)`, [articleId])),
      'invalid_input',
    );
    await expectCode(ed((d) => transitionArticle(d, articleId, 'rejected', '  ')), 'invalid_input');
    // Okidač brani stroj stanja i za vlasnika baze.
    await expectCode(
      db.query(`UPDATE vijesti.articles SET status = 'published' WHERE id = $1`, [articleId]),
      'invalid_transition',
    );
    // Prijavljeni urednik ne može mijenjati tablicu izravno.
    await expect(
      ed((d) => d.query(`UPDATE vijesti.articles SET status = 'review' WHERE id = $1`, [articleId])),
    ).rejects.toThrow(/permission denied/);
    expect(await status()).toBe('draft');

    await ed((d) => transitionArticle(d, articleId, 'rejected', 'Nije vijest.'));
    await expectCode(ed((d) => transitionArticle(d, articleId, 'review')), 'invalid_transition');
    await ed((d) => transitionArticle(d, articleId, 'draft'));
    expect(await status()).toBe('draft');
  });

  it('bez uloge nema prijelaza; čitatelj ne može ni pozvati funkciju', async () => {
    await expectCode(asUser(db, STRANGER, (d) => transitionArticle(d, articleId, 'review')), 'forbidden');
    await expect(anon((d) => transitionArticle(d, articleId, 'review'))).rejects.toThrow(/permission denied/);
    // Prijavljeni bez uloge vidi što i čitatelj: nacrt ne.
    expect(
      (await asUser(db, STRANGER, (d) => d.query('SELECT 1 FROM vijesti.articles'))).rows,
    ).toHaveLength(0);
    expect(await status()).toBe('draft');
  });

  it('nova verzija na odobrenom članku vraća ga u pregled; povučen članak skriva tijelo', async () => {
    const v2 = await latest();
    await ed((d) => transitionArticle(d, articleId, 'review'));
    await resolveAll(v2.versionId, v2.verify);
    await ed((d) => approveArticle(d, articleId, v2.versionId));
    const r3 = await verify();
    expect(await status()).toBe('review');
    const events = await loadArticleEvents(db, articleId);
    expect(events.at(-1)).toMatchObject({
      fromStatus: 'approved',
      toStatus: 'review',
      actor: null,
      actorLabel: 'engine:verify',
      versionId: r3.saved.versionId,
    });
    const approved = await db.query<{ approved_version_id: string | null }>(
      'SELECT approved_version_id FROM vijesti.articles WHERE id = $1',
      [articleId],
    );
    expect(approved.rows[0]?.approved_version_id).toBeNull();

    await resolveAll(r3.saved.versionId, r3.result);
    await ed((d) => approveArticle(d, articleId, r3.saved.versionId));
    await admin((d) => allowChannel(d, channel));
    await ed((d) => publishArticle(d, articleId));
    await ed((d) => retractArticle(d, articleId, 'Govornik je osporio kontekst.'));
    expect(await status()).toBe('retracted');
    const pub = await anon((d) =>
      Promise.all([
        d.query('SELECT id FROM vijesti.articles'),
        d.query('SELECT id FROM vijesti.public_article_versions'),
        d.query<{ kind: string }>('SELECT kind FROM vijesti.public_corrections'),
        d.query('SELECT id FROM vijesti.stories'),
      ]),
    );
    expect(pub[0].rows).toHaveLength(1);
    expect(pub[1].rows).toHaveLength(0);
    expect(pub[2].rows).toEqual([{ kind: 'retraction' }]);
    expect(pub[3].rows).toHaveLength(1);
  });

  it('urednička verzija: citat samo iz iste epizode, uređuje se zadnja verzija', async () => {
    const v = await latest();
    const content = v.content as ArticleContent;
    const base = {
      articleId,
      baseVersionId: v.versionId,
      title: content.title,
      lead: content.lead,
      category: content.category,
    };
    const other = await db.query<{ id: number }>(
      `INSERT INTO vijesti.moments (video_id, start_ms, end_ms, speaker, quote, quote_check, quote_match)
       VALUES ('drugiVideo1', 0, 1000, 'SPEAKER_00', 'Tuđi citat.', 'exact', 'exact') RETURNING id`,
    );
    await expectCode(
      ed((d) => saveEditorVersion(d, { ...base, blocks: [{ type: 'quote', moment_id: Number(other.rows[0]?.id) }] })),
      'invalid_quote',
    );
    await expectCode(
      ed((d) => saveEditorVersion(d, { ...base, baseVersionId: v.versionId - 1, blocks: [{ type: 'p', text: 'X.' }] })),
      'stale_version',
    );
    await expectCode(ed((d) => saveEditorVersion(d, { ...base, blocks: [] })), 'invalid_input');
    // Novi trenutak iste epizode dobiva prvu slobodnu poziciju.
    const extra = await db.query<{ id: number }>(
      `INSERT INTO vijesti.moments (video_id, start_ms, end_ms, speaker, quote, quote_check, quote_match)
       VALUES ($1, 3723000, 3725000, 'SPEAKER_00', 'Dodatni citat iz iste epizode.', 'exact', 'exact') RETURNING id`,
      [VIDEO],
    );
    const extraId = Number(extra.rows[0]?.id);
    expect(extraId).toBeGreaterThan(0);
    const id = await ed((d) =>
      saveEditorVersion(d, { ...base, blocks: [{ type: 'p', text: 'Novi odlomak.' }, { type: 'quote', moment_id: extraId }] }),
    );
    const saved = await latest();
    const maxPos = Math.max(...v.sources.map((s) => s.position));
    expect(saved.versionId).toBe(id);
    expect(saved.sources.find((s) => s.id === extraId)?.position).toBe(maxPos + 1);
    expect(saved.content?.blocks[1]).toEqual({ type: 'quote', moment_id: extraId, ref: `t${String(maxPos + 1)}` });
    expect(saved.body.split('\n\n')[1]).toBe('„Dodatni citat iz iste epizode.” – SPEAKER_00, 1:02:03');
    // Verify radi nad uredničkom verzijom kao nad generatorovom.
    const r = await verify();
    expect(r.baseVersion).toBe(saved.version);
  });

  it('dnevnik je samo za dodavanje; prijelazi u kodu i u bazi su isti', async () => {
    await expectCode(db.query(`UPDATE vijesti.article_events SET note = 'x'`), 'append_only');
    await expectCode(db.query('DELETE FROM vijesti.article_events'), 'append_only');
    await expectCode(db.query(`UPDATE vijesti.article_versions SET title = 'Drugi naslov'`), 'immutable');
    // FK `runs` → `run_id SET NULL` pri brisanju runa ostaje moguć.
    await db.query('UPDATE vijesti.article_versions SET run_id = NULL');
    const rows = await db.query<{ from_status: string; to_status: string }>(
      'SELECT from_status, to_status FROM vijesti.article_transitions ORDER BY 1, 2',
    );
    const key = (a: readonly [string, string]) => `${a[0]}>${a[1]}`;
    expect(rows.rows.map((r) => key([r.from_status, r.to_status])).sort()).toEqual(TRANSITIONS.map(key).sort());
  });

  it('admin vodi uloge; zadnji admin ostaje', async () => {
    await expectCode(ed((d) => setStaffRole(d, STRANGER, 'editor')), 'forbidden');
    await admin((d) => setStaffRole(d, STRANGER, 'editor'));
    await asUser(db, STRANGER, (d) => transitionArticle(d, articleId, 'review'));
    await expectCode(admin((d) => removeStaff(d, ADMIN)), 'last_admin');
    await expectCode(admin((d) => setStaffRole(d, ADMIN, 'editor')), 'last_admin');
    await admin((d) => removeStaff(d, STRANGER));
    await expectCode(asUser(db, STRANGER, (d) => transitionArticle(d, articleId, 'draft')), 'forbidden');
    // Korisnik vidi svoj redak, ne tuđe.
    const own = await asUser(db, STRANGER, (d) => d.query('SELECT user_id FROM vijesti.staff'));
    expect(own.rows).toHaveLength(0);
    const all = await ed((d) => d.query('SELECT user_id FROM vijesti.staff'));
    expect(all.rows).toHaveLength(2);
  });
});

describe('parseEditorialError', () => {
  it('kod do prve dvotočke, samo poznati kodovi', () => {
    expect(parseEditorialError(new Error('unresolved: verzija 3 ima nerazriješene rečenice {2}'))).toEqual({
      code: 'unresolved',
      message: 'verzija 3 ima nerazriješene rečenice {2}',
    });
    expect(parseEditorialError(new Error('permission denied for table articles'))).toBeNull();
    expect(parseEditorialError(new Error('nesto: drugo'))).toBeNull();
    expect(parseEditorialError(42)).toBeNull();
  });
});

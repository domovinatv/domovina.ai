// Adresa članka je stabilna (odluka 720): ni ispravak s novim naslovom ni nova
// verzija iz enginea ne mijenjaju `articles.slug`, a nijedna funkcija sheme ga
// ne piše. Nad lokalnim seedom (objavljen članak), bez mreže.
import type { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { asUser, correctArticle, resolveSentence, saveEditorVersion, type EditorBlock } from '../../db/editorial.js';
import { articleSlug, loadLatestVersion, saveArticleVersion } from '../../engine/write/store.js';
import { LOCAL_EDITOR_ID } from './ids.js';
import { seededDb, verifyArticle, type SeededArticle } from './seed.js';

const NEW_TITLE = 'Potpuno drukčiji naslov nakon ispravka';

describe('slug članka nakon objave', () => {
  let db: PGlite;
  let a: SeededArticle;
  const slugNow = async () =>
    (await db.query<{ slug: string }>('SELECT slug FROM vijesti.articles WHERE id = $1', [a.articleId])).rows[0]?.slug;
  const latest = async () => {
    const v = await loadLatestVersion(db, a.articleId);
    if (!v) throw new Error('nema verzije');
    return v;
  };

  beforeAll(async () => {
    const s = await seededDb();
    db = s.db;
    const found = s.articles.find((x) => x.state === 'published');
    if (!found) throw new Error('seed bez objavljenog članka');
    a = found;
  });
  afterAll(async () => {
    await db.close();
  });

  it('ispravak s novim naslovom: nova javna verzija, ista adresa', async () => {
    expect(articleSlug(NEW_TITLE, a.videoId)).not.toBe(a.slug);
    let v = await latest();
    const blocks = (v.content?.blocks ?? []).flatMap((b): EditorBlock[] =>
      b.type === 'p' ? [{ type: 'p', text: b.text }] : b.moment_id === null ? [] : [{ type: 'quote', moment_id: b.moment_id }],
    );
    await asUser(db, LOCAL_EDITOR_ID, (d) =>
      saveEditorVersion(d, {
        articleId: a.articleId,
        baseVersionId: v.versionId,
        title: NEW_TITLE,
        lead: v.lead ?? '',
        category: v.category ?? 'drustvo',
        blocks,
      }),
    );
    await verifyArticle(db, a.articleId);
    v = await latest();
    const pending = ((v.verify as { sentences?: { n: number; status: string }[] } | null)?.sentences ?? []).filter(
      (s) => s.status !== 'supported',
    );
    for (const s of pending) {
      await asUser(db, LOCAL_EDITOR_ID, (d) => resolveSentence(d, v.versionId, s.n, 'verified', 'test'));
    }
    await asUser(db, LOCAL_EDITOR_ID, (d) => correctArticle(d, a.articleId, v.versionId, 'other', 'Ispravljen naslov.'));

    const pub = await db.query<{ status: string; title: string }>(
      `SELECT a.status, v.title FROM vijesti.articles a JOIN vijesti.article_versions v ON v.id = a.published_version_id
       WHERE a.id = $1`,
      [a.articleId],
    );
    expect(pub.rows[0]).toEqual({ status: 'corrected', title: NEW_TITLE });
    expect(await slugNow()).toBe(a.slug);
  });

  it('nova verzija iz enginea s drugim naslovom ne mijenja adresu', async () => {
    const v = await latest();
    if (!v.content) throw new Error('verzija bez sadržaja');
    const saved = await saveArticleVersion(db, {
      videoId: a.videoId,
      title: 'Engine je napisao treći naslov',
      lead: v.lead ?? '',
      body: v.lead ?? '',
      category: v.category ?? 'drustvo',
      content: { ...v.content, title: 'Engine je napisao treći naslov' },
      wordCount: 1,
      promptVersion: 'test/slug',
      runId: null,
      createdBy: 'engine:test',
      sources: [],
    });
    expect(saved.articleId).toBe(a.articleId);
    expect(saved.slug).toBe(a.slug);
    expect(await slugNow()).toBe(a.slug);
  });

  it('nijedna funkcija sheme ne piše slug članka', async () => {
    const r = await db.query<{ proname: string }>(
      `SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'vijesti' AND p.prosrc ~* 'slug\\s*='`,
    );
    expect(r.rows).toEqual([]);
  });
});

// Lokalni PostgREST-shim nad seedom (odluka 604): protokol, uloge iz JWT-a i
// RLS kroz `asUser`, te javni i urednički sloj portala nad njim, bez mreže.
import type { PGlite } from '@electric-sql/pglite';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { describeError } from '../src/lib/errors.js';
import { articleBySlug, categoryArticles, clipMediaFile, latestArticles } from '../src/lib/public-data.js';
import { createRest, RestError } from '../src/lib/rest.js';
import { correctionState, createEditorApi, pendingSentences, editableBlocks } from '../src/scripts/admin/api.js';
import { mintUnsignedJwt } from '../src/scripts/admin/auth-local.js';
import { LOCAL_ANON_KEY, LOCAL_EDITOR_ID, LOCAL_STRANGER_ID } from './ids.js';
import { buildSelect, createRestShim, type RestShim } from './rest-shim.js';
import { SEED_RETRACTION_REASON, SEED_CORRECTION_DESCRIPTION, seededDb, verifyArticle, type SeededArticle } from './seed.js';
import { fetchViaShim } from './via-shim.js';

const URL_BASE = 'http://127.0.0.1:8790';

describe('PostgREST-shim nad lokalnim seedom', () => {
  let shim: RestShim;
  let articles: SeededArticle[];
  const reseed = async (): Promise<PGlite> => (await seededDb()).db;

  const rest = (token?: string) =>
    createRest({ url: URL_BASE, anonKey: LOCAL_ANON_KEY, token: token ?? null, fetch: fetchViaShim(shim) });
  const editor = () => rest(mintUnsignedJwt(LOCAL_EDITOR_ID));
  const get = (url: string, headers: Record<string, string | undefined> = {}) =>
    shim.handle({ method: 'GET', url, headers: { apikey: LOCAL_ANON_KEY, 'accept-profile': 'vijesti', ...headers } });
  const by = (state: SeededArticle['state']): SeededArticle => {
    const a = articles.find((x) => x.state === state);
    if (!a) throw new Error(state);
    return a;
  };

  beforeAll(async () => {
    const s = await seededDb();
    articles = s.articles;
    shim = createRestShim({ db: s.db, reset: reseed, verify: verifyArticle, seedInfo: () => articles });
  });
  afterAll(async () => {
    await shim.db().close();
  });

  it('seed: pet članaka u pet stanja', async () => {
    const r = await shim.db().query<{ status: string }>('SELECT status FROM vijesti.articles ORDER BY id');
    expect(r.rows.map((x) => x.status)).toEqual(['published', 'corrected', 'retracted', 'review', 'approved']);
    expect(articles.map((a) => a.state)).toEqual(['published', 'corrected', 'retracted', 'review', 'approved']);
  });

  it('anon i prijavljeni bez uloge ne vide nacrte; urednik vidi sve', async () => {
    const anon = await rest().select<{ status: string }>('articles', { select: 'id,status' });
    expect(anon.map((a) => a.status).sort()).toEqual(['corrected', 'published', 'retracted']);
    const stranger = await rest(mintUnsignedJwt(LOCAL_STRANGER_ID)).select('articles', { select: 'id' });
    expect(stranger).toHaveLength(3);
    const ed = await editor().select<{ status: string }>('articles', { select: 'id,status' });
    expect(ed).toHaveLength(5);
    // Javne verzije: samo trenutno objavljene (povučen članak nema nijednu).
    expect(await rest().select('public_article_versions', { select: 'id' })).toHaveLength(2);
    // Čitatelj nema pravo na urednički pogled (401 kao u PostgREST-u za anon).
    const denied = await rest()
      .select('editor_article_versions', { select: 'id' })
      .catch((e: unknown) => e);
    expect((denied as RestError).status).toBe(401);
    expect(await rest(mintUnsignedJwt(LOCAL_STRANGER_ID)).select('editor_article_versions', { select: 'id' })).toHaveLength(0);
    expect((await editor().select('editor_article_versions', { select: 'id' })).length).toBeGreaterThan(5);
  });

  it('protokol: apikey, profil, nepoznata relacija, istekao i nevaljan token, nepodržan operator', async () => {
    expect((await get('/rest/v1/articles', { apikey: undefined })).status).toBe(401);
    expect((await get('/rest/v1/articles', { 'accept-profile': undefined })).status).toBe(406);
    expect((await get('/rest/v1/runs')).status).toBe(404);
    const expired = mintUnsignedJwt(LOCAL_EDITOR_ID, 1);
    const r = await get('/rest/v1/articles', { authorization: `Bearer ${expired}` });
    expect(r.status).toBe(401);
    expect(JSON.parse(String(r.body))).toMatchObject({ code: 'PGRST303' });
    expect((await get('/rest/v1/articles', { authorization: 'Bearer nije.jwt' })).status).toBe(401);
    expect((await get('/rest/v1/articles?id=like.1')).status).toBe(400);
    expect((await get('/rest/v1/articles?select=id;drop')).status).toBe(400);
    expect(() => buildSelect('articles', new URLSearchParams('order=id.desc;x'))).toThrow();
  });

  it('upit: filteri, in s navodnicima, order, limit', () => {
    const q = buildSelect('articles', new URLSearchParams('select=id,slug&status=in.("a","b,c")&id=gte.2&order=published_at.desc.nullslast,id.asc&limit=5'));
    expect(q.sql).toBe(
      'SELECT "id", "slug" FROM vijesti."articles" WHERE "status"::text = ANY($1::text[]) AND "id" >= $2 ORDER BY "published_at" DESC NULLS LAST, "id" ASC LIMIT 5',
    );
    expect(q.params).toEqual([['a', 'b,c'], '2']);
  });

  it('javne stranice: najnovije, kategorija, članak, ispravljen i povučen', async () => {
    const list = await latestArticles(rest());
    expect(list.map((c) => c.slug).sort()).toEqual([by('published').slug, by('corrected').slug].sort());
    const cat = list[0]?.category ?? '';
    expect((await categoryArticles(rest(), cat)).map((c) => c.category)).toEqual(
      list.filter((c) => c.category === cat).map((c) => c.category),
    );
    expect(await categoryArticles(rest(), 'sport')).toEqual([]);

    const pub = await articleBySlug(rest(), by('published').slug);
    expect(pub?.kind).toBe('published');
    if (pub?.kind !== 'published') throw new Error('nije objavljen');
    const quoted = pub.content.blocks.flatMap((b) => (b.type === 'quote' && b.moment_id !== null ? [b.moment_id] : []));
    expect(quoted.length).toBeGreaterThan(0);
    expect([...pub.moments.keys()].sort()).toEqual([...new Set(quoted)].sort());
    expect(pub.episode.videoId).toBe('MGLq9v3AtvE');

    const cor = await articleBySlug(rest(), by('corrected').slug);
    expect(cor?.kind === 'published' && cor.corrections.map((c) => [c.kind, c.description])).toEqual([
      ['fact', SEED_CORRECTION_DESCRIPTION],
    ]);
    expect(cor?.kind === 'published' && cor.version.id).toBe(by('corrected').versionId);

    const ret = await articleBySlug(rest(), by('retracted').slug);
    expect(ret?.kind).toBe('retracted');
    expect(ret?.kind === 'retracted' && ret.retraction?.description).toBe(SEED_RETRACTION_REASON);

    expect(await articleBySlug(rest(), by('review').slug)).toBeNull();
    expect(await articleBySlug(rest(), 'ne-postoji')).toBeNull();
  });

  it('lažni CDN: episode.json iz fixturea, medij isječka je tišina, ostalo 404', async () => {
    expect(await clipMediaFile(fetchViaShim(shim), `${URL_BASE}/cdn`, 'MGLq9v3AtvE')).toBe('video_h264.mp4');
    expect(await clipMediaFile(fetchViaShim(shim), `${URL_BASE}/cdn`, 'nema-ga')).toBeNull();
    const media = await get('/cdn/data/MGLq9v3AtvE/video_h264.mp4');
    expect(media.status).toBe(200);
    expect(media.headers['content-type']).toBe('audio/mpeg');
  });

  it('urednik: red čekanja, rečenice, razrješenje, zastarjela verzija, odobravanje; anon ne zove rpc', async () => {
    const api = createEditorApi(editor());
    expect(await api.role(LOCAL_EDITOR_ID)).toBe('editor');
    expect(await createEditorApi(rest(mintUnsignedJwt(LOCAL_STRANGER_ID))).role(LOCAL_STRANGER_ID)).toBeNull();
    const queue = await api.queue(['draft', 'review', 'approved']);
    expect(queue.map((q) => q.article.status).sort()).toEqual(['approved', 'review']);

    const id = by('review').articleId;
    const b = await api.article(id);
    if (!b) throw new Error('nema članka');
    expect(b.latest.id).toBe(by('review').versionId);
    expect(b.versions.map((v) => v.version)).toEqual([...b.versions.map((v) => v.version)].sort((x, y) => y - x));
    const pending = pendingSentences(b.latest, b.resolutions);
    expect(pending.length).toBeGreaterThan(0);
    expect(b.moments.length).toBeGreaterThan(0);
    expect(b.events.at(-1)?.to_status).toBe('review');

    const anonErr = await createEditorApi(rest())
      .approve(id, b.latest.id, null)
      .catch((e: unknown) => e);
    expect((anonErr as RestError).status).toBe(401);

    const unresolved = await api.approve(id, b.latest.id, null).catch((e: unknown) => e);
    expect(describeError(unresolved).code).toBe('unresolved');
    const older = b.versions[1];
    if (!older) throw new Error('nema starije verzije');
    const stale = await api.approve(id, older.id, null).catch((e: unknown) => e);
    expect(describeError(stale).code).toBe('stale_version');
    const staleSave = await api
      .saveVersion({
        articleId: id,
        latestVersionId: older.id,
        title: 'x',
        lead: 'y',
        category: 'drustvo',
        blocks: editableBlocks(b.latest),
      })
      .catch((e: unknown) => e);
    expect(describeError(staleSave).code).toBe('stale_version');

    for (const s of pending) await api.resolve(b.latest.id, s.n, 'verified', 'Provjereno na snimci.');
    await api.approve(id, b.latest.id, 'U redu.');
    expect((await api.article(id))?.article.status).toBe('approved');
    // Nakon reseta je baza opet početna.
    expect((await shim.handle({ method: 'POST', url: '/__shim/reset', headers: {} })).status).toBe(200);
    expect((await createEditorApi(editor()).article(id))?.article.status).toBe('review');
  });

  it('ispravak: tek nova, provjerena i razriješena verzija; /__shim/seed i /__shim/verify', async () => {
    const info = JSON.parse(String((await shim.handle({ method: 'GET', url: '/__shim/seed', headers: {} })).body)) as SeededArticle[];
    expect(info.map((a) => a.state)).toEqual(articles.map((a) => a.state));
    const id = by('published').articleId;
    const api = createEditorApi(editor());
    const load = async () => {
      const b = await api.article(id);
      if (!b) throw new Error('nema članka');
      return b;
    };
    let b = await load();
    expect(correctionState(b)).toBe('needs_edit');
    // Gumb bez nove verzije bi dobio ovu grešku: zato ga admin ne nudi.
    const same = await api.correct(id, b.latest.id, 'fact', 'x').catch((e: unknown) => e);
    expect(describeError(same).code).toBe('invalid_input');

    await api.saveVersion({
      articleId: id,
      latestVersionId: b.latest.id,
      title: b.latest.title,
      lead: 'Novi uvod.',
      category: b.latest.category ?? 'drustvo',
      blocks: editableBlocks(b.latest),
    });
    b = await load();
    expect(b.article.status).toBe('published');
    expect(correctionState(b)).toBe('needs_verify');
    const notVerified = await api.correct(id, b.latest.id, 'fact', 'x').catch((e: unknown) => e);
    expect(describeError(notVerified).code).toBe('not_verified');

    expect((await shim.handle({ method: 'POST', url: '/__shim/verify?article=x', headers: {} })).status).toBe(400);
    expect((await shim.handle({ method: 'POST', url: `/__shim/verify?article=${String(id)}`, headers: {} })).status).toBe(200);
    b = await load();
    for (const s of pendingSentences(b.latest, b.resolutions)) await api.resolve(b.latest.id, s.n, 'verified', 'U redu.');
    b = await load();
    expect(correctionState(b)).toBe('ready');
    await api.correct(id, b.latest.id, 'fact', 'Ispravljen uvod.');
    b = await load();
    expect(b.article.status).toBe('corrected');
    expect(correctionState(b)).toBe('needs_edit');
    expect(correctionState({ ...b, article: { ...b.article, status: 'review' } })).toBeNull();
  });
});

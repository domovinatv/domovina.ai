// Dnevni job (S8, odluka 809) na PGliteu s lažnim CDN-om i lažnim modelom:
// dva uzastopna pokretanja bez duplikata, dnevni limit, red provjere prvi.
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { asUser, saveEditorVersion, type EditorBlock } from '../../db/editorial.js';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { PERSONS_FIXTURE } from '../cli.js';
import { createFakeEvalLlm } from '../eval/fake-llm.js';
import { buildPersonIndex, parsePersons } from '../score/persons.js';
import { fixtureCdn } from '../test/scored-db.js';
import { loadLatestVersion } from '../write/store.js';
import { EXIT_DEFERRED, fitBudget, formatNotify, runDaily, zagrebMidnight, type DailyOptions } from './run.js';

const EDITOR = '11111111-1111-4111-8111-111111111111';
// Obje epizode `domovina_tv` iz fixturea (26.2. i 26.3.2026.) su u prozoru.
const OPTS: DailyOptions = {
  now: new Date('2026-03-27T10:00:00Z'),
  days: 31,
  maxCalls: 1000,
  dryRun: false,
  attempts: 2,
  adminUrl: 'https://domovina.ai/vijesti/admin',
};

let db: PGlite;
beforeEach(async () => {
  db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  await db.query(`INSERT INTO vijesti.allowed_channels (channel) VALUES ('domovina_tv')`);
});
afterEach(async () => {
  await db.close();
});

function deps() {
  const recorder = createSqlRunRecorder(db);
  const persons = buildPersonIndex(parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons);
  return { cdn: fixtureCdn(), db, recorder, persons, llm: () => createFakeEvalLlm(recorder), backend: 'fake' as const };
}

const count = async (sql: string) => Number((await db.query<{ n: number | string }>(sql)).rows[0]?.n ?? 0);

describe('dnevni job', () => {
  it('dva uzastopna pokretanja: drugo ne troši poziv i ne stvara duplikat', async () => {
    const first = await runDaily(deps(), OPTS);
    expect(first.exitCode, first.text).toBe(0);
    expect(first.candidates).toBe(2);
    expect(first.callsMade).toBeGreaterThan(0);
    expect(first.newDrafts.length).toBeGreaterThan(0);
    const articles = await count('SELECT count(*) AS n FROM vijesti.articles');
    const runs = await count('SELECT count(*) AS n FROM vijesti.runs');
    expect(first.notify).toContain(`?clanak=${String(first.newDrafts[0]?.articleId)}`);

    const second = await runDaily(deps(), OPTS);
    expect(second.exitCode, second.text).toBe(0);
    expect(second.callsMade).toBe(0);
    expect(second.planned).toBe(0);
    expect(second.newDrafts).toEqual([]);
    expect(await count('SELECT count(*) AS n FROM vijesti.articles')).toBe(articles);
    expect(await count('SELECT count(*) AS n FROM vijesti.runs')).toBe(runs);
    expect(second.usedBefore).toBe(first.callsMade);
  });

  it('suhi prolaz ništa ne poziva ni ne upisuje', async () => {
    const r = await runDaily(deps(), { ...OPTS, dryRun: true });
    expect(r.callsMade).toBe(0);
    expect(r.planned).toBe(2);
    expect(await count('SELECT count(*) AS n FROM vijesti.runs')).toBe(0);
  });

  it('dnevni limit: epizoda koja ne stane čeka sutra, poziva nikad više od limita', async () => {
    const dry = await runDaily(deps(), { ...OPTS, dryRun: true });
    expect(dry.planned).toBe(2);
    // Limit manji od procjene i jedne epizode: obje čekaju, ništa se ne poziva.
    const all = await runDaily(deps(), { ...OPTS, dryRun: true, maxCalls: 1 });
    expect(all.deferred).toHaveLength(2);
    const r = await runDaily(deps(), { ...OPTS, maxCalls: 1 });
    expect(r.exitCode).toBe(EXIT_DEFERRED);
    expect(r.callsMade).toBe(0);
    expect(r.notify).toContain('Čeka sutra (limit): 2 epizoda');
    // Limit je dnevni: već potrošeni pozivi se oduzimaju.
    await db.query(`INSERT INTO vijesti.runs (step, model, status, calls) VALUES ('extract', 'x', 'ok', 5)`);
    const again = await runDaily(deps(), { ...OPTS, dryRun: true, maxCalls: 5 });
    expect(again.usedBefore).toBe(5);
    expect(again.text).toContain('ostaje 0');
  });

  it('urednikova verzija bez provjere ide prva u red i dobiva provjeru', async () => {
    await runDaily(deps(), OPTS);
    const id = Number((await db.query<{ id: number }>('SELECT min(id) AS id FROM vijesti.articles')).rows[0]?.id);
    await db.query(`INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor')`, [EDITOR]);
    const base = await loadLatestVersion(db, id);
    if (!base?.content) throw new Error('bez sadržaja');
    const content = base.content;
    const blocks: EditorBlock[] = content.blocks.map((b) =>
      b.type === 'p' ? { type: 'p', text: b.text } : { type: 'quote', moment_id: b.moment_id ?? 0 },
    );
    await asUser(db, EDITOR, (d) =>
      saveEditorVersion(d, { articleId: id, baseVersionId: base.versionId, title: content.title, lead: content.lead, category: content.category, blocks }),
    );
    expect((await loadLatestVersion(db, id))?.verify).toBeNull();

    const r = await runDaily(deps(), OPTS);
    expect(r.queue.map((q) => q.item.articleId)).toEqual([id]);
    expect(r.queue[0]?.result).toMatch(/^provjereno/);
    expect(r.callsMade).toBe(1);
    expect((await loadLatestVersion(db, id))?.verify).not.toBeNull();
    expect(r.notify).toContain('Provjerenih uredničkih verzija: 1');
  });

  it('bez dopuštenih kanala nema posla', async () => {
    await db.query('DELETE FROM vijesti.allowed_channels');
    const r = await runDaily(deps(), OPTS);
    expect(r.candidates).toBe(0);
    expect(r.exitCode).toBe(0);
  });
});

describe('pomoćne funkcije', () => {
  it('ponoć po Zagrebu: zimsko (CET) i ljetno (CEST) vrijeme', () => {
    expect(zagrebMidnight(new Date('2026-01-15T10:00:00Z')).toISOString()).toBe('2026-01-14T23:00:00.000Z');
    expect(zagrebMidnight(new Date('2026-07-15T10:00:00Z')).toISOString()).toBe('2026-07-14T22:00:00.000Z');
    // 23:30 UTC 14.7. je već 15.7. u Zagrebu.
    expect(zagrebMidnight(new Date('2026-07-14T23:30:00Z')).toISOString()).toBe('2026-07-14T22:00:00.000Z');
  });

  it('fitBudget čuva redoslijed i staje na prvoj koja ne stane', () => {
    const p = (calls: number) => ({ calls }) as Parameters<typeof fitBudget>[0][number];
    const { take, rest } = fitBudget([p(3), p(5), p(1)], 7);
    expect(take.map((x) => x.calls)).toEqual([3]);
    expect(rest.map((x) => x.calls)).toEqual([5, 1]);
  });

  it('obavijest bez HTML-a iz naslova', () => {
    const n = formatNotify(
      { exitCode: 0, usedBefore: 0, callsMade: 3, queue: [], candidates: 1, planned: 1, ran: 1, deferred: [], newDrafts: [{ articleId: 7, title: 'A <b> & B' }], errors: [] },
      { adminUrl: 'https://x/admin', maxCalls: 150 },
    );
    expect(n).toContain('A &lt;b&gt; &amp; B — https://x/admin?clanak=7');
    expect(n).toContain('Poziva modela danas: 3/150');
  });
});

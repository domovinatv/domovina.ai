// Adversarijalni testovi uredničkog toka (migracija 006, odluke 500–528): svaki
// nedopušten prijelaz, curenje nacrta javnom klijentu, trag ispravka, eskalacija
// uloga, zastarjele verzije, SQL injection i `search_path`. Baza je minimalna
// (bez generatora), da svako stanje i svaki trenutak bude pod kontrolom testa.
import { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { CONTENT_SCHEMA, type ArticleContent } from '../engine/write/content.js';
import { saveArticleVersion } from '../engine/write/store.js';
import {
  ARTICLE_STATUSES,
  asUser,
  parseEditorialError,
  TRANSITIONS,
  type ArticleStatus,
  type EditorialErrorCode,
} from './editorial.js';
import { migrateUp } from './migrate.js';
import type { SqlDb } from './sql.js';

const CH = 'kanal_a';
const VIDEO = 'videoAAAAAAA';
const OTHER_VIDEO = 'videoBBBBBBB';
const EDITOR = '11111111-1111-4111-8111-111111111111';
const ADMIN = '22222222-2222-4222-8222-222222222222';
const STRANGER = '33333333-3333-4333-8333-333333333333';
const EDITOR2 = '44444444-4444-4444-8444-444444444444';

const INJECTION = `'); DELETE FROM vijesti.staff; UPDATE vijesti.articles SET status = 'published'; -- %s %% $$ \\`;

async function errorOf(p: Promise<unknown>): Promise<unknown> {
  return p.then(
    () => null,
    (e: unknown) => e,
  );
}

async function expectCode(p: Promise<unknown>, code: EditorialErrorCode): Promise<void> {
  const err = await errorOf(p);
  expect(err, `očekivana greška ${code}`).not.toBeNull();
  expect(parseEditorialError(err)?.code, String(err)).toBe(code);
}

async function expectDenied(p: Promise<unknown>): Promise<void> {
  await expect(p).rejects.toThrow(/permission denied/);
}

/** Zabrana unutar otvorene transakcije: savepoint, da se transakcija ne prekine. */
async function deniedIn(d: SqlDb, sql: string): Promise<void> {
  await d.exec('SAVEPOINT denied');
  const err = await errorOf(d.query(sql));
  await d.exec('ROLLBACK TO SAVEPOINT denied');
  expect(String(err), sql).toMatch(/permission denied/);
}

const allowed = (from: string, to: string) => TRANSITIONS.some(([f, t]) => f === from && t === to);

/** Put vlasnika baze do stanja (svaki korak je dopušten prijelaz). */
const PATH: Record<ArticleStatus, ArticleStatus[]> = {
  draft: [],
  review: ['review'],
  approved: ['review', 'approved'],
  published: ['review', 'approved', 'published'],
  corrected: ['review', 'approved', 'published', 'corrected'],
  retracted: ['review', 'approved', 'published', 'retracted'],
  rejected: ['rejected'],
};

interface Fixture {
  db: PGlite;
  moment(video: string, startMs: number, quote: string, failed?: boolean): Promise<number>;
  /** Novi članak u nacrtu s verzijom 1 (provjerena, sve `supported`). */
  article(opts?: { quotes?: number[]; sources?: number[]; video?: string }): Promise<{ id: number; v1: number }>;
  addVersion(
    articleId: number,
    opts?: { quotes?: number[]; sources?: number[]; verified?: boolean; unsupported?: number[] },
  ): Promise<number>;
  /** Vlasnik: preduvjeti za `to` (zapis ispravka, obavijest povlačenja). */
  prepare(articleId: number, to: ArticleStatus): Promise<void>;
  /** Vlasnik: jedan UPDATE prema `to`. */
  apply(articleId: number, to: ArticleStatus): Promise<void>;
  reach(articleId: number, state: ArticleStatus): Promise<void>;
  status(articleId: number): Promise<string>;
  events(articleId: number): Promise<number>;
  latest(articleId: number): Promise<number>;
  one<T>(sql: string, params?: unknown[]): Promise<T>;
}

let seq = 0;

async function fixture(): Promise<Fixture> {
  const db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  await db.query(`INSERT INTO vijesti.staff (user_id, role) VALUES ($1, 'editor'), ($2, 'admin')`, [EDITOR, ADMIN]);
  await db.query(`INSERT INTO vijesti.allowed_channels (channel) VALUES ($1)`, [CH]);

  const one = async <T>(sql: string, params: unknown[] = []): Promise<T> => {
    const row = (await db.query<T>(sql, params)).rows[0];
    if (row === undefined) throw new Error(`nema retka: ${sql}`);
    return row;
  };
  const content = (title: string, quotes: number[], video: string): ArticleContent => ({
    schema: CONTENT_SCHEMA,
    episode: { videoId: video, title: 'Epizoda', channel: CH, channelName: 'Kanal A', date: '2026-11-01', lang: 'hr', speakers: [] },
    title,
    lead: 'Lead članka.',
    category: 'drustvo',
    blocks: [
      { type: 'p', text: 'Odlomak članka.' },
      ...quotes.map((m, i) => ({ type: 'quote' as const, moment_id: m, ref: `t${String(i + 1)}` })),
    ],
  });
  const insertVersion = async (
    articleId: number,
    version: number,
    o: { quotes: number[]; sources: number[]; verified: boolean; unsupported: number[]; video: string },
  ): Promise<number> => {
    const title = `Naslov verzije ${String(version)}`;
    const verify = o.verified
      ? {
          base_version: version - 1,
          sentences: [
            { n: 1, status: 'supported' },
            ...o.unsupported.map((n) => ({ n, status: 'unsupported' })),
          ],
        }
      : null;
    const v = await one<{ id: number | string }>(
      `INSERT INTO vijesti.article_versions
         (article_id, version, title, body, lead, category, content, word_count, prompt_version, verify, created_by)
       VALUES ($1, $2, $3, 'Tijelo.', 'Lead članka.', 'drustvo', $4::jsonb, 4, 'test/1', $5::jsonb, 'engine:test')
       RETURNING id`,
      [articleId, version, title, JSON.stringify(content(title, o.quotes, o.video)), verify === null ? null : JSON.stringify(verify)],
    );
    const ids = [...new Set([...o.quotes, ...o.sources])];
    for (const [i, m] of ids.entries()) {
      await db.query('INSERT INTO vijesti.article_sources (version_id, moment_id, position) VALUES ($1, $2, $3)', [
        v.id,
        m,
        i + 1,
      ]);
    }
    return Number(v.id);
  };
  const videoOf = async (articleId: number) =>
    (
      await one<{ v: string }>(
        `SELECT content -> 'episode' ->> 'videoId' AS v FROM vijesti.article_versions
         WHERE article_id = $1 ORDER BY version LIMIT 1`,
        [articleId],
      )
    ).v;

  const f: Fixture = {
    db,
    one,
    async moment(video, startMs, quote, failed = false) {
      const r = await one<{ id: number | string }>(
        `INSERT INTO vijesti.moments (video_id, start_ms, end_ms, speaker, speaker_name, quote, quote_check, quote_match,
                                      reject_reason, claim, score, score_parts, score_reasons, score_version, scored_at, run_id)
         SELECT $1, $2, $2 + 1000, 'SPEAKER_00', 'Ivan Horvat', $3, $4, $5, $6, 'Tvrdnja modela.', s.score, s.parts,
                s.reasons, s.version, s.at, NULL
         FROM (SELECT 0.9::real AS score, '{}'::jsonb AS parts, '{"novost":"interni razlog"}'::jsonb AS reasons,
                      'score/1' AS version, now() AS at WHERE NOT $7
               UNION ALL SELECT NULL, NULL, NULL, NULL, NULL WHERE $7) s
         RETURNING id`,
        [video, startMs, quote, failed ? 'failed' : 'exact', failed ? null : 'exact', failed ? 'Nije u titlu.' : null, failed],
      );
      return Number(r.id);
    },
    async article(opts = {}) {
      seq += 1;
      const video = opts.video ?? VIDEO;
      const s = await one<{ id: number | string }>(`INSERT INTO vijesti.stories (slug, title) VALUES ($1, $2) RETURNING id`, [
        `video-${video}-${String(seq)}`,
        `Naslov nacrta ${String(seq)}`,
      ]);
      const a = await one<{ id: number | string }>(
        `INSERT INTO vijesti.articles (story_id, format, slug) VALUES ($1, 'vijest', $2) RETURNING id`,
        [s.id, `clanak-${String(seq)}`],
      );
      const id = Number(a.id);
      const v1 = await insertVersion(id, 1, {
        quotes: opts.quotes ?? [],
        sources: opts.sources ?? [],
        verified: true,
        unsupported: [],
        video,
      });
      return { id, v1 };
    },
    async addVersion(articleId, opts = {}) {
      const n = await one<{ n: number }>(
        'SELECT coalesce(max(version), 0)::int + 1 AS n FROM vijesti.article_versions WHERE article_id = $1',
        [articleId],
      );
      return insertVersion(articleId, n.n, {
        quotes: opts.quotes ?? [],
        sources: opts.sources ?? [],
        verified: opts.verified ?? true,
        unsupported: opts.unsupported ?? [],
        video: await videoOf(articleId),
      });
    },
    async prepare(articleId, to) {
      if (to === 'corrected') {
        await db.query(
          `INSERT INTO vijesti.corrections (article_id, version_id, kind, description, created_by, replaced_version_id)
           SELECT id, coalesce(published_version_id, vijesti._latest_version_id(id)), 'fact', 'Ispravak.', 'test',
                  published_version_id
           FROM vijesti.articles WHERE id = $1`,
          [articleId],
        );
      } else if (to === 'retracted') {
        await db.query(
          `INSERT INTO vijesti.corrections (article_id, kind, description, created_by, replaced_version_id)
           SELECT id, 'retraction', 'Povučeno.', 'test', published_version_id FROM vijesti.articles WHERE id = $1`,
          [articleId],
        );
      }
    },
    async apply(articleId, to) {
      const set =
        to === 'approved'
          ? `status = 'approved', approved_version_id = vijesti._latest_version_id(id)`
          : to === 'published'
            ? `status = 'published', published_version_id = approved_version_id, published_at = coalesce(published_at, now())`
            : `status = '${to}'`;
      await db.query(`UPDATE vijesti.articles SET ${set} WHERE id = $1`, [articleId]);
    },
    async reach(articleId, state) {
      for (const to of PATH[state]) {
        await f.prepare(articleId, to);
        await f.apply(articleId, to);
      }
      expect(await f.status(articleId)).toBe(state);
    },
    async status(articleId) {
      return (await one<{ status: string }>('SELECT status FROM vijesti.articles WHERE id = $1', [articleId])).status;
    },
    async events(articleId) {
      return (await one<{ n: number }>('SELECT count(*)::int AS n FROM vijesti.article_events WHERE article_id = $1', [articleId]))
        .n;
    },
    async latest(articleId) {
      return Number((await one<{ id: number | string }>('SELECT vijesti._latest_version_id($1) AS id', [articleId])).id);
    },
  };
  return f;
}

describe('urednički tok pod napadom', () => {
  let f: Fixture;
  let db: PGlite;
  const ed = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, EDITOR, fn);
  const admin = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, ADMIN, fn);
  const anon = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, null, fn);
  const stranger = <T>(fn: (d: SqlDb) => Promise<T>) => asUser(db, STRANGER, fn);
  /** Kao PostgREST, ali s proizvoljnim (i neispravnim) `request.jwt.claims`. */
  const asClaims = async <T>(role: string, claims: string | null, fn: (d: SqlDb) => Promise<T>): Promise<T> => {
    await db.exec('BEGIN');
    try {
      await db.exec(`SET LOCAL ROLE ${role}`);
      if (claims !== null) await db.query("SELECT set_config('request.jwt.claims', $1, true)", [claims]);
      const out = await fn(db);
      await db.exec('COMMIT');
      return out;
    } catch (e) {
      await db.exec('ROLLBACK');
      throw e;
    }
  };
  const asService = <T>(fn: (d: SqlDb) => Promise<T>) => asClaims('service_role', null, fn);

  beforeEach(async () => {
    f = await fixture();
    db = f.db;
  });
  afterEach(async () => {
    await db.close();
  });

  describe('1. stroj stanja: svih 49 parova', () => {
    it('vlasnik baze izravnim UPDATE-om: prolazi točno tablica prijelaza (i isto stanje kao no-op)', async () => {
      const got: string[] = [];
      for (const from of ARTICLE_STATUSES) {
        for (const to of ARTICLE_STATUSES) {
          const { id } = await f.article();
          await f.reach(id, from);
          await f.prepare(id, to);
          const before = await f.events(id);
          const err = await errorOf(f.apply(id, to));
          const ok = from === to || allowed(from, to);
          if (ok) {
            expect(err, `${from} → ${to}: ${String(err)}`).toBeNull();
            expect(await f.status(id)).toBe(to);
            // Dnevnik dobiva redak točno za prijelaz iz tablice (i `corrected → corrected`).
            expect(await f.events(id), `${from} → ${to}`).toBe(before + (allowed(from, to) ? 1 : 0));
            if (from !== to) got.push(`${from}>${to}`);
          } else {
            expect(parseEditorialError(err)?.code, `${from} → ${to}: ${String(err)}`).toBe('invalid_transition');
            expect(await f.status(id)).toBe(from);
            expect(await f.events(id)).toBe(before);
          }
        }
      }
      expect(got.sort()).toEqual(
        TRANSITIONS.filter(([a, b]) => a !== b)
          .map(([a, b]) => `${a}>${b}`)
          .sort(),
      );
    });

    it('urednik kroz funkcije: prolazi točno tablica prijelaza', async () => {
      for (const from of ARTICLE_STATUSES) {
        for (const to of ARTICLE_STATUSES) {
          const { id } = await f.article();
          await f.reach(id, from);
          // Nova provjerena verzija za ispravak; na odobrenom članku bi ga vratila u pregled.
          if (to === 'corrected' && from !== 'approved') await f.addVersion(id);
          const latest = await f.latest(id);
          const before = await f.status(id);
          const sql =
            to === 'approved'
              ? ['SELECT vijesti.approve_article($1, $2)', [id, latest]]
              : to === 'published'
                ? ['SELECT vijesti.publish_article($1)', [id]]
                : to === 'corrected'
                  ? [`SELECT vijesti.correct_article($1, $2, 'fact', 'Opis ispravka.')`, [id, latest]]
                  : to === 'retracted'
                    ? [`SELECT vijesti.retract_article($1, 'Razlog povlačenja.')`, [id]]
                    : [`SELECT vijesti.transition_article($1, $2, 'Bilješka urednika.')`, [id, to]];
          const err = await errorOf(ed((d) => d.query(sql[0] as string, sql[1] as unknown[])));
          if (allowed(from, to)) {
            expect(err, `${from} → ${to}: ${String(err)}`).toBeNull();
            expect(await f.status(id)).toBe(to);
          } else {
            expect(parseEditorialError(err)?.code, `${from} → ${to}: ${String(err)}`).toBe('invalid_transition');
            expect(await f.status(id)).toBe(before);
          }
        }
      }
    });

    it('authenticated (i urednik i admin) nema UPDATE, INSERT ni DELETE ni na jednoj tablici', async () => {
      const { id } = await f.article();
      for (const user of [EDITOR, ADMIN, STRANGER]) {
        for (const to of ARTICLE_STATUSES) {
          await expectDenied(asUser(db, user, (d) => d.query(`UPDATE vijesti.articles SET status = $2 WHERE id = $1`, [id, to])));
        }
      }
      const tables = (
        await db.query<{ t: string; col: string }>(
          `SELECT c.relname AS t,
                  (SELECT a.attname FROM pg_attribute a WHERE a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
                   ORDER BY a.attnum DESC LIMIT 1) AS col
           FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'vijesti' AND c.relkind = 'r' ORDER BY 1`,
        )
      ).rows;
      expect(tables.length).toBeGreaterThan(10);
      for (const { t, col } of tables) {
        for (const who of [null, EDITOR, ADMIN]) {
          await expectDenied(asUser(db, who, (d) => d.query(`DELETE FROM vijesti.${t}`)));
          await expectDenied(asUser(db, who, (d) => d.query(`UPDATE vijesti.${t} SET ${col} = ${col}`)));
          await expectDenied(asUser(db, who, (d) => d.query(`INSERT INTO vijesti.${t} DEFAULT VALUES`)));
          await expectDenied(asUser(db, who, (d) => d.query(`TRUNCATE vijesti.${t}`)));
        }
      }
      expect(await f.status(id)).toBe('draft');
    });
  });

  describe('2. javni klijent ne vidi nacrt', () => {
    interface World {
      states: Record<string, number>;
      publicArticles: number[];
      publicVersions: number[];
      publicMoments: number[];
      publicStories: number[];
      replaced: number;
      corrected: number;
      retracted: number;
    }
    const world = async (): Promise<World> => {
      const mDraft = await f.moment(VIDEO, 1000, 'Citat iz nacrta.');
      const mPub = await f.moment(VIDEO, 2000, 'Objavljen citat.');
      const mSrcOnly = await f.moment(VIDEO, 3000, 'Trenutak samo među izvorima.');
      const mOld = await f.moment(VIDEO, 4000, 'Citat uklonjen ispravkom.');
      const mKeep = await f.moment(VIDEO, 5000, 'Citat koji ostaje nakon ispravka.');
      const mRetr = await f.moment(VIDEO, 6000, 'Citat povučenog članka.');
      await f.moment(VIDEO, 7000, 'Odbačen citat.', true);
      const states: Record<string, number> = {};
      for (const st of ['draft', 'review', 'approved', 'rejected'] as const) {
        const a = await f.article({ quotes: [mDraft], sources: [mPub] });
        await f.reach(a.id, st);
        states[st] = a.id;
      }
      const pub = await f.article({ quotes: [mPub], sources: [mSrcOnly] });
      await f.reach(pub.id, 'published');
      // Neobjavljena verzija objavljenog članka (urednička izmjena u tijeku).
      await f.addVersion(pub.id, { quotes: [mPub, mDraft], verified: false });

      const corr = await f.article({ quotes: [mOld, mKeep] });
      await f.reach(corr.id, 'published');
      // Kao `save_editor_version`: izvori nose i trenutak čiji je citat uklonjen.
      const v2 = await f.addVersion(corr.id, { quotes: [mKeep], sources: [mOld] });
      await ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'quote', 'Uklonjen netočno pripisan citat.')`, [corr.id, v2]));

      const retr = await f.article({ quotes: [mRetr] });
      await f.reach(retr.id, 'published');
      await ed((d) => d.query(`SELECT vijesti.retract_article($1, 'Govornik je osporio kontekst.')`, [retr.id]));
      const storyOf = async (id: number) =>
        Number((await f.one<{ s: number | string }>('SELECT story_id AS s FROM vijesti.articles WHERE id = $1', [id])).s);
      return {
        states,
        publicArticles: [pub.id, corr.id, retr.id].sort((a, b) => a - b),
        publicVersions: [pub.v1, v2].sort((a, b) => a - b),
        publicMoments: [mPub, mKeep].sort((a, b) => a - b),
        publicStories: (await Promise.all([pub.id, corr.id, retr.id].map(storyOf))).sort((a, b) => a - b),
        replaced: corr.v1,
        corrected: corr.id,
        retracted: retr.id,
      };
    };
    const ids = (rows: { id: number | string }[]) => rows.map((r) => Number(r.id)).sort((a, b) => a - b);

    it('svaka relacija sheme, kao anon i kao prijavljeni bez uloge: točno javni retci ili zabrana', async () => {
      const w = await world();
      const PUBLIC_VERSION_COLS = 'id, article_id, version, title, body, lead, category, content, word_count, prompt_version, created_at';
      const PUBLIC_MOMENT_COLS =
        'id, video_id, start_ms, end_ms, speaker, speaker_name, quote, quote_check, quote_match, quote_lang, topics, entities, cue_from, cue_to, created_at';
      type Check = (d: SqlDb, who: string | null) => Promise<void>;
      const hidden =
        (rel: string): Check =>
        async (d, who) => {
          if (who === null) {
            await deniedIn(d, `SELECT * FROM vijesti.${rel}`);
          } else {
            expect((await d.query(`SELECT * FROM vijesti.${rel}`)).rows, rel).toEqual([]);
          }
        };
      const checks: Record<string, Check> = {
        articles: async (d) => {
          expect(ids((await d.query<{ id: number | string }>('SELECT * FROM vijesti.articles')).rows)).toEqual(w.publicArticles);
        },
        article_versions: async (d) => {
          await deniedIn(d, 'SELECT * FROM vijesti.article_versions');
          for (const col of ['verify', 'run_id', 'created_by']) {
            await deniedIn(d, `SELECT ${col} FROM vijesti.article_versions`);
          }
          expect(ids((await d.query<{ id: number | string }>(`SELECT ${PUBLIC_VERSION_COLS} FROM vijesti.article_versions`)).rows)).toEqual(
            w.publicVersions,
          );
        },
        public_article_versions: async (d) => {
          expect(ids((await d.query<{ id: number | string }>('SELECT * FROM vijesti.public_article_versions')).rows)).toEqual(
            w.publicVersions,
          );
        },
        article_sources: async (d) => {
          const rows = (await d.query<{ version_id: number | string }>('SELECT * FROM vijesti.article_sources')).rows;
          expect([...new Set(rows.map((r) => Number(r.version_id)))].sort((a, b) => a - b)).toEqual(w.publicVersions);
        },
        moments: async (d) => {
          await deniedIn(d, 'SELECT * FROM vijesti.moments');
          for (const col of ['run_id', 'score_run_id', 'score', 'score_reasons', 'score_parts', 'claim', 'reject_reason']) {
            await deniedIn(d, `SELECT ${col} FROM vijesti.moments`);
          }
          expect(ids((await d.query<{ id: number | string }>(`SELECT ${PUBLIC_MOMENT_COLS} FROM vijesti.moments`)).rows)).toEqual(
            w.publicMoments,
          );
        },
        public_moments: async (d) => {
          expect(ids((await d.query<{ id: number | string }>('SELECT * FROM vijesti.public_moments')).rows)).toEqual(w.publicMoments);
        },
        stories: async (d) => {
          await deniedIn(d, 'SELECT title FROM vijesti.stories');
          expect(ids((await d.query<{ id: number | string }>('SELECT id, slug FROM vijesti.stories')).rows)).toEqual(w.publicStories);
        },
        public_stories: async (d) => {
          expect(ids((await d.query<{ id: number | string }>('SELECT * FROM vijesti.public_stories')).rows)).toEqual(w.publicStories);
        },
        corrections: async (d) => {
          await deniedIn(d, 'SELECT * FROM vijesti.corrections');
          await deniedIn(d, 'SELECT created_by FROM vijesti.corrections');
          await deniedIn(d, 'SELECT replaced_version_id FROM vijesti.corrections');
        },
        public_corrections: async (d) => {
          const rows = (await d.query<{ article_id: number | string; kind: string }>('SELECT * FROM vijesti.public_corrections')).rows;
          expect(rows.map((r) => [Number(r.article_id), r.kind]).sort()).toEqual(
            [
              [w.corrected, 'quote'],
              [w.retracted, 'retraction'],
            ].sort(),
          );
        },
        editor_article_versions: hidden('editor_article_versions'),
        versions_awaiting_verify: hidden('versions_awaiting_verify'),
        runs: hidden('runs'),
        staff: hidden('staff'),
        sentence_resolutions: hidden('sentence_resolutions'),
        article_events: hidden('article_events'),
        article_transitions: hidden('article_transitions'),
        allowed_channels: hidden('allowed_channels'),
        story_moments: hidden('story_moments'),
        eval_channels: hidden('eval_channels'),
        eval_sample: hidden('eval_sample'),
        schema_migrations: async (d) => {
          await deniedIn(d, 'SELECT * FROM vijesti.schema_migrations');
        },
      };
      // Nova tablica ili pogled bez očekivanja ruši test.
      const rels = (
        await db.query<{ r: string }>(
          `SELECT c.relname AS r FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
           WHERE n.nspname = 'vijesti' AND c.relkind IN ('r', 'v', 'm', 'p', 'f') ORDER BY 1`,
        )
      ).rows.map((r) => r.r);
      expect(rels).toEqual(Object.keys(checks).sort());
      for (const who of [null, STRANGER]) {
        for (const [rel, check] of Object.entries(checks)) {
          // Svaka provjera u svojoj transakciji (greška prava je prekida).
          await asUser(db, who, (d) => check(d, who)).catch((e: unknown) => {
            throw new Error(`${rel} (${who ?? 'anon'}): ${String(e)}`);
          });
        }
      }
    });

    it('JOIN, podupit i curava funkcija u WHERE ne zaobilaze RLS ni security_barrier', async () => {
      const w = await world();
      for (const who of [null, STRANGER]) {
        const joined = await asUser(db, who, (d) =>
          d.query<{ id: number | string }>(
            `SELECT v.id FROM vijesti.articles a
             JOIN vijesti.article_versions v ON v.article_id = a.id
             LEFT JOIN vijesti.article_sources s ON s.version_id = v.id
             LEFT JOIN vijesti.moments m ON m.id = s.moment_id
             GROUP BY v.id`,
          ),
        );
        expect(ids(joined.rows)).toEqual(w.publicVersions);
        const sub = await asUser(db, who, (d) =>
          d.query<{ n: number }>(
            `SELECT count(*)::int AS n FROM vijesti.public_article_versions
             WHERE article_id IN (SELECT id FROM vijesti.articles WHERE status = 'draft')
                OR id = $1`,
            [w.replaced],
          ),
        );
        expect(sub.rows[0]?.n).toBe(0);
        // Curava funkcija (nije LEAKPROOF) ne smije vidjeti retke prije filtra politike.
        const fn = `pg_temp.leak_${who === null ? 'anon' : 'auth'}`;
        const leaked = await asUser(db, who, async (d) => {
          await d.exec('CREATE TEMP TABLE leak (t text) ON COMMIT DROP');
          await d.exec(
            `CREATE FUNCTION ${fn}(x text) RETURNS boolean LANGUAGE plpgsql AS
             $f$ BEGIN INSERT INTO pg_temp.leak VALUES (x); RETURN true; END $f$`,
          );
          await d.query(`SELECT id FROM vijesti.article_versions WHERE ${fn}(title)`);
          await d.query(`SELECT id FROM vijesti.moments WHERE ${fn}(quote)`);
          await d.query(`SELECT id FROM vijesti.articles WHERE ${fn}(status)`);
          if (who !== null) {
            await d.query(`SELECT id FROM vijesti.editor_article_versions WHERE ${fn}(verify::text)`);
            await d.query(`SELECT 1 FROM vijesti.versions_awaiting_verify WHERE ${fn}(created_by)`);
            await d.query(`SELECT 1 FROM vijesti.article_events WHERE ${fn}(note)`);
          }
          const out = (await d.query<{ t: string }>('SELECT t FROM pg_temp.leak')).rows.map((r) => r.t);
          await d.exec(`DROP FUNCTION ${fn}(text)`);
          return out;
        });
        expect(leaked).not.toContain('draft');
        expect(leaked).not.toContain('review');
        expect(leaked).not.toContain('Citat iz nacrta.');
        expect(leaked).not.toContain('Citat uklonjen ispravkom.');
        expect(leaked.filter((t) => t.startsWith('{'))).toEqual([]);
        expect(new Set(leaked.filter((t) => t.startsWith('Naslov')))).toEqual(new Set(['Naslov verzije 1', 'Naslov verzije 2']));
      }
    });

    it('anon smije EXECUTE samo current_user_id i has_role; nijedna funkcija nije PUBLIC', async () => {
      const fns = (
        await db.query<{ name: string; types: string[]; trig: boolean; acl: string | null }>(
          `SELECT p.proname AS name,
                  ARRAY(SELECT format_type(t, NULL) FROM unnest(p.proargtypes::oid[]) t) AS types,
                  p.prorettype = 'trigger'::regtype AS trig, p.proacl::text AS acl
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'vijesti' ORDER BY 1`,
        )
      ).rows;
      expect(fns.length).toBeGreaterThan(25);
      const API = [
        'allow_channel',
        'approve_article',
        'correct_article',
        'disallow_channel',
        'publish_article',
        'remove_staff',
        'resolve_sentence',
        'retract_article',
        'save_editor_version',
        'set_staff_role',
        'transition_article',
      ];
      const can = async (role: string) =>
        (
          await db.query<{ name: string }>(
            `SELECT p.proname AS name FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
             WHERE n.nspname = 'vijesti' AND has_function_privilege($1, p.oid, 'EXECUTE') ORDER BY 1`,
            [role],
          )
        ).rows.map((r) => r.name);
      expect(await can('anon')).toEqual(['current_user_id', 'has_role']);
      expect(await can('service_role')).toEqual(['current_user_id', 'has_role']);
      expect(await can('authenticated')).toEqual([...API, 'current_user_id', 'has_role'].sort());
      for (const fn of fns) expect(fn.acl ?? '', fn.name).not.toMatch(/(^|[{,])=X/);

      // I stvarni poziv: svaka funkcija osim dvije javne je zabranjena čitatelju.
      for (const fn of fns.filter((x) => !x.trig)) {
        const args = fn.types.map((t) => `NULL::${t}`).join(', ');
        const p = anon((d) => d.query(`SELECT vijesti.${fn.name}(${args})`));
        if (fn.name === 'current_user_id' || fn.name === 'has_role') {
          await expect(p).resolves.toBeDefined();
        } else {
          await expectDenied(p);
        }
        // Prijavljeni bez uloge: API odbija ulogom, interne funkcije pravom.
        const q = stranger((d) => d.query(`SELECT vijesti.${fn.name}(${args})`));
        if (API.includes(fn.name)) await expectCode(q, 'forbidden');
        else if (fn.name !== 'current_user_id' && fn.name !== 'has_role') await expectDenied(q);
      }
      const r = await anon((d) => d.query<{ r: boolean }>(`SELECT vijesti.has_role('editor') AS r`));
      expect(r.rows[0]?.r).toBe(false);
    });

    it('lažan, prazan ili ne-UUID `sub` nije nitko; neispravan JSON je greška, ne uloga', async () => {
      const { id } = await f.article();
      const fake = [
        '{"sub":""}',
        '{"sub":"nije-uuid"}',
        `{"sub":"' OR 1=1 --"}`,
        `{"sub":"${EDITOR} "}`,
        `{"sub":"${EDITOR}\\n"}`,
        `{"sub":" ${EDITOR}"}`,
        '{"sub":123}',
        `{"sub":{"id":"${EDITOR}"}}`,
        `{"sub":["${EDITOR}"]}`,
        '{"sub":null}',
        '{}',
        '',
        null,
      ];
      for (const claims of fake) {
        for (const role of ['anon', 'authenticated']) {
          const uid = await asClaims(role, claims, (d) => d.query<{ u: string | null }>('SELECT vijesti.current_user_id() AS u'));
          expect(uid.rows[0]?.u, `${role} ${String(claims)}`).toBeNull();
          const seen = await asClaims(role, claims, (d) => d.query('SELECT id FROM vijesti.articles'));
          expect(seen.rows, `${role} ${String(claims)}`).toEqual([]);
          if (role === 'authenticated') {
            await expectCode(
              asClaims(role, claims, (d) => d.query(`SELECT vijesti.transition_article($1, 'review')`, [id])),
              'forbidden',
            );
          }
        }
      }
      await expect(asClaims('authenticated', 'nije json', (d) => d.query('SELECT id FROM vijesti.articles'))).rejects.toThrow(
        /json/i,
      );
      // Isti UUID velikim slovima je isti korisnik (Postgres uuid ne razlikuje veličinu).
      const upper = await asClaims('authenticated', JSON.stringify({ sub: EDITOR.toUpperCase() }), (d) =>
        d.query<{ r: boolean }>(`SELECT vijesti.has_role('editor') AS r`),
      );
      expect(upper.rows[0]?.r).toBe(true);
      expect(await f.status(id)).toBe('draft');
    });
  });

  describe('3. ispravak ostavlja trag', () => {
    const corrected = async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat.');
      const a = await f.article({ quotes: [m] });
      await f.reach(a.id, 'published');
      const v2 = await f.addVersion(a.id, { quotes: [m], unsupported: [2] });
      await ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'no_claim', 'Rečenica ne iznosi činjenicu.')`, [v2]));
      const cid = Number(
        (
          await ed((d) =>
            d.query<{ r: number | string }>(`SELECT vijesti.correct_article($1, $2, 'fact', 'Ispravljen datum.') AS r`, [a.id, v2]),
          )
        ).rows[0]?.r,
      );
      return { ...a, v2, cid };
    };

    it('redak (tko, što, zašto, kada), dnevnik i stara verzija ostaju', async () => {
      const { id, v1, v2, cid } = await corrected();
      const c = await f.one<{
        article_id: number | string;
        version_id: number | string;
        replaced_version_id: number | string;
        kind: string;
        description: string;
        created_by: string;
        created_at: Date | null;
      }>('SELECT * FROM vijesti.corrections WHERE id = $1', [cid]);
      expect(c).toMatchObject({ kind: 'fact', description: 'Ispravljen datum.', created_by: `editor:${EDITOR}` });
      expect([Number(c.article_id), Number(c.version_id), Number(c.replaced_version_id)]).toEqual([id, v2, v1]);
      expect(c.created_at).not.toBeNull();
      const ev = await f.one<{ actor: string; note: string; version_id: number | string }>(
        `SELECT actor, note, version_id FROM vijesti.article_events WHERE article_id = $1 AND to_status = 'corrected'`,
        [id],
      );
      expect([ev.actor, ev.note, Number(ev.version_id)]).toEqual([EDITOR, 'Ispravljen datum.', v2]);
      expect((await db.query('SELECT 1 FROM vijesti.article_versions WHERE id = $1', [v1])).rows).toHaveLength(1);
    });

    it('trag se ne mijenja ni ne briše: vlasnik, service_role, urednik, admin', async () => {
      const { v1, v2, cid } = await corrected();
      const writes = [
        `UPDATE vijesti.corrections SET description = 'Prepisano.' WHERE id = ${String(cid)}`,
        `UPDATE vijesti.corrections SET created_by = NULL WHERE id = ${String(cid)}`,
        `UPDATE vijesti.corrections SET version_id = NULL WHERE id = ${String(cid)}`,
        `DELETE FROM vijesti.corrections WHERE id = ${String(cid)}`,
        `UPDATE vijesti.sentence_resolutions SET note = 'Prepisano.' WHERE version_id = ${String(v2)}`,
        `DELETE FROM vijesti.sentence_resolutions WHERE version_id = ${String(v2)}`,
      ];
      for (const sql of writes) {
        await expectCode(db.query(sql), 'append_only');
        await expectCode(asService((d) => d.query(sql)), 'append_only');
        await expectDenied(ed((d) => d.query(sql)));
        await expectDenied(admin((d) => d.query(sql)));
      }
      await expectCode(db.query('TRUNCATE vijesti.corrections'), 'append_only');
      await expectCode(db.query('TRUNCATE vijesti.sentence_resolutions'), 'append_only');
      // Stara verzija: ne mijenja se i ne briše (FK ispravka i dnevnika).
      await expectCode(db.query(`UPDATE vijesti.article_versions SET body = 'Prepisano.' WHERE id = $1`, [v1]), 'immutable');
      await expect(db.query('DELETE FROM vijesti.article_versions WHERE id = $1', [v1])).rejects.toThrow(/foreign key/);
      // Verzija ispravka: FK `version_id → SET NULL` bi bio UPDATE traga, pa ga odbija okidač.
      await expect(db.query('DELETE FROM vijesti.article_versions WHERE id = $1', [v2])).rejects.toThrow(
        /foreign key|append_only/,
      );
      const left = await f.one<{ n: number }>('SELECT count(*)::int AS n FROM vijesti.corrections WHERE id = $1', [cid]);
      expect(left.n).toBe(1);
    });

    it('iznimka 505/521: brisanje cijelog članka (vlasnik) nosi i trag', async () => {
      const { id } = await corrected();
      await db.query('DELETE FROM vijesti.articles WHERE id = $1', [id]);
      for (const t of ['corrections', 'article_events', 'article_versions']) {
        const n = await f.one<{ n: number }>(`SELECT count(*)::int AS n FROM vijesti.${t} WHERE article_id = $1`, [id]);
        expect(n.n, t).toBe(0);
      }
      expect((await f.one<{ n: number }>('SELECT count(*)::int AS n FROM vijesti.sentence_resolutions')).n).toBe(0);
    });

    it('objavljena verzija se ne mijenja tiho: bez zapisa ispravka ni vlasnik ni engine', async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat.');
      const a = await f.article({ quotes: [m] });
      const other = await f.article({ quotes: [m] });
      await f.reach(a.id, 'published');
      const v2 = await f.addVersion(a.id, { verified: false });
      const attempts: [string, unknown[]][] = [
        ['UPDATE vijesti.articles SET published_version_id = $2 WHERE id = $1', [a.id, v2]],
        ['UPDATE vijesti.articles SET published_version_id = NULL WHERE id = $1', [a.id]],
        [`UPDATE vijesti.articles SET status = 'corrected', published_version_id = $2 WHERE id = $1`, [a.id, v2]],
        [`UPDATE vijesti.articles SET status = 'corrected' WHERE id = $1`, [a.id]],
        [`UPDATE vijesti.articles SET status = 'retracted' WHERE id = $1`, [a.id]],
        ['UPDATE vijesti.articles SET approved_version_id = $2 WHERE id = $1', [a.id, v2]],
      ];
      for (const [sql, params] of attempts) {
        await expectCode(db.query(sql, params), 'invalid_state');
        await expectCode(asService((d) => d.query(sql, params)), 'invalid_state');
      }
      // Verzija drugog članka: okidač ili složeni FK.
      await expect(
        db.query('UPDATE vijesti.articles SET published_version_id = $2 WHERE id = $1', [a.id, other.v1]),
      ).rejects.toThrow(/invalid_state|articles_published_version_fkey/);
      // Prva objava samo odobrene verzije odobrenog članka.
      const b = await f.article();
      const bv2 = await f.addVersion(b.id);
      await f.reach(b.id, 'review');
      await db.query(`UPDATE vijesti.articles SET status = 'approved', approved_version_id = $2 WHERE id = $1`, [b.id, bv2]);
      await expectCode(
        db.query(`UPDATE vijesti.articles SET status = 'published', published_version_id = $2 WHERE id = $1`, [b.id, b.v1]),
        'invalid_state',
      );
      await expectCode(
        db.query(`UPDATE vijesti.articles SET published_version_id = $2 WHERE id = $1`, [b.id, bv2]).then(() =>
          db.query(`UPDATE vijesti.articles SET status = 'review', published_version_id = NULL WHERE id = $1`, [b.id]),
        ),
        'invalid_state',
      );
      expect(await f.status(a.id)).toBe('published');
      const pv = await f.one<{ p: number | string }>('SELECT published_version_id AS p FROM vijesti.articles WHERE id = $1', [a.id]);
      expect(Number(pv.p)).toBe(a.v1);
    });
  });

  describe('4. članak nastaje samo kao nacrt', () => {
    it('INSERT sa stanjem, verzijom ili datumom objave odbija okidač (vlasnik i service_role); nepoznato stanje CHECK', async () => {
      const s = await f.one<{ id: number | string }>(`INSERT INTO vijesti.stories (slug, title) VALUES ('s', 'S') RETURNING id`);
      const bad = [
        `status = 'published'`,
        `status = 'review'`,
        `status = 'approved'`,
        `status = 'corrected'`,
        `status = 'retracted'`,
        `status = 'rejected'`,
        `published_at = now()`,
      ];
      for (const [i, col] of bad.entries()) {
        const [k, v] = col.split(' = ') as [string, string];
        const sql = `INSERT INTO vijesti.articles (story_id, format, slug, ${k}) VALUES ($1, 'vijest', 'x${String(i)}', ${v})`;
        await expectCode(db.query(sql, [s.id]), 'invalid_state');
        await expectCode(asService((d) => d.query(sql, [s.id])), 'invalid_state');
      }
      // Preko ON CONFLICT DO UPDATE ide okidač UPDATE-a.
      const a = await f.article();
      await expectCode(
        db.query(
          `INSERT INTO vijesti.articles (story_id, format, lang, slug)
           SELECT story_id, format, lang, 'drugi' FROM vijesti.articles WHERE id = $1
           ON CONFLICT (story_id, format, lang) DO UPDATE SET status = 'published'`,
          [a.id],
        ),
        'invalid_transition',
      );
      await expect(
        db.query(`INSERT INTO vijesti.articles (story_id, format, slug, status) VALUES ($1, 'v', 'y', 'objavljen')`, [s.id]),
      ).rejects.toThrow(/articles_status_check/);
      await db.query(`INSERT INTO vijesti.articles (story_id, format, slug) VALUES ($1, 'vijest', 'nacrt')`, [s.id]);
    });

    it('engine (saveArticleVersion) i dalje radi: novi članak, druga verzija, objavljen članak, kao service_role', async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat za engine.');
      const content: ArticleContent = {
        schema: CONTENT_SCHEMA,
        episode: { videoId: VIDEO, title: 'E', channel: CH, channelName: 'K', date: null, lang: 'hr', speakers: [] },
        title: 'Engine naslov',
        lead: 'Lead.',
        category: 'drustvo',
        blocks: [{ type: 'quote', moment_id: m, ref: 't1' }],
      };
      const nv = {
        videoId: VIDEO,
        title: 'Engine naslov',
        lead: 'Lead.',
        body: 'Tijelo.',
        category: 'drustvo',
        content,
        wordCount: 3,
        promptVersion: 'write-vijest/1',
        runId: null,
        createdBy: 'engine:write',
        sources: [{ momentId: m, position: 1 }],
      };
      const s1 = await saveArticleVersion(db, nv);
      const s2 = await saveArticleVersion(db, { ...nv, verify: { base_version: 1, sentences: [] }, createdBy: 'engine:verify' });
      expect([s2.articleId, s2.version]).toEqual([s1.articleId, 2]);
      await f.reach(s1.articleId, 'published');
      await db.exec('SET ROLE service_role');
      try {
        const s3 = await saveArticleVersion(db, { ...nv, createdBy: 'engine:write' });
        expect([s3.articleId, s3.version]).toEqual([s1.articleId, 3]);
        const queue = await db.query<{ version_id: number | string }>('SELECT version_id FROM vijesti.versions_awaiting_verify');
        expect(queue.rows.map((r) => Number(r.version_id))).toEqual([s3.versionId]);
      } finally {
        await db.exec('RESET ROLE');
      }
      expect(await f.status(s1.articleId)).toBe('published');
    });
  });

  describe('5. eskalacija uloga', () => {
    it('urednik ne dira uloge ni kanale; bez uloge nema pisanja; zadnji admin ostaje', async () => {
      for (const sql of [
        `SELECT vijesti.set_staff_role('${EDITOR}', 'admin')`,
        `SELECT vijesti.set_staff_role('${STRANGER}', 'admin')`,
        `SELECT vijesti.set_staff_role('${STRANGER}', 'editor')`,
        `SELECT vijesti.remove_staff('${ADMIN}')`,
        `SELECT vijesti.allow_channel('tudji_kanal')`,
        `SELECT vijesti.disallow_channel('${CH}')`,
      ]) {
        await expectCode(ed((d) => d.query(sql)), 'forbidden');
        await expectCode(stranger((d) => d.query(sql)), 'forbidden');
      }
      for (const sql of [
        `INSERT INTO vijesti.staff (user_id, role) VALUES ('${EDITOR}', 'admin')`,
        `UPDATE vijesti.staff SET role = 'admin' WHERE user_id = '${EDITOR}'`,
        `INSERT INTO vijesti.allowed_channels (channel) VALUES ('tudji_kanal')`,
        `DELETE FROM vijesti.staff WHERE user_id = '${ADMIN}'`,
      ]) {
        await expectDenied(ed((d) => d.query(sql)));
        await expectDenied(stranger((d) => d.query(sql)));
        await expectDenied(admin((d) => d.query(sql)));
      }
      const roles = await db.query<{ user_id: string; role: string }>('SELECT user_id, role FROM vijesti.staff ORDER BY role');
      expect(roles.rows).toEqual([
        { user_id: ADMIN, role: 'admin' },
        { user_id: EDITOR, role: 'editor' },
      ]);
      expect((await db.query('SELECT channel FROM vijesti.allowed_channels')).rows).toEqual([{ channel: CH }]);

      await expectCode(admin((d) => d.query(`SELECT vijesti.remove_staff($1)`, [ADMIN])), 'last_admin');
      await expectCode(admin((d) => d.query(`SELECT vijesti.set_staff_role($1, 'editor')`, [ADMIN])), 'last_admin');
      await admin((d) => d.query(`SELECT vijesti.set_staff_role($1, 'admin')`, [EDITOR2]));
      await asUser(db, EDITOR2, (d) => d.query(`SELECT vijesti.remove_staff($1)`, [ADMIN]));
      await expectCode(asUser(db, EDITOR2, (d) => d.query(`SELECT vijesti.remove_staff($1)`, [EDITOR2])), 'last_admin');
      await expectCode(admin((d) => d.query(`SELECT vijesti.set_staff_role($1, 'admin')`, [ADMIN])), 'forbidden');
    });

    it('privremena tablica `staff` i search_path ne daju ulogu (search_path je fiksiran)', async () => {
      const r = await stranger(async (d) => {
        await d.exec('CREATE TEMP TABLE staff (user_id uuid, role text) ON COMMIT DROP');
        await d.query(`INSERT INTO pg_temp.staff VALUES ($1, 'admin')`, [STRANGER]);
        await d.exec('SET LOCAL search_path = pg_temp, vijesti, public');
        const own = await d.query<{ r: boolean }>(`SELECT vijesti.has_role('admin') AS r`);
        const err = await errorOf(d.query(`SELECT vijesti.set_staff_role($1, 'admin')`, [STRANGER]));
        return { own: own.rows[0]?.r, err };
      }).catch((e: unknown) => ({ own: undefined, err: e }));
      expect(r.own).not.toBe(true);
      expect(parseEditorialError(r.err)?.code ?? String(r.err)).toMatch(/forbidden/);
      expect((await db.query('SELECT 1 FROM vijesti.staff WHERE user_id = $1', [STRANGER])).rows).toHaveLength(0);
    });

    it('service_role (engine) piše što treba, ali ne zaobilazi okidače', async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat.');
      const { id } = await asService(async () => f.article({ quotes: [m] }));
      await asService((d) => d.query(`UPDATE vijesti.articles SET status = 'review' WHERE id = $1`, [id]));
      await asService((d) => d.query(`UPDATE vijesti.moments SET speaker_name = 'Ana Anić' WHERE id = $1`, [m]));
      await expectCode(
        asService((d) => d.query(`UPDATE vijesti.articles SET status = 'published' WHERE id = $1`, [id])),
        'invalid_transition',
      );
      await expectCode(asService((d) => d.query('DELETE FROM vijesti.article_events')), 'append_only');
      await expectCode(asService((d) => d.query(`UPDATE vijesti.article_versions SET title = 'X'`)), 'immutable');
      const ev = await f.one<{ label: string }>(
        `SELECT actor_label AS label FROM vijesti.article_events WHERE article_id = $1 ORDER BY id DESC LIMIT 1`,
        [id],
      );
      expect(ev.label).toBe('db:service_role');
    });
  });

  describe('6. utrke i zastarjelost', () => {
    it('zastarjela, tuđa ili nepostojeća verzija i tuđi trenutak se odbijaju', async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat.');
      const foreign = await f.moment(OTHER_VIDEO, 1000, 'Tuđi citat.');
      const failed = await f.moment(VIDEO, 9000, 'Odbačen.', true);
      const a = await f.article({ quotes: [m] });
      const b = await f.article({ quotes: [m] });
      const v2 = await f.addVersion(a.id, { unsupported: [2] });
      await f.reach(a.id, 'review');
      for (const v of [a.v1, b.v1, 0]) {
        await expectCode(ed((d) => d.query('SELECT vijesti.approve_article($1, $2)', [a.id, v])), 'stale_version');
      }
      await expectCode(ed((d) => d.query('SELECT vijesti.approve_article($1, NULL)', [a.id])), 'stale_version');
      await expectCode(ed((d) => d.query('SELECT vijesti.approve_article($1, $2)', [a.id, v2])), 'unresolved');
      // Razrješenje: nepostojeća, stara, tuđa (zadnja svog članka, ali tuđa rečenica) verzija.
      await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence(999999, 2, 'verified', 'Bilješka.')`)), 'not_found');
      await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'verified', 'Bilješka.')`, [a.v1])), 'stale_version');
      await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'verified', 'Bilješka.')`, [b.v1])), 'invalid_input');
      await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 1, 'verified', 'Bilješka.')`, [v2])), 'invalid_input');
      await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'odobreno', 'Bilješka.')`, [v2])), 'invalid_input');
      await ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'verified', 'Bilješka.')`, [v2]));
      // Engine doda verziju između čitanja i odobravanja.
      const v3 = await f.addVersion(a.id);
      await expectCode(ed((d) => d.query('SELECT vijesti.approve_article($1, $2)', [a.id, v2])), 'stale_version');
      await ed((d) => d.query('SELECT vijesti.approve_article($1, $2)', [a.id, v3]));
      // Urednička verzija: tuđa epizoda, odbačen citat, neispravan id, zastarjela baza.
      const save = (base: number, blocks: unknown) =>
        ed((d) =>
          d.query(`SELECT vijesti.save_editor_version($1, $2, 'Naslov', 'Lead.', 'drustvo', $3::jsonb)`, [
            a.id,
            base,
            JSON.stringify(blocks),
          ]),
        );
      await expectCode(save(v3, [{ type: 'quote', moment_id: foreign }]), 'invalid_quote');
      await expectCode(save(v3, [{ type: 'quote', moment_id: failed }]), 'invalid_quote');
      await expectCode(save(v3, [{ type: 'quote', moment_id: String(m) }]), 'invalid_input');
      await expectCode(save(v3, [{ type: 'quote', moment_id: m + 0.5 }]), 'invalid_input');
      await expectCode(save(v3, [{ type: 'quote', moment_id: -m }]), 'invalid_input');
      await expectCode(save(v3, [{ type: 'p', text: '   ' }]), 'invalid_input');
      await expectCode(save(v3, [{ type: 'html', text: '<script>' }]), 'invalid_input');
      await expectCode(save(v3, { type: 'p', text: 'Nije niz.' }), 'invalid_input');
      await expectCode(save(v2, [{ type: 'p', text: 'Stara baza.' }]), 'stale_version');
      await expectCode(save(b.v1, [{ type: 'p', text: 'Tuđa baza.' }]), 'stale_version');
      expect(await f.status(a.id)).toBe('approved');
      // Ispravak tuđom ili zastarjelom verzijom.
      await f.apply(a.id, 'published');
      const v4 = await f.addVersion(a.id);
      await expectCode(ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'fact', 'Opis.')`, [a.id, b.v1])), 'stale_version');
      await expectCode(ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'fact', 'Opis.')`, [a.id, v3])), 'stale_version');
      await expectCode(
        ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'retraction', 'Opis.')`, [a.id, v4])),
        'invalid_input',
      );
      // `published_version_id` / `approved_version_id` na verziju drugog članka: složeni FK.
      await expect(
        db.query('UPDATE vijesti.articles SET published_version_id = $2 WHERE id = $1', [a.id, b.v1]),
      ).rejects.toThrow(/invalid_state|articles_published_version_fkey/);
      await f.reach(b.id, 'review');
      await expect(
        db.query('UPDATE vijesti.articles SET approved_version_id = $2 WHERE id = $1', [b.id, a.v1]),
      ).rejects.toThrow(/articles_approved_version_fkey/);
    });
  });

  describe('7. SQL injection i search_path', () => {
    it('tekstualni argumenti se spremaju doslovno; prazno (i tab, NBSP, zero-width) nije obrazloženje', async () => {
      const m = await f.moment(VIDEO, 1000, 'Citat.');
      const a = await f.article({ quotes: [m] });
      await ed((d) => d.query('SELECT vijesti.transition_article($1, $2, $3)', [a.id, 'review', INJECTION]));
      await expectCode(
        ed((d) => d.query('SELECT vijesti.transition_article($1, $2, NULL)', [a.id, `draft' OR '1'='1`])),
        'invalid_input',
      );
      for (const blank of ['\t', '\n\n', ' ', '​', '  \t ', '—', '…']) {
        await expectCode(ed((d) => d.query(`SELECT vijesti.transition_article($1, 'rejected', $2)`, [a.id, blank])), 'invalid_input');
      }
      await f.reach(a.id, 'review');
      await f.apply(a.id, 'approved');
      await f.apply(a.id, 'published');
      const v2 = await f.addVersion(a.id, { unsupported: [2] });
      for (const blank of ['\t', ' ']) {
        await expectCode(ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'verified', $2)`, [v2, blank])), 'invalid_input');
        await expectCode(ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'fact', $3)`, [a.id, v2, blank])), 'invalid_input');
        await expectCode(ed((d) => d.query(`SELECT vijesti.retract_article($1, $2)`, [a.id, blank])), 'invalid_input');
      }
      await ed((d) => d.query(`SELECT vijesti.resolve_sentence($1, 2, 'verified', $2)`, [v2, INJECTION]));
      await ed((d) => d.query(`SELECT vijesti.correct_article($1, $2, 'fact', $3)`, [a.id, v2, INJECTION]));
      await admin((d) => d.query('SELECT vijesti.allow_channel($1, $2)', [`kanal'); DROP TABLE vijesti.staff; --`, INJECTION]));

      const stored = await f.one<{ e: string; c: string; r: string; n: string }>(
        `SELECT (SELECT note FROM vijesti.article_events WHERE article_id = $1 AND to_status = 'review') AS e,
                (SELECT description FROM vijesti.corrections WHERE article_id = $1) AS c,
                (SELECT note FROM vijesti.sentence_resolutions WHERE version_id = $2) AS r,
                (SELECT note FROM vijesti.allowed_channels WHERE channel LIKE 'kanal''%') AS n`,
        [a.id, v2],
      );
      expect(stored).toEqual({ e: INJECTION, c: INJECTION, r: INJECTION, n: INJECTION });
      expect((await f.one<{ n: number }>('SELECT count(*)::int AS n FROM vijesti.staff')).n).toBe(2);
      expect(await f.status(a.id)).toBe('corrected');
    });

    it('svaka funkcija sheme ima search_path = vijesti, pg_temp; nijedna ne gradi SQL dinamički; nitko ne stvara u shemi', async () => {
      const fns = (
        await db.query<{ name: string; secdef: boolean; config: string[] | null; src: string }>(
          `SELECT p.proname AS name, p.prosecdef AS secdef, p.proconfig AS config, p.prosrc AS src
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'vijesti' ORDER BY 1`,
        )
      ).rows;
      expect(fns.filter((x) => x.secdef).length).toBeGreaterThan(15);
      for (const fn of fns) {
        expect(fn.config, fn.name).toEqual(['search_path=vijesti, pg_temp']);
        expect(fn.src, fn.name).not.toMatch(/\bEXECUTE\b|\bformat\s*\(|quote_ident|quote_literal/i);
      }
      for (const role of ['anon', 'authenticated', 'service_role', 'public']) {
        const r = await f.one<{ c: boolean }>(`SELECT has_schema_privilege($1, 'vijesti', 'CREATE') AS c`, [role]);
        expect(r.c, role).toBe(false);
      }
    });
  });
});

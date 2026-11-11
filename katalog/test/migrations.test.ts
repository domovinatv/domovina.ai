import { env } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import {
  allChannels,
  catalogContext,
  channelBySlug,
  channelDirectory,
  channelEpisodes,
  episodeCard,
  episodeIds,
  episodesOnDay,
  existingChannelSlugs,
  latestEpisodes,
  MAX_PAGE_SIZE,
  prepare,
  type SqlQuery,
} from "../src/db/queries.js";

const BRAND = "plan";

interface PlanRow {
  detail: string;
}

async function queryPlan(query: SqlQuery): Promise<string[]> {
  const { results } = await env.DB.prepare(`EXPLAIN QUERY PLAN ${query.sql}`)
    .bind(...query.params)
    .all<PlanRow>();
  return results.map((r) => r.detail);
}

function day(i: number): string {
  return new Date(Date.UTC(2026, 0, 1 + i)).toISOString().slice(0, 10);
}

// 40 dana × 10 epizoda u 4 kanala + kanali u oba tiera. Dovoljno da planer
// ima statistiku i da `rows_read` pokaže razliku između raspona i skena.
beforeAll(async () => {
  const now = "2026-11-05T12:00:00Z";
  const stmts: D1PreparedStatement[] = [
    env.DB.prepare("INSERT INTO brands (id, host) VALUES (?1, ?2)").bind(BRAND, "plan.test"),
  ];
  for (let c = 0; c < 4; c++) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar,
           processed_count, latest_published_date)
         VALUES (?1, ?2, NULL, ?3, ?4, 'hr', NULL, 100, ?5)`,
      ).bind(BRAND, `kanal_${c}`, `Kanal ${c}`, c < 2 ? 1 : 2, day(39 - c)),
    );
  }
  for (let d = 0; d < 40; d++) {
    for (let e = 0; e < 10; e++) {
      stmts.push(
        env.DB.prepare(
          `INSERT INTO episodes (brand, id, channel_slug, title, title_hr, published_date,
             duration_seconds, tier, lang, magisterium_score, flags, updated_at)
           VALUES (?1, ?2, ?3, ?4, NULL, ?5, 3600, 1, 'hr', NULL, 511, ?6)`,
        ).bind(BRAND, `ep_${d}_${e}`, `kanal_${e % 4}`, `Epizoda ${d}/${e}`, day(d), now),
      );
    }
  }
  await env.DB.batch(stmts);
});

const PAGE = 20;
const cursor = { publishedDate: day(20), id: "ep_20_5" };

// Svaki upit kartice: raspon indeksa epizoda + kanal po PK u LEFT JOIN-u.
const JOIN = /^SEARCH c USING PRIMARY KEY \(brand=\? AND slug=\?\) LEFT-JOIN$/m;
const on = (table: string, index: string) => new RegExp(`^SEARCH ${table} USING (COVERING )?INDEX ${index} \\(`, "m");
const chCursor = { latestPublishedDate: day(39), slug: "kanal_0" };

const cases: { name: string; query: SqlQuery; plan: RegExp[] }[] = [
  { name: "najnovije, prva stranica", query: latestEpisodes(BRAND, PAGE), plan: [on("e", "episodes_by_date"), JOIN] },
  { name: "najnovije, iza kursora", query: latestEpisodes(BRAND, PAGE, cursor), plan: [on("e", "episodes_by_date"), JOIN] },
  { name: "dan, prva stranica", query: episodesOnDay(BRAND, day(20), PAGE), plan: [on("e", "episodes_by_date"), JOIN] },
  { name: "dan, iza kursora", query: episodesOnDay(BRAND, day(20), PAGE, "ep_20_5"), plan: [on("e", "episodes_by_date"), JOIN] },
  { name: "kanal, prva stranica", query: channelEpisodes(BRAND, "kanal_1", PAGE), plan: [on("e", "episodes_by_channel"), JOIN] },
  { name: "kanal, iza kursora", query: channelEpisodes(BRAND, "kanal_1", PAGE, cursor), plan: [on("e", "episodes_by_channel"), JOIN] },
  { name: "tier, prva stranica", query: channelDirectory(BRAND, 1, PAGE), plan: [on("channels", "channels_directory")] },
  { name: "tier, iza kursora", query: channelDirectory(BRAND, 1, PAGE, chCursor), plan: [on("channels", "channels_directory")] },
  { name: "svi kanali, prva stranica", query: allChannels(BRAND, PAGE), plan: [on("channels", "channels_all_by_date")] },
  { name: "svi kanali, iza kursora", query: allChannels(BRAND, PAGE, chCursor), plan: [on("channels", "channels_all_by_date")] },
  {
    name: "kartica epizode",
    query: episodeCard(BRAND, "ep_20_5"),
    plan: [/^SEARCH e USING PRIMARY KEY \(brand=\? AND id=\?\)$/m, JOIN],
  },
  {
    name: "zaglavlje kanala",
    query: channelBySlug(BRAND, "kanal_1"),
    plan: [/^SEARCH channels USING PRIMARY KEY \(brand=\? AND slug=\?\)$/m],
  },
  {
    name: "ID-evi epizoda (ingest/ids), prva stranica",
    query: episodeIds(BRAND, 5001),
    plan: [/^SEARCH episodes USING PRIMARY KEY \(brand=\?\)$/m],
  },
  {
    name: "ID-evi epizoda (ingest/ids), iza ID-a",
    query: episodeIds(BRAND, 5001, "ep_20_5"),
    plan: [/^SEARCH episodes USING PRIMARY KEY \(brand=\? AND id>\?\)$/m],
  },
  {
    name: "brend i verzija kataloga",
    query: catalogContext("plan.test", "plan"),
    plan: [
      /^SEARCH brands USING INDEX sqlite_autoindex_brands_2 \(host=\?\)$/m,
      /^SEARCH brands USING PRIMARY KEY \(id=\?\)$/m,
      /^SEARCH ingest_runs USING COVERING INDEX ingest_runs_ok$/m,
    ],
  },
];

describe("migracije", () => {
  it("stvaraju tablice i indekse", async () => {
    const { results } = await env.DB.prepare(
      `SELECT type, name FROM sqlite_schema
       WHERE name NOT LIKE 'sqlite_%' AND name NOT LIKE '_cf_%' AND name != 'd1_migrations'
       ORDER BY type, name`,
    ).all<{ type: string; name: string }>();
    expect(results).toEqual([
      { type: "index", name: "channels_all_by_date" },
      { type: "index", name: "channels_by_uc" },
      { type: "index", name: "channels_directory" },
      { type: "index", name: "episodes_by_channel" },
      { type: "index", name: "episodes_by_date" },
      { type: "index", name: "ingest_runs_ok" },
      { type: "table", name: "brands" },
      { type: "table", name: "channel_settings" },
      { type: "table", name: "channel_tombstones" },
      { type: "table", name: "channels" },
      { type: "table", name: "episodes" },
      { type: "table", name: "ingest_runs" },
      { type: "table", name: "settings_poll_state" },
      { type: "trigger", name: "channel_tombstones_no_delete" },
      { type: "trigger", name: "channel_tombstones_no_update" },
    ]);
  });

  it("D1 podržava row-value usporedbu", async () => {
    const row = await env.DB.prepare("SELECT (2, 'b') < (2, 'c') AS lt, (2, 'b') < (1, 'z') AS gt").first<{
      lt: number;
      gt: number;
    }>();
    expect(row).toEqual({ lt: 1, gt: 0 });
  });
});

describe("EXPLAIN QUERY PLAN", () => {
  it.each(cases)("$name: indeks, bez SCAN i TEMP B-TREE", async ({ query, plan: expected }) => {
    const plan = await queryPlan(query);
    const text = plan.join("\n");
    for (const re of expected) expect(text).toMatch(re);
    // `SCAN CONSTANT ROW` je SELECT bez FROM (upit brenda), ne sken tablice.
    expect(text.replace(/^SCAN CONSTANT ROW$/m, "")).not.toMatch(/\bSCAN\b/);
    expect(text).not.toMatch(/TEMP B-TREE/);
  });

  it("postojeći kanali za ingest: PK po slugu iz json_each, bez TEMP B-TREE", async () => {
    const query = existingChannelSlugs(BRAND, JSON.stringify(["kanal_1", "kanal_3", "nema"]));
    const text = (await queryPlan(query)).join("\n");
    expect(text).toMatch(/SEARCH channels USING PRIMARY KEY \(brand=\? AND slug=\?\)/);
    // Jedini SCAN je nad virtualnom tablicom `json_each` (popis slugova iz batcha).
    expect(text.replace(/^.*SCAN json_each VIRTUAL TABLE.*$/m, "")).not.toMatch(/\bSCAN\b/);
    expect(text).not.toMatch(/TEMP B-TREE/);
    const { results } = await prepare(env.DB, query).all<{ slug: string }>();
    expect(results.map((r) => r.slug).sort()).toEqual(["kanal_1", "kanal_3"]);
    expect(() => episodeIds(BRAND, 5002)).toThrow(RangeError);
  });

  it("row-value kursor je raspon indeksa, ne filtar", async () => {
    const plan = await queryPlan(latestEpisodes(BRAND, PAGE, cursor));
    expect(plan.join("\n")).toContain("(brand=? AND (published_date,id)<(?,?))");
    expect((await queryPlan(allChannels(BRAND, PAGE, chCursor))).join("\n")).toContain(
      "(brand=? AND (latest_published_date,slug)<(?,?))",
    );
  });
});

describe("rows_read je ograničen stranicom", () => {
  it.each(cases)("$name", async ({ query }) => {
    const { results, meta } = await prepare(env.DB, query).all();
    expect(results.length).toBeGreaterThan(0);
    // Indeksni raspon + dohvat retka po PK: najviše dva čitanja po retku
    // stranice i jedno za kraj raspona. Sken tablice bio bi ~400. Kanal u
    // LEFT JOIN-u po PK izmjereno ne povećava rows_read (odluka 301).
    expect(meta.rows_read).toBeLessThanOrEqual(2 * results.length + 1);
  });

  it("varijanta nije u popisima, kartica je vidi", async () => {
    await env.DB.prepare(
      `INSERT INTO episodes (brand, id, channel_slug, title, title_hr, published_date,
         duration_seconds, tier, lang, magisterium_score, flags, updated_at, variant_of)
       VALUES (?1, 'ep_39_9x_1', 'kanal_1', 'Varijanta', NULL, ?2, NULL, 2, NULL, NULL, 0, ?3, 'ep_39_9')`,
    )
      .bind(BRAND, day(39), "2026-11-05T12:00:00Z")
      .run();
    const ids = async (q: SqlQuery) => (await prepare(env.DB, q).all<{ id: string }>()).results.map((r) => r.id);
    expect(await ids(latestEpisodes(BRAND, 100))).not.toContain("ep_39_9x_1");
    expect(await ids(episodesOnDay(BRAND, day(39), 100))).not.toContain("ep_39_9x_1");
    expect(await ids(channelEpisodes(BRAND, "kanal_1", 100))).not.toContain("ep_39_9x_1");
    expect(await ids(episodeCard(BRAND, "ep_39_9x_1"))).toEqual(["ep_39_9x_1"]);
    await expect(
      env.DB.prepare(
        `INSERT INTO episodes (brand, id, channel_slug, title, tier, flags, updated_at, variant_of)
         VALUES (?1, 'prazna_var', NULL, 'X', 2, 0, '2026-11-05T12:00:00Z', '')`,
      )
        .bind(BRAND)
        .run(),
    ).rejects.toThrow(/CHECK/);
  });

  it("kursor nastavlja točno iza zadnjeg retka", async () => {
    const first = await prepare(env.DB, latestEpisodes(BRAND, PAGE)).all<{
      id: string;
      published_date: string;
    }>();
    const last = first.results.at(-1);
    expect(last).toBeDefined();
    if (last === undefined) return;
    const second = await prepare(
      env.DB,
      latestEpisodes(BRAND, PAGE, { publishedDate: last.published_date, id: last.id }),
    ).all<{ id: string }>();
    const all = [...first.results, ...second.results].map((r) => r.id);
    expect(new Set(all).size).toBe(2 * PAGE);
    expect(all.slice(0, 3)).toEqual(["ep_39_9", "ep_39_8", "ep_39_7"]);
    expect(all.slice(PAGE - 1, PAGE + 1)).toEqual(["ep_38_0", "ep_37_9"]);
  });

  it("limit izvan 1–MAX_PAGE_SIZE se odbija", () => {
    expect(() => latestEpisodes(BRAND, 0)).toThrow(RangeError);
    // MAX_PAGE_SIZE + 1 je dopušten: API čita redak više za `next` (odluka 304).
    expect(() => latestEpisodes(BRAND, MAX_PAGE_SIZE + 1)).not.toThrow();
    expect(() => latestEpisodes(BRAND, MAX_PAGE_SIZE + 2)).toThrow(RangeError);
    expect(() => latestEpisodes(BRAND, 1.5)).toThrow(RangeError);
  });
});

describe("ograničenja sheme", () => {
  const now = "2026-11-05T12:00:00Z";

  function insertEpisode(overrides: Record<string, string | number | null>): Promise<D1Result> {
    const row: Record<string, string | number | null> = {
      brand: BRAND,
      id: "constraint_ep",
      channel_slug: null,
      title: "Naslov",
      title_hr: null,
      published_date: "2026-11-05",
      duration_seconds: null,
      tier: 2,
      lang: null,
      magisterium_score: null,
      flags: 0,
      updated_at: now,
      ...overrides,
    };
    const cols = Object.keys(row);
    return env.DB.prepare(
      `INSERT INTO episodes (${cols.join(", ")}) VALUES (${cols.map((_, i) => `?${i + 1}`).join(", ")})`,
    )
      .bind(...Object.values(row))
      .run();
  }

  it("decimalno trajanje ostaje decimalno, NULL kanal i datum su dopušteni", async () => {
    await insertEpisode({ id: "CUJmOc91C64", duration_seconds: 245.295, published_date: null });
    const row = await env.DB.prepare(
      "SELECT duration_seconds, channel_slug, published_date FROM episodes WHERE brand = ?1 AND id = ?2",
    )
      .bind(BRAND, "CUJmOc91C64")
      .first();
    expect(row).toEqual({ duration_seconds: 245.295, channel_slug: null, published_date: null });
  });

  it("cijelo trajanje se sprema kao REAL", async () => {
    await insertEpisode({ id: "int_duration", duration_seconds: 3600 });
    const row = await env.DB.prepare(
      "SELECT typeof(duration_seconds) AS t FROM episodes WHERE brand = ?1 AND id = ?2",
    )
      .bind(BRAND, "int_duration")
      .first<{ t: string }>();
    expect(row?.t).toBe("real");
  });

  it.each([
    ["tier izvan 1–2", { id: "c1", tier: 3 }],
    ["nepostojeći datum", { id: "c2", published_date: "2026-02-30" }],
    ["datum u YYYYMMDD obliku", { id: "c3", published_date: "20261105" }],
    ["flags izvan 9 bitova", { id: "c4", flags: 512 }],
    ["negativno trajanje", { id: "c5", duration_seconds: -1 }],
    ["magisterium_score izvan 0–100", { id: "c6", magisterium_score: 101 }],
    ["decimalni magisterium_score", { id: "c7", magisterium_score: 77.5 }],
    ["tekst u REAL stupcu (STRICT; CHECK bi ga propustio)", { id: "c8", duration_seconds: "dugo" }],
    ["kanal koji ne postoji (strani ključ)", { id: "c9", channel_slug: "nema_ga" }],
    ["prazan ID", { id: "" }],
    ["updated_at koji nije vrijeme", { id: "c10", updated_at: "jučer" }],
  ])("odbija: %s", async (_name, overrides) => {
    await expect(insertEpisode(overrides)).rejects.toThrow(/constraint|cannot store/i);
  });

  it("youtube_channel_id nije jedinstven", async () => {
    const insert = (slug: string) =>
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar,
           processed_count, latest_published_date)
         VALUES (?1, ?2, 'UCuk9D5H9mx7birJ1-S22nyQ', ?2, 1, NULL, NULL, 0, NULL)`,
      )
        .bind(BRAND, slug)
        .run();
    await insert("slijedi_svoj_poziv_1");
    await expect(insert("slijedi_svoj_poziv_2")).resolves.toBeDefined();
  });

  it("ingest_runs: završen run mora imati finished_at, counts mora biti JSON objekt", async () => {
    const insert = (finished: string | null, status: string, counts: string | null) =>
      env.DB.prepare(
        "INSERT INTO ingest_runs (started_at, finished_at, source, counts, status) VALUES (?1, ?2, 'test', ?3, ?4)",
      )
        .bind(now, finished, counts, status)
        .run();
    await expect(insert(null, "running", null)).resolves.toBeDefined();
    await expect(insert("2026-11-05T12:05:00Z", "ok", '{"episodes":3}')).resolves.toBeDefined();
    await expect(insert(null, "ok", null)).rejects.toThrow(/constraint/i);
    await expect(insert("2026-11-05T12:05:00Z", "running", null)).rejects.toThrow(/constraint/i);
    await expect(insert("2026-11-05T11:00:00Z", "failed", null)).rejects.toThrow(/constraint/i);
    await expect(insert("2026-11-05T12:05:00Z", "ok", "[1,2]")).rejects.toThrow(/constraint/i);
  });

  it("channel_settings: effective je JSON objekt, vremena su valjana (i s mikrosekundama iz PostgRESTa)", async () => {
    const insert = (uc: string, effective: string, at: string) =>
      env.DB.prepare(
        "INSERT INTO channel_settings (youtube_channel_id, effective, source_updated_at, synced_at) VALUES (?1, ?2, ?3, ?3)",
      )
        .bind(uc, effective, at)
        .run();
    await expect(insert("UCmig1", '{"ebook":false}', "2026-11-11T19:07:01.651675+00:00")).resolves.toBeDefined();
    await expect(insert("UCmig2", "[false]", now)).rejects.toThrow(/constraint/i);
    await expect(insert("UCmig3", "nije json", now)).rejects.toThrow(/constraint/i);
    await expect(insert("UCmig4", "{}", "jučer")).rejects.toThrow(/constraint/i);
    await expect(insert("", "{}", now)).rejects.toThrow(/constraint/i);
  });

  it("channel_tombstones: slugs je JSON polje; UPDATE i DELETE odbija trigger", async () => {
    const insert = (uc: string, slugs: string) =>
      env.DB.prepare(
        `INSERT INTO channel_tombstones (youtube_channel_id, channel_title, slugs, requested_at, phone_confirmed_at, deleted_at, synced_at)
         VALUES (?1, 'Kanal', ?2, NULL, NULL, ?3, ?3)`,
      )
        .bind(uc, slugs, now)
        .run();
    await expect(insert("UCmigT1", '["kanal"]')).resolves.toBeDefined();
    await expect(insert("UCmigT2", '{"a":1}')).rejects.toThrow(/constraint/i);
    await expect(env.DB.prepare("UPDATE channel_tombstones SET channel_title = 'x' WHERE youtube_channel_id = 'UCmigT1'").run()).rejects.toThrow(/trajan/);
    await expect(env.DB.prepare("DELETE FROM channel_tombstones WHERE youtube_channel_id = 'UCmigT1'").run()).rejects.toThrow(/trajan/);
    const row = await env.DB.prepare("SELECT count(*) AS n FROM channel_tombstones WHERE youtube_channel_id = 'UCmigT1'").first();
    expect(row).toEqual({ n: 1 });
  });

  it("settings_poll_state: kursor je NULL ili vrijeme, status nije prazan", async () => {
    const insert = (source: string, cursor: string | null, status: string) =>
      env.DB.prepare("INSERT INTO settings_poll_state (source, cursor, polled_at, status) VALUES (?1, ?2, ?3, ?4)")
        .bind(source, cursor, now, status)
        .run();
    await expect(insert("mig-a", null, "disabled")).resolves.toBeDefined();
    await expect(insert("mig-b", "2026-11-11T19:07:01.651675+00:00", "ok")).resolves.toBeDefined();
    await expect(insert("mig-c", "nije vrijeme", "ok")).rejects.toThrow(/constraint/i);
    await expect(insert("mig-d", null, "")).rejects.toThrow(/constraint/i);
  });
});

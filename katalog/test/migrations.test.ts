import { env } from "cloudflare:workers";
import { beforeAll, describe, expect, it } from "vitest";
import {
  channelDirectory,
  channelEpisodes,
  episodesOnDay,
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

const cases: { name: string; query: SqlQuery; index: string; table: string }[] = [
  { name: "najnovije, prva stranica", query: latestEpisodes(BRAND, PAGE), index: "episodes_by_date", table: "episodes" },
  { name: "najnovije, iza kursora", query: latestEpisodes(BRAND, PAGE, cursor), index: "episodes_by_date", table: "episodes" },
  { name: "dan, prva stranica", query: episodesOnDay(BRAND, day(20), PAGE), index: "episodes_by_date", table: "episodes" },
  { name: "dan, iza kursora", query: episodesOnDay(BRAND, day(20), PAGE, "ep_20_5"), index: "episodes_by_date", table: "episodes" },
  { name: "kanal, prva stranica", query: channelEpisodes(BRAND, "kanal_1", PAGE), index: "episodes_by_channel", table: "episodes" },
  { name: "kanal, iza kursora", query: channelEpisodes(BRAND, "kanal_1", PAGE, cursor), index: "episodes_by_channel", table: "episodes" },
  { name: "direktorij, prva stranica", query: channelDirectory(BRAND, 1, PAGE), index: "channels_directory", table: "channels" },
  {
    name: "direktorij, iza kursora",
    query: channelDirectory(BRAND, 1, PAGE, { latestPublishedDate: day(39), slug: "kanal_0" }),
    index: "channels_directory",
    table: "channels",
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
      { type: "index", name: "channels_directory" },
      { type: "index", name: "episodes_by_channel" },
      { type: "index", name: "episodes_by_date" },
      { type: "table", name: "brands" },
      { type: "table", name: "channels" },
      { type: "table", name: "episodes" },
      { type: "table", name: "ingest_runs" },
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
  it.each(cases)("$name: indeks $index, bez SCAN i TEMP B-TREE", async ({ query, index, table }) => {
    const plan = await queryPlan(query);
    const text = plan.join("\n");
    expect(text).toMatch(new RegExp(`^SEARCH ${table} USING (COVERING )?INDEX ${index} \\(`, "m"));
    expect(text).not.toMatch(/\bSCAN\b/);
    expect(text).not.toMatch(/TEMP B-TREE/);
  });

  it("row-value kursor je raspon indeksa, ne filtar", async () => {
    const plan = await queryPlan(latestEpisodes(BRAND, PAGE, cursor));
    expect(plan.join("\n")).toContain("(brand=? AND (published_date,id)<(?,?))");
  });
});

describe("rows_read je ograničen stranicom", () => {
  it.each(cases)("$name", async ({ query }) => {
    const { results, meta } = await prepare(env.DB, query).all();
    expect(results.length).toBeGreaterThan(0);
    // Indeksni raspon + dohvat retka po PK: najviše dva čitanja po retku
    // stranice i jedno za kraj raspona. Sken tablice bio bi ~400.
    expect(meta.rows_read).toBeLessThanOrEqual(2 * PAGE + 1);
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
    expect(() => latestEpisodes(BRAND, MAX_PAGE_SIZE + 1)).toThrow(RangeError);
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
});

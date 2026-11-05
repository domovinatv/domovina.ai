import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { buildPlan, type ImportPlan } from "../../src/ingest/plan.ts";
import { applyPlan, finishRun, startRun } from "../../src/ingest/write.ts";
import { fixturePlanInput } from "./input.ts";

// Storage nije izoliran po testu: svaki opis ima svoj brend (odluka 123 / S1).
const plan = buildPlan(fixturePlanInput());
const T1 = "2026-11-05T10:00:00.000Z";
const T2 = "2026-11-05T11:00:00.000Z";
const T3 = "2026-11-05T12:00:00.000Z";

async function rows<T>(sql: string, ...params: (string | number)[]): Promise<T[]> {
  return (await env.DB.prepare(sql).bind(...params).all<T>()).results;
}

describe("applyPlan u D1", () => {
  const brand = { id: "s2-idem", host: "s2-idem.test" };

  it("prvi upis: svi retci; drugi upis istog ulaza: 0 promjena, updated_at isti", async () => {
    const first = await applyPlan(env.DB, brand, plan, T1);
    expect(first).toEqual({ brands: 1, channels: plan.channels.length, episodes: plan.episodes.length });
    expect(first).toEqual({ brands: 1, channels: 12, episodes: 127 });

    const second = await applyPlan(env.DB, brand, buildPlan(fixturePlanInput()), T2);
    expect(second).toEqual({ brands: 0, channels: 0, episodes: 0 });
    expect(await rows("SELECT DISTINCT updated_at AS u FROM episodes WHERE brand = ?1", brand.id)).toEqual([{ u: T1 }]);
  });

  it("promjena jedne epizode: 1 promijenjen redak, updated_at samo njoj", async () => {
    const changed: ImportPlan = {
      ...plan,
      episodes: plan.episodes.map((e) => (e.id === "hmM9f_3Mqm4" ? { ...e, durationSeconds: 1234 } : e)),
    };
    expect(await applyPlan(env.DB, brand, changed, T3)).toEqual({ brands: 0, channels: 0, episodes: 1 });
    expect(await rows("SELECT id, updated_at AS u FROM episodes WHERE brand = ?1 AND updated_at = ?2", brand.id, T3)).toEqual([
      { id: "hmM9f_3Mqm4", u: T3 },
    ]);
    // NULL → broj i broj → NULL su promjena (IS NOT, ne <>).
    expect(await applyPlan(env.DB, brand, plan, T3)).toEqual({ brands: 0, channels: 0, episodes: 1 });
  });

  it("promjena kanala (unregistered, ime) se broji; ista vrijednost ne", async () => {
    const renamed: ImportPlan = {
      ...plan,
      channels: plan.channels.map((c) => (c.slug === "hkm" ? { ...c, name: "HKM" } : c)),
    };
    expect(await applyPlan(env.DB, brand, renamed, T3)).toEqual({ brands: 0, channels: 1, episodes: 0 });
    expect(await applyPlan(env.DB, brand, plan, T3)).toEqual({ brands: 0, channels: 1, episodes: 0 });
    expect(await applyPlan(env.DB, brand, plan, T3)).toEqual({ brands: 0, channels: 0, episodes: 0 });
  });
});

describe("retci u D1 nakon uvoza", () => {
  const brand = { id: "s2-rows", host: "s2-rows.test" };

  it("tieri, unregistered, NULL kanal, REAL trajanje, flags", async () => {
    await applyPlan(env.DB, brand, plan, T1);
    expect(await rows("SELECT tier, count(*) AS n FROM episodes WHERE brand = ?1 GROUP BY tier ORDER BY tier", brand.id)).toEqual([
      { tier: 1, n: 119 },
      { tier: 2, n: 8 },
    ]);
    expect(
      await rows(
        "SELECT tier, unregistered, count(*) AS n FROM channels WHERE brand = ?1 GROUP BY 1, 2 ORDER BY 1, 2",
        brand.id,
      ),
    ).toEqual([
      { tier: 1, unregistered: 0, n: 7 },
      { tier: 2, unregistered: 0, n: 3 },
      { tier: 2, unregistered: 1, n: 2 },
    ]);
    expect(
      await rows(
        `SELECT id, channel_slug, duration_seconds AS d, typeof(duration_seconds) AS t, flags, typeof(flags) AS ft
         FROM episodes WHERE brand = ?1 AND id IN ('CUJmOc91C64', 'kYwKrihe2K0', '0sxT3NF8yFg', 'hmM9f_3Mqm4') ORDER BY id`,
        brand.id,
      ),
    ).toEqual([
      { id: "0sxT3NF8yFg", channel_slug: null, d: 1845, t: "real", flags: 511, ft: "integer" },
      { id: "CUJmOc91C64", channel_slug: "x-1973380383166050304", d: 245.295, t: "real", flags: 511, ft: "integer" },
      { id: "hmM9f_3Mqm4", channel_slug: "yt-UCckHqySbfy5FcPP6MD_S-Yg", d: null, t: "null", flags: 15, ft: "integer" },
      { id: "kYwKrihe2K0", channel_slug: "hkm", d: 2017, t: "real", flags: 15, ft: "integer" },
    ]);
    expect(await rows("SELECT id, host FROM brands WHERE id = ?1", brand.id)).toEqual([{ id: brand.id, host: brand.host }]);
  });
});

describe("ingest_runs", () => {
  it("running → ok s counts JSON-om", async () => {
    const id = await startRun(env.DB, "backfill", T1);
    expect(await rows("SELECT status, finished_at AS f FROM ingest_runs WHERE id = ?1", id)).toEqual([
      { status: "running", f: null },
    ]);
    await finishRun(env.DB, id, "ok", T2, { written: { episodes: 0 } });
    expect(
      await rows("SELECT source, status, finished_at AS f, json_extract(counts, '$.written.episodes') AS n FROM ingest_runs WHERE id = ?1", id),
    ).toEqual([{ source: "backfill", status: "ok", f: T2, n: 0 }]);
  });
});

describe("migracija 0002: channels.unregistered", () => {
  const brand = "s2-mig";
  it("unregistered = 1 samo uz tier 2; samo 0/1", async () => {
    await env.DB.prepare("INSERT INTO brands (id, host) VALUES (?1, ?2)").bind(brand, "s2-mig.test").run();
    const insert = (slug: string, tier: number, unregistered: number) =>
      env.DB.prepare(
        `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar, processed_count,
           latest_published_date, unregistered) VALUES (?1, ?2, NULL, 'Ime', ?3, NULL, NULL, 0, NULL, ?4)`,
      )
        .bind(brand, slug, tier, unregistered)
        .run();
    await expect(insert("ok-2", 2, 1)).resolves.toBeDefined();
    await expect(insert("bad-1", 1, 1)).rejects.toThrow(/CHECK/);
    await expect(insert("bad-2", 2, 2)).rejects.toThrow(/CHECK/);
    const dflt = await env.DB.prepare(
      `INSERT INTO channels (brand, slug, youtube_channel_id, name, tier, lang, avatar, processed_count,
         latest_published_date) VALUES (?1, 'dflt', NULL, 'Ime', 1, NULL, NULL, 0, NULL) RETURNING unregistered`,
    )
      .bind(brand)
      .first<{ unregistered: number }>();
    expect(dflt).toEqual({ unregistered: 0 });
  });
});

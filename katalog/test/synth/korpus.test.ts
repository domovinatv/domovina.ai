// Generator sintetičkog kataloga (S4): determinizam po sjemenu i oblik
// raspodjele (`src/synth/korpus.ts`, `src/synth/s3.ts`). Mali N, u poolu.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { EpisodeRow } from "../../src/ingest/plan.ts";
import { applyPlan } from "../../src/ingest/write.ts";
import { KORPUS_HOT_DAY, Korpus } from "../../src/synth/korpus.ts";
import { S3_EPISODES, S3_HOT_DAY, S3_SEED, synthesizeS3 } from "../../src/synth/s3.ts";
import { brand, NOW, plan } from "../api/helpers.ts";

function rows(k: Korpus): EpisodeRow[] {
  return [...k.episodes()];
}

/** Varijanta stoji uz osnovnu epizodu: isti kanal, dan i tier; osnova nije varijanta. */
function expectVariantsHaveBase(episodes: readonly EpisodeRow[]): number {
  const byId = new Map(episodes.map((e) => [e.id, e]));
  let n = 0;
  for (const v of episodes) {
    if (v.variantOf === null) continue;
    n++;
    const base = byId.get(v.variantOf);
    expect(base, v.id).toBeDefined();
    expect(base?.variantOf, v.id).toBeNull();
    expect(base?.channelSlug, v.id).toBe(v.channelSlug);
    expect(base?.publishedDate, v.id).toBe(v.publishedDate);
    expect(base?.tier, v.id).toBe(v.tier);
    expect(v.id).toMatch(new RegExp(`^${v.variantOf.slice(0, 9)}_[0-9]+$`));
  }
  return n;
}

describe("korpus: determinizam", () => {
  it("isto sjeme → isti retci i kanali; dva prolaza istog generatora → isti retci", () => {
    const a = new Korpus({ episodes: 5000, seed: 7 });
    const b = new Korpus({ episodes: 5000, seed: 7 });
    const ra = rows(a);
    expect(rows(b)).toEqual(ra);
    expect(b.channelRows()).toEqual(a.channelRows());
    expect(rows(a)).toEqual(ra);
    expect(a.summary()).toEqual(b.summary());
  });

  it("drugo sjeme → drugi ID-evi, isti N", () => {
    const a = rows(new Korpus({ episodes: 5000, seed: 1 }));
    const b = rows(new Korpus({ episodes: 5000, seed: 2 }));
    expect(b).toHaveLength(a.length);
    const ids = new Set(a.map((e) => e.id));
    const shared = b.filter((e) => ids.has(e.id)).length;
    // Zajednički su samo ID-evi „veličine slova” (case…) i njihove varijante.
    expect(shared).toBeLessThan(60);
  });

  it("zlatne brojke za N = 10 000, sjeme 1 (isto što ispiše `npm run synth`)", () => {
    const k = new Korpus({ episodes: 10_000, seed: 1 });
    rows(k);
    expect(k.summary()).toEqual({
      channels: {
        total: 401,
        tier1: 118,
        tier2: 283,
        unregistered: 75,
        largest: 1014,
        bySize: { "1": 201, "2": 27, "3–10": 84, "11–100": 59, "101–1000": 29, ">1000": 1 },
      },
      episodes: { total: 10_000, tier1: 9297, tier2: 703, variants: 150, withoutChannel: 60, withoutDate: 5 },
      hotDay: { date: KORPUS_HOT_DAY, episodes: 104 },
    });
  });
});

describe("korpus: oblik raspodjele", () => {
  const N = 20_000;
  const k = new Korpus({ episodes: N, seed: 3 });
  const episodes = rows(k);
  const channels = k.channelRows();
  const s = k.summary();

  it("točno N epizoda, jedinstveni ID-evi i slugovi", () => {
    expect(episodes).toHaveLength(N);
    expect(new Set(episodes.map((e) => e.id)).size).toBe(N);
    expect(new Set(channels.map((c) => c.slug)).size).toBe(channels.length);
    const slugs = new Set(channels.map((c) => c.slug));
    expect(episodes.every((e) => e.channelSlug === null || slugs.has(e.channelSlug))).toBe(true);
  });

  it("dugi rep: većina kanala s 1–2 epizode, malo kanala s tisuću i više", () => {
    const small = s.channels.bySize["1"] + s.channels.bySize["2"];
    expect(small / s.channels.total).toBeGreaterThan(0.45);
    expect(s.channels.bySize[">1000"]).toBeGreaterThanOrEqual(1);
    expect(s.channels.bySize[">1000"] / s.channels.total).toBeLessThan(0.01);
    // Broj kanala ∝ N: stvarni korpus ima 162 kanala na 3665 epizoda (≈ 44 na 1000).
    expect(s.channels.total / N).toBeGreaterThan(0.03);
    expect(s.channels.total / N).toBeLessThan(0.06);
  });

  it("udjeli kao u stvarnom korpusu: Tier 2 ~6,9 %, varijante ~1,5 %, bez kanala ~0,6 %", () => {
    expect(s.episodes.tier2 / N).toBeGreaterThan(0.06);
    expect(s.episodes.tier2 / N).toBeLessThan(0.08);
    expect(s.episodes.variants).toBe(Math.round((N * 55) / 3665));
    expect(s.episodes.withoutChannel).toBe(Math.round((N * 22) / 3665));
    expect(s.episodes.withoutDate).toBeGreaterThan(0);
    expect(episodes.filter((e) => e.channelSlug === null).every((e) => e.tier === 2)).toBe(true);
  });

  it("vrući dan postoji i višestruko je veći od prosječnog dana 2026.", () => {
    expect(s.hotDay.date).toBe(KORPUS_HOT_DAY);
    const in2026 = episodes.filter((e) => e.variantOf === null && e.publishedDate?.startsWith("2026-") === true);
    const avg = in2026.length / new Set(in2026.map((e) => e.publishedDate)).size;
    expect(s.hotDay.episodes).toBeGreaterThan(5 * avg);
    expect(s.hotDay.episodes / N).toBeGreaterThan(0.005);
    expect(s.hotDay.episodes / N).toBeLessThan(0.012);
  });

  it("svaka varijanta ima osnovnu epizodu (isti kanal i dan), pola na vrućem danu", () => {
    const n = expectVariantsHaveBase(episodes);
    expect(n).toBe(s.episodes.variants);
    const hot = episodes.filter((e) => e.variantOf !== null && e.publishedDate === KORPUS_HOT_DAY).length;
    expect(hot / n).toBeGreaterThan(0.4);
  });

  it("kanal: processed_count i latest_published_date iz istih redaka, bez varijanti", () => {
    const own = new Map<string, { n: number; latest: string | null }>();
    for (const e of episodes) {
      if (e.channelSlug === null || e.variantOf !== null || e.publishedDate === null) continue;
      const a = own.get(e.channelSlug) ?? { n: 0, latest: null };
      a.n++;
      if (a.latest === null || e.publishedDate > a.latest) a.latest = e.publishedDate;
      own.set(e.channelSlug, a);
    }
    for (const c of channels) {
      expect(c.processedCount, c.slug).toBe(own.get(c.slug)?.n ?? 0);
      expect(c.latestPublishedDate, c.slug).toBe(own.get(c.slug)?.latest ?? null);
      expect(c.unregistered && c.tier !== 2, c.slug).toBe(false);
    }
  });

  it("retci prolaze shemu D1 kroz applyPlan (CHECK, strani ključ)", { timeout: 30_000 }, async () => {
    const small = new Korpus({ episodes: 2000, seed: 11 });
    const eps = rows(small);
    const b = brand("s4-korpus");
    const w = await applyPlan(env.DB, b, { channels: small.channelRows(), episodes: eps, report: plan.report }, NOW);
    expect(w.episodes).toBe(2000);
    const n = await env.DB.prepare("SELECT count(*) AS n FROM episodes WHERE brand = ?1").bind(b.id).first<{ n: number }>();
    expect(n?.n).toBe(2000);
  });
});

describe("s3: parametrizirano N i sjemenom", () => {
  it("N = 5000, sjeme 20261105: oblik iz odluke 313", () => {
    const a = synthesizeS3({ episodes: S3_EPISODES, seed: S3_SEED });
    expect(a.episodes).toHaveLength(5000);
    expect(a.channels).toHaveLength(328);
    expect(a.episodes.filter((e) => e.variantOf !== null)).toHaveLength(400);
    // 2340 + 30 ID-eva „veličine slova”, uz to dio epizoda bez datuma i varijanti.
    expect(a.episodes.filter((e) => e.channelSlug === "synth-big-a").length).toBeGreaterThanOrEqual(2370);
  });

  it("isto sjeme → isti retci; drugi N skalira razrede i zbroj je točno N", () => {
    const a = synthesizeS3({ episodes: 12_345, seed: 5 });
    expect(synthesizeS3({ episodes: 12_345, seed: 5 })).toEqual(a);
    expect(a.episodes).toHaveLength(12_345);
    expect(new Set(a.episodes.map((e) => e.id)).size).toBe(12_345);
    expect(expectVariantsHaveBase(a.episodes)).toBe(Math.round(400 * (12_345 / 5000)));
    const hot = a.episodes.filter((e) => e.publishedDate === S3_HOT_DAY && e.variantOf === null).length;
    expect(hot).toBeGreaterThan(250 * (12_345 / 5000));
  });
});

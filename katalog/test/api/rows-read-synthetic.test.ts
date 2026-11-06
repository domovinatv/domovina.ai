// `meta.rows_read` nad sintetičkim katalogom (odluka 313): fixturei + 5000
// sintetičkih epizoda upisanih istim putem kao uvoz (`applyPlan`). Dokazuje da
// `rows_read` ovisi o veličini stranice, a ne o veličini kataloga ni o dubini
// stranice, i da varijante (`variant_of`) usred raspona ne napuhuju čitanje.
//
// Raspodjela je deterministička (mulberry32 sa stalnim sjemenom), od S4 u
// zajedničkom modulu `src/synth/s3.ts` (isti retci kao u S3):
// - dugi rep: dva velika kanala (2340 + 30 i 1100 epizoda), 6 srednjih po 80,
//   320 malih s 1–2 epizode, 140 epizoda bez kanala, 30 bez datuma;
// - „vrući” dan s 300+ epizoda raznih kanala (više stranica i na limitu 100),
//   uz parove ID-eva koji se razlikuju samo veličinom slova;
// - 400 varijanti, svaka uz svoju osnovnu epizodu (isti kanal, isti dan, ID
//   `<9 znakova osnove>_<n>`), pa pada usred raspona koji popis čita.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { EpisodeRow, ImportPlan } from "../../src/ingest/plan.ts";
import { applyPlan } from "../../src/ingest/write.ts";
import {
  S3_BIG_A,
  S3_BIG_B,
  S3_EPISODES,
  S3_HOT_DAY,
  S3_QUIET_DAY,
  S3_SEED,
  synthesizeS3,
} from "../../src/synth/s3.ts";
import {
  api,
  brand,
  type Card,
  collect,
  type Contract,
  type ListBody,
  measure,
  NOW,
  okRun,
  plan,
  ROWS_READ_CONSTANT,
} from "./helpers.ts";

const b = brand("s3-synth");

const HOT_DAY = S3_HOT_DAY;
const QUIET_DAY = S3_QUIET_DAY;
const BIG_A = S3_BIG_A;
const BIG_B = S3_BIG_B;

interface Synthetic {
  readonly plan: ImportPlan;
  readonly episodes: readonly EpisodeRow[];
}

/** Raspodjela „s3” iz `src/synth/s3.ts` (S4): N = 5000, sjeme 20261105, uz fixture ID-eve. */
function synthesize(): Synthetic {
  const synth = synthesizeS3({
    episodes: S3_EPISODES,
    seed: S3_SEED,
    reservedIds: plan.episodes.map((e) => e.id),
  });
  expect(synth.episodes).toHaveLength(5000);
  expect(synth.channels).toHaveLength(328);
  return {
    plan: {
      ...plan,
      channels: [...plan.channels, ...synth.channels],
      episodes: [...plan.episodes, ...synth.episodes],
    },
    episodes: synth.episodes,
  };
}

/** Poredak popisa: datum DESC, id DESC, BINARY (za ASCII ID-eve = usporedba u JS-u). */
function desc(a: EpisodeRow, b2: EpisodeRow): number {
  const ad = a.publishedDate ?? "";
  const bd = b2.publishedDate ?? "";
  if (ad !== bd) return ad < bd ? 1 : -1;
  return a.id < b2.id ? 1 : a.id > b2.id ? -1 : 0;
}

interface Route {
  readonly path: string;
  readonly contract: Contract;
  /** Koliko stranica po 100 preskočiti do „duboke” stranice; 0 = popis je kratak. */
  readonly deep: number;
}

const ROUTES: readonly Route[] = [
  { path: `days/${HOT_DAY}`, contract: "days", deep: 2 },
  { path: `days/${QUIET_DAY}`, contract: "days", deep: 0 },
  { path: "channels", contract: "channels", deep: 3 },
  { path: "channels?tier=1", contract: "channels", deep: 0 },
  { path: "channels?tier=2", contract: "channels", deep: 3 },
  { path: "directory", contract: "directory", deep: 3 },
  { path: `channels/${BIG_A}/episodes`, contract: "channel-episodes", deep: 15 },
  { path: `channels/${BIG_B}/episodes`, contract: "channel-episodes", deep: 8 },
  { path: "channels/podcast_cuspajz/episodes", contract: "channel-episodes", deep: 0 },
];

const LIMITS = [1, 30, 100] as const;

describe("rows_read nad 5000 sintetičkih epizoda", () => {
  let synth: Synthetic;

  it("upis kroz applyPlan (fixturei + 5000 sintetičkih)", { timeout: 60_000 }, async () => {
    synth = synthesize();
    const t0 = Date.now();
    await applyPlan(env.DB, b, synth.plan, NOW);
    await okRun();
    const ms = Date.now() - t0;
    console.log(`applyPlan ${synth.plan.episodes.length} epizoda, ${synth.plan.channels.length} kanala: ${ms} ms`);
    const hot = synth.episodes.filter((e) => e.publishedDate === HOT_DAY && e.variantOf === null);
    expect(hot.length).toBeGreaterThan(250);
    expect(synth.episodes.filter((e) => e.variantOf !== null)).toHaveLength(400);
  });

  it.each(ROUTES)("$path: ≤ 3 × limit + konstanta, duboka stranica ne čita više od prve", async (route) => {
    const sep = route.path.includes("?") ? "&" : "?";
    const out: string[] = [];
    const first = new Map<number, number>();
    for (const limit of LIMITS) {
      const n = await measure(b.host, `${route.path}${sep}limit=${limit}`, route.contract);
      first.set(limit, n);
      expect(n, `${route.path} limit=${limit}`).toBeLessThanOrEqual(3 * limit + ROWS_READ_CONSTANT);
    }
    // Duboki kursor: `next` stranica po 100 (prva je već u cacheu, ovdje je hit).
    let cursor: string | null = null;
    for (let i = 0; i < route.deep; i++) {
      const q: string = cursor === null ? "" : `&cursor=${cursor}`;
      const { body } = await api<ListBody<unknown>>(b.host, `${route.path}${sep}limit=100${q}`, route.contract);
      expect(body.next, `${route.path} stranica ${i + 1}`).not.toBeNull();
      cursor = body.next;
    }
    for (const limit of LIMITS) {
      const f = first.get(limit) ?? 0;
      if (cursor === null) {
        out.push(`${route.path} limit=${limit}: ${f}`);
        continue;
      }
      const d = await measure(b.host, `${route.path}${sep}limit=${limit}&cursor=${cursor}`, route.contract);
      out.push(`${route.path} limit=${limit}: ${f} / ${d} (dubina ${route.deep * 100})`);
      expect(d, `${route.path} limit=${limit} duboko`).toBeLessThanOrEqual(3 * limit + ROWS_READ_CONSTANT);
      expect(d - f, `${route.path} limit=${limit}: duboka − prva`).toBeLessThanOrEqual(ROWS_READ_CONSTANT);
    }
    console.log(out.join("\n"));
  });

  it("kartica varijante i mali kanal: konstantan rows_read", async () => {
    const variant = synth.episodes.find((e) => e.variantOf !== null);
    expect(variant).toBeDefined();
    const card = await measure(b.host, `episodes/${variant?.id}/card`, "card-response");
    const small = await measure(b.host, "channels/synth-small-007", "channel-response");
    console.log(`card ${card}, channels/synth-small-007 ${small}`);
    expect(card).toBeLessThanOrEqual(3 + ROWS_READ_CONSTANT);
    expect(small).toBeLessThanOrEqual(3 + ROWS_READ_CONSTANT);
  });

  it("vrući dan do kraja: svi retci, bez varijanti i duplikata, BINARY poredak (veličina slova)", async () => {
    const expected = [...plan.episodes, ...synth.episodes]
      .filter((e) => e.publishedDate === HOT_DAY && e.variantOf === null)
      .sort(desc)
      .map((e) => e.id);
    const { items, pages } = await collect<Card>(b.host, `days/${HOT_DAY}`, "days", 100);
    expect(pages.length).toBeGreaterThanOrEqual(3);
    expect(items.map((c) => c.id)).toEqual(expected);
  });

  it("veliki kanal do kraja: sve ne-varijante s datumom = processed_count", async () => {
    const expected = synth.episodes
      .filter((e) => e.channelSlug === BIG_B && e.variantOf === null && e.publishedDate !== null)
      .sort(desc)
      .map((e) => e.id);
    const { items } = await collect<Card>(b.host, `channels/${BIG_B}/episodes`, "channel-episodes", 100);
    expect(items.map((c) => c.id)).toEqual(expected);
    const head = await api<{ item: { processed_count: number } }>(b.host, `channels/${BIG_B}`, "channel-response");
    expect(head.body.item.processed_count).toBe(expected.length);
  });
});

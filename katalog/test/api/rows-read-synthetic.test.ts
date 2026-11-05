// `meta.rows_read` nad sintetičkim katalogom (odluka 313): fixturei + 5000
// sintetičkih epizoda upisanih istim putem kao uvoz (`applyPlan`). Dokazuje da
// `rows_read` ovisi o veličini stranice, a ne o veličini kataloga ni o dubini
// stranice, i da varijante (`variant_of`) usred raspona ne napuhuju čitanje.
//
// Raspodjela je deterministička (mulberry32 sa stalnim sjemenom):
// - dugi rep: dva velika kanala (2340 + 30 i 1100 epizoda), 6 srednjih po 80,
//   320 malih s 1–2 epizode, 140 epizoda bez kanala, 30 bez datuma;
// - „vrući” dan s 300+ epizoda raznih kanala (više stranica i na limitu 100),
//   uz parove ID-eva koji se razlikuju samo veličinom slova;
// - 400 varijanti, svaka uz svoju osnovnu epizodu (isti kanal, isti dan, ID
//   `<9 znakova osnove>_<n>`), pa pada usred raspona koji popis čita.
import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import type { ChannelRow, EpisodeRow, ImportPlan } from "../../src/ingest/plan.ts";
import { applyPlan } from "../../src/ingest/write.ts";
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

const HOT_DAY = "2026-10-20";
const QUIET_DAY = "2025-03-14";
const BIG_A = "synth-big-a";
const BIG_B = "synth-big-b";

/** mulberry32: mali PRNG sa sjemenom, da je raspodjela ista u svakom pokretanju. */
function prng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

interface Synthetic {
  readonly plan: ImportPlan;
  readonly episodes: readonly EpisodeRow[];
}

function synthesize(): Synthetic {
  const rnd = prng(20261105);
  const pick = <T>(xs: readonly T[]): T => xs[Math.floor(rnd() * xs.length)] as T;
  const used = new Set(plan.episodes.map((e) => e.id));
  const newId = (): string => {
    for (;;) {
      let id = "s";
      for (let i = 0; i < 10; i++) id += ALPHABET.charAt(Math.floor(rnd() * ALPHABET.length));
      if (!used.has(id)) {
        used.add(id);
        return id;
      }
    }
  };
  // ~3 godine dana; razdioba prema novijim datumima (kvadrat), kao stvarni katalog.
  const start = Date.UTC(2023, 10, 1);
  const span = Date.UTC(2026, 10, 4) - start;
  const randomDay = (): string =>
    new Date(start + Math.floor((1 - (1 - rnd()) ** 2) * (span / 86_400_000)) * 86_400_000)
      .toISOString()
      .slice(0, 10);

  const channelSpecs: { slug: string; tier: 1 | 2; count: number }[] = [
    { slug: BIG_A, tier: 1, count: 2340 },
    { slug: BIG_B, tier: 2, count: 1100 },
  ];
  for (let i = 0; i < 6; i++) channelSpecs.push({ slug: `synth-mid-${i}`, tier: i % 2 === 0 ? 1 : 2, count: 80 });
  for (let i = 0; i < 320; i++) {
    channelSpecs.push({ slug: `synth-small-${String(i).padStart(3, "0")}`, tier: 2, count: 1 + (i % 2) });
  }

  const episodes: EpisodeRow[] = [];
  const row = (id: string, slug: string | null, tier: 1 | 2, date: string | null, variantOf: string | null) => {
    episodes.push({
      id,
      channelSlug: slug,
      title: `Sintetička ${id}`,
      titleHr: null,
      publishedDate: date,
      durationSeconds: Math.round(rnd() * 7200 * 1000) / 1000,
      tier,
      lang: "hr",
      magisteriumScore: null,
      flags: 0,
      variantOf,
    });
  };
  for (const c of channelSpecs) {
    for (let i = 0; i < c.count; i++) {
      // Svaka 12. epizoda velikih kanala pada na vrući dan (≈ 290), ostale razasute.
      const hot = c.count >= 1000 && i % 12 === 0;
      row(newId(), c.slug, c.tier, hot ? HOT_DAY : randomDay(), null);
    }
  }
  for (let i = 0; i < 140; i++) row(newId(), null, 2, i % 10 === 0 ? HOT_DAY : randomDay(), null);
  for (let i = 0; i < 30; i++) row(newId(), pick([BIG_A, BIG_B, null]), 2, null, null);
  // Parovi koji se razlikuju samo veličinom slova (BINARY: 'A' < 'a').
  for (let i = 0; i < 10; i++) {
    const base = `case${String(i).padStart(2, "0")}xyz`;
    for (const id of [`${base}Q`, `${base}q`, `${base.toUpperCase()}q`]) {
      used.add(id);
      row(id, BIG_A, 1, HOT_DAY, null);
    }
  }
  // Varijante: uz osnovnu epizodu (isti kanal i dan), pola na vrućem danu.
  const bases = episodes.filter((e) => e.publishedDate !== null && e.channelSlug !== null);
  const hotBases = bases.filter((e) => e.publishedDate === HOT_DAY);
  for (let i = 0; i < 400; i++) {
    const base = i % 2 === 0 ? pick(hotBases) : pick(bases);
    let n = 1;
    while (used.has(`${base.id.slice(0, 9)}_${n}`)) n++;
    const id = `${base.id.slice(0, 9)}_${n}`;
    used.add(id);
    row(id, base.channelSlug, base.tier, base.publishedDate, base.id);
  }
  const synthetic = episodes.slice(0, 5000);
  expect(synthetic).toHaveLength(5000);

  // Kanali: brojevi i datum iz istih redaka, kao plan (bez varijanti, odluka 302).
  const channels: ChannelRow[] = channelSpecs.map((c) => {
    const own = synthetic.filter((e) => e.channelSlug === c.slug && e.variantOf === null);
    const dates = own.map((e) => e.publishedDate).filter((d): d is string => d !== null);
    return {
      slug: c.slug,
      youtubeChannelId: null,
      name: `Sintetički ${c.slug}`,
      tier: c.tier,
      lang: "hr",
      avatar: null,
      processedCount: dates.length,
      latestPublishedDate: dates.length === 0 ? null : dates.reduce((m, d) => (d > m ? d : m)),
      unregistered: false,
    };
  });
  return {
    plan: { ...plan, channels: [...plan.channels, ...channels], episodes: [...plan.episodes, ...synthetic] },
    episodes: synthetic,
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

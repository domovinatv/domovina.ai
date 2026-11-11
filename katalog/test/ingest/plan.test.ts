import { describe, expect, it } from "vitest";
import { buildPlan } from "../../src/ingest/plan.ts";
import { fixturePlanInput } from "./input.ts";

const input = fixturePlanInput();
const plan = buildPlan(input);
const episode = (id: string) => plan.episodes.find((e) => e.id === id);
const channel = (slug: string) => plan.channels.find((c) => c.slug === slug);

describe("buildPlan nad fixtureima", () => {
  it("Tier 2 = key cache minus Tier 1 listinzi: KLPD-Meu4e8 je tier 1 (nanovoroeni)", () => {
    expect(input.tier2.map((t) => t.id)).toEqual([
      "0sxT3NF8yFg",
      "6dcab9c9837",
      "7N0gyXAfA4M",
      "A-oDNz3nvdQ",
      "CUJmOc91C64",
      "UM2MWlNUp_1",
      "hmM9f_3Mqm4",
      "kYwKrihe2K0",
    ]);
    expect(episode("KLPD-Meu4e8")).toMatchObject({ tier: 1, channelSlug: "nanovoroeni" });
    expect(plan.report.episodes).toEqual({ tier1: 119, tier2: 8 });
  });

  it("kanali: 7 Tier 1, 5 Tier 2 od kojih 2 unregistered", () => {
    expect(plan.report.channels).toEqual({ tier1: 7, tier2: 5, unregistered: 2 });
    expect(plan.channels.filter((c) => c.tier === 2).map((c) => c.slug)).toEqual([
      "hkm",
      "nova-eva",
      "tech-cakula-it-zajednica-rijeka",
      "x-1973380383166050304",
      "yt-UCckHqySbfy5FcPP6MD_S-Yg",
    ]);
  });

  it("izvještaj: bez kanala, Tier 2 na praćenom kanalu, bez info.json, varijante", () => {
    const r = plan.report;
    expect(r.withoutChannel).toEqual({ ambiguous_registry_channel_id: ["0sxT3NF8yFg"] });
    expect(r.tier2Via).toEqual({ summary_source_channel: 1, registry: 3, unregistered: 2, tier1_channel_id: 1 });
    expect(r.tier2OnTier1Channel).toEqual([
      { id: "6dcab9c9837", slug: "subclub", via: "summary_source_channel" },
      { id: "UM2MWlNUp_1", slug: "podcast_cuspajz", via: "tier1_channel_id" },
    ]);
    expect(r.withoutInfoJson).toEqual(["6dcab9c9837"]);
    expect(r.experimentalVariants).toEqual([{ id: "UM2MWlNUp_1", base: "UM2MWlNUpqg" }]);
    // Varijanta nosi osnovni ID u retku (stupac `variant_of`, odluka 302); nitko drugi.
    expect(plan.episodes.filter((e) => e.variantOf !== null).map((e) => [e.id, e.variantOf])).toEqual([
      ["UM2MWlNUp_1", "UM2MWlNUpqg"],
    ]);
    expect(r.withoutDate).toEqual({ tier1: [], tier2: [] });
    expect(r.infoIdMismatch).toEqual([]);
    expect(r.tier2AlsoInTier1).toEqual([]);
    // Listinzi u fixtureu su skraćeni na ≤ 20 epizoda, pa video_count odstupa (u stvarnom ulazu 0/52).
    expect(r.videoCountMismatch.map((m) => m.slug)).toEqual([
      "40_dana_za_zivot",
      "dijalog",
      "nanovoroeni",
      "podcast_cuspajz",
      "subclub",
    ]);
  });

  it("Tier 2 retci: datum, trajanje, jezik, flags iz key cachea", () => {
    expect(episode("CUJmOc91C64")).toEqual({
      id: "CUJmOc91C64",
      channelSlug: "x-1973380383166050304",
      title: "Hobba 🟢 - Meet the CEO of Hobba, @IgorJerkovic  Hobba is the future of borrowin...",
      titleHr: "Upoznajte Hobba-u: Budućnost posuđivanja na Solani s Igorom Jerkovićem",
      publishedDate: "2026-07-16",
      durationSeconds: 245.295,
      tier: 2,
      lang: "hr",
      magisteriumScore: null,
      flags: 511,
      variantOf: null,
      // yt-dlp `timestamp` iz info.json (odluka 1205).
      publishedAt: "2026-07-16T15:47:10Z",
    });
    expect(episode("hmM9f_3Mqm4")).toMatchObject({ durationSeconds: null, flags: 15 });
    expect(episode("0sxT3NF8yFg")).toMatchObject({ channelSlug: null, publishedDate: "2026-11-03", flags: 511 });
  });

  it("bez info.json: naslov, datum i trajanje iz summary.json source", () => {
    expect(episode("6dcab9c9837")).toEqual({
      id: "6dcab9c9837",
      channelSlug: "subclub",
      title: "Rast kao posao svakoga: Gio Contestable (Life360) o eksperimentiranju, freemiumu i personalizaciji",
      titleHr: "Rast kao posao svakoga: Gio Contestable (Life360) o eksperimentiranju, freemiumu i personalizaciji",
      publishedDate: "2026-05-13",
      durationSeconds: null,
      tier: 2,
      lang: "hr",
      magisteriumScore: null,
      flags: 15,
      variantOf: null,
      publishedAt: null,
    });
  });

  it("processed_count i latest_published_date broje sve retke kanala, oba tiera, bez varijanti", () => {
    // 21 redak, od toga varijanta UM2MWlNUp_1 (odluka 302): broji se 20.
    expect(plan.episodes.filter((e) => e.channelSlug === "podcast_cuspajz")).toHaveLength(21);
    expect(channel("podcast_cuspajz")).toMatchObject({ tier: 1, processedCount: 20, latestPublishedDate: "2026-11-04" });
    expect(channel("subclub")).toMatchObject({ tier: 1, processedCount: 21, latestPublishedDate: "2026-10-28" });
    expect(channel("hkm")).toMatchObject({ processedCount: 1, latestPublishedDate: "2018-10-01", avatar: null });
    for (const c of plan.channels) {
      const rows = plan.episodes.filter((e) => e.channelSlug === c.slug && e.variantOf === null);
      expect(c.processedCount, c.slug).toBe(rows.length);
    }
  });

  it("Tier 1 retci uzimaju listing doslovno; lang ostaje NULL (listing ga nema)", () => {
    expect(episode("KLPD-Meu4e8")).toMatchObject({
      title: "Goran Ćurković | Svjedočanstvo/Testimony (Eng. sub)",
      tier: 1,
      lang: null,
    });
    expect(plan.episodes.filter((e) => e.tier === 1 && e.lang !== null)).toEqual([]);
  });

  it("ime Tier 2 kanala dolazi s najnovije epizode", () => {
    const base = input.tier2.find((t) => t.id === "hmM9f_3Mqm4");
    if (base?.info == null) throw new Error("nema hmM9f_3Mqm4");
    const older = { ...base, id: "older_ep_01", info: { ...base.info, id: "older_ep_01", channel: "Stari naziv", uploadDate: "2020-01-01", timestamp: null } };
    const p = buildPlan({ ...input, tier2: [older, ...input.tier2] });
    expect(p.channels.find((c) => c.slug === "yt-UCckHqySbfy5FcPP6MD_S-Yg")).toMatchObject({
      name: "Times Of India",
      processedCount: 2,
      latestPublishedDate: "2026-09-25",
    });
  });

  it("Tier 2 ID koji je u listingu se preskače (tier 1 ima prednost)", () => {
    const klpd = { id: "KLPD-Meu4e8", info: null, summary: null, files: new Set<string>() };
    const p = buildPlan({ ...input, tier2: [...input.tier2, klpd] });
    expect(p.report.tier2AlsoInTier1).toEqual(["KLPD-Meu4e8"]);
    expect(p.episodes.filter((e) => e.id === "KLPD-Meu4e8")).toHaveLength(1);
  });

  it("kanal u index.json bez listinga → greška", () => {
    expect(() => buildPlan({ ...input, listings: input.listings.slice(1) })).toThrow(/listinga nema/);
  });

  it("Tier 2 dan je iz info.json timestamp u Europe/Zagreb: premijera 23:00Z ide na sljedeći dan", () => {
    const base = input.tier2.find((t) => t.id === "hmM9f_3Mqm4");
    if (base?.info == null) throw new Error("nema hmM9f_3Mqm4");
    // cvEZWm_ZlWU (Ora et labora): upload_date 20261108, timestamp 2026-11-08T23:00:06Z = 00:00 u Zagrebu.
    const premiere = { ...base, id: "premiere_01", info: { ...base.info, id: "premiere_01", uploadDate: "2026-11-08", timestamp: 1794178806 } };
    const p = buildPlan({ ...input, tier2: [...input.tier2, premiere] });
    expect(p.episodes.find((e) => e.id === "premiere_01")?.publishedDate).toBe("2026-11-09");
    // Bez timestamp-a ostaje upload_date.
    const noTs = { ...premiere, info: { ...premiere.info, timestamp: null } };
    expect(buildPlan({ ...input, tier2: [...input.tier2, noTs] }).episodes.find((e) => e.id === "premiere_01")?.publishedDate).toBe("2026-11-08");
  });

  it("backfill.json ima prednost za Tier 1 i Tier 2 i ulazi u latest_published_date", () => {
    const publishDates = new Map([
      ["KLPD-Meu4e8", "2020-02-09"],
      ["hmM9f_3Mqm4", "2026-09-24"],
    ]);
    const p = buildPlan({ ...input, publishDates });
    expect(p.episodes.find((e) => e.id === "KLPD-Meu4e8")?.publishedDate).toBe("2020-02-09");
    expect(p.episodes.find((e) => e.id === "hmM9f_3Mqm4")?.publishedDate).toBe("2026-09-24");
    expect(p.channels.find((c) => c.slug === "yt-UCckHqySbfy5FcPP6MD_S-Yg")?.latestPublishedDate).toBe("2026-09-24");
    expect(p.report.dates.backfill).toBe(2);
    expect(p.report.dates.changedByBackfill).toEqual(["KLPD-Meu4e8", "hmM9f_3Mqm4"]);
  });

  it("trenutak objave: backfill ima prednost, Tier 2 pada na timestamp, Tier 1 bez backfilla null", () => {
    const publishTimes = new Map([
      ["KLPD-Meu4e8", "2020-02-09T19:00:00Z"],
      ["CUJmOc91C64", "2026-07-16T15:00:00Z"],
    ]);
    const p = buildPlan({ ...input, publishTimes });
    const at = (id: string) => p.episodes.find((e) => e.id === id)?.publishedAt;
    expect(at("KLPD-Meu4e8")).toBe("2020-02-09T19:00:00Z");
    expect(at("CUJmOc91C64")).toBe("2026-07-16T15:00:00Z");
    expect(plan.episodes.filter((e) => e.tier === 1).every((e) => e.publishedAt === null)).toBe(true);
  });

  it("bez backfilla: Tier 2 s timestampom broji se kao timestamp, ostalo kao izvor", () => {
    expect(plan.report.dates.backfill).toBe(0);
    expect(plan.report.dates.timestamp).toBeGreaterThan(0);
    expect(plan.report.dates.timestamp + plan.report.dates.source).toBe(
      plan.episodes.filter((e) => e.publishedDate !== null).length,
    );
  });

  it("deterministički: dva plana nad istim ulazom su jednaka", () => {
    expect(buildPlan(fixturePlanInput())).toEqual(plan);
  });
});

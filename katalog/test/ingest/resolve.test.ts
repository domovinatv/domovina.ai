import { describe, expect, it } from "vitest";
import {
  type EpisodeInfo,
  parseChannelIndex,
  parseEpisodeInfo,
  parseEpisodeSummary,
  parseRegistry,
  type RegistryEntry,
} from "../../src/input/index.ts";
import { createResolver, pickRegistryEntry, registrySlugToCdn } from "../../src/ingest/resolve.ts";
import { fixtures } from "../input/fixtures.ts";

const index = parseChannelIndex(fixtures.index());
const registry = parseRegistry(fixtures.registry());
const resolver = createResolver(index, registry);
const info = (id: string): EpisodeInfo => parseEpisodeInfo(fixtures.infos().get(id));
const summary = (id: string) => parseEpisodeSummary(fixtures.summaries().get(id));
const resolve = (id: string) => resolver.resolve(info(id), summary(id));

describe("razrješavanje kanala Tier 2 epizode", () => {
  it("HKM kYwKrihe2K0: 10 registry unosa → umbrella hkm (Tier 2)", () => {
    expect(registry.entries.filter((e) => e.youtubeChannelId === "UCrfV3uhCoHNBaqiva1wCB4Q")).toHaveLength(10);
    expect(resolve("kYwKrihe2K0")).toEqual({
      ok: true,
      via: "registry",
      channel: {
        slug: "hkm",
        name: "Hrvatska katolička mreža (HKM / HKR)",
        tier: 2,
        youtubeChannelId: "UCrfV3uhCoHNBaqiva1wCB4Q",
        unregistered: false,
      },
    });
  });

  it("jedan registry unos (7N0gyXAfA4M) → njegov slug", () => {
    expect(resolve("7N0gyXAfA4M")).toMatchObject({
      ok: true,
      via: "registry",
      channel: { slug: "tech-cakula-it-zajednica-rijeka", tier: 2, unregistered: false },
    });
  });

  it("Nova Eva A-oDNz3nvdQ: type channel uz playlistu → nova-eva", () => {
    const cands = registry.entries.filter((e) => e.youtubeChannelId === "UCU_HxRUP9Ta1NJp6cjXx_0w");
    expect(cands.map((e) => [e.slug, e.youtubeType]).sort()).toEqual([
      ["nova-eva", "channel"],
      ["teologija-tijela", "playlist"],
    ]);
    expect(resolve("A-oDNz3nvdQ")).toMatchObject({ ok: true, via: "registry", channel: { slug: "nova-eva" } });
  });

  it("VTV 0sxT3NF8yFg: tri playliste, nijedno pravilo → NULL ambiguous_registry_channel_id", () => {
    const cands = registry.entries.filter((e) => e.youtubeChannelId === info("0sxT3NF8yFg").channelId);
    expect(cands.map((e) => e.youtubeType)).toEqual(["playlist", "playlist", "playlist"]);
    expect(resolve("0sxT3NF8yFg")).toEqual({ ok: false, reason: "ambiguous_registry_channel_id" });
  });

  it("UM2MWlNUp_1: channel_id = jedan Tier 1 kanal iz index.json → podcast_cuspajz", () => {
    expect(resolve("UM2MWlNUp_1")).toEqual({
      ok: true,
      via: "tier1_channel_id",
      channel: {
        slug: "podcast_cuspajz",
        name: "PODCAST  ČUŠPAJZ OFFICIAL",
        tier: 1,
        youtubeChannelId: "UCaqCX-pMk_RXhs4EQnP4VuQ",
        unregistered: false,
      },
    });
  });

  it("channel_id koji dijele dva Tier 1 kanala → NULL ambiguous_tier1_channel_id", () => {
    const shared = index.channels.filter((c) => c.youtubeChannelId === "UCuk9D5H9mx7birJ1-S22nyQ");
    expect(shared.map((c) => c.slug)).toEqual(["slijedi_svoj_poziv_1", "slijedi_svoj_poziv_2"]);
    // Stvarne Tier 2 epizode s tog kanala nema (izmjereno 05.11.); info je stvaran, ID kanala zamijenjen.
    const i = { ...info("7N0gyXAfA4M"), channelId: "UCuk9D5H9mx7birJ1-S22nyQ" };
    expect(resolver.resolve(i, null)).toEqual({ ok: false, reason: "ambiguous_tier1_channel_id" });
  });

  it("X/Twitter CUJmOc91C64: nema registryja ni `channel` → x-<id>, ime iz uploader", () => {
    expect(info("CUJmOc91C64").channel).toBeNull();
    expect(resolve("CUJmOc91C64")).toEqual({
      ok: true,
      via: "unregistered",
      channel: { slug: "x-1973380383166050304", name: "Hobba 🟢", tier: 2, youtubeChannelId: null, unregistered: true },
    });
  });

  it("hmM9f_3Mqm4 (bez duration): nema registryja → yt-<UC…>, veličina slova ostaje", () => {
    expect(resolve("hmM9f_3Mqm4")).toEqual({
      ok: true,
      via: "unregistered",
      channel: {
        slug: "yt-UCckHqySbfy5FcPP6MD_S-Yg",
        name: "Times Of India",
        tier: 2,
        youtubeChannelId: "UCckHqySbfy5FcPP6MD_S-Yg",
        unregistered: true,
      },
    });
  });

  it("bez info.json: source.channel subclub (Tier 1 slug) → subclub", () => {
    expect(summary("6dcab9c9837").sourceChannel).toBe("subclub");
    expect(resolver.resolve(null, summary("6dcab9c9837"))).toMatchObject({
      ok: true,
      via: "summary_source_channel",
      channel: { slug: "subclub", tier: 1 },
    });
  });

  it("bez info.json, source.channel _unlisted → NULL no_info_json", () => {
    expect(summary("kYwKrihe2K0").sourceChannel).toBe("_unlisted");
    expect(resolver.resolve(null, summary("kYwKrihe2K0"))).toEqual({ ok: false, reason: "no_info_json" });
    expect(resolver.resolve(null, null)).toEqual({ ok: false, reason: "no_info_json" });
  });

  it("bez channel_id, bez imena, nepoznat extractor → NULL s razlogom", () => {
    const base = info("hmM9f_3Mqm4");
    expect(resolver.resolve({ ...base, channelId: null }, null)).toEqual({ ok: false, reason: "no_channel_id" });
    expect(resolver.resolve({ ...base, channel: null, uploader: null }, null)).toEqual({
      ok: false,
      reason: "no_channel_name",
    });
    expect(resolver.resolve({ ...base, extractor: "vimeo" }, null)).toEqual({ ok: false, reason: "unknown_extractor" });
    expect(resolver.resolve({ ...base, extractor: null }, null)).toEqual({ ok: false, reason: "unknown_extractor" });
  });

  it("registry unos čiji slug je Tier 1 CDN slug → Tier 1 kanal (registry_tier1)", () => {
    // 40-dana-za-zivot ima channel_id u registryju; index URL mu je /channel/UC…, pa ga
    // put (a) nađe prvi. Bez index ID-a ostaje samo registry → 40_dana_za_zivot.
    const noUrl = parseChannelIndex(fixtures.index());
    const stripped = {
      ...noUrl,
      channels: noUrl.channels.map((c) => (c.slug === "40_dana_za_zivot" ? { ...c, youtubeChannelId: null } : c)),
    };
    const r = createResolver(stripped, registry);
    const i = { ...info("7N0gyXAfA4M"), channelId: "UChgVPEqmTeG0na3u8VfY3PQ" };
    expect(r.resolve(i, null)).toMatchObject({ ok: true, via: "registry_tier1", channel: { slug: "40_dana_za_zivot", tier: 1 } });
    expect(resolver.resolve(i, null)).toMatchObject({ ok: true, via: "tier1_channel_id" });
  });

  it("registrySlugToCdn: crtice u podvlake", () => {
    expect(registrySlugToCdn("40-dana-za-zivot")).toBe("40_dana_za_zivot");
    expect(registrySlugToCdn("hkm")).toBe("hkm");
  });
});

describe("pickRegistryEntry", () => {
  const e = (slug: string, youtubeType: string | null, parentSlug: string | null = null): RegistryEntry => ({
    slug,
    displayName: slug,
    youtubeChannelId: "UC",
    trackingEnabled: false,
    registryTier: null,
    youtubeType,
    parentSlug,
  });

  it("redoslijed: jedini, umbrella, channel, bez parent_slug, inače null", () => {
    expect(pickRegistryEntry([e("a", "playlist")])?.slug).toBe("a");
    expect(pickRegistryEntry([e("p", "playlist"), e("c", "channel"), e("u", "umbrella")])?.slug).toBe("u");
    expect(pickRegistryEntry([e("p", "playlist"), e("c", "channel")])?.slug).toBe("c");
    expect(pickRegistryEntry([e("p", "playlist", "r"), e("r", "playlist")])?.slug).toBe("r");
    expect(pickRegistryEntry([e("c1", "channel"), e("c2", "channel")])).toBeNull();
    expect(pickRegistryEntry([e("u1", "umbrella"), e("u2", "umbrella")])).toBeNull();
    expect(pickRegistryEntry([])).toBeNull();
  });
});

import { describe, expect, it } from "vitest";
import { parseEpisodeInfo, parseRegistry } from "../../src/input/index.ts";
import { clone, fixtures, inputError } from "./fixtures.ts";

interface RawRegistry {
  podcasts: Record<string, unknown>[];
}

function entryAt(r: RawRegistry, i: number): Record<string, unknown> {
  const e = r.podcasts[i];
  if (e === undefined) throw new Error(`nema podcasts[${i}]`);
  return e;
}

describe("parseRegistry", () => {
  const registry = parseRegistry(fixtures.registry());
  const bySlug = new Map(registry.entries.map((e) => [e.slug, e]));

  it("čita isječak u izvornom obliku {version, podcasts}", () => {
    expect(registry.version).toBe("1.2");
    expect(registry.entries.length).toBeGreaterThanOrEqual(5);
  });

  it("nanovoroeni: Tier 1 kanal bez youtube.channel_id", () => {
    expect(bySlug.get("nanovoroeni")).toEqual({
      slug: "nanovoroeni",
      displayName: "Na novo rođeni",
      youtubeChannelId: null,
      trackingEnabled: true,
      registryTier: 3,
      youtubeType: "channel",
      parentSlug: null,
    });
  });

  it("registry slug piše crtice, CDN slug podvlake", () => {
    expect(bySlug.get("40-dana-za-zivot")?.youtubeChannelId).toBe("UChgVPEqmTeG0na3u8VfY3PQ");
    expect(bySlug.has("40_dana_za_zivot")).toBe(false);
  });

  it("isti channel_id nosi više unosa (playliste istog kanala)", () => {
    const shared = registry.entries.filter((e) => e.youtubeChannelId === "UCuk9D5H9mx7birJ1-S22nyQ");
    expect(shared.map((e) => e.slug).sort()).toEqual([
      "na-kavi-sa-svetim-ignacijem",
      "slijedi-svoj-poziv-1",
      "slijedi-svoj-poziv-2",
    ]);
    const hkm = registry.entries.filter((e) => e.youtubeChannelId === "UCrfV3uhCoHNBaqiva1wCB4Q");
    expect(hkm.length).toBeGreaterThan(1);
    expect(hkm.every((e) => !e.trackingEnabled)).toBe(true);
  });

  it("kanali X/Twitter i hmM9f_3Mqm4 epizode NISU u registryju", () => {
    const infos = fixtures.infos();
    const ids = new Set(registry.entries.map((e) => e.youtubeChannelId));
    for (const id of ["CUJmOc91C64", "hmM9f_3Mqm4"]) {
      expect(ids.has(parseEpisodeInfo(infos.get(id)).channelId)).toBe(false);
    }
    for (const id of ["kYwKrihe2K0", "7N0gyXAfA4M"]) {
      expect(ids.has(parseEpisodeInfo(infos.get(id)).channelId)).toBe(true);
    }
  });

  it("registryTier je registryjev 1–4, ne naš tier", () => {
    for (const e of registry.entries) {
      if (e.registryTier !== null) expect([1, 2, 3, 4]).toContain(e.registryTier);
    }
    expect(bySlug.get("slijedi-svoj-poziv-1")?.registryTier).toBe(4);
  });

  describe("negativni", () => {
    it("tracking.enabled kao string", () => {
      const r = clone(fixtures.registry()) as RawRegistry;
      (entryAt(r, 2).tracking as Record<string, unknown>).enabled = "true";
      expect(inputError(() => parseRegistry(r)).path).toBe("podcasts[2].tracking.enabled");
    });

    it("bez tracking objekta", () => {
      const r = clone(fixtures.registry()) as RawRegistry;
      delete entryAt(r, 0).tracking;
      expect(inputError(() => parseRegistry(r)).path).toBe("podcasts[0].tracking");
    });

    it("decimalni tier", () => {
      const r = clone(fixtures.registry()) as RawRegistry;
      entryAt(r, 1).tier = 3.5;
      expect(inputError(() => parseRegistry(r)).path).toBe("podcasts[1].tier");
    });

    it("slug koji se ponavlja", () => {
      const r = clone(fixtures.registry()) as RawRegistry;
      r.podcasts.push(entryAt(r, 0));
      expect(inputError(() => parseRegistry(r)).path).toBe(`podcasts[${r.podcasts.length - 1}].slug`);
    });

    it("youtube.channel_id: null → null (postoji u stvarnom registryju)", () => {
      const r = clone(fixtures.registry()) as RawRegistry;
      (entryAt(r, 0).youtube as Record<string, unknown>).channel_id = null;
      expect(parseRegistry(r).entries[0]?.youtubeChannelId).toBeNull();
    });
  });
});

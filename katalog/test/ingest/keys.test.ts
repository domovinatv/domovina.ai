import { describe, expect, it } from "vitest";
import { InputError, PIPELINE_BITS } from "../../src/input/index.ts";
import { articleIds, experimentalVariants, flagsFromFiles, parseKeyCache } from "../../src/ingest/keys.ts";
import { clone, fixtures, LISTING_SLUGS, NO_INFO_IDS, UNLISTED_IDS } from "../input/fixtures.ts";
import { parseChannelListing } from "../../src/input/index.ts";

const files = parseKeyCache(fixtures.keyCache());

describe("parseKeyCache", () => {
  it("drži samo ključeve data/<id>/…; images/ i channels/ preskače", () => {
    const raw = fixtures.keyCache() as { sizes: Record<string, number> };
    const keys = Object.keys(raw.sizes);
    expect(keys.some((k) => k.startsWith("images/"))).toBe(true);
    expect(keys.some((k) => k.startsWith("channels/"))).toBe(true);
    for (const id of files.keys()) expect(id).not.toContain("/");
    const total = [...files.values()].reduce((n, f) => n + f.size, 0);
    expect(total).toBe(keys.filter((k) => k.startsWith("data/")).length);
  });

  it("verzija mora biti 2", () => {
    const raw = clone(fixtures.keyCache()) as { v: unknown };
    raw.v = 3;
    expect(() => parseKeyCache(raw)).toThrow(InputError);
    expect(() => parseKeyCache({ v: 2 })).toThrow(/sizes/);
  });

  it("article ID-evi = sve epizode iz fixturea (Tier 1 listinzi + Tier 2)", () => {
    const listingIds = [...fixtures.listings().values()].flatMap((r) => parseChannelListing(r).videos.map((v) => v.id));
    expect(LISTING_SLUGS).toHaveLength(7);
    const expected = new Set([...listingIds, ...UNLISTED_IDS, ...NO_INFO_IDS]);
    expect(articleIds(files)).toEqual([...expected].sort());
  });

  it("epizoda bez info.json na R2 (6dcab9c9837) nema ni ključ", () => {
    expect(files.get("6dcab9c9837")?.has("info.json")).toBe(false);
    expect(files.get("6dcab9c9837")?.has("summary.json")).toBe(true);
  });
});

describe("flagsFromFiles", () => {
  it("prazan popis = 0, sve datoteke = 511", () => {
    expect(flagsFromFiles(new Set())).toBe(0);
    const all = new Set([
      "diarized.srt",
      "summary.json",
      "article.json",
      "article.magisterium.json",
      "summary.en.json",
      "article.en.json",
      "article.magisterium.en.json",
    ]);
    expect(flagsFromFiles(all)).toBe(511);
    expect(PIPELINE_BITS).toHaveLength(9);
  });

  it("has_translation_en traži summary.en i article.en; magisterium_batch vrijedi", () => {
    expect(flagsFromFiles(new Set(["summary.en.json"]))).toBe(1 << 6);
    expect(flagsFromFiles(new Set(["article.en.json"]))).toBe(1 << 7);
    expect(flagsFromFiles(new Set(["summary.en.json", "article.en.json"]))).toBe((1 << 5) | (1 << 6) | (1 << 7));
    expect(flagsFromFiles(new Set(["article.magisterium_batch.json"]))).toBe(1 << 4);
  });

  it("iz key cachea daje isti flags kao listing za sve Tier 1 epizode u fixtureima", () => {
    let checked = 0;
    for (const raw of fixtures.listings().values()) {
      for (const v of parseChannelListing(raw).videos) {
        expect(flagsFromFiles(files.get(v.id) ?? new Set()), v.id).toBe(v.flags);
        checked++;
      }
    }
    expect(checked).toBe(119);
  });
});

describe("experimentalVariants", () => {
  it("UM2MWlNUp_1 je varijanta UM2MWlNUpqg", () => {
    expect(experimentalVariants(articleIds(files))).toEqual([{ id: "UM2MWlNUp_1", base: "UM2MWlNUpqg" }]);
  });

  it("_<znamenka> bez osnovnog ID-a nije varijanta", () => {
    expect(experimentalVariants(["UM2MWlNUp_1", "UM2MWlNUp_2"])).toEqual([]);
    expect(experimentalVariants(["abcdefghi_2", "abcdefghiXY", "zzzzzzzzzzz"])).toEqual([
      { id: "abcdefghi_2", base: "abcdefghiXY" },
    ]);
  });
});

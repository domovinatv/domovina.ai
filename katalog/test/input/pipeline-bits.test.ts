import { describe, expect, it } from "vitest";
import {
  ALL_PIPELINE_FLAGS,
  flagsFromPipeline,
  PIPELINE_BITS,
  type PipelineFlags,
  pipelineFromFlags,
} from "../../src/input/index.ts";

function only(...raised: (typeof PIPELINE_BITS)[number][]): PipelineFlags {
  return Object.fromEntries(PIPELINE_BITS.map((b) => [b, raised.includes(b)])) as PipelineFlags;
}

describe("PIPELINE_BITS (ugovor s generate_channel_index.js i VideoPipeline.fromBits)", () => {
  it("redoslijed je ugovor: bit 0…8", () => {
    expect(PIPELINE_BITS).toEqual([
      "has_transcript",
      "has_diarized",
      "has_summary",
      "has_article",
      "has_magisterium",
      "has_translation_en",
      "has_summary_en",
      "has_article_en",
      "has_magisterium_en",
    ]);
  });

  it("svih 9 = 511, ništa = 0", () => {
    expect(ALL_PIPELINE_FLAGS).toBe(511);
    expect(flagsFromPipeline(only(...PIPELINE_BITS))).toBe(511);
    expect(flagsFromPipeline(only())).toBe(0);
  });

  // Tablica iz `VideoPipeline.fromBits`: bit i ↔ zastavica.
  it.each([
    ["has_transcript", 1],
    ["has_diarized", 2],
    ["has_summary", 4],
    ["has_article", 8],
    ["has_magisterium", 16],
    ["has_translation_en", 32],
    ["has_summary_en", 64],
    ["has_article_en", 128],
    ["has_magisterium_en", 256],
  ] as const)("%s = %i", (bit, value) => {
    expect(flagsFromPipeline(only(bit))).toBe(value);
    expect(pipelineFromFlags(value)).toEqual(only(bit));
  });

  it("15 = transkript + diarizacija + sažetak + članak (najčešće u listinzima)", () => {
    expect(pipelineFromFlags(15)).toEqual(only("has_transcript", "has_diarized", "has_summary", "has_article"));
  });

  it("fromBits semantika: EN članak je bit 7 ILI bit 5", () => {
    // `VideoPipeline.fromBits`: hasArticleEn = bit(7) || bit(5).
    const hasArticleEn = (flags: number): boolean => {
      const p = pipelineFromFlags(flags);
      return p.has_article_en || p.has_translation_en;
    };
    expect(hasArticleEn(128)).toBe(true);
    expect(hasArticleEn(32)).toBe(true);
    expect(hasArticleEn(15)).toBe(false);
  });

  it("obrat je točan za svih 512 vrijednosti", () => {
    for (let f = 0; f <= ALL_PIPELINE_FLAGS; f++) expect(flagsFromPipeline(pipelineFromFlags(f))).toBe(f);
  });
});

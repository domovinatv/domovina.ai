import { describe, expect, it } from "vitest";
import { allFixtures, fixtures, LISTING_SLUGS, UNLISTED_IDS } from "./fixtures.ts";

// Glob koji ništa ne nađe vrati `{}` bez greške, pa bi svaki test „po svim
// fixtureima” tiho prošao nad nulom. Brojke su ovdje izričite.
describe("fixturei", () => {
  it("ima ih točno 20 (index, 3 listinga, 5 × 3 po epizodi, registry)", () => {
    expect(Object.keys(allFixtures)).toHaveLength(20);
  });

  it("svaka skupina ima očekivane ključeve", () => {
    expect([...fixtures.listings().keys()].sort()).toEqual(LISTING_SLUGS);
    expect([...fixtures.infos().keys()].sort()).toEqual(UNLISTED_IDS);
    expect([...fixtures.summaries().keys()].sort()).toEqual(UNLISTED_IDS);
    expect([...fixtures.manifests().keys()].sort()).toEqual(UNLISTED_IDS);
    expect(fixtures.index()).toBeTypeOf("object");
    expect(fixtures.registry()).toBeTypeOf("object");
  });

  it("svaki završava s jednim \\n (deterministički upis)", () => {
    for (const [path, text] of Object.entries(allFixtures)) {
      expect(text.endsWith("}\n") && !text.endsWith("\n\n"), path).toBe(true);
    }
  });

  it("mreža je zatvorena: fixturei se ne mogu dohvatiti s CDN-a", async () => {
    await expect(fetch("https://cdn.domovina.ai/data/KLPD-Meu4e8/info.json")).rejects.toThrow(
      /mreža je u testu zabranjena/,
    );
  });
});

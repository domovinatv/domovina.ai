// Ulaz plana uvoza iz fixturea, istim putem kao `scripts/import.mjs`:
// Tier 2 = ID-evi s `article.json` u key cacheu minus ID-evi iz Tier 1 listinga.
import { parseChannelIndex, parseChannelListing, parseEpisodeInfo, parseEpisodeSummary, parseRegistry } from "../../src/input/index.ts";
import { articleIds, parseKeyCache } from "../../src/ingest/keys.ts";
import type { PlanInput, Tier2Input } from "../../src/ingest/plan.ts";
import { fixtures } from "../input/fixtures.ts";

export function fixturePlanInput(): PlanInput {
  const index = parseChannelIndex(fixtures.index());
  const listings = [...fixtures.listings().values()].map((raw) => parseChannelListing(raw));
  const registry = parseRegistry(fixtures.registry());
  const files = parseKeyCache(fixtures.keyCache());
  const infos = fixtures.infos();
  const summaries = fixtures.summaries();
  const tier1 = new Set(listings.flatMap((l) => l.videos.map((v) => v.id)));
  const tier2: Tier2Input[] = articleIds(files)
    .filter((id) => !tier1.has(id))
    .map((id) => {
      const info = infos.get(id);
      const summary = summaries.get(id);
      return {
        id,
        info: info === undefined ? null : parseEpisodeInfo(info),
        summary: summary === undefined ? null : parseEpisodeSummary(summary),
        files: files.get(id) ?? new Set(),
      };
    });
  return { index, listings, registry, tier2 };
}

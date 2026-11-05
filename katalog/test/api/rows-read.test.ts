// `meta.rows_read` po ruti nad fixtureima (odluka 309): zbroj svih D1 upita
// zahtjeva, ≤ 3 × limit + konstanta. Isto nad 5000 sintetičkih epizoda:
// `rows-read-synthetic.test.ts` (odluka 313); `measure()` je u `helpers.ts`.
import { describe, expect, it } from "vitest";
import { brand, type Contract, measure, ROWS_READ_CONSTANT, seed } from "./helpers.ts";

const ROUTES: readonly { readonly path: string; readonly contract: Contract }[] = [
  { path: "days/2026-05-13", contract: "days" },
  { path: "days/2026-11-03", contract: "days" },
  { path: "channels", contract: "channels" },
  { path: "channels?tier=1", contract: "channels" },
  { path: "channels?tier=2", contract: "channels" },
  { path: "directory", contract: "directory" },
  { path: "channels/podcast_cuspajz/episodes", contract: "channel-episodes" },
  { path: "channels/subclub", contract: "channel-response" },
  { path: "episodes/UM2MWlNUp_1/card", contract: "card-response" },
];

describe("rows_read nad fixtureima", () => {
  const b = brand("s3-rows");

  it.each([1, 5, 30, 100])("limit %i: ≤ 3 × limit + konstanta", async (limit) => {
    if (limit === 1) await seed(b);
    const out: string[] = [];
    for (const { path, contract } of ROUTES) {
      const sep = path.includes("?") ? "&" : "?";
      const single = path.startsWith("channels/subclub") || path.startsWith("episodes/");
      // Rute jednog objekta nemaju limit; ključ cachea se razlikuje po `limit`
      // pa svaka iteracija mjeri miss, a ovdje ih mjerimo samo jednom.
      if (single && limit !== 1) continue;
      const n = await measure(b.host, single ? path : `${path}${sep}limit=${limit}`, contract);
      out.push(`${path} limit=${single ? "-" : limit}: ${n}`);
      expect(n, path).toBeLessThanOrEqual(3 * (single ? 1 : limit) + ROWS_READ_CONSTANT);
    }
    // Izmjerene vrijednosti (odluka 309) za zadanu veličinu stranice: promjena
    // obračuna u D1 ili plana upita mora se vidjeti.
    if (limit === 30) {
      expect(out).toEqual([
        "days/2026-05-13 limit=30: 7",
        "days/2026-11-03 limit=30: 4",
        "channels limit=30: 14",
        "channels?tier=1 limit=30: 10",
        "channels?tier=2 limit=30: 7",
        "directory limit=30: 14",
        "channels/podcast_cuspajz/episodes limit=30: 44",
      ]);
    }
  });
});

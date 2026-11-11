import { describe, expect, it } from "vitest";
import type { Cdn } from "../../scripts/lib/cdn.ts";
import { loadMagisteriumScores, magisteriumSizes, overallScore, type ScoreStore } from "../../scripts/lib/magisterium-scores.ts";

function fakeCdn(bodies: Record<string, string | null>): Cdn & { calls: string[] } {
  const calls: string[] = [];
  const get = (path: string): Promise<string | null> => {
    calls.push(path);
    return Promise.resolve(bodies[path] ?? null);
  };
  return {
    calls,
    getText: get,
    getRequired: async (p: string) => (await get(p)) ?? Promise.reject(new Error(p)),
    stats: () => ({ requests: calls.length, retries: 0, notFound: 0 }),
  } as unknown as Cdn & { calls: string[] };
}

describe("magisteriumSizes / overallScore", () => {
  it("samo data/<id>/article.magisterium.json, ne EN ni druge datoteke", () => {
    const m = magisteriumSizes(
      JSON.stringify({
        v: 2,
        sizes: {
          "data/abc/article.magisterium.json": 93579,
          "data/abc/article.magisterium.en.json": 164224,
          "data/def/article.json": 10,
        },
      }),
    );
    expect([...m]).toEqual([["abc", 93579]]);
  });

  it("cijeli broj 0–100, inače null", () => {
    expect(overallScore('{"overall_score":78}')).toBe(78);
    expect(overallScore('{"overall_score":101}')).toBeNull();
    expect(overallScore('{"overall_score":7.5}')).toBeNull();
    expect(overallScore("{}")).toBeNull();
    expect(overallScore("nije json")).toBeNull();
  });
});

function memoryStore(): ScoreStore & { text: string | null } {
  const s = {
    text: null as string | null,
    read: () => Promise.resolve(s.text),
    write: (t: string) => {
      s.text = t;
      return Promise.resolve();
    },
  };
  return s;
}

describe("loadMagisteriumScores", () => {
  it("dohvati jednom; ista veličina iz cachea; nova veličina ponovno; 404 se ne pamti", async () => {
    const store = memoryStore();
    const cdn = fakeCdn({
      "data/aaa/article.magisterium.json": '{"overall_score":78}',
      "data/bbb/article.magisterium.json": '{"overall_score":null}',
    });
    const sizes = new Map([
      ["aaa", 100],
      ["bbb", 200],
      ["ccc", 300],
    ]);
    const ids = ["aaa", "bbb", "ccc", "ddd"];

    const first = await loadMagisteriumScores({ ids, sizes, cdn, store, concurrency: 2 });
    expect([...first.scores].sort()).toEqual([
      ["aaa", 78],
      ["bbb", null],
    ]);
    expect(first.fetched).toBe(2);
    expect(cdn.calls.sort()).toEqual([
      "data/aaa/article.magisterium.json",
      "data/bbb/article.magisterium.json",
      "data/ccc/article.magisterium.json",
    ]);
    expect(Object.keys(JSON.parse(store.text ?? "{}") as Record<string, unknown>)).toEqual(["aaa", "bbb"]);

    cdn.calls.length = 0;
    const second = await loadMagisteriumScores({
      ids,
      sizes: new Map([...sizes, ["bbb", 201]]),
      cdn,
      store,
      concurrency: 2,
    });
    expect(second.cached).toBe(1);
    expect(cdn.calls.sort()).toEqual(["data/bbb/article.magisterium.json", "data/ccc/article.magisterium.json"]);
    expect(second.scores.get("aaa")).toBe(78);
  });
});

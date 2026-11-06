// `katalog drift-check` (scripts/lib/drift.ts): usporedba, exit kodovi kao
// ugovor, paginacija `ingest/ids`, `--sync` nad stubom servisa. Bez mreže:
// `fetch` se predaje (globalni je u `test/setup.ts` zatvoren).
import { describe, expect, it } from "vitest";
import type { ChannelRow, EpisodeRow } from "../../src/ingest/plan.ts";
import { createCdn } from "../../scripts/lib/cdn.ts";
import {
  CannotCheck,
  compare,
  EXIT_DRIFT,
  EXIT_OK,
  EXIT_UNKNOWN,
  exitCodeFor,
  fetchAllIds,
  formatReport,
  ingestBatches,
  readKeyCacheText,
  runDriftCheck,
  tokenFromDevVars,
  type DriftDeps,
  type IngestBody,
} from "../../scripts/lib/drift.ts";

const TOKEN = "tajni-token-0123456789abcdef";
const BASE = "https://katalog.test";

function keyCache(ids: readonly string[], extraFiles: Record<string, number> = {}): string {
  const sizes: Record<string, number> = { "channels/data/index.json": 1, ...extraFiles };
  for (const id of ids) {
    sizes[`data/${id}/article.json`] = 10;
    sizes[`data/${id}/info.json`] = 5;
  }
  return JSON.stringify({ v: 2, sizes });
}

const urlOf = (input: RequestInfo | URL): string =>
  typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

function channel(slug: string): ChannelRow {
  return {
    slug,
    youtubeChannelId: null,
    name: slug,
    tier: 2,
    lang: null,
    avatar: null,
    processedCount: 1,
    latestPublishedDate: null,
    unregistered: false,
  };
}

function episode(id: string, channelSlug: string | null = "kanal"): EpisodeRow {
  return {
    id,
    channelSlug,
    title: id,
    titleHr: null,
    publishedDate: "2026-11-01",
    durationSeconds: 60,
    tier: 2,
    lang: null,
    magisteriumScore: null,
    flags: 0,
    variantOf: null,
  };
}

interface Call {
  readonly method: string;
  readonly url: URL;
  readonly auth: string | null;
  readonly body: unknown;
}

/**
 * Stub servisa: `ingest/ids` paginira nad `d1` (ID ASC), `POST ingest` dodaje
 * epizode (i odbija epizodu čiji kanal nije poslan ranije ili u istom pozivu).
 */
function fakeService(initial: readonly string[], opts: { applyIngest?: boolean } = {}) {
  const d1 = new Set(initial);
  const channels = new Set<string>(["kanal"]);
  const calls: Call[] = [];
  const handle = (input: RequestInfo | URL, init?: RequestInit): Response => {
    const url = new URL(urlOf(input));
    const method = init?.method ?? "GET";
    const headers = new Headers(init?.headers);
    const body: unknown = typeof init?.body === "string" ? JSON.parse(init.body) : undefined;
    calls.push({ method, url, auth: headers.get("authorization"), body });
    if (headers.get("authorization") !== `Bearer ${TOKEN}`) return json({ ok: false, error: "unauthorized" }, 401);
    if (method === "GET" && url.pathname === "/api/katalog/v1/ingest/ids") {
      const limit = Number(url.searchParams.get("limit"));
      const after = url.searchParams.get("after");
      const sorted = [...d1].sort();
      const page = sorted.filter((id) => after === null || id > after).slice(0, limit);
      const last = page.at(-1);
      const next = last !== undefined && sorted.some((id) => id > last) ? last : null;
      return json({ ids: page, next, meta: { rows_read: page.length } });
    }
    if (method === "POST" && url.pathname === "/api/katalog/v1/ingest") {
      const b = body as IngestBody;
      for (const c of b.channels) channels.add(c.slug);
      for (const e of b.episodes) {
        if (e.channelSlug !== null && !channels.has(e.channelSlug)) {
          return json({ ok: false, error: "unknown_channel", detail: "episodes[0].channelSlug" }, 409);
        }
      }
      let n = 0;
      if (opts.applyIngest !== false) {
        for (const e of b.episodes) {
          if (d1.has(e.id)) continue;
          d1.add(e.id);
          n++;
        }
      }
      return json({ ok: true, changes: { channels: b.channels.length, episodes: n }, catalog: { version: 7 } });
    }
    return json({ ok: false, error: "not_found" }, 404);
  };
  const fetchStub: typeof fetch = (input, init) => Promise.resolve(handle(input, init));
  return { d1, calls, fetch: fetchStub };
}

function deps(over: Partial<DriftDeps> & Pick<DriftDeps, "fetch">): DriftDeps {
  return {
    base: BASE,
    token: TOKEN,
    keyCachePath: "/fake/.r2_keys_cache.json",
    readKeyCache: () => Promise.resolve(keyCache(["a1", "b2", "c3"])),
    sync: false,
    buildPlan: () => Promise.reject(new Error("buildPlan se ne smije zvati")),
    ...over,
  };
}

describe("compare", () => {
  it("poravnato: isti skupovi → 0", () => {
    const c = compare(["b", "a"], ["a", "b"]);
    expect(c).toEqual({ r2: 2, d1: 2, missing: [], extra: [] });
    expect(exitCodeFor(c)).toBe(EXIT_OK);
  });

  it("missing = R2 \\ D1, sortirano → drift", () => {
    const c = compare(["c", "a", "b"], ["b"]);
    expect(c.missing).toEqual(["a", "c"]);
    expect(exitCodeFor(c)).toBe(EXIT_DRIFT);
  });

  it("extra (Tier 1 bez članka, varijante) ne mijenja exit kod", () => {
    const c = compare(["a"], ["a", "z", "y"]);
    expect(c.extra).toEqual(["y", "z"]);
    expect(c.missing).toEqual([]);
    expect(exitCodeFor(c)).toBe(EXIT_OK);
  });
});

describe("readKeyCacheText", () => {
  it("vadi samo ID-eve s article.json", () => {
    const { articles } = readKeyCacheText(keyCache(["b", "a"], { "data/x/info.json": 1, "images/a/t.png": 1 }));
    expect(articles).toEqual(["a", "b"]);
  });

  it.each([
    ["nije JSON", "{ne"],
    ["kriva verzija", JSON.stringify({ v: 3, sizes: {} })],
    ["bez sizes", JSON.stringify({ v: 2 })],
    ["nijedan članak", JSON.stringify({ v: 2, sizes: { "data/a/info.json": 1 } })],
  ])("%s → CannotCheck", (_, text) => {
    expect(() => readKeyCacheText(text)).toThrow(CannotCheck);
  });
});

describe("tokenFromDevVars", () => {
  it("čita redak INGEST_TOKEN, i s navodnicima", () => {
    expect(tokenFromDevVars("# x\nCLOUDFLARE_ACCOUNT_ID=1\nINGEST_TOKEN=abc\n")).toBe("abc");
    expect(tokenFromDevVars('INGEST_TOKEN="q w"')).toBe("q w");
    expect(tokenFromDevVars("INGEST_TOKEN=\nX=1")).toBeNull();
    expect(tokenFromDevVars("X=1")).toBeNull();
  });
});

describe("fetchAllIds", () => {
  it("prolazi sve stranice (after = next) s Bearer tokenom", async () => {
    const ids = Array.from({ length: 7 }, (_, i) => `id${i}`);
    const svc = fakeService(ids);
    const r = await fetchAllIds({ base: BASE, token: TOKEN, fetch: svc.fetch }, 3);
    expect(r.ids).toEqual(ids);
    expect(r.pages).toBe(3);
    expect(r.rowsRead).toBe(7);
    expect(svc.calls.map((c) => c.url.searchParams.get("after"))).toEqual([null, "id2", "id5"]);
    expect(svc.calls.every((c) => c.url.searchParams.get("limit") === "3")).toBe(true);
    expect(svc.calls.every((c) => c.auth === `Bearer ${TOKEN}`)).toBe(true);
  });

  it("next bez napretka → CannotCheck (nema beskonačne petlje)", async () => {
    const stuck: typeof fetch = () => Promise.resolve(json({ ids: ["a"], next: "a", meta: { rows_read: 1 } }));
    let n = 0;
    const counting: typeof fetch = (i, init) => {
      n++;
      return stuck(i, init);
    };
    await expect(fetchAllIds({ base: BASE, token: TOKEN, fetch: counting })).rejects.toThrow(CannotCheck);
    expect(n).toBe(2);
  });
});

describe("runDriftCheck: exit kodovi", () => {
  it("poravnato preko više stranica → 0, plan se ne gradi", async () => {
    const ids = Array.from({ length: 12_000 }, (_, i) => `e${String(i).padStart(5, "0")}`);
    const svc = fakeService(ids);
    const r = await runDriftCheck(deps({ fetch: svc.fetch, readKeyCache: () => Promise.resolve(keyCache(ids)) }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.status).toBe("ok");
    expect(r.before?.idPages).toBe(3);
    expect(r.before).toMatchObject({ r2: 12_000, d1: 12_000, missing: [], extraCount: 0 });
  });

  it("drift bez --sync → 1, missing u izvještaju", async () => {
    const svc = fakeService(["a1", "z9"]);
    const r = await runDriftCheck(deps({ fetch: svc.fetch }));
    expect(r.exitCode).toBe(EXIT_DRIFT);
    expect(r.before?.missing).toEqual(["b2", "c3"]);
    expect(r.before?.extraCount).toBe(1);
    expect(formatReport(r).join("\n")).toMatch(/missing\s+2 {2}b2 c3/);
  });

  it("nečitljiv / nepostojeći cache → 2", async () => {
    const svc = fakeService(["a1"]);
    const enoent = await runDriftCheck(
      deps({ fetch: svc.fetch, readKeyCache: () => Promise.reject(new Error("ENOENT: no such file")) }),
    );
    expect(enoent.exitCode).toBe(EXIT_UNKNOWN);
    expect(enoent.error).toMatch(/ENOENT/);
    const garbage = await runDriftCheck(deps({ fetch: svc.fetch, readKeyCache: () => Promise.resolve("{\"v\":") }));
    expect(garbage.exitCode).toBe(EXIT_UNKNOWN);
    expect(svc.calls).toHaveLength(0);
  });

  it("401 → 2, token se ne pojavljuje ni u izvještaju ni u ispisu", async () => {
    const leaky: typeof fetch = () => Promise.resolve(new Response(`bad token ${TOKEN}`, { status: 401 }));
    const r = await runDriftCheck(deps({ fetch: leaky }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toMatch(/401/);
    expect(JSON.stringify(r)).not.toContain(TOKEN);
    expect(formatReport(r, true).join("\n")).not.toContain(TOKEN);
  });

  it("krivi token na stubu → 2 (ne drift)", async () => {
    const svc = fakeService([]);
    const r = await runDriftCheck(deps({ fetch: svc.fetch, token: "drugi-token-xxxxxxxx" }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
  });

  it.each([
    ["5xx", () => Promise.resolve(json({ ok: false, error: "internal" }, 500)), /500 internal/],
    ["503 ingest_disabled", () => Promise.resolve(json({ ok: false, error: "ingest_disabled" }, 503)), /ingest_disabled/],
    ["mreža", () => Promise.reject(new TypeError("fetch failed")), /mreža/],
    ["ne-JSON", () => Promise.resolve(new Response("<html>", { status: 200 })), /nije JSON/],
    ["krivi oblik", () => Promise.resolve(json({ ids: "a" })), /ids: string\[\]/],
  ] satisfies [string, typeof fetch, RegExp][])("%s → 2", async (_, f, re) => {
    const r = await runDriftCheck(deps({ fetch: f }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toMatch(re);
  });

  it("nema tokena → 2 bez ijednog poziva", async () => {
    const svc = fakeService([]);
    const r = await runDriftCheck(deps({ fetch: svc.fetch, token: null }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toMatch(/INGEST_TOKEN/);
    expect(svc.calls).toHaveLength(0);
  });
});

describe("runDriftCheck --sync", () => {
  const plan = {
    channels: [channel("kanal"), channel("novi")],
    episodes: [episode("a1"), episode("b2", "novi"), episode("c3", null)],
  };

  it("drift → puni plan na ingest → ponovno mjerenje → 0 (synced)", async () => {
    const svc = fakeService(["a1"]);
    const r = await runDriftCheck(deps({ fetch: svc.fetch, sync: true, buildPlan: () => Promise.resolve(plan) }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.status).toBe("synced");
    expect(r.sync).toMatchObject({ calls: 1, converged: true, changes: { channels: 2, episodes: 2 } });
    expect(r.sync?.after?.missing).toEqual([]);
    const post = svc.calls.find((c) => c.method === "POST");
    expect(post?.url.pathname).toBe("/api/katalog/v1/ingest");
    expect(post?.body).toMatchObject({ source: "drift-check" });
    expect(svc.calls.map((c) => c.method)).toEqual(["GET", "POST", "GET"]);
  });

  it("poravnato uz --sync ne piše ništa", async () => {
    const svc = fakeService(["a1", "b2", "c3"]);
    const r = await runDriftCheck(deps({ fetch: svc.fetch, sync: true }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.status).toBe("ok");
    expect(svc.calls.some((c) => c.method === "POST")).toBe(false);
  });

  it("upis prošao, a D1 i dalje zaostaje → 2 (nije konvergiralo)", async () => {
    const svc = fakeService(["a1"], { applyIngest: false });
    const r = await runDriftCheck(deps({ fetch: svc.fetch, sync: true, buildPlan: () => Promise.resolve(plan) }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.sync?.converged).toBe(false);
    expect(r.error).toMatch(/konvergirao/);
  });

  it("409 unknown_channel → 2", async () => {
    const svc = fakeService(["a1"]);
    const bad = { channels: [], episodes: [episode("b2", "nepoznat")] };
    const r = await runDriftCheck(deps({ fetch: svc.fetch, sync: true, buildPlan: () => Promise.resolve(bad) }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toMatch(/409 unknown_channel \(episodes\[0\]\.channelSlug\)/);
  });

  it("TypeError u izgradnji plana → 2, nikad 1", async () => {
    const svc = fakeService(["a1"]);
    const r = await runDriftCheck(
      deps({
        fetch: svc.fetch,
        sync: true,
        buildPlan: () => Promise.reject(new TypeError("Cannot read properties of undefined (reading 'length')")),
      }),
    );
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
  });
});

describe("ingestBatches", () => {
  const eps = (n: number) => Array.from({ length: n }, (_, i) => episode(`e${i}`));
  const chs = (n: number) => Array.from({ length: n }, (_, i) => channel(`c${i}`));
  const shape = (b: IngestBody[]) => b.map((x) => [x.channels.length, x.episodes.length]);

  it("kanali prije epizoda, ≤ 200 / ≤ 500 po pozivu", () => {
    const b = ingestBatches({ channels: chs(450), episodes: eps(1200) });
    expect(shape(b)).toEqual([
      [200, 0],
      [200, 0],
      [50, 500],
      [0, 500],
      [0, 200],
    ]);
    expect(b.every((x) => x.source === "drift-check")).toBe(true);
  });

  it("stvarna veličina (162 kanala, 3670 epizoda) = 8 poziva", () => {
    expect(ingestBatches({ channels: chs(162), episodes: eps(3670) })).toHaveLength(8);
  });

  it("rubni slučajevi", () => {
    expect(shape(ingestBatches({ channels: [], episodes: eps(3) }))).toEqual([[0, 3]]);
    expect(shape(ingestBatches({ channels: chs(3), episodes: [] }))).toEqual([[3, 0]]);
    expect(ingestBatches({ channels: [], episodes: [] })).toEqual([]);
  });
});

describe("createCdn (dijeli ga uvoznik)", () => {
  it("404 se ponovi jednom s cache-busterom; drugi 404 = null", async () => {
    const urls: string[] = [];
    const cdn = createCdn({
      base: "https://cdn.test/",
      fetch: (input) => {
        urls.push(urlOf(input));
        return Promise.resolve(new Response("", { status: 404 }));
      },
    });
    expect(await cdn.getText("data/x/info.json")).toBeNull();
    expect(urls).toHaveLength(2);
    expect(urls[1]).toMatch(/^https:\/\/cdn\.test\/data\/x\/info\.json\?cb=\d+$/);
    expect(cdn.stats).toEqual({ get: 2, notFound: 1, retried: 1, missingAfterRetry: 1 });
    await expect(cdn.getRequired("data/x/info.json")).rejects.toThrow(/404 i nakon cache-bustera/);
  });

  it("drugi pokušaj 200 vraća tekst; 500 baca", async () => {
    let n = 0;
    const flaky = createCdn({
      base: "https://cdn.test/",
      fetch: () => Promise.resolve(n++ === 0 ? new Response("", { status: 404 }) : new Response("ok")),
    });
    expect(await flaky.getText("a")).toBe("ok");
    const broken = createCdn({ base: "https://cdn.test/", fetch: () => Promise.resolve(new Response("", { status: 500 })) });
    await expect(broken.getText("a")).rejects.toThrow(/HTTP 500/);
  });
});

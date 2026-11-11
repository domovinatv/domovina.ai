// `katalog ingest-episode` (scripts/lib/ingest-episodes.ts): odabir redaka s
// brojkama iz punog plana, mapa kanala za episode.json (`first_seen`), exit
// kodovi kao ugovor za run_pipeline.sh, i `fresh` CDN. Bez mreže: `fetch` se predaje.
import { describe, expect, it } from "vitest";
import type { ChannelRow, EpisodeRow } from "../../src/ingest/plan.ts";
import { createCdn } from "../../scripts/lib/cdn.ts";
import { EXIT_DRIFT, EXIT_OK, EXIT_UNKNOWN, MAX_EPISODES_PER_CALL, type IngestBody } from "../../scripts/lib/drift.ts";
import {
  buildChannelMap,
  formatIngestReport,
  parseChannelMap,
  runIngestEpisodes,
  selectRows,
  type IngestEpisodesDeps,
} from "../../scripts/lib/ingest-episodes.ts";

const TOKEN = "tajni-token-0123456789abcdef";
const BASE = "https://katalog.test";
const NOW = new Date("2026-11-06T12:00:00Z");

function channel(slug: string, tier: 1 | 2, processedCount: number): ChannelRow {
  return {
    slug,
    youtubeChannelId: null,
    name: `Kanal ${slug}`,
    tier,
    lang: null,
    avatar: null,
    processedCount,
    latestPublishedDate: "2026-11-05",
    unregistered: false,
  };
}

function episode(id: string, channelSlug: string | null, tier: 1 | 2 = 2): EpisodeRow {
  return {
    id,
    channelSlug,
    title: `Epizoda ${id}`,
    titleHr: null,
    publishedDate: "2026-11-05",
    durationSeconds: 3600,
    tier,
    lang: "hr",
    magisteriumScore: null,
    flags: 0,
    variantOf: null,
    publishedAt: "2026-11-05T18:00:00Z",
  };
}

const PLAN = {
  channels: [channel("prati", 1, 40), channel("novi", 2, 3), channel("drugi", 2, 7)],
  episodes: [
    episode("aaaaaaaaaaa", "prati", 1),
    episode("bbbbbbbbbbb", "novi"),
    episode("ccccccccccc", "novi"),
    episode("ddddddddddd", "drugi"),
    episode("eeeeeeeeeee", null),
  ],
};

const urlOf = (input: RequestInfo | URL): string =>
  typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

const json = (body: unknown, status = 200): Response =>
  new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });

/** Stub servisa: bilježi tijela POST /ingest. */
function service(status = 200): { fetch: typeof fetch; posts: IngestBody[]; auth: (string | null)[] } {
  const posts: IngestBody[] = [];
  const auth: (string | null)[] = [];
  const stub = ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = urlOf(input);
    if (!url.startsWith(`${BASE}/api/katalog/v1/ingest`)) throw new Error(`neočekivan URL ${url}`);
    auth.push(new Headers(init?.headers).get("authorization"));
    if (status !== 200) return Promise.resolve(json({ error: "internal" }, status));
    const body = JSON.parse(init?.body as string) as IngestBody;
    posts.push(body);
    return Promise.resolve(
      json({ ok: true, changes: { channels: body.channels.length, episodes: body.episodes.length }, catalog: "9" }),
    );
  }) as typeof fetch;
  return { fetch: stub, posts, auth };
}

function deps(over: Partial<IngestEpisodesDeps> = {}): IngestEpisodesDeps {
  return {
    base: BASE,
    token: TOKEN,
    fetch: service().fetch,
    ids: [],
    all: false,
    dryRun: false,
    buildPlan: () => Promise.resolve(PLAN),
    now: () => NOW,
    ...over,
  };
}

describe("selectRows", () => {
  it("šalje tražene epizode i njihove kanale s brojkama iz PUNOG plana", () => {
    const s = selectRows(PLAN, ["bbbbbbbbbbb"]);
    expect(s.episodes.map((e) => e.id)).toEqual(["bbbbbbbbbbb"]);
    // processedCount 3, ne 1: brojka kanala dolazi iz cijelog plana.
    expect(s.channels).toEqual([channel("novi", 2, 3)]);
    expect(s.missing).toEqual([]);
  });

  it("epizoda bez kanala ide bez retka kanala", () => {
    const s = selectRows(PLAN, ["eeeeeeeeeee"]);
    expect(s.channels).toEqual([]);
    expect(s.episodes).toHaveLength(1);
  });

  it("ID kojeg nema u planu je missing, ostali idu", () => {
    const s = selectRows(PLAN, ["zzzzzzzzzzz", "aaaaaaaaaaa", "aaaaaaaaaaa"]);
    expect(s.missing).toEqual(["zzzzzzzzzzz"]);
    expect(s.episodes.map((e) => e.id)).toEqual(["aaaaaaaaaaa"]);
    expect(s.channels.map((c) => c.slug)).toEqual(["prati"]);
  });

  it("epizoda koja pokazuje na kanal izvan plana je greška, ne 409 na pola posla", () => {
    const broken = { channels: [], episodes: [episode("bbbbbbbbbbb", "novi")] };
    expect(() => selectRows(broken, ["bbbbbbbbbbb"])).toThrow(/novi/);
  });
});

describe("mapa kanala", () => {
  it("prvo sijanje: sve epizode first_seen null", () => {
    const m = buildChannelMap(PLAN, null, NOW.toISOString());
    expect(m.seeded_at).toBe(NOW.toISOString());
    expect(Object.values(m.episodes).every((e) => e.first_seen === null)).toBe(true);
    expect(m.episodes.bbbbbbbbbbb?.channel).toEqual({ slug: "novi", name: "Kanal novi", tier: 2 });
    expect(m.episodes.eeeeeeeeeee?.channel).toBeNull();
  });

  it("nova epizoda dobiva first_seen, stare ga nasljeđuju, seeded_at ostaje", () => {
    const seed = buildChannelMap({ channels: PLAN.channels, episodes: PLAN.episodes.slice(0, 2) }, null, "2026-11-01T00:00:00Z");
    const later = buildChannelMap(PLAN, seed, NOW.toISOString());
    expect(later.seeded_at).toBe("2026-11-01T00:00:00Z");
    expect(later.episodes.aaaaaaaaaaa?.first_seen).toBeNull();
    expect(later.episodes.ccccccccccc?.first_seen).toBe(NOW.toISOString());
    const again = buildChannelMap(PLAN, later, "2026-11-07T00:00:00Z");
    expect(again.episodes.ccccccccccc?.first_seen).toBe(NOW.toISOString());
  });

  it("parseChannelMap: nečitljivo ili druga verzija = nema prethodne mape", () => {
    expect(parseChannelMap(null)).toBeNull();
    expect(parseChannelMap("{")).toBeNull();
    expect(parseChannelMap(JSON.stringify({ v: 2, seeded_at: "x", episodes: {} }))).toBeNull();
    expect(parseChannelMap(JSON.stringify({ v: 1, seeded_at: "x", episodes: [] }))).toBeNull();
    const ok = buildChannelMap(PLAN, null, NOW.toISOString());
    expect(parseChannelMap(JSON.stringify(ok))).toEqual(ok);
  });
});

describe("runIngestEpisodes", () => {
  it("jedna epizoda: jedan POST, source pipeline, Bearer token, exit 0", async () => {
    const svc = service();
    const r = await runIngestEpisodes(deps({ fetch: svc.fetch, ids: ["ccccccccccc"] }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.status).toBe("ok");
    expect(svc.posts).toHaveLength(1);
    expect(svc.posts[0]?.source).toBe("pipeline");
    expect(svc.posts[0]?.channels.map((c) => c.slug)).toEqual(["novi"]);
    expect(svc.posts[0]?.episodes.map((e) => e.id)).toEqual(["ccccccccccc"]);
    expect(svc.auth).toEqual([`Bearer ${TOKEN}`]);
    expect(r.catalog).toBe("9");
  });

  it("--all šalje cijeli plan, kanali u prvom pozivu", async () => {
    const svc = service();
    const r = await runIngestEpisodes(deps({ fetch: svc.fetch, all: true }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(svc.posts[0]?.channels).toHaveLength(3);
    expect(svc.posts.flatMap((p) => p.episodes)).toHaveLength(5);
  });

  it("veliki --all se reže na ≤ 500 epizoda po pozivu", async () => {
    const svc = service();
    const many = Array.from({ length: 1201 }, (_, i) => episode(`x${String(i).padStart(10, "0")}`, "novi"));
    const r = await runIngestEpisodes(
      deps({ fetch: svc.fetch, all: true, buildPlan: () => Promise.resolve({ channels: PLAN.channels, episodes: many }) }),
    );
    expect(r.exitCode).toBe(EXIT_OK);
    expect(svc.posts.map((p) => p.episodes.length)).toEqual([MAX_EPISODES_PER_CALL, MAX_EPISODES_PER_CALL, 201]);
  });

  it("ID kojeg nema u planu: ostali upisani, exit 1 (partial)", async () => {
    const svc = service();
    const r = await runIngestEpisodes(deps({ fetch: svc.fetch, ids: ["zzzzzzzzzzz", "bbbbbbbbbbb"] }));
    expect(r.exitCode).toBe(EXIT_DRIFT);
    expect(r.status).toBe("partial");
    expect(r.missing).toEqual(["zzzzzzzzzzz"]);
    expect(svc.posts).toHaveLength(1);
  });

  it("nijedan traženi ID u planu: bez POST-a, exit 1", async () => {
    const svc = service();
    const r = await runIngestEpisodes(deps({ fetch: svc.fetch, ids: ["zzzzzzzzzzz"] }));
    expect(r.exitCode).toBe(EXIT_DRIFT);
    expect(svc.posts).toHaveLength(0);
  });

  it("nema tokena: exit 2 i bez plana", async () => {
    let built = false;
    const r = await runIngestEpisodes(
      deps({ token: null, ids: ["bbbbbbbbbbb"], buildPlan: () => { built = true; return Promise.resolve(PLAN); } }),
    );
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(built).toBe(false);
  });

  it("ID-evi i --all zajedno, ili ništa: exit 2", async () => {
    expect((await runIngestEpisodes(deps({ ids: ["bbbbbbbbbbb"], all: true }))).exitCode).toBe(EXIT_UNKNOWN);
    expect((await runIngestEpisodes(deps())).exitCode).toBe(EXIT_UNKNOWN);
  });

  it("5xx servisa: exit 2, mapa se ne piše, token se ne pojavljuje u grešci", async () => {
    const writes: string[] = [];
    const r = await runIngestEpisodes(
      deps({
        fetch: service(500).fetch,
        ids: ["bbbbbbbbbbb"],
        channelMap: { read: () => Promise.resolve(null), write: (t) => { writes.push(t); return Promise.resolve(); } },
      }),
    );
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(writes).toEqual([]);
    expect(r.error).toMatch(/HTTP 500/);
    expect(formatIngestReport(r).join("\n")).not.toContain(TOKEN);
  });

  it("plan pao: exit 2, greška bez tokena", async () => {
    const r = await runIngestEpisodes(deps({ ids: ["bbbbbbbbbbb"], buildPlan: () => Promise.reject(new Error(`CDN pao ${TOKEN}`)) }));
    expect(r.exitCode).toBe(EXIT_UNKNOWN);
    expect(r.error).toBe("CDN pao ***");
  });

  it("mapa se piše za cijeli plan, nasljeđuje first_seen i nije u dry-runu", async () => {
    const prev = buildChannelMap({ channels: PLAN.channels, episodes: PLAN.episodes.slice(0, 4) }, null, "2026-11-01T00:00:00Z");
    let stored: string | null = JSON.stringify(prev);
    const channelMap = {
      read: () => Promise.resolve(stored),
      write: (t: string) => { stored = t; return Promise.resolve(); },
    };
    const r = await runIngestEpisodes(deps({ ids: ["eeeeeeeeeee"], channelMap }));
    expect(r.exitCode).toBe(EXIT_OK);
    expect(r.channelMap).toEqual({ episodes: 5, newSinceSeed: 1, seeded: false });
    const map = parseChannelMap(stored);
    expect(map?.episodes.eeeeeeeeeee?.first_seen).toBe(NOW.toISOString());
    expect(map?.episodes.aaaaaaaaaaa?.first_seen).toBeNull();

    const before = stored;
    const svc = service();
    const dry = await runIngestEpisodes(deps({ fetch: svc.fetch, ids: ["bbbbbbbbbbb"], dryRun: true, token: null, channelMap }));
    expect(dry.exitCode).toBe(EXIT_OK);
    expect(dry.status).toBe("dry-run");
    expect(svc.posts).toHaveLength(0);
    expect(stored).toBe(before);
  });
});

describe("createCdn fresh", () => {
  function recorder(statusFor: (url: string) => number): { fetch: typeof fetch; urls: string[] } {
    const urls: string[] = [];
    const stub = ((input: RequestInfo | URL) => {
      const url = urlOf(input);
      urls.push(url);
      return Promise.resolve(new Response("{}", { status: statusFor(url) }));
    }) as typeof fetch;
    return { fetch: stub, urls };
  }

  it("listinzi kanala uvijek s jedinstvenim busterom, data/ bez njega", async () => {
    const rec = recorder(() => 200);
    const cdn = createCdn({ base: "https://cdn.test/", fetch: rec.fetch, fresh: true, now: () => 1234 });
    await cdn.getText("channels/data/index.json");
    await cdn.getText("data/x/info.json");
    expect(rec.urls).toEqual(["https://cdn.test/channels/data/index.json?cb=1234", "https://cdn.test/data/x/info.json"]);
  });

  it("404 retry s jedinstvenim busterom (ne 5-minutnim bucketom aplikacije)", async () => {
    const rec = recorder((u) => (u.includes("?cb=") ? 200 : 404));
    const cdn = createCdn({ base: "https://cdn.test/", fetch: rec.fetch, fresh: true, now: () => 1234 });
    expect(await cdn.getText("data/x/info.json")).toBe("{}");
    expect(rec.urls.at(-1)).toBe("https://cdn.test/data/x/info.json?cb=1234");
  });

  it("bez fresh: ponašanje kao prije (listing bez bustera)", async () => {
    const rec = recorder(() => 200);
    const cdn = createCdn({ base: "https://cdn.test/", fetch: rec.fetch });
    await cdn.getText("channels/data/index.json");
    expect(rec.urls).toEqual(["https://cdn.test/channels/data/index.json"]);
  });
});

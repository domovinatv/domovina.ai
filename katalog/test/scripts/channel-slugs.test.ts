// `channel-slugs-sync` (scripts/lib/channel-slugs.ts): slug → UC iz kataloga uz
// pad na registry, razlika prema `channel_slugs`, HTTP nad stubom. Bez mreže.
import { describe, expect, it } from "vitest";
import {
  buildSlugMap,
  diffSlugs,
  fetchCatalogChannels,
  fetchChannelSlugs,
  redactKey,
  upsertChannelSlugs,
  valueFromEnvText,
} from "../../scripts/lib/channel-slugs.ts";
import { parseRegistry } from "../../src/input/index.ts";
import { registryUcBySlug } from "../../src/ingest/plan.ts";

const urlOf = (input: RequestInfo | URL): string =>
  typeof input === "string" ? input : input instanceof URL ? input.href : input.url;

const UC_A = "UCaaaaaaaaaaaaaaaaaaaaaa";
const UC_B = "UCbbbbbbbbbbbbbbbbbbbbbb";
const UC_L = "UCHBZvDkQfz4A_fi-QbsY_lw";

const registry = parseRegistry({
  podcasts: [
    { slug: "launched", display_name: "Launched", youtube: { type: "playlist", channel_id: UC_L }, tracking: { enabled: true } },
    { slug: "dijalog", display_name: "DijaLOG", youtube: { type: "audio-only" }, tracking: { enabled: true } },
    { slug: "40-dana", display_name: "40 dana", youtube: { channel_id: UC_B }, tracking: { enabled: true } },
  ],
});

describe("buildSlugMap", () => {
  it("UC iz kataloga, pad na registry (i CDN oblik sluga), bez UC-a se javlja", () => {
    const m = buildSlugMap(
      [
        { slug: "zadnji", youtubeChannelId: UC_A },
        { slug: "launched", youtubeChannelId: null },
        { slug: "dijalog", youtubeChannelId: null },
        { slug: "40_dana", youtubeChannelId: null },
        { slug: "playlista_1", youtubeChannelId: UC_A },
        { slug: "nevaljan", youtubeChannelId: "@handle" },
      ],
      registryUcBySlug(registry),
    );
    expect([...m.map]).toEqual([
      ["40_dana", UC_B],
      ["launched", UC_L],
      ["playlista_1", UC_A],
      ["zadnji", UC_A],
    ]);
    expect(m.fromRegistry).toEqual(["40_dana", "launched"]);
    expect(m.withoutUc).toEqual(["dijalog", "nevaljan"]);
  });

  it("katalog ima prednost pred registryjem", () => {
    const m = buildSlugMap([{ slug: "launched", youtubeChannelId: UC_A }], registryUcBySlug(registry));
    expect(m.map.get("launched")).toBe(UC_A);
    expect(m.fromRegistry).toEqual([]);
  });
});

describe("diffSlugs", () => {
  it("novi, drugi UC, isti; slug samo u cilju se ne briše", () => {
    const d = diffSlugs(
      new Map([
        ["a", UC_A],
        ["b", UC_B],
        ["c", UC_A],
      ]),
      new Map([
        ["a", UC_A],
        ["b", UC_A],
        ["stari", UC_B],
      ]),
    );
    expect(d.insert).toEqual([{ slug: "c", youtube_channel_id: UC_A }]);
    expect(d.update).toEqual([{ slug: "b", youtube_channel_id: UC_B, from: UC_A }]);
    expect(d.unchanged).toBe(1);
    expect(d.onlyInTarget).toEqual(["stari"]);
  });

  it("idempotentno: nakon upisa nema razlike", () => {
    const want = new Map([["a", UC_A]]);
    const d = diffSlugs(want, new Map(want));
    expect(d.insert.length + d.update.length).toBe(0);
  });
});

describe("HTTP", () => {
  it("katalog: sve stranice preko `cursor`", async () => {
    const seen: string[] = [];
    const f = ((input: RequestInfo | URL) => {
      const url = new URL(urlOf(input));
      seen.push(url.search);
      const page = url.searchParams.get("cursor");
      const body =
        page === null
          ? { items: [{ slug: "a", youtube_channel_id: UC_A }], next: "p2" }
          : { items: [{ slug: "b", youtube_channel_id: null }], next: null };
      return Promise.resolve(Response.json(body));
    }) as typeof fetch;
    const rows = await fetchCatalogChannels(f, "https://k.test");
    expect(rows).toEqual([
      { slug: "a", youtubeChannelId: UC_A },
      { slug: "b", youtubeChannelId: null },
    ]);
    expect(seen).toEqual(["?limit=100", "?limit=100&cursor=p2"]);
  });

  it("channel_slugs: zaglavlja sheme i ključa; upsert merge-duplicates", async () => {
    const calls: { method: string; url: string; headers: Headers; body: string | null }[] = [];
    const f = ((input: RequestInfo | URL, init?: RequestInit) => {
      calls.push({
        method: init?.method ?? "GET",
        url: urlOf(input),
        headers: new Headers(init?.headers),
        body: typeof init?.body === "string" ? init.body : null,
      });
      if ((init?.method ?? "GET") === "GET") return Promise.resolve(Response.json([{ slug: "a", youtube_channel_id: UC_A }]));
      return Promise.resolve(new Response(null, { status: 201 }));
    }) as typeof fetch;
    expect(await fetchChannelSlugs(f, "https://api.test", "anon-0123456789")).toEqual(new Map([["a", UC_A]]));
    expect(calls[0]?.headers.get("accept-profile")).toBe("domovina_ai");
    expect(calls[0]?.headers.get("apikey")).toBe("anon-0123456789");

    const n = await upsertChannelSlugs(f, "https://api.test", "svc-0123456789", [{ slug: "b", youtube_channel_id: UC_B }], new Date("2026-11-11T12:00:00Z"));
    expect(n).toBe(1);
    const post = calls[1];
    expect(post?.method).toBe("POST");
    expect(post?.url).toBe("https://api.test/rest/v1/channel_slugs?on_conflict=slug");
    expect(post?.headers.get("content-profile")).toBe("domovina_ai");
    expect(post?.headers.get("prefer")).toBe("resolution=merge-duplicates,return=minimal");
    expect(JSON.parse(post?.body ?? "null")).toEqual([{ slug: "b", youtube_channel_id: UC_B, updated_at: "2026-11-11T12:00:00.000Z" }]);
    // Prazan upis ne zove mrežu.
    expect(await upsertChannelSlugs(f, "https://api.test", "svc", [], new Date())).toBe(0);
    expect(calls).toHaveLength(2);
  });

  it("HTTP greška se baca s porukom, ključ se reže", async () => {
    const f = (() => Promise.resolve(new Response("ključ svc-0123456789 odbijen", { status: 401 }))) as typeof fetch;
    const err = await fetchChannelSlugs(f, "https://api.test", "svc-0123456789").catch((e: unknown) => e);
    expect(err).toBeInstanceOf(Error);
    expect(redactKey((err as Error).message, "svc-0123456789")).toBe("GET https://api.test/rest/v1/channel_slugs: HTTP 401 ključ *** odbijen");
  });
});

describe("valueFromEnvText", () => {
  it("čita redak, navodnici, export; nema ili prazno = null", () => {
    const text = 'A=1\nexport SERVICE_ROLE_KEY="abc"\nEMPTY=\nX = \'y\'\n';
    expect(valueFromEnvText(text, "SERVICE_ROLE_KEY")).toBe("abc");
    expect(valueFromEnvText(text, "X")).toBe("y");
    expect(valueFromEnvText(text, "EMPTY")).toBeNull();
    expect(valueFromEnvText(text, "NEMA")).toBeNull();
  });
});

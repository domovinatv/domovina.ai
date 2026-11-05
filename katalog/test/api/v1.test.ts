// Ugovorni testovi API-ja v1 nad fixtureima (odluke 300–3xx). Svaki odgovor
// (2xx i 4xx) prolazi JSON Schemu iz `contract/v1/` u `api()`.
import { describe, expect, it } from "vitest";
import { encodeCursor } from "../../src/api/cursor.ts";
import { MAX_PAGE_SIZE } from "../../src/db/queries.ts";
import {
  api,
  apiError,
  brand,
  type Card,
  type Channel,
  collect,
  type ItemBody,
  type ListBody,
  plan,
  seed,
} from "./helpers.ts";

const byIdDesc = (a: string, b: string): number => (a < b ? 1 : a > b ? -1 : 0);

/** Očekivani ID-evi dana: oba tiera, bez varijanti, `id DESC`. */
function dayIds(date: string): string[] {
  return plan.episodes
    .filter((e) => e.publishedDate === date && e.variantOf === null)
    .map((e) => e.id)
    .sort(byIdDesc);
}

/** Očekivani slugovi popisa kanala: s datumom, `latest_published_date DESC, slug DESC`. */
function channelSlugs(tier?: 1 | 2): string[] {
  return plan.channels
    .filter((c) => c.latestPublishedDate !== null && c.processedCount >= 1 && (tier === undefined || c.tier === tier))
    .sort((a, b) => {
      const d = byIdDesc(a.latestPublishedDate ?? "", b.latestPublishedDate ?? "");
      return d !== 0 ? d : byIdDesc(a.slug, b.slug);
    })
    .map((c) => c.slug);
}

describe("brend", () => {
  it("host koji nije u brands i nema DEFAULT_BRAND u bazi → 404 brand_not_found", async () => {
    await apiError("nepoznat.test", "channels", 404, "brand_not_found");
  });

  it("host koji nije u brands pada na DEFAULT_BRAND (domovina)", async () => {
    await seed({ id: "domovina", host: "domovina.ai" });
    const { res, body } = await api<ListBody<Channel>>("localhost", "channels?limit=2", "channels");
    expect(res.status).toBe(200);
    expect(body.items.map((c) => c.slug)).toEqual(channelSlugs().slice(0, 2));
  });
});

describe("GET /days/:date", () => {
  const b = brand("s3-days");

  it("dan s epizodama oba tiera: kartice, poredak id DESC", async () => {
    const run = await seed(b);
    const { res, body } = await api<ListBody<Card>>(b.host, "days/2026-05-13", "days");
    expect(res.status).toBe(200);
    expect(body.version).toBe("1");
    expect(body.catalog).toBe(String(run));
    expect(body.next).toBeNull();
    expect(body.items.map((c) => c.id)).toEqual(dayIds("2026-05-13"));
    expect(new Set(body.items.map((c) => c.tier))).toEqual(new Set([1, 2]));
    expect(body.items.find((c) => c.id === "6dcab9c9837")).toEqual({
      id: "6dcab9c9837",
      title: "Rast kao posao svakoga: Gio Contestable (Life360) o eksperimentiranju, freemiumu i personalizaciji",
      title_hr: "Rast kao posao svakoga: Gio Contestable (Life360) o eksperimentiranju, freemiumu i personalizaciji",
      date: "2026-05-13",
      duration_seconds: null,
      magisterium_score: null,
      p: 15,
      tier: 2,
      lang: "hr",
      variant_of: null,
      channel: { slug: "subclub", name: "Sub Club by RevenueCat", tier: 1 },
    });
  });

  it("epizoda bez kanala: channel je null (ključ prisutan)", async () => {
    const { body } = await api<ListBody<Card>>(b.host, "days/2026-11-03", "days");
    const ep = body.items.find((c) => c.id === "0sxT3NF8yFg");
    expect(ep).toBeDefined();
    expect(ep && "channel" in ep).toBe(true);
    expect(ep?.channel).toBeNull();
    expect(ep?.duration_seconds).toBe(1845);
  });

  it("decimalno trajanje ostaje decimalno", async () => {
    const { body } = await api<ListBody<Card>>(b.host, "days/2026-07-16", "days");
    expect(body.items.find((c) => c.id === "CUJmOc91C64")).toMatchObject({
      duration_seconds: 245.295,
      p: 511,
      channel: { slug: "x-1973380383166050304", tier: 2 },
    });
  });

  it("varijanta nije u danu", async () => {
    const { body } = await api<ListBody<Card>>(b.host, "days/2026-10-10", "days");
    expect(body.items.map((c) => c.id)).toEqual(["UM2MWlNUpqg"]);
  });

  it("paginacija do kraja: unija stranica = svi retci, bez duplikata", async () => {
    const date = "2026-05-13";
    const { items, pages } = await collect<Card>(b.host, `days/${date}`, "days", 1);
    expect(items.map((c) => c.id)).toEqual(dayIds(date));
    expect(pages.at(-1)?.next).toBeNull();
    expect(pages).toHaveLength(dayIds(date).length);
  });

  it("prazan dan i stranica iza zadnjeg retka: items [] i next null", async () => {
    const { body } = await api<ListBody<Card>>(b.host, "days/1990-01-01", "days");
    expect(body).toMatchObject({ items: [], next: null });
    const last = dayIds("2026-05-13").at(-1) ?? "";
    const after = encodeCursor("2026-05-13", last);
    const { body: tail } = await api<ListBody<Card>>(b.host, `days/2026-05-13?cursor=${after}`, "days");
    expect(tail).toMatchObject({ items: [], next: null });
  });

  it("400: nevaljan datum, kursor drugog dana, loš kursor i limit", async () => {
    await apiError(b.host, "days/2026-02-30", 400, "bad_date");
    await apiError(b.host, "days/20261105", 400, "bad_date");
    await apiError(b.host, "days/danas", 400, "bad_date");
    await apiError(b.host, `days/2026-05-13?cursor=${encodeCursor("2026-05-14", "x")}`, 400, "bad_cursor");
    await apiError(b.host, "days/2026-05-13?cursor=", 400, "bad_cursor");
    await apiError(b.host, "days/2026-05-13?limit=0", 400, "bad_limit");
  });
});

describe("GET /channels, /directory", () => {
  const b = brand("s3-channels");

  it("bez tiera: oba tiera, latest_published_date DESC, slug DESC; paginacija do kraja", async () => {
    await seed(b);
    const { items, pages } = await collect<Channel>(b.host, "channels", "channels", 5);
    expect(items.map((c) => c.slug)).toEqual(channelSlugs());
    expect(new Set(items.map((c) => c.tier))).toEqual(new Set([1, 2]));
    expect(new Set(items.map((c) => c.slug)).size).toBe(items.length);
    expect(pages.at(-1)?.next).toBeNull();
  });

  it.each([1, 2] as const)("tier=%i", async (tier) => {
    const { items } = await collect<Channel>(b.host, `channels?tier=${tier}`, "channels", 3);
    expect(items.map((c) => c.slug)).toEqual(channelSlugs(tier));
  });

  it("directory: svi kanali s processed_count >= 1", async () => {
    const { items } = await collect<Channel>(b.host, "directory", "directory", 4);
    expect(items.map((c) => c.slug)).toEqual(channelSlugs());
    expect(items.every((c) => c.processed_count >= 1)).toBe(true);
  });

  it("limit izvan 1–100 ili ne cijeli broj, tier izvan 1|2, loš kursor → 400", async () => {
    for (const limit of ["0", String(MAX_PAGE_SIZE + 1), "abc", "1.5", "-1", "", "1e1"]) {
      await apiError(b.host, `channels?limit=${limit}`, 400, "bad_limit");
    }
    for (const tier of ["0", "3", "", "1,2", "one"]) await apiError(b.host, `channels?tier=${tier}`, 400, "bad_tier");
    for (const cursor of [
      "!!!",
      btoa("nije json").replace(/=+$/, ""),
      btoa(JSON.stringify({ a: 1 })).replace(/=+$/, ""),
      btoa(JSON.stringify(["2026-01-01"])).replace(/=+$/, ""),
      btoa(JSON.stringify(["2026-01-01", 5])).replace(/=+$/, ""),
      btoa(JSON.stringify(["2026-01-01", ""])).replace(/=+$/, ""),
      btoa(JSON.stringify(["2026-13-01", "x"])).replace(/=+$/, ""),
      // Ispravan sadržaj, ali s paddingom: nije kanonski zapis.
      `${encodeCursor("2026-01-01", "ab")}=`,
    ]) {
      await apiError(b.host, `directory?cursor=${encodeURIComponent(cursor)}`, 400, "bad_cursor");
    }
    expect(MAX_PAGE_SIZE).toBe(100);
    const { res } = await api(b.host, "channels?limit=100", "channels");
    expect(res.status).toBe(200);
  });
});

describe("GET /channels/:slug, /channels/:slug/episodes", () => {
  const b = brand("s3-channel");
  const unregistered = "yt-UCckHqySbfy5FcPP6MD_S-Yg";

  it("unregistered kanal: zaglavlje i epizode", async () => {
    await seed(b);
    const { res, body } = await api<ItemBody<Channel>>(b.host, `channels/${unregistered}`, "channel-response");
    expect(res.status).toBe(200);
    expect(body.item).toEqual({
      slug: unregistered,
      name: "Times Of India",
      tier: 2,
      lang: null,
      avatar: null,
      youtube_channel_id: "UCckHqySbfy5FcPP6MD_S-Yg",
      processed_count: 1,
      latest_published_date: "2026-09-25",
      unregistered: true,
    });
    const eps = await api<ListBody<Card>>(b.host, `channels/${unregistered}/episodes`, "channel-episodes");
    expect(eps.body.items.map((c) => c.id)).toEqual(["hmM9f_3Mqm4"]);
    expect(eps.body.items[0]?.channel).toEqual({ slug: unregistered, name: "Times Of India", tier: 2 });
  });

  it("Tier 1 kanal: zaglavlje s avatarom, unregistered false", async () => {
    const { body } = await api<ItemBody<Channel>>(b.host, "channels/podcast_cuspajz", "channel-response");
    expect(body.item).toMatchObject({ slug: "podcast_cuspajz", tier: 1, unregistered: false, processed_count: 20 });
  });

  it("epizode kanala: najnovije prve, do kraja; varijanta skrivena; processed_count = broj stavki", async () => {
    const { items, pages } = await collect<Card>(b.host, "channels/podcast_cuspajz/episodes", "channel-episodes", 3);
    const expected = plan.episodes
      .filter((e) => e.channelSlug === "podcast_cuspajz" && e.variantOf === null && e.publishedDate !== null)
      .sort((x, y) => byIdDesc(x.publishedDate ?? "", y.publishedDate ?? "") || byIdDesc(x.id, y.id))
      .map((e) => e.id);
    expect(items.map((c) => c.id)).toEqual(expected);
    expect(items.map((c) => c.id)).not.toContain("UM2MWlNUp_1");
    expect(new Set(items.map((c) => c.id)).size).toBe(items.length);
    expect(items).toHaveLength(20);
    expect(pages.at(-1)?.next).toBeNull();
    expect(items.every((c) => c.variant_of === null)).toBe(true);
  });

  it("404 za nepoznat kanal i njegove epizode", async () => {
    await apiError(b.host, "channels/nema_ga", 404, "channel_not_found");
    await apiError(b.host, "channels/nema_ga/episodes", 404, "channel_not_found");
    await apiError(b.host, "channels/nema_ga/episodes?limit=0", 400, "bad_limit");
  });
});

describe("GET /episodes/:id/card", () => {
  const b = brand("s3-card");

  it("varijanta: vidljiva u kartici s variant_of", async () => {
    await seed(b);
    const { res, body } = await api<ItemBody<Card>>(b.host, "episodes/UM2MWlNUp_1/card", "card-response");
    expect(res.status).toBe(200);
    expect(body.item).toMatchObject({
      id: "UM2MWlNUp_1",
      tier: 2,
      variant_of: "UM2MWlNUpqg",
      channel: { slug: "podcast_cuspajz", tier: 1 },
    });
    const base = await api<ItemBody<Card>>(b.host, "episodes/UM2MWlNUpqg/card", "card-response");
    expect(base.body.item.variant_of).toBeNull();
  });

  it("kartica epizode bez kanala", async () => {
    const { body } = await api<ItemBody<Card>>(b.host, "episodes/0sxT3NF8yFg/card", "card-response");
    expect(body.item.channel).toBeNull();
  });

  it("404 episode_not_found; nepoznata ruta 404 not_found", async () => {
    await apiError(b.host, "episodes/nema/card", 404, "episode_not_found");
    for (const path of ["episodes/x", "episodes/x/card/y", "days", "days/2026-01-01/x", "channels/a/b", "nepoznato"]) {
      await apiError(b.host, path, 404, "not_found");
    }
  });
});

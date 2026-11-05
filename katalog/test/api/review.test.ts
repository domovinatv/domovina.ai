// Rubni slučajevi iz neovisnog pregleda API koda (S3, odluka 314): putanje s
// percent-encodingom, kontrolni znakovi, kursor s neobičnim ključem, metode.
// Ovo su regresijski testovi za ponašanje koje je pregledom potvrđeno.
import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { encodeCursor } from "../../src/api/cursor.ts";
import { cacheControlFor, cacheKey } from "../../src/api/v1.ts";
import { applyPlan } from "../../src/ingest/write.ts";
import { api, apiError, brand, type Card, type ListBody, NOW, okRun, plan, seed } from "./helpers.ts";

describe("pregled: catalog null", () => {
  const b = brand("s3-review-null");

  it("podaci bez uspješnog uvoza: catalog null, cache po _cv=none; prvi ok uvoz → miss", async () => {
    const ok = await env.DB.prepare("SELECT count(*) AS n FROM ingest_runs WHERE status = 'ok'").first<{ n: number }>();
    // Pool izolira storage po datoteci; ovaj test je prvi u datoteci.
    expect(ok?.n).toBe(0);
    await applyPlan(env.DB, b, plan, NOW);
    const first = await api<ListBody<Card>>(b.host, "days/2026-05-13", "days");
    expect(first.body.catalog).toBeNull();
    expect(first.res.headers.get("x-katalog-cache")).toBe("miss");
    const run = await okRun();
    const after = await api<ListBody<Card>>(b.host, "days/2026-05-13", "days");
    expect(after.res.headers.get("x-katalog-cache")).toBe("miss");
    expect(after.body.catalog).toBe(String(run));
    expect(after.body.items).toEqual(first.body.items);
  });
});

describe("pregled: putanje i parametri", () => {
  const b = brand("s3-review");

  it("slug s kosom crtom i kontrolnim znakom: 404 channel_not_found, ne 500", async () => {
    await seed(b);
    await apiError(b.host, "channels/podcast_cuspajz%2Fepisodes", 404, "channel_not_found");
    await apiError(b.host, "channels/a%2Fb/episodes", 404, "channel_not_found");
    await apiError(b.host, "channels/%00", 404, "channel_not_found");
    await apiError(b.host, "channels/%27%20OR%201%3D1--", 404, "channel_not_found");
    await apiError(b.host, "episodes/%00/card", 404, "episode_not_found");
  });

  it("percent-encodiran slug je isti kanal; neispravan UTF-8 u segmentu → 404 not_found", async () => {
    const plain = await api<{ item: { slug: string } }>(b.host, "channels/subclub", "channel-response");
    const encoded = await api<{ item: { slug: string } }>(b.host, "channels/%73ubclub", "channel-response");
    expect(encoded.body.item).toEqual(plain.body.item);
    await apiError(b.host, "channels/%ED%A0%80", 404, "not_found");
    await apiError(b.host, "channels/%E0%A4%A", 404, "not_found");
  });

  it("`..` u putanji URL parser normalizira prije rute; ne izlazi iz prefiksa", async () => {
    await apiError(b.host, "channels/%2e%2e/%2e%2e/health", 404, "not_found");
  });

  it("kursor s ključem koji ne postoji, NUL ili tuđim datumom: valjan odgovor, ne 500", async () => {
    for (const key of ["\u0000", "zzzzzzzzzzz", "ž", "x".repeat(2000)]) {
      const cursor = encodeCursor("2026-05-13", key);
      const { res, body } = await api<ListBody<Card>>(b.host, `days/2026-05-13?cursor=${cursor}`, "days");
      expect(res.status, JSON.stringify(key.slice(0, 10))).toBe(200);
      expect(Array.isArray(body.items)).toBe(true);
    }
  });

  it("HEAD, OPTIONS i POST na rutu: 404 not_found JSON bez cachea (odluka 308)", async () => {
    for (const method of ["HEAD", "OPTIONS", "POST", "PUT", "DELETE"]) {
      const res = await exports.default.fetch(`https://${b.host}/api/katalog/v1/channels`, { method });
      expect(res.status, method).toBe(404);
      expect(res.headers.get("cache-control"), method).toBe("no-store");
      expect(res.headers.get("access-control-allow-origin"), method).toBe("*");
    }
  });
});

describe("pregled: Cache-Control na granici UTC dana i ključ cachea", () => {
  const PAST = "public, max-age=3600, stale-while-revalidate=86400";
  const RECENT = "public, max-age=60, stale-while-revalidate=300";
  const day = (date: string, now: string): string => cacheControlFor({ kind: "day", date }, new Date(now));

  it("ponoć UTC pomiče „jučer” točno u 00:00:00.000Z", () => {
    expect(day("2026-11-03", "2026-11-04T23:59:59.999Z")).toBe(RECENT);
    expect(day("2026-11-02", "2026-11-04T23:59:59.999Z")).toBe(PAST);
    expect(day("2026-11-03", "2026-11-05T00:00:00.000Z")).toBe(PAST);
    expect(day("2026-11-04", "2026-11-05T00:00:00.000Z")).toBe(RECENT);
    // Prijelaz godine i prijestupni dan.
    expect(day("2027-12-31", "2028-01-01T00:00:00.000Z")).toBe(RECENT);
    expect(day("2028-02-28", "2028-03-01T00:00:00.000Z")).toBe(PAST);
    expect(day("2028-02-29", "2028-03-01T00:00:00.000Z")).toBe(RECENT);
  });

  it("ključ razdvaja host, limit, kursor, tier i verziju; nepoznati parametri ne ulaze", () => {
    const route = { kind: "channels" } as const;
    const page = (limit: number, cursor?: string) => ({
      limit,
      after: undefined,
      canonical: cursor === undefined ? { limit: String(limit) } : { limit: String(limit), cursor },
    });
    const key = (u: string, limit: number, tier?: 1 | 2, cursor?: string, cv: string | null = "7") =>
      cacheKey(new URL(u), { route, page: page(limit, cursor), tier }, cv);
    const base = key("https://a.test/api/katalog/v1/channels", 30);
    expect(key("https://a.test/api/katalog/v1/channels?utm=x&limit=30", 30)).toBe(base);
    expect(new Set([
      base,
      key("https://b.test/api/katalog/v1/channels", 30),
      key("https://a.test:8443/api/katalog/v1/channels", 30),
      key("https://a.test/api/katalog/v1/channels", 31),
      key("https://a.test/api/katalog/v1/channels", 30, 1),
      key("https://a.test/api/katalog/v1/channels", 30, undefined, "abc"),
      key("https://a.test/api/katalog/v1/channels", 30, undefined, undefined, null),
    ]).size).toBe(7);
    expect(key("https://a.test/api/katalog/v1/channels", 30, undefined, undefined, null)).toContain("_cv=none");
  });
});

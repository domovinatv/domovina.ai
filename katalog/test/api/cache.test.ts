// Cache-Control, CORS i `caches.default` (odluke 307, 308).
import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { api, apiError, brand, type Card, type ListBody, okRun, seed } from "./helpers.ts";

const b = brand("s3-cache");

/** UTC datum `days` dana od danas. */
function utcDay(days: number): string {
  return new Date(Date.now() + days * 86_400_000).toISOString().slice(0, 10);
}

/**
 * `cache.put` ide kroz `ctx.waitUntil`, pa odgovor stigne prije upisa. Ponavlja
 * zahtjev dok ne dobije `hit` (najviše 50 × 10 ms) i vraća taj odgovor.
 */
async function untilHit(path: string): Promise<Response> {
  for (let i = 0; i < 50; i++) {
    const res = await exports.default.fetch(`https://${b.host}/api/katalog/v1/${path}`);
    if (res.headers.get("x-katalog-cache") === "hit") return res;
    await res.arrayBuffer();
    await new Promise((r) => setTimeout(r, 10));
  }
  throw new Error(`${path}: nikad hit`);
}

describe("cache", () => {
  it("prvi zahtjev miss, isti zahtjev hit s istim tijelom; novi ok uvoz → opet miss", async () => {
    await seed(b);
    const first = await api<ListBody<Card>>(b.host, "days/2026-05-13?limit=5", "days");
    expect(first.res.headers.get("x-katalog-cache")).toBe("miss");

    const hit = await untilHit("days/2026-05-13?limit=5");
    const hitBody: unknown = await hit.json();
    // Tijelo s cache hita je ono iz izračuna, i `meta.rows_read`.
    expect(hitBody).toEqual(first.body);

    // Kanonski ključ: redoslijed parametara, nepoznati parametar i zadani
    // limit ne mijenjaju ključ.
    await untilHit("days/2026-05-13?utm=x&limit=5");
    await api(b.host, "days/2026-05-13", "days");
    await untilHit("days/2026-05-13?limit=30");

    const run = await okRun();
    const after = await api<ListBody<Card>>(b.host, "days/2026-05-13?limit=5", "days");
    expect(after.res.headers.get("x-katalog-cache")).toBe("miss");
    expect(after.body.catalog).toBe(String(run));
    expect(after.body.items).toEqual(first.body.items);
  });

  it("Cache-Control po ruti; ACAO *, bez Vary", async () => {
    const cases: [string, string][] = [
      [`days/${utcDay(-2)}`, "public, max-age=60, stale-while-revalidate=600"],
      ["days/2020-01-01", "public, max-age=60, stale-while-revalidate=600"],
      [`days/${utcDay(-1)}`, "public, max-age=60, stale-while-revalidate=300"],
      [`days/${utcDay(0)}`, "public, max-age=60, stale-while-revalidate=300"],
      [`days/${utcDay(3)}`, "public, max-age=60, stale-while-revalidate=300"],
      ["channels", "public, max-age=60, stale-while-revalidate=600"],
      ["channels?tier=1", "public, max-age=60, stale-while-revalidate=600"],
      ["directory", "public, max-age=60, stale-while-revalidate=600"],
      ["channels/subclub", "public, max-age=60, stale-while-revalidate=600"],
      ["channels/subclub/episodes", "public, max-age=60, stale-while-revalidate=600"],
      ["episodes/hPwt12zZMCY/card", "public, max-age=300, stale-while-revalidate=3600"],
    ];
    for (const [path, cc] of cases) {
      const contract = path.startsWith("days/")
        ? "days"
        : path.startsWith("directory")
          ? "directory"
          : path.endsWith("/episodes")
            ? "channel-episodes"
            : path.startsWith("episodes/")
              ? "card-response"
              : path.startsWith("channels/")
                ? "channel-response"
                : "channels";
      // Dvaput: i miss i hit nose isto zaglavlje.
      for (let i = 0; i < 2; i++) {
        const { res } = await api(b.host, path, contract);
        expect(res.status, path).toBe(200);
        expect(res.headers.get("cache-control"), path).toBe(cc);
        expect(res.headers.get("access-control-allow-origin"), path).toBe("*");
        expect(res.headers.get("vary"), path).toBeNull();
      }
    }
  });

  it("greške: no-store, ACAO *, bez Vary, ne ulaze u cache", async () => {
    for (let i = 0; i < 2; i++) {
      await apiError(b.host, "channels/nema_ga", 404, "channel_not_found");
      await apiError(b.host, "channels?limit=0", 400, "bad_limit");
    }
    const res = await exports.default.fetch(`https://${b.host}/api/katalog/v1/episodes/nema/card`);
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    expect(res.headers.get("vary")).toBeNull();
    await res.arrayBuffer();
  });

  it("isti odgovor s Origin zaglavljem i bez njega (jedan zapis, bez Vary)", async () => {
    await untilHit("channels/subclub");
    const res = await exports.default.fetch(`https://${b.host}/api/katalog/v1/channels/subclub`, {
      headers: { origin: "https://domovina.ai" },
    });
    expect(res.headers.get("x-katalog-cache")).toBe("hit");
    expect(res.headers.get("access-control-allow-origin")).toBe("*");
    await res.arrayBuffer();
  });
});

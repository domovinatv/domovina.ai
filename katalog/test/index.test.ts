import { exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("worker", () => {
  it("GET /api/katalog/v1/health vraća JSON", async () => {
    const res = await exports.default.fetch("https://domovina.ai/api/katalog/v1/health");
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expect(await res.json()).toEqual({ ok: true, service: "katalog", version: 1 });
  });

  it.each([
    ["GET", "/"],
    ["GET", "/api/katalog/v1"],
    ["GET", "/api/katalog/v1/health/"],
    ["GET", "/api/katalog/v2/health"],
    ["POST", "/api/katalog/v1/health"],
  ])("%s %s → 404 JSON", async (method, path) => {
    const res = await exports.default.fetch(`https://domovina.ai${path}`, { method });
    expect(res.status).toBe(404);
    expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
    expect(await res.json()).toEqual({ ok: false, error: "not_found" });
  });

  it("mreža prema van je u testu zatvorena", async () => {
    await expect(fetch("https://cdn.domovina.ai/channels/data/index.json")).rejects.toThrow(
      /mreža je u testu zabranjena/,
    );
  });
});

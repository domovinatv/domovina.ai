// Iznimka iz handlera (S4, odluka 314 b): 500 `internal` u obliku ostalih
// grešaka (JSON, CORS, `no-store`), `console.error` s porukom, i nikad u
// Cache API. Handler se zove izravno s podmetnutim `env` (bez `DB` ili s D1
// koji baca), jer `exports.default` uvijek nosi pravi binding.
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { afterEach, describe, expect, it, vi } from "vitest";
import type { Env } from "../../src/env.ts";
import worker from "../../src/index.ts";
import { assertContract, brand, seed } from "./helpers.ts";

const b = brand("s4-internal");
const KVAR = "D1_ERROR: simulirani kvar";

/** D1 koji propusti prvih `okPrepares` upita (kontekst brenda), a zatim baca. */
function failingDb(okPrepares: number): D1Database {
  let n = 0;
  const db = env.DB;
  return {
    prepare(sql: string) {
      if (n++ >= okPrepares) throw new Error(KVAR);
      return db.prepare(sql);
    },
    batch() {
      return Promise.reject(new Error(KVAR));
    },
    exec() {
      return Promise.reject(new Error(KVAR));
    },
    withSession() {
      throw new Error(KVAR);
    },
  } as unknown as D1Database;
}

async function call(path: string, e: Partial<Env>): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(new Request(`https://${b.host}/api/katalog/v1/${path}`), e as Env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

async function expectInternal(res: Response): Promise<void> {
  expect(res.status).toBe(500);
  expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
  expect(res.headers.get("access-control-allow-origin")).toBe("*");
  expect(res.headers.get("cache-control")).toBe("no-store");
  expect(res.headers.get("x-katalog-cache")).toBeNull();
  const body: unknown = await res.json();
  expect(body).toEqual({ ok: false, error: "internal" });
  assertContract("error", body);
}

describe("iznimka iz handlera → 500 internal", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("env bez DB: 500 JSON s CORS i no-store, poruka u console.error", async () => {
    await seed(b);
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    await expectInternal(await call("channels?limit=5", { DEFAULT_BRAND: "domovina" }));
    expect(log).toHaveBeenCalledTimes(1);
    const line = String(log.mock.calls[0]?.[0]);
    expect(line).toContain("/api/katalog/v1/channels");
    expect(line).toContain("TypeError");
    // Upit (`?limit=…`) ne ide u log.
    expect(line).not.toContain("limit");
  });

  it.each([
    ["episodes/UM2MWlNUp_1/card", "all"],
    ["channels/podcast_cuspajz/episodes?limit=7", "batch"],
    ["days/2026-05-13?limit=3", "all"],
  ])("%s: D1 baca nakon konteksta (%s) → 500, a odgovor ne ulazi u cache", async (path) => {
    const log = vi.spyOn(console, "error").mockImplementation(() => undefined);
    await expectInternal(await call(path, { DB: failingDb(1), DEFAULT_BRAND: "domovina" }));
    expect(String(log.mock.calls[0]?.[0])).toContain(KVAR);
    // Ista verzija kataloga = isti ključ cachea: da je 500 spremljen, ovo bi bio hit.
    const res = await exports.default.fetch(`https://${b.host}/api/katalog/v1/${path}`);
    expect(res.status).toBe(200);
    expect(res.headers.get("x-katalog-cache")).toBe("miss");
  });
});

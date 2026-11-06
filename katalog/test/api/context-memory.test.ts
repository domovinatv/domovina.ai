// Kontekst kataloga u memoriji izolata (odluke 502, 503, 600, 601): hit ne dira
// `env.DB`, miss čita kontekst iz D1 i uz zapamćen brend ide jednim odlaskom do
// baze. Handler se zove izravno s D1 koji broji pozive.
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env } from "cloudflare:workers";
import { beforeEach, describe, expect, it } from "vitest";
import { CONTEXT_TTL_MS, forgetCatalogContexts } from "../../src/api/context.ts";
import { handleV1 } from "../../src/api/v1.ts";
import type { Env } from "../../src/env.ts";
import { finishRun, startRun } from "../../src/ingest/write.ts";
import worker from "../../src/index.ts";
import { brand, NOW, seed } from "./helpers.ts";

const b = brand("s6-context");

interface Counter {
  /** Odlasci do baze: `db.batch` + pojedinačni upiti izvan batcha. */
  trips: number;
  prepares: number;
}

/** D1 koji broji `prepare` i `batch`; odlazak = batch ili upit koji nije išao u batch. */
function countingDb(): { db: D1Database; count: () => Counter } {
  const real = env.DB;
  let prepares = 0;
  let batches = 0;
  let batched = 0;
  const db = {
    prepare(sql: string) {
      prepares++;
      return real.prepare(sql);
    },
    batch(stmts: D1PreparedStatement[]) {
      batches++;
      batched += stmts.length;
      return real.batch(stmts);
    },
  } as unknown as D1Database;
  return { db, count: () => ({ trips: batches + prepares - batched, prepares }) };
}

/** D1 koji baca na svaki pristup: hit ga ne smije ni dotaknuti. */
const untouchable = new Proxy({} as D1Database, {
  get(_t, prop) {
    throw new Error(`hit je dirao DB.${String(prop)}`);
  },
});

async function call(path: string, db: D1Database, host = b.host): Promise<Response> {
  const ctx = createExecutionContext();
  const e: Env = { DB: db, DEFAULT_BRAND: "nema-zadanog" };
  const res = await worker.fetch(new Request(`https://${host}/api/katalog/v1/${path}`), e, ctx);
  // Čeka `cache.put` iz `ctx.waitUntil`, pa je sljedeći isti zahtjev hit.
  await waitOnExecutionContext(ctx);
  return res;
}

describe("kontekst u memoriji izolata", () => {
  beforeEach(() => {
    forgetCatalogContexts();
  });

  it("drugi isti zahtjev je hit i ne dira DB", async () => {
    await seed(b);
    const c = countingDb();
    const miss = await call("episodes/hPwt12zZMCY/card", c.db);
    expect(miss.headers.get("x-katalog-cache")).toBe("miss");
    const missBody: unknown = await miss.json();
    expect(c.count().prepares).toBeGreaterThan(0);

    const hit = await call("episodes/hPwt12zZMCY/card", untouchable);
    expect(hit.status).toBe(200);
    expect(hit.headers.get("x-katalog-cache")).toBe("hit");
    expect(await hit.json()).toEqual(missBody);
  });

  it("miss uz zapamćen kontekst: kontekst i ruta jednim odlaskom do baze, isti rows_read", async () => {
    const cold = countingDb();
    const first = await call("channels/subclub", cold.db);
    expect(first.headers.get("x-katalog-cache")).toBe("miss");
    // Bez memorije: kontekst, pa ruta (brend mora biti poznat prije upita rute).
    expect(cold.count().trips).toBe(2);
    const firstBody = await first.json<{ meta: { rows_read: number } }>();

    const warm = countingDb();
    const second = await call("channels/podcast_cuspajz", warm.db);
    expect(second.headers.get("x-katalog-cache")).toBe("miss");
    expect(warm.count()).toEqual({ trips: 1, prepares: 2 });
    const secondBody = await second.json<{ meta: { rows_read: number } }>();
    // `rows_read` i dalje uključuje upit konteksta (odluka 300).
    expect(secondBody.meta.rows_read).toBe(firstBody.meta.rows_read);

    // Epizode kanala već idu batchom (zaglavlje + stranica); kontekst ide u isti.
    const eps = countingDb();
    await call("channels/podcast_cuspajz/episodes?limit=3", eps.db).then((r) => r.arrayBuffer());
    expect(eps.count()).toEqual({ trips: 1, prepares: 3 });
  });

  it("nova verzija kataloga unutar TTL-a: hit na staroj verziji; nakon zaborava miss na novoj", async () => {
    const before = await (await call("channels/subclub", env.DB)).json<{ catalog: string }>();
    await call("channels/subclub", env.DB).then((r) => r.arrayBuffer());
    const id = await startRun(env.DB, "test", NOW);
    await finishRun(env.DB, id, "ok", NOW, {});

    const stale = await call("channels/subclub", untouchable);
    expect(stale.headers.get("x-katalog-cache")).toBe("hit");
    expect((await stale.json<{ catalog: string }>()).catalog).toBe(before.catalog);

    forgetCatalogContexts();
    const fresh = await call("channels/subclub", env.DB);
    expect(fresh.headers.get("x-katalog-cache")).toBe("miss");
    expect((await fresh.json<{ catalog: string }>()).catalog).toBe(String(id));
  });

  it("nakon TTL-a kontekst se ponovno čita iz D1", async () => {
    await call("channels/subclub", env.DB).then((r) => r.arrayBuffer());
    const later = new Date(Date.now() + CONTEXT_TTL_MS + 1000);
    const c = countingDb();
    const ctx = createExecutionContext();
    const url = new URL(`https://${b.host}/api/katalog/v1/channels/subclub`);
    const res = await handleV1(url, "channels/subclub", { DB: c.db, DEFAULT_BRAND: "nema-zadanog" }, ctx, later);
    await waitOnExecutionContext(ctx);
    // Zapis u Cache API i dalje postoji pod istom verzijom: hit, ali tek nakon
    // što je kontekst pročitan iz D1.
    expect(res.headers.get("x-katalog-cache")).toBe("hit");
    expect(c.count().trips).toBe(1);
    await res.arrayBuffer();
  });

  it("brand_not_found se ne pamti: svaki zahtjev pita D1", async () => {
    for (let i = 0; i < 2; i++) {
      const c = countingDb();
      const res = await call("channels/subclub", c.db, "nepoznat.test");
      expect(res.status).toBe(404);
      expect(await res.json()).toEqual({ ok: false, error: "brand_not_found" });
      expect(c.count().trips).toBe(1);
    }
  });
});

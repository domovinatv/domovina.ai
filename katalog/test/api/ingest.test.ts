// `POST /ingest` i `GET /ingest/ids` (S6, odluke 602–607). Token je testni
// binding iz `vitest.config.ts`. Pool izolira storage po datoteci: brend
// `domovina` (DEFAULT_BRAND) ovdje ne postoji dok ga test ne upiše.
import { createExecutionContext, waitOnExecutionContext } from "cloudflare:test";
import { env, exports } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { MAX_BATCH_CHANNELS, MAX_BATCH_EPISODES, MAX_BODY_BYTES } from "../../src/api/ingest.ts";
import type { Env } from "../../src/env.ts";
import type { ChannelRow, EpisodeRow } from "../../src/ingest/plan.ts";
import { writeRows } from "../../src/ingest/write.ts";
import worker from "../../src/index.ts";
import { api, type ApiResult, assertContract, brand, type Card, type ErrorBody, type ItemBody, NOW, plan } from "./helpers.ts";

const b = brand("s6-ingest");
const TOKEN = env.INGEST_TOKEN;
// Token iz `vitest.config.ts`, ne iz lokalne `.dev.vars`.
if (TOKEN !== "test-ingest-token") throw new Error("INGEST_TOKEN nije testni binding");
const PREFIX = "/api/katalog/v1";

interface IngestBody {
  readonly ok: true;
  readonly changes: { readonly channels: number; readonly episodes: number };
  readonly catalog: string | null;
}

interface IdsBody {
  readonly ids: string[];
  readonly next: string | null;
  readonly meta: { readonly rows_read: number };
}

interface Batch {
  source: string;
  channels: readonly ChannelRow[];
  episodes: readonly EpisodeRow[];
}

const batch: Batch = { source: "pipeline", channels: plan.channels, episodes: plan.episodes };

interface CallOptions {
  readonly host?: string;
  readonly token?: string | null;
  readonly authorization?: string;
  readonly contentType?: string;
}

function requestHeaders(o: CallOptions): Record<string, string> {
  const h: Record<string, string> = { "content-type": o.contentType ?? "application/json" };
  const token = o.token === undefined ? TOKEN : o.token;
  if (o.authorization !== undefined) h.authorization = o.authorization;
  else if (token !== null) h.authorization = `Bearer ${token}`;
  return h;
}

/** Odgovor ingesta: JSON, `no-store`, nikad cache; tijelo prolazi shemu. */
async function check<T>(res: Response, contract: "ingest-response" | "ingest-ids"): Promise<ApiResult<T>> {
  expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
  expect(res.headers.get("cache-control")).toBe("no-store");
  expect(res.headers.get("x-katalog-cache")).toBeNull();
  const body: unknown = await res.json();
  assertContract(res.status === 200 ? contract : "error", body);
  return { res, body: body as T };
}

async function post<T = IngestBody>(body: unknown, o: CallOptions = {}): Promise<ApiResult<T>> {
  const res = await exports.default.fetch(`https://${o.host ?? b.host}${PREFIX}/ingest`, {
    method: "POST",
    headers: requestHeaders(o),
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
  return check<T>(res, "ingest-response");
}

async function ids<T = IdsBody>(query: string, o: CallOptions = {}): Promise<ApiResult<T>> {
  const res = await exports.default.fetch(`https://${o.host ?? b.host}${PREFIX}/ingest/ids${query}`, {
    headers: requestHeaders(o),
  });
  return check<T>(res, "ingest-ids");
}

async function expectError(
  call: Promise<{ res: Response; body: unknown }>,
  status: number,
  error: string,
  detail?: string,
): Promise<void> {
  const { res, body } = await call;
  expect(res.status).toBe(status);
  expect(body).toEqual(detail === undefined ? { ok: false, error } : { ok: false, error, detail });
}

async function okRuns(): Promise<{ id: number; source: string; status: string; counts: string | null }[]> {
  return (
    await env.DB.prepare("SELECT id, source, status, counts FROM ingest_runs ORDER BY id").all<{
      id: number;
      source: string;
      status: string;
      counts: string | null;
    }>()
  ).results;
}

/** Izravan poziv handlera s podmetnutim `env` (bez tokena, D1 koji baca …). */
async function direct(path: string, init: RequestInit, e: Partial<Env>): Promise<Response> {
  const ctx = createExecutionContext();
  const res = await worker.fetch(new Request(`https://${b.host}${PREFIX}/${path}`, init), e as Env, ctx);
  await waitOnExecutionContext(ctx);
  return res;
}

function card(id: string): Promise<{ res: Response; body: ItemBody<Card> }> {
  return api<ItemBody<Card>>(b.host, `episodes/${id}/card`, "card-response");
}

describe("ingest: auth i brend", () => {
  it("host bez brenda i bez DEFAULT_BRAND u bazi → 404 brand_not_found (i za ids)", async () => {
    await expectError(post(batch, { host: "nema-brenda.test" }), 404, "brand_not_found");
    await expectError(ids("", { host: "nema-brenda.test" }), 404, "brand_not_found");
    expect(await okRuns()).toEqual([]);
    await env.DB.prepare("INSERT INTO brands (id, host) VALUES (?1, ?2)").bind(b.id, b.host).run();
  });

  it("bez tokena u env-u → 503 ingest_disabled (prazan token isto)", async () => {
    for (const e of [{ DB: env.DB, DEFAULT_BRAND: "domovina" }, { DB: env.DB, DEFAULT_BRAND: "domovina", INGEST_TOKEN: "" }]) {
      const init = { method: "POST", headers: requestHeaders({}), body: JSON.stringify(batch) };
      const r1 = await check<ErrorBody>(await direct("ingest", init, e), "ingest-response");
      expect(r1.res.status).toBe(503);
      expect(r1.body).toEqual({ ok: false, error: "ingest_disabled" });
      const r2 = await check<ErrorBody>(await direct("ingest/ids", { headers: requestHeaders({}) }, e), "ingest-ids");
      expect(r2.res.status).toBe(503);
    }
  });

  it("bez Bearera, s krivim, s prefiksom pravog ili drugom shemom → 401 unauthorized", async () => {
    const cases: CallOptions[] = [
      { token: null },
      { token: "krivi" },
      { token: `${TOKEN}x` },
      { token: TOKEN.slice(0, -1) },
      { authorization: `Basic ${TOKEN}` },
      { authorization: `Bearer  ${TOKEN}` },
      { authorization: TOKEN },
    ];
    for (const o of cases) {
      await expectError(post(batch, o), 401, "unauthorized");
      await expectError(ids("", o), 401, "unauthorized");
    }
    // Auth je prije svega ostalog: ni loše tijelo ne otkriva ništa bez tokena.
    await expectError(post("{", { token: "krivi" }), 401, "unauthorized");
    expect(await okRuns()).toEqual([]);
  });

  it("GET /ingest i POST /ingest/ids: 404 not_found", async () => {
    const get = await exports.default.fetch(`https://${b.host}${PREFIX}/ingest`, { headers: requestHeaders({}) });
    expect(get.status).toBe(404);
    await get.arrayBuffer();
    const postIds = await exports.default.fetch(`https://${b.host}${PREFIX}/ingest/ids`, {
      method: "POST",
      headers: requestHeaders({}),
      body: "{}",
    });
    expect(postIds.status).toBe(404);
    await postIds.arrayBuffer();
  });
});

describe("ingest: tijelo", () => {
  const ep = plan.episodes[3];
  const ch = plan.channels[0];
  if (ep === undefined || ch === undefined) throw new Error("fixture plan je prazan");

  it("content-type i JSON", async () => {
    await expectError(post(batch, { contentType: "text/plain" }), 400, "bad_content_type");
    await expectError(post(batch, { contentType: "application/jsonx" }), 400, "bad_content_type");
    await expectError(post("{", {}), 400, "bad_json");
    await expectError(post("", {}), 400, "bad_json");
    // Charset parametar je dopušten.
    const ok = await post({ source: "pipeline", channels: [], episodes: [] }, { contentType: "application/json; charset=utf-8" });
    expect(ok.res.status).toBe(200);
    expect(ok.body.changes).toEqual({ channels: 0, episodes: 0 });
  });

  const withEpisode = (patch: Record<string, unknown>): unknown => ({
    ...batch,
    episodes: batch.episodes.map((e, i) => (i === 3 ? { ...e, ...patch } : e)),
  });
  const withChannel = (patch: Record<string, unknown>): unknown => ({
    ...batch,
    channels: batch.channels.map((c, i) => (i === 0 ? { ...c, ...patch } : c)),
  });

  it.each<[string, unknown, string]>([
    ["tijelo nije objekt", [], "body"],
    ["nepoznat ključ na vrhu", { ...batch, extra: 1 }, "extra"],
    ["source nedostaje", { channels: [], episodes: [] }, "source"],
    ["source prazan", { ...batch, source: "" }, "source"],
    ["source s razmakom", { ...batch, source: "drift check" }, "source"],
    ["episodes nije niz", { ...batch, episodes: {} }, "episodes"],
    ["tier 3", withEpisode({ tier: 3 }), "episodes[3].tier"],
    ["tier kao string", withEpisode({ tier: "1" }), "episodes[3].tier"],
    ["flags 512", withEpisode({ flags: 512 }), "episodes[3].flags"],
    ["flags decimalan", withEpisode({ flags: 1.5 }), "episodes[3].flags"],
    ["flags negativan", withEpisode({ flags: -1 }), "episodes[3].flags"],
    ["nepostojeći datum", withEpisode({ publishedDate: "2026-02-30" }), "episodes[3].publishedDate"],
    ["datum s vremenom", withEpisode({ publishedDate: "2026-02-03T00:00:00Z" }), "episodes[3].publishedDate"],
    ["prazan naslov", withEpisode({ title: "" }), "episodes[3].title"],
    ["naslov null", withEpisode({ title: null }), "episodes[3].title"],
    ["prazan titleHr", withEpisode({ titleHr: "" }), "episodes[3].titleHr"],
    ["prazan channelSlug", withEpisode({ channelSlug: "" }), "episodes[3].channelSlug"],
    ["negativno trajanje", withEpisode({ durationSeconds: -1 }), "episodes[3].durationSeconds"],
    ["magisterium 101", withEpisode({ magisteriumScore: 101 }), "episodes[3].magisteriumScore"],
    ["lang od 1 znaka", withEpisode({ lang: "h" }), "episodes[3].lang"],
    ["lang od 17 znakova", withEpisode({ lang: "x".repeat(17) }), "episodes[3].lang"],
    ["nepoznat ključ epizode", withEpisode({ snake_case: 1 }), "episodes[3].snake_case"],
    ["nedostaje ključ epizode", { ...batch, episodes: [{ ...ep, variantOf: undefined }] }, "episodes[0].variantOf"],
    ["epizoda nije objekt", { ...batch, episodes: [null] }, "episodes[0]"],
    ["dupli ID epizode", { ...batch, episodes: [ep, ep] }, "episodes[1].id"],
    ["kanal tier 1 unregistered", withChannel({ tier: 1, unregistered: true }), "channels[0].unregistered"],
    ["unregistered kao broj", withChannel({ unregistered: 0 }), "channels[0].unregistered"],
    ["processedCount negativan", withChannel({ processedCount: -1 }), "channels[0].processedCount"],
    ["prazno ime kanala", withChannel({ name: "" }), "channels[0].name"],
    ["dupli slug", { ...batch, channels: [ch, ch] }, "channels[1].slug"],
  ])("%s → 400 bad_body %s", async (_name, body, detail) => {
    await expectError(post(body), 400, "bad_body", detail);
  });

  it("prevelik batch → 400 batch_too_large; prevelik zahtjev → 413 body_too_large", async () => {
    const many = Array.from({ length: MAX_BATCH_EPISODES + 1 }, (_, i) => ({ ...ep, id: `ep_${i}` }));
    await expectError(post({ ...batch, episodes: many }), 400, "batch_too_large", "episodes");
    const channels = Array.from({ length: MAX_BATCH_CHANNELS + 1 }, (_, i) => ({ ...ch, slug: `k_${i}` }));
    await expectError(post({ ...batch, channels }), 400, "batch_too_large", "channels");
    // Točno na granici prolazi provjeru veličine (pa padne na nepoznatom kanalu ili prođe).
    const atLimit = await post({ ...batch, channels: [], episodes: many.slice(0, MAX_BATCH_EPISODES).map((e) => ({ ...e, channelSlug: null })) });
    expect(atLimit.res.status).toBe(200);
    expect(atLimit.body.changes.episodes).toBe(MAX_BATCH_EPISODES);

    const huge = JSON.stringify({ ...batch, source: "x" }).replace(/}$/, `,"pad":"${" ".repeat(MAX_BODY_BYTES)}"}`);
    await expectError(post(huge), 413, "body_too_large");
    // Bez `content-length` (stream): granica se mjeri na stvarnoj duljini.
    const bytes = new TextEncoder().encode(huge);
    const stream = new ReadableStream<Uint8Array>({
      start(c) {
        for (let i = 0; i < bytes.length; i += 65_536) c.enqueue(bytes.subarray(i, i + 65_536));
        c.close();
      },
    });
    const res = await exports.default.fetch(`https://${b.host}${PREFIX}/ingest`, {
      method: "POST",
      headers: requestHeaders({}),
      body: stream,
    });
    await expectError(check(res, "ingest-response"), 413, "body_too_large");
  });
});

describe("ingest: upis", () => {
  const target = plan.episodes.find((e) => e.channelSlug !== null && e.variantOf === null);
  if (target === undefined) throw new Error("fixture bez epizode s kanalom");

  let first: IngestBody;

  it("prvi batch upiše retke, vrati changes > 0 i novu verziju kataloga", async () => {
    const before = (await okRuns()).filter((r) => r.status === "ok");
    const { res, body } = await post(batch);
    expect(res.status).toBe(200);
    expect(body.ok).toBe(true);
    expect(body.changes).toEqual({ channels: plan.channels.length, episodes: plan.episodes.length });
    const runs = await okRuns();
    const last = runs[runs.length - 1];
    expect(last?.status).toBe("ok");
    expect(last?.source).toBe("pipeline");
    expect(body.catalog).toBe(String(last?.id));
    expect(Math.max(0, ...before.map((r) => r.id))).toBeLessThan(Number(body.catalog));
    expect(JSON.parse(last?.counts ?? "null")).toEqual({
      received: { channels: plan.channels.length, episodes: plan.episodes.length },
      written: body.changes,
    });
    // Nijedan `running` redak ne ostaje.
    expect(runs.filter((r) => r.status === "running")).toEqual([]);
    first = body;

    const c = await card(target.id);
    expect(c.res.status).toBe(200);
    expect(c.body.item.title).toBe(target.title);
    expect(c.body.catalog).toBe(body.catalog);
  });

  it("isti batch ponovljen → changes 0, catalog nepromijenjen, bez novog retka u ingest_runs", async () => {
    const runs = await okRuns();
    const { res, body } = await post(batch);
    expect(res.status).toBe(200);
    expect(body).toEqual({ ok: true, changes: { channels: 0, episodes: 0 }, catalog: first.catalog });
    expect(await okRuns()).toEqual(runs);
  });

  it("izmijenjen naslov jedne epizode → changes.episodes = 1; kartica vraća novi naslov", async () => {
    // Kartica je u cacheu pod trenutnom verzijom (hit uz kontekst iz memorije).
    for (let i = 0; i < 50; i++) {
      const c = await card(target.id);
      if (c.res.headers.get("x-katalog-cache") === "hit") break;
      await new Promise((r) => setTimeout(r, 10));
    }
    const title = `${target.title} (izmijenjeno)`;
    const changed = { ...batch, source: "drift-check", episodes: batch.episodes.map((e) => (e.id === target.id ? { ...e, title } : e)) };
    const { body } = await post(changed);
    expect(body.changes).toEqual({ channels: 0, episodes: 1 });
    expect(Number(body.catalog)).toBeGreaterThan(Number(first.catalog));
    // Ingest je u svom izolatu zaboravio kontekst (odluka 600), pa GET odmah vidi
    // novu verziju: novi ključ cachea, miss, novi naslov.
    const c = await card(target.id);
    expect(c.res.headers.get("x-katalog-cache")).toBe("miss");
    expect(c.body.catalog).toBe(body.catalog);
    expect(c.body.item.title).toBe(title);
  });

  it("epizoda s kanalom koji je samo u bazi (ne u batchu) prolazi", async () => {
    const { res, body } = await post({ source: "pipeline", channels: [], episodes: [{ ...target, title: "Treći naslov" }] });
    expect(res.status).toBe(200);
    expect(body.changes).toEqual({ channels: 0, episodes: 1 });
  });

  it("nepoznat kanal → 409 unknown_channel s putanjom, ništa upisano, bez novog retka", async () => {
    const runs = await okRuns();
    const fresh: EpisodeRow = { ...target, id: "novi_ep_bez_kanala", channelSlug: "nema_kanala" };
    const episodes = [{ ...target, title: "Ne smije se upisati" }, fresh];
    await expectError(post({ source: "pipeline", channels: [], episodes }), 409, "unknown_channel", "episodes[1].channelSlug");
    expect(await okRuns()).toEqual(runs);
    const row = await env.DB.prepare("SELECT title FROM episodes WHERE brand = ?1 AND id = ?2")
      .bind(b.id, target.id)
      .first<{ title: string }>();
    expect(row?.title).toBe("Treći naslov");
  });

  it("D1 u poolu provodi strani ključ (rezerva iza provjere u ingestu)", async () => {
    const bad: EpisodeRow = { ...target, id: "fk_test", channelSlug: "nema_kanala" };
    await expect(writeRows(env.DB, b.id, [], [bad], NOW)).rejects.toThrow(/FOREIGN KEY constraint failed/);
  });

  it("iznimka tijekom upisa → 500 internal i `failed` redak", async () => {
    const db = env.DB;
    const failing = {
      prepare: (sql: string) => db.prepare(sql),
      batch: () => Promise.reject(new Error("D1_ERROR: simulirani kvar")),
    } as unknown as D1Database;
    const original = console.error;
    console.error = () => undefined;
    try {
      const init = { method: "POST", headers: requestHeaders({}), body: JSON.stringify({ ...batch, episodes: [{ ...target, title: "Kvar" }] }) };
      const res = await direct("ingest", init, { DB: failing, DEFAULT_BRAND: "domovina", INGEST_TOKEN: TOKEN });
      expect(res.status).toBe(500);
      expect(await res.json()).toEqual({ ok: false, error: "internal" });
    } finally {
      console.error = original;
    }
    const runs = await okRuns();
    const last = runs[runs.length - 1];
    expect(last?.status).toBe("failed");
    expect(last?.counts).toContain("simulirani kvar");
  });
});

describe("ingest/ids", () => {
  const all = plan.episodes.map((e) => e.id).concat(Array.from({ length: MAX_BATCH_EPISODES }, (_, i) => `ep_${i}`));
  const sorted = [...new Set(all)].sort((x, y) => (x < y ? -1 : x > y ? 1 : 0));

  it("zadano: sve epizode brenda (i varijante) u jednoj stranici, po id ASC, next null", async () => {
    const { res, body } = await ids("");
    expect(res.status).toBe(200);
    expect(body.ids).toEqual(sorted);
    expect(body.next).toBeNull();
    expect(plan.episodes.some((e) => e.variantOf !== null && body.ids.includes(e.id))).toBe(true);
  });

  it("keyset stranice: rows_read ograničen veličinom stranice, ne dubinom", async () => {
    const limit = 37;
    const got: string[] = [];
    const reads: number[] = [];
    let after: string | null = null;
    for (let i = 0; i < 100; i++) {
      const q: string = after === null ? `?limit=${limit}` : `?limit=${limit}&after=${encodeURIComponent(after)}`;
      const { res, body } = await ids(q);
      expect(res.status).toBe(200);
      got.push(...body.ids);
      reads.push(body.meta.rows_read);
      // Kontekst (≤ 3) + stranica + jedan redak za `next`.
      expect(body.meta.rows_read).toBeLessThanOrEqual(limit + 1 + 3);
      if (body.next === null) break;
      expect(body.ids).toHaveLength(limit);
      expect(body.next).toBe(body.ids[body.ids.length - 1]);
      after = body.next;
    }
    expect(got).toEqual(sorted);
    expect(reads.length).toBe(Math.ceil(sorted.length / limit));
    // Duboka stranica ne čita više od prve.
    expect(Math.max(...reads)).toBe(reads[0]);
  });

  it("after iza zadnjeg ID-a → prazno; parametri", async () => {
    const { body } = await ids("?after=zzzzzzzzzzzz");
    expect(body).toEqual({ ids: [], next: null, meta: body.meta });
    for (const q of ["?limit=0", "?limit=5001", "?limit=x", "?limit=", "?limit=1.5", "?limit=-1"]) {
      await expectError(ids(q), 400, "bad_limit");
    }
    await expectError(ids("?after="), 400, "bad_after");
    const one = await ids("?limit=1");
    expect(one.body.ids).toEqual(sorted.slice(0, 1));
    expect(one.body.next).toBe(sorted[0]);
  });
});

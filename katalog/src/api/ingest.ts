// Ingest kataloga (S6, odluke 602–607): `POST /ingest` upisuje retke kanala i
// epizoda istim kodom kao uvoznik (`writeRows`), `GET /ingest/ids` daje ID-eve
// epizoda za drift-check. Server-to-server, Bearer token, uvijek `no-store`,
// nikad u Cache API.
import { episodeIds, existingChannelSlugs, MAX_IDS_PAGE_SIZE } from "../db/queries.ts";
import type { Env } from "../env.ts";
import type { ChannelRow, EpisodeRow } from "../ingest/plan.ts";
import { commitRun, discardRun, finishRun, startRun, writeRows } from "../ingest/write.ts";
import { forgetCatalogContexts } from "./context.ts";
import { isIsoDate } from "./cursor.ts";
import { errorResponse, jsonResponse, NO_STORE, Reader, readContext } from "./v1.ts";

/** Najveće tijelo zahtjeva u bajtovima (odluka 603). */
export const MAX_BODY_BYTES = 1_048_576;
/** Najviše redaka po batchu (odluka 603). */
export const MAX_BATCH_EPISODES = 500;
export const MAX_BATCH_CHANNELS = 200;
/** Zadana i najveća stranica `ingest/ids` (odluka 607). */
export const DEFAULT_IDS_PAGE_SIZE = MAX_IDS_PAGE_SIZE;

// ---------------------------------------------------------------- auth

async function sha256(text: string): Promise<ArrayBuffer> {
  return crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
}

/**
 * `null` = smije dalje; inače gotov odgovor. Nema tokena u env-u → 503
 * `ingest_disabled`; nedostaje ili krivi → 401 `unauthorized`. Usporedba je nad
 * SHA-256 obje strane u konstantnom vremenu (jednaka duljina, `timingSafeEqual`),
 * pa ni duljina tokena ne curi (odluka 602).
 */
async function authorize(request: Request, env: Env): Promise<Response | null> {
  const expected = env.INGEST_TOKEN;
  if (expected === undefined || expected.length === 0) return errorResponse(503, "ingest_disabled");
  const m = /^Bearer ([\x21-\x7e]+)$/i.exec(request.headers.get("authorization") ?? "");
  const given = m?.[1];
  if (given === undefined) return errorResponse(401, "unauthorized");
  const [a, b] = await Promise.all([sha256(given), sha256(expected)]);
  return crypto.subtle.timingSafeEqual(a, b) ? null : errorResponse(401, "unauthorized");
}

// ---------------------------------------------------------------- tijelo

/** Tijelo do `max` bajtova; `null` kad je veće (i po `content-length` i po stvarnoj duljini). */
async function readLimited(request: Request, max: number): Promise<Uint8Array | null> {
  const declared = request.headers.get("content-length");
  if (declared !== null && Number(declared) > max) return null;
  if (request.body === null) return new Uint8Array();
  const reader = (request.body as ReadableStream<Uint8Array>).getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > max) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return out;
}

/** Loše polje: `path` je putanja prvog lošeg polja, npr. `episodes[3].tier`. */
class BadBody extends Error {
  readonly path: string;
  constructor(path: string) {
    super(path);
    this.path = path;
  }
}

function fail(path: string): never {
  throw new BadBody(path);
}

type Json = Record<string, unknown>;

/** Objekt s točno zadanim ključevima (ni manje ni više). */
function object(value: unknown, path: string, keys: readonly string[]): Json {
  if (typeof value !== "object" || value === null || Array.isArray(value)) fail(path === "" ? "body" : path);
  const o = value as Json;
  const prefix = path === "" ? "" : `${path}.`;
  for (const k of Object.keys(o)) if (!keys.includes(k)) fail(`${prefix}${k}`);
  for (const k of keys) if (!Object.hasOwn(o, k)) fail(`${prefix}${k}`);
  return o;
}

/** Neprazan string (`length(x) > 0` u shemi). */
function text(value: unknown, path: string): string {
  return typeof value === "string" && value.length > 0 ? value : fail(path);
}

function textOrNull(value: unknown, path: string): string | null {
  return value === null ? null : text(value, path);
}

/** `lang`: NULL ili 2–16 znakova (SQLite `length` broji znakove, ne UTF-16 jedinice). */
function langOrNull(value: unknown, path: string): string | null {
  if (value === null) return null;
  if (typeof value !== "string") fail(path);
  const n = Array.from(value).length;
  return n >= 2 && n <= 16 ? value : fail(path);
}

function dateOrNull(value: unknown, path: string): string | null {
  if (value === null) return null;
  return typeof value === "string" && isIsoDate(value) ? value : fail(path);
}

function tier(value: unknown, path: string): 1 | 2 {
  return value === 1 || value === 2 ? value : fail(path);
}

function integer(value: unknown, path: string, min: number, max: number): number {
  return typeof value === "number" && Number.isSafeInteger(value) && value >= min && value <= max
    ? value
    : fail(path);
}

const CHANNEL_KEYS = [
  "slug",
  "youtubeChannelId",
  "name",
  "tier",
  "lang",
  "avatar",
  "processedCount",
  "latestPublishedDate",
  "unregistered",
] as const satisfies readonly (keyof ChannelRow)[];

const EPISODE_KEYS = [
  "id",
  "channelSlug",
  "title",
  "titleHr",
  "publishedDate",
  "durationSeconds",
  "tier",
  "lang",
  "magisteriumScore",
  "flags",
  "variantOf",
  "publishedAt",
] as const satisfies readonly (keyof EpisodeRow)[];

/** Kanal prema CHECK ograničenjima `channels` (0001, 0002). */
function channelRow(value: unknown, path: string): ChannelRow {
  const o = object(value, path, CHANNEL_KEYS);
  const t = tier(o.tier, `${path}.tier`);
  const unregistered = o.unregistered;
  // `unregistered = 1` samo uz tier 2 (CHECK iz 0002).
  if (typeof unregistered !== "boolean" || (unregistered && t !== 2)) fail(`${path}.unregistered`);
  return {
    slug: text(o.slug, `${path}.slug`),
    youtubeChannelId: textOrNull(o.youtubeChannelId, `${path}.youtubeChannelId`),
    name: text(o.name, `${path}.name`),
    tier: t,
    lang: langOrNull(o.lang, `${path}.lang`),
    avatar: textOrNull(o.avatar, `${path}.avatar`),
    processedCount: integer(o.processedCount, `${path}.processedCount`, 0, Number.MAX_SAFE_INTEGER),
    latestPublishedDate: dateOrNull(o.latestPublishedDate, `${path}.latestPublishedDate`),
    unregistered,
  };
}

/** `published_at` prema CHECK-u iz 0004: `YYYY-MM-DDTHH:MM:SSZ` i stvaran trenutak. */
function instantOrNull(value: unknown, path: string): string | null {
  if (value === null) return null;
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(value)) fail(path);
  const ms = Date.parse(value);
  return Number.isFinite(ms) && new Date(ms).toISOString().replace(".000Z", "Z") === value ? value : fail(path);
}

/** Epizoda prema CHECK ograničenjima `episodes` (0001, 0003, 0004). */
function episodeRow(value: unknown, path: string): EpisodeRow {
  const o = object(value, path, EPISODE_KEYS);
  const d = o.durationSeconds;
  if (d !== null && (typeof d !== "number" || !Number.isFinite(d) || d < 0)) fail(`${path}.durationSeconds`);
  return {
    id: text(o.id, `${path}.id`),
    channelSlug: textOrNull(o.channelSlug, `${path}.channelSlug`),
    title: text(o.title, `${path}.title`),
    titleHr: textOrNull(o.titleHr, `${path}.titleHr`),
    publishedDate: dateOrNull(o.publishedDate, `${path}.publishedDate`),
    durationSeconds: d,
    tier: tier(o.tier, `${path}.tier`),
    lang: langOrNull(o.lang, `${path}.lang`),
    magisteriumScore: o.magisteriumScore === null ? null : integer(o.magisteriumScore, `${path}.magisteriumScore`, 0, 100),
    flags: integer(o.flags, `${path}.flags`, 0, 511),
    variantOf: textOrNull(o.variantOf, `${path}.variantOf`),
    publishedAt: instantOrNull(o.publishedAt, `${path}.publishedAt`),
  };
}

/** `source` u `ingest_runs` (odluka 603): kratko ime izvora, npr. `pipeline`, `drift-check`. */
const SOURCE = /^[a-z][a-z0-9_-]{0,31}$/;

export interface IngestBatch {
  readonly source: string;
  readonly channels: readonly ChannelRow[];
  readonly episodes: readonly EpisodeRow[];
}

type Parsed =
  | { readonly ok: true; readonly batch: IngestBatch }
  | { readonly ok: false; readonly error: "bad_body" | "batch_too_large"; readonly detail: string };

/** Stroga provjera tijela; vraća putanju prvog lošeg polja. Duplikat ključa je loše polje. */
export function parseBatch(value: unknown): Parsed {
  try {
    const o = object(value, "", ["source", "channels", "episodes"]);
    const source = typeof o.source === "string" && SOURCE.test(o.source) ? o.source : fail("source");
    if (!Array.isArray(o.channels)) fail("channels");
    if (!Array.isArray(o.episodes)) fail("episodes");
    const rawChannels: unknown[] = o.channels;
    const rawEpisodes: unknown[] = o.episodes;
    if (rawChannels.length > MAX_BATCH_CHANNELS) return { ok: false, error: "batch_too_large", detail: "channels" };
    if (rawEpisodes.length > MAX_BATCH_EPISODES) return { ok: false, error: "batch_too_large", detail: "episodes" };
    const channels = rawChannels.map((c, i) => channelRow(c, `channels[${i}]`));
    const episodes = rawEpisodes.map((e, i) => episodeRow(e, `episodes[${i}]`));
    const slugs = new Set<string>();
    channels.forEach((c, i) => {
      if (slugs.has(c.slug)) fail(`channels[${i}].slug`);
      slugs.add(c.slug);
    });
    const ids = new Set<string>();
    episodes.forEach((e, i) => {
      if (ids.has(e.id)) fail(`episodes[${i}].id`);
      ids.add(e.id);
    });
    return { ok: true, batch: { source, channels, episodes } };
  } catch (err) {
    if (err instanceof BadBody) return { ok: false, error: "bad_body", detail: err.path };
    throw err;
  }
}

// ---------------------------------------------------------------- POST /ingest

function isForeignKeyError(err: unknown): boolean {
  return err instanceof Error && /FOREIGN KEY constraint failed/i.test(err.message);
}

export async function handleIngest(request: Request, url: URL, env: Env): Promise<Response> {
  const denied = await authorize(request, env);
  if (denied !== null) return denied;

  if (!/^application\/json\s*(;|$)/i.test(request.headers.get("content-type") ?? "")) {
    return errorResponse(400, "bad_content_type");
  }
  const bytes = await readLimited(request, MAX_BODY_BYTES);
  if (bytes === null) return errorResponse(413, "body_too_large");
  let value: unknown;
  try {
    value = JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(bytes));
  } catch {
    return errorResponse(400, "bad_json");
  }
  const parsed = parseBatch(value);
  if (!parsed.ok) return errorResponse(400, parsed.error, parsed.detail);
  const { source, channels, episodes } = parsed.batch;

  const db = env.DB;
  const context = await readContext(new Reader(db), url, env);
  if (context === null) return errorResponse(404, "brand_not_found");
  const { brand } = context;

  // Strani ključ epizoda → kanal se provjerava prije upisa (odluka 605): kanal
  // mora biti u batchu ili u bazi. Bez ovoga bi D1 odbio batch usred upisa, a
  // raniji batchevi od `BATCH_SIZE` naredbi ostali bi upisani.
  const inBatch = new Set(channels.map((c) => c.slug));
  const wanted = [...new Set(episodes.flatMap((e) => (e.channelSlug === null || inBatch.has(e.channelSlug) ? [] : [e.channelSlug])))];
  if (wanted.length > 0) {
    const reader = new Reader(db);
    const rows = await reader.all<{ slug: string }>(existingChannelSlugs(brand, JSON.stringify(wanted)));
    const known = new Set(rows.map((r) => r.slug));
    const i = episodes.findIndex((e) => e.channelSlug !== null && !inBatch.has(e.channelSlug) && !known.has(e.channelSlug));
    if (i >= 0) return errorResponse(409, "unknown_channel", `episodes[${i}].channelSlug`);
  }

  const startedAt = new Date().toISOString();
  const runId = await startRun(db, source, startedAt);
  let catalog = context.catalog;
  let changes;
  try {
    changes = await writeRows(db, brand, channels, episodes, startedAt);
    if (changes.channels + changes.episodes > 0) {
      const counts = { received: { channels: channels.length, episodes: episodes.length }, written: changes };
      catalog = String(await commitRun(db, runId, source, startedAt, new Date().toISOString(), counts));
      // Nova verzija: ovaj izolat ne čeka TTL konteksta (odluka 600).
      forgetCatalogContexts();
    } else {
      // Ponovljen batch ne smije dići verziju i poništiti cache (odluka 606).
      await discardRun(db, runId);
    }
  } catch (err) {
    const what = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
    await finishRun(db, runId, "failed", new Date().toISOString(), { error: what }).catch(() => undefined);
    // Utrka: kanal je obrisan između provjere i upisa.
    if (isForeignKeyError(err)) return errorResponse(409, "unknown_channel");
    throw err;
  }
  return jsonResponse({ ok: true, changes, catalog }, 200, NO_STORE);
}

// ---------------------------------------------------------------- GET /ingest/ids

export async function handleIngestIds(request: Request, url: URL, env: Env): Promise<Response> {
  const denied = await authorize(request, env);
  if (denied !== null) return denied;

  const rawLimit = url.searchParams.get("limit");
  let limit = DEFAULT_IDS_PAGE_SIZE;
  if (rawLimit !== null) {
    if (!/^\d{1,4}$/.test(rawLimit)) return errorResponse(400, "bad_limit");
    limit = Number(rawLimit);
    if (limit < 1 || limit > MAX_IDS_PAGE_SIZE) return errorResponse(400, "bad_limit");
  }
  const after = url.searchParams.get("after");
  if (after?.length === 0) return errorResponse(400, "bad_after");

  const reader = new Reader(env.DB);
  const context = await readContext(reader, url, env);
  if (context === null) return errorResponse(404, "brand_not_found");
  const rows = await reader.all<{ id: string }>(episodeIds(context.brand, limit + 1, after ?? undefined));
  const ids = rows.slice(0, limit).map((r) => r.id);
  const next = rows.length > limit ? (ids[ids.length - 1] ?? null) : null;
  return jsonResponse({ ids, next, meta: { rows_read: reader.rowsRead } }, 200, NO_STORE);
}

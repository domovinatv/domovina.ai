// API v1 nad D1 (odluke 300–3xx). Rute, provjera parametara, omotnica odgovora,
// Cache-Control i `caches.default`. SQL živi u `src/db/queries.ts`; ovdje se
// samo izvršava. Ugovor odgovora: `contract/v1/*.schema.json`.
import {
  allChannels,
  catalogContext,
  channelBySlug,
  channelDirectory,
  channelEpisodes,
  episodeCard,
  episodesOnDay,
  MAX_PAGE_SIZE,
  prepare,
  type SqlQuery,
} from "../db/queries.ts";
import type { Env } from "../env.ts";
import { type CatalogContextValue, contextKey, forgetContext, recallContext, rememberContext } from "./context.ts";
import { decodeCursor, encodeCursor, isIsoDate } from "./cursor.ts";

/** Zadana veličina stranice kad `limit` nije zadan (odluka 304). */
export const DEFAULT_PAGE_SIZE = 30;

/** Verzija ugovora u omotnici; string, jer stari build čita `as String?` (odluka 300). */
export const CONTRACT_VERSION = "1";

/** Koliko dugo `caches.default` drži odgovor jedne verzije kataloga (odluka 307). */
const WORKER_CACHE_TTL = 3600;

export type ErrorCode =
  | "not_found"
  | "brand_not_found"
  | "channel_not_found"
  | "episode_not_found"
  | "bad_cursor"
  | "bad_limit"
  | "bad_tier"
  | "bad_date"
  // Ingest (odluke 603–607).
  | "ingest_disabled"
  | "unauthorized"
  | "bad_content_type"
  | "bad_json"
  | "bad_body"
  | "batch_too_large"
  | "body_too_large"
  | "unknown_channel"
  | "bad_after"
  | "internal";

export type ErrorStatus = 400 | 401 | 404 | 409 | 413 | 500 | 503;

const CACHE_LIST = "public, max-age=60, stale-while-revalidate=600";
const CACHE_CARD = "public, max-age=300, stale-while-revalidate=3600";
const CACHE_DAY_RECENT = "public, max-age=60, stale-while-revalidate=300";
const CACHE_DAY_PAST = "public, max-age=3600, stale-while-revalidate=86400";
export const NO_STORE = "no-store";

function headers(cacheControl: string): Record<string, string> {
  // CORS bez `Vary: Origin` (odluka 308): javni podaci, jedan cache zapis za
  // web (šalje Origin) i native (ne šalje).
  return {
    "content-type": "application/json; charset=utf-8",
    "cache-control": cacheControl,
    "access-control-allow-origin": "*",
  };
}

export function jsonResponse(body: unknown, status: number, cacheControl: string): Response {
  return new Response(JSON.stringify(body), { status, headers: headers(cacheControl) });
}

/** Greška `{ok: false, error}`; `detail` (putanja polja) samo kad je zadan (odluka 604). */
export function errorResponse(status: ErrorStatus, error: ErrorCode, detail?: string): Response {
  return jsonResponse(detail === undefined ? { ok: false, error } : { ok: false, error, detail }, status, NO_STORE);
}

/**
 * Neuhvaćena iznimka (npr. iz D1) → 500 `internal` istog oblika kao ostale
 * greške: JSON, CORS i `no-store`. Bez ovoga runtime vrati goli 500 bez ACAO,
 * pa ga web klijent vidi kao CORS grešku, a ne kao grešku servisa. U log ide
 * samo ime i poruka iznimke i putanja, bez upita i zaglavlja.
 */
export function internalErrorResponse(err: unknown, url: URL): Response {
  const what = err instanceof Error ? `${err.name}: ${err.message}` : String(err);
  console.error(`katalog: iznimka na ${url.pathname}: ${what}`);
  return errorResponse(500, "internal");
}

// ---------------------------------------------------------------- rute

type Route =
  | { readonly kind: "day"; readonly date: string }
  | { readonly kind: "channels" }
  | { readonly kind: "channel"; readonly slug: string }
  | { readonly kind: "channelEpisodes"; readonly slug: string }
  | { readonly kind: "card"; readonly id: string }
  | { readonly kind: "directory" };

/** Segment putanje; `null` kad nije valjan URI-escape ili je prazan. */
function segment(raw: string | undefined): string | null {
  if (raw === undefined || raw.length === 0) return null;
  try {
    return decodeURIComponent(raw);
  } catch {
    return null;
  }
}

/** Putanja ispod prefiksa → ruta; `null` = 404 `not_found`. `:date` se provjerava kasnije (400). */
export function matchRoute(rest: string): Route | null {
  const parts = rest.split("/");
  const [head, a, b] = parts;
  if (parts.length === 1 && head === "channels") return { kind: "channels" };
  if (parts.length === 1 && head === "directory") return { kind: "directory" };
  const first = segment(a);
  if (first === null) return null;
  if (parts.length === 2 && head === "days") return { kind: "day", date: first };
  if (parts.length === 2 && head === "channels") return { kind: "channel", slug: first };
  if (parts.length === 3 && head === "channels" && b === "episodes") return { kind: "channelEpisodes", slug: first };
  if (parts.length === 3 && head === "episodes" && b === "card") return { kind: "card", id: first };
  return null;
}

// ---------------------------------------------------------------- parametri

interface Page {
  readonly limit: number;
  /** `[datum, ključ]` iz kursora; `undefined` = prva stranica. */
  readonly after: readonly [string, string] | undefined;
  /** Kanonski parametri za ključ cachea (sortirani, poznati, normalizirani). */
  readonly canonical: Record<string, string>;
}

type Parsed<T> = { readonly ok: true; readonly value: T } | { readonly ok: false; readonly error: ErrorCode };

function parsePage(params: URLSearchParams): Parsed<Page> {
  const rawLimit = params.get("limit");
  let limit = DEFAULT_PAGE_SIZE;
  if (rawLimit !== null) {
    if (!/^\d{1,3}$/.test(rawLimit)) return { ok: false, error: "bad_limit" };
    limit = Number(rawLimit);
    if (limit < 1 || limit > MAX_PAGE_SIZE) return { ok: false, error: "bad_limit" };
  }
  const canonical: Record<string, string> = { limit: String(limit) };
  const rawCursor = params.get("cursor");
  let after: readonly [string, string] | undefined;
  if (rawCursor !== null) {
    const decoded = decodeCursor(rawCursor);
    if (decoded === null) return { ok: false, error: "bad_cursor" };
    after = decoded;
    canonical.cursor = rawCursor;
  }
  return { ok: true, value: { limit, after, canonical } };
}

function parseTier(params: URLSearchParams): Parsed<1 | 2 | undefined> {
  const raw = params.get("tier");
  if (raw === null) return { ok: true, value: undefined };
  if (raw === "1") return { ok: true, value: 1 };
  if (raw === "2") return { ok: true, value: 2 };
  return { ok: false, error: "bad_tier" };
}

// ---------------------------------------------------------------- retci → JSON

interface CardRow {
  readonly id: string;
  readonly title: string;
  readonly title_hr: string | null;
  readonly published_date: string | null;
  readonly duration_seconds: number | null;
  readonly magisterium_score: number | null;
  readonly flags: number;
  readonly tier: number;
  readonly lang: string | null;
  readonly variant_of: string | null;
  readonly published_at: string | null;
  readonly channel_slug: string | null;
  readonly channel_name: string | null;
  readonly channel_tier: number | null;
}

interface ChannelRow {
  readonly slug: string;
  readonly youtube_channel_id: string | null;
  readonly name: string;
  readonly tier: number;
  readonly lang: string | null;
  readonly avatar: string | null;
  readonly processed_count: number;
  readonly latest_published_date: string | null;
  readonly unregistered: number;
}

/** Kartica epizode (odluka 301), snake_case kao `ChannelVideo.fromJson` / `HomeSnapshot`. */
function card(r: CardRow): Record<string, unknown> {
  return {
    id: r.id,
    title: r.title,
    title_hr: r.title_hr,
    date: r.published_date,
    duration_seconds: r.duration_seconds,
    magisterium_score: r.magisterium_score,
    p: r.flags,
    tier: r.tier,
    lang: r.lang,
    variant_of: r.variant_of,
    published_at: r.published_at,
    channel:
      r.channel_slug === null || r.channel_name === null || r.channel_tier === null
        ? null
        : { slug: r.channel_slug, name: r.channel_name, tier: r.channel_tier },
  };
}

function channel(r: ChannelRow): Record<string, unknown> {
  return {
    slug: r.slug,
    name: r.name,
    tier: r.tier,
    lang: r.lang,
    avatar: r.avatar,
    youtube_channel_id: r.youtube_channel_id,
    processed_count: r.processed_count,
    latest_published_date: r.latest_published_date,
    unregistered: r.unregistered === 1,
  };
}

// ---------------------------------------------------------------- izvršavanje

/**
 * Zbraja `meta.rows_read` svih upita jednog zahtjeva (odluka 300).
 *
 * `lead(q)` stavlja upit u red: ide u isti `db.batch` kao prvi sljedeći upit, pa
 * miss uz zapamćen kontekst čita kontekst i rutu jednim odlaskom do baze
 * (odluka 503/601). Rezultat je u `leadRows` nakon tog upita.
 */
export class Reader {
  rowsRead = 0;
  private readonly db: D1Database;
  private pending: SqlQuery | undefined;
  leadRows: unknown[] | undefined;
  constructor(db: D1Database) {
    this.db = db;
  }

  lead(query: SqlQuery): void {
    this.pending = query;
    this.leadRows = undefined;
  }

  async all<T>(query: SqlQuery): Promise<T[]> {
    if (this.pending !== undefined) {
      const [rows] = await this.batch([query]);
      return (rows ?? []) as T[];
    }
    const res = await prepare(this.db, query).all<T>();
    this.rowsRead += res.meta.rows_read;
    return res.results;
  }

  /** Više upita jednim `db.batch` (jedan odlazak do baze). */
  async batch(queries: readonly SqlQuery[]): Promise<unknown[][]> {
    const lead = this.pending;
    this.pending = undefined;
    const all = lead === undefined ? queries : [lead, ...queries];
    const results = await this.db.batch(all.map((q) => prepare(this.db, q)));
    const rows = results.map((r) => {
      this.rowsRead += r.meta.rows_read;
      return r.results;
    });
    if (lead !== undefined) this.leadRows = rows.shift();
    return rows;
  }

  /** Upit iz `lead` koji nijedan upit nije ponio (ruta bez upita) ide sam. */
  async flushLead(): Promise<void> {
    const lead = this.pending;
    if (lead === undefined) return;
    this.pending = undefined;
    this.leadRows = await this.all(lead);
  }
}

type Outcome =
  | { readonly ok: true; readonly body: Record<string, unknown> }
  | { readonly ok: false; readonly status: 404; readonly error: ErrorCode };

/** `LIMIT n+1`: n+1-vi redak znači da postoji sljedeća stranica (odluka 304). */
function paginate<T>(rows: readonly T[], limit: number, key: (row: T) => readonly [string, string]): {
  page: readonly T[];
  next: string | null;
} {
  if (rows.length <= limit) return { page: rows, next: null };
  const page = rows.slice(0, limit);
  const last = page[page.length - 1];
  if (last === undefined) return { page, next: null };
  const [date, k] = key(last);
  return { page, next: encodeCursor(date, k) };
}

function episodeKey(r: CardRow): readonly [string, string] {
  // Popisi epizoda ne čitaju retke bez datuma (`IS NOT NULL`, odluka 114).
  return [r.published_date ?? "", r.id];
}

function channelKey(r: ChannelRow): readonly [string, string] {
  return [r.latest_published_date ?? "", r.slug];
}

interface Request0 {
  readonly route: Route;
  readonly page: Page | undefined;
  readonly tier: 1 | 2 | undefined;
}

async function compute(reader: Reader, brand: string, req: Request0): Promise<Outcome> {
  const { route, page, tier } = req;
  const n = (page?.limit ?? DEFAULT_PAGE_SIZE) + 1;
  const after = page?.after;
  const list = (items: readonly Record<string, unknown>[], next: string | null): Outcome => ({
    ok: true,
    body: { items, next },
  });

  switch (route.kind) {
    case "day": {
      const rows = await reader.all<CardRow>(episodesOnDay(brand, route.date, n, after?.[1]));
      const { page: p, next } = paginate(rows, n - 1, episodeKey);
      return list(p.map(card), next);
    }
    case "channels":
    case "directory": {
      const cursor = after === undefined ? undefined : { latestPublishedDate: after[0], slug: after[1] };
      const query =
        route.kind === "channels" && tier !== undefined
          ? channelDirectory(brand, tier, n, cursor)
          : allChannels(brand, n, cursor);
      const rows = await reader.all<ChannelRow>(query);
      const { page: p, next } = paginate(rows, n - 1, channelKey);
      return list(p.map(channel), next);
    }
    case "channel": {
      const [row] = await reader.all<ChannelRow>(channelBySlug(brand, route.slug));
      if (row === undefined) return { ok: false, status: 404, error: "channel_not_found" };
      return { ok: true, body: { item: channel(row) } };
    }
    case "channelEpisodes": {
      const cursor = after === undefined ? undefined : { publishedDate: after[0], id: after[1] };
      const [head, rows] = await reader.batch([
        channelBySlug(brand, route.slug),
        channelEpisodes(brand, route.slug, n, cursor),
      ]);
      if (head === undefined || head.length === 0) return { ok: false, status: 404, error: "channel_not_found" };
      const { page: p, next } = paginate((rows ?? []) as CardRow[], n - 1, episodeKey);
      return list(p.map(card), next);
    }
    case "card": {
      const [row] = await reader.all<CardRow>(episodeCard(brand, route.id));
      if (row === undefined) return { ok: false, status: 404, error: "episode_not_found" };
      return { ok: true, body: { item: card(row) } };
    }
  }
}

/** UTC datum `YYYY-MM-DD`, `days` dana od danas (negativno = unatrag). */
function utcDay(now: Date, days: number): string {
  return new Date(now.getTime() + days * 86_400_000).toISOString().slice(0, 10);
}

/** Cache-Control po ruti (odluka 307); računa se pri svakom odgovoru, i na cache hit. */
export function cacheControlFor(route: Route, now: Date): string {
  switch (route.kind) {
    case "day":
      return route.date < utcDay(now, -1) ? CACHE_DAY_PAST : CACHE_DAY_RECENT;
    case "card":
      return CACHE_CARD;
    case "channels":
    case "channel":
    case "channelEpisodes":
    case "directory":
      return CACHE_LIST;
  }
}

/**
 * Ključ u `caches.default` (odluka 307): put + sortirani poznati parametri
 * (normalizirani, nepoznati odbačeni) + `_cv` = verzija kataloga. Novi uvoz daje
 * nove ključeve, pa purge po URL-u nikad ne treba.
 */
export function cacheKey(url: URL, req: Request0, catalog: string | null): string {
  const params: Record<string, string> = { ...(req.page?.canonical ?? {}) };
  if (req.tier !== undefined) params.tier = String(req.tier);
  params._cv = catalog ?? "none";
  const query = Object.keys(params)
    .sort()
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(params[k] ?? "")}`)
    .join("&");
  return `${url.origin}${url.pathname}?${query}`;
}

interface ContextRow {
  readonly host_brand: string | null;
  readonly default_brand: string | null;
  readonly catalog: number | null;
}

/** Redak `catalogContext` → kontekst; `null` = `brand_not_found` (odluka 305). */
export function parseContext(rows: readonly unknown[] | undefined): CatalogContextValue | null {
  const row = rows?.[0] as ContextRow | undefined;
  const brand = row?.host_brand ?? row?.default_brand ?? null;
  if (brand === null) return null;
  return { brand, catalog: row?.catalog == null ? null : String(row.catalog) };
}

/** Kontekst iz D1 (uvijek, bez memorije); ingest ga čita ovako. */
export async function readContext(reader: Reader, url: URL, env: Env): Promise<CatalogContextValue | null> {
  return parseContext(await reader.all(catalogContext(url.hostname, env.DEFAULT_BRAND)));
}

function hitResponse(hit: Response, cacheControl: string): Response {
  return new Response(hit.body, {
    status: 200,
    headers: { ...headers(cacheControl), "x-katalog-cache": "hit" },
  });
}

export async function handleV1(
  url: URL,
  rest: string,
  env: Env,
  ctx: ExecutionContext,
  now: Date = new Date(),
): Promise<Response> {
  const route = matchRoute(rest);
  if (route === null) return errorResponse(404, "not_found");

  // Parametri se provjeravaju prije baze: loš zahtjev ne troši rows_read.
  if (route.kind === "day" && !isIsoDate(route.date)) return errorResponse(400, "bad_date");
  let page: Page | undefined;
  let tier: 1 | 2 | undefined;
  if (route.kind !== "channel" && route.kind !== "card") {
    const p = parsePage(url.searchParams);
    if (!p.ok) return errorResponse(400, p.error);
    page = p.value;
    // Kursor dana nosi isti datum kao putanja (odluka 304).
    if (route.kind === "day" && page.after !== undefined && page.after[0] !== route.date) {
      return errorResponse(400, "bad_cursor");
    }
  }
  if (route.kind === "channels") {
    const t = parseTier(url.searchParams);
    if (!t.ok) return errorResponse(400, t.error);
    tier = t.value;
  }
  const req: Request0 = { route, page, tier };

  // Hit uz zapamćen kontekst ne dira `env.DB` (odluke 502, 600).
  const cacheControl = cacheControlFor(route, now);
  const cache = caches.default;
  const memKey = contextKey(url.hostname, env.DEFAULT_BRAND);
  const nowMs = now.getTime();
  const remembered = recallContext(memKey, nowMs);
  if (remembered !== undefined) {
    const hit = await cache.match(cacheKey(url, req, remembered.catalog));
    if (hit !== undefined) return hitResponse(hit, cacheControl);
  }

  // Miss: kontekst se uvijek ponovno čita iz D1 (svjež `catalog` za ključ, isti
  // `rows_read` kao prije memorije). Uz zapamćen brend ide u isti `db.batch` kao
  // upit rute (odluka 601); bez njega prvo kontekst, pa cache pod svježim ključem.
  const reader = new Reader(env.DB);
  const contextQuery = catalogContext(url.hostname, env.DEFAULT_BRAND);
  let context: CatalogContextValue | null;
  let out: Outcome | undefined;
  if (remembered !== undefined) {
    reader.lead(contextQuery);
    out = await compute(reader, remembered.brand, req);
    await reader.flushLead();
    context = parseContext(reader.leadRows);
    // Brend hosta se promijenio unutar TTL-a: izračun s krivim brendom se baca.
    if (context?.brand !== remembered.brand) out = undefined;
  } else {
    context = parseContext(await reader.all(contextQuery));
  }
  if (context === null) {
    forgetContext(memKey);
    return errorResponse(404, "brand_not_found");
  }
  rememberContext(memKey, context, nowMs);
  const { brand, catalog } = context;
  const key = cacheKey(url, req, catalog);
  if (out === undefined) {
    const hit = await cache.match(key);
    if (hit !== undefined) return hitResponse(hit, cacheControl);
    out = await compute(reader, brand, req);
  }

  if (!out.ok) return errorResponse(out.status, out.error);
  const body = JSON.stringify({
    version: CONTRACT_VERSION,
    catalog,
    ...out.body,
    meta: { rows_read: reader.rowsRead },
  });
  ctx.waitUntil(
    cache.put(
      key,
      new Response(body, {
        headers: {
          "content-type": "application/json; charset=utf-8",
          "cache-control": `public, max-age=${WORKER_CACHE_TTL}`,
        },
      }),
    ),
  );
  return new Response(body, { status: 200, headers: { ...headers(cacheControl), "x-katalog-cache": "miss" } });
}

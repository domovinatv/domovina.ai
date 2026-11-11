// Jezgra `channel-slugs-sync` i provjere pokrivenosti slugova u drift-checku:
// slug kataloga → UC (odluka 202 lanca `postavke-kanala/`) prema tablici
// `domovina_ai.channel_slugs` u domovina-api. Bez Node API-ja: mreža (`fetch`)
// i ulazi se predaju, pa se testira u workerd poolu.
//
// Pravila:
//   - izvor je katalog (`GET /api/katalog/v1/channels`, sve stranice): slug + UC;
//   - kanal bez UC-a u katalogu dobiva UC iz registryja (`registryUcBySlug`,
//     odluka 101: `launched`, `subclub`) dok uvoz s padom ne stigne u produkciju;
//   - samo upis (upsert): redak u `channel_slugs` kojeg katalog nema se NE briše
//     (kampanja pinke vezana na stari slug i dalje mora naći kanal), nego se
//     samo javlja (`onlyInTarget`).
import { UC_PATTERN } from "../../src/settings/keys.ts";

export const KATALOG_PREFIX = "/api/katalog/v1";
/** Najveći `limit` kataloga (MAX_PAGE_SIZE). */
export const CHANNELS_PAGE = 100;
/** Ograda protiv kursora bez kraja. */
const MAX_PAGES = 100;

export interface CatalogChannel {
  readonly slug: string;
  readonly youtubeChannelId: string | null;
}

export interface SlugMap {
  /** slug → UC, poredano po slugu. */
  readonly map: ReadonlyMap<string, string>;
  /** Slugovi kojima je UC došao iz registryja. */
  readonly fromRegistry: readonly string[];
  /** Slugovi bez UC-a ni u katalogu ni u registryju (RSS, X; odluka 102). */
  readonly withoutUc: readonly string[];
}

export function buildSlugMap(channels: readonly CatalogChannel[], registryUc: ReadonlyMap<string, string>): SlugMap {
  const map = new Map<string, string>();
  const fromRegistry: string[] = [];
  const withoutUc: string[] = [];
  for (const c of [...channels].sort((a, b) => (a.slug < b.slug ? -1 : a.slug > b.slug ? 1 : 0))) {
    if (c.youtubeChannelId !== null && UC_PATTERN.test(c.youtubeChannelId)) {
      map.set(c.slug, c.youtubeChannelId);
      continue;
    }
    const uc = registryUc.get(c.slug);
    if (uc !== undefined) {
      map.set(c.slug, uc);
      fromRegistry.push(c.slug);
    } else {
      withoutUc.push(c.slug);
    }
  }
  return { map, fromRegistry, withoutUc };
}

export interface SlugRow {
  readonly slug: string;
  readonly youtube_channel_id: string;
}

export interface SlugDiff {
  readonly insert: readonly SlugRow[];
  /** Slug postoji s drugim UC-om. */
  readonly update: readonly (SlugRow & { readonly from: string })[];
  readonly unchanged: number;
  /** U `channel_slugs`, a katalog ga nema (ne briše se). */
  readonly onlyInTarget: readonly string[];
}

export function diffSlugs(desired: ReadonlyMap<string, string>, existing: ReadonlyMap<string, string>): SlugDiff {
  const insert: SlugRow[] = [];
  const update: (SlugRow & { from: string })[] = [];
  let unchanged = 0;
  for (const [slug, uc] of desired) {
    const cur = existing.get(slug);
    if (cur === undefined) insert.push({ slug, youtube_channel_id: uc });
    else if (cur !== uc) update.push({ slug, youtube_channel_id: uc, from: cur });
    else unchanged += 1;
  }
  const onlyInTarget = [...existing.keys()].filter((s) => !desired.has(s)).sort();
  return { insert, update, unchanged, onlyInTarget };
}

// ---- HTTP ------------------------------------------------------------------

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

export class HttpError extends Error {
  override readonly name = "HttpError";
}

/** Ključ se nikad ne ispisuje, ni ako ga server vrati u poruci. */
export function redactKey(text: string, key: string | null): string {
  return key === null || key.length < 8 ? text : text.split(key).join("***");
}

async function getJson(f: typeof fetch, url: string, headers: Record<string, string>): Promise<unknown> {
  let res: Response;
  try {
    res = await f(url, { headers: { accept: "application/json", ...headers } });
  } catch (err) {
    throw new HttpError(`GET ${url.replace(/\?.*$/, "")}: mreža: ${err instanceof Error ? err.message : String(err)}`);
  }
  const text = await res.text();
  if (!res.ok) throw new HttpError(`GET ${url.replace(/\?.*$/, "")}: HTTP ${res.status} ${text.slice(0, 200)}`.trimEnd());
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(`GET ${url.replace(/\?.*$/, "")}: tijelo nije JSON`);
  }
}

/** Svi kanali kataloga (sve stranice `GET /channels`). */
export async function fetchCatalogChannels(f: typeof fetch, base: string): Promise<CatalogChannel[]> {
  const out: CatalogChannel[] = [];
  let cursor: string | null = null;
  for (let page = 0; page < MAX_PAGES; page++) {
    const qs = new URLSearchParams({ limit: String(CHANNELS_PAGE) });
    if (cursor !== null) qs.set("cursor", cursor);
    const body = await getJson(f, `${base}${KATALOG_PREFIX}/channels?${qs.toString()}`, {});
    if (!isObject(body) || !Array.isArray(body.items)) throw new HttpError("GET /channels: odgovor nema items");
    for (const it of body.items as unknown[]) {
      if (!isObject(it) || typeof it.slug !== "string") throw new HttpError("GET /channels: kanal bez sluga");
      const uc = it.youtube_channel_id;
      if (uc !== null && typeof uc !== "string") throw new HttpError(`GET /channels: ${it.slug}.youtube_channel_id`);
      out.push({ slug: it.slug, youtubeChannelId: uc });
    }
    const next = body.next;
    if (next === null) return out;
    if (typeof next !== "string" || next === cursor) throw new HttpError("GET /channels: neispravan next");
    cursor = next;
  }
  throw new HttpError(`GET /channels: više od ${MAX_PAGES} stranica`);
}

function restHeaders(key: string): Record<string, string> {
  return { apikey: key, authorization: `Bearer ${key}`, "accept-profile": "domovina_ai" };
}

/** Cijela `domovina_ai.channel_slugs` (čitljiva i anon ključem). */
export async function fetchChannelSlugs(f: typeof fetch, apiBase: string, key: string): Promise<Map<string, string>> {
  const out = new Map<string, string>();
  const page = 1000;
  for (let offset = 0; ; offset += page) {
    const qs = new URLSearchParams({ select: "slug,youtube_channel_id", order: "slug.asc", limit: String(page), offset: String(offset) });
    const body = await getJson(f, `${apiBase}/rest/v1/channel_slugs?${qs.toString()}`, restHeaders(key));
    if (!Array.isArray(body)) throw new HttpError("channel_slugs: odgovor nije polje");
    for (const r of body as unknown[]) {
      if (!isObject(r) || typeof r.slug !== "string" || typeof r.youtube_channel_id !== "string") {
        throw new HttpError("channel_slugs: neispravan redak");
      }
      out.set(r.slug, r.youtube_channel_id);
    }
    if (body.length < page) return out;
  }
}

/**
 * Upsert redaka u `channel_slugs` (PostgREST `resolution=merge-duplicates`,
 * po PK `slug`). Treba `service_role` ključ. Idempotentno.
 */
export async function upsertChannelSlugs(
  f: typeof fetch,
  apiBase: string,
  serviceKey: string,
  rows: readonly SlugRow[],
  now: Date,
): Promise<number> {
  if (rows.length === 0) return 0;
  const body = rows.map((r) => ({ slug: r.slug, youtube_channel_id: r.youtube_channel_id, updated_at: now.toISOString() }));
  let res: Response;
  try {
    res = await f(`${apiBase}/rest/v1/channel_slugs?on_conflict=slug`, {
      method: "POST",
      headers: {
        ...restHeaders(serviceKey),
        "content-profile": "domovina_ai",
        "content-type": "application/json",
        prefer: "resolution=merge-duplicates,return=minimal",
      },
      body: JSON.stringify(body),
    });
  } catch (err) {
    throw new HttpError(`POST channel_slugs: mreža: ${err instanceof Error ? err.message : String(err)}`);
  }
  if (!res.ok) throw new HttpError(`POST channel_slugs: HTTP ${res.status} ${(await res.text()).slice(0, 200)}`.trimEnd());
  return rows.length;
}

/** `KEY=vrijednost` iz env datoteke (navodnici dopušteni); `null` kad retka nema. */
export function valueFromEnvText(text: string, name: string): string | null {
  for (const line of text.split(/\r?\n/)) {
    const m = /^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$/.exec(line);
    if (m?.[1] !== name) continue;
    const v = (m[2] ?? "").replace(/^(['"])(.*)\1$/, "$2");
    return v === "" ? null : v;
  }
  return null;
}

// Jezgra `katalog drift-check`: R2 (izvor istine) ↔ D1 (projekcija). Bez Node
// API-ja i bez globalnog stanja — datoteke, mreža i plan se predaju, pa se sve
// ovdje testira u workerd poolu sa stubom `fetch`a. CLI: `scripts/drift-check.ts`.
//
// Što je „poravnato” (zašto je drift SAMO `missing`):
//   R2   = ID-evi s `data/<id>/article.json` u `.r2_keys_cache.json`.
//   D1   = svi ID-evi epizoda brenda (`GET /ingest/ids`).
//   Uvoznik (`buildPlan`) upisuje Tier 1 = SVE epizode iz listinga (i one bez
//   `article.json`) + Tier 2 = ostatak R2 članaka, uključujući eksperimentalne
//   varijante (`variant_of`). Poravnat D1 je zato NADSKUP R2 članaka:
//     missing = R2 \ D1  → drift (exit 1), to `--sync` popravlja;
//     extra   = D1 \ R2  → samo izvještaj, ne utječe na exit kod i ništa se ne
//               briše. Legitimno nastaje iz Tier 1 epizode bez članka i iz key
//               cachea koji zaostaje za CDN listingom (pipeline je epizodu već
//               objavio, a fetch repo još nije osvježio cache). Izmjereno 6.11.:
//               „Tier 1 epizode bez article.json” = 0, pa je danas extra 0.
//
// Exit kodovi su UGOVOR (kao `sync_voting_candidates.mjs --check`):
//   0 = poravnato (ili `--sync` je popravio i ponovno mjerenje je konvergiralo),
//   1 = drift (samo bez `--sync`),
//   2 = ne mogu provjeriti: nema/nečitljiv cache, mreža, 401/5xx, nevaljan
//       odgovor, sync pao ili nije konvergirao. SVAKA neočekivana iznimka je 2,
//       nikad 1: „ne znam” se ne smije čitati kao „ima drifta” (povijesni bug
//       voting tripwirea: TypeError je izlazio s 1).
import { articleIds, parseKeyCache } from "../../src/ingest/keys.ts";
import type { ChannelRow, EpisodeRow, ImportPlan } from "../../src/ingest/plan.ts";

export const EXIT_OK = 0;
export const EXIT_DRIFT = 1;
export const EXIT_UNKNOWN = 2;
export type ExitCode = typeof EXIT_OK | typeof EXIT_DRIFT | typeof EXIT_UNKNOWN;

export const API_PREFIX = "/api/katalog/v1";
export const DEFAULT_BASE = "https://domovina.ai";
export const IDS_PAGE_LIMIT = 5000;
export const MAX_CHANNELS_PER_CALL = 200;
export const MAX_EPISODES_PER_CALL = 500;
export const INGEST_SOURCE = "drift-check";
/** Ograda protiv servera koji vraća `next` bez kraja (5000 × 1000 = 5 M epizoda). */
const MAX_ID_PAGES = 1000;

/** „Ne mogu provjeriti” — uvijek exit 2. */
export class CannotCheck extends Error {
  override readonly name = "CannotCheck";
}

export interface Api {
  readonly base: string;
  readonly token: string;
  readonly fetch: typeof fetch;
}

// ---- Ulazi -----------------------------------------------------------------

/** Tekst `.r2_keys_cache.json` → R2 ID-evi s člankom i popis datoteka po ID-u. */
export function readKeyCacheText(text: string): { files: Map<string, ReadonlySet<string>>; articles: string[] } {
  let files: Map<string, ReadonlySet<string>>;
  try {
    files = parseKeyCache(JSON.parse(text));
  } catch (err) {
    throw new CannotCheck(`key cache nečitljiv: ${message(err)}`, { cause: err });
  }
  const articles = articleIds(files);
  // Prazan cache bi dao missing = 0 i „poravnato” za bilo koji D1: to je „ne znam”.
  if (articles.length === 0) throw new CannotCheck("key cache nema nijedan data/<id>/article.json");
  return { files, articles };
}

/** Redak `INGEST_TOKEN=` iz `.dev.vars` (navodnici dopušteni); `null` kad ga nema. */
export function tokenFromDevVars(text: string): string | null {
  for (const raw of text.split(/\r?\n/)) {
    const m = /^\s*(?:export\s+)?INGEST_TOKEN\s*=\s*(.*)$/.exec(raw);
    if (m === null) continue;
    let v = (m[1] ?? "").trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) v = v.slice(1, -1);
    return v === "" ? null : v;
  }
  return null;
}

// ---- Usporedba -------------------------------------------------------------

export interface Comparison {
  readonly r2: number;
  readonly d1: number;
  /** U R2 (ima članak), a nema u D1 — sortirano. */
  readonly missing: readonly string[];
  /** U D1, a nema članka na R2 — sortirano, samo informativno. */
  readonly extra: readonly string[];
}

const byKey = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);

export function compare(r2Ids: Iterable<string>, d1Ids: Iterable<string>): Comparison {
  const r2 = new Set(r2Ids);
  const d1 = new Set(d1Ids);
  return {
    r2: r2.size,
    d1: d1.size,
    missing: [...r2].filter((id) => !d1.has(id)).sort(byKey),
    extra: [...d1].filter((id) => !r2.has(id)).sort(byKey),
  };
}

/** Drift je samo `missing` (vidi zaglavlje). */
export function exitCodeFor(c: Comparison): typeof EXIT_OK | typeof EXIT_DRIFT {
  return c.missing.length === 0 ? EXIT_OK : EXIT_DRIFT;
}

// ---- HTTP ------------------------------------------------------------------

export function normalizeBase(base: string): string {
  let u: URL;
  try {
    u = new URL(base);
  } catch {
    throw new CannotCheck(`--base nije URL: ${base}`);
  }
  if (u.protocol !== "https:" && u.protocol !== "http:") throw new CannotCheck(`--base mora biti http(s): ${base}`);
  return u.origin + u.pathname.replace(/\/+$/, "");
}

/** Token se nikad ne ispisuje, ni ako ga server ili runtime vrati u poruci. */
export function redact(text: string, token: string | null): string {
  // Kratki niz (test, tipfeler) bi izrezao pola poruke; pravi token je dug.
  return token === null || token.length < 8 ? text : text.split(token).join("***");
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

async function request(api: Api, method: "GET" | "POST", path: string, body?: unknown): Promise<unknown> {
  const url = api.base + API_PREFIX + path;
  const what = `${method} ${API_PREFIX}${path.replace(/\?.*$/, "")}`;
  const headers: Record<string, string> = { authorization: `Bearer ${api.token}`, accept: "application/json" };
  const init: RequestInit = { method, headers };
  if (body !== undefined) {
    headers["content-type"] = "application/json";
    init.body = JSON.stringify(body);
  }
  let res: Response;
  try {
    res = await api.fetch(url, init);
  } catch (err) {
    throw new CannotCheck(`${what}: mreža: ${message(err)}`, { cause: err });
  }
  let text: string;
  try {
    text = await res.text();
  } catch (err) {
    throw new CannotCheck(`${what}: HTTP ${res.status}, tijelo nečitljivo: ${message(err)}`, { cause: err });
  }
  if (res.status === 401) throw new CannotCheck(`${what}: HTTP 401, token odbijen`);
  let json: unknown = undefined;
  try {
    json = JSON.parse(text);
  } catch {
    /* ne-JSON tijelo: niže */
  }
  if (!res.ok) {
    const detail = isObject(json) && typeof json.detail === "string" ? ` (${json.detail})` : "";
    const code = isObject(json) && typeof json.error === "string" ? json.error + detail : text.slice(0, 200);
    throw new CannotCheck(`${what}: HTTP ${res.status} ${code}`.trimEnd());
  }
  if (json === undefined) throw new CannotCheck(`${what}: HTTP ${res.status}, tijelo nije JSON`);
  return json;
}

export interface IdsResult {
  readonly ids: string[];
  readonly pages: number;
  readonly rowsRead: number;
}

/** Svi ID-evi epizoda brenda iz D1, sve stranice `GET /ingest/ids`. */
export async function fetchAllIds(api: Api, pageLimit: number = IDS_PAGE_LIMIT): Promise<IdsResult> {
  const ids: string[] = [];
  let after: string | null = null;
  let pages = 0;
  let rowsRead = 0;
  for (;;) {
    if (pages >= MAX_ID_PAGES) throw new CannotCheck(`ingest/ids: više od ${MAX_ID_PAGES} stranica`);
    const qs: string = `?limit=${pageLimit}` + (after === null ? "" : `&after=${encodeURIComponent(after)}`);
    const json = await request(api, "GET", `/ingest/ids${qs}`);
    pages++;
    if (!isObject(json) || !Array.isArray(json.ids) || !json.ids.every((id) => typeof id === "string")) {
      throw new CannotCheck("ingest/ids: odgovor nema ids: string[]");
    }
    const next = json.next;
    if (next !== null && typeof next !== "string") throw new CannotCheck("ingest/ids: next nije string ni null");
    const page = json.ids;
    ids.push(...page);
    const meta = json.meta;
    if (isObject(meta) && typeof meta.rows_read === "number") rowsRead += meta.rows_read;
    if (next === null) break;
    // Stranica bez napretka bi se vrtjela zauvijek.
    if (page.length === 0 || next === after) throw new CannotCheck(`ingest/ids: next=${next} bez napretka`);
    after = next;
  }
  return { ids, pages, rowsRead };
}

export interface IngestBody {
  readonly source: string;
  readonly channels: readonly ChannelRow[];
  readonly episodes: readonly EpisodeRow[];
}

function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += size) out.push(items.slice(i, i + size));
  return out;
}

/**
 * Pozivi za cijeli plan: svi kanali PRIJE epizoda (epizoda smije referencirati
 * kanal iz istog ili ranijeg poziva). Zadnji poziv s kanalima nosi i prvih
 * ≤ 500 epizoda, pa za ≤ 200 kanala nema poziva sa samim kanalima.
 */
export function ingestBatches(
  plan: Pick<ImportPlan, "channels" | "episodes">,
  source: string = INGEST_SOURCE,
): IngestBody[] {
  const ch = chunk(plan.channels, MAX_CHANNELS_PER_CALL);
  const ep = chunk(plan.episodes, MAX_EPISODES_PER_CALL);
  const out: IngestBody[] = ch.map((channels) => ({ source, channels, episodes: [] }));
  const last = out.at(-1);
  const first = ep.shift();
  if (last !== undefined && first !== undefined) out[out.length - 1] = { ...last, episodes: first };
  else if (first !== undefined) ep.unshift(first);
  for (const episodes of ep) out.push({ source, channels: [], episodes });
  return out;
}

export interface IngestResult {
  readonly calls: number;
  readonly changes: { channels: number; episodes: number };
  readonly catalog: unknown;
}

export async function postIngest(api: Api, batches: readonly IngestBody[]): Promise<IngestResult> {
  const changes = { channels: 0, episodes: 0 };
  let catalog: unknown = null;
  let calls = 0;
  for (const body of batches) {
    const json = await request(api, "POST", "/ingest", body);
    calls++;
    if (!isObject(json) || json.ok !== true || !isObject(json.changes)) {
      throw new CannotCheck(`POST ingest (poziv ${calls}/${batches.length}): odgovor nije {ok:true, changes}`);
    }
    const c = json.changes;
    if (typeof c.channels === "number") changes.channels += c.channels;
    if (typeof c.episodes === "number") changes.episodes += c.episodes;
    catalog = json.catalog ?? null;
  }
  return { calls, changes, catalog };
}

// ---- Tok -------------------------------------------------------------------

export interface DriftDeps {
  readonly base: string;
  /** `null` = nema tokena (exit 2). */
  readonly token: string | null;
  readonly fetch: typeof fetch;
  readonly keyCachePath: string;
  /** Sirovi tekst key cachea; baca kad datoteke nema. */
  readonly readKeyCache: () => Promise<string>;
  readonly sync: boolean;
  /** Puni plan kao uvoznik; zove se samo uz `--sync` i drift. */
  readonly buildPlan: (files: ReadonlyMap<string, ReadonlySet<string>>) => Promise<Pick<ImportPlan, "channels" | "episodes">>;
  readonly now?: () => Date;
}

export interface SideReport {
  readonly r2: number;
  readonly d1: number;
  readonly missing: readonly string[];
  readonly extraCount: number;
  readonly extraSample: readonly string[];
}

export interface DriftReport {
  readonly checkedAt: string;
  readonly base: string;
  readonly keyCachePath: string;
  status: "ok" | "drift" | "synced" | "unknown";
  exitCode: ExitCode;
  before?: SideReport & { readonly idPages: number; readonly rowsRead: number };
  sync?: {
    readonly planChannels: number;
    readonly planEpisodes: number;
    calls: number;
    changes?: { channels: number; episodes: number };
    catalog?: unknown;
    after?: SideReport;
    converged: boolean;
  };
  error?: string;
}

const SAMPLE = 10;

function side(c: Comparison): SideReport {
  return { r2: c.r2, d1: c.d1, missing: c.missing, extraCount: c.extra.length, extraSample: c.extra.slice(0, SAMPLE) };
}

export async function runDriftCheck(deps: DriftDeps): Promise<DriftReport> {
  const report: DriftReport = {
    checkedAt: (deps.now?.() ?? new Date()).toISOString(),
    base: deps.base,
    keyCachePath: deps.keyCachePath,
    status: "unknown",
    exitCode: EXIT_UNKNOWN,
  };
  try {
    const base = normalizeBase(deps.base);
    if (deps.token === null || deps.token === "") {
      throw new CannotCheck("nema INGEST_TOKEN (ni u okolini ni u katalog/.dev.vars)");
    }
    const api: Api = { base, token: deps.token, fetch: deps.fetch };

    let text: string;
    try {
      text = await deps.readKeyCache();
    } catch (err) {
      throw new CannotCheck(`key cache ${deps.keyCachePath}: ${message(err)}`, { cause: err });
    }
    const { files, articles } = readKeyCacheText(text);

    const d1 = await fetchAllIds(api);
    const before = compare(articles, d1.ids);
    report.before = { ...side(before), idPages: d1.pages, rowsRead: d1.rowsRead };
    const code = exitCodeFor(before);
    if (code === EXIT_OK) {
      report.status = "ok";
      report.exitCode = EXIT_OK;
      return report;
    }
    if (!deps.sync) {
      report.status = "drift";
      report.exitCode = EXIT_DRIFT;
      return report;
    }

    // Puni plan, ne samo missing: ingest je idempotentan (0 promjena ne diže
    // verziju), ~8 poziva za ~3700 epizoda, i usput popravi izmijenjene retke.
    const plan = await deps.buildPlan(files);
    const batches = ingestBatches(plan);
    const sync: NonNullable<DriftReport["sync"]> = {
      planChannels: plan.channels.length,
      planEpisodes: plan.episodes.length,
      calls: 0,
      converged: false,
    };
    report.sync = sync;
    const written = await postIngest(api, batches);
    sync.calls = written.calls;
    sync.changes = written.changes;
    sync.catalog = written.catalog;

    // Kao `verifyConverged` u voting toku: pisanje je više poziva, nije atomarno.
    const after = compare(articles, (await fetchAllIds(api)).ids);
    sync.after = side(after);
    sync.converged = after.missing.length === 0;
    if (!sync.converged) {
      throw new CannotCheck(`sync nije konvergirao: nakon upisa još ${after.missing.length} missing`);
    }
    report.status = "synced";
    report.exitCode = EXIT_OK;
    return report;
  } catch (err) {
    report.status = "unknown";
    report.exitCode = EXIT_UNKNOWN;
    report.error = redact(message(err), deps.token);
    return report;
  }
}

/** Kratak ispis za stdout (i Telegram omotač). */
export function formatReport(r: DriftReport, verbose = false): string[] {
  const lines: string[] = [];
  const line = (k: string, v: string | number): void => {
    lines.push(`  ${k.padEnd(22)} ${v}`);
  };
  const ids = (a: readonly string[]): string =>
    a.length === 0 ? "0" : `${a.length}  ${a.slice(0, SAMPLE).join(" ")}${a.length > SAMPLE ? " …" : ""}`;
  lines.push(`katalog drift-check  ${r.base}`);
  const b = r.before;
  if (b !== undefined) {
    line("R2 (article.json)", b.r2);
    line("D1 (epizode)", b.d1);
    line("missing", ids(b.missing));
    line("extra (informativno)", b.extraCount);
    if (verbose) {
      if (b.extraCount > 0) line("extra uzorak", b.extraSample.join(" "));
      line("ingest/ids stranice", `${b.idPages} (rows_read ${b.rowsRead})`);
      line("key cache", r.keyCachePath);
    }
  }
  const s = r.sync;
  if (s !== undefined) {
    line("sync plan", `${s.planChannels} kanala, ${s.planEpisodes} epizoda`);
    line("sync pozivi", s.calls);
    if (s.changes !== undefined) line("sync promjene", `${s.changes.channels} kanala, ${s.changes.episodes} epizoda`);
    if (s.after !== undefined) line("nakon synca missing", ids(s.after.missing));
  }
  if (r.error !== undefined) line("GREŠKA", r.error);
  const verdict = { ok: "poravnato", drift: "DRIFT", synced: "poravnato nakon synca", unknown: "ne mogu provjeriti" };
  line("ishod", `${verdict[r.status]} (exit ${r.exitCode})`);
  return lines;
}

function message(err: unknown): string {
  if (!(err instanceof Error)) return String(err);
  // undici: „fetch failed” bez razloga; razlog (ECONNREFUSED, ENOTFOUND…) je u `cause`.
  const cause: unknown = err.cause;
  if (err instanceof TypeError && cause instanceof Error && cause.message !== "") return `${err.message} (${cause.message})`;
  return err.message;
}

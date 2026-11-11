// Drift postavki kanala: domovina-api (izvor istine) ↔ katalog (projekcija koju
// puni poller). Dio `drift-check`a; bez Node API-ja, `fetch` se predaje.
//
// Izvor: `public_channel_settings` + `public_channel_tombstones` (anon ključ).
// Katalog: `GET {base}/api/katalog/v1/settings`, tijelo
//   {"version":"1","catalog":…,"settings":{"<UC>":{"status","off":[…],"deleted_at"?}},"meta":{…}}
// sa samo onim UC-ovima koji imaju barem jedan `false` u `effective` ili tombstone.
//
// Što je drift (exit 1, SAMO izvještaj; popravlja ga poller, ne ova skripta):
//   missing    UC koji izvor traži, a katalog ga nema;
//   extra      UC u katalogu kojeg izvor ne traži (npr. vlasnik je sve vratio,
//              a poller još nije upisao);
//   mismatched različit status ili popis `off`; za `deleted` se uspoređuje
//              `deleted_at` (kao trenutak), a `off` ne (obrisan kanal nema ništa).
//   slugovi    slug kataloga s UC-om kojeg nema u `channel_slugs` ili ima drugi
//              UC (popravak: `npm run channel-slugs-sync -- --commit`).
// „Ne mogu provjeriti” (mreža, 401/404/5xx, nevaljan odgovor, nema ključa) je
// exit 2, nikad 1.
import { parseSettingsRows, parseTombstoneRows, SourceError } from "../../src/settings/source.ts";
import { buildSlugMap, diffSlugs, fetchCatalogChannels, fetchChannelSlugs, KATALOG_PREFIX, redactKey } from "./channel-slugs.ts";
import { EXIT_DRIFT, EXIT_OK, EXIT_UNKNOWN, type ExitCode } from "./drift.ts";

export type SettingsStatus = "active" | "withdrawn" | "deleted";

export interface SettingsEntry {
  readonly status: SettingsStatus;
  /** Ključevi s `false`, poredani. */
  readonly off: readonly string[];
  readonly deleted_at?: string;
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

class CannotCheck extends Error {
  override readonly name = "CannotCheck";
}

/** Očekivano stanje kataloga iz redaka izvora (pravilo odgovora `/settings`). */
export function expectedSettings(rawSettings: unknown, rawTombstones: unknown): Map<string, SettingsEntry> {
  const rows = parseSettingsRows(rawSettings);
  const tombs = new Map(parseTombstoneRows(rawTombstones).map((t) => [t.youtubeChannelId, t.deletedAt]));
  const out = new Map<string, SettingsEntry>();
  for (const r of rows) {
    const eff = JSON.parse(r.effective) as Record<string, boolean>;
    const off = Object.keys(eff)
      .filter((k) => !eff[k])
      .sort();
    const deletedAt = tombs.get(r.youtubeChannelId);
    if (r.tombstoned || deletedAt !== undefined) {
      if (deletedAt === undefined) throw new SourceError(`${r.youtubeChannelId}: tombstoned bez tombstonea`);
      out.set(r.youtubeChannelId, { status: "deleted", off, deleted_at: deletedAt });
    } else if (off.length > 0) {
      out.set(r.youtubeChannelId, { status: eff.channel_enabled === false ? "withdrawn" : "active", off });
    }
  }
  return out;
}

/** Tijelo `GET /settings` kataloga → mapa; stroga provjera oblika. */
export function parseKatalogSettings(body: unknown): Map<string, SettingsEntry> {
  if (!isObject(body) || body.version !== "1" || !isObject(body.settings)) {
    throw new CannotCheck("GET /settings: odgovor nema version \"1\" i objekt settings");
  }
  const out = new Map<string, SettingsEntry>();
  for (const [uc, v] of Object.entries(body.settings)) {
    if (!isObject(v)) throw new CannotCheck(`GET /settings: ${uc} nije objekt`);
    const { status, off, deleted_at: deletedAt } = v;
    if (status !== "active" && status !== "withdrawn" && status !== "deleted") {
      throw new CannotCheck(`GET /settings: ${uc}.status`);
    }
    if (!Array.isArray(off) || !off.every((k): k is string => typeof k === "string")) {
      throw new CannotCheck(`GET /settings: ${uc}.off`);
    }
    if (deletedAt !== undefined && (typeof deletedAt !== "string" || Number.isNaN(Date.parse(deletedAt)))) {
      throw new CannotCheck(`GET /settings: ${uc}.deleted_at`);
    }
    if (status === "deleted" && deletedAt === undefined) throw new CannotCheck(`GET /settings: ${uc} deleted bez deleted_at`);
    out.set(uc, { status, off, ...(deletedAt === undefined ? {} : { deleted_at: deletedAt }) });
  }
  return out;
}

export interface SettingsComparison {
  readonly source: number;
  readonly katalog: number;
  readonly missing: readonly string[];
  readonly extra: readonly string[];
  readonly mismatched: readonly { readonly uc: string; readonly expected: SettingsEntry; readonly actual: SettingsEntry }[];
}

function same(a: SettingsEntry, b: SettingsEntry): boolean {
  if (a.status !== b.status) return false;
  if (a.status === "deleted") return Date.parse(a.deleted_at ?? "") === Date.parse(b.deleted_at ?? "");
  return a.off.length === b.off.length && a.off.every((k, i) => k === b.off[i]);
}

export function compareSettings(expected: ReadonlyMap<string, SettingsEntry>, actual: ReadonlyMap<string, SettingsEntry>): SettingsComparison {
  const missing: string[] = [];
  const mismatched: { uc: string; expected: SettingsEntry; actual: SettingsEntry }[] = [];
  for (const [uc, e] of [...expected].sort(([a], [b]) => (a < b ? -1 : 1))) {
    const a = actual.get(uc);
    if (a === undefined) missing.push(uc);
    else if (!same(e, a)) mismatched.push({ uc, expected: e, actual: a });
  }
  const extra = [...actual.keys()].filter((uc) => !expected.has(uc)).sort();
  return { source: expected.size, katalog: actual.size, missing, extra, mismatched };
}

// ---- HTTP ------------------------------------------------------------------

async function getJson(f: typeof fetch, url: string, headers: Record<string, string>): Promise<unknown> {
  const what = `GET ${url.replace(/\?.*$/, "")}`;
  let res: Response;
  try {
    res = await f(url, { headers: { accept: "application/json", ...headers } });
  } catch (err) {
    throw new CannotCheck(`${what}: mreža: ${err instanceof Error ? err.message : String(err)}`);
  }
  const text = await res.text().catch(() => "");
  if (!res.ok) throw new CannotCheck(`${what}: HTTP ${res.status} ${text.slice(0, 200)}`.trimEnd());
  try {
    return JSON.parse(text);
  } catch {
    throw new CannotCheck(`${what}: tijelo nije JSON`);
  }
}

const REST_PAGE = 1000;

/** Svi retci javnog pogleda, keyset po UC-u (`youtube_channel_id=gt.`). */
async function fetchView(f: typeof fetch, apiBase: string, key: string, view: string, select: string): Promise<unknown[]> {
  const out: unknown[] = [];
  let after: string | null = null;
  for (;;) {
    const qs = new URLSearchParams({ select, order: "youtube_channel_id.asc", limit: String(REST_PAGE) });
    if (after !== null) qs.set("youtube_channel_id", `gt.${after}`);
    const body = await getJson(f, `${apiBase}/rest/v1/${view}?${qs.toString()}`, {
      apikey: key,
      authorization: `Bearer ${key}`,
      "accept-profile": "domovina_ai",
    });
    if (!Array.isArray(body)) throw new CannotCheck(`${view}: odgovor nije polje`);
    out.push(...(body as unknown[]));
    const last: unknown = body[body.length - 1];
    if (body.length < REST_PAGE || !isObject(last) || typeof last.youtube_channel_id !== "string") return out;
    after = last.youtube_channel_id;
  }
}

// ---- Tok -------------------------------------------------------------------

export interface SettingsDriftDeps {
  /** Katalog, npr. `https://domovina.ai`. */
  readonly katalogBase: string;
  /** domovina-api, npr. `https://api.domovina.ai`. */
  readonly apiBase: string;
  /** Anon ključ domovina-api; `null` = exit 2. */
  readonly anonKey: string | null;
  readonly fetch: typeof fetch;
  /** Slug → UC iz registryja (`registryUcBySlug`), za kanale bez UC-a u katalogu. */
  readonly registryUc: () => Promise<ReadonlyMap<string, string>>;
}

export interface SettingsDriftReport {
  status: "ok" | "drift" | "unknown";
  exitCode: ExitCode;
  settings?: SettingsComparison;
  slugs?: {
    readonly catalog: number;
    readonly missing: readonly string[];
    readonly wrongUc: readonly string[];
  };
  error?: string;
}

export async function runSettingsDrift(deps: SettingsDriftDeps): Promise<SettingsDriftReport> {
  const report: SettingsDriftReport = { status: "unknown", exitCode: EXIT_UNKNOWN };
  try {
    if (deps.anonKey === null || deps.anonKey === "") throw new CannotCheck("nema anon ključa domovina-api (SETTINGS_ANON_KEY)");
    const key = deps.anonKey;
    const api = deps.apiBase.replace(/\/+$/, "");
    const katalog = deps.katalogBase.replace(/\/+$/, "");

    const rawSettings = await fetchView(deps.fetch, api, key, "public_channel_settings", "youtube_channel_id,effective,updated_at,tombstoned");
    const rawTombs = await fetchView(
      deps.fetch,
      api,
      key,
      "public_channel_tombstones",
      "youtube_channel_id,channel_title,slugs,requested_at,phone_confirmed_at,deleted_at",
    );
    let expected: Map<string, SettingsEntry>;
    try {
      expected = expectedSettings(rawSettings, rawTombs);
    } catch (err) {
      if (err instanceof SourceError) throw new CannotCheck(`domovina-api: ${err.message}`);
      throw err;
    }
    const actual = parseKatalogSettings(await getJson(deps.fetch, `${katalog}${KATALOG_PREFIX}/settings`, {}));
    report.settings = compareSettings(expected, actual);

    const channels = await fetchCatalogChannels(deps.fetch, katalog);
    const slugMap = buildSlugMap(channels, await deps.registryUc());
    const diff = diffSlugs(slugMap.map, await fetchChannelSlugs(deps.fetch, api, key));
    report.slugs = {
      catalog: slugMap.map.size,
      missing: diff.insert.map((r) => r.slug),
      wrongUc: diff.update.map((r) => r.slug),
    };

    const s = report.settings;
    const drift =
      s.missing.length + s.extra.length + s.mismatched.length + report.slugs.missing.length + report.slugs.wrongUc.length > 0;
    report.status = drift ? "drift" : "ok";
    report.exitCode = drift ? EXIT_DRIFT : EXIT_OK;
    return report;
  } catch (err) {
    report.status = "unknown";
    report.exitCode = EXIT_UNKNOWN;
    report.error = redactKey(err instanceof Error ? err.message : String(err), deps.anonKey);
    delete report.settings;
    delete report.slugs;
    return report;
  }
}

/**
 * Zajednički exit dvaju dijelova: „ne znam” (2) ima prednost, pa drift (1),
 * pa poravnato (0). Dio koji ne zna se nikad ne prikazuje kao drift ni kao ok.
 */
export function combineExit(a: ExitCode, b: ExitCode): ExitCode {
  if (a === EXIT_UNKNOWN || b === EXIT_UNKNOWN) return EXIT_UNKNOWN;
  if (a === EXIT_DRIFT || b === EXIT_DRIFT) return EXIT_DRIFT;
  return EXIT_OK;
}

const SAMPLE = 10;

export function formatSettingsReport(r: SettingsDriftReport): string[] {
  const lines: string[] = [];
  const line = (k: string, v: string | number): void => {
    lines.push(`  ${k.padEnd(22)} ${v}`);
  };
  const ids = (a: readonly string[]): string =>
    a.length === 0 ? "0" : `${a.length}  ${a.slice(0, SAMPLE).join(" ")}${a.length > SAMPLE ? " …" : ""}`;
  lines.push("postavke kanala  domovina-api ↔ katalog");
  const s = r.settings;
  if (s !== undefined) {
    line("izvor (UC s isklj.)", s.source);
    line("katalog /settings", s.katalog);
    line("postavke missing", ids(s.missing));
    line("postavke extra", ids(s.extra));
    line("postavke različite", ids(s.mismatched.map((m) => m.uc)));
  }
  if (r.slugs !== undefined) {
    line("slugovi s UC-om", r.slugs.catalog);
    line("nema u channel_slugs", ids(r.slugs.missing));
    line("drugi UC u channel_sl.", ids(r.slugs.wrongUc));
  }
  if (r.error !== undefined) line("GREŠKA", r.error);
  const verdict = { ok: "poravnato", drift: "DRIFT (poller/channel-slugs-sync)", unknown: "ne mogu provjeriti" };
  line("ishod postavki", `${verdict[r.status]} (exit ${r.exitCode})`);
  return lines;
}

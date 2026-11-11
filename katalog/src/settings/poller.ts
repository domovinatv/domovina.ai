// Poller postavki kanala: domovina-api (izvor istine) → D1 (projekcija).
// Pokreće ga Cron Trigger svake minute (`scheduled` u `src/index.ts`).
//
// Tok jednog poziva:
//   1. kursor iz `settings_poll_state` (najveći upisani `updated_at`);
//   2. `public_channel_settings?updated_at=gte.<kursor − LOOKBACK>` po stranicama,
//      keyset (`updated_at`, `youtube_channel_id`) unutar poziva;
//   3. za `tombstoned` UC-ove kojih u D1 još nema: `public_channel_tombstones`;
//   4. usporedba s D1 u kodu, pa JEDAN `db.batch` (transakcija): promijenjeni
//      retci postavki, novi tombstonei, stanje pollera i, samo kad se promijenilo
//      nešto što API vidi, novi `ingest_runs` redak (nova verzija kataloga →
//      novi ključevi edge cachea).
//
// Zašto LOOKBACK: `updated_at` u izvoru je `now()` transakcije, tj. trenutak
// POČETKA. Transakcija koja je počela prije, a commitala poslije retka koji je
// već pomaknuo kursor, imala bi `updated_at < kursor` i nikad ne bi bila
// pročitana. Ponovno čitanje zadnjih 5 minuta je idempotentno (nepromijenjen
// redak se ne piše), a stoji jedan mali upit.
//
// Greške: kod u `settings_poll_state.status` (`http_503`, `network`,
// `invalid_response`, `d1_error`), kursor ostaje. Ništa ne izlazi kao iznimka.
// Bez `SETTINGS_ANON_KEY` ili `SETTINGS_API_URL` poller ne zove mrežu i bilježi
// `disabled` (isti obrazac kao `INGEST_TOKEN`, odluka 602 kataloga).
import { parseSettingsRows, parseTombstoneRows, quoted, SourceError, type SettingsRow, type TombstoneRow } from "./source.ts";

/** Redak `settings_poll_state.source` za domovina-api. */
export const POLL_SOURCE = "domovina-api";
/** `ingest_runs.source` kad poller promijeni katalog. */
export const INGEST_SOURCE = "settings-poller";
export const PAGE_SIZE = 500;
/** Ograda po pozivu; ostatak čita sljedeća minuta (kursor je zadnji upisani redak). */
export const MAX_PAGES = 20;
export const LOOKBACK_MS = 5 * 60_000;
/** UC-ova po `in.(…)` filtru tombstonea (duljina URL-a). */
const TOMBSTONE_CHUNK = 50;

export interface PollDeps {
  readonly db: D1Database;
  /** Korijen domovina-api, npr. `https://api.domovina.ai`. */
  readonly apiUrl: string | undefined;
  readonly anonKey: string | undefined;
  readonly fetch: typeof fetch;
  readonly now?: () => Date;
  /** Redak u `settings_poll_state` (testovi koriste svoj). */
  readonly source?: string;
  readonly pageSize?: number;
  readonly maxPages?: number;
  readonly lookbackMs?: number;
}

export interface PollResult {
  /** `ok`, `disabled` ili kod greške (isti kao u `settings_poll_state.status`). */
  readonly status: string;
  readonly cursor: string | null;
  /** Redaka postavki pročitanih iz izvora. */
  readonly fetched: number;
  readonly pages: number;
  /** Redaka postavki upisanih u D1 (efektivno stanje ili `updated_at` različit). */
  readonly settingsWritten: number;
  /** Od toga s promijenjenim efektivnim stanjem (vidi ga API). */
  readonly effectiveChanged: number;
  readonly tombstonesInserted: number;
  /** Nova verzija kataloga (`ingest_runs.id`), `null` kad nije bilo vidljive promjene. */
  readonly catalog: number | null;
  readonly error?: string;
}

class PollError extends Error {
  readonly code: string;
  constructor(code: string, message: string) {
    super(message);
    this.code = code;
  }
}

const UPSERT_SETTINGS = `INSERT INTO channel_settings (youtube_channel_id, effective, source_updated_at, synced_at)
  VALUES (?1, ?2, ?3, ?4)
  ON CONFLICT (youtube_channel_id) DO UPDATE SET
    effective = excluded.effective,
    source_updated_at = excluded.source_updated_at,
    synced_at = excluded.synced_at
  WHERE julianday(excluded.source_updated_at) >= julianday(channel_settings.source_updated_at)
    AND (channel_settings.effective IS NOT excluded.effective
         OR channel_settings.source_updated_at IS NOT excluded.source_updated_at)`;

const INSERT_TOMBSTONE = `INSERT INTO channel_tombstones
  (youtube_channel_id, channel_title, slugs, requested_at, phone_confirmed_at, deleted_at, synced_at)
  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
  ON CONFLICT (youtube_channel_id) DO NOTHING`;

const UPSERT_STATE = `INSERT INTO settings_poll_state (source, cursor, polled_at, status)
  VALUES (?1, ?2, ?3, ?4)
  ON CONFLICT (source) DO UPDATE SET cursor = excluded.cursor, polled_at = excluded.polled_at, status = excluded.status`;

async function readCursor(db: D1Database, source: string): Promise<string | null> {
  const row = await db
    .prepare("SELECT cursor FROM settings_poll_state WHERE source = ?1")
    .bind(source)
    .first<{ cursor: string | null }>();
  return row?.cursor ?? null;
}

async function writeState(db: D1Database, source: string, cursor: string | null, at: string, status: string): Promise<void> {
  await db.prepare(UPSERT_STATE).bind(source, cursor, at, status).run();
}

function restUrl(apiUrl: string, view: string, params: URLSearchParams): string {
  return `${apiUrl.replace(/\/+$/, "")}/rest/v1/${view}?${params.toString()}`;
}

async function getJson(deps: PollDeps, anonKey: string, url: string): Promise<unknown> {
  let res: Response;
  try {
    res = await deps.fetch(url, {
      headers: {
        apikey: anonKey,
        authorization: `Bearer ${anonKey}`,
        "accept-profile": "domovina_ai",
        accept: "application/json",
      },
    });
  } catch (err) {
    throw new PollError("network", err instanceof Error ? err.message : String(err));
  }
  if (!res.ok) {
    // Tijelo se pročita da se veza oslobodi; u poruku ide samo početak.
    const body = await res.text().catch(() => "");
    throw new PollError(`http_${res.status}`, body.slice(0, 200));
  }
  try {
    return await res.json();
  } catch {
    throw new PollError("invalid_response", "tijelo nije JSON");
  }
}

function parsed<T>(f: () => T): T {
  try {
    return f();
  } catch (err) {
    if (err instanceof SourceError) throw new PollError("invalid_response", err.message);
    throw err;
  }
}

/** Sve promijenjene postavke od `since`, keyset po (`updated_at`, UC). */
async function fetchSettings(
  deps: PollDeps,
  anonKey: string,
  apiUrl: string,
  since: string | null,
): Promise<{ rows: SettingsRow[]; pages: number }> {
  const pageSize = deps.pageSize ?? PAGE_SIZE;
  const maxPages = deps.maxPages ?? MAX_PAGES;
  const rows: SettingsRow[] = [];
  let pages = 0;
  let after: SettingsRow | undefined;
  while (pages < maxPages) {
    const params = new URLSearchParams({
      select: "youtube_channel_id,effective,updated_at,tombstoned",
      order: "updated_at.asc,youtube_channel_id.asc",
      limit: String(pageSize),
    });
    if (since !== null) params.set("updated_at", `gte.${since}`);
    if (after !== undefined) {
      const t = quoted(after.updatedAt);
      params.set("or", `(updated_at.gt.${t},and(updated_at.eq.${t},youtube_channel_id.gt.${after.youtubeChannelId}))`);
    }
    const raw = await getJson(deps, anonKey, restUrl(apiUrl, "public_channel_settings", params));
    const batch = parsed(() => parseSettingsRows(raw));
    pages += 1;
    rows.push(...batch);
    if (batch.length < pageSize) break;
    after = batch[batch.length - 1];
  }
  return { rows, pages };
}

async function fetchTombstones(deps: PollDeps, anonKey: string, apiUrl: string, ucs: readonly string[]): Promise<TombstoneRow[]> {
  const out: TombstoneRow[] = [];
  for (let i = 0; i < ucs.length; i += TOMBSTONE_CHUNK) {
    const chunk = ucs.slice(i, i + TOMBSTONE_CHUNK);
    const params = new URLSearchParams({
      select: "youtube_channel_id,channel_title,slugs,requested_at,phone_confirmed_at,deleted_at",
      youtube_channel_id: `in.(${chunk.join(",")})`,
    });
    const raw = await getJson(deps, anonKey, restUrl(apiUrl, "public_channel_tombstones", params));
    out.push(...parsed(() => parseTombstoneRows(raw)));
  }
  return out;
}

/** Zadnji redak po UC-u (stranice su poredane po vremenu, pa zadnji = najnoviji). */
function latestByUc(rows: readonly SettingsRow[]): Map<string, SettingsRow> {
  const out = new Map<string, SettingsRow>();
  for (const r of rows) out.set(r.youtubeChannelId, r);
  return out;
}

function minus(instant: string, ms: number): string {
  return new Date(Date.parse(instant) - ms).toISOString();
}

export async function pollSettings(deps: PollDeps): Promise<PollResult> {
  const now = deps.now ?? (() => new Date());
  const source = deps.source ?? POLL_SOURCE;
  const startedAt = now().toISOString();
  const empty = { fetched: 0, pages: 0, settingsWritten: 0, effectiveChanged: 0, tombstonesInserted: 0, catalog: null };

  let cursor: string | null = null;
  try {
    cursor = await readCursor(deps.db, source);
    const { apiUrl, anonKey } = deps;
    if (apiUrl === undefined || apiUrl === "" || anonKey === undefined || anonKey === "") {
      await writeState(deps.db, source, cursor, startedAt, "disabled");
      return { status: "disabled", cursor, ...empty };
    }

    const since = cursor === null ? null : minus(cursor, deps.lookbackMs ?? LOOKBACK_MS);
    const { rows, pages } = await fetchSettings(deps, anonKey, apiUrl, since);
    const last = rows[rows.length - 1];
    // Kursor ne ide unatrag (LOOKBACK vraća i retke prije kursora).
    const nextCursor =
      last === undefined || (cursor !== null && Date.parse(last.updatedAt) < Date.parse(cursor)) ? cursor : last.updatedAt;
    const latest = [...latestByUc(rows).values()];
    const ucs = latest.map((r) => r.youtubeChannelId);

    // Što D1 već ima (jedan upit po tablici, UC-ovi kao JSON polje).
    const ucJson = JSON.stringify(ucs);
    const existing = new Map<string, { effective: string; source_updated_at: string }>();
    const knownTombstones = new Set<string>();
    if (ucs.length > 0) {
      const [settings, tombs] = await deps.db.batch<Record<string, string>>([
        deps.db
          .prepare(
            `SELECT youtube_channel_id, effective, source_updated_at FROM channel_settings
             WHERE youtube_channel_id IN (SELECT value FROM json_each(?1))`,
          )
          .bind(ucJson),
        deps.db
          .prepare("SELECT youtube_channel_id FROM channel_tombstones WHERE youtube_channel_id IN (SELECT value FROM json_each(?1))")
          .bind(ucJson),
      ]);
      for (const r of settings?.results ?? []) {
        const uc = r.youtube_channel_id;
        const effective = r.effective;
        const at = r.source_updated_at;
        if (uc !== undefined && effective !== undefined && at !== undefined) existing.set(uc, { effective, source_updated_at: at });
      }
      for (const r of tombs?.results ?? []) if (r.youtube_channel_id !== undefined) knownTombstones.add(r.youtube_channel_id);
    }

    const toWrite: SettingsRow[] = [];
    let effectiveChanged = 0;
    for (const r of latest) {
      const old = existing.get(r.youtubeChannelId);
      if (old === undefined) {
        toWrite.push(r);
        effectiveChanged += 1;
        continue;
      }
      // Stariji od onoga što D1 ima: preskače se (isto pravilo je i u WHERE upserta).
      if (Date.parse(r.updatedAt) < Date.parse(old.source_updated_at)) continue;
      if (old.effective !== r.effective) {
        toWrite.push(r);
        effectiveChanged += 1;
      } else if (old.source_updated_at !== r.updatedAt) {
        toWrite.push(r);
      }
    }

    const newTombUcs = latest.filter((r) => r.tombstoned && !knownTombstones.has(r.youtubeChannelId)).map((r) => r.youtubeChannelId);
    const tombstones = newTombUcs.length === 0 ? [] : await fetchTombstones(deps, anonKey, apiUrl, newTombUcs);
    const gotTombs = new Set(tombstones.map((t) => t.youtubeChannelId));
    const lost = newTombUcs.filter((uc) => !gotTombs.has(uc));
    if (lost.length > 0) throw new PollError("invalid_response", `tombstoned bez tombstonea: ${lost.join(",")}`);

    const syncedAt = now().toISOString();
    const db = deps.db;
    const stmts: D1PreparedStatement[] = [
      ...toWrite.map((r) => db.prepare(UPSERT_SETTINGS).bind(r.youtubeChannelId, r.effective, r.updatedAt, syncedAt)),
      ...tombstones.map((t) =>
        db
          .prepare(INSERT_TOMBSTONE)
          .bind(t.youtubeChannelId, t.channelTitle, t.slugs, t.requestedAt, t.phoneConfirmedAt, t.deletedAt, syncedAt),
      ),
      db.prepare(UPSERT_STATE).bind(source, nextCursor, syncedAt, "ok"),
    ];
    const visible = effectiveChanged + tombstones.length > 0;
    if (visible) {
      const counts = { settings: toWrite.length, effective_changed: effectiveChanged, tombstones: tombstones.length };
      stmts.push(
        db
          .prepare(
            `INSERT INTO ingest_runs (started_at, finished_at, source, counts, status)
             VALUES (?1, ?2, ?3, ?4, 'ok') RETURNING id`,
          )
          .bind(startedAt, syncedAt, INGEST_SOURCE, JSON.stringify(counts)),
      );
    }
    let results: D1Result<{ id?: number }>[];
    try {
      results = await db.batch<{ id?: number }>(stmts);
    } catch (err) {
      throw new PollError("d1_error", err instanceof Error ? err.message : String(err));
    }
    const catalog = visible ? (results[results.length - 1]?.results[0]?.id ?? null) : null;
    return {
      status: "ok",
      cursor: nextCursor,
      fetched: rows.length,
      pages,
      settingsWritten: toWrite.length,
      effectiveChanged,
      tombstonesInserted: tombstones.length,
      catalog,
    };
  } catch (err) {
    const code = err instanceof PollError ? err.code : "internal";
    const message = err instanceof Error ? err.message : String(err);
    try {
      await writeState(deps.db, source, cursor, now().toISOString(), code);
    } catch (stateErr) {
      console.error("settings poller: stanje se ne može upisati", stateErr);
    }
    console.error(`settings poller: ${code}: ${message}`);
    return { status: code, cursor, ...empty, error: message };
  }
}

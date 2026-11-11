// Točni dani objave iz fetch repoa: `automatic/watchlist/backfill.json`
// (`automatic/backfill_days.js`, YouTube Data API `publishedAt` → dan u
// Europe/Zagreb). Isti izvor koristi podcast.domovina.ai/dani/, pa katalog po
// njemu dijeli epizode na dane kao i ta stranica (odluka 1200).
//
// Datoteka je tuđa i raste svaku noć: neispravan zapis se PRESKAČE (epizoda
// zadrži datum iz `info.json`/listinga), ne ruši uvoz.
import { asObject, type JsonObject, ROOT } from "./read.ts";

const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

function isRealIsoDate(v: string): boolean {
  if (!ISO_DATE.test(v)) return false;
  const d = new Date(`${v}T00:00:00Z`);
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === v;
}

function objectOrNull(v: unknown): JsonObject | null {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as JsonObject) : null;
}

/**
 * Zapisi `{date, published_at, …}` po ID-u iz `channels.<slug>.extras` pa
 * `channels.<slug>.originals` (original pobjeđuje isti ID). `extras` su Tier 1
 * epizode koje backfill ne broji kao „pune originale" (kraće od praga kanala,
 * video s tuđeg kanala), a fetch ih od 11. 11. 2026. nadopunjuje po ID-u
 * (`backfill_days.js` `fillExtras`). Neispravan kanal ili zapis se preskače.
 */
function backfillRecords(raw: unknown): Array<readonly [string, JsonObject]> {
  const root = asObject(raw, ROOT);
  const out: Array<readonly [string, JsonObject]> = [];
  const channels = objectOrNull(root.channels);
  if (channels === null) return out;
  for (const key of ["extras", "originals"] as const) {
    for (const ch of Object.values(channels)) {
      const records = objectOrNull(objectOrNull(ch)?.[key]);
      if (records === null) continue;
      for (const [id, o] of Object.entries(records)) {
        const rec = objectOrNull(o);
        if (rec !== null) out.push([id, rec]);
      }
    }
  }
  return out;
}

/** `channels.<slug>.{extras,originals}.<id>.date` → mapa ID → `YYYY-MM-DD`. */
export function parsePublishDates(raw: unknown): ReadonlyMap<string, string> {
  const out = new Map<string, string>();
  for (const [id, o] of backfillRecords(raw)) {
    const date = o.date;
    if (typeof date === "string" && isRealIsoDate(date)) out.set(id, date);
  }
  return out;
}

const ISO_INSTANT = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/;

/** Trenutak u obliku koji traži CHECK u 0004: `YYYY-MM-DDTHH:MM:SSZ`, bez milisekundi. */
export function isoInstant(ms: number): string {
  return new Date(Math.floor(ms / 1000) * 1000).toISOString().replace(".000Z", "Z");
}

/**
 * `channels.<slug>.{extras,originals}.<id>.published_at` → mapa ID → `YYYY-MM-DDTHH:MM:SSZ`
 * (odluka 1205). Isti izvor kao [parsePublishDates]; neispravan zapis se preskače.
 */
export function parsePublishTimes(raw: unknown): ReadonlyMap<string, string> {
  const out = new Map<string, string>();
  for (const [id, o] of backfillRecords(raw)) {
    const at = o.published_at;
    if (typeof at !== "string" || !ISO_INSTANT.test(at)) continue;
    const ms = Date.parse(at);
    if (Number.isFinite(ms) && isRealIsoDate(at.slice(0, 10))) out.set(id, isoInstant(ms));
  }
  return out;
}

const ZAGREB_DAY = new Intl.DateTimeFormat("en-CA", {
  timeZone: "Europe/Zagreb",
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
});

/** Unix sekunde → dan u Europe/Zagreb (`YYYY-MM-DD`). */
export function zagrebDay(unixSeconds: number): string {
  return ZAGREB_DAY.format(new Date(unixSeconds * 1000));
}

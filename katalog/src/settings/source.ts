// Čitanje izvora postavki: javni pogledi domovina-api preko PostgRESTa
// (`/rest/v1/…`, shema `domovina_ai` kroz `Accept-Profile`, anon ključ).
// Ovdje su samo parsiranje i validacija; mreža ide kroz predani `fetch`
// (poller), pa se sve testira bez mreže.
//
// Validacija je stroga i SVE-ILI-NIŠTA: jedan nevaljan redak odbija cijeli
// odgovor (`invalid_response`), kursor ostaje gdje je bio i ništa se ne upiše.
// Djelomičan upis bi pomaknuo kursor preko retka koji nikad nije upisan.
import { SETTING_KEYS, UC_PATTERN } from "./keys.ts";

/** Redak `domovina_ai.public_channel_settings` (bez rijetkog `settings`, koji se ne preslikava). */
export interface SettingsRow {
  readonly youtubeChannelId: string;
  /** Kanonski JSON: svih 20 ključeva (nedostaje = `true`) + nepoznati, ključevi poredani. */
  readonly effective: string;
  /** `updated_at` doslovno kako ga je izvor poslao (kursor ide natrag u izvor). */
  readonly updatedAt: string;
  readonly tombstoned: boolean;
}

/** Redak `domovina_ai.public_channel_tombstones`. */
export interface TombstoneRow {
  readonly youtubeChannelId: string;
  readonly channelTitle: string | null;
  /** JSON polje slugova. */
  readonly slugs: string;
  readonly requestedAt: string | null;
  readonly phoneConfirmedAt: string | null;
  readonly deletedAt: string;
}

export class SourceError extends Error {
  override readonly name = "SourceError";
}

const isObject = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);

function reqUc(o: Record<string, unknown>, at: string): string {
  const v = o.youtube_channel_id;
  if (typeof v !== "string" || !UC_PATTERN.test(v)) throw new SourceError(`${at}.youtube_channel_id nije UC id`);
  return v;
}

function reqInstant(o: Record<string, unknown>, key: string, at: string): string {
  const v = o[key];
  if (typeof v !== "string" || Number.isNaN(Date.parse(v))) throw new SourceError(`${at}.${key} nije vrijeme`);
  return v;
}

function optInstant(o: Record<string, unknown>, key: string, at: string): string | null {
  return o[key] === null || o[key] === undefined ? null : reqInstant(o, key, at);
}

/**
 * `effective` → kanonski JSON. Vrijednosti moraju biti boolean; ključ iz
 * `SETTING_KEYS` koji nedostaje je `true`; nepoznati ključ se čuva.
 */
export function canonicalEffective(raw: unknown, at = "effective"): string {
  if (!isObject(raw)) throw new SourceError(`${at} nije objekt`);
  const out: Record<string, boolean> = {};
  for (const k of SETTING_KEYS) out[k] = true;
  for (const [k, v] of Object.entries(raw)) {
    if (typeof v !== "boolean") throw new SourceError(`${at}.${k} nije boolean`);
    out[k] = v;
  }
  const sorted: Record<string, boolean> = {};
  for (const k of Object.keys(out).sort()) sorted[k] = out[k] ?? true;
  return JSON.stringify(sorted);
}

export function parseSettingsRows(raw: unknown): SettingsRow[] {
  if (!Array.isArray(raw)) throw new SourceError("public_channel_settings: odgovor nije polje");
  return raw.map((value: unknown, i): SettingsRow => {
    const at = `public_channel_settings[${i}]`;
    if (!isObject(value)) throw new SourceError(`${at} nije objekt`);
    if (typeof value.tombstoned !== "boolean") throw new SourceError(`${at}.tombstoned nije boolean`);
    return {
      youtubeChannelId: reqUc(value, at),
      effective: canonicalEffective(value.effective, `${at}.effective`),
      updatedAt: reqInstant(value, "updated_at", at),
      tombstoned: value.tombstoned,
    };
  });
}

export function parseTombstoneRows(raw: unknown): TombstoneRow[] {
  if (!Array.isArray(raw)) throw new SourceError("public_channel_tombstones: odgovor nije polje");
  return raw.map((value: unknown, i): TombstoneRow => {
    const at = `public_channel_tombstones[${i}]`;
    if (!isObject(value)) throw new SourceError(`${at} nije objekt`);
    const title = value.channel_title;
    if (title !== null && title !== undefined && typeof title !== "string") {
      throw new SourceError(`${at}.channel_title nije tekst`);
    }
    const slugs = value.slugs;
    if (!Array.isArray(slugs) || !slugs.every((s): s is string => typeof s === "string" && s.length > 0)) {
      throw new SourceError(`${at}.slugs nije polje slugova`);
    }
    return {
      youtubeChannelId: reqUc(value, at),
      channelTitle: typeof title === "string" && title.length > 0 ? title : null,
      slugs: JSON.stringify(slugs),
      requestedAt: optInstant(value, "requested_at", at),
      phoneConfirmedAt: optInstant(value, "phone_confirmed_at", at),
      deletedAt: reqInstant(value, "deleted_at", at),
    };
  });
}

/** PostgREST vrijednost u `or=(…)` filtru: navodnici, jer vrijeme sadrži `:` `.` `+`. */
export function quoted(value: string): string {
  return `"${value.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

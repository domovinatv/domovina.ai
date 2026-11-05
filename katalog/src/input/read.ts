// Čitači polja za parsere ulaza. Pravila (odluke 118–121):
// - polje koje nedostaje ili je `null` → `null` (opcionalni čitači) ili
//   InputError (obavezni); nikad izmišljena zamjenska vrijednost;
// - pogrešan tip je greška, ne tiha pretvorba (`"511"` nije broj);
// - prazan string je greška i u opcionalnom polju: D1 ga ionako odbija
//   (`CHECK length(x) > 0`), a ovdje greška nosi putanju.
import { InputError } from "./errors.ts";

export type JsonObject = Readonly<Record<string, unknown>>;

export const ROOT = "$";

export function at(path: string, key: string): string {
  return path === ROOT ? key : `${path}.${key}`;
}

export function index(path: string, i: number): string {
  return `${path === ROOT ? "" : path}[${i}]`;
}

function describe(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "niz";
  return typeof value;
}

export function asObject(value: unknown, path: string): JsonObject {
  if (typeof value !== "object" || value === null || Array.isArray(value)) {
    throw new InputError(path, `očekivan objekt, stiglo ${describe(value)}`);
  }
  return value as JsonObject;
}

export function asArray(value: unknown, path: string): readonly unknown[] {
  if (!Array.isArray(value)) {
    throw new InputError(path, `očekivan niz, stiglo ${describe(value)}`);
  }
  return value;
}

/** `null` kad polje nedostaje ili je `null`. */
function present(o: JsonObject, key: string): unknown {
  const v = o[key];
  return v === undefined ? null : v;
}

function missing(path: string): InputError {
  return new InputError(path, "obavezno polje nedostaje ili je null");
}

function checkString(v: unknown, path: string): string {
  if (typeof v !== "string") throw new InputError(path, `očekivan string, stiglo ${describe(v)}`);
  if (v.length === 0) throw new InputError(path, "prazan string");
  return v;
}

export function optString(o: JsonObject, key: string, path: string): string | null {
  const v = present(o, key);
  return v === null ? null : checkString(v, at(path, key));
}

export function reqString(o: JsonObject, key: string, path: string): string {
  const v = optString(o, key, path);
  if (v === null) throw missing(at(path, key));
  return v;
}

export function optObject(o: JsonObject, key: string, path: string): JsonObject | null {
  const v = present(o, key);
  return v === null ? null : asObject(v, at(path, key));
}

export function reqArray(o: JsonObject, key: string, path: string): readonly unknown[] {
  const v = present(o, key);
  if (v === null) throw missing(at(path, key));
  return asArray(v, at(path, key));
}

export function optBoolean(o: JsonObject, key: string, path: string): boolean | null {
  const v = present(o, key);
  if (v === null) return null;
  if (typeof v !== "boolean") {
    throw new InputError(at(path, key), `očekivan boolean, stiglo ${describe(v)}`);
  }
  return v;
}

export function reqBoolean(o: JsonObject, key: string, path: string): boolean {
  const v = optBoolean(o, key, path);
  if (v === null) throw missing(at(path, key));
  return v;
}

function checkNumber(v: unknown, path: string): number {
  if (typeof v !== "number" || !Number.isFinite(v)) {
    throw new InputError(path, `očekivan broj, stiglo ${describe(v)}`);
  }
  return v;
}

/** Konačan broj ≥ 0 (trajanje: cijeli ili decimalni, `CUJmOc91C64` ima 245.295). */
export function optNonNegative(o: JsonObject, key: string, path: string): number | null {
  const v = present(o, key);
  if (v === null) return null;
  const n = checkNumber(v, at(path, key));
  if (n < 0) throw new InputError(at(path, key), `negativan broj ${n}`);
  return n;
}

export function optInteger(o: JsonObject, key: string, path: string): number | null {
  const v = present(o, key);
  if (v === null) return null;
  const n = checkNumber(v, at(path, key));
  if (!Number.isInteger(n)) throw new InputError(at(path, key), `očekivan cijeli broj, stiglo ${n}`);
  return n;
}

export function optCount(o: JsonObject, key: string, path: string): number | null {
  const n = optInteger(o, key, path);
  if (n !== null && n < 0) throw new InputError(at(path, key), `negativan broj ${n}`);
  return n;
}

/** Magisterium ocjena: cijeli broj 0–100. Decimalna se odbija, ne zaokružuje (odluka 107). */
export function optScore(o: JsonObject, key: string, path: string): number | null {
  const n = optInteger(o, key, path);
  if (n !== null && (n < 0 || n > 100)) {
    throw new InputError(at(path, key), `ocjena izvan 0–100: ${n}`);
  }
  return n;
}

function isRealDate(y: number, m: number, d: number): boolean {
  const t = new Date(0);
  t.setUTCFullYear(y, m - 1, d);
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;
const COMPACT_DATE = /^(\d{4})(\d{2})(\d{2})$/;

function checkDate(v: string, re: RegExp, path: string): string {
  const m = re.exec(v);
  if (m === null) throw new InputError(path, `datum nije u obliku ${re === ISO_DATE ? "YYYY-MM-DD" : "YYYYMMDD"}: ${v}`);
  const [y, mo, d] = [Number(m[1]), Number(m[2]), Number(m[3])];
  if (!isRealDate(y, mo, d)) throw new InputError(path, `nepostojeći datum: ${v}`);
  return `${m[1] ?? ""}-${m[2] ?? ""}-${m[3] ?? ""}`;
}

/** `YYYY-MM-DD`, provjeren kao stvaran dan (isto što D1 `date(x) = x`). */
export function optIsoDate(o: JsonObject, key: string, path: string): string | null {
  const v = optString(o, key, path);
  return v === null ? null : checkDate(v, ISO_DATE, at(path, key));
}

/** yt-dlp `upload_date` (`YYYYMMDD`) → `YYYY-MM-DD`. */
export function optCompactDate(o: JsonObject, key: string, path: string): string | null {
  const v = optString(o, key, path);
  return v === null ? null : checkDate(v, COMPACT_DATE, at(path, key));
}

const ISO_TIMESTAMP = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

/** ISO 8601 vrijeme s vremenskom zonom (`generated_at`). */
export function optTimestamp(o: JsonObject, key: string, path: string): string | null {
  const v = optString(o, key, path);
  if (v === null) return null;
  if (!ISO_TIMESTAMP.test(v) || !Number.isFinite(Date.parse(v))) {
    throw new InputError(at(path, key), `nije ISO 8601 vrijeme: ${v}`);
  }
  return v;
}

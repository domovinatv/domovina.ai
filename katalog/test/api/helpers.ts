// Pomoćne funkcije ugovornih testova API-ja v1 (odluke 300–3xx).
//
// Storage nije izoliran po testu (S1/S2): svaki `describe` ima svoj brend i
// host, a `ingest_runs` je zajednički (verzija kataloga je globalna u bazi, kao
// u produkciji gdje je jedna baza po brendu, odluka 4).
import { Validator, type Schema } from "@cfworker/json-schema";
import { env, exports } from "cloudflare:workers";
import { expect } from "vitest";
import { forgetCatalogContexts } from "../../src/api/context.ts";
import { buildPlan, type Brand, type ImportPlan } from "../../src/ingest/plan.ts";
import { applyPlan, finishRun, startRun } from "../../src/ingest/write.ts";
import { fixturePlanInput } from "../ingest/input.ts";

const SCHEMA_DIR = "../../contract/v1/";
const schemas = import.meta.glob<Schema>("../../contract/v1/*.schema.json", { eager: true, import: "default" });

export type Contract =
  | "days"
  | "channels"
  | "directory"
  | "channel-episodes"
  | "channel-response"
  | "card-response"
  | "settings"
  | "ingest-response"
  | "ingest-ids"
  | "error";

const validators = new Map<string, Validator>();

function validator(name: string): Validator {
  const cached = validators.get(name);
  if (cached !== undefined) return cached;
  const schema = schemas[`${SCHEMA_DIR}${name}.schema.json`];
  if (schema === undefined) throw new Error(`nema sheme ${name}`);
  // shortCircuit = false: greška nabroji sva prekršena pravila, ne samo prvo.
  const v = new Validator(schema, "2020-12", false);
  for (const [path, other] of Object.entries(schemas)) {
    if (path !== `${SCHEMA_DIR}${name}.schema.json`) v.addSchema(other);
  }
  validators.set(name, v);
  return v;
}

/** Baci s popisom grešaka ako `body` ne odgovara shemi. */
export function assertContract(name: Contract, body: unknown): void {
  const r = validator(name).validate(body);
  if (!r.valid) {
    const detail = r.errors.map((e) => `${e.instanceLocation} ${e.keyword}: ${e.error}`).join("\n");
    throw new Error(`odgovor ne odgovara shemi ${name}:\n${detail}\n${JSON.stringify(body)}`);
  }
}

export const NOW = "2026-11-05T10:00:00.000Z";
export const plan: ImportPlan = buildPlan(fixturePlanInput());

/** Brend za `describe` blok: id i host (host zahtjeva = `brands.host`). */
export function brand(id: string): Brand {
  return { id, host: `${id}.test` };
}

/** Upiše fixture plan u brend i doda uspješan `ingest_runs` redak; vraća njegov id. */
export async function seed(b: Brand): Promise<number> {
  await applyPlan(env.DB, b, plan, NOW);
  return okRun();
}

/**
 * Novi uspješan uvoz = nova verzija kataloga. Zaboravlja i kontekst u memoriji
 * izolata (odluka 600): u produkciji se nova verzija vidi do 30 s kasnije, a test
 * je hoće odmah.
 */
export async function okRun(): Promise<number> {
  const id = await startRun(env.DB, "test", NOW);
  await finishRun(env.DB, id, "ok", NOW, {});
  forgetCatalogContexts();
  return id;
}

export interface ApiResult<T> {
  readonly res: Response;
  readonly body: T;
}

export interface ListBody<T> {
  readonly version: string;
  readonly catalog: string | null;
  readonly items: T[];
  readonly next: string | null;
  readonly meta: { readonly rows_read: number };
}

export interface ItemBody<T> {
  readonly version: string;
  readonly catalog: string | null;
  readonly item: T;
  readonly meta: { readonly rows_read: number };
}

export interface ErrorBody {
  readonly ok: false;
  readonly error: string;
  readonly detail?: string;
}

export interface Card {
  readonly id: string;
  readonly title: string;
  readonly title_hr: string | null;
  readonly date: string | null;
  readonly duration_seconds: number | null;
  readonly magisterium_score: number | null;
  readonly p: number;
  readonly tier: number;
  readonly lang: string | null;
  readonly variant_of: string | null;
  readonly channel: { readonly slug: string; readonly name: string; readonly tier: number } | null;
}

export interface Channel {
  readonly slug: string;
  readonly name: string;
  readonly tier: number;
  readonly lang: string | null;
  readonly avatar: string | null;
  readonly youtube_channel_id: string | null;
  readonly processed_count: number;
  readonly latest_published_date: string | null;
  readonly unregistered: boolean;
}

/**
 * GET na API; SVAKI odgovor se validira shemom: 2xx shemom rute, 4xx shemom
 * greške. Vraća odgovor i parsirano tijelo.
 */
export async function api<T>(host: string, path: string, contract: Contract): Promise<ApiResult<T>> {
  const res = await exports.default.fetch(`https://${host}/api/katalog/v1/${path}`);
  expect(res.headers.get("content-type")).toBe("application/json; charset=utf-8");
  const body: unknown = await res.json();
  if (res.status >= 200 && res.status < 300) assertContract(contract, body);
  else if (res.status >= 400 && res.status < 500) assertContract("error", body);
  else throw new Error(`neočekivan status ${res.status}: ${JSON.stringify(body)}`);
  return { res, body: body as T };
}

/** Isto, ali očekuje 4xx s danim kodom; provjerava i `no-store`. */
export async function apiError(host: string, path: string, status: 400 | 404, error: string): Promise<void> {
  const { res, body } = await api<ErrorBody>(host, path, "error");
  expect(res.status, path).toBe(status);
  expect(body, path).toEqual({ ok: false, error });
  expect(res.headers.get("cache-control"), path).toBe("no-store");
  expect(res.headers.get("x-katalog-cache"), path).toBeNull();
}

/** Prolista popis do kraja (`next` do `null`); vraća sve stavke i sve stranice. */
export async function collect<T>(
  host: string,
  path: string,
  contract: Contract,
  limit: number,
): Promise<{ items: T[]; pages: ListBody<T>[] }> {
  const pages: ListBody<T>[] = [];
  let cursor: string | null = null;
  const sep = path.includes("?") ? "&" : "?";
  for (let i = 0; i < 1000; i++) {
    const q: string = cursor === null ? "" : `&cursor=${cursor}`;
    const { res, body } = await api<ListBody<T>>(host, `${path}${sep}limit=${limit}${q}`, contract);
    expect(res.status).toBe(200);
    pages.push(body);
    if (body.next === null) return { items: pages.flatMap((p) => p.items), pages };
    expect(body.items).toHaveLength(limit);
    cursor = body.next;
  }
  throw new Error("popis nema kraja");
}

/** Konstanta: upit brenda i verzije (≤ 3) + zaglavlje kanala uz njegove epizode (1) + kraj raspona (1). */
export const ROWS_READ_CONSTANT = 5;

/**
 * `meta.rows_read` jednog zahtjeva, uz provjeru da je bio cache miss (inače bi
 * se mjerio upit verzije, ne ruta).
 */
export async function measure(host: string, path: string, contract: Contract): Promise<number> {
  const { res, body } = await api<{ meta: { rows_read: number } }>(host, path, contract);
  expect(res.status, path).toBe(200);
  expect(res.headers.get("x-katalog-cache"), path).toBe("miss");
  return body.meta.rows_read;
}

// Lokalni PostgREST-shim (S6, odluka 604): isti protokol kao Supabase
// PostgREST (`/rest/v1/<relacija>?…`, `/rest/v1/rpc/<fn>`, `apikey`,
// `Authorization: Bearer <jwt>`, `Accept-Profile`/`Content-Profile: vijesti`),
// nad PGliteom, ali SAMO podskup koji portal koristi. Svaki zahtjev ide kroz
// `asUser` (uloga i claims iz JWT-a, `anon` bez tokena), pa RLS i prava rade
// isto kao na produkciji. Shim NE provjerava potpis JWT-a: zato je lokalan i
// jedini prihvaća lažnu prijavu (odluka 606). Služi i lažni CDN nad fixtureima.
import { createServer, type IncomingMessage, type Server } from 'node:http';
import type { PGlite } from '@electric-sql/pglite';
import { asUser } from '../../db/editorial.js';
import type { SqlDb } from '../../db/sql.js';
import { createFakeCdn } from '../../engine/test/fake-cdn.js';
import { LOCAL_ANON_KEY } from './ids.js';

export interface ShimRequest {
  method: string;
  /** Putanja s upitom, npr. `/rest/v1/articles?select=id`. */
  url: string;
  headers: Record<string, string | undefined>;
  body?: string;
}

export interface ShimResponse {
  status: number;
  headers: Record<string, string>;
  body: string | Uint8Array;
}

/** Relacije koje portal čita (javne stranice i admin). Ostalo je 404 kao nepoznata tablica. */
export const SHIM_RELATIONS = [
  'articles',
  'public_article_versions',
  'public_moments',
  'public_corrections',
  'public_stories',
  'editor_article_versions',
  'sentence_resolutions',
  'article_events',
  'allowed_channels',
  'staff',
] as const;

type ArgType = 'bigint' | 'integer' | 'text' | 'jsonb' | 'uuid';

/** Funkcije koje admin zove, s imenima i tipovima argumenata (migracija 006). */
export const SHIM_RPC: Record<string, Record<string, ArgType>> = {
  transition_article: { p_article_id: 'bigint', p_to: 'text', p_note: 'text' },
  approve_article: { p_article_id: 'bigint', p_version_id: 'bigint', p_note: 'text' },
  publish_article: { p_article_id: 'bigint', p_note: 'text' },
  save_editor_version: {
    p_article_id: 'bigint',
    p_base_version_id: 'bigint',
    p_title: 'text',
    p_lead: 'text',
    p_category: 'text',
    p_blocks: 'jsonb',
  },
  resolve_sentence: { p_version_id: 'bigint', p_n: 'integer', p_resolution: 'text', p_note: 'text' },
  correct_article: { p_article_id: 'bigint', p_version_id: 'bigint', p_kind: 'text', p_description: 'text' },
  retract_article: { p_article_id: 'bigint', p_reason: 'text' },
};

const IDENT = /^[a-z_][a-z0-9_]*$/;
const OPS: Record<string, string> = { eq: '=', neq: '<>', gt: '>', gte: '>=', lt: '<', lte: '<=' };
const RESERVED = new Set(['select', 'order', 'limit', 'offset']);
const ORDER_MODS = new Set(['asc', 'desc', 'nullsfirst', 'nullslast']);

/** Tišina u MP3 okviru: dovoljno da `<audio>` ima izvor, a e2e ne ide na mrežu. */
const SILENT_MP3 = (() => {
  const frame = new Uint8Array(417);
  frame.set([0xff, 0xfb, 0x90, 0x64]);
  const out = new Uint8Array(frame.length * 40);
  for (let i = 0; i < 40; i++) out.set(frame, i * frame.length);
  return out;
})();

const CORS: Record<string, string> = {
  'access-control-allow-origin': '*',
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers':
    'apikey, authorization, content-type, accept, accept-profile, content-profile, prefer, x-client-info',
};

class ShimError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function json(status: number, body: unknown, extra: Record<string, string> = {}): ShimResponse {
  return {
    status,
    headers: { ...CORS, 'content-type': 'application/json; charset=utf-8', ...extra },
    body: JSON.stringify(body, (_k, v: unknown) => (typeof v === 'bigint' ? Number(v) : v)),
  };
}

function pgrstError(status: number, code: string, message: string): ShimResponse {
  return json(status, { code, message, details: null, hint: null });
}

/** Payload JWT-a bez provjere potpisa (lokalno!). Nevaljan token je greška kao u PostgREST-u. */
export function decodeJwtPayload(token: string): Record<string, unknown> {
  const parts = token.split('.');
  if (parts.length !== 3) throw new ShimError(401, 'PGRST301', 'JWT nije valjan (očekivana tri dijela)');
  try {
    const payload: unknown = JSON.parse(Buffer.from(parts[1] ?? '', 'base64url').toString('utf8'));
    if (typeof payload !== 'object' || payload === null) throw new Error('payload');
    return payload as Record<string, unknown>;
  } catch {
    throw new ShimError(401, 'PGRST301', 'JWT nije valjan');
  }
}

/** Korisnik zahtjeva: `null` = `anon`. */
export function requestUser(headers: ShimRequest['headers'], now = Date.now()): string | null {
  if (headers.apikey !== LOCAL_ANON_KEY) throw new ShimError(401, 'PGRST000', 'nedostaje ili nije valjan apikey');
  const auth = headers.authorization;
  if (!auth) return null;
  const m = /^Bearer (.+)$/i.exec(auth);
  if (!m) throw new ShimError(401, 'PGRST301', 'zaglavlje Authorization nije Bearer');
  const token = m[1] ?? '';
  // supabase-js bez sesije šalje anon ključ kao bearer.
  if (token === LOCAL_ANON_KEY) return null;
  const p = decodeJwtPayload(token);
  if (typeof p.exp === 'number' && p.exp * 1000 < now) throw new ShimError(401, 'PGRST303', 'JWT expired');
  if (p.role === 'anon') return null;
  if (p.role !== 'authenticated' || typeof p.sub !== 'string') {
    throw new ShimError(401, 'PGRST301', 'JWT mora imati ulogu anon ili authenticated (sa sub)');
  }
  return p.sub;
}

function requireProfile(value: string | undefined, header: string): void {
  if (value !== 'vijesti') {
    throw new ShimError(406, 'PGRST106', `shema mora biti „vijesti” (zaglavlje ${header})`);
  }
}

function ident(name: string): string {
  if (!IDENT.test(name)) throw new ShimError(400, 'PGRST100', `nevaljan identifikator „${name}”`);
  return `"${name}"`;
}

/** `(a,"b,c",d)` → vrijednosti. */
function parseList(raw: string): string[] {
  const m = /^\((.*)\)$/.exec(raw);
  if (!m) throw new ShimError(400, 'PGRST100', `in traži popis u zagradama: ${raw}`);
  const out: string[] = [];
  const re = /"((?:[^"\\]|\\.)*)"|([^,]+)/g;
  for (const x of (m[1] ?? '').matchAll(re)) out.push(x[1] !== undefined ? x[1].replace(/\\(.)/g, '$1') : (x[2] ?? ''));
  return out;
}

export interface BuiltQuery {
  sql: string;
  params: unknown[];
}

/** SELECT iz PostgREST upita (podskup: select, filteri eq/neq/gt/gte/lt/lte/in/is, order, limit, offset). */
export function buildSelect(relation: string, search: URLSearchParams): BuiltQuery {
  if (!(SHIM_RELATIONS as readonly string[]).includes(relation)) {
    throw new ShimError(404, '42P01', `relacija „vijesti.${relation}” ne postoji (ili je shim ne podržava)`);
  }
  const params: unknown[] = [];
  const select = search.get('select') ?? '*';
  const cols = select === '*' ? '*' : select.split(',').map((c) => ident(c.trim())).join(', ');
  const where: string[] = [];
  for (const [key, raw] of search) {
    if (RESERVED.has(key)) continue;
    const col = ident(key);
    const dot = raw.indexOf('.');
    const op = dot < 0 ? raw : raw.slice(0, dot);
    const value = dot < 0 ? '' : raw.slice(dot + 1);
    if (op === 'in') {
      params.push(parseList(value));
      where.push(`${col}::text = ANY($${String(params.length)}::text[])`);
    } else if (op === 'is') {
      const v = { null: 'NULL', true: 'TRUE', false: 'FALSE' }[value];
      if (!v) throw new ShimError(400, 'PGRST100', `is traži null/true/false: ${value}`);
      where.push(`${col} IS ${v}`);
    } else if (OPS[op]) {
      params.push(value);
      where.push(`${col} ${OPS[op]} $${String(params.length)}`);
    } else {
      throw new ShimError(400, 'PGRST100', `operator „${op}” shim ne podržava`);
    }
  }
  const order = search.get('order');
  const orderSql = order
    ? order
        .split(',')
        .map((part) => {
          const [c = '', ...mods] = part.split('.');
          for (const m of mods) {
            if (!ORDER_MODS.has(m)) throw new ShimError(400, 'PGRST100', `nepoznat modifikator poretka „${m}”`);
          }
          const dir = mods.includes('desc') ? 'DESC' : 'ASC';
          const nulls = mods.includes('nullsfirst') ? ' NULLS FIRST' : mods.includes('nullslast') ? ' NULLS LAST' : '';
          return `${ident(c)} ${dir}${nulls}`;
        })
        .join(', ')
    : '';
  const num = (k: string): number | null => {
    const v = search.get(k);
    if (v === null) return null;
    if (!/^\d+$/.test(v)) throw new ShimError(400, 'PGRST100', `${k} mora biti cijeli broj`);
    return Number(v);
  };
  const limit = num('limit');
  const offset = num('offset');
  const sql = [
    `SELECT ${cols} FROM vijesti.${ident(relation)}`,
    where.length ? `WHERE ${where.join(' AND ')}` : '',
    orderSql ? `ORDER BY ${orderSql}` : '',
    limit !== null ? `LIMIT ${String(limit)}` : '',
    offset !== null ? `OFFSET ${String(offset)}` : '',
  ]
    .filter(Boolean)
    .join(' ');
  return { sql, params };
}

/** `SELECT vijesti.fn(p_a => $1::tip, …) AS r` iz tijela rpc poziva (imenovani argumenti). */
export function buildRpc(fn: string, body: unknown): BuiltQuery {
  const spec = SHIM_RPC[fn];
  if (!spec) throw new ShimError(404, 'PGRST202', `funkcija vijesti.${fn} ne postoji (ili je shim ne podržava)`);
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    throw new ShimError(400, 'PGRST102', 'tijelo rpc poziva mora biti JSON objekt');
  }
  const params: unknown[] = [];
  const args: string[] = [];
  for (const [name, value] of Object.entries(body as Record<string, unknown>)) {
    const type = spec[name];
    if (!type) throw new ShimError(404, 'PGRST202', `funkcija vijesti.${fn} nema argument ${name}`);
    params.push(value === null ? null : type === 'jsonb' ? JSON.stringify(value) : typeof value === 'string' ? value : JSON.stringify(value));
    args.push(`${name} => $${String(params.length)}::${type}`);
  }
  return { sql: `SELECT vijesti.${ident(fn)}(${args.join(', ')}) AS r`, params };
}

function pgError(e: unknown, user: string | null): ShimResponse {
  const err = e as { code?: string; message?: string; detail?: string; hint?: string };
  const code = err.code ?? 'XX000';
  // PostgREST: 42501 je 401 za anon i 403 za prijavljenog; P0001 (RAISE) je 400.
  const status = code === '42501' ? (user === null ? 401 : 403) : code === '42P01' || code === '42883' ? 404 : 400;
  return json(status, { code, message: err.message ?? String(e), details: err.detail ?? null, hint: err.hint ?? null });
}

export interface RestShim {
  handle(req: ShimRequest): Promise<ShimResponse>;
  /** Baza nad kojom shim trenutno radi (nakon resetiranja nova). */
  db(): PGlite;
}

export interface RestShimOptions {
  db: PGlite;
  /** `POST /__shim/reset`: nova baza (npr. ponovni seed za e2e). */
  reset?: () => Promise<PGlite>;
  /** `GET /__shim/seed`: opis trenutnog seeda (slugovi i stanja za e2e). */
  seedInfo?: () => unknown;
  /** `POST /__shim/verify?article=<id>`: automatska provjera zadnje verzije (engine izvan preglednika). */
  verify?: (db: PGlite, articleId: number) => Promise<void>;
  now?: () => number;
}

export function createRestShim(opts: RestShimOptions): RestShim {
  let db = opts.db;
  const cdn = createFakeCdn();
  // PGlite ima jednu vezu, a `asUser` otvara transakciju: zahtjevi idu redom.
  let queue: Promise<unknown> = Promise.resolve();
  const serial = <T>(fn: () => Promise<T>): Promise<T> => {
    const p = queue.then(fn, fn);
    queue = p.catch(() => undefined);
    return p;
  };

  async function rest(req: ShimRequest, path: string, search: URLSearchParams): Promise<ShimResponse> {
    const user = requestUser(req.headers, opts.now?.());
    if (req.method === 'GET' && !path.startsWith('rpc/')) {
      requireProfile(req.headers['accept-profile'], 'Accept-Profile');
      const q = buildSelect(path, search);
      return serial(async () => {
        try {
          const res = await asUser(db, user, (d: SqlDb) => d.query(q.sql, q.params));
          return json(200, res.rows);
        } catch (e) {
          return pgError(e, user);
        }
      });
    }
    if (req.method === 'POST' && path.startsWith('rpc/')) {
      requireProfile(req.headers['content-profile'], 'Content-Profile');
      let body: unknown;
      try {
        body = JSON.parse(req.body && req.body.length > 0 ? req.body : '{}');
      } catch {
        throw new ShimError(400, 'PGRST102', 'tijelo nije JSON');
      }
      const q = buildRpc(path.slice(4), body);
      return serial(async () => {
        try {
          const res = await asUser(db, user, (d: SqlDb) => d.query<{ r: unknown }>(q.sql, q.params));
          return json(200, res.rows[0]?.r ?? null);
        } catch (e) {
          return pgError(e, user);
        }
      });
    }
    throw new ShimError(405, 'PGRST117', `${req.method} /rest/v1/${path} shim ne podržava`);
  }

  async function cdnFile(path: string): Promise<ShimResponse> {
    if (/^data\/[^/]+\/(audio\.mp3|video_h264(_fmp4(_web)?)?\.mp4)$/.test(path)) {
      return { status: 200, headers: { ...CORS, 'content-type': 'audio/mpeg' }, body: SILENT_MP3 };
    }
    const res = await cdn.fetch(`https://cdn.domovina.ai/${path}`);
    return {
      status: res.status,
      headers: { ...CORS, 'content-type': 'application/json; charset=utf-8' },
      body: res.ok ? await res.text() : '',
    };
  }

  async function handle(req: ShimRequest): Promise<ShimResponse> {
    const url = new URL(req.url, 'http://shim.local');
    const path = url.pathname;
    try {
      if (req.method === 'OPTIONS') return { status: 204, headers: CORS, body: '' };
      if (path.startsWith('/rest/v1/')) return await rest(req, path.slice('/rest/v1/'.length), url.searchParams);
      if (path.startsWith('/cdn/') && req.method === 'GET') return await cdnFile(path.slice('/cdn/'.length));
      if (path === '/__shim/health') return json(200, { ok: true });
      if (path === '/__shim/seed' && req.method === 'GET') return json(200, opts.seedInfo?.() ?? null);
      if (path === '/__shim/verify' && req.method === 'POST') {
        const verify = opts.verify;
        const id = url.searchParams.get('article') ?? '';
        if (!verify) return pgrstError(404, 'PGRST000', 'verify nije podešen');
        if (!/^\d+$/.test(id)) return pgrstError(400, 'PGRST100', 'article mora biti broj');
        return await serial(async () => {
          await verify(db, Number(id));
          return json(200, { ok: true });
        });
      }
      if (path === '/__shim/reset' && req.method === 'POST') {
        if (!opts.reset) return pgrstError(404, 'PGRST000', 'reset nije podešen');
        const reset = opts.reset;
        return await serial(async () => {
          const old = db;
          db = await reset();
          await old.close();
          return json(200, { ok: true });
        });
      }
      return pgrstError(404, 'PGRST125', `nepoznata putanja ${path}`);
    } catch (e) {
      if (e instanceof ShimError) return pgrstError(e.status, e.code, e.message);
      throw e;
    }
  }

  return { handle, db: () => db };
}

async function readBody(req: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  for await (const c of req) chunks.push(c as Buffer);
  return Buffer.concat(chunks).toString('utf8');
}

/** HTTP poslužitelj nad shimom (127.0.0.1). */
export function serveShim(shim: RestShim, port: number, host = '127.0.0.1'): Promise<Server> {
  const server = createServer((req, res) => {
    void (async () => {
      try {
        const headers: Record<string, string | undefined> = {};
        for (const [k, v] of Object.entries(req.headers)) headers[k] = Array.isArray(v) ? v.join(', ') : v;
        const out = await shim.handle({
          method: req.method ?? 'GET',
          url: req.url ?? '/',
          headers,
          body: await readBody(req),
        });
        res.writeHead(out.status, out.headers);
        res.end(out.body);
      } catch (e) {
        res.writeHead(500, { ...CORS, 'content-type': 'text/plain; charset=utf-8' });
        res.end(String(e));
      }
    })();
  });
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, host, () => {
      resolve(server);
    });
  });
}

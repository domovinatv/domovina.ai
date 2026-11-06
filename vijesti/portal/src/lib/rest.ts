// PostgREST klijent portala (odluka 603): isti kod za produkciju (Supabase) i
// lokalni shim. Shema `vijesti` kroz `Accept-Profile`/`Content-Profile`,
// `apikey` uvijek, `Authorization: Bearer` s JWT-om urednika ili anon ključem.

export type FetchFn = (input: string, init?: RequestInit) => Promise<Response>;

export interface RestOptions {
  url: string;
  anonKey: string;
  /** JWT prijavljenog korisnika; bez njega zahtjev ide kao `anon`. */
  token?: string | null;
  fetch?: FetchFn;
  /** Prekid zahtjeva (ms); 0 = bez prekida. */
  timeoutMs?: number;
}

/** Greška PostgREST-a: `message` je za urednička pravila `kod: tekst` (odluka 511). */
export class RestError extends Error {
  constructor(
    readonly status: number,
    readonly code: string | null,
    message: string,
    readonly details: string | null = null,
  ) {
    super(message);
    this.name = 'RestError';
  }
}

/** Vrijednost filtera: `eq.x`. */
export const eq = (v: string | number): string => `eq.${String(v)}`;
/** `in.("a","b")` (navodnici: vrijednost smije imati zarez). */
export const inList = (vs: readonly (string | number)[]): string =>
  `in.(${vs.map((v) => `"${String(v).replace(/["\\]/g, '\\$&')}"`).join(',')})`;

export interface Rest {
  select<T>(relation: string, query: Record<string, string>): Promise<T[]>;
  rpc<T>(fn: string, args: Record<string, unknown>): Promise<T>;
}

async function toError(res: Response): Promise<RestError> {
  const text = await res.text().catch(() => '');
  try {
    const j = JSON.parse(text) as { code?: unknown; message?: unknown; details?: unknown };
    return new RestError(
      res.status,
      typeof j.code === 'string' ? j.code : null,
      typeof j.message === 'string' ? j.message : text,
      typeof j.details === 'string' ? j.details : null,
    );
  } catch {
    return new RestError(res.status, null, text || `HTTP ${String(res.status)}`);
  }
}

export function createRest(opts: RestOptions): Rest {
  const doFetch: FetchFn = opts.fetch ?? ((i, init) => fetch(i, init));
  const base = `${opts.url.replace(/\/+$/, '')}/rest/v1`;
  const headers = (): Record<string, string> => ({
    apikey: opts.anonKey,
    authorization: `Bearer ${opts.token ?? opts.anonKey}`,
    accept: 'application/json',
  });
  const send = async (url: string, init: RequestInit): Promise<Response> => {
    const ms = opts.timeoutMs ?? 0;
    const signal = ms > 0 ? AbortSignal.timeout(ms) : null;
    const res = await doFetch(url, signal ? { ...init, signal } : init);
    if (!res.ok) throw await toError(res);
    return res;
  };
  return {
    async select<T>(relation: string, query: Record<string, string>): Promise<T[]> {
      const qs = new URLSearchParams(query).toString();
      const res = await send(`${base}/${relation}${qs ? `?${qs}` : ''}`, {
        method: 'GET',
        headers: { ...headers(), 'accept-profile': 'vijesti' },
      });
      return (await res.json()) as T[];
    },
    async rpc<T>(fn: string, args: Record<string, unknown>): Promise<T> {
      const res = await send(`${base}/rpc/${fn}`, {
        method: 'POST',
        headers: { ...headers(), 'content-profile': 'vijesti', 'content-type': 'application/json' },
        body: JSON.stringify(args),
      });
      const text = await res.text();
      return (text ? JSON.parse(text) : null) as T;
    },
  };
}

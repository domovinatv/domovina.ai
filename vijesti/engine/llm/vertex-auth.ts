// OAuth token za Vertex AI iz `gcloud auth print-access-token --account=…`
// (isti put kao pipeline, `fetch.domovina.tv/lib/vertex_auth.js`). Token živi
// ~60 min, pa se kešira 50 min. Token se nikad ne logira: poruke grešaka nose
// samo stderr gcloud-a, nikad stdout.
import { execFile as nodeExecFile } from 'node:child_process';
import type { AccessTokenProvider } from './gemini.js';

export type ExecFileLike = (file: string, args: string[]) => Promise<{ stdout: string; stderr?: string }>;

export const TOKEN_TTL_MS = 50 * 60 * 1000;

const defaultExecFile: ExecFileLike = (file, args) =>
  new Promise((resolve, reject) => {
    nodeExecFile(file, args, { timeout: 30_000, encoding: 'utf8' }, (err, stdout, stderr) => {
      if (err) {
        const why = stderr.trim().split('\n').slice(-2).join(' ').slice(0, 200) || err.message;
        reject(new Error(why));
      } else resolve({ stdout, stderr });
    });
  });

export interface GcloudTokenOptions {
  /** gcloud account (`VIJESTI_VERTEX_ACCOUNT`); bez njega aktivni account gcloud-a. */
  account?: string | null | undefined;
  execFile?: ExecFileLike;
  now?: () => number;
  ttlMs?: number;
}

export function gcloudTokenArgs(account?: string | null): string[] {
  return ['auth', 'print-access-token', ...(account ? [`--account=${account}`] : [])];
}

export function createGcloudTokenProvider(opts: GcloudTokenOptions = {}): AccessTokenProvider & {
  /** Koliko je puta gcloud stvarno pozvan (testovi). */
  readonly fetches: number;
} {
  const exec = opts.execFile ?? defaultExecFile;
  const now = opts.now ?? Date.now;
  const ttl = opts.ttlMs ?? TOKEN_TTL_MS;
  let cached: { token: string; at: number } | null = null;
  let pending: Promise<string> | null = null;
  let fetches = 0;
  const who = opts.account ? ` (${opts.account})` : '';

  async function fetchToken(): Promise<string> {
    fetches++;
    let stdout: string;
    try {
      ({ stdout } = await exec('gcloud', gcloudTokenArgs(opts.account)));
    } catch (e) {
      // `cause` je greška iz execFile omota: nosi samo stderr, nikad stdout (token).
      throw new Error(`gcloud auth print-access-token${who} nije uspio: ${(e as Error).message}`, { cause: e });
    }
    const token = stdout.trim();
    if (!token || /\s/.test(token)) {
      throw new Error(`gcloud auth print-access-token${who} nije vratio token`);
    }
    cached = { token, at: now() };
    return token;
  }

  return {
    get fetches() {
      return fetches;
    },
    token() {
      if (cached && now() - cached.at < ttl) return Promise.resolve(cached.token);
      // Istodobni pozivi dijele jedan gcloud proces.
      pending ??= fetchToken().finally(() => {
        pending = null;
      });
      return pending;
    },
    invalidate() {
      cached = null;
    },
  };
}

/** Gotov token (testovi, ili token izdan izvan procesa). */
export function staticTokenProvider(token: string): AccessTokenProvider {
  return { token: () => Promise.resolve(token), invalidate: () => undefined };
}

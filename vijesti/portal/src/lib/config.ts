// Konfiguracija portala iz okoline Workera (wrangler `vars`). Zadane vrijednosti
// su produkcijske; lokalni način ih prepisuje u `env.local` (wrangler.jsonc).

export interface PortalConfig {
  /** PostgREST (Supabase) korijen, bez `/rest/v1`. */
  restUrl: string;
  /** Javni anon ključ (Supabase `apikey`); nije tajna. */
  anonKey: string;
  /** GoTrue (Supabase Auth) korijen za prijavu u admin. */
  authUrl: string;
  /** CDN s datotekama epizoda (`data/<id>/…`). */
  cdnBase: string;
  /** Aplikacija (poveznica „Poslušaj cijeli razgovor”). */
  appBase: string;
}

export const DEFAULT_CONFIG: PortalConfig = {
  restUrl: 'https://api.domovina.ai',
  anonKey: '',
  authUrl: 'https://api.domovina.ai',
  cdnBase: 'https://cdn.domovina.ai',
  appBase: 'https://domovina.ai',
};

const trim = (s: string) => s.replace(/\/+$/, '');

function str(env: Record<string, unknown>, key: string): string | undefined {
  const v = env[key];
  return typeof v === 'string' && v.trim() !== '' ? v.trim() : undefined;
}

export function readConfig(env: Record<string, unknown>): PortalConfig {
  const restUrl = trim(str(env, 'VIJESTI_REST_URL') ?? DEFAULT_CONFIG.restUrl);
  return {
    restUrl,
    anonKey: str(env, 'VIJESTI_ANON_KEY') ?? DEFAULT_CONFIG.anonKey,
    authUrl: trim(str(env, 'VIJESTI_AUTH_URL') ?? restUrl),
    cdnBase: trim(str(env, 'VIJESTI_CDN_BASE') ?? DEFAULT_CONFIG.cdnBase),
    appBase: trim(str(env, 'VIJESTI_APP_BASE') ?? DEFAULT_CONFIG.appBase),
  };
}

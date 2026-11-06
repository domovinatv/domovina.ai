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
  /** Javna domena portala (canonical, sitemap, RSS, JSON-LD), bez `/vijesti`. */
  siteBase: string;
  /** Podaci za impresum i kontakt; null = upisuje izdavač (odluka 710). */
  legal: LegalConfig;
}

export interface LegalConfig {
  /** Naziv nakladnika (izdavača). */
  publisherName: string | null;
  /** Sjedište (adresa) nakladnika. */
  publisherAddress: string | null;
  /** Glavni urednik (ime i prezime). */
  editorInChief: string | null;
  /** E-pošta za ispravke i za kreatore koji žele van. */
  contactEmail: string | null;
  /** Upis u Upisnik pružatelja elektroničkih publikacija (AEM), npr. klasa ili datum. */
  aemRegistration: string | null;
}

/** Varijabla okoline (wrangler `vars`) za svako pravno polje. */
export const LEGAL_VARS = {
  publisherName: 'VIJESTI_PUBLISHER_NAME',
  publisherAddress: 'VIJESTI_PUBLISHER_ADDRESS',
  editorInChief: 'VIJESTI_EDITOR_IN_CHIEF',
  contactEmail: 'VIJESTI_CONTACT_EMAIL',
  aemRegistration: 'VIJESTI_AEM_REGISTRATION',
} as const satisfies Record<keyof LegalConfig, string>;

export const DEFAULT_CONFIG: PortalConfig = {
  restUrl: 'https://api.domovina.ai',
  anonKey: '',
  authUrl: 'https://api.domovina.ai',
  cdnBase: 'https://cdn.domovina.ai',
  appBase: 'https://domovina.ai',
  siteBase: 'https://domovina.ai',
  legal: {
    publisherName: null,
    publisherAddress: null,
    editorInChief: null,
    contactEmail: null,
    aemRegistration: null,
  },
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
    siteBase: trim(str(env, 'VIJESTI_SITE_BASE') ?? DEFAULT_CONFIG.siteBase),
    legal: readLegal(env),
  };
}

export function readLegal(env: Record<string, unknown>): LegalConfig {
  const out = { ...DEFAULT_CONFIG.legal };
  for (const [field, key] of Object.entries(LEGAL_VARS) as [keyof LegalConfig, string][]) {
    out[field] = str(env, key) ?? null;
  }
  return out;
}

/** Pravna polja koja još čekaju izdavača (prazna u konfiguraciji). */
export function missingLegal(legal: LegalConfig): (keyof LegalConfig)[] {
  return (Object.keys(LEGAL_VARS) as (keyof LegalConfig)[]).filter((k) => legal[k] === null);
}

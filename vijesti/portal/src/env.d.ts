/// <reference types="astro/client" />

/** Način prijave u admin, zamijenjen pri buildu (astro.config.mjs, odluka 606). */
declare const __VIJESTI_AUTH_MODE__: 'local' | 'supabase';

/** Okolina Workera (wrangler `vars`); čita je samo src/lib/runtime.ts. */
declare module 'cloudflare:workers' {
  export const env: Record<string, unknown>;
}

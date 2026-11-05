import { applyD1Migrations } from "cloudflare:test";
import { env } from "cloudflare:workers";

// Nijedan test ne ide na mrežu (odluka 9). `fetch` baca prije nego išta
// ode van; `outboundService` u `vitest.config.ts` je druga ograda na razini
// runtimea. Fixturei se čitaju iz datoteka, nikad s CDN-a.
globalThis.fetch = (input: RequestInfo | URL): Promise<Response> => {
  const url = input instanceof Request ? input.url : String(input);
  return Promise.reject(new Error(`mreža je u testu zabranjena: ${url}`));
};

// Idempotentno: primijenjene migracije bilježi u `d1_migrations`.
await applyD1Migrations(env.DB, env.TEST_MIGRATIONS);

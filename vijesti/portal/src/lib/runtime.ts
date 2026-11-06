// Pristup okolini Workera; jedino mjesto koje uvozi `cloudflare:workers`.
import { env } from 'cloudflare:workers';
import { readConfig, type PortalConfig } from './config.js';
import { createRest, type Rest } from './rest.js';

export function portalConfig(): PortalConfig {
  return readConfig(env);
}

/** Javni klijent: uvijek `anon`, s prekidom da spora baza ne drži stranicu. */
export function publicRest(cfg: PortalConfig): Rest {
  return createRest({ url: cfg.restUrl, anonKey: cfg.anonKey, timeoutMs: 4000 });
}

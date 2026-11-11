/** Bindingi Workera (vidi `wrangler.jsonc`). */
export interface Env {
  readonly DB: D1Database;
  /** Brend kad host zahtjeva nije u `brands.host` (`wrangler dev` na localhostu), odluka 305. */
  readonly DEFAULT_BRAND: string;
  /**
   * Bearer token za `/ingest` i `/ingest/ids` (secret, `wrangler secret put`).
   * Bez njega ingest vraća 503 `ingest_disabled` (odluka 602).
   */
  readonly INGEST_TOKEN?: string;
  /**
   * Korijen domovina-api za poller postavki kanala (var; produkcija
   * `https://api.domovina.ai`). Bez njega poller bilježi `disabled`.
   */
  readonly SETTINGS_API_URL?: string;
  /**
   * Anon ključ domovina-api za javne poglede postavki (secret, `wrangler secret put
   * SETTINGS_ANON_KEY`). Bez njega poller ne zove mrežu i bilježi `disabled`
   * (obrazac odluke 602).
   */
  readonly SETTINGS_ANON_KEY?: string;
}

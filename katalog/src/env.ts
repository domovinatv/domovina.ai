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
}

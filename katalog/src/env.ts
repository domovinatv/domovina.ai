/** Bindingi Workera (vidi `wrangler.jsonc`). */
export interface Env {
  readonly DB: D1Database;
  /** Brend kad host zahtjeva nije u `brands.host` (`wrangler dev` na localhostu), odluka 305. */
  readonly DEFAULT_BRAND: string;
}

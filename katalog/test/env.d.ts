import type { D1Migration } from "cloudflare:test";

declare global {
  namespace Cloudflare {
    interface Env {
      readonly DB: D1Database;
      /** Migracije pročitane u `vitest.config.ts` (Node), primijenjene u `setup.ts`. */
      readonly TEST_MIGRATIONS: D1Migration[];
      /** Testni token za `/ingest` (`vitest.config.ts`). */
      readonly INGEST_TOKEN: string;
    }
    interface GlobalProps {
      mainModule: typeof import("../src/index.js");
    }
  }
}

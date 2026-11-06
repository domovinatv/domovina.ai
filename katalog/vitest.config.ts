import { cloudflareTest, readD1Migrations } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest(async () => ({
      main: "./src/index.ts",
      wrangler: { configPath: "./wrangler.jsonc" },
      miniflare: {
        // Migracije se čitaju u Nodeu (ovdje) i predaju testnom workeru kao
        // binding; `test/setup.ts` ih primijeni na lokalni D1.
        // `INGEST_TOKEN` je testni secret za `/ingest` (odluka 602); nikad kroz
        // `.dev.vars`, koja je lokalna i gitignorana.
        bindings: {
          TEST_MIGRATIONS: await readD1Migrations("./migrations"),
          INGEST_TOKEN: "test-ingest-token",
        },
        // Mreža prema van je u testu zatvorena i na razini runtimea: svaki
        // `fetch` koji ne ide na binding završi ovdje. Uz stub u
        // `test/setup.ts` ovo hvata i fetch koji bi kod vratio na original.
        outboundService: (request: Request) => {
          throw new Error(`mreža je u testu zabranjena: ${request.method} ${request.url}`);
        },
      },
    })),
  ],
  test: {
    setupFiles: ["./test/setup.ts"],
  },
});

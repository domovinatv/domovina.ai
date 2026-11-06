// e2e portala vijesti (S6): Chromium nad produkcijskim buildom u lokalnom
// načinu (`npm run portal:preview`: shim 8790 + workerd 4322). Jedan worker:
// shim je jedna baza, a testovi koji pišu resetiraju seed (`POST /__shim/reset`).
// Mreža prema van je zabranjena u `e2e/fixtures.ts` (test pada).
import { defineConfig, devices } from '@playwright/test';

const PORT = Number(process.env.VIJESTI_PORTAL_PORT ?? 4322);

export default defineConfig({
  testDir: './e2e',
  fullyParallel: false,
  workers: 1,
  forbidOnly: true,
  retries: 0,
  reporter: process.env.CI ? 'line' : [['list']],
  timeout: 30_000,
  expect: { timeout: 5_000 },
  outputDir: '../.cache/e2e-results',
  use: {
    baseURL: `http://127.0.0.1:${String(PORT)}`,
    locale: 'hr-HR',
    timezoneId: 'Europe/Zagreb',
    trace: 'retain-on-failure',
    serviceWorkers: 'block',
  },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: 'npx tsx dev/preview.ts',
    cwd: import.meta.dirname,
    url: `http://127.0.0.1:${String(PORT)}/vijesti/`,
    reuseExistingServer: false,
    timeout: 120_000,
    stdout: 'ignore',
    stderr: 'pipe',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5_000 },
  },
});

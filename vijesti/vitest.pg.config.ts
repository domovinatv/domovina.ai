import { defineConfig } from 'vitest/config';

// `npm run test:pg`: adapter `db/pg.ts` nad pravim Postgresom (privremeni
// klaster iz `initdb`, odluka 808). Odvojeno od `npm run check` jer traži
// Postgres binarije na stroju; pokreće se uz svaku promjenu `db/pg.ts` ili
// migracija koje engine koristi.
export default defineConfig({
  test: {
    include: ['db/**/*.itest.ts'],
    setupFiles: ['engine/test/setup.ts'],
    allowOnly: false,
    passWithNoTests: false,
    testTimeout: 120_000,
    hookTimeout: 60_000,
  },
});

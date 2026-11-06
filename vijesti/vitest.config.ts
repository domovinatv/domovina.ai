import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['engine/**/*.test.ts', 'db/**/*.test.ts'],
    setupFiles: ['engine/test/setup.ts'],
    // Preskočen test se ne smije sakriti: `skipped 0` je uvjet zelenog stanja.
    allowOnly: false,
    passWithNoTests: false,
    // Prvi PGlite test u datoteci pod punim paralelnim opterećenjem traje ~4,5 s
    // (inicijalizacija WASM-a), tik uz zadanih 5 s; odluka 519.
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
});

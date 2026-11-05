import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['engine/**/*.test.ts', 'db/**/*.test.ts'],
    setupFiles: ['engine/test/setup.ts'],
    // Preskočen test se ne smije sakriti: `skipped 0` je uvjet zelenog stanja.
    allowOnly: false,
    passWithNoTests: false,
  },
});

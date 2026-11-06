// Produkcijski build nema lažnu prijavu (odluka 606): način prijave je
// konstanta pri buildu, pa grana `local` i modul auth-local ispadaju iz izlaza.
// Lokalni build mora oznaku imati, inače test ništa ne dokazuje.
import { execFileSync } from 'node:child_process';
import { mkdtempSync, readdirSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, describe, expect, it } from 'vitest';
import { LOCAL_AUTH_MARKER } from '../src/scripts/admin/auth-local.js';

const ROOT = fileURLToPath(new URL('..', import.meta.url));
const outDirs: string[] = [];

function build(mode: string | undefined): string {
  const out = mkdtempSync(join(tmpdir(), 'vijesti-portal-'));
  outDirs.push(out);
  const env = { ...process.env };
  delete env.VIJESTI_AUTH_MODE;
  delete env.CLOUDFLARE_ENV;
  if (mode !== undefined) env.VIJESTI_AUTH_MODE = mode;
  execFileSync(join(ROOT, '..', 'node_modules', '.bin', 'astro'), ['build', '--root', ROOT, '--outDir', out], {
    env,
    stdio: 'pipe',
  });
  return out;
}

function files(dir: string): string[] {
  return readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((d) => d.isFile() && /\.(m?js|html|json)$/.test(d.name))
    .map((d) => join(d.parentPath, d.name));
}

const containsMarker = (dir: string) => files(dir).filter((f) => readFileSync(f, 'utf8').includes(LOCAL_AUTH_MARKER));
const names = (dir: string) => files(dir).map((f) => f.slice(dir.length));

afterAll(() => {
  for (const d of outDirs) rmSync(d, { recursive: true, force: true });
});

describe('build portala', () => {
  it('zadani (produkcijski) build nema lažnu prijavu ni modul auth-local', () => {
    const out = build(undefined);
    expect(containsMarker(out)).toEqual([]);
    expect(names(out).filter((n) => n.includes('auth-local'))).toEqual([]);
    expect(names(out).some((n) => n.includes('auth-supabase'))).toBe(true);
  }, 120_000);

  it('lokalni build je ima (provjera nije prazna), bez Supabase modula', () => {
    const out = build('local');
    expect(containsMarker(out).length).toBeGreaterThan(0);
    expect(names(out).some((n) => n.includes('auth-supabase'))).toBe(false);
  }, 120_000);

  it('nepoznat način prijave ruši build', () => {
    expect(() => build('lokal')).toThrow();
  }, 120_000);
});

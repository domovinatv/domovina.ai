// Provjera prije objave (odluka 710): prazan impresum ili anon ključ se javljaju
// imenom varijable; potpuna konfiguracija prolazi.
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { formatProblems, readWranglerVars, releaseProblems } from '../dev/release-check.js';
import { LEGAL_VARS } from '../src/lib/config.js';

const FULL = {
  VIJESTI_ANON_KEY: 'javni-anon',
  VIJESTI_PUBLISHER_NAME: 'Nakladnik d.o.o.',
  VIJESTI_PUBLISHER_ADDRESS: 'Ulica 1, Zagreb',
  VIJESTI_EDITOR_IN_CHIEF: 'Ime Prezime',
  VIJESTI_CONTACT_EMAIL: 'vijesti@primjer.hr',
  VIJESTI_AEM_REGISTRATION: 'upisano 1. 12. 2026.',
};

describe('release-check', () => {
  it('prazna konfiguracija: svih pet pravnih polja i anon ključ', () => {
    const vars = releaseProblems({}).map((p) => p.variable);
    expect(vars).toEqual([...Object.values(LEGAL_VARS), 'VIJESTI_ANON_KEY']);
    expect(formatProblems(releaseProblems({}))).toMatch(/NIJE spreman za objavu: 6/);
  });
  it('razmak nije vrijednost; potpuna konfiguracija prolazi', () => {
    expect(releaseProblems({ ...FULL, VIJESTI_EDITOR_IN_CHIEF: '  ' }).map((p) => p.variable)).toEqual([
      'VIJESTI_EDITOR_IN_CHIEF',
    ]);
    expect(releaseProblems(FULL)).toEqual([]);
  });
  it('čita `vars` iz izlaznog wrangler.json; bez `vars` je sve prazno', () => {
    const dir = mkdtempSync(join(tmpdir(), 'vijesti-release-'));
    try {
      writeFileSync(join(dir, 'a.json'), JSON.stringify({ name: 'x', vars: FULL }));
      writeFileSync(join(dir, 'b.json'), JSON.stringify({ name: 'x' }));
      expect(releaseProblems(readWranglerVars(join(dir, 'a.json')))).toEqual([]);
      expect(releaseProblems(readWranglerVars(join(dir, 'b.json')))).toHaveLength(6);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

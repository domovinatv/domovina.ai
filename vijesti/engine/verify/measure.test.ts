// Fiksira ključne brojke mjerenja rizika provjere citata (odluka 212,
// docs/research/2026-11-05-provjera-citata.md). Promjena provjere koja ih
// pomakne mora promijeniti i ovaj test i dokument. `npm run verify:measure`.
import { beforeAll, describe, expect, it } from 'vitest';
import { formatTable, loadFixtureCues, MEASURE_FIXTURES, measureAll, wordsAlignment, type Tally } from './measure.js';

let rows: Tally[] = [];
beforeAll(async () => {
  rows = await measureAll();
});

const pass = (t: Tally | undefined) => (t?.by.exact ?? 0) + (t?.by.fuzzy ?? 0) + (t?.by.srt_only ?? 0);
const row = (fixture: string, variant: string) => rows.find((r) => r.fixture === fixture && r.variant === variant);
const sum = (variant: string, f: (t: Tally) => number) =>
  rows.filter((r) => r.variant === variant).reduce((a, r) => a + f(r), 0);

describe('mjerenje provjere citata na 5 fixturea', () => {
  it('doslovni cue / par cueova: [prolazi, n] po fixtureu; padovi su samo negation_cut', () => {
    const got = Object.fromEntries(
      MEASURE_FIXTURES.map((f) => {
        const r = row(f.id, 'verbatim');
        return [f.id, [pass(r), r?.n ?? 0]];
      }),
    );
    expect(got).toEqual({
      'pIx_7N-6HJ4': [135, 140],
      'P9sLks-f2mQ': [126, 126],
      'x3w2BVZJ9vQ': [242, 242],
      'MGLq9v3AtvE': [136, 136],
      'b-nls1ck8EE': [134, 134],
    });
    expect(row('pIx_7N-6HJ4', 'verbatim')?.by).toEqual({ exact: 135, 'failed:negation_cut': 5 });
    // Bez words.json sve je srt_only, s words.json ništa nije srt_only.
    expect(row('P9sLks-f2mQ', 'verbatim')?.by).toEqual({ srt_only: 126 });
    expect(sum('verbatim', (r) => r.by.srt_only ?? 0)).toBe(126);
  });

  it('(b) interpunkcija i velika slova ne mijenjaju ishod; (c) pola-pola pada samo uz niječnicu', () => {
    expect(sum('repunct', pass)).toBe(sum('verbatim', pass));
    expect(sum('repunct', (r) => r.n)).toBe(778);
    expect([sum('half_half', pass), sum('half_half', (r) => r.n)]).toEqual([325, 335]);
    for (const r of rows.filter((x) => x.variant === 'half_half')) {
      expect(Object.keys(r.by).filter((k) => k.startsWith('failed:') && k !== 'failed:negation_cut')).toEqual([]);
    }
  });

  it('(a1) glasovi oklijevanja: samo 2 uzorka (EN), oba fuzzy; HR titlovi ih nemaju', () => {
    expect(rows.filter((r) => r.variant === 'no_fillers').map((r) => [r.fixture, r.by])).toEqual([
      ['x3w2BVZJ9vQ', { fuzzy: 2 }],
    ]);
  });

  it('(a2) bez „ovaj, znači, dakle, ono” i (d) ASCII: gotovo sve pada', () => {
    expect([sum('no_discourse', pass), sum('no_discourse', (r) => r.n)]).toEqual([17, 229]);
    expect([sum('no_diacritics', pass), sum('no_diacritics', (r) => r.n)]).toEqual([0, 495]);
  });

  it('words.json: svi cueovi s vremenima, vremena unutar cuea i uzlazna', async () => {
    const got: Record<string, [number, number, number, number]> = {};
    for (const f of MEASURE_FIXTURES) {
      const a = wordsAlignment(f.id, await loadFixtureCues(f));
      expect(a.countMismatch, f.id).toBe(0);
      expect(a.outOfOrder, f.id).toBe(0);
      got[f.id] = [a.ok, a.missing, a.words, a.zeroLength];
    }
    expect(got).toEqual({
      'pIx_7N-6HJ4': [85, 0, 1921, 7],
      'P9sLks-f2mQ': [0, 73, 0, 0],
      'x3w2BVZJ9vQ': [149, 0, 2521, 60],
      'MGLq9v3AtvE': [103, 0, 2146, 12],
      'b-nls1ck8EE': [75, 0, 1956, 0],
    });
  });

  it('tablica se ispisuje za sve fixturee', () => {
    const t = formatTable(rows);
    for (const f of MEASURE_FIXTURES) expect(t).toContain(f.id);
  });
});

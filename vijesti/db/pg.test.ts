import { describe, expect, it } from 'vitest';
import { parseInt8Array, typeParser } from './pg.js';

describe('pg tipovi poravnati s PGliteom', () => {
  it('int8 je broj, date je ponoć UTC, numeric ostaje string', () => {
    expect(typeParser(20)('42')).toBe(42);
    expect(typeParser(1082)('2026-11-12')).toEqual(new Date('2026-11-12T00:00:00Z'));
    expect(typeParser(1700)('1.50')).toBe('1.50');
  });
  it('int8[] u brojeve, NULL ostaje null', () => {
    expect(parseInt8Array('{}')).toEqual([]);
    expect(parseInt8Array('{1,22,NULL}')).toEqual([1, 22, null]);
  });
});

// Uparivanje govornika s osobom iz kataloga i učitavanje popisa (odluke 308, 314).
import { readFileSync } from 'node:fs';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { createDiskCache } from '../cdn/cache.js';
import type { FetchLike } from '../cdn/loader.js';
import { FIXTURES_DIR } from '../test/fixtures-refresh.js';
import {
  buildPersonIndex,
  loadPersons,
  nameTokens,
  normalizeName,
  parsePersons,
  PERSONS_CACHE_PATH,
  PERSONS_URL,
  type PersonMatch,
} from './persons.js';

const RAW = readFileSync(join(FIXTURES_DIR, 'persons.json'), 'utf8');
const FILE = parsePersons(RAW);
const index = buildPersonIndex(FILE.persons);

const slug = (m: PersonMatch) => (m.matched ? m.person.slug : `-${m.reason}`);

describe('popis osoba (snimka /api/persons, 5.11.2026.)', () => {
  it('prolazi shemu: 83 osobe, slug i ime', () => {
    expect(FILE.person_count).toBe(83);
    expect(FILE.persons).toHaveLength(83);
    // „Nepoznati govornik” je zapis u katalogu, ali nije osoba: ne ulazi u indeks.
    expect(index.match('Nepoznati govornik')).toMatchObject({ matched: false, reason: 'placeholder' });
    // Dva zapisa istog čovjeka („p.” i „Pater”) daju jedan ključ.
    expect(index.size).toBe(81);
  });
});

describe('normalizacija imena', () => {
  it('mala slova, bez dijakritike, bez titula, zagrada i interpunkcije', () => {
    expect(normalizeName('Don Damir Stojić')).toBe('damir stojic');
    expect(normalizeName('fra Ante Vučković')).toBe('ante vuckovic');
    expect(normalizeName('dr. sc. Stjepo Bartulica')).toBe('stjepo bartulica');
    expect(normalizeName('Vlč. Ivan Grbešić')).toBe('ivan grbesic');
    expect(normalizeName('Karolina Vidović-Krišto')).toBe('karolina vidovic kristo');
    expect(normalizeName('Dan Đaković')).toBe('dan dakovic');
    expect(normalizeName('Gost 6 (odvjetnica)')).toBe('gost 6');
    expect(nameTokens('  ')).toEqual([]);
  });
});

describe('uparivanje govornika', () => {
  it('pogoci: titula, dijakritika, velika slova, crtica', () => {
    expect(slug(index.match('Don Damir Stojić'))).toBe('don-damir-stojic');
    expect(slug(index.match('Damir Stojić'))).toBe('don-damir-stojic');
    expect(slug(index.match('NINO RASPUDIC'))).toBe('nino-raspudic');
    expect(slug(index.match('dr. Stjepo Bartulica'))).toBe('stjepo-bartulica');
    expect(slug(index.match('Karolina Vidović-Krišto'))).toBe('karolina-vidovic-kristo');
    expect(slug(index.match('Marija Selak Raspudić'))).toBe('marija-selak-raspudic');
  });

  it('isto prezime, druga osoba: nema pogotka', () => {
    expect(slug(index.match('Stanko Stojić'))).toBe('-not_found');
    expect(slug(index.match('Ivan Raspudić'))).toBe('-not_found');
    // Dio višedijelnog imena nije ime.
    expect(slug(index.match('Marija Raspudić'))).toBe('-not_found');
  });

  it('samo ime ili samo prezime: nema pogotka', () => {
    expect(slug(index.match('Nino'))).toBe('-single_token');
    expect(slug(index.match('Raspudić'))).toBe('-single_token');
    expect(slug(index.match('don Damir'))).toBe('-single_token');
  });

  it('oznake bez imena: placeholder', () => {
    for (const n of ['SPEAKER_01', 'Gost 1', 'Gost 6 (odvjetnica)', 'Voditelj', 'Nepoznat govornik']) {
      expect(slug(index.match(n))).toBe('-placeholder');
    }
    expect(slug(index.match(null))).toBe('-empty');
    expect(slug(index.match('(—)'))).toBe('-empty');
  });

  it('dva zapisa istog imena: onaj s više epizoda, drugi kao alternativa', () => {
    const m = index.match('Stjepan Ivan Horvat');
    expect(m).toMatchObject({
      matched: true,
      person: { slug: 'p-stjepan-ivan-horvat' },
      alternates: ['pater-stjepan-ivan-horvat'],
    });
  });

  it('osobe iz fixture epizoda nisu u katalogu (voditelji i gosti bez profila)', () => {
    for (const n of ['Stanko Stojić', 'fra Ante Vučković', 'Goran Jeras', 'Matija Stepanić', 'Iva Kraljević']) {
      expect(index.match(n).matched).toBe(false);
    }
  });
});

describe('loadPersons: disk cache i zastario cache', () => {
  const okFetch =
    (body: string, calls: string[]): FetchLike =>
    (url) => {
      calls.push(url);
      return Promise.resolve({ status: 200, ok: true, text: () => Promise.resolve(body) });
    };
  const deadFetch: FetchLike = () => Promise.reject(new Error('ENOTFOUND'));

  it('mreža → cache; svjež cache bez mreže; mreža pala → zastario cache; ništa → greška', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'vijesti-persons-'));
    try {
      let t = Date.now();
      const cache = createDiskCache(dir, () => t);
      const calls: string[] = [];
      const a = await loadPersons({ fetch: okFetch(RAW, calls), cache });
      expect(a.source).toBe('network');
      expect(calls).toEqual([PERSONS_URL]);
      const b = await loadPersons({ fetch: deadFetch, cache });
      expect(b.source).toBe('cache');
      expect(b.file.persons).toHaveLength(83);
      t += 2 * 24 * 60 * 60 * 1000;
      const c = await loadPersons({ fetch: deadFetch, cache });
      expect(c.source).toBe('stale-cache');
      // Nečitljiv odgovor se ne sprema preko dobrog.
      const d = await loadPersons({ fetch: okFetch('{"persons": 3}', []), cache });
      expect(d.source).toBe('stale-cache');
      expect(await cache.get(PERSONS_CACHE_PATH)).toBe(RAW);

      const empty = createDiskCache(join(dir, 'prazno'));
      await expect(loadPersons({ fetch: deadFetch, cache: empty })).rejects.toThrow(/popis osoba nedostupan.*ENOTFOUND/);
    } finally {
      await rm(dir, { recursive: true, force: true });
    }
  });
});

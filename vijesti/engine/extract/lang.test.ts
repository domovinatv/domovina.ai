import { describe, expect, it } from 'vitest';
import { parseSrt } from '../cdn/srt.js';
import { createCdnClient } from '../cdn/loader.js';
import type { EpisodeBundle } from '../cdn/schemas.js';
import { createFakeCdn, readFixture } from '../test/fake-cdn.js';
import {
  assertTextLang,
  countLangWords,
  decideQuoteLang,
  LANG_MIN_SHARE,
  originalPairs,
  QuoteLangError,
} from './lang.js';

const cdn = () => createCdnClient({ fetch: createFakeCdn().fetch });
const bundle = (files: string[]): EpisodeBundle => ({ version: 1, files, inline: {} });
const srtText = (id: string, name: string) =>
  parseSrt(readFixture(id, name))
    .cues.map((c) => c.text)
    .join(' ');

describe('decideQuoteLang (odluka 200)', () => {
  it('x3w2BVZJ9vQ: par diarized.en.srt + words.en.json → en', async () => {
    const b = await cdn().bundle('x3w2BVZJ9vQ');
    expect(originalPairs(b)).toEqual(['en']);
    expect(decideQuoteLang({ bundle: b })).toEqual({ lang: 'en', source: 'pair' });
  });

  it('hrvatske fixturei: zadano hr', async () => {
    for (const id of ['pIx_7N-6HJ4', 'P9sLks-f2mQ', 'MGLq9v3AtvE', 'b-nls1ck8EE']) {
      const b = await cdn().bundle(id);
      expect(decideQuoteLang({ bundle: b })).toEqual({ lang: 'hr', source: 'default' });
    }
  });

  it('--lang ne smije proturječiti paru (citat bi bio iz prijevoda)', async () => {
    const b = await cdn().bundle('x3w2BVZJ9vQ');
    expect(() => decideQuoteLang({ bundle: b, explicit: 'hr' })).toThrow(QuoteLangError);
    expect(decideQuoteLang({ bundle: b, explicit: 'EN' })).toEqual({ lang: 'en', source: 'explicit' });
    expect(() => decideQuoteLang({ bundle: b, explicit: 'english' })).toThrow(/neispravan --lang/);
  });

  it('jezik kanala prije zadanog; prijevod bez words nije par', () => {
    // HR epizoda s EN prijevodom titla (faza 3): words.json je HR, en nema words.
    const hrWithTranslation = bundle(['diarized.srt', 'words.json', 'diarized.en.srt']);
    expect(originalPairs(hrWithTranslation)).toEqual([]);
    expect(decideQuoteLang({ bundle: hrWithTranslation })).toEqual({ lang: 'hr', source: 'default' });
    expect(decideQuoteLang({ bundle: bundle(['diarized.srt']), channelLang: 'en' })).toEqual({
      lang: 'en',
      source: 'channel',
    });
  });

  it('dvosmisleno: goli diarized.srt bez words uz titl drugog jezika → greška', () => {
    expect(() => decideQuoteLang({ bundle: bundle(['diarized.srt', 'diarized.en.srt']) })).toThrow(
      /ne zna se koji je izvornik/,
    );
    expect(() =>
      decideQuoteLang({
        bundle: bundle(['diarized.en.srt', 'words.en.json', 'diarized.de.srt', 'words.de.json']),
      }),
    ).toThrow(/više izvornih parova/);
  });
});

describe('assertTextLang', () => {
  it('fixturei: HR titlovi su hr, EN izvornik je en, HR prijevod nije en', () => {
    for (const id of ['pIx_7N-6HJ4', 'P9sLks-f2mQ', 'MGLq9v3AtvE', 'b-nls1ck8EE', 'x3w2BVZJ9vQ']) {
      const c = assertTextLang(srtText(id, 'diarized.srt'), 'hr');
      expect(c.hr / (c.hr + c.en)).toBeGreaterThan(0.99);
    }
    const en = assertTextLang(srtText('x3w2BVZJ9vQ', 'diarized.en.srt'), 'en');
    expect(en).toMatchObject({ hr: 0, en: 906 });
    expect(() => assertTextLang(srtText('x3w2BVZJ9vQ', 'diarized.srt'), 'en')).toThrow(
      /titl nije na jeziku en \(en 0, hr 569\)/,
    );
    expect(() => assertTextLang(srtText('x3w2BVZJ9vQ', 'diarized.en.srt'), 'hr')).toThrow(QuoteLangError);
  });

  it('brojke iz odluke 200 (prvih 15 min fixturea)', () => {
    const counts = Object.fromEntries(
      ['pIx_7N-6HJ4', 'P9sLks-f2mQ', 'MGLq9v3AtvE', 'b-nls1ck8EE'].map((id) => [
        id,
        countLangWords(srtText(id, 'diarized.srt')),
      ]),
    );
    expect(counts).toMatchObject({
      'pIx_7N-6HJ4': { hr: 498, en: 1 },
      'P9sLks-f2mQ': { hr: 626, en: 4 },
      'MGLq9v3AtvE': { hr: 597, en: 2 },
      'b-nls1ck8EE': { hr: 459, en: 0 },
    });
    expect(LANG_MIN_SHARE).toBe(0.8);
  });

  it('premalo teksta i nepoznat jezik su greška, ne prolaz', () => {
    expect(() => assertTextLang('je da se', 'hr')).toThrow(/premalo teksta/);
    expect(() => assertTextLang('der die das', 'de')).toThrow(/ne zna jezik „de”/);
  });
});

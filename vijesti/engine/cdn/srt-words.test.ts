import { describe, expect, it } from 'vitest';
import { readFixture } from '../test/fake-cdn.js';
import { FIXTURES } from '../test/fixtures-refresh.js';
import { WordsFileSchema } from './schemas.js';
import { cueTokens, parseSrt } from './srt.js';
import { hmsToMs } from './time.js';
import { attachWords, wordsStats } from './words.js';

describe('parseSrt', () => {
  it('čita oznaku govornika, vrijeme i tekst', () => {
    const { cues, skippedBlocks } = parseSrt(
      '1\n00:00:00,330 --> 00:00:04,710\n[SPEAKER_00] Hoćemo mi, Matija?\n\n' +
        '2\n01:02:03,004 --> 01:02:05,000\n[SPEAKER_11] Drugi\nredak.\n',
    );
    expect(skippedBlocks).toBe(0);
    expect(cues).toEqual([
      { index: 1, startMs: 330, endMs: 4710, speaker: 'SPEAKER_00', text: 'Hoćemo mi, Matija?' },
      {
        index: 2,
        startMs: 3_723_004,
        endMs: 3_725_000,
        speaker: 'SPEAKER_11',
        text: 'Drugi redak.',
      },
    ]);
  });

  it('podnosi CRLF, BOM, cue bez govornika i preskače neispravan blok', () => {
    const raw =
      '﻿1\r\n00:00:01,000 --> 00:00:02,000\r\nBez oznake\r\n\r\n' +
      'smeće bez vremena\r\n\r\n' +
      '3\r\n00:00:03,000 --> 00:00:04,000\r\n[SPEAKER_01] Da.\r\n';
    const { cues, skippedBlocks } = parseSrt(raw);
    expect(skippedBlocks).toBe(1);
    expect(cues.map((c) => [c.speaker, c.text])).toEqual([
      [null, 'Bez oznake'],
      ['SPEAKER_01', 'Da.'],
    ]);
  });

  it('prazan SRT', () => {
    expect(parseSrt('  \n')).toEqual({ cues: [], skippedBlocks: 0 });
  });

  it('svaki fixture: nijedan preskočen blok, oznaka uvijek na početku', () => {
    for (const f of FIXTURES) {
      const raw = readFixture(f.id, 'diarized.srt');
      const { cues, skippedBlocks } = parseSrt(raw);
      expect(skippedBlocks, f.id).toBe(0);
      expect(cues.every((c) => c.speaker !== null && !c.text.includes('[SPEAKER_'))).toBe(true);
      expect(cues.every((c) => c.startMs < 15 * 60 * 1000)).toBe(true);
    }
  });

  it('cueTokens broji kao ugovor words.json', () => {
    expect(cueTokens('  Dakle,  počeli smo\tsrijedom. ')).toEqual(['Dakle,', 'počeli', 'smo', 'srijedom.']);
    expect(cueTokens('   ')).toEqual([]);
  });
});

describe('attachWords', () => {
  const cues = parseSrt(
    '1\n00:00:01,000 --> 00:00:02,000\n[SPEAKER_00] jedan dva\n\n' +
      '2\n00:00:03,000 --> 00:00:04,000\n[SPEAKER_01] tri četiri pet\n\n' +
      '3\n00:00:05,000 --> 00:00:06,000\n[SPEAKER_00] šest\n',
  ).cues;

  it('vremena su apsolutni parovi (početak, kraj); početak ±1 ms', () => {
    const words = WordsFileSchema.parse({
      v: 1,
      source: 'soniox',
      anchored: 1,
      cues: [
        { s: 1001, e: 2000, w: [1000, 1400, 1500, 2000], a: 1 },
        { s: 3000, e: 4000, w: [3000, 3500, 3600, 4000] },
      ],
    });
    const timed = attachWords(cues, words);
    expect(timed[0]?.wordsStatus).toBe('ok');
    expect(timed[0]?.words).toEqual([
      { text: 'jedan', startMs: 1000, endMs: 1400 },
      { text: 'dva', startMs: 1500, endMs: 2000 },
    ]);
    expect(timed[0]?.anchored).toBe(1);
    // Drugi cue ima 3 riječi, a words.json 2 para: bez vremena, ne pomaknuto.
    expect(timed[1]?.wordsStatus).toBe('count_mismatch');
    expect(timed[1]?.words).toBeNull();
    expect(timed[2]?.wordsStatus).toBe('missing');
    expect(wordsStats(timed)).toEqual({ cues: 3, ok: 1, countMismatch: 1, missing: 1 });
  });

  it('bez words.json svi cueovi su `missing`', () => {
    expect(wordsStats(attachWords(cues, null)).missing).toBe(3);
  });

  it('stvarni fixture: pokvaren tekst jednog cue-a gubi vremena samo za taj cue', () => {
    const f = FIXTURES.find((x) => x.criterion === 'words');
    if (!f) throw new Error('nema fixturea');
    const parsed = parseSrt(readFixture(f.id, 'diarized.srt')).cues;
    const words = WordsFileSchema.parse(JSON.parse(readFixture(f.id, 'words.json')));
    const tampered = parsed.map((c, i) => (i === 5 ? { ...c, text: `${c.text} umetnuto` } : c));
    const stats = wordsStats(attachWords(tampered, words));
    expect(stats.countMismatch).toBe(1);
    expect(stats.ok).toBe(parsed.length - 1);
  });

  it('riječi u fixtureima su monotone po početku i unutar cue-a ±1 s', () => {
    for (const f of FIXTURES) {
      const name = f.lang ? `words.${f.lang}.json` : 'words.json';
      let raw: string;
      try {
        raw = readFixture(f.id, name);
      } catch {
        continue; // fixture bez words datoteke (namjerno)
      }
      const words = WordsFileSchema.parse(JSON.parse(raw));
      for (const c of words.cues) {
        for (let i = 0; i + 1 < c.w.length; i += 2) {
          const s = c.w[i] ?? 0;
          const e = c.w[i + 1] ?? 0;
          expect(e).toBeGreaterThanOrEqual(s);
          expect(s).toBeGreaterThanOrEqual(c.s - 1000);
          expect(e).toBeLessThanOrEqual(c.e + 1000);
          if (i >= 2) expect(s).toBeGreaterThanOrEqual(c.w[i - 2] ?? 0);
        }
      }
    }
  });
});

describe('hmsToMs', () => {
  it('pretvara i odbija neispravno', () => {
    expect(hmsToMs('02:40:36')).toBe((2 * 3600 + 40 * 60 + 36) * 1000);
    expect(() => hmsToMs('2:40')).toThrow();
  });
});

// Spoj SRT cue-a i `words.json`. Ugovor je SRT
// (docs/2026-10-06-titlovi-rijec-po-rijec.md, korijen repoa): cue dobiva
// vremena riječi samo ako `words.json` za njegov početak (±1 ms) ima TOČNO
// onoliko parova koliko cue ima riječi (`text.trim().split(/\s+/)`). Inače je
// cue bez vremena riječi, nikad s pomaknutim.
import type { WordsFile } from './schemas.js';
import { cueTokens, type SrtCue } from './srt.js';

export interface TimedWord {
  text: string;
  startMs: number;
  endMs: number;
}

/** `ok`: vremena su tu; `count_mismatch`: words.json ima cue, ali drugi broj riječi; `missing`: nema zapisa. */
export type WordsStatus = 'ok' | 'count_mismatch' | 'missing';

export interface TimedCue extends SrtCue {
  tokens: string[];
  /** Vremena po riječi ili `null` kad status nije `ok`. */
  words: TimedWord[] | null;
  wordsStatus: WordsStatus;
  /** Udio usidrenih riječi u cue-u (`a` iz words.json), ako postoji. */
  anchored: number | null;
}

export interface WordsStats {
  cues: number;
  ok: number;
  countMismatch: number;
  missing: number;
}

export function attachWords(cues: readonly SrtCue[], words: WordsFile | null): TimedCue[] {
  const byStart = new Map<number, WordsFile['cues'][number]>();
  for (const c of words?.cues ?? []) byStart.set(c.s, c);
  return cues.map((cue) => {
    const tokens = cueTokens(cue.text);
    const w =
      byStart.get(cue.startMs) ?? byStart.get(cue.startMs - 1) ?? byStart.get(cue.startMs + 1);
    if (!w) return { ...cue, tokens, words: null, wordsStatus: 'missing', anchored: null };
    const anchored = w.a ?? null;
    if (w.w.length !== tokens.length * 2) {
      return { ...cue, tokens, words: null, wordsStatus: 'count_mismatch', anchored };
    }
    const timed = tokens.map((text, i) => ({
      text,
      startMs: w.w[2 * i] ?? 0,
      endMs: w.w[2 * i + 1] ?? 0,
    }));
    return { ...cue, tokens, words: timed, wordsStatus: 'ok', anchored };
  });
}

export function wordsStats(cues: readonly TimedCue[]): WordsStats {
  const stats: WordsStats = { cues: cues.length, ok: 0, countMismatch: 0, missing: 0 };
  for (const c of cues) {
    if (c.wordsStatus === 'ok') stats.ok++;
    else if (c.wordsStatus === 'count_mismatch') stats.countMismatch++;
    else stats.missing++;
  }
  return stats;
}

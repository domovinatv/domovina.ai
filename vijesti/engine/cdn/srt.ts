// Parser za `data/<id>/diarized.srt`. Isto pravilo kao Flutter
// (`packages/podcast_core/lib/services/data_service.dart`, `_parseSrt`):
// blokovi razdvojeni praznim retkom, drugi redak je vrijeme, ostatak tekst
// spojen razmakom, oznaka govornika `[SPEAKER_XX]` na početku teksta.

export interface SrtCue {
  /** Redni broj iz SRT-a (prvi redak bloka). */
  index: number;
  startMs: number;
  endMs: number;
  /** `SPEAKER_00` itd., ili `null` ako cue nema oznaku. */
  speaker: string | null;
  /** Tekst bez oznake govornika. */
  text: string;
}

export interface ParsedSrt {
  cues: SrtCue[];
  /** Blokovi bez ispravnog retka s vremenom. Ne bi ih trebalo biti. */
  skippedBlocks: number;
}

const TS =
  /^(\d{2}):(\d{2}):(\d{2}),(\d{3})\s*-->\s*(\d{2}):(\d{2}):(\d{2}),(\d{3})/;
const SPEAKER = /^\[(\w+)\]/;

function toMs(parts: number[], from: number): number {
  const at = (i: number): number => parts[from + i] ?? 0;
  return at(0) * 3_600_000 + at(1) * 60_000 + at(2) * 1000 + at(3);
}

export function parseSrt(raw: string): ParsedSrt {
  const cues: SrtCue[] = [];
  let skippedBlocks = 0;
  const body = raw.replace(/^\uFEFF/, '').trim();
  if (body === '') return { cues, skippedBlocks };
  for (const block of body.split(/\r?\n\s*\r?\n/)) {
    const lines = block.trim().split(/\r?\n/);
    const ts = lines.length >= 3 ? TS.exec(lines[1] ?? '') : null;
    if (!ts) {
      skippedBlocks++;
      continue;
    }
    const parts = ts.slice(1, 9).map(Number);
    const joined = lines.slice(2).join(' ').trimStart();
    const sp = SPEAKER.exec(joined);
    cues.push({
      index: Number(lines[0]),
      startMs: toMs(parts, 0),
      endMs: toMs(parts, 4),
      speaker: sp ? (sp[1] ?? null) : null,
      text: (sp ? joined.slice(sp[0].length) : joined).trim(),
    });
  }
  return { cues, skippedBlocks };
}

/** Riječi cue-a kako ih broji ugovor `words.json`: `text.trim().split(/\s+/)`. */
export function cueTokens(text: string): string[] {
  const t = text.trim();
  return t === '' ? [] : t.split(/\s+/);
}

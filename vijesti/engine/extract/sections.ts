// Podjela transkripta na dijelove za prompt (odluka 201). Sekcija članka nema
// kraj: traje od svog `screenshot_timestamp` do početka sljedeće, zadnja do
// kraja titla. Iteracije članka su vremenski odsječci (~40 min), ne verzije,
// pa se uzimaju sekcije SVIH iteracija.
import type { Article } from '../cdn/schemas.js';
import { hmsToMs } from '../cdn/time.js';
import type { TimedCue } from '../cdn/words.js';

export interface TranscriptSection {
  /** Redni broj (0…). */
  index: number;
  title: string | null;
  startMs: number;
  /** Isključivo. */
  endMs: number;
  /** Globalni indeksi cueova (isti kao `c<N>` u promptu), uzlazno. */
  cueIds: number[];
}

export const DEFAULT_FIXED_WINDOW_MS = 10 * 60 * 1000;

interface Boundary {
  startMs: number;
  title: string | null;
}

function articleBoundaries(article: Article): Boundary[] {
  const out: Boundary[] = [];
  for (const it of article.iterations) {
    for (const s of it.sections) {
      out.push({ startMs: hmsToMs(s.screenshot_timestamp), title: s.subtitle });
    }
  }
  out.sort((a, b) => a.startMs - b.startMs);
  // Dvije sekcije s istim početkom: prva bi bila prazna, ostaje zadnja.
  return out.filter((b, i) => out[i + 1]?.startMs !== b.startMs);
}

function fixedBoundaries(endMs: number, windowMs: number): Boundary[] {
  const out: Boundary[] = [];
  for (let s = 0; s < endMs; s += windowMs) out.push({ startMs: s, title: null });
  return out;
}

/**
 * Cue pripada sekciji u kojoj mu je POČETAK. Cueovi prije prve sekcije članka
 * idu u prvu (uvod prije prvog podnaslova nije izgubljen). Prazne sekcije
 * se izostavljaju (za njih nema poziva modela).
 */
export function splitSections(
  cues: readonly TimedCue[],
  article: Article | null,
  opts: { fixedWindowMs?: number } = {},
): TranscriptSection[] {
  if (cues.length === 0) return [];
  const transcriptEnd = Math.max(...cues.map((c) => c.endMs)) + 1;
  const fromArticle = article ? articleBoundaries(article) : [];
  const bounds =
    fromArticle.length > 0
      ? fromArticle
      : fixedBoundaries(transcriptEnd, opts.fixedWindowMs ?? DEFAULT_FIXED_WINDOW_MS);
  const first = bounds[0];
  if (first) first.startMs = 0;
  const sections: TranscriptSection[] = bounds.map((b, i) => ({
    index: i,
    title: b.title,
    startMs: b.startMs,
    endMs: Math.max(bounds[i + 1]?.startMs ?? transcriptEnd, b.startMs + 1),
    cueIds: [],
  }));
  cues.forEach((cue, id) => {
    let target = sections[0];
    for (const s of sections) {
      if (cue.startMs >= s.startMs) target = s;
      else break;
    }
    target?.cueIds.push(id);
  });
  return sections.filter((s) => s.cueIds.length > 0).map((s, i) => ({ ...s, index: i }));
}

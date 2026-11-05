// Prompt za izvlačenje trenutaka (S2). Promjena teksta ili sheme = novi
// PROMPT_VERSION, jer se `runs.prompt_version` uspoređuje između prolaza.
import { z } from 'zod';
import type { TimedCue } from '../cdn/words.js';
import type { TranscriptSection } from './sections.js';

export const PROMPT_VERSION = 'extract-moments/1';
export const PROMPT_NAME = 'extract-moments';

/** Izlaz modela. Vrijeme se NE traži: raspon dolazi iz cueova (odluka 206). */
export const ExtractedMomentSchema = z.object({
  cue_from: z.number().int().nonnegative(),
  cue_to: z.number().int().nonnegative(),
  speaker: z.string().regex(/^SPEAKER_\d{2}$/),
  quote: z.string().regex(/\S/),
  claim: z.string().min(1),
  topics: z.array(z.string()),
  entities: z.array(z.string()),
});
export type ExtractedMoment = z.infer<typeof ExtractedMomentSchema>;

export const ExtractOutputSchema = z.object({ moments: z.array(ExtractedMomentSchema) });
export type ExtractOutput = z.infer<typeof ExtractOutputSchema>;

const LANG_NAMES: Record<string, string> = { hr: 'hrvatskom', en: 'engleskom' };

export function langName(lang: string): string {
  return LANG_NAMES[lang] ?? `jeziku „${lang}”`;
}

export const SYSTEM_PROMPT = `Ti si urednik vijesti koji iz transkripta podcasta izdvaja izjave vrijedne vijesti.
Radiš samo s onim što je u transkriptu. Ne izmišljaš, ne ispravljaš i ne prevodiš citate.`;

function hms(ms: number): string {
  const s = Math.floor(ms / 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(Math.floor(s / 3600))}:${p(Math.floor((s % 3600) / 60))}:${p(s % 60)}`;
}

/** Redak transkripta: `[c42 00:12:34 SPEAKER_01] tekst`. */
export function cueLine(id: number, cue: TimedCue): string {
  return `[c${String(id)} ${hms(cue.startMs)} ${cue.speaker ?? 'NEPOZNAT'}] ${cue.text}`;
}

/** Parsira redak natrag (lažni klijent i testovi). */
export const CUE_LINE_RE = /^\[c(\d+) (\d{2}:\d{2}:\d{2}) (\S+)\] (.*)$/;

export function buildExtractPrompt(input: {
  cues: readonly TimedCue[];
  section: TranscriptSection;
  lang: string;
  title?: string | null;
}): string {
  const { section, lang } = input;
  const lines = section.cueIds.flatMap((id) => {
    const cue = input.cues[id];
    return cue ? [cueLine(id, cue)] : [];
  });
  const jezik = langName(lang);
  return `Epizoda: ${input.title ?? '(bez naslova)'}
Dio: ${section.title ?? '(bez podnaslova)'} (${hms(section.startMs)}–${hms(section.endMs)})
Jezik snimke: ${lang}

Transkript je podijeljen na retke. Svaki redak počinje oznakom [c<broj> <vrijeme> <govornik>].

Zadatak: izdvoji TRENUTKE, tj. konkretne izjave vrijedne vijesti (tvrdnja, podatak,
najava, stav, optužba, svjedočanstvo). Preskoči pozdrave, šale, uvode i prazne fraze.
Ako u dijelu nema ničega vrijednog, vrati prazan popis.

Za svaki trenutak vrati:
- cue_from, cue_to: brojevi redaka (samo broj iza „c”) u kojima citat počinje i završava;
- speaker: oznaka govornika iz tih redaka (npr. SPEAKER_01); citat mora izgovoriti jedan govornik;
- quote: DOSLOVAN citat na ${jezik}, kako piše u transkriptu: neprekinut niz riječi,
  bez izostavljanja („…”), bez dodavanja, bez ispravljanja gramatike i bez prijevoda;
  najmanje četiri riječi, najviše nekoliko rečenica;
- claim: jedna kratka rečenica na hrvatskom koja sažima tvrdnju;
- topics: 1–4 teme na hrvatskom;
- entities: imena osoba, organizacija i mjesta koja se u citatu spominju.

Transkript:
${lines.join('\n')}
`;
}

// Prompt za ocjenu vijesti (S3). Jedan poziv po epizodi nad svim prihvaćenim
// trenucima (odluka 306). Promjena teksta ili sheme = novi PROMPT_VERSION.
import { z } from 'zod';

export const PROMPT_VERSION = 'score-moments/1';
export const PROMPT_NAME = 'score-moments';

const Unit = z.number().min(0).max(1);
const Reason = z.string().regex(/\S/).max(300);

export const MomentScoreSchema = z.object({
  /** Broj iza „t” u oznaci trenutka u promptu. */
  id: z.number().int().positive(),
  novelty: Unit,
  concreteness: Unit,
  /** Javna uloga govornika (iz konteksta epizode), 0 = nepoznata ili privatna osoba. */
  speaker: Unit,
  /** Npr. „ministar zdravstva”, ako se iz konteksta vidi; inače null. */
  public_role: z.string().max(120).nullable(),
  reasons: z.object({
    novelty: Reason,
    concreteness: Reason,
    speaker: Reason,
  }),
});
export type MomentScore = z.infer<typeof MomentScoreSchema>;

export const ScoreOutputSchema = z.object({ scores: z.array(MomentScoreSchema) });
export type ScoreOutput = z.infer<typeof ScoreOutputSchema>;

export const SYSTEM_PROMPT = `Ti si urednik vijesti koji procjenjuje koliko su izjave iz podcasta vrijedne vijesti.
Ocjenjuješ samo ono što piše u ulazu. Ne izmišljaš uloge, funkcije ni činjenice.`;

export interface ScoreSpeaker {
  label: string;
  name: string | null;
  role: string | null;
  /** Uparena osoba iz kataloga (`/api/persons`). */
  person: { name: string; episodes: number; channels: number } | null;
}

export interface PriorEpisode {
  videoId: string;
  date: string | null;
  title: string;
  points: string[];
}

export interface PriorMoment {
  date: string | null;
  claim: string;
}

export interface ScoreMomentInput {
  /** Oznaka u promptu (1…n). */
  n: number;
  speaker: string;
  startMs: number;
  quote: string;
  claim: string | null;
  entities: string[];
}

export interface ScorePromptInput {
  title: string | null;
  date: string | null;
  channel: string | null;
  speakers: ScoreSpeaker[];
  prior: PriorEpisode[];
  priorMoments: PriorMoment[];
  moments: ScoreMomentInput[];
}

function hms(ms: number): string {
  const s = Math.floor(ms / 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(Math.floor(s / 3600))}:${p(Math.floor((s % 3600) / 60))}:${p(s % 60)}`;
}

/** Redak trenutka: `[t3 SPEAKER_01 00:12:34]`. */
export const MOMENT_LINE_RE = /^\[t(\d+) (\S+) (\d{2}:\d{2}:\d{2})\]$/;

function speakerLine(s: ScoreSpeaker): string {
  const who = s.name ?? 'ime nepoznato';
  const role = s.role ? ` (${s.role} u ovoj epizodi)` : '';
  const cat = s.person
    ? `; u katalogu osoba: ${s.person.name}, ${String(s.person.episodes)} epizoda na ${String(s.person.channels)} kanala`
    : '';
  return `- ${s.label}: ${who}${role}${cat}`;
}

export function buildScorePrompt(input: ScorePromptInput): string {
  const prior =
    input.prior.length === 0
      ? '(nema ranijih epizoda u katalogu)'
      : input.prior
          .map((e) => {
            const pts = e.points.map((p) => `  - ${p}`).join('\n');
            return `[${e.date ?? 'bez datuma'}] ${e.title}${pts ? `\n${pts}` : ''}`;
          })
          .join('\n');
  const priorMoments =
    input.priorMoments.length === 0
      ? '(nema)'
      : input.priorMoments.map((m) => `- [${m.date ?? 'bez datuma'}] ${m.claim}`).join('\n');
  const moments = input.moments
    .map((m) => {
      const lines = [
        `[t${String(m.n)} ${m.speaker} ${hms(m.startMs)}]`,
        `Citat: „${m.quote}”`,
        ...(m.claim ? [`Tvrdnja: ${m.claim}`] : []),
        ...(m.entities.length > 0 ? [`Entiteti: ${m.entities.join(', ')}`] : []),
      ];
      return lines.join('\n');
    })
    .join('\n\n');
  return `Epizoda: ${input.title ?? '(bez naslova)'}
Datum: ${input.date ?? '(nepoznat)'}
Kanal: ${input.channel ?? '(nepoznat)'}

Govornici:
${input.speakers.length > 0 ? input.speakers.map(speakerLine).join('\n') : '(nepoznati)'}

Ranije epizode istog kanala (najnovije prvo), naslov i ključne točke:
${prior}

Tvrdnje iz ranijih epizoda istog kanala koje su već izdvojene:
${priorMoments}

Zadatak: za SVAKI trenutak ispod vrati jednu ocjenu, s istim brojem (id = broj iza „t”).
Ne izostavljaj trenutke i ne dodaj nove. Sve ocjene su brojevi od 0 do 1:
- novelty: 1 = tvrdnja je nova za ovaj kanal; 0 = ista tvrdnja već je bila u ranijim
  epizodama ili tvrdnjama gore. Općepoznato ili ponavljanje stava kanala je nisko.
- concreteness: 1 = konkretna brojka, ime, datum, odluka ili najava; 0 = općenit stav,
  dojam ili savjet bez provjerljivog sadržaja.
- speaker: 1 = govornik ima javnu ulogu relevantnu za tvrdnju (dužnosnik, stručnjak,
  sudionik događaja) i to se vidi iz ulaza; 0 = uloga nepoznata. Ne nagađaj funkcije.
- public_role: javna uloga govornika ako je izričito vidljiva iz ulaza, inače null.
- reasons: po jedna kratka rečenica na hrvatskom za novelty, concreteness i speaker.

Trenuci za ocjenu:
${moments}
`;
}

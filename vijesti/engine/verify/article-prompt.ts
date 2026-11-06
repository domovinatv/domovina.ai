// Prompt LLM sloja provjere članka (S4, odluka 426): za svaku numeriranu
// rečenicu koji trenutak(ci) je podupiru. Promjena teksta ili sheme = novi
// PROMPT_VERSION. Deterministički pod je u article-checks.ts i ne vjeruje ovom
// izlazu.
import { z } from 'zod';
import type { EpisodeMeta, SourceMoment } from '../write/content.js';
import { hms } from '../write/text.js';

export const PROMPT_VERSION = 'verify-article/1';
export const PROMPT_NAME = 'verify-article';

export const SentenceVerdictSchema = z.object({
  /** Broj iza „s” u oznaci rečenice. */
  id: z.number().int().positive(),
  /** Brojevi trenutaka (iza „t”) koji izravno podupiru rečenicu. */
  supported_by: z.array(z.number().int().positive()).max(12),
  /** Rečenica govori samo o epizodi (naslov, kanal, datum, govornici) i to piše u podacima o epizodi. */
  metadata: z.boolean(),
  /** null kad je rečenica podržana; inače kratki razlog na hrvatskom. */
  reason: z.string().regex(/\S/).max(300).nullable(),
});
export type SentenceVerdict = z.infer<typeof SentenceVerdictSchema>;

export const VerifyOutputSchema = z.object({ sentences: z.array(SentenceVerdictSchema) });
export type VerifyOutput = z.infer<typeof VerifyOutputSchema>;

export const SYSTEM_PROMPT = `Ti si provjeravatelj činjenica. Za svaku rečenicu članka utvrđuješ podupiru li je trenuci iz podcasta.
Rečenica je podržana samo ako sve što tvrdi (imena, brojevi, funkcije, događaji, tko je što rekao) piše u navedenim trenucima ili u podacima o epizodi.
Ne nadopunjuješ iz vlastitog znanja. Kad nisi siguran, rečenica nije podržana.`;

export type SentencePart = 'title' | 'lead' | 'block';

export interface PromptSentence {
  n: number;
  part: SentencePart;
  text: string;
}

const PART_LABEL: Record<SentencePart, string> = { title: 'naslov', lead: 'lead', block: 'tijelo' };

/** Redak rečenice: `[s3] (tijelo) …`. */
export const SENTENCE_LINE_RE = /^\[s(\d+)\] \((naslov|lead|tijelo)\) (.*)$/;
/** Zaglavlje trenutka: `[t2 SPEAKER_00 00:01:02]`. */
export const VERIFY_MOMENT_LINE_RE = /^\[t(\d+) (\S+) (\d{2}:\d{2}:\d{2})\]$/;

export function buildVerifyPrompt(input: {
  episode: EpisodeMeta;
  moments: readonly SourceMoment[];
  sentences: readonly PromptSentence[];
}): string {
  const e = input.episode;
  const speakers = e.speakers.map((s) => `- ${s.label}: ${s.name ?? 'ime nepoznato'}${s.role ? ` (${s.role})` : ''}`);
  const moments = input.moments.map((m) =>
    [
      `[t${String(m.position)} ${m.speaker} ${hms(m.startMs)}]`,
      `Govornik: ${m.speakerName ?? 'ime nepoznato'}`,
      `Citat (${m.quoteLang}): „${m.quote}”`,
      ...(m.claim ? [`Tvrdnja: ${m.claim}`] : []),
      ...(m.entities.length > 0 ? [`Entiteti: ${m.entities.join(', ')}`] : []),
    ].join('\n'),
  );
  return `Podaci o epizodi:
Epizoda: ${e.title ?? '(bez naslova)'}
Kanal: ${e.channelName ?? '(nepoznat)'}
Datum: ${e.date ?? '(nepoznat)'}
Govornici:
${speakers.length > 0 ? speakers.join('\n') : '(nepoznati)'}

Trenuci (izvor članka):
${moments.join('\n\n')}

Rečenice članka:
${input.sentences.map((s) => `[s${String(s.n)}] (${PART_LABEL[s.part]}) ${s.text}`).join('\n')}

Zadatak: za SVAKU rečenicu vrati jedan zapis s istim brojem (id = broj iza „s”); ne izostavljaj i ne dodaj rečenice.
- supported_by: brojevi trenutaka (iza „t”) koji izravno podupiru rečenicu; prazno ako nijedan.
- metadata: true samo ako rečenica govori o epizodi (naslov, kanal, datum, govornici) i to piše u podacima o epizodi.
- reason: null ako je rečenica podržana; inače jedna kratka rečenica zašto nije (što nedostaje u izvoru).
`;
}

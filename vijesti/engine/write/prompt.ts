// Prompt generatora „vijest iz podcasta” (S4, odluke 413–419). Sistemska uputa
// sažima docs/stil.md po oznakama V1…V14; test drži oboje usklađenima
// (odluka 415). Promjena pravila, teksta ili sheme = novi PROMPT_VERSION.
import { z } from 'zod';
import { hms } from './text.js';

export const PROMPT_VERSION = 'write-vijest/1';
export const PROMPT_NAME = 'write-vijest';

/**
 * sha256 datoteke docs/stil.md iz koje je sažeta SYSTEM_PROMPT. Kad se vodič
 * promijeni, test pada dok se uputa ne pregleda i ovaj broj ne osvježi.
 */
export const STIL_SHA256 = '48d37ebb2aecbb9bef1622fb711795088227425dd0f1ede44f4f8204eba06930';

/** Zatvoren popis kategorija (docs/stil.md, odluka 416), redom prednosti. */
export const CATEGORIES = [
  'politika',
  'gospodarstvo',
  'vjera',
  'zdravlje',
  'obrazovanje',
  'znanost-tehnologija',
  'kultura',
  'sport',
  'svijet',
  'drustvo',
] as const;
export type Category = (typeof CATEGORIES)[number];

/** Ciljni raspon riječi (V10): lead + odlomci + citati kako se prikazuju. */
export const WORD_RANGE = { min: 300, max: 500 } as const;

/** Najviše trenutaka u promptu: najbolje ocijenjeni, pa redom snimke (odluka 414). */
export const MAX_WRITE_MOMENTS = 12;

const Text = z.string().regex(/\S/);

export const WriteBlockSchema = z.discriminatedUnion('type', [
  z.object({ type: z.literal('p'), text: Text.max(1500) }),
  /** Citat kao referenca: broj iza „t” u oznaci trenutka. Tekst citata se ne piše. */
  z.object({ type: z.literal('quote'), moment: z.number().int().positive() }),
]);
export type WriteBlock = z.infer<typeof WriteBlockSchema>;

export const WriteOutputSchema = z.object({
  title: Text.max(160),
  lead: Text.max(700),
  body: z.array(WriteBlockSchema).min(2).max(24),
  category: z.enum(CATEGORIES),
});
export type WriteOutput = z.infer<typeof WriteOutputSchema>;

export const SYSTEM_PROMPT = `Ti si novinar koji iz izjava jedne epizode podcasta piše kratku vijest na hrvatskom.
Pravila (docs/stil.md):
V1 Treće lice, izvještajni ton; bez „mi”, „ja”, bez obraćanja čitatelju.
V2 Obrnuta piramida: najvažnija tvrdnja prva, pozadina na kraju.
V3 Naslov: jedna izjavna rečenica do 110 znakova, bez upitnika, uskličnika, navodnika i mamaca („šokantno”, „nevjerojatno”, „evo zašto”); velika slova samo na početku i u imenima.
V4 Lead (jedna do dvije rečenice): tko govori, što tvrdi, u kojem podcastu (ime kanala) i kada (datum objave).
V5 Citat ulazi SAMO kao blok {"type":"quote","moment":N} za trenutak tN; tekst citata ne prepisuješ. U odlomcima nema navodnika; prepričana izjava ne ide u navodnike.
V6 Svaku tvrdnju pripiši govorniku („kaže”, „smatra”, „prema riječima”); ništa ne tvrdiš u svoje ime.
V7 Samo iz ulaza: nijedno ime, broj, datum, funkcija ni događaj kojih nema u trenucima ili podacima o epizodi; brojke prepisuj točno.
V8 Bez superlativa i pojačivača bez izvora („najveći”, „povijesni”, „ključni”).
V9 Bez mišljenja i vrednovanja („hrabro”, „nažalost”, „važno je istaknuti”), bez zaključaka i savjeta.
V10 Duljina 300–500 riječi: lead, odlomci i citati zajedno; naslov se ne broji.
V11 Pravopis IHJJ, dijakritike, datumi kao „6. studenoga 2026.”.
V12 Bez emojija, bez riječi velikim slovima radi naglaska, bez uskličnika.
V13 Engleska epizoda: članak je na hrvatskom, citat ostaje izvorni (blok), prijevod nikad u navodnicima; izjavu prepričaj.
V14 Jedna kategorija iz popisa: ${CATEGORIES.join(', ')} (tema glavne tvrdnje; kod dvojbe prva po redu).`;

export interface WriteSpeaker {
  label: string;
  name: string | null;
  role: string | null;
}

export interface WriteMomentInput {
  /** Oznaka u promptu (1…n), redom snimke. */
  n: number;
  speaker: string;
  speakerName: string | null;
  startMs: number;
  score: number;
  quote: string;
  quoteLang: string;
  claim: string | null;
  entities: string[];
}

export interface WritePromptInput {
  title: string | null;
  channelName: string | null;
  date: string | null;
  lang: string;
  speakers: WriteSpeaker[];
  moments: WriteMomentInput[];
}

/** Zaglavlje trenutka: `[t3 SPEAKER_01 00:12:34 ocjena 0.713]`. */
export const WRITE_MOMENT_LINE_RE = /^\[t(\d+) (\S+) (\d{2}:\d{2}:\d{2}) ocjena (\d(?:\.\d+)?)\]$/;

export function buildWritePrompt(input: WritePromptInput): string {
  const speakers =
    input.speakers.length === 0
      ? '(nepoznati)'
      : input.speakers
          .map((s) => `- ${s.label}: ${s.name ?? 'ime nepoznato'}${s.role ? ` (${s.role})` : ''}`)
          .join('\n');
  const moments = input.moments
    .map((m) =>
      [
        `[t${String(m.n)} ${m.speaker} ${hms(m.startMs)} ocjena ${m.score.toFixed(3)}]`,
        `Govornik: ${m.speakerName ?? 'ime nepoznato'}`,
        `Citat (${m.quoteLang}): „${m.quote}”`,
        ...(m.claim ? [`Tvrdnja: ${m.claim}`] : []),
        ...(m.entities.length > 0 ? [`Entiteti: ${m.entities.join(', ')}`] : []),
      ].join('\n'),
    )
    .join('\n\n');
  return `Epizoda: ${input.title ?? '(bez naslova)'}
Kanal: ${input.channelName ?? '(nepoznat)'}
Datum: ${input.date ?? '(nepoznat)'}
Jezik snimke: ${input.lang}

Govornici:
${speakers}

Zadatak: napiši vijest po pravilima V1–V14 iz trenutaka ispod (najvažniji imaju najveću ocjenu).
Vrati JSON: title, lead, body (niz blokova {"type":"p","text":…} i {"type":"quote","moment":N}), category.
Citat je samo blok s brojem trenutka; ne navodi brojeve trenutaka koji ne postoje.

Trenuci (redom snimke):
${moments}
`;
}

// Konačna ocjena je deterministička funkcija sastavnica (odluka 310). Model
// daje sudove 0–1, kod ih spaja s obilježjima i uparenom osobom. Promjena
// težina = novi FORMULA_VERSION (ide u `moments.score_version`).
import { concreteFeatureScore, type ConcreteFeatures } from './features.js';
import { PROMPT_VERSION, type MomentScore } from './prompt.js';

export const FORMULA_VERSION = 'f1';
export const SCORE_VERSION = `${PROMPT_VERSION}+${FORMULA_VERSION}`;

/** Novost i konkretnost nose 85 %, govornik je bonus. */
export const WEIGHTS = { novelty: 0.45, concreteness: 0.4, speaker: 0.15 } as const;
/** Konkretnost: sud modela i zatvoreni popisi obilježja. */
export const CONCRETE_MIX = { llm: 0.6, features: 0.4 } as const;
/** Govornik: sud modela (javna uloga iz konteksta) i katalog osoba. */
export const SPEAKER_MIX = { llm: 0.5, person: 0.5 } as const;
/** Osoba iz kataloga na ovoliko kanala dobiva punu katalošku ocjenu. */
export const PERSON_FULL_CHANNELS = 5;

export interface CatalogPerson {
  slug: string;
  name: string;
  episodes: number;
  channels: number;
}

const r3 = (n: number) => Math.round(n * 1000) / 1000;

/** 0 bez osobe; uparena osoba 0,5 + do 0,5 po broju kanala na kojima govori. */
export function personScore(p: CatalogPerson | null): number {
  if (!p) return 0;
  return r3(0.5 + 0.5 * Math.min(1, p.channels / PERSON_FULL_CHANNELS));
}

export interface ScoreParts {
  novelty: number;
  concreteness: number;
  speaker: number;
  llm: { novelty: number; concreteness: number; speaker: number };
  features: ConcreteFeatures & { score: number };
  person: (CatalogPerson & { score: number }) | null;
  speaker_name: string | null;
  public_role: string | null;
  weights: typeof WEIGHTS;
}

export function combineScore(
  llm: Pick<MomentScore, 'novelty' | 'concreteness' | 'speaker' | 'public_role'>,
  features: ConcreteFeatures,
  person: CatalogPerson | null,
  speakerName: string | null,
): { score: number; parts: ScoreParts } {
  for (const k of ['novelty', 'concreteness', 'speaker'] as const) {
    const v = llm[k];
    if (!Number.isFinite(v) || v < 0 || v > 1) throw new RangeError(`${k} izvan 0–1: ${String(v)}`);
  }
  const f = concreteFeatureScore(features);
  const ps = personScore(person);
  const novelty = r3(llm.novelty);
  const concreteness = r3(CONCRETE_MIX.llm * llm.concreteness + CONCRETE_MIX.features * f);
  const speaker = r3(SPEAKER_MIX.llm * llm.speaker + SPEAKER_MIX.person * ps);
  const score = r3(
    Math.min(1, WEIGHTS.novelty * novelty + WEIGHTS.concreteness * concreteness + WEIGHTS.speaker * speaker),
  );
  return {
    score,
    parts: {
      novelty,
      concreteness,
      speaker,
      llm: { novelty: llm.novelty, concreteness: llm.concreteness, speaker: llm.speaker },
      features: { ...features, score: f },
      person: person ? { ...person, score: ps } : null,
      speaker_name: speakerName,
      public_role: llm.public_role,
      weights: WEIGHTS,
    },
  };
}

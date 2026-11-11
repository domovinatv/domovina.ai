// Čista logika uredničkog ekrana (S8 redizajn): koji je JEDAN sljedeći korak i
// zašto je blokiran, i kako se rečenice provjere smještaju u tekst članka.
// Bez DOM-a, pa se testira u vitestu (`flow.test.ts`).
import { pendingSentences, type ArticleBundle, type SentenceCheck, type Status } from './api.js';

/** Koraci na traci; ispravak i povlačenje su grane objavljenog članka. */
export const STEPS = [
  { key: 'draft', label: 'Nacrt' },
  { key: 'review', label: 'U pregledu' },
  { key: 'approved', label: 'Odobreno' },
  { key: 'published', label: 'Objavljeno' },
] as const;

export type StepKey = (typeof STEPS)[number]['key'];

/** Na kojem je koraku trake članak; `null` = izvan toka (odbijen, povučen). */
export function stepOf(status: Status): StepKey | null {
  if (status === 'corrected') return 'published';
  if (status === 'rejected' || status === 'retracted') return null;
  return status;
}

export type NextAction = 'to-review' | 'approve' | 'publish' | 'to-draft';

export type Blocker =
  /** Zadnja verzija nema automatsku provjeru (npr. spremljena u adminu). */
  | { kind: 'verify'; version: number; byEditor: boolean }
  /** Rečenice bez potpore koje urednik još nije potvrdio. */
  | { kind: 'sentences'; count: number; first: number };

export interface NextStep {
  /** Radnja glavnog gumba; `null` = nema sljedećeg koraka (objavljeno, povučeno). */
  action: NextAction | null;
  label: string;
  /** Zašto se glavni gumb ne može pritisnuti (prazno = može). */
  blockers: Blocker[];
  /** Jedna rečenica o tome što slijedi nakon ovog koraka. */
  hint: string;
}

/** Blokade odobravanja zadnje verzije (iste koje `approve_article` provjerava). */
export function approvalBlockers(b: Pick<ArticleBundle, 'latest' | 'resolutions'>): Blocker[] {
  if (!b.latest.verify) {
    return [{ kind: 'verify', version: b.latest.version, byEditor: (b.latest.created_by ?? '').startsWith('editor:') }];
  }
  const pending = pendingSentences(b.latest, b.resolutions);
  const first = pending[0];
  return first ? [{ kind: 'sentences', count: pending.length, first: first.n }] : [];
}

export function nextStep(b: Pick<ArticleBundle, 'article' | 'latest' | 'resolutions'>): NextStep {
  const blockers = approvalBlockers(b);
  switch (b.article.status) {
    case 'draft':
      return {
        action: 'to-review',
        label: 'Pošalji u pregled',
        blockers: [],
        hint:
          blockers.length === 0
            ? 'U pregledu članak odobravaš, a zatim objavljuješ.'
            : `Prije odobravanja: ${blockerText(blockers[0])}. Rečenice možeš potvrditi već sada.`,
      };
    case 'review':
      return {
        action: 'approve',
        label: `Odobri v${String(b.latest.version)}`,
        blockers,
        hint: 'Odobrena verzija se objavljuje u sljedećem koraku.',
      };
    case 'approved':
      return { action: 'publish', label: 'Objavi', blockers: [], hint: 'Objava je javna odmah, na domovina.ai/vijesti.' };
    case 'rejected':
      return { action: 'to-draft', label: 'Vrati u nacrt', blockers: [], hint: 'Odbijen članak nije javan.' };
    default:
      return { action: null, label: '', blockers: [], hint: '' };
  }
}

/** Razlog blokade kao dio rečenice („2 rečenice čekaju potvrdu”). */
export function blockerText(b: Blocker | undefined): string {
  if (!b) return '';
  if (b.kind === 'verify') {
    return `verzija v${String(b.version)} čeka automatsku provjeru`;
  }
  return `${String(b.count)} ${plural(b.count, 'rečenica čeka', 'rečenice čekaju', 'rečenica čeka')} potvrdu`;
}

/** Hrvatski plural: 1 rečenica, 2–4 rečenice, 5+ rečenica (11–14 = „rečenica”). */
export function plural(n: number, one: string, few: string, many: string): string {
  const d = n % 10;
  const dd = n % 100;
  if (d === 1 && dd !== 11) return one;
  if (d >= 2 && d <= 4 && (dd < 12 || dd > 14)) return few;
  return many;
}

const PROBLEM_TEXT: Record<string, string> = {
  low_overlap: 'malo zajedničkih riječi s izvornim trenutkom',
  llm_unsupported: 'provjera nije našla potporu u snimci',
  verifier_omitted: 'provjera je preskočila ovu rečenicu',
  unknown_moment_ref: 'poziva se na trenutak koji ne postoji',
  quote_not_verbatim: 'citat nije doslovno iz snimke',
  quote_ref_missing: 'citat bez izvornog trenutka',
  quote_ref_not_source: 'citat nije iz izvora članka',
};

/** Zašto rečenica nema potporu, ljudskim riječima (detalj ostaje u zagradi). */
export function problemText(p: { code: string; detail?: string }): string {
  if (p.code === 'unknown_name' || p.code === 'unknown_number') return p.detail ?? p.code;
  const base = PROBLEM_TEXT[p.code];
  if (!base) return p.detail ?? p.code;
  return p.code === 'llm_unsupported' && p.detail ? `${base}: ${p.detail}` : base;
}

export type Segment = { kind: 'text'; text: string } | { kind: 'sentence'; sentence: SentenceCheck };

/**
 * Tekst odlomka razlomljen na rečenice provjere, redom. Rečenica koja se ne
 * nađe doslovno (`null`) znači da se tekst i provjera ne poklapaju: odlomak se
 * tada crta kao običan tekst, a rečenice ispod njega.
 */
export function segmentText(text: string, sentences: readonly SentenceCheck[]): Segment[] | null {
  const out: Segment[] = [];
  let pos = 0;
  for (const s of sentences) {
    const i = text.indexOf(s.text, pos);
    if (i < 0) return null;
    if (i > pos) out.push({ kind: 'text', text: text.slice(pos, i) });
    out.push({ kind: 'sentence', sentence: s });
    pos = i + s.text.length;
  }
  if (pos < text.length) out.push({ kind: 'text', text: text.slice(pos) });
  return out;
}

/** Rečenice provjere po mjestu u članku: `title`, `lead`, `block:<i>`. */
export function sentencesByPlace(sentences: readonly SentenceCheck[]): Map<string, SentenceCheck[]> {
  const m = new Map<string, SentenceCheck[]>();
  for (const s of sentences) {
    const key = s.part === 'block' ? `block:${String(s.block ?? -1)}` : s.part;
    const list = m.get(key) ?? [];
    list.push(s);
    m.set(key, list);
  }
  return m;
}

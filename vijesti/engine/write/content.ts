// Strukturirani sadržaj verzije članka (`article_versions.content`, migracija
// 005). Citat je REFERENCA na `moments.id`; tekst citata pri prikazu dolazi iz
// `moments.quote` (odluka 417), pa se `body` i broj riječi računaju iz
// sadržaja i trenutaka, nikad iz teksta koji je napisao model.
import { clock, wordCount } from './text.js';

export const CONTENT_SCHEMA = 1;

export interface EpisodeMeta {
  videoId: string;
  title: string | null;
  /** Slug kanala iz listinga. */
  channel: string | null;
  channelName: string | null;
  /** Datum objave iz listinga (`YYYY-MM-DD`). */
  date: string | null;
  /** Jezik snimke (`moments.quote_lang`). */
  lang: string;
  speakers: { label: string; name: string | null; role: string | null }[];
}

export type ContentBlock =
  | { type: 'p'; text: string }
  /** `ref` je oznaka iz prompta (`t3`); `moment_id` je NULL kad trenutak ne postoji. */
  | { type: 'quote'; moment_id: number | null; ref: string };

export interface ArticleContent {
  schema: typeof CONTENT_SCHEMA;
  episode: EpisodeMeta;
  title: string;
  lead: string;
  category: string;
  blocks: ContentBlock[];
}

/** Trenutak na koji se verzija poziva (`article_sources` + `moments`). */
export interface SourceMoment {
  id: number;
  /** `article_sources.position` = broj iza „t” u promptu. */
  position: number;
  videoId: string;
  startMs: number;
  speaker: string;
  speakerName: string | null;
  quote: string;
  quoteLang: string;
  claim: string | null;
  entities: string[];
  score: number | null;
}

/** `„…” – Ime, 12:34` (+ jezik izvornika kad nije hrvatski). */
export function renderQuote(m: SourceMoment): string {
  const lang = m.quoteLang === 'hr' ? '' : ` (izvornik, ${m.quoteLang})`;
  return `„${m.quote}” – ${m.speakerName ?? m.speaker}, ${clock(m.startMs)}${lang}`;
}

/** Čitljiv tekst za `article_versions.body`: odlomci i citati, prazan redak između. */
export function renderBody(blocks: readonly ContentBlock[], byId: ReadonlyMap<number, SourceMoment>): string {
  return blocks
    .map((b) => {
      if (b.type === 'p') return b.text;
      const m = b.moment_id === null ? undefined : byId.get(b.moment_id);
      return m ? renderQuote(m) : `[citat ${b.ref}: trenutak ne postoji]`;
    })
    .join('\n\n');
}

/** Riječi leada, odlomaka i citata kako se prikazuju (V10); naslov ne ulazi. */
export function articleWordCount(
  content: Pick<ArticleContent, 'lead' | 'blocks'>,
  byId: ReadonlyMap<number, SourceMoment>,
): number {
  let n = wordCount(content.lead);
  for (const b of content.blocks) {
    if (b.type === 'p') n += wordCount(b.text);
    else if (b.moment_id !== null) n += wordCount(byId.get(b.moment_id)?.quote ?? '');
  }
  return n;
}

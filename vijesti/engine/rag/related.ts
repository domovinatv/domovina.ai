// „O istoj temi u drugim podcastima” iz RAG-a (domovina-rag, odluka 803).
// `mcp.domovina.ai/api/search` je hibridna pretraga nad `rag_chunks`
// (ClickHouse, embedding + HNSW) cijelog kataloga, koju pipeline puni svaku
// noć. Bez LLM poziva: upit je naslov + uvod članka, a pogodak je TEMA druge
// epizode s linkom na sekundu. Citati se odavde NIKAD ne uzimaju: izvor citata
// i vremena ostaje CDN (`words.json`/SRT, odluke 202–206).
import { z } from 'zod';
import type { FetchLike } from '../cdn/loader.js';

export const RAG_SEARCH_URL = 'https://mcp.domovina.ai/api/search';
/** Kosinusna sličnost ispod koje pogodak nije ista tema (izmjereno 11.11.: EU-INC → HNB 0,67). */
export const RELATED_MIN_SCORE = 0.6;
export const RELATED_MAX = 3;
/** Koliko tema s vremenom smije biti slabija od sažetka iste epizode (0,637 vs 0,62, 11.11.). */
export const RELATED_TIMED_SLACK = 0.03;

export interface RelatedItem {
  videoId: string;
  /** Sekunda početka teme; 0 za sažetak cijele epizode. */
  t: number;
  channel: string;
  episodeTitle: string;
  /** Prvi redak chunka bez oznake („Tema:”/„Naslov:”). */
  topic: string;
  date: string | null;
  score: number;
}

const Hit = z.object({
  youtube_id: z.string(),
  channel: z.string(),
  episode_title: z.string().nullable().optional(),
  upload_date: z.string().nullable().optional(),
  start_ts: z.coerce.number(),
  text: z.string(),
  score: z.coerce.number(),
});
const SearchResponse = z.object({ results: z.array(z.unknown()).optional(), hits: z.array(z.unknown()).optional() });

export function topicLine(text: string): string {
  const first = text.split('\n').find((l) => l.trim() !== '') ?? '';
  return first.replace(/^(Tema|Naslov|Topic|Title):\s*/i, '').trim();
}

export interface RelatedOptions {
  fetch: FetchLike;
  query: string;
  excludeVideoId: string;
  url?: string;
  max?: number;
  minScore?: number;
}

/** Najviše `max` drugih epizoda (jedna po epizodi, najbolji chunk), iznad praga. */
export async function findRelated(opts: RelatedOptions): Promise<RelatedItem[]> {
  const url = new URL(opts.url ?? RAG_SEARCH_URL);
  url.searchParams.set('q', opts.query.slice(0, 500));
  url.searchParams.set('limit', '20');
  url.searchParams.set('include_summaries', 'true');
  const res = await opts.fetch(url.toString(), { headers: { accept: 'application/json' } });
  if (!res.ok) throw new Error(`RAG pretraga: HTTP ${String(res.status)}`);
  const body = SearchResponse.parse(JSON.parse(await res.text()));
  const raw = body.results ?? body.hits ?? [];
  const best = new Map<string, RelatedItem>();
  for (const r of raw) {
    const h = Hit.safeParse(r);
    if (!h.success) continue;
    const v = h.data;
    if (v.youtube_id === opts.excludeVideoId || v.score < (opts.minScore ?? RELATED_MIN_SCORE)) continue;
    const item: RelatedItem = {
      videoId: v.youtube_id,
      t: Math.max(0, Math.floor(v.start_ts)),
      channel: v.channel,
      episodeTitle: v.episode_title ?? '',
      topic: topicLine(v.text),
      date: v.upload_date ?? null,
      score: Math.round(v.score * 1000) / 1000,
    };
    const prev = best.get(v.youtube_id);
    if (!prev) best.set(v.youtube_id, item);
    else if (prev.t === 0 && item.t > 0 && prev.score - item.score <= RELATED_TIMED_SLACK) {
      // Sažetak epizode (t = 0) vodi na početak; tema s vremenom blizu po sličnosti vodi
      // na pravu sekundu. Rezultat ostaje sažetkov (bolji), sekunda i tema od teme.
      best.set(v.youtube_id, { ...item, score: prev.score });
    } else if (item.score > prev.score && !(prev.t > 0 && item.t === 0 && item.score - prev.score <= RELATED_TIMED_SLACK)) {
      best.set(v.youtube_id, item);
    }
  }
  return [...best.values()].sort((a, b) => b.score - a.score).slice(0, opts.max ?? RELATED_MAX);
}

// Kontekst za „novost” (odluka 307): naslov i ključne točke zadnjih N ranijih
// epizoda istog kanala (summary.json, inače listing) i već izdvojene tvrdnje
// ranijih epizoda tog kanala iz baze. „Ranije” = strogo raniji datum u
// listingu; epizoda bez datuma nema ranijih (ne nagađa se).
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import type { ChannelListing } from '../cdn/schemas.js';
import type { PriorEpisode, PriorMoment } from './prompt.js';

export const DEFAULT_PRIOR_EPISODES = 8;
export const DEFAULT_PRIOR_MOMENTS = 40;
const MAX_POINTS = 6;
const MAX_ABSTRACT = 400;

export interface ChannelRef {
  slug: string;
  listing: ChannelListing;
}

/** Kanal epizode iz listinga (odluka 112). Uz `hint` se traži samo taj kanal. */
export async function findChannel(cdn: CdnClient, videoId: string, hint?: string): Promise<ChannelRef | null> {
  if (hint) {
    const listing = await cdn.channel(hint);
    if (!listing) throw new Error(`kanal ${hint} ne postoji na CDN-u`);
    if (!listing.videos.some((v) => v.id === videoId)) {
      throw new Error(`epizoda ${videoId} nije u listingu kanala ${hint}`);
    }
    return { slug: hint, listing };
  }
  const index = await cdn.channelIndex();
  for (const ch of index.channels) {
    const listing = await cdn.channel(ch.id);
    if (listing?.videos.some((v) => v.id === videoId)) return { slug: ch.id, listing };
  }
  return null;
}

export interface NoveltyContext {
  date: string | null;
  prior: PriorEpisode[];
  priorMoments: PriorMoment[];
  /** Odakle su točke ranijih epizoda. */
  sources: { summary: number; listing: number };
}

export async function buildNoveltyContext(
  deps: { cdn: CdnClient; db: SqlDb },
  opts: { videoId: string; listing: ChannelListing | null; priorEpisodes?: number; priorMoments?: number },
): Promise<NoveltyContext> {
  const { listing, videoId } = opts;
  const date = listing?.videos.find((v) => v.id === videoId)?.date ?? null;
  const empty: NoveltyContext = { date, prior: [], priorMoments: [], sources: { summary: 0, listing: 0 } };
  if (!listing || !date) return empty;
  const earlier = listing.videos
    .filter((v) => v.id !== videoId && typeof v.date === 'string' && v.date < date)
    .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '') || a.id.localeCompare(b.id));

  const prior: PriorEpisode[] = [];
  const sources = { summary: 0, listing: 0 };
  for (const v of earlier.slice(0, opts.priorEpisodes ?? DEFAULT_PRIOR_EPISODES)) {
    const s = await deps.cdn.summary(v.id);
    if (s) {
      sources.summary++;
      prior.push({
        videoId: v.id,
        date: v.date ?? null,
        title: s.summary.title_hr || v.title_hr || v.title,
        points: s.summary.key_points.slice(0, MAX_POINTS),
      });
    } else {
      sources.listing++;
      const abs = v.abstract?.trim();
      prior.push({
        videoId: v.id,
        date: v.date ?? null,
        title: v.title_hr ?? v.title,
        points: abs ? [abs.length > MAX_ABSTRACT ? `${abs.slice(0, MAX_ABSTRACT)}…` : abs] : [],
      });
    }
  }

  const dates = new Map(earlier.map((v) => [v.id, v.date ?? null]));
  let priorMoments: PriorMoment[] = [];
  if (dates.size > 0) {
    const res = await deps.db.query<{ video_id: string; claim: string }>(
      `SELECT video_id, claim FROM vijesti.moments
       WHERE video_id = ANY($1::text[]) AND quote_check <> 'failed'
         AND claim IS NOT NULL AND length(btrim(claim)) > 0
       ORDER BY video_id, start_ms, id`,
      [[...dates.keys()]],
    );
    priorMoments = res.rows
      .map((r) => ({ date: dates.get(r.video_id) ?? null, claim: r.claim }))
      // Najnovije prvo; unutar epizode redom kao u snimci (sort je stabilan).
      .sort((a, b) => (b.date ?? '').localeCompare(a.date ?? ''))
      .slice(0, opts.priorMoments ?? DEFAULT_PRIOR_MOMENTS);
  }
  return { date, prior, priorMoments, sources };
}

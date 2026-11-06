// Uzorak epizoda za mjerenje F0 (odluka 405): po kanalu pola svježih, pola
// starijih, prednost epizodama s `words.json`, deterministički (isti listing
// daje isti uzorak). Uz uzorak i dotok: epizode u zadnjih 30 dana po kanalu.
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import type { ListingVideo } from '../cdn/schemas.js';

export type Pick = 'fresh' | 'older';

export interface SampledEpisode {
  videoId: string;
  channel: string;
  /** `YYYY-MM-DD` iz listinga ili null. */
  date: string | null;
  hasWords: boolean;
  pick: Pick;
}

export interface ChannelInflow {
  channel: string;
  name: string | null;
  /** Epizoda u listingu. */
  listed: number;
  /** Epizoda s datumom u (windowEnd − 30 dana, windowEnd]. */
  episodes30d: number;
  windowEnd: string;
}

export interface SampleRejection {
  videoId: string;
  channel: string;
  reason: string;
}

export interface ChannelSample {
  episodes: SampledEpisode[];
  inflow: ChannelInflow;
  rejected: SampleRejection[];
}

export const INFLOW_DAYS = 30;
const WORDS_RE = /^words(\.[a-z]{2})?\.json$/;

export function isoDay(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function byDateDesc(a: ListingVideo, b: ListingVideo): number {
  const da = a.date ?? '';
  const db = b.date ?? '';
  if (da !== db) return da < db ? 1 : -1;
  return a.id < b.id ? -1 : a.id > b.id ? 1 : 0;
}

/** `count` indeksa ravnomjerno raspoređenih po `0..len-1`, bez ponavljanja, rastuće. */
export function spread(len: number, count: number): number[] {
  if (len <= 0 || count <= 0) return [];
  if (count >= len) return [...Array(len).keys()];
  const out = new Set<number>();
  for (let k = 0; k < count; k++) out.add(Math.floor((k * len) / count));
  return [...out];
}

export function countInflow(videos: readonly ListingVideo[], now: Date, days = INFLOW_DAYS): number {
  const end = isoDay(now);
  const start = isoDay(new Date(now.getTime() - days * 86_400_000));
  return videos.filter((v) => v.date != null && v.date > start && v.date <= end).length;
}

interface Probe {
  srt: boolean;
  words: boolean;
}

async function probe(cdn: CdnClient, id: string): Promise<Probe> {
  const bundle = await cdn.bundle(id);
  if (bundle) {
    return { srt: bundle.files.includes('diarized.srt'), words: bundle.files.some((f) => WORDS_RE.test(f)) };
  }
  // Stari katalog bez episode.json: datoteku po datoteku.
  return { srt: await cdn.has(id, 'diarized.srt'), words: await cdn.has(id, 'words.json') };
}

/**
 * Uzorak jednog kanala. Listing se slaže po datumu (najnovije prvo, pa ID);
 * svježa polovica daje `ceil(limit/2)` epizoda iz najnovijih kandidata, starija
 * polovica ostatak iz ravnomjerno raspoređenih kandidata. Kandidata je dvaput
 * više nego mjesta; među njima `words.json` ide prvi, inače redoslijed listinga.
 * Kad jedna polovica nema dosta, ostatak se puni iz druge.
 */
export async function sampleChannel(
  cdn: CdnClient,
  slug: string,
  opts: { limit: number; now: Date },
): Promise<ChannelSample> {
  const listing = await cdn.channel(slug);
  if (!listing) throw new Error(`kanal ${slug} ne postoji na CDN-u`);
  const sorted = [...listing.videos].sort(byDateDesc);
  const inflow: ChannelInflow = {
    channel: slug,
    name: listing.name,
    listed: sorted.length,
    episodes30d: countInflow(sorted, opts.now),
    windowEnd: isoDay(opts.now),
  };
  const nFresh = Math.ceil(opts.limit / 2);
  const nOld = opts.limit - nFresh;
  const split = Math.ceil(sorted.length / 2);
  const freshHalf = sorted.slice(0, split);
  const olderHalf = sorted.slice(split);
  const freshCand = freshHalf.slice(0, 2 * nFresh);
  const olderCand = spread(olderHalf.length, 2 * Math.max(nOld, 1)).flatMap((i) => olderHalf[i] ?? []);

  const rejected: SampleRejection[] = [];
  const eligible = async (cands: ListingVideo[], pick: Pick): Promise<SampledEpisode[]> => {
    const out: SampledEpisode[] = [];
    for (const v of cands) {
      const p = await probe(cdn, v.id);
      if (!p.srt) {
        rejected.push({ videoId: v.id, channel: slug, reason: 'nema diarized.srt' });
        continue;
      }
      out.push({ videoId: v.id, channel: slug, date: v.date ?? null, hasWords: p.words, pick });
    }
    // Stabilno: words.json prvi, unutar toga redoslijed kandidata.
    return [...out.filter((e) => e.hasWords), ...out.filter((e) => !e.hasWords)];
  };
  const fresh = await eligible(freshCand, 'fresh');
  const older = await eligible(olderCand, 'older');
  const chosen = [...fresh.slice(0, nFresh), ...older.slice(0, nOld)];
  const rest = [...fresh.slice(nFresh), ...older.slice(nOld)];
  while (chosen.length < opts.limit && rest.length > 0) {
    const next = rest.shift();
    if (next) chosen.push(next);
  }
  return { episodes: chosen, inflow, rejected };
}

/** Redoslijed obrade: kanal, pa starije prvo (kontekst novosti čita ranije epizode iz baze, odluka 307). */
export function processingOrder(eps: readonly SampledEpisode[]): SampledEpisode[] {
  return [...eps].sort(
    (a, b) =>
      a.channel.localeCompare(b.channel) ||
      (a.date ?? '').localeCompare(b.date ?? '') ||
      a.videoId.localeCompare(b.videoId),
  );
}

interface SampleRow {
  video_id: string;
  channel: string;
  episode_date: string | Date | null;
  has_words: boolean;
  pick: Pick;
}

interface InflowRow {
  channel: string;
  name: string | null;
  listed: number;
  episodes_30d: number;
  window_end: string | Date;
}

function day(v: string | Date | null): string | null {
  if (v === null) return null;
  return typeof v === 'string' ? v.slice(0, 10) : isoDay(v);
}

/** Spremljen uzorak kanala (nastavak, odluka 407) ili null. */
export async function loadChannelSample(db: SqlDb, slug: string): Promise<ChannelSample | null> {
  const eps = await db.query<SampleRow>(
    `SELECT video_id, channel, to_char(episode_date, 'YYYY-MM-DD') AS episode_date, has_words, pick
     FROM vijesti.eval_sample WHERE channel = $1 ORDER BY episode_date NULLS FIRST, video_id`,
    [slug],
  );
  if (eps.rows.length === 0) return null;
  const inf = await db.query<InflowRow>(
    `SELECT channel, name, listed, episodes_30d, to_char(window_end, 'YYYY-MM-DD') AS window_end
     FROM vijesti.eval_channels WHERE channel = $1`,
    [slug],
  );
  const i = inf.rows[0];
  return {
    episodes: eps.rows.map((r) => ({
      videoId: r.video_id,
      channel: r.channel,
      date: day(r.episode_date),
      hasWords: r.has_words,
      pick: r.pick,
    })),
    inflow: i
      ? { channel: i.channel, name: i.name, listed: i.listed, episodes30d: i.episodes_30d, windowEnd: day(i.window_end) ?? '' }
      : { channel: slug, name: null, listed: 0, episodes30d: 0, windowEnd: '' },
    rejected: [],
  };
}

/** Zamijeni spremljeni uzorak kanala (prvi put ili `--resample`). */
export async function saveChannelSample(db: SqlDb, sample: ChannelSample): Promise<void> {
  const slug = sample.inflow.channel;
  await db.exec('BEGIN');
  try {
    await db.query('DELETE FROM vijesti.eval_sample WHERE channel = $1', [slug]);
    for (const e of sample.episodes) {
      await db.query(
        `INSERT INTO vijesti.eval_sample (video_id, channel, episode_date, has_words, pick)
         VALUES ($1, $2, $3, $4, $5)
         ON CONFLICT (video_id) DO UPDATE SET channel = EXCLUDED.channel, episode_date = EXCLUDED.episode_date,
           has_words = EXCLUDED.has_words, pick = EXCLUDED.pick, sampled_at = now()`,
        [e.videoId, e.channel, e.date, e.hasWords, e.pick],
      );
    }
    const i = sample.inflow;
    await db.query(
      `INSERT INTO vijesti.eval_channels (channel, name, listed, episodes_30d, window_end)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (channel) DO UPDATE SET name = EXCLUDED.name, listed = EXCLUDED.listed,
         episodes_30d = EXCLUDED.episodes_30d, window_end = EXCLUDED.window_end, measured_at = now()`,
      [i.channel, i.name, i.listed, i.episodes30d, i.windowEnd],
    );
    await db.exec('COMMIT');
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

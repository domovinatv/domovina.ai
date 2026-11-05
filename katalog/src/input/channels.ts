// `channels/data/index.json` i `channels/data/<slug>.json`.
// Oblik: docs/research/2026-11-05-oblik-ulaza.md. Klijentski ugovor:
// `ChannelSummary`/`ChannelDetail`/`ChannelVideo` u packages/podcast_core.
import { InputError } from "./errors.ts";
import { flagsFromPipeline, PIPELINE_BITS, type PipelineBit, type PipelineFlags } from "./pipeline-bits.ts";
import {
  asObject,
  at,
  index,
  type JsonObject,
  optBoolean,
  optCount,
  optIsoDate,
  optNonNegative,
  optObject,
  optScore,
  optString,
  optTimestamp,
  reqArray,
  reqString,
  ROOT,
} from "./read.ts";

/** Polja zaglavlja kanala zajednička `index.json` unosu i listingu. */
export interface ChannelHeader {
  /** `id` u ulazu; ključ kanala u URL-u (`/c/:slug`) i u D1. */
  readonly slug: string;
  readonly name: string;
  readonly avatarSquare: string | null;
  /** Nije nužno YouTube: `dijalog` ima Spotify URL. */
  readonly youtubeChannelUrl: string | null;
  /** Izveden samo iz URL-a oblika `youtube.com/channel/UC…`, inače `null`. Nije jedinstven. */
  readonly youtubeChannelId: string | null;
  readonly youtubePlaylistUrl: string | null;
  /** `video_count` kako ga je pipeline izbrojio; listing u fixtureu je skraćen, pa ≠ `videos.length`. */
  readonly videoCount: number | null;
}

export interface ChannelSummary extends ChannelHeader {
  /** `latest_video.date` (index nema `latest_video_date`). */
  readonly latestVideoDate: string | null;
}

export interface ChannelIndex {
  readonly generatedAt: string | null;
  readonly channels: readonly ChannelSummary[];
}

export interface ListingVideo {
  /** ID epizode; YouTube ID, ali ne nužno (`dijalog`: 11 hex znakova). */
  readonly id: string;
  readonly title: string;
  readonly titleHr: string | null;
  readonly date: string | null;
  readonly durationSeconds: number | null;
  readonly magisteriumScore: number | null;
  /** `null` kad listing nema `pipeline` objekt; tada je `flags` 0. */
  readonly pipeline: PipelineFlags | null;
  /** Bitmaska po `PIPELINE_BITS`, kao `p` u `home.json`. */
  readonly flags: number;
}

export interface ChannelListing extends ChannelHeader {
  readonly generatedAt: string | null;
  readonly latestVideoDate: string | null;
  readonly videos: readonly ListingVideo[];
}

const YOUTUBE_HOSTS = new Set(["youtube.com", "www.youtube.com", "m.youtube.com"]);
const CHANNEL_PATH = /^\/channel\/(UC[0-9A-Za-z_-]{22})(?:\/|$)/;

/** `https://www.youtube.com/channel/UC…` → `UC…`; sve ostalo (Spotify, `@handle`, playlist) → `null`. */
export function youtubeChannelIdFromUrl(url: string | null): string | null {
  if (url === null) return null;
  let u: URL;
  try {
    u = new URL(url);
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || !YOUTUBE_HOSTS.has(u.hostname)) return null;
  return CHANNEL_PATH.exec(u.pathname)?.[1] ?? null;
}

function readHeader(o: JsonObject, path: string): ChannelHeader {
  const youtubeChannelUrl = optString(o, "youtube_channel_url", path);
  return {
    slug: reqString(o, "id", path),
    name: reqString(o, "name", path),
    avatarSquare: optString(o, "avatar_square", path),
    youtubeChannelUrl,
    youtubeChannelId: youtubeChannelIdFromUrl(youtubeChannelUrl),
    youtubePlaylistUrl: optString(o, "youtube_playlist_url", path),
    videoCount: optCount(o, "video_count", path),
  };
}

function readSummary(value: unknown, path: string): ChannelSummary {
  const o = asObject(value, path);
  const latest = optObject(o, "latest_video", path);
  return {
    ...readHeader(o, path),
    latestVideoDate: latest === null ? null : optIsoDate(latest, "date", at(path, "latest_video")),
  };
}

export function parseChannelIndex(raw: unknown): ChannelIndex {
  const o = asObject(raw, ROOT);
  const list = reqArray(o, "channels", ROOT);
  const seen = new Set<string>();
  const channels = list.map((c, i) => {
    const path = index("channels", i);
    const summary = readSummary(c, path);
    if (seen.has(summary.slug)) throw new InputError(at(path, "id"), `kanal se ponavlja: ${summary.slug}`);
    seen.add(summary.slug);
    return summary;
  });
  return { generatedAt: optTimestamp(o, "generated_at", ROOT), channels };
}

function readPipeline(o: JsonObject, path: string): PipelineFlags | null {
  const p = optObject(o, "pipeline", path);
  if (p === null) return null;
  const pPath = at(path, "pipeline");
  const flags = {} as Record<PipelineBit, boolean>;
  // Zastavica koja nedostaje nije podignuta (izostanak nije informacija);
  // nepoznate ključeve (nova zastavica na kraju ugovora) preskačemo.
  for (const bit of PIPELINE_BITS) flags[bit] = optBoolean(p, bit, pPath) ?? false;
  return flags;
}

function readVideo(value: unknown, path: string): ListingVideo {
  const o = asObject(value, path);
  const pipeline = readPipeline(o, path);
  return {
    id: reqString(o, "id", path),
    title: reqString(o, "title", path),
    titleHr: optString(o, "title_hr", path),
    date: optIsoDate(o, "date", path),
    durationSeconds: optNonNegative(o, "duration_seconds", path),
    magisteriumScore: optScore(o, "magisterium_score", path),
    pipeline,
    flags: pipeline === null ? 0 : flagsFromPipeline(pipeline),
  };
}

export function parseChannelListing(raw: unknown): ChannelListing {
  const o = asObject(raw, ROOT);
  const seen = new Set<string>();
  const videos = reqArray(o, "videos", ROOT).map((v, i) => {
    const path = index("videos", i);
    const video = readVideo(v, path);
    if (seen.has(video.id)) throw new InputError(at(path, "id"), `epizoda se ponavlja: ${video.id}`);
    seen.add(video.id);
    return video;
  });
  return {
    ...readHeader(o, ROOT),
    generatedAt: optTimestamp(o, "generated_at", ROOT),
    latestVideoDate: optIsoDate(o, "latest_video_date", ROOT),
    videos,
  };
}

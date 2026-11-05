// Runtime sheme za datoteke s cdn.domovina.ai. Polja su provjerena na stvarnim
// datotekama 5.11.2026. (vidi docs/research/2026-11-05-oblik-cdn-datoteka.md).
// Nepoznata polja se odbacuju: engine čita samo ono što je ovdje navedeno.
import { z } from 'zod';

/** `data/<id>/info.json` je yt-dlp dump (~85 kB, većinom `formats`). Čitamo samo ovo. */
export const InfoSchema = z.object({
  id: z.string(),
  title: z.string(),
  duration: z.number().nonnegative(),
  description: z.string().nullish(),
  channel: z.string().nullish(),
  channel_id: z.string().nullish(),
  uploader: z.string().nullish(),
  upload_date: z.string().nullish(),
  timestamp: z.number().nullish(),
  webpage_url: z.string().nullish(),
  thumbnail: z.string().nullish(),
  tags: z.array(z.string()).nullish(),
  playable_in_embed: z.boolean().nullish(),
  chapters: z
    .array(z.object({ start_time: z.number(), end_time: z.number(), title: z.string() }))
    .nullish(),
});
export type Info = z.infer<typeof InfoSchema>;

export const SpeakerSchema = z.object({
  id: z.string(),
  suggested_name: z.string().nullish(),
  role: z.string().nullish(),
});
export type Speaker = z.infer<typeof SpeakerSchema>;

/** `data/<id>/summary.json`. `language` je jezik IZLAZA (uvijek "hr"), ne snimke. */
export const SummarySchema = z.object({
  version: z.string(),
  generated_at: z.string(),
  model: z.string().nullish(),
  source: z.object({
    channel: z.string(),
    youtube_id: z.string(),
    title: z.string(),
    upload_date: z.string().nullish(),
    duration_seconds: z.number().nullish(),
    platform: z.string().nullish(),
    source_url: z.string().nullish(),
  }),
  summary: z.object({
    title_hr: z.string(),
    abstract_hr: z.string(),
    key_topics: z.array(z.string()).default([]),
    speakers: z.array(SpeakerSchema).default([]),
    key_points: z.array(z.string()).default([]),
    mentioned_people: z.array(z.string()).default([]),
    mentioned_places: z.array(z.string()).default([]),
    mentioned_organizations: z.array(z.string()).default([]),
    language: z.string().nullish(),
    content_type: z.string().nullish(),
    sentiment: z.string().nullish(),
  }),
});
export type Summary = z.infer<typeof SummarySchema>;

/** `HH:MM:SS` kako ga piše pipeline u article/outline. */
const HmsSchema = z.string().regex(/^\d{2}:\d{2}:\d{2}$/);

export const ArticleSectionSchema = z.object({
  subtitle: z.string(),
  screenshot_timestamp: HmsSchema,
  screenshot_description: z.string().nullish(),
  content: z.string(),
  keywords: z.array(z.string()).default([]),
  entities: z.array(z.string()).default([]),
});
export type ArticleSection = z.infer<typeof ArticleSectionSchema>;

export const ArticleIterationSchema = z.object({
  iteration_number: z.number().int(),
  start_time: HmsSchema,
  end_time: HmsSchema,
  theme: z.string().nullish(),
  sections: z.array(ArticleSectionSchema),
});
export type ArticleIteration = z.infer<typeof ArticleIterationSchema>;

/** `data/<id>/article.json`: članak po iteracijama (~40 min) i sekcijama. */
export const ArticleSchema = z.object({
  metadata: z
    .object({
      source_file: z.string().nullish(),
      generated_at: z.string().nullish(),
      model: z.string().nullish(),
      iterations_expected: z.number().nullish(),
      complete: z.boolean().nullish(),
    })
    .nullish(),
  iterations: z.array(ArticleIterationSchema),
});
export type Article = z.infer<typeof ArticleSchema>;

/**
 * `data/<id>/episode.json` (v1): izmjereni popis datoteka pod `data/<id>/` i
 * sadržaj nekih od njih (`inline`). Nepoznata verzija je greška; klijent tada
 * ide datoteku po datoteku (vidi loader).
 */
export const EpisodeBundleSchema = z.object({
  version: z.literal(1),
  generated_at: z.string().nullish(),
  files: z.array(z.string()),
  inline: z.record(z.string(), z.unknown()).default({}),
});
export type EpisodeBundle = z.infer<typeof EpisodeBundleSchema>;

/**
 * `data/<id>/words.json` (i `words.<lang>.json`). `w` je ravan niz parova
 * (početak, kraj) u APSOLUTNIM ms po riječi, istim redom kao riječi teksta
 * cue-a. `a` je udio usidrenih riječi u tom cue-u (polje koje ugovor iz
 * 6.10.2026. ne spominje; postoji u svim datotekama koje smo vidjeli).
 */
export const WordsCueSchema = z
  .object({
    s: z.number().int(),
    e: z.number().int(),
    w: z.array(z.number()),
    a: z.number().min(0).max(1).optional(),
  })
  .refine((c) => c.w.length % 2 === 0, { message: 'w mora imati paran broj elemenata' });
export type WordsCue = z.infer<typeof WordsCueSchema>;

export const WordsFileSchema = z.object({
  v: z.literal(1),
  source: z.string(),
  anchored: z.number().min(0).max(1),
  cues: z.array(WordsCueSchema),
});
export type WordsFile = z.infer<typeof WordsFileSchema>;

export const ListingVideoSchema = z.object({
  id: z.string(),
  title: z.string(),
  title_hr: z.string().nullish(),
  date: z.string().nullish(),
  duration_seconds: z.number().nullish(),
  thumbnail: z.string().nullish(),
  youtube_url: z.string().nullish(),
  abstract: z.string().nullish(),
  topics: z.array(z.string()).nullish(),
  speakers: z.array(SpeakerSchema).nullish(),
  magisterium_score: z.number().nullish(),
  pipeline: z.record(z.string(), z.boolean().nullish()).nullish(),
});
export type ListingVideo = z.infer<typeof ListingVideoSchema>;

/** `channels/data/<slug>.json`. `version` je string ("1.0"), ne broj. */
export const ChannelListingSchema = z.object({
  version: z.string(),
  generated_at: z.string().nullish(),
  id: z.string(),
  name: z.string(),
  description: z.string().nullish(),
  tags: z.array(z.string()).nullish(),
  youtube_channel_url: z.string().nullish(),
  video_count: z.number().nullish(),
  latest_video_date: z.string().nullish(),
  videos: z.array(ListingVideoSchema),
});
export type ChannelListing = z.infer<typeof ChannelListingSchema>;

/** `channels/data/index.json`: popis kanala. */
export const ChannelIndexSchema = z.object({
  version: z.union([z.string(), z.number()]),
  generated_at: z.string().nullish(),
  channel_count: z.number().nullish(),
  channels: z.array(
    z.object({
      id: z.string(),
      name: z.string(),
      video_count: z.number().nullish(),
      latest_video: z
        .object({ id: z.string(), date: z.string().nullish(), title: z.string().nullish() })
        .nullish(),
    }),
  ),
});
export type ChannelIndex = z.infer<typeof ChannelIndexSchema>;

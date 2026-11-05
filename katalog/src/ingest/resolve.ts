// Razrješavanje kanala Tier 2 epizode (`_unlisted`). Čista funkcija bez I/O:
// isti kod vrti uvoznik u Nodeu i test u poolu. Pravila: odluke 203–207.
import type { ChannelIndex, EpisodeInfo, EpisodeSummary, Registry, RegistryEntry } from "../input/index.ts";

/** Kanal na koji epizoda ide. `slug` je ključ u D1 (`channels.slug`). */
export interface ResolvedChannel {
  readonly slug: string;
  readonly name: string;
  readonly tier: 1 | 2;
  /** Samo YouTube `UC…`; X/Twitter ID ovdje ne ide (stupac je `youtube_channel_id`). */
  readonly youtubeChannelId: string | null;
  /** Kanal nema registry unos; slug je izveden iz `channel_id` (odluka 205). */
  readonly unregistered: boolean;
}

/** Kojim je putem kanal nađen; ide u izvještaj. */
export type ResolutionVia =
  /** `channel_id` = točno jedan Tier 1 kanal iz `index.json` (`youtube_channel_url`). */
  | "tier1_channel_id"
  /** Registry unos čiji slug (`-` → `_`) je Tier 1 CDN slug. */
  | "registry_tier1"
  /** Registry unos koji nije Tier 1: Tier 2 kanal sa slugom iz registryja. */
  | "registry"
  /** Bez `info.json`: `summary.json` `source.channel` je Tier 1 CDN slug. */
  | "summary_source_channel"
  /** Nema registryja: slug `yt-<channel_id>` / `x-<channel_id>`. */
  | "unregistered";

export type NoChannelReason =
  /** Više Tier 1 kanala dijeli `channel_id` (`UCuk9D5H9mx7birJ1-S22nyQ`). */
  | "ambiguous_tier1_channel_id"
  /** Više registry unosa s istim `channel_id`, a nijedno pravilo `pickRegistryEntry` ne daje jedan. */
  | "ambiguous_registry_channel_id"
  /** Nema `info.json`, a `source.channel` nije Tier 1 slug (većinom `_unlisted`). */
  | "no_info_json"
  /** `info.json` bez `channel_id`. */
  | "no_channel_id"
  /** Nema registryja ni imena (`channel` i `uploader` nedostaju): kanal bez imena se ne stvara. */
  | "no_channel_name"
  /** Izvor koji nije YouTube ni X/Twitter: ne znamo oblik sluga. */
  | "unknown_extractor";

export type Resolution =
  | { readonly ok: true; readonly via: ResolutionVia; readonly channel: ResolvedChannel }
  | { readonly ok: false; readonly reason: NoChannelReason };

export interface Resolver {
  resolve(info: EpisodeInfo | null, summary: EpisodeSummary | null): Resolution;
}

/** Registry slug → CDN slug (`40-dana-za-zivot` → `40_dana_za_zivot`), odluka 204. */
export function registrySlugToCdn(slug: string): string {
  return slug.replaceAll("-", "_");
}

/** Prefiks sluga po `extractor`u; drugi izvori nemaju pravilo (odluka 205). */
const UNREGISTERED_PREFIX: Readonly<Record<string, string>> = { youtube: "yt-", twitter: "x-" };

/**
 * Bira jedan registry unos među onima s istim `channel_id` (odluka 204), redom:
 * jedini unos; jedini `youtube.type === "umbrella"` (HKM: `hkm` uz 9 playlista);
 * jedini `type === "channel"` (`nova-eva` uz playlistu `teologija-tijela`);
 * jedini bez `parent_slug`. Inače `null`: kanal se ne pogađa.
 */
export function pickRegistryEntry(candidates: readonly RegistryEntry[]): RegistryEntry | null {
  if (candidates.length === 1) return candidates[0] ?? null;
  const umbrellas = candidates.filter((e) => e.youtubeType === "umbrella");
  if (umbrellas.length === 1) return umbrellas[0] ?? null;
  const channels = candidates.filter((e) => e.youtubeType === "channel");
  if (channels.length === 1) return channels[0] ?? null;
  const roots = candidates.filter((e) => e.parentSlug === null);
  if (roots.length === 1) return roots[0] ?? null;
  return null;
}

function groupBy<T>(items: readonly T[], key: (t: T) => string | null): Map<string, T[]> {
  const out = new Map<string, T[]>();
  for (const it of items) {
    const k = key(it);
    if (k === null) continue;
    const list = out.get(k);
    if (list === undefined) out.set(k, [it]);
    else list.push(it);
  }
  return out;
}

export function createResolver(index: ChannelIndex, registry: Registry): Resolver {
  const tier1BySlug = new Map(index.channels.map((c) => [c.slug, c]));
  const tier1ByChannelId = groupBy(index.channels, (c) => c.youtubeChannelId);
  const registryByChannelId = groupBy(registry.entries, (e) => e.youtubeChannelId);
  // Slugovi koje izvedeni slug ne smije pogoditi (odluka 205): CDN i registry.
  const taken = new Set([...tier1BySlug.keys(), ...registry.entries.map((e) => e.slug)]);

  function tier1(slug: string): ResolvedChannel {
    const c = tier1BySlug.get(slug);
    if (c === undefined) throw new Error(`nema Tier 1 kanala ${slug}`);
    return { slug, name: c.name, tier: 1, youtubeChannelId: c.youtubeChannelId, unregistered: false };
  }

  return {
    resolve(info, summary) {
      if (info === null) {
        const src = summary?.sourceChannel ?? null;
        if (src !== null && tier1BySlug.has(src)) {
          return { ok: true, via: "summary_source_channel", channel: tier1(src) };
        }
        return { ok: false, reason: "no_info_json" };
      }
      const channelId = info.channelId;
      if (channelId === null) return { ok: false, reason: "no_channel_id" };
      const youtubeChannelId = info.extractor === "youtube" ? channelId : null;

      // (a) Tier 1 preko index.json.
      const t1 = tier1ByChannelId.get(channelId) ?? [];
      if (t1.length > 1) return { ok: false, reason: "ambiguous_tier1_channel_id" };
      const only = t1[0];
      if (only !== undefined) return { ok: true, via: "tier1_channel_id", channel: tier1(only.slug) };

      // (b) Registry.
      const candidates = registryByChannelId.get(channelId) ?? [];
      if (candidates.length > 0) {
        const entry = pickRegistryEntry(candidates);
        if (entry === null) return { ok: false, reason: "ambiguous_registry_channel_id" };
        const cdn = registrySlugToCdn(entry.slug);
        if (tier1BySlug.has(cdn)) return { ok: true, via: "registry_tier1", channel: tier1(cdn) };
        return {
          ok: true,
          via: "registry",
          channel: { slug: entry.slug, name: entry.displayName, tier: 2, youtubeChannelId, unregistered: false },
        };
      }

      // (c) Bez registryja.
      const prefix = info.extractor === null ? undefined : UNREGISTERED_PREFIX[info.extractor];
      if (prefix === undefined) return { ok: false, reason: "unknown_extractor" };
      const name = info.channel ?? info.uploader;
      if (name === null) return { ok: false, reason: "no_channel_name" };
      const slug = `${prefix}${channelId}`;
      if (taken.has(slug)) throw new Error(`izvedeni slug ${slug} već postoji u CDN-u ili registryju`);
      return { ok: true, via: "unregistered", channel: { slug, name, tier: 2, youtubeChannelId, unregistered: true } };
    },
  };
}

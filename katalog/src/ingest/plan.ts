// Plan uvoza: od parsiranih ulaza do redaka za D1 i izvještaja. Čisto, bez
// I/O (uvoznik `scripts/import.mjs` dohvaća, `write.ts` upisuje). Odluke 200–212.
import type { ChannelIndex, ChannelListing, EpisodeInfo, EpisodeSummary, Registry } from "../input/index.ts";
import { experimentalVariants, flagsFromFiles } from "./keys.ts";
import { createResolver, type NoChannelReason, type ResolutionVia } from "./resolve.ts";

export interface Brand {
  readonly id: string;
  readonly host: string;
}

/** Brend DOMOVINA.ai (odluka 211). */
export const DOMOVINA_BRAND: Brand = { id: "domovina", host: "domovina.ai" };

export interface ChannelRow {
  readonly slug: string;
  readonly youtubeChannelId: string | null;
  readonly name: string;
  readonly tier: 1 | 2;
  readonly lang: string | null;
  readonly avatar: string | null;
  readonly processedCount: number;
  readonly latestPublishedDate: string | null;
  readonly unregistered: boolean;
}

export interface EpisodeRow {
  readonly id: string;
  readonly channelSlug: string | null;
  readonly title: string;
  readonly titleHr: string | null;
  readonly publishedDate: string | null;
  readonly durationSeconds: number | null;
  readonly tier: 1 | 2;
  readonly lang: string | null;
  readonly magisteriumScore: number | null;
  readonly flags: number;
  /** Osnovni ID kad je epizoda eksperimentalna varijanta (odluke 208, 302), inače `null`. */
  readonly variantOf: string | null;
}

/** Tier 2 epizoda kako je uvoznik dohvatio: `null` = datoteka nema ni nakon retryja. */
export interface Tier2Input {
  readonly id: string;
  readonly info: EpisodeInfo | null;
  readonly summary: EpisodeSummary | null;
  /** Imena datoteka u `data/<id>/` iz key cachea. */
  readonly files: ReadonlySet<string>;
}

export interface PlanInput {
  readonly index: ChannelIndex;
  /** Svi listinzi; svaki kanal iz `index.json` mora imati svoj. */
  readonly listings: readonly ChannelListing[];
  readonly registry: Registry;
  readonly tier2: readonly Tier2Input[];
}

export interface PlanReport {
  readonly episodes: { readonly tier1: number; readonly tier2: number };
  readonly channels: { readonly tier1: number; readonly tier2: number; readonly unregistered: number };
  /** Tier 2 epizode po putu razrješavanja kanala. */
  readonly tier2Via: Readonly<Partial<Record<ResolutionVia, number>>>;
  /** Epizode bez kanala (`channel_slug` NULL), po razlogu, s ID-evima. */
  readonly withoutChannel: Readonly<Partial<Record<NoChannelReason, readonly string[]>>>;
  readonly withoutDate: { readonly tier1: readonly string[]; readonly tier2: readonly string[] };
  /** Tier 2 epizode koje su otišle na praćeni (Tier 1) kanal. */
  readonly tier2OnTier1Channel: readonly { readonly id: string; readonly slug: string; readonly via: ResolutionVia }[];
  /** Tier 2 ID-evi bez `info.json` (podaci iz `summary.json` `source`). */
  readonly withoutInfoJson: readonly string[];
  /** `info.json` `id` ≠ ID mape na R2 (vrijedi ID mape). */
  readonly infoIdMismatch: readonly { readonly id: string; readonly infoId: string }[];
  readonly experimentalVariants: readonly { readonly id: string; readonly base: string }[];
  /** Tier 1 listing kojem `video_count` ≠ broj epizoda u `videos` (izmjereno: 0 od 52). */
  readonly videoCountMismatch: readonly {
    readonly slug: string;
    readonly videoCount: number | null;
    readonly listingRows: number;
  }[];
  /** Tier 2 ID koji je u nekom Tier 1 listingu: preskočen, tier 1 ima prednost. */
  readonly tier2AlsoInTier1: readonly string[];
}

export interface ImportPlan {
  readonly channels: readonly ChannelRow[];
  readonly episodes: readonly EpisodeRow[];
  readonly report: PlanReport;
}

interface ChannelDraft {
  readonly slug: string;
  name: string;
  readonly tier: 1 | 2;
  readonly youtubeChannelId: string | null;
  readonly avatar: string | null;
  readonly unregistered: boolean;
  readonly videoCount: number | null;
  /** Broj epizoda u listingu (Tier 1); Tier 2 nema listing. */
  readonly listingRows: number;
  /** Datum + ID epizode od koje je uzeto ime (Tier 2: najnovija epizoda, odluka 207). */
  nameFrom: string;
}

const byKey = (a: string, b: string): number => (a < b ? -1 : a > b ? 1 : 0);

export function buildPlan(input: PlanInput): ImportPlan {
  const listingBySlug = new Map(input.listings.map((l) => [l.slug, l]));
  const channels = new Map<string, ChannelDraft>();
  const episodes: EpisodeRow[] = [];
  const tier1Ids = new Set<string>();

  for (const c of input.index.channels) {
    const listing = listingBySlug.get(c.slug);
    if (listing === undefined) throw new Error(`kanal ${c.slug} je u index.json, a listinga nema`);
    channels.set(c.slug, {
      slug: c.slug,
      name: listing.name,
      tier: 1,
      youtubeChannelId: listing.youtubeChannelId ?? c.youtubeChannelId,
      avatar: listing.avatarSquare ?? c.avatarSquare,
      unregistered: false,
      videoCount: listing.videoCount,
      listingRows: listing.videos.length,
      nameFrom: "",
    });
    for (const v of listing.videos) {
      if (tier1Ids.has(v.id)) throw new Error(`epizoda ${v.id} je u dva Tier 1 listinga`);
      tier1Ids.add(v.id);
      episodes.push({
        id: v.id,
        channelSlug: c.slug,
        title: v.title,
        titleHr: v.titleHr,
        publishedDate: v.date,
        durationSeconds: v.durationSeconds,
        tier: 1,
        lang: null,
        magisteriumScore: v.magisteriumScore,
        flags: v.flags,
        variantOf: null,
      });
    }
  }
  for (const l of input.listings) {
    if (!channels.has(l.slug)) throw new Error(`listing ${l.slug} nije u index.json`);
  }

  const resolver = createResolver(input.index, input.registry);
  const withoutChannel: Partial<Record<NoChannelReason, string[]>> = {};
  const tier2Via: Partial<Record<ResolutionVia, number>> = {};
  const tier2OnTier1Channel: { id: string; slug: string; via: ResolutionVia }[] = [];
  const withoutInfoJson: string[] = [];
  const infoIdMismatch: { id: string; infoId: string }[] = [];
  const tier2AlsoInTier1: string[] = [];

  const tier2 = [...input.tier2].sort((a, b) => byKey(a.id, b.id));
  for (const t of tier2) {
    if (tier1Ids.has(t.id)) {
      tier2AlsoInTier1.push(t.id);
      continue;
    }
    const { info, summary } = t;
    if (info === null) withoutInfoJson.push(t.id);
    else if (info.id !== t.id) infoIdMismatch.push({ id: t.id, infoId: info.id });
    const title = info?.title ?? summary?.title ?? null;
    if (title === null) throw new Error(`Tier 2 epizoda ${t.id} nema naslova ni u info.json ni u summary.json`);
    const publishedDate = info?.uploadDate ?? summary?.uploadDate ?? null;

    const r = resolver.resolve(info, summary);
    let channelSlug: string | null = null;
    if (r.ok) {
      const ch = r.channel;
      channelSlug = ch.slug;
      tier2Via[r.via] = (tier2Via[r.via] ?? 0) + 1;
      if (ch.tier === 1) tier2OnTier1Channel.push({ id: t.id, slug: ch.slug, via: r.via });
      else {
        const stamp = `${publishedDate ?? ""}\u0000${t.id}`;
        const existing = channels.get(ch.slug);
        if (existing === undefined) {
          channels.set(ch.slug, {
            slug: ch.slug,
            name: ch.name,
            tier: 2,
            youtubeChannelId: ch.youtubeChannelId,
            avatar: null,
            unregistered: ch.unregistered,
            videoCount: null,
            listingRows: 0,
            nameFrom: stamp,
          });
        } else if (existing.tier === 2 && stamp > existing.nameFrom) {
          existing.name = ch.name;
          existing.nameFrom = stamp;
        }
      }
    } else {
      (withoutChannel[r.reason] ??= []).push(t.id);
    }

    episodes.push({
      id: t.id,
      channelSlug,
      title,
      titleHr: summary?.titleHr ?? null,
      publishedDate,
      durationSeconds: info === null ? (summary?.durationSeconds ?? null) : info.durationSeconds,
      tier: 2,
      lang: summary?.language ?? null,
      magisteriumScore: null,
      flags: flagsFromFiles(t.files),
      variantOf: null,
    });
  }

  // Varijante (odluka 208) dobivaju osnovni ID; popisi ih ne pokazuju (odluka 302).
  const variants = experimentalVariants(episodes.map((e) => e.id));
  const baseOf = new Map(variants.map((v) => [v.id, v.base]));
  for (let i = 0; i < episodes.length; i++) {
    const e = episodes[i];
    const base = e === undefined ? undefined : baseOf.get(e.id);
    if (e !== undefined && base !== undefined) episodes[i] = { ...e, variantOf: base };
  }

  // processed_count i latest_published_date iz redaka koji idu u D1 (odluka 210),
  // bez varijanti, da brojka odgovara onome što lista `/channels/:slug/episodes`
  // (odluka 302).
  const counts = new Map<string, { n: number; latest: string | null }>();
  for (const e of episodes) {
    if (e.channelSlug === null || e.variantOf !== null) continue;
    const c = counts.get(e.channelSlug) ?? { n: 0, latest: null };
    c.n += 1;
    if (e.publishedDate !== null && (c.latest === null || e.publishedDate > c.latest)) c.latest = e.publishedDate;
    counts.set(e.channelSlug, c);
  }
  const channelRows: ChannelRow[] = [...channels.values()]
    .sort((a, b) => byKey(a.slug, b.slug))
    .map((d) => ({
      slug: d.slug,
      youtubeChannelId: d.youtubeChannelId,
      name: d.name,
      tier: d.tier,
      lang: null,
      avatar: d.avatar,
      processedCount: counts.get(d.slug)?.n ?? 0,
      latestPublishedDate: counts.get(d.slug)?.latest ?? null,
      unregistered: d.unregistered,
    }));
  const videoCountMismatch = [...channels.values()]
    .filter((d) => d.tier === 1 && d.videoCount !== d.listingRows)
    .map((d) => ({ slug: d.slug, videoCount: d.videoCount, listingRows: d.listingRows }))
    .sort((a, b) => byKey(a.slug, b.slug));

  episodes.sort((a, b) => byKey(a.id, b.id));
  const tier2Rows = episodes.filter((e) => e.tier === 2);
  const report: PlanReport = {
    episodes: { tier1: episodes.length - tier2Rows.length, tier2: tier2Rows.length },
    channels: {
      tier1: channelRows.filter((c) => c.tier === 1).length,
      tier2: channelRows.filter((c) => c.tier === 2).length,
      unregistered: channelRows.filter((c) => c.unregistered).length,
    },
    tier2Via,
    withoutChannel,
    withoutDate: {
      tier1: episodes.filter((e) => e.tier === 1 && e.publishedDate === null).map((e) => e.id),
      tier2: tier2Rows.filter((e) => e.publishedDate === null).map((e) => e.id),
    },
    tier2OnTier1Channel,
    withoutInfoJson,
    infoIdMismatch,
    experimentalVariants: variants,
    videoCountMismatch,
    tier2AlsoInTier1,
  };
  return { channels: channelRows, episodes, report };
}

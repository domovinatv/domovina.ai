// Sažetak sintetičkog kataloga (S4): broji retke onako kako ih je mjerenje
// stvarnog korpusa brojilo (`docs/research/2026-11-06-raspodjela-korpusa.md`),
// pa se izlaz generatora može usporediti sa stvarnim oblikom. Strujni: drži
// samo brojače po kanalu i po danu, ne retke.
import type { ChannelRow, EpisodeRow } from "../ingest/plan.ts";

export type SizeBucket = "1" | "2" | "3–10" | "11–100" | "101–1000" | ">1000";

export function sizeBucket(n: number): SizeBucket {
  if (n <= 1) return "1";
  if (n === 2) return "2";
  if (n <= 10) return "3–10";
  if (n <= 100) return "11–100";
  if (n <= 1000) return "101–1000";
  return ">1000";
}

export interface CatalogSummary {
  readonly channels: {
    readonly total: number;
    readonly tier1: number;
    readonly tier2: number;
    readonly unregistered: number;
    /** Najviše epizoda na jednom kanalu (sve epizode, i varijante). */
    readonly largest: number;
    /** Broj kanala po broju epizoda (sve epizode kanala, i varijante), kao u mjerenju korpusa. */
    readonly bySize: Readonly<Record<SizeBucket, number>>;
  };
  readonly episodes: {
    readonly total: number;
    readonly tier1: number;
    readonly tier2: number;
    readonly variants: number;
    readonly withoutChannel: number;
    readonly withoutDate: number;
  };
  /** Dan s najviše ne-varijanti (kod jednakih noviji) i njihov broj. */
  readonly hotDay: { readonly date: string | null; readonly episodes: number };
}

export class Tally {
  private readonly counts = { tier1: 0, tier2: 0, variants: 0, withoutChannel: 0, withoutDate: 0 };
  private readonly perChannel = new Map<string, number>();
  private readonly perDay = new Map<string, number>();

  add(e: EpisodeRow): void {
    if (e.tier === 1) this.counts.tier1++;
    else this.counts.tier2++;
    if (e.variantOf !== null) this.counts.variants++;
    if (e.channelSlug === null) this.counts.withoutChannel++;
    else this.perChannel.set(e.channelSlug, (this.perChannel.get(e.channelSlug) ?? 0) + 1);
    if (e.publishedDate === null) this.counts.withoutDate++;
    else if (e.variantOf === null) this.perDay.set(e.publishedDate, (this.perDay.get(e.publishedDate) ?? 0) + 1);
  }

  summary(channels: readonly ChannelRow[]): CatalogSummary {
    const bySize: Record<SizeBucket, number> = { "1": 0, "2": 0, "3–10": 0, "11–100": 0, "101–1000": 0, ">1000": 0 };
    let largest = 0;
    let tier1 = 0;
    let unregistered = 0;
    for (const c of channels) {
      const n = this.perChannel.get(c.slug) ?? 0;
      // Kanal bez ijedne epizode (ne bi ga trebalo biti) ide u razred „1”, kao najmanji.
      bySize[sizeBucket(n)]++;
      largest = Math.max(largest, n);
      if (c.tier === 1) tier1++;
      if (c.unregistered) unregistered++;
    }
    let hot: { date: string | null; episodes: number } = { date: null, episodes: 0 };
    for (const [date, n] of this.perDay) {
      if (n > hot.episodes || (n === hot.episodes && hot.date !== null && date > hot.date)) hot = { date, episodes: n };
    }
    return {
      channels: { total: channels.length, tier1, tier2: channels.length - tier1, unregistered, largest, bySize },
      episodes: { total: this.counts.tier1 + this.counts.tier2, ...this.counts },
      hotDay: hot,
    };
  }
}

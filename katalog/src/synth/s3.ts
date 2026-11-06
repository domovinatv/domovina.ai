// Raspodjela „s3”: oblik sintetičkog testa `rows_read` iz S3 (odluka 313),
// izvučen iz `test/api/rows-read-synthetic.test.ts` u S4. Namjerno nije oblik
// stvarnog korpusa (to je `korpus.ts`), nego ograda za paginaciju: dva vrlo
// velika kanala (duboki kursor do 1500 redaka), „vrući” dan s nekoliko
// stranica, varijante usred raspona i ID-evi koji se razlikuju samo veličinom
// slova.
//
// Za N = 5000 i sjeme 20261105 daje ISTE retke kao test u S3 (isti redoslijed
// poziva PRNG-a), pa i iste brojke `rows_read`. Za drugi N se svaki razred
// skalira s N / 5000, a ostatak zaokruživanja ide prvom velikom kanalu.
// Drži sve retke u memoriji: namijenjeno N do ~100 000 (test, mali generator).
import type { ChannelRow, EpisodeRow } from "../ingest/plan.ts";
import { ALPHABET, isoDay, prng } from "./random.ts";

export const S3_HOT_DAY = "2026-10-20";
export const S3_QUIET_DAY = "2025-03-14";
export const S3_BIG_A = "synth-big-a";
export const S3_BIG_B = "synth-big-b";
/** N i sjeme pod kojima su izmjerene brojke odluke 313. */
export const S3_EPISODES = 5000;
export const S3_SEED = 20261105;

export interface S3Options {
  readonly episodes: number;
  readonly seed: number;
  /** ID-evi koji već postoje (npr. fixturei), da se sintetički ne sudare s njima. */
  readonly reservedIds?: Iterable<string>;
}

export interface Synthetic {
  readonly channels: readonly ChannelRow[];
  readonly episodes: readonly EpisodeRow[];
}

interface Spec {
  readonly slug: string;
  readonly tier: 1 | 2;
  readonly count: number;
  /** Svaka 12. epizoda pada na vrući dan. */
  readonly big: boolean;
}

export function synthesizeS3(opts: S3Options): Synthetic {
  const n = opts.episodes;
  if (!Number.isInteger(n) || n < 100) throw new Error(`s3: N mora biti cijeli broj ≥ 100, ne ${n}`);
  const k = n / S3_EPISODES;
  const scale = (x: number): number => Math.max(1, Math.round(x * k));

  const rnd = prng(opts.seed);
  const pick = <T>(xs: readonly T[]): T => xs[Math.floor(rnd() * xs.length)] as T;
  const used = new Set(opts.reservedIds ?? []);
  const newId = (): string => {
    for (;;) {
      let id = "s";
      for (let i = 0; i < 10; i++) id += ALPHABET.charAt(Math.floor(rnd() * ALPHABET.length));
      if (!used.has(id)) {
        used.add(id);
        return id;
      }
    }
  };
  // ~3 godine dana; razdioba prema novijim datumima (kvadrat), kao stvarni katalog.
  const start = Date.UTC(2023, 10, 1);
  const span = Date.UTC(2026, 10, 4) - start;
  const randomDay = (): string => isoDay(start, Math.floor((1 - (1 - rnd()) ** 2) * (span / 86_400_000)));

  // Razredi (N = 5000): 2340 + 1100 + 6 × 80 + 320 malih (480) + 140 bez kanala
  // + 30 bez datuma + 30 parova veličine slova + 400 varijanti = 5000.
  const mids = 6;
  const midCount = scale(80);
  const smalls = scale(320);
  const noChannel = scale(140);
  const noDate = scale(30);
  const caseGroups = scale(10);
  const variants = scale(400);
  const bigB = scale(1100);
  const smallEpisodes = smalls + Math.floor(smalls / 2);
  const bigA = n - bigB - mids * midCount - smallEpisodes - noChannel - noDate - caseGroups * 3 - variants;
  if (bigA < 1) throw new Error(`s3: N = ${n} je premalen za raspodjelu`);

  const channelSpecs: Spec[] = [
    { slug: S3_BIG_A, tier: 1, count: bigA, big: true },
    { slug: S3_BIG_B, tier: 2, count: bigB, big: true },
  ];
  for (let i = 0; i < mids; i++) {
    channelSpecs.push({ slug: `synth-mid-${i}`, tier: i % 2 === 0 ? 1 : 2, count: midCount, big: false });
  }
  for (let i = 0; i < smalls; i++) {
    channelSpecs.push({ slug: `synth-small-${String(i).padStart(3, "0")}`, tier: 2, count: 1 + (i % 2), big: false });
  }

  const episodes: EpisodeRow[] = [];
  const row = (id: string, slug: string | null, tier: 1 | 2, date: string | null, variantOf: string | null) => {
    episodes.push({
      id,
      channelSlug: slug,
      title: `Sintetička ${id}`,
      titleHr: null,
      publishedDate: date,
      durationSeconds: Math.round(rnd() * 7200 * 1000) / 1000,
      tier,
      lang: "hr",
      magisteriumScore: null,
      flags: 0,
      variantOf,
    });
  };
  for (const c of channelSpecs) {
    for (let i = 0; i < c.count; i++) {
      // Svaka 12. epizoda velikih kanala pada na vrući dan (≈ 290 za N = 5000), ostale razasute.
      const hot = c.big && i % 12 === 0;
      row(newId(), c.slug, c.tier, hot ? S3_HOT_DAY : randomDay(), null);
    }
  }
  for (let i = 0; i < noChannel; i++) row(newId(), null, 2, i % 10 === 0 ? S3_HOT_DAY : randomDay(), null);
  for (let i = 0; i < noDate; i++) row(newId(), pick([S3_BIG_A, S3_BIG_B, null]), 2, null, null);
  // Parovi koji se razlikuju samo veličinom slova (BINARY: 'A' < 'a').
  for (let i = 0; i < caseGroups; i++) {
    const base = `case${String(i).padStart(2, "0")}xyz`;
    for (const id of [`${base}Q`, `${base}q`, `${base.toUpperCase()}q`]) {
      used.add(id);
      row(id, S3_BIG_A, 1, S3_HOT_DAY, null);
    }
  }
  // Varijante: uz osnovnu epizodu (isti kanal i dan), pola na vrućem danu.
  const bases = episodes.filter((e) => e.publishedDate !== null && e.channelSlug !== null);
  const hotBases = bases.filter((e) => e.publishedDate === S3_HOT_DAY);
  for (let i = 0; i < variants; i++) {
    const base = i % 2 === 0 ? pick(hotBases) : pick(bases);
    let v = 1;
    while (used.has(`${base.id.slice(0, 9)}_${v}`)) v++;
    const id = `${base.id.slice(0, 9)}_${v}`;
    used.add(id);
    row(id, base.channelSlug, base.tier, base.publishedDate, base.id);
  }
  if (episodes.length !== n) throw new Error(`s3: ${episodes.length} epizoda umjesto ${n}`);

  // Kanali: brojevi i datum iz istih redaka, kao plan (bez varijanti, odluka 302).
  const own = new Map<string, { count: number; latest: string | null }>();
  for (const e of episodes) {
    if (e.channelSlug === null || e.variantOf !== null || e.publishedDate === null) continue;
    const a = own.get(e.channelSlug) ?? { count: 0, latest: null };
    a.count++;
    if (a.latest === null || e.publishedDate > a.latest) a.latest = e.publishedDate;
    own.set(e.channelSlug, a);
  }
  const channels: ChannelRow[] = channelSpecs.map((c) => {
    const a = own.get(c.slug);
    return {
      slug: c.slug,
      youtubeChannelId: null,
      name: `Sintetički ${c.slug}`,
      tier: c.tier,
      lang: "hr",
      avatar: null,
      processedCount: a?.count ?? 0,
      latestPublishedDate: a?.latest ?? null,
      unregistered: false,
    };
  });
  return { channels, episodes };
}

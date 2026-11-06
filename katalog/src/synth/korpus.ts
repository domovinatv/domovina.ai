// Raspodjela „korpus” (S4): oblik stvarnog kataloga iz S2 uvoza, skaliran na
// N epizoda. Mjerenje i obrazloženje skaliranja:
// `docs/research/2026-11-06-raspodjela-korpusa.md`.
//
// Skaliranje u jednoj rečenici: veći katalog ima VIŠE kanala, ne dulje kanale.
// Veličine kanala se uzorkuju iz stvarnih (bootstrap po tieru), pa je broj
// kanala ∝ N, a dugi rep ostaje isti; uz to `max(1, round(N / 50 000))`
// „divovskih” kanala od 1000–3000 epizoda (najviše N / 10), kakvih u današnjem
// korpusu još nema, a u većem hoće (dnevna emisija kroz ~8 godina).
//
// Generator je strujni: `episodes()` daje redak po redak i u memoriji drži samo
// opis kanala (~44 000 za N = 1 000 000) i brojače, nikad sve epizode. Svaki
// poziv `episodes()` počinje istim sjemenom, pa dva prolaza daju iste retke
// (skripta prvim prolazom izračuna brojeve kanala, drugim piše epizode).
import type { ChannelRow, EpisodeRow } from "../ingest/plan.ts";
import { ALPHABET, isoDay, prng } from "./random.ts";
import { type CatalogSummary, Tally } from "./tally.ts";

// ------------------------------------------------- izmjereno (S2 uvoz, 3665 epizoda)

/** Epizoda po Tier 1 kanalu, svih 52 kanala (silazno). */
export const REAL_TIER1_SIZES: readonly number[] = [
  320, 271, 238, 224, 187, 178, 171, 169, 141, 121, 103, 91, 83, 81, 76, 69, 67, 59, 57, 55, 55, 53, 45, 44, 44, 43,
  38, 37, 33, 33, 31, 27, 22, 21, 17, 13, 12, 12, 10, 10, 9, 9, 9, 7, 7, 7, 5, 5, 4, 3, 2, 1,
];

/** Epizoda po Tier 2 kanalu, svih 110 kanala (silazno; 77 kanala s jednom). */
export const REAL_TIER2_SIZES: readonly number[] = [
  10, 9, 7, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 3, 3, ...Array<number>(12).fill(2),
  ...Array<number>(77).fill(1),
];

/** Epizoda po godini objave (2010 s jednom epizodom izostavljena). */
export const REAL_YEARS: readonly (readonly [number, number])[] = [
  [2016, 9],
  [2017, 40],
  [2018, 39],
  [2019, 65],
  [2020, 204],
  [2021, 286],
  [2022, 242],
  [2023, 367],
  [2024, 587],
  [2025, 891],
  [2026, 934],
];

const REAL_EPISODES = 3665;
/** Udjeli u svim epizodama. */
const SHARE_NO_CHANNEL = 22 / REAL_EPISODES;
const SHARE_TIER2_CHANNEL = 214 / REAL_EPISODES;
const SHARE_VARIANTS = 55 / REAL_EPISODES;
/** Tier 2 epizoda na Tier 1 kanalu (17 od 3429). */
const SHARE_TIER2_ON_TIER1 = 17 / 3429;
/** Tier 2 kanal bez registry unosa (28 od 110). */
const SHARE_UNREGISTERED = 28 / 110;
/**
 * Najveći dan je 28 od 3610 ne-varijanti (0,78 %). Na vrući dan prirodno pada
 * ~0,08 %, osnove pola varijanti ~0,2 %, pa se dodaje 0,5 % (ukupno ~0,78 %).
 */
const SHARE_HOT_EXTRA = 0.005;
/** Stvarno 0; namjerno malo iznad nule, da put „bez datuma” postoji i na razini 1M. */
const SHARE_NO_DATE = 0.0005;
/** `magisterium_score` nije NULL kod 363 od 3665. */
const SHARE_MAGISTERIUM = 363 / REAL_EPISODES;
/** `duration_seconds` je NULL kod 4 od 3665. */
const SHARE_NO_DURATION = 4 / REAL_EPISODES;

// ------------------------------------------------------------------ oblik

export const KORPUS_END = "2026-11-04";
export const KORPUS_HOT_DAY = "2026-10-20";
/** Divovski kanal po ovoliko epizoda (najmanje jedan). */
export const GIANT_EVERY = 50_000;
export const GIANT_MIN = 1000;
export const GIANT_MAX = 3000;
/** Varijante su nove (stvarne su sve iz zadnjeg mjeseca): pola na vrućem danu, pola u zadnjih 30 dana. */
const VARIANT_RECENT_DAYS = 30;
/** Najveći N: brojač u ID-u ima 4 znaka baze 62. */
export const KORPUS_MAX_EPISODES = 62 ** 4;

const BASE62 = ALPHABET.slice(0, 62);
/** Bez `_`: obični ID tako nikad ne izgleda kao varijanta (`<9>_<n>`). */
const ID_ALPHABET = ALPHABET.slice(0, 63);
const FILLER =
  "razgovor o vjeri, obitelji, odgoju djece i društvu u Hrvatskoj danas, s gostima iz cijele zemlje i iseljeništva";

export interface KorpusOptions {
  readonly episodes: number;
  readonly seed: number;
}

interface Spec {
  readonly slug: string;
  readonly tier: 1 | 2;
  readonly size: number;
  readonly giant: boolean;
  readonly youtubeChannelId: string;
  readonly unregistered: boolean;
  // Brojači jednog prolaza `episodes()`.
  processed: number;
  latest: string | null;
}

const DAY_MS = 86_400_000;
const END_MS = Date.parse(`${KORPUS_END}T00:00:00Z`);

function base62(n: number, width: number): string {
  let s = "";
  let x = n;
  for (let i = 0; i < width; i++) {
    s = BASE62.charAt(x % 62) + s;
    x = Math.floor(x / 62);
  }
  return s;
}

/** Ukupni broj epizoda po razredu; zbroj je točno N. */
function budget(n: number): { variants: number; noChannel: number; tier2: number; tier1: number } {
  const variants = Math.round(n * SHARE_VARIANTS);
  const noChannel = Math.max(1, Math.round(n * SHARE_NO_CHANNEL));
  const tier2 = Math.round(n * SHARE_TIER2_CHANNEL);
  return { variants, noChannel, tier2, tier1: n - variants - noChannel - tier2 };
}

export class Korpus {
  readonly options: KorpusOptions;
  private readonly specs: Spec[] = [];
  private readonly budget: ReturnType<typeof budget>;
  private tally: Tally | null = null;

  constructor(options: KorpusOptions) {
    const n = options.episodes;
    if (!Number.isInteger(n) || n < 1000 || n > KORPUS_MAX_EPISODES) {
      throw new Error(`korpus: N mora biti cijeli broj 1000–${KORPUS_MAX_EPISODES}, ne ${n}`);
    }
    this.options = options;
    this.budget = budget(n);
    this.planChannels();
  }

  /** Kanali i njihove veličine: vlastiti PRNG, neovisan o epizodama. */
  private planChannels(): void {
    const rnd = prng(this.options.seed);
    const n = this.options.episodes;
    let t1 = this.budget.tier1;
    const giants = Math.max(1, Math.round(n / GIANT_EVERY));
    for (let i = 0; i < giants && t1 > 0; i++) {
      const size = Math.min(Math.floor(GIANT_MIN * (GIANT_MAX / GIANT_MIN) ** rnd()), Math.floor(n / 10), t1);
      this.add(`synth-giant-${String(i).padStart(2, "0")}`, 1, size, true, false);
      t1 -= size;
    }
    for (let i = 0; t1 > 0; i++) {
      const size = Math.min(REAL_TIER1_SIZES[Math.floor(rnd() * REAL_TIER1_SIZES.length)] ?? 1, t1);
      this.add(`synth-t1-${String(i).padStart(6, "0")}`, 1, size, false, false);
      t1 -= size;
    }
    let t2 = this.budget.tier2;
    for (let i = 0; t2 > 0; i++) {
      const size = Math.min(REAL_TIER2_SIZES[Math.floor(rnd() * REAL_TIER2_SIZES.length)] ?? 1, t2);
      const unregistered = rnd() < SHARE_UNREGISTERED;
      const slug = unregistered ? `yt-${this.channelId()}` : `synth-t2-${String(i).padStart(6, "0")}`;
      this.add(slug, 2, size, false, unregistered);
      t2 -= size;
    }
  }

  private channelId(): string {
    return `UCsynth${String(this.specs.length).padStart(17, "0")}`;
  }

  private add(slug: string, tier: 1 | 2, size: number, giant: boolean, unregistered: boolean): void {
    const youtubeChannelId = this.channelId();
    this.specs.push({ slug, tier, size, giant, youtubeChannelId, unregistered, processed: 0, latest: null });
  }

  /**
   * Sve epizode, redom kanala (pa epizode bez kanala na kraju). Varijanta ide
   * odmah iza svoje osnovne epizode. Svaki poziv počinje istim sjemenom.
   */
  *episodes(): Generator<EpisodeRow> {
    const n = this.options.episodes;
    // Drugo sjeme od kanala: promjena raspodjele kanala ne mijenja niz epizoda istog kanala.
    const rnd = prng((this.options.seed ^ 0x9e3779b9) >>> 0);
    for (const s of this.specs) {
      s.processed = 0;
      s.latest = null;
    }
    this.tally = null;
    const tally = new Tally();
    let total = 0;

    const yearTotal = REAL_YEARS.reduce((a, [, w]) => a + w, 0);
    const randomDay = (): string => {
      let r = rnd() * yearTotal;
      let year = 2026;
      for (const [y, w] of REAL_YEARS) {
        year = y;
        if (r < w) break;
        r -= w;
      }
      const from = Date.UTC(year, 0, 1);
      const to = Math.min(Date.UTC(year + 1, 0, 1), END_MS + DAY_MS);
      return isoDay(from, Math.floor(rnd() * ((to - from) / DAY_MS)));
    };
    const recentDay = (): string => isoDay(END_MS, -Math.floor(rnd() * VARIANT_RECENT_DAYS));

    let counter = 0;
    const newId = (): string => {
      let id = "s";
      for (let i = 0; i < 6; i++) id += ID_ALPHABET.charAt(Math.floor(rnd() * ID_ALPHABET.length));
      return id + base62(counter++, 4);
    };
    const variantSuffix = new Map<string, number>();

    const { variants, tier1, tier2 } = this.budget;
    const channelBases = tier1 + tier2;
    const groups: number[] = [];
    for (let left = variants; left > 0; ) {
      const g = Math.min(groups.length % 2 === 0 ? 3 : 4, left);
      groups.push(g);
      left -= g;
    }
    // Varijante ravnomjerno po nizu osnovnih epizoda s kanalom (bez PRNG-a).
    let nextGroup = 0;
    const groupAt = (j: number): number => Math.floor(((j + 0.5) * channelBases) / groups.length);
    const noDateCount = Math.round(n * SHARE_NO_DATE);
    const noDateStride = noDateCount === 0 ? 0 : Math.floor((n - variants) / noDateCount);

    const build = (id: string, spec: Spec | null, tier: 1 | 2, date: string | null, variantOf: string | null) => {
      const prefix = `Sintetička epizoda ${id}: `;
      const title = (prefix + FILLER).slice(0, prefix.length + 10 + Math.floor(rnd() * 70)).trimEnd();
      const row: EpisodeRow = {
        id,
        channelSlug: spec?.slug ?? null,
        title,
        titleHr: title,
        publishedDate: date,
        durationSeconds: rnd() < SHARE_NO_DURATION ? null : Math.round(rnd() * 7200 * 1000) / 1000,
        tier,
        lang: tier === 1 ? null : "hr",
        magisteriumScore: rnd() < SHARE_MAGISTERIUM ? Math.floor(rnd() * 101) : null,
        flags: 1 + Math.floor(rnd() * 511),
        variantOf,
      };
      tally.add(row);
      total++;
      if (spec !== null && variantOf === null && date !== null) {
        spec.processed++;
        if (spec.latest === null || date > spec.latest) spec.latest = date;
      }
      return row;
    };

    let base = 0;
    let channelBase = 0;
    const baseDate = (variantBase: boolean, j: number): string | null => {
      if (variantBase) return j % 2 === 0 ? KORPUS_HOT_DAY : recentDay();
      if (noDateStride > 0 && base % noDateStride === noDateStride - 1) return null;
      return rnd() < SHARE_HOT_EXTRA ? KORPUS_HOT_DAY : randomDay();
    };

    for (const spec of this.specs) {
      for (let i = 0; i < spec.size; i++) {
        const variantBase = nextGroup < groups.length && channelBase === groupAt(nextGroup);
        // Prvih 30 epizoda prvog diva: trojke ID-eva koje se razlikuju samo veličinom slova (BINARY).
        const caseIndex = spec.giant && spec === this.specs[0] && i < 30 ? i : -1;
        let id: string;
        let date: string | null;
        if (caseIndex >= 0) {
          const g = `case${String(Math.floor(caseIndex / 3)).padStart(2, "0")}xyz`;
          id = [`${g}Q`, `${g}q`, `${g.toUpperCase()}q`][caseIndex % 3] ?? g;
          date = KORPUS_HOT_DAY;
        } else {
          id = newId();
          date = baseDate(variantBase, nextGroup);
        }
        const tier: 1 | 2 = spec.tier === 2 || rnd() < SHARE_TIER2_ON_TIER1 ? 2 : 1;
        yield build(id, spec, tier, date, null);
        base++;
        channelBase++;
        if (variantBase) {
          const size = groups[nextGroup] ?? 0;
          for (let v = 0; v < size; v++) {
            const head = id.slice(0, 9);
            const k = (variantSuffix.get(head) ?? 0) + 1;
            variantSuffix.set(head, k);
            yield build(`${head}_${k}`, spec, tier, date, id);
          }
          nextGroup++;
        }
      }
    }
    for (let i = 0; i < this.budget.noChannel; i++) {
      yield build(newId(), null, 2, baseDate(false, 0), null);
      base++;
    }
    if (nextGroup !== groups.length) throw new Error(`korpus: ${groups.length - nextGroup} grupa varijanti nije smješteno`);
    if (total !== n) throw new Error(`korpus: ${total} epizoda umjesto ${n}`);
    this.tally = tally;
  }

  /** Redak kanala kako bi ga napisao plan (brojevi bez varijanti, odluka 302). Konačan tek nakon `episodes()`. */
  channelRows(): ChannelRow[] {
    if (this.tally === null) throw new Error("korpus: channelRows() tek nakon cijelog prolaza episodes()");
    return this.specs.map((s) => ({
      slug: s.slug,
      youtubeChannelId: s.youtubeChannelId,
      name: `Sintetički kanal ${s.slug}`,
      tier: s.tier,
      lang: "hr",
      avatar: s.tier === 1 ? `channels/${s.slug}/avatar.jpg` : null,
      processedCount: s.processed,
      latestPublishedDate: s.latest,
      unregistered: s.unregistered,
    }));
  }

  summary(): CatalogSummary {
    if (this.tally === null) throw new Error("korpus: summary() tek nakon cijelog prolaza episodes()");
    return this.tally.summary(this.channelRows());
  }

  /** Broj divovskih kanala (> 1000 epizoda po planu). */
  get giants(): number {
    return this.specs.filter((s) => s.giant).length;
  }
}

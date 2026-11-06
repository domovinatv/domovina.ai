// Jezgra `katalog ingest-episode` (S7, odluke 700–): pipeline nakon uploada
// upiše svoje epizode u D1 i zapiše mapu „epizoda → kanal” za `episode.json`.
// Bez Node API-ja i bez globalnog stanja (plan, mreža i datoteke se predaju),
// pa se testira u workerd poolu sa stubom `fetch`a. CLI: `scripts/ingest-episode.ts`.
//
// Zašto PUNI plan i za jednu epizodu: redak kanala nosi `processed_count` i
// `latest_published_date`, a upsert ih prepisuje. Brojka Tier 2 kanala (i Tier 1
// kanala na koji je pala `_unlisted` epizoda) ovisi o SVIM Tier 2 epizodama, a
// kanal svake od njih zna tek resolver nad njezinim `info.json`. Plan sastavljen
// samo od jedne epizode upisao bi kanalu brojku 1. Zato se plan gradi istim
// `buildImportPlan` putem kao uvoznik i `drift-check --sync`, a šalju se samo
// retci traženih epizoda i njihovih kanala, s točnim brojkama iz punog plana.
//
// Exit kodovi (ugovor za `run_pipeline.sh` KORAK 13.5):
//   0 = sve tražene epizode su u planu i upisane (ili `--all` upisan),
//   1 = neka tražena epizoda nije u planu (nema `article.json` u key cacheu ili
//       nije u listingu): ostale su upisane, `drift-check` je jutro pokupi,
//   2 = ne mogu: nema tokena, mreža, 4xx/5xx, plan pao. Ništa se ne zapisuje.
import type { ChannelRow, EpisodeRow, ImportPlan } from "../../src/ingest/plan.ts";
import {
  CannotCheck,
  EXIT_DRIFT,
  EXIT_OK,
  EXIT_UNKNOWN,
  ingestBatches,
  normalizeBase,
  postIngest,
  redact,
  type Api,
  type ExitCode,
} from "./drift.ts";

export const INGEST_SOURCE_PIPELINE = "pipeline";
export const CHANNEL_MAP_VERSION = 1;

// ---- Odabir redaka ---------------------------------------------------------

export interface Selection {
  readonly channels: readonly ChannelRow[];
  readonly episodes: readonly EpisodeRow[];
  /** Traženi ID-evi kojih nema u planu. */
  readonly missing: readonly string[];
}

/** Retci traženih epizoda + kanali na koje pokazuju (s brojkama iz punog plana). */
export function selectRows(plan: Pick<ImportPlan, "channels" | "episodes">, ids: readonly string[]): Selection {
  const wanted = new Set(ids);
  const episodes = plan.episodes.filter((e) => wanted.has(e.id));
  const found = new Set(episodes.map((e) => e.id));
  const slugs = new Set(episodes.flatMap((e) => (e.channelSlug === null ? [] : [e.channelSlug])));
  const channels = plan.channels.filter((c) => slugs.has(c.slug));
  if (channels.length !== slugs.size) {
    // buildPlan to ne proizvodi; da se ipak dogodi, server bi vratio 409 tek na pola posla.
    const known = new Set(channels.map((c) => c.slug));
    const lost = [...slugs].filter((s) => !known.has(s));
    throw new CannotCheck(`plan: epizode pokazuju na kanale kojih nema u planu: ${lost.join(", ")}`);
  }
  return { channels, episodes, missing: [...wanted].filter((id) => !found.has(id)).sort() };
}

// ---- Mapa kanala za episode.json ------------------------------------------

export interface ChannelRef {
  readonly slug: string;
  readonly name: string;
  readonly tier: 1 | 2;
}

export interface ChannelMapEntry {
  /** `null` = epizoda je u katalogu bez kanala (resolver nije našao kanal). */
  readonly channel: ChannelRef | null;
  /**
   * Kad je ova mapa epizodu prvi put vidjela; `null` = bila je u katalogu prije
   * nego što je mapa nastala. `episode.json` dobiva `channel` samo za ne-`null`
   * (pravilo „samo nove epizode, bez backfilla”, fetch.domovina.tv CLAUDE.md #4).
   */
  readonly first_seen: string | null;
}

export interface ChannelMap {
  readonly v: typeof CHANNEL_MAP_VERSION;
  readonly generated_at: string;
  /** Kad je mapa prvi put zapisana; sve epizode tada dobivaju `first_seen: null`. */
  readonly seeded_at: string;
  readonly episodes: Readonly<Record<string, ChannelMapEntry>>;
}

/** Prethodna mapa ili `null` kad je nema / nečitljiva je (tada se mapa sije ispočetka). */
export function parseChannelMap(text: string | null): ChannelMap | null {
  if (text === null) return null;
  try {
    const raw: unknown = JSON.parse(text);
    if (typeof raw !== "object" || raw === null) return null;
    const o = raw as Record<string, unknown>;
    if (o.v !== CHANNEL_MAP_VERSION || typeof o.seeded_at !== "string") return null;
    if (typeof o.episodes !== "object" || o.episodes === null || Array.isArray(o.episodes)) return null;
    return raw as ChannelMap;
  } catch {
    return null;
  }
}

/**
 * Mapa za SVE epizode plana (ne samo tražene): bundle u nightlyju ide preko
 * cijelog kataloga. `first_seen` se nasljeđuje iz prethodne mape; epizoda koje
 * u njoj nema dobiva `now`, osim pri prvom sijanju (nema prethodne mape) kad
 * sve dobivaju `null`.
 */
export function buildChannelMap(
  plan: Pick<ImportPlan, "channels" | "episodes">,
  previous: ChannelMap | null,
  now: string,
): ChannelMap {
  const bySlug = new Map(plan.channels.map((c) => [c.slug, c]));
  const episodes: Record<string, ChannelMapEntry> = {};
  for (const e of plan.episodes) {
    const c = e.channelSlug === null ? undefined : bySlug.get(e.channelSlug);
    const prev = previous?.episodes[e.id];
    episodes[e.id] = {
      channel: c === undefined ? null : { slug: c.slug, name: c.name, tier: c.tier },
      first_seen: previous === null ? null : prev === undefined ? now : prev.first_seen,
    };
  }
  return { v: CHANNEL_MAP_VERSION, generated_at: now, seeded_at: previous?.seeded_at ?? now, episodes };
}

// ---- Tok -------------------------------------------------------------------

export interface IngestEpisodesDeps {
  readonly base: string;
  readonly token: string | null;
  readonly fetch: typeof fetch;
  /** Prazno = `all`. */
  readonly ids: readonly string[];
  readonly all: boolean;
  readonly dryRun: boolean;
  readonly buildPlan: () => Promise<Pick<ImportPlan, "channels" | "episodes">>;
  /** Mapa kanala: čitanje prethodne (`null` = nema) i zapis nove. Bez ovoga se mapa ne piše. */
  readonly channelMap?: {
    readonly read: () => Promise<string | null>;
    readonly write: (text: string) => Promise<void>;
  };
  readonly now?: () => Date;
}

export interface IngestEpisodesReport {
  readonly startedAt: string;
  readonly base: string;
  readonly mode: "ids" | "all";
  readonly requested: readonly string[];
  status: "ok" | "partial" | "dry-run" | "unknown";
  exitCode: ExitCode;
  planEpisodes?: number;
  sent?: { channels: number; episodes: number };
  missing?: readonly string[];
  calls?: number;
  changes?: { channels: number; episodes: number };
  catalog?: unknown;
  channelMap?: { episodes: number; newSinceSeed: number; seeded: boolean };
  error?: string;
}

const message = (err: unknown): string => (err instanceof Error ? err.message : String(err));

export async function runIngestEpisodes(deps: IngestEpisodesDeps): Promise<IngestEpisodesReport> {
  const started = deps.now?.() ?? new Date();
  const report: IngestEpisodesReport = {
    startedAt: started.toISOString(),
    base: deps.base,
    mode: deps.all ? "all" : "ids",
    requested: deps.ids,
    status: "unknown",
    exitCode: EXIT_UNKNOWN,
  };
  try {
    if (deps.all === (deps.ids.length > 0)) throw new CannotCheck("zadaj ID-eve ILI --all");
    const base = normalizeBase(deps.base);
    if (!deps.dryRun && (deps.token === null || deps.token === "")) {
      throw new CannotCheck("nema INGEST_TOKEN (ni u okolini ni u katalog/.dev.vars)");
    }

    const plan = await deps.buildPlan();
    report.planEpisodes = plan.episodes.length;
    const sel = deps.all ? { channels: plan.channels, episodes: plan.episodes, missing: [] } : selectRows(plan, deps.ids);
    report.sent = { channels: sel.channels.length, episodes: sel.episodes.length };
    report.missing = sel.missing;

    if (!deps.dryRun && sel.episodes.length > 0) {
      const api: Api = { base, token: deps.token ?? "", fetch: deps.fetch };
      const written = await postIngest(api, ingestBatches(sel, INGEST_SOURCE_PIPELINE));
      report.calls = written.calls;
      report.changes = written.changes;
      report.catalog = written.catalog;
    }

    // Mapa se piše i u dry-runu? Ne: dry-run ne mijenja ništa ni lokalno.
    if (deps.channelMap !== undefined && !deps.dryRun) {
      const previous = parseChannelMap(await deps.channelMap.read());
      const map = buildChannelMap(plan, previous, started.toISOString());
      await deps.channelMap.write(`${JSON.stringify(map)}\n`);
      report.channelMap = {
        episodes: Object.keys(map.episodes).length,
        newSinceSeed: Object.values(map.episodes).filter((e) => e.first_seen !== null).length,
        seeded: previous === null,
      };
    }

    if (deps.dryRun) {
      report.status = "dry-run";
      report.exitCode = sel.missing.length > 0 ? EXIT_DRIFT : EXIT_OK;
    } else if (sel.missing.length > 0) {
      report.status = "partial";
      report.exitCode = EXIT_DRIFT;
    } else {
      report.status = "ok";
      report.exitCode = EXIT_OK;
    }
    return report;
  } catch (err) {
    report.status = "unknown";
    report.exitCode = EXIT_UNKNOWN;
    report.error = redact(message(err), deps.token);
    return report;
  }
}

/** Jedan do nekoliko redaka za log pipelinea. */
export function formatIngestReport(r: IngestEpisodesReport): string[] {
  const what = r.mode === "all" ? "cijeli plan" : r.requested.join(",");
  const lines = [`katalog ingest-episode  ${r.base}  (${what})`];
  if (r.planEpisodes !== undefined) lines.push(`  plan                 ${r.planEpisodes} epizoda`);
  if (r.sent !== undefined) lines.push(`  poslano              ${r.sent.episodes} epizoda, ${r.sent.channels} kanala`);
  if (r.changes !== undefined) {
    lines.push(`  promjena u D1        ${r.changes.episodes} epizoda, ${r.changes.channels} kanala (${r.calls ?? 0} poziva, verzija ${String(r.catalog)})`);
  }
  if (r.missing !== undefined && r.missing.length > 0) {
    lines.push(`  nema u planu         ${r.missing.join(", ")} (nema article.json u key cacheu ili listingu)`);
  }
  if (r.channelMap !== undefined) {
    lines.push(`  mapa kanala          ${r.channelMap.episodes} epizoda, nove od sijanja ${r.channelMap.newSinceSeed}${r.channelMap.seeded ? " (posijana sada)" : ""}`);
  }
  if (r.error !== undefined) lines.push(`  greška               ${r.error}`);
  lines.push(`  ishod                ${r.status} (exit ${r.exitCode})`);
  return lines;
}

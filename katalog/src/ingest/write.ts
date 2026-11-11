// Upis plana u D1. Isti kod ide kroz `env.DB` u testu (pool) i kroz
// `getPlatformProxy` u uvozniku (lokalni D1 u `.wrangler/state`), odluka 213.
//
// Upsert je `INSERT … ON CONFLICT (brand, …) DO UPDATE SET … WHERE <neki stupac
// se razlikuje>`: nepromijenjen redak se ne dira, pa `meta.changes` broji samo
// stvarne promjene, a `updated_at` epizode se pomiče samo kad se sadržaj
// promijenio (odluka 214). Kanali prije epizoda (strani ključ, odluka 110).
import type { Brand, ChannelRow, EpisodeRow, ImportPlan } from "./plan.ts";

/** Naredbi po `db.batch()`; batch je transakcija, pa je ovo i jedinica atomarnosti. */
export const BATCH_SIZE = 200;

export const UPSERT_BRAND = `INSERT INTO brands (id, host) VALUES (?1, ?2)
  ON CONFLICT (id) DO UPDATE SET host = excluded.host
  WHERE brands.host IS NOT excluded.host`;

const CHANNEL_SET = [
  "youtube_channel_id",
  "name",
  "tier",
  "lang",
  "avatar",
  "processed_count",
  "latest_published_date",
  "unregistered",
] as const;

export const UPSERT_CHANNEL = `INSERT INTO channels (brand, slug, ${CHANNEL_SET.join(", ")})
  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
  ON CONFLICT (brand, slug) DO UPDATE SET ${CHANNEL_SET.map((c) => `${c} = excluded.${c}`).join(", ")}
  WHERE ${CHANNEL_SET.map((c) => `channels.${c} IS NOT excluded.${c}`).join(" OR ")}`;

const EPISODE_SET = [
  "channel_slug",
  "title",
  "title_hr",
  "published_date",
  "duration_seconds",
  "tier",
  "lang",
  "magisterium_score",
  "flags",
  "variant_of",
  "published_at",
] as const;

export const UPSERT_EPISODE = `INSERT INTO episodes (brand, id, ${EPISODE_SET.join(", ")}, updated_at)
  VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)
  ON CONFLICT (brand, id) DO UPDATE SET ${EPISODE_SET.map((c) => `${c} = excluded.${c}`).join(", ")},
    updated_at = excluded.updated_at
  WHERE ${EPISODE_SET.map((c) => `episodes.${c} IS NOT excluded.${c}`).join(" OR ")}`;

export function channelParams(brand: string, c: ChannelRow): (string | number | null)[] {
  return [
    brand,
    c.slug,
    c.youtubeChannelId,
    c.name,
    c.tier,
    c.lang,
    c.avatar,
    c.processedCount,
    c.latestPublishedDate,
    c.unregistered ? 1 : 0,
  ];
}

export function episodeParams(brand: string, e: EpisodeRow, now: string): (string | number | null)[] {
  return [
    brand,
    e.id,
    e.channelSlug,
    e.title,
    e.titleHr,
    e.publishedDate,
    e.durationSeconds,
    e.tier,
    e.lang,
    e.magisteriumScore,
    e.flags,
    e.variantOf,
    e.publishedAt,
    now,
  ];
}

export interface WriteCounts {
  readonly brands: number;
  readonly channels: number;
  readonly episodes: number;
}

async function run(db: D1Database, stmts: D1PreparedStatement[]): Promise<number> {
  let changes = 0;
  for (let i = 0; i < stmts.length; i += BATCH_SIZE) {
    const results = await db.batch(stmts.slice(i, i + BATCH_SIZE));
    for (const r of results) changes += r.meta.changes;
  }
  return changes;
}

export interface RowCounts {
  readonly channels: number;
  readonly episodes: number;
}

/**
 * Upiše retke kanala pa epizoda (strani ključ) u postojeći brend; vraća broj
 * stvarno promijenjenih redaka. Zajednički put uvoznika (`applyPlan`) i
 * `POST /ingest` (odluka 605). Nije atomarno preko `BATCH_SIZE` naredbi.
 */
export async function writeRows(
  db: D1Database,
  brandId: string,
  channelRows: readonly ChannelRow[],
  episodeRows: readonly EpisodeRow[],
  now: string,
): Promise<RowCounts> {
  const channel = db.prepare(UPSERT_CHANNEL);
  const channels = await run(db, channelRows.map((c) => channel.bind(...channelParams(brandId, c))));
  const episode = db.prepare(UPSERT_EPISODE);
  const episodes = await run(db, episodeRows.map((e) => episode.bind(...episodeParams(brandId, e, now))));
  return { channels, episodes };
}

/** Upiše plan; vraća broj stvarno promijenjenih (umetnutih ili izmijenjenih) redaka po tablici. */
export async function applyPlan(db: D1Database, brand: Brand, plan: ImportPlan, now: string): Promise<WriteCounts> {
  const brands = await run(db, [db.prepare(UPSERT_BRAND).bind(brand.id, brand.host)]);
  const { channels, episodes } = await writeRows(db, brand.id, plan.channels, plan.episodes, now);
  return { brands, channels, episodes };
}

/** Otvori redak u `ingest_runs` (`status = 'running'`), vrati njegov `id`. */
export async function startRun(db: D1Database, source: string, startedAt: string): Promise<number> {
  const row = await db
    .prepare("INSERT INTO ingest_runs (started_at, source, status) VALUES (?1, ?2, 'running') RETURNING id")
    .bind(startedAt, source)
    .first<{ id: number }>();
  if (row === null) throw new Error("ingest_runs: INSERT nije vratio id");
  return row.id;
}

export async function finishRun(
  db: D1Database,
  id: number,
  status: "ok" | "failed",
  finishedAt: string,
  counts: unknown,
): Promise<void> {
  await db
    .prepare("UPDATE ingest_runs SET status = ?2, finished_at = ?3, counts = ?4 WHERE id = ?1")
    .bind(id, status, finishedAt, JSON.stringify(counts))
    .run();
}

/**
 * Zatvori `running` redak kao uspjeh tako da ga zamijeni NOVIM `ok` retkom
 * (jedan `db.batch`, transakcija). Novi `id` je najveći u trenutku završetka, pa
 * verzija kataloga raste i kad dva ingesta idu usporedo: ingest koji je počeo
 * prije a završio poslije ne ostavi verziju ispod svojih upisa (odluka 606).
 * Vraća novu verziju (`id`).
 */
export async function commitRun(
  db: D1Database,
  runningId: number,
  source: string,
  startedAt: string,
  finishedAt: string,
  counts: unknown,
): Promise<number> {
  const [, inserted] = await db.batch<{ id: number }>([
    db.prepare("DELETE FROM ingest_runs WHERE id = ?1 AND status = 'running'").bind(runningId),
    db
      .prepare(
        `INSERT INTO ingest_runs (started_at, finished_at, source, counts, status)
         VALUES (?1, ?2, ?3, ?4, 'ok') RETURNING id`,
      )
      .bind(startedAt, finishedAt, source, JSON.stringify(counts)),
  ]);
  const id = inserted?.results[0]?.id;
  if (id === undefined) throw new Error("ingest_runs: INSERT nije vratio id");
  return id;
}

/** Ukloni `running` redak ingesta bez ijedne promjene: nema nove verzije kataloga (odluka 606). */
export async function discardRun(db: D1Database, runningId: number): Promise<void> {
  await db.prepare("DELETE FROM ingest_runs WHERE id = ?1 AND status = 'running'").bind(runningId).run();
}

/**
 * Upiti kataloga. Jedino mjesto gdje živi SQL ruta: API (S3) ih izvršava, a
 * `test/migrations.test.ts` nad istim stringovima provjerava `EXPLAIN QUERY
 * PLAN` (indeks, bez SCAN tablice, bez TEMP B-TREE za ORDER BY).
 *
 * Paginacija je samo keyset (odluka 8): stranica počinje iza zadnjeg retka
 * prethodne, `OFFSET` ne postoji. Svaka ruta ima dvije varijante, prvu
 * stranicu i stranicu iza kursora, jer `(?2 IS NULL OR …)` u jednom upitu
 * planer ne pretvara u raspon indeksa pa bi `rows_read` rastao s dubinom.
 *
 * Svaki upit nosi `INDEXED BY`: granica `rows_read` ne smije ovisiti o tome
 * je li baza analizirana. Ako indeks nestane ili postane neupotrebljiv, upit
 * pukne s greškom umjesto da tiho skenira tablicu.
 *
 * Retci bez datuma (`published_date` / `latest_published_date` NULL) ne
 * ulaze u popise poredane po datumu, ni na prvoj stranici (`IS NOT NULL`) ni
 * iza kursora (usporedba s NULL nikad nije istinita), pa je popis isti kako
 * god se listao.
 */

export type SqlParam = string | number | null;

export interface SqlQuery {
  readonly sql: string;
  readonly params: readonly SqlParam[];
}

/** Gornja granica stranice; `rows_read` po zahtjevu ograničen je njome (tvrdi uvjet 2). */
export const MAX_PAGE_SIZE = 100;

export interface EpisodeCursor {
  readonly publishedDate: string;
  readonly id: string;
}

export interface ChannelCursor {
  readonly latestPublishedDate: string;
  readonly slug: string;
}

const EPISODE_COLUMNS = `id, channel_slug, title, title_hr, published_date, duration_seconds,
  tier, lang, magisterium_score, flags`;

const CHANNEL_COLUMNS = `slug, youtube_channel_id, name, tier, lang, avatar, processed_count,
  latest_published_date`;

function checkLimit(limit: number): number {
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE) {
    throw new RangeError(`limit mora biti cijeli broj 1–${MAX_PAGE_SIZE}, dobiven ${limit}`);
  }
  return limit;
}

/** Najnovije epizode brenda (naslovnica, „Danas u korpusu”). Indeks `episodes_by_date`. */
export function latestEpisodes(brand: string, limit: number, after?: EpisodeCursor): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_date
        WHERE brand = ?1 AND published_date IS NOT NULL
        ORDER BY published_date DESC, id DESC
        LIMIT ?2`,
      params: [brand, n],
    };
  }
  return {
    sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_date
      WHERE brand = ?1 AND (published_date, id) < (?2, ?3)
      ORDER BY published_date DESC, id DESC
      LIMIT ?4`,
    params: [brand, after.publishedDate, after.id, n],
  };
}

/**
 * Epizode jednog dana (`/dani/:datum`). Indeks `episodes_by_date`.
 *
 * Ovdje je `INDEXED BY` nužan, ne kozmetičan: bez statistike (svježa baza,
 * nema `ANALYZE`) planer bira PRIMARY KEY (brand, id), koji daje isti
 * redoslijed, ali čita sve epizode brenda i filtrira po datumu (izmjereno:
 * `rows_read` 400 umjesto ≤ 41 na 400 epizoda).
 */
export function episodesOnDay(
  brand: string,
  day: string,
  limit: number,
  afterId?: string,
): SqlQuery {
  const n = checkLimit(limit);
  if (afterId === undefined) {
    return {
      sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_date
        WHERE brand = ?1 AND published_date = ?2
        ORDER BY published_date DESC, id DESC
        LIMIT ?3`,
      params: [brand, day, n],
    };
  }
  return {
    sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_date
      WHERE brand = ?1 AND published_date = ?2 AND id < ?3
      ORDER BY published_date DESC, id DESC
      LIMIT ?4`,
    params: [brand, day, afterId, n],
  };
}

/** Epizode kanala (`/c/:slug`), najnovije prve. Indeks `episodes_by_channel`. */
export function channelEpisodes(
  brand: string,
  channelSlug: string,
  limit: number,
  after?: EpisodeCursor,
): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_channel
        WHERE brand = ?1 AND channel_slug = ?2 AND published_date IS NOT NULL
        ORDER BY published_date DESC, id DESC
        LIMIT ?3`,
      params: [brand, channelSlug, n],
    };
  }
  return {
    sql: `SELECT ${EPISODE_COLUMNS} FROM episodes INDEXED BY episodes_by_channel
      WHERE brand = ?1 AND channel_slug = ?2 AND (published_date, id) < (?3, ?4)
      ORDER BY published_date DESC, id DESC
      LIMIT ?5`,
    params: [brand, channelSlug, after.publishedDate, after.id, n],
  };
}

/** Direktorij kanala jednog tiera (`/channels`), najsvježiji prvi. Indeks `channels_directory`. */
export function channelDirectory(
  brand: string,
  tier: 1 | 2,
  limit: number,
  after?: ChannelCursor,
): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY channels_directory
        WHERE brand = ?1 AND tier = ?2 AND latest_published_date IS NOT NULL
        ORDER BY latest_published_date DESC, slug DESC
        LIMIT ?3`,
      params: [brand, tier, n],
    };
  }
  return {
    sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY channels_directory
      WHERE brand = ?1 AND tier = ?2 AND (latest_published_date, slug) < (?3, ?4)
      ORDER BY latest_published_date DESC, slug DESC
      LIMIT ?5`,
    params: [brand, tier, after.latestPublishedDate, after.slug, n],
  };
}

export function prepare(db: D1Database, query: SqlQuery): D1PreparedStatement {
  return db.prepare(query.sql).bind(...query.params);
}

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

/**
 * Gornja granica stranice; `rows_read` po zahtjevu ograničen je njome (tvrdi
 * uvjet 2). Upit popisa smije tražiti `MAX_PAGE_SIZE + 1` redak: API čita
 * jedan više da zna ima li sljedeće stranice (odluka 304).
 */
export const MAX_PAGE_SIZE = 100;

export interface EpisodeCursor {
  readonly publishedDate: string;
  readonly id: string;
}

export interface ChannelCursor {
  readonly latestPublishedDate: string;
  readonly slug: string;
}

/**
 * Stupci kartice epizode (odluka 301): epizoda + ime i tier kanala JOIN-om po
 * PK kanala, jedno čitanje po retku, bez dodatnog upita. `LEFT JOIN` jer
 * epizoda smije biti bez kanala (`channel_slug` NULL, odluka 109); tada su sva
 * tri `channel_*` NULL. Kanal je u LEFT JOIN-u nužno unutarnja petlja, pa
 * redoslijed i raspon i dalje daje indeks epizoda.
 */
const CARD_COLUMNS = `e.id, e.title, e.title_hr, e.published_date, e.duration_seconds,
  e.magisterium_score, e.flags, e.tier, e.lang, e.variant_of, e.published_at,
  c.slug AS channel_slug, c.name AS channel_name, c.tier AS channel_tier,
  json_extract(s.effective, '$.channel_enabled') AS channel_enabled,
  json_extract(s.effective, '$.magisterium') AS channel_magisterium,
  t.deleted_at AS channel_deleted_at`;

/**
 * PK tablica WITHOUT ROWID SQLite imenuje `sqlite_autoindex_<tablica>_1` i
 * prima ga u `INDEXED BY`, iako ga nema u `sqlite_schema` (izmjereno, odluka 306).
 */
const CHANNELS_PK = "sqlite_autoindex_channels_1";
const EPISODES_PK = "sqlite_autoindex_episodes_1";
/** UNIQUE (host) u `brands`; drugi uvjet u CREATE TABLE, zato `_2`. */
const BRANDS_HOST = "sqlite_autoindex_brands_2";
/** PK (UC) projekcije postavki i tombstonea (migracija 0005), WITHOUT ROWID. */
const SETTINGS_PK = "sqlite_autoindex_channel_settings_1";
const TOMBSTONES_PK = "sqlite_autoindex_channel_tombstones_1";

/**
 * Postavke kanala (lanac `postavke-kanala/`, S3). `channel_settings` i
 * `channel_tombstones` se pridružuju po UC-u kanala (`LEFT JOIN` po PK, unutarnja
 * petlja, pa redoslijed i raspon i dalje daje indeks popisa). Kanal bez retka
 * postavki i ključ koji nedostaje u `effective` = uključeno (tvrdi uvjet 4):
 * `json_extract` tada daje NULL, a `NULL IS NOT 0` je istina. `effective` je već
 * razriješen u domovina-api (master i ovisni ključevi); ovdje se samo čita.
 *
 * Kanal bez UC-a (`youtube_channel_id` NULL: RSS, X izvor) nema postavki u v1
 * (odluka 102): LEFT JOIN po NULL ne nalazi ništa.
 */
function settingsJoin(uc: string): string {
  return `LEFT JOIN channel_settings AS s INDEXED BY ${SETTINGS_PK} ON s.youtube_channel_id = ${uc}
    LEFT JOIN channel_tombstones AS t INDEXED BY ${TOMBSTONES_PK} ON t.youtube_channel_id = ${uc}`;
}

/** Kanal nije povučen (`channel_enabled` nije 0) ni obrisan (nema tombstone po UC-u). */
const VISIBLE = `json_extract(s.effective, '$.channel_enabled') IS NOT 0 AND t.youtube_channel_id IS NULL`;

/**
 * Uz `VISIBLE`: vlasnik nije isključio `home_featured` (heroj, railovi, „Danas u
 * korpusu”). Samo popisi epizoda koji hrane naslovnicu; kanal i njegove epizode
 * ostaju dostupni na `/channels/:slug`.
 */
const FEATURED = `${VISIBLE} AND json_extract(s.effective, '$.home_featured') IS NOT 0`;

function cardFrom(index: string): string {
  return `FROM episodes AS e INDEXED BY ${index}
    LEFT JOIN channels AS c INDEXED BY ${CHANNELS_PK} ON c.brand = e.brand AND c.slug = e.channel_slug
    ${settingsJoin("c.youtube_channel_id")}`;
}

// Stupci kanala su kvalificirani: `youtube_channel_id` postoji i u `s` i `t`.
// Tablica kanala namjerno nema alias (plan upita je imenuje `channels`).
const CHANNEL_COLUMNS = `channels.slug, channels.youtube_channel_id, channels.name, channels.tier,
  channels.lang, channels.avatar, channels.processed_count, channels.latest_published_date,
  channels.unregistered, s.effective AS effective, t.deleted_at AS deleted_at,
  t.channel_title AS deleted_title`;

const CHANNEL_JOIN = settingsJoin("channels.youtube_channel_id");

function checkLimit(limit: number): number {
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_PAGE_SIZE + 1) {
    throw new RangeError(`limit mora biti cijeli broj 1–${MAX_PAGE_SIZE + 1}, dobiven ${limit}`);
  }
  return limit;
}

/**
 * Brend po hostu, zamjenski brend i verzija kataloga, jednim upitom (odluka
 * 305). Konstantan `rows_read`: dva čitanja po ključu i jedno iz parcijalnog
 * indeksa `ingest_runs_ok` (`max(id)` bez skena, kako god tablica rasla).
 */
export function catalogContext(host: string, defaultBrand: string): SqlQuery {
  return {
    sql: `SELECT
        (SELECT id FROM brands INDEXED BY ${BRANDS_HOST} WHERE host = ?1) AS host_brand,
        (SELECT id FROM brands INDEXED BY sqlite_autoindex_brands_1 WHERE id = ?2) AS default_brand,
        (SELECT max(id) FROM ingest_runs INDEXED BY ingest_runs_ok WHERE status = 'ok') AS catalog`,
    params: [host, defaultBrand],
  };
}

/**
 * Najnovije epizode brenda (naslovnica, „Danas u korpusu”, S9/S12; API v1 ga
 * još ne izlaže). Indeks `episodes_by_date`.
 *
 * `variant_of IS NULL` je u svakom upitu epizoda doslovno: indeksi popisa su
 * parcijalni (odluka 302) i planer ih smije koristiti samo kad upit taj uvjet
 * nosi; bez njega `INDEXED BY` pukne.
 */
export function latestEpisodes(brand: string, limit: number, after?: EpisodeCursor): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_date")}
        WHERE e.brand = ?1 AND e.published_date IS NOT NULL AND e.variant_of IS NULL
          AND ${FEATURED}
        ORDER BY e.published_date DESC, e.id DESC
        LIMIT ?2`,
      params: [brand, n],
    };
  }
  return {
    sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_date")}
      WHERE e.brand = ?1 AND (e.published_date, e.id) < (?2, ?3) AND e.variant_of IS NULL
        AND ${FEATURED}
      ORDER BY e.published_date DESC, e.id DESC
      LIMIT ?4`,
    params: [brand, after.publishedDate, after.id, n],
  };
}

/**
 * Epizode jednog dana (`/days/:date`), oba tiera. Indeks `episodes_by_date`.
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
      sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_date")}
        WHERE e.brand = ?1 AND e.published_date = ?2 AND e.variant_of IS NULL
          AND ${FEATURED}
        ORDER BY e.published_date DESC, e.id DESC
        LIMIT ?3`,
      params: [brand, day, n],
    };
  }
  return {
    sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_date")}
      WHERE e.brand = ?1 AND e.published_date = ?2 AND e.id < ?3 AND e.variant_of IS NULL
        AND ${FEATURED}
      ORDER BY e.published_date DESC, e.id DESC
      LIMIT ?4`,
    params: [brand, day, afterId, n],
  };
}

/** Epizode kanala (`/channels/:slug/episodes`), najnovije prve. Indeks `episodes_by_channel`. */
export function channelEpisodes(
  brand: string,
  channelSlug: string,
  limit: number,
  after?: EpisodeCursor,
): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_channel")}
        WHERE e.brand = ?1 AND e.channel_slug = ?2 AND e.published_date IS NOT NULL
          AND e.variant_of IS NULL
        ORDER BY e.published_date DESC, e.id DESC
        LIMIT ?3`,
      params: [brand, channelSlug, n],
    };
  }
  return {
    sql: `SELECT ${CARD_COLUMNS} ${cardFrom("episodes_by_channel")}
      WHERE e.brand = ?1 AND e.channel_slug = ?2 AND (e.published_date, e.id) < (?3, ?4)
        AND e.variant_of IS NULL
      ORDER BY e.published_date DESC, e.id DESC
      LIMIT ?5`,
    params: [brand, channelSlug, after.publishedDate, after.id, n],
  };
}

/** Kartica jedne epizode (`/episodes/:id/card`), i varijante. Po PK epizode. */
export function episodeCard(brand: string, id: string): SqlQuery {
  return {
    sql: `SELECT ${CARD_COLUMNS} ${cardFrom(EPISODES_PK)}
      WHERE e.brand = ?1 AND e.id = ?2`,
    params: [brand, id],
  };
}

/** Kanali jednog tiera (`/channels?tier=`), najsvježiji prvi. Indeks `channels_directory`. */
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
        ${CHANNEL_JOIN}
        WHERE brand = ?1 AND tier = ?2 AND latest_published_date IS NOT NULL AND ${VISIBLE}
        ORDER BY latest_published_date DESC, channels.slug DESC
        LIMIT ?3`,
      params: [brand, tier, n],
    };
  }
  return {
    sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY channels_directory
      ${CHANNEL_JOIN}
      WHERE brand = ?1 AND tier = ?2 AND (latest_published_date, channels.slug) < (?3, ?4) AND ${VISIBLE}
      ORDER BY latest_published_date DESC, channels.slug DESC
      LIMIT ?5`,
    params: [brand, tier, after.latestPublishedDate, after.slug, n],
  };
}

/**
 * Svi kanali oba tiera s barem jednom obrađenom epizodom, najsvježiji prvi:
 * `/channels` bez `tier` i `/directory` (odluka 303). Indeks
 * `channels_all_by_date` (parcijalni, `processed_count >= 1`, pa uvjet mora biti
 * u upitu doslovno).
 */
export function allChannels(brand: string, limit: number, after?: ChannelCursor): SqlQuery {
  const n = checkLimit(limit);
  if (after === undefined) {
    return {
      sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY channels_all_by_date
        ${CHANNEL_JOIN}
        WHERE brand = ?1 AND processed_count >= 1 AND latest_published_date IS NOT NULL AND ${VISIBLE}
        ORDER BY latest_published_date DESC, channels.slug DESC
        LIMIT ?2`,
      params: [brand, n],
    };
  }
  return {
    sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY channels_all_by_date
      ${CHANNEL_JOIN}
      WHERE brand = ?1 AND processed_count >= 1 AND (latest_published_date, channels.slug) < (?2, ?3) AND ${VISIBLE}
      ORDER BY latest_published_date DESC, channels.slug DESC
      LIMIT ?4`,
    params: [brand, after.latestPublishedDate, after.slug, n],
  };
}

/**
 * Zaglavlje kanala (`/channels/:slug`, i provjera postojanja za njegove epizode).
 * Po PK, uz postavke i tombstone po UC-u: povučen ili obrisan kanal nije 404
 * (tvrdi uvjet 3), stanje računa API.
 */
export function channelBySlug(brand: string, slug: string): SqlQuery {
  return {
    sql: `SELECT ${CHANNEL_COLUMNS} FROM channels INDEXED BY ${CHANNELS_PK}
      ${CHANNEL_JOIN}
      WHERE brand = ?1 AND channels.slug = ?2`,
    params: [brand, slug],
  };
}

/**
 * Tombstone po slugu (`/channels/:slug` kad kanala više nema u katalogu): slug
 * je u JSON polju `slugs` iz trenutka brisanja. Čita se samo kad `channelBySlug`
 * ne nađe redak, pa je sken tombstonea (rijetki, trajni retci) cijena 404-a, ne
 * svakog zahtjeva. Tombstone nije po brendu (postavke su vlasnikove). Bez
 * `INDEXED BY`: namjeran sken, nema raspona čiji bi `rows_read` ovisio o planu.
 */
export function tombstoneBySlug(slug: string): SqlQuery {
  return {
    sql: `SELECT youtube_channel_id, channel_title, deleted_at
      FROM channel_tombstones
      WHERE EXISTS (SELECT 1 FROM json_each(channel_tombstones.slugs) WHERE value = ?1)
      LIMIT 1`,
    params: [slug],
  };
}

/**
 * Sve postavke i svi tombstonei (`GET /v1/settings`, odluka 105), po UC-u.
 * Nije po brendu. `rows_read` = broj redaka postavki + broj tombstonea: retke
 * imaju samo kanali s vlasnikom (stotine, ne tisuće), pa sken je namjeran.
 * Filtar „barem jedan isključen ključ” radi API nad poznatim ključevima.
 */
export function allChannelSettings(): SqlQuery {
  return {
    sql: `SELECT youtube_channel_id, effective, NULL AS deleted_at
        FROM channel_settings
      UNION ALL
      SELECT youtube_channel_id, NULL AS effective, deleted_at
        FROM channel_tombstones`,
    params: [],
  };
}

/** Gornja granica stranice `ingest/ids` (odluka 607); upit smije tražiti jedan više. */
export const MAX_IDS_PAGE_SIZE = 5000;

/**
 * ID-evi svih epizoda brenda, i varijanti, po `id` ASC (`GET /ingest/ids`, za
 * drift-check, odluka 607). Raspon po PK `(brand, id)`, bez OFFSET-a: `rows_read`
 * je ograničen stranicom kako god duboko se listalo.
 */
export function episodeIds(brand: string, limit: number, afterId?: string): SqlQuery {
  if (!Number.isInteger(limit) || limit < 1 || limit > MAX_IDS_PAGE_SIZE + 1) {
    throw new RangeError(`limit mora biti cijeli broj 1–${MAX_IDS_PAGE_SIZE + 1}, dobiven ${limit}`);
  }
  if (afterId === undefined) {
    return {
      sql: `SELECT id FROM episodes INDEXED BY ${EPISODES_PK}
        WHERE brand = ?1
        ORDER BY id
        LIMIT ?2`,
      params: [brand, limit],
    };
  }
  return {
    sql: `SELECT id FROM episodes INDEXED BY ${EPISODES_PK}
      WHERE brand = ?1 AND id > ?2
      ORDER BY id
      LIMIT ?3`,
    params: [brand, afterId, limit],
  };
}

/**
 * Koji od zadanih slugova (JSON niz stringova) postoje kao kanali brenda; po PK
 * kanala, jedno čitanje po slugu. Ingest time provjerava strani ključ prije
 * upisa (odluka 605).
 */
export function existingChannelSlugs(brand: string, slugsJson: string): SqlQuery {
  return {
    sql: `SELECT slug FROM channels INDEXED BY ${CHANNELS_PK}
      WHERE brand = ?1 AND slug IN (SELECT value FROM json_each(?2))`,
    params: [brand, slugsJson],
  };
}

export function prepare(db: D1Database, query: SqlQuery): D1PreparedStatement {
  return db.prepare(query.sql).bind(...query.params);
}

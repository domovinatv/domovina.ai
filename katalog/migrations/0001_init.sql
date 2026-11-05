-- Migration number: 0001 	 2026-11-05
-- Shema kataloga (S1). Odluke 100–1xx u docs/decisions.md.
--
-- D1 je projekcija onoga što je pipeline uploadao na R2, ne izvor istine.
-- Pravila: STRICT (tipovi se provjeravaju, ne pretvaraju tiho), NULL samo gdje
-- ulaz stvarno može nedostajati, nikad izmišljena zamjenska vrijednost.
-- Upsert ide kroz `INSERT … ON CONFLICT DO UPDATE`, nikad `INSERT OR REPLACE`:
-- REPLACE briše pa umeće, a strani ključ epizoda → kanal bi to odbio.

CREATE TABLE brands (
  id   TEXT NOT NULL PRIMARY KEY CHECK (length(id) > 0),
  host TEXT NOT NULL UNIQUE CHECK (length(host) > 0)
) STRICT, WITHOUT ROWID;

CREATE TABLE channels (
  brand                 TEXT    NOT NULL REFERENCES brands (id),
  slug                  TEXT    NOT NULL CHECK (length(slug) > 0),
  -- Nije UNIQUE: kanali iz playlista istog YouTube kanala dijele ID
  -- (`na_kavi_sa_svetim_ignacijem`, `slijedi_svoj_poziv_1`, `_2`).
  -- NULL kad izvor nije YouTube kanal (`dijalog`, `launched`, `subclub`).
  youtube_channel_id    TEXT CHECK (youtube_channel_id IS NULL OR length(youtube_channel_id) > 0),
  name                  TEXT    NOT NULL CHECK (length(name) > 0),
  -- 1 = praćen kanal s listingom, 2 = samo `_unlisted`. NIJE registry tier 1–4.
  tier                  INTEGER NOT NULL CHECK (tier IN (1, 2)),
  lang                  TEXT CHECK (lang IS NULL OR length(lang) BETWEEN 2 AND 16),
  avatar                TEXT CHECK (avatar IS NULL OR length(avatar) > 0),
  processed_count       INTEGER NOT NULL CHECK (processed_count >= 0),
  -- NULL dok kanal nema nijednu epizodu s datumom.
  latest_published_date TEXT CHECK (
    latest_published_date IS NULL
    OR (latest_published_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(latest_published_date) = latest_published_date)
  ),
  PRIMARY KEY (brand, slug)
) STRICT, WITHOUT ROWID;

CREATE TABLE episodes (
  brand             TEXT    NOT NULL REFERENCES brands (id),
  -- ID epizode: YouTube ID, ali ne nužno (`dijalog` ima 11 hex znakova,
  -- X/Twitter epizode imaju svoj izvorni ID).
  id                TEXT    NOT NULL CHECK (length(id) > 0),
  -- NULL kad se kanal ne da razriješiti (32 od 232 Tier 2 epizode nemaju
  -- registry unos po `channel_id`; X/Twitter zapis nema `channel`).
  channel_slug      TEXT CHECK (channel_slug IS NULL OR length(channel_slug) > 0),
  title             TEXT    NOT NULL CHECK (length(title) > 0),
  title_hr          TEXT CHECK (title_hr IS NULL OR length(title_hr) > 0),
  published_date    TEXT CHECK (
    published_date IS NULL
    OR (published_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
        AND date(published_date) = published_date)
  ),
  -- REAL: X/Twitter epizoda ima 245.295 s; NULL kad yt-dlp trajanje ne zna.
  duration_seconds  REAL CHECK (duration_seconds IS NULL OR duration_seconds >= 0),
  tier              INTEGER NOT NULL CHECK (tier IN (1, 2)),
  lang              TEXT CHECK (lang IS NULL OR length(lang) BETWEEN 2 AND 16),
  -- Cijeli broj 0–100 (izmjereno u listinzima i home.json); većinom NULL.
  magisterium_score INTEGER CHECK (magisterium_score IS NULL OR magisterium_score BETWEEN 0 AND 100),
  -- Bitmaska kao `p` u home.json, redoslijed = PIPELINE_BITS (bit 0…8).
  -- 0 = nijedna zastavica nije podignuta (izostanak nije informacija).
  flags             INTEGER NOT NULL CHECK (flags BETWEEN 0 AND 511),
  -- ISO 8601 UTC, kad je redak zadnji put upisan.
  updated_at        TEXT    NOT NULL CHECK (julianday(updated_at) IS NOT NULL),
  PRIMARY KEY (brand, id),
  FOREIGN KEY (brand, channel_slug) REFERENCES channels (brand, slug)
) STRICT, WITHOUT ROWID;

CREATE TABLE ingest_runs (
  id          INTEGER PRIMARY KEY,
  started_at  TEXT NOT NULL CHECK (julianday(started_at) IS NOT NULL),
  finished_at TEXT CHECK (finished_at IS NULL OR julianday(finished_at) >= julianday(started_at)),
  -- Odakle je uvoz krenuo, npr. 'backfill', 'pipeline', 'drift-check'.
  source      TEXT NOT NULL CHECK (length(source) > 0),
  -- JSON objekt s brojačima (umetnuto/promijenjeno/preskočeno …).
  counts      TEXT CHECK (counts IS NULL OR (json_valid(counts) AND json_type(counts) = 'object')),
  status      TEXT NOT NULL CHECK (status IN ('running', 'ok', 'failed')),
  CHECK ((status = 'running') = (finished_at IS NULL))
) STRICT;

-- Najnovije epizode brenda i epizode jednog dana (/dani/:datum, „Danas u korpusu”).
CREATE INDEX episodes_by_date
  ON episodes (brand, published_date DESC, id DESC);

-- Epizode jednog kanala (/c/:slug), najnovije prve. Služi i provjeri stranog
-- ključa kad se kanal mijenja.
CREATE INDEX episodes_by_channel
  ON episodes (brand, channel_slug, published_date DESC, id DESC);

-- Direktorij kanala po tieru (/channels), najsvježiji prvi.
CREATE INDEX channels_directory
  ON channels (brand, tier, latest_published_date DESC, slug DESC);

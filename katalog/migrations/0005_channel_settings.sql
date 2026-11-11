-- Migration number: 0005 	 2026-11-11
-- Postavke kanala za vlasnika (lanac `postavke-kanala/`, S3, odluke 300+ u
-- `postavke-kanala/docs/decisions.md`).
--
-- Izvor istine je domovina-api (`domovina_ai.public_channel_settings` i
-- `public_channel_tombstones`); ovo je PROJEKCIJA koju puni poller (Cron
-- Trigger). D1 preslikava `effective` (svih 20 ključeva, master i ovisni
-- ključevi već primijenjeni u SQL-u domovina-api), NE preračunava ga.
-- Ključ je UC id (odluka 7): slugovi iz playlista dijele UC, pa jedan redak
-- vrijedi za sve. Nije po brendu: postavke su vlasnikove, ne brendove.
--
-- Kanal bez retka = sve uključeno (tvrdi uvjet 4).

CREATE TABLE channel_settings (
  youtube_channel_id TEXT NOT NULL PRIMARY KEY CHECK (length(youtube_channel_id) > 0),
  -- JSON objekt ključ → boolean, svih 20 ključeva (`effective` iz domovina-api).
  effective          TEXT NOT NULL CHECK (json_valid(effective) AND json_type(effective) = 'object'),
  -- `updated_at` iz izvora (ISO 8601); kursor pollera.
  source_updated_at  TEXT NOT NULL CHECK (julianday(source_updated_at) IS NOT NULL),
  -- Kad je poller zadnji put upisao redak (ISO 8601 UTC); mjeri zastoj RPC → D1.
  synced_at          TEXT NOT NULL CHECK (julianday(synced_at) IS NOT NULL)
) STRICT, WITHOUT ROWID;

-- Trajni zapis brisanja (tvrdi uvjet 5, odluka 6). Kod nema DELETE ni UPDATE
-- put; triggeri ga odbijaju i za ručni SQL. Upis je `ON CONFLICT DO NOTHING`.
CREATE TABLE channel_tombstones (
  youtube_channel_id TEXT NOT NULL PRIMARY KEY CHECK (length(youtube_channel_id) > 0),
  channel_title      TEXT CHECK (channel_title IS NULL OR length(channel_title) > 0),
  -- JSON polje slugova kanala u trenutku brisanja.
  slugs              TEXT NOT NULL CHECK (json_valid(slugs) AND json_type(slugs) = 'array'),
  requested_at       TEXT CHECK (requested_at IS NULL OR julianday(requested_at) IS NOT NULL),
  phone_confirmed_at TEXT CHECK (phone_confirmed_at IS NULL OR julianday(phone_confirmed_at) IS NOT NULL),
  deleted_at         TEXT NOT NULL CHECK (julianday(deleted_at) IS NOT NULL),
  synced_at          TEXT NOT NULL CHECK (julianday(synced_at) IS NOT NULL)
) STRICT, WITHOUT ROWID;

CREATE TRIGGER channel_tombstones_no_update
  BEFORE UPDATE ON channel_tombstones
  BEGIN SELECT RAISE(ABORT, 'channel_tombstones je trajan'); END;

CREATE TRIGGER channel_tombstones_no_delete
  BEFORE DELETE ON channel_tombstones
  BEGIN SELECT RAISE(ABORT, 'channel_tombstones je trajan'); END;

-- Stanje pollera: jedan redak po izvoru. `cursor` = najveći `updated_at`
-- koji je upisan; sljedeći poziv traži `updated_at >= cursor` (jednaki se
-- ponovno upišu, upis je idempotentan).
CREATE TABLE settings_poll_state (
  source     TEXT NOT NULL PRIMARY KEY CHECK (length(source) > 0),
  cursor     TEXT CHECK (cursor IS NULL OR julianday(cursor) IS NOT NULL),
  polled_at  TEXT NOT NULL CHECK (julianday(polled_at) IS NOT NULL),
  -- 'ok' ili kratak kod greške zadnjeg poziva (npr. 'http_503').
  status     TEXT NOT NULL CHECK (length(status) > 0)
) STRICT, WITHOUT ROWID;

-- Kanali po UC-u (filtar povučenih kanala i stanje `/channels/:slug`).
CREATE INDEX channels_by_uc ON channels (youtube_channel_id);

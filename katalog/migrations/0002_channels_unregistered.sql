-- Migration number: 0002 	 2026-11-05
-- S2: oznaka kanala bez registry unosa (odluka 205).
--
-- `unregistered = 1`: Tier 2 kanal čiji je slug izveden iz `channel_id`
-- (`yt-<UC…>`, `x-<id>`) jer kanala nema u `podcasts_registry.json`. Takav
-- kanal je uvijek tier 2: praćen kanal (tier 1) ima listing, dakle i registry.
--
-- DEFAULT 0 postoji samo zato što `ALTER TABLE ADD COLUMN … NOT NULL` traži
-- zamjensku vrijednost za postojeće retke; uvoznik stupac uvijek piše izričito.
ALTER TABLE channels ADD COLUMN unregistered INTEGER NOT NULL DEFAULT 0
  CHECK (unregistered IN (0, 1) AND (unregistered = 0 OR tier = 2));

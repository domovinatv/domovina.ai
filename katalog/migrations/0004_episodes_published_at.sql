-- Migration number: 0004 	 2026-11-11
-- Sat objave epizode na YouTubeu (odluka 1205). `published_date` ostaje dan
-- (Europe/Zagreb) po kojem se dijeli na `/days/:date`; ovo je točan trenutak u
-- UTC-u (`YYYY-MM-DDTHH:MM:SSZ`), za prikaz sata na `/dani/` i `/c/<slug>`.
-- Izvor: `backfill.json` `published_at` (YouTube Data API), inače yt-dlp
-- `timestamp` iz `info.json` (Tier 2). Tier 1 bez backfill zapisa ostaje NULL.
-- Bez indeksa: redoslijed popisa ga (još) ne koristi.
-- CHECK je kanonski oblik kroz strftime (stvaran trenutak, točno taj zapis);
-- GLOB s 14 klasa D1 odbija („LIKE or GLOB pattern too complex”).
ALTER TABLE episodes ADD COLUMN published_at TEXT
  CHECK (published_at IS NULL
    OR strftime('%Y-%m-%dT%H:%M:%SZ', published_at) IS published_at);

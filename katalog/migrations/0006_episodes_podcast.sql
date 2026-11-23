-- Migration number: 0006 	 2026-11-23
-- Podcast iz registra kojem epizoda pripada (slug ključa `channels.<slug>` u
-- fetch `automatic/watchlist/backfill.json`). Jedan YouTube kanal nosi više
-- podcasta (HRT, Laudato TV, Tribina…), a podcast.domovina.ai/dani/ broji
-- kanale po podcastu, pa brojač na `/dani/:datum` broji po ovom stupcu
-- (odluka 1208). NULL = epizoda još nije u backfillu; klijent pada na kanal.
ALTER TABLE episodes ADD COLUMN podcast TEXT CHECK (podcast IS NULL OR length(podcast) > 0);

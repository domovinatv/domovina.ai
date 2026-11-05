-- Migration number: 0003 	 2026-11-05
-- S3: eksperimentalne varijante, indeks direktorija svih kanala i verzija
-- kataloga (odluke 300–3xx u docs/decisions.md).
--
-- `variant_of`: osnovni ID kad je epizoda eksperimentalna varijanta
-- (`<9 znakova osnovnog ID-a>_<n>`, odluka 208), inače NULL. Popisi epizoda
-- varijante ne pokazuju; kartica (`/episodes/:id/card`) ih vraća s ovim poljem.
-- Nema stranog ključa na `episodes`: `ALTER TABLE ADD COLUMN` ne može dodati
-- složeni ključ (brand, variant_of), a uvoznik ga puni samo kad osnovni ID
-- postoji u istom planu.
ALTER TABLE episodes ADD COLUMN variant_of TEXT
  CHECK (variant_of IS NULL OR length(variant_of) > 0);

-- Indeksi popisa postaju parcijalni: varijanta nije u indeksu, pa je ni
-- popis ne čita (rows_read se ne troši na retke koji se odbace). Upit mora
-- nositi `variant_of IS NULL` doslovno, inače planer parcijalni indeks ne
-- smije koristiti, a `INDEXED BY` tada pukne umjesto da tiho skenira.
DROP INDEX episodes_by_date;
CREATE INDEX episodes_by_date
  ON episodes (brand, published_date DESC, id DESC)
  WHERE variant_of IS NULL;

DROP INDEX episodes_by_channel;
CREATE INDEX episodes_by_channel
  ON episodes (brand, channel_slug, published_date DESC, id DESC)
  WHERE variant_of IS NULL;

-- Svi kanali (oba tiera) po svježini: `/channels` bez `tier` i `/directory`.
-- Odluka 111 je ovaj indeks predvidjela; parcijalni jer kanal bez obrađene
-- epizode nema datum i u popis po datumu ionako ne ulazi.
CREATE INDEX channels_all_by_date
  ON channels (brand, latest_published_date DESC, slug DESC)
  WHERE processed_count >= 1;

-- Verzija kataloga = najveći `id` uspješnog uvoza. Parcijalni indeks daje
-- `max(id)` jednim čitanjem, kako god tablica rasla.
CREATE INDEX ingest_runs_ok
  ON ingest_runs (id)
  WHERE status = 'ok';

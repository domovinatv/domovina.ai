-- S3: ocjena vijesti po trenutku (odluka 311). `score` postoji od 001
-- (`real` bez raspona); 003 mu daje skalu 0–1 i objašnjenje.
ALTER TABLE vijesti.moments
  -- Sastavnice (novost, konkretnost, govornik) i obilježja iz kojih je ocjena izračunata.
  ADD COLUMN score_parts   jsonb,
  -- Kratki razlozi modela na hrvatskom, po sastavnici.
  ADD COLUMN score_reasons jsonb,
  -- `score-moments/1+f1`: verzija prompta i formule; ocjene različitih verzija se ne miješaju.
  ADD COLUMN score_version text CHECK (length(btrim(score_version)) > 0),
  ADD COLUMN score_run_id  bigint REFERENCES vijesti.runs (id) ON DELETE SET NULL,
  ADD COLUMN scored_at     timestamptz;
-- Vrijednosti `score` iz vremena prije skale nemaju objašnjenje ni verziju: brišu se.
UPDATE vijesti.moments SET score = NULL;
ALTER TABLE vijesti.moments
  ADD CONSTRAINT moments_score_range CHECK (score IS NULL OR (score >= 0 AND score <= 1)),
  ADD CONSTRAINT moments_score_consistent CHECK (
    (score IS NULL) = (score_version IS NULL)
    AND (score IS NULL) = (score_parts IS NULL)
    AND (score IS NULL) = (score_reasons IS NULL)
    AND (score IS NULL) = (scored_at IS NULL)
  ),
  -- Odbačen citat (provjera citata) se ne ocjenjuje.
  ADD CONSTRAINT moments_score_not_failed CHECK (score IS NULL OR quote_check <> 'failed');
CREATE INDEX moments_score_idx ON vijesti.moments (score DESC) WHERE score IS NOT NULL;

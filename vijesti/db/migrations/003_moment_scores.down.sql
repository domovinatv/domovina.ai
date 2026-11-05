-- Ocjena bez verzije i razloga nema značenje (skala iz 003), pa se briše.
DROP INDEX IF EXISTS vijesti.moments_score_idx;
ALTER TABLE vijesti.moments
  DROP CONSTRAINT IF EXISTS moments_score_not_failed,
  DROP CONSTRAINT IF EXISTS moments_score_consistent,
  DROP CONSTRAINT IF EXISTS moments_score_range,
  DROP COLUMN IF EXISTS scored_at,
  DROP COLUMN IF EXISTS score_run_id,
  DROP COLUMN IF EXISTS score_version,
  DROP COLUMN IF EXISTS score_reasons,
  DROP COLUMN IF EXISTS score_parts;
UPDATE vijesti.moments SET score = NULL;

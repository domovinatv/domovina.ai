ALTER TABLE vijesti.moments
  DROP CONSTRAINT IF EXISTS moments_quote_match_consistent,
  DROP CONSTRAINT IF EXISTS moments_reject_reason_consistent,
  DROP COLUMN IF EXISTS cue_to,
  DROP COLUMN IF EXISTS cue_from,
  DROP COLUMN IF EXISTS quote_match,
  DROP COLUMN IF EXISTS reject_reason,
  DROP COLUMN IF EXISTS claim;

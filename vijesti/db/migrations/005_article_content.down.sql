ALTER TABLE vijesti.article_versions
  DROP CONSTRAINT IF EXISTS article_versions_verify_needs_content,
  DROP CONSTRAINT IF EXISTS article_versions_content_consistent,
  DROP COLUMN IF EXISTS verify,
  DROP COLUMN IF EXISTS prompt_version,
  DROP COLUMN IF EXISTS word_count,
  DROP COLUMN IF EXISTS content,
  DROP COLUMN IF EXISTS category,
  DROP COLUMN IF EXISTS lead;

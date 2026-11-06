-- Vraća shemu iz 005. Uloge anon/authenticated/service_role ostaju (odluka 502):
-- na Supabaseu nisu naše. Povučen članak ili ispravak vrste `retraction` ruše
-- ovaj korak (CHECK iz 001), pa se ne gube bez traga.
REVOKE ALL ON ALL TABLES IN SCHEMA vijesti FROM anon, authenticated, service_role;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vijesti FROM anon, authenticated, service_role;
REVOKE ALL ON SCHEMA vijesti FROM anon, authenticated, service_role;

DROP VIEW IF EXISTS vijesti.versions_awaiting_verify;
DROP VIEW IF EXISTS vijesti.editor_article_versions;
DROP VIEW IF EXISTS vijesti.public_corrections;
DROP VIEW IF EXISTS vijesti.public_article_versions;

DROP POLICY IF EXISTS articles_read ON vijesti.articles;
DROP POLICY IF EXISTS article_versions_read ON vijesti.article_versions;
DROP POLICY IF EXISTS article_sources_read ON vijesti.article_sources;
DROP POLICY IF EXISTS moments_read ON vijesti.moments;
DROP POLICY IF EXISTS stories_read ON vijesti.stories;
DROP POLICY IF EXISTS corrections_read ON vijesti.corrections;
DROP POLICY IF EXISTS story_moments_read ON vijesti.story_moments;
DROP POLICY IF EXISTS runs_read ON vijesti.runs;
DROP POLICY IF EXISTS eval_channels_read ON vijesti.eval_channels;
DROP POLICY IF EXISTS eval_sample_read ON vijesti.eval_sample;

ALTER TABLE vijesti.runs DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.moments DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.stories DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.story_moments DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.articles DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_versions DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_sources DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.corrections DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.eval_channels DISABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.eval_sample DISABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS article_versions_after_insert ON vijesti.article_versions;
DROP TRIGGER IF EXISTS article_versions_immutable ON vijesti.article_versions;
DROP TRIGGER IF EXISTS articles_status_log ON vijesti.articles;
DROP TRIGGER IF EXISTS articles_status_guard ON vijesti.articles;

DROP FUNCTION IF EXISTS vijesti.disallow_channel(text);
DROP FUNCTION IF EXISTS vijesti.allow_channel(text, text);
DROP FUNCTION IF EXISTS vijesti.remove_staff(uuid);
DROP FUNCTION IF EXISTS vijesti.set_staff_role(uuid, text);
DROP FUNCTION IF EXISTS vijesti.retract_article(bigint, text);
DROP FUNCTION IF EXISTS vijesti.correct_article(bigint, bigint, text, text);
DROP FUNCTION IF EXISTS vijesti.resolve_sentence(bigint, integer, text, text);
DROP FUNCTION IF EXISTS vijesti.save_editor_version(bigint, bigint, text, text, text, jsonb);
DROP FUNCTION IF EXISTS vijesti.publish_article(bigint, text);
DROP FUNCTION IF EXISTS vijesti.approve_article(bigint, bigint, text);
DROP FUNCTION IF EXISTS vijesti.transition_article(bigint, text, text);
DROP FUNCTION IF EXISTS vijesti._nonblank(text, text);
DROP FUNCTION IF EXISTS vijesti._lock_article(bigint);
DROP FUNCTION IF EXISTS vijesti._require_ready(bigint);
DROP FUNCTION IF EXISTS vijesti._latest_version_id(bigint);
DROP FUNCTION IF EXISTS vijesti._render_quote(bigint);
DROP FUNCTION IF EXISTS vijesti._word_count(text);
DROP FUNCTION IF EXISTS vijesti._clock(integer);
DROP FUNCTION IF EXISTS vijesti._article_versions_after_insert();
DROP FUNCTION IF EXISTS vijesti._article_versions_immutable();
DROP FUNCTION IF EXISTS vijesti._transition(bigint, text, bigint, text, text);
DROP FUNCTION IF EXISTS vijesti._articles_status_log();
DROP FUNCTION IF EXISTS vijesti._articles_status_guard();

DROP TABLE IF EXISTS vijesti.sentence_resolutions;
-- Okidač samo-dodavanja ide s tablicom.
DROP TABLE IF EXISTS vijesti.article_events;
DROP FUNCTION IF EXISTS vijesti._article_events_no_truncate();
DROP FUNCTION IF EXISTS vijesti._article_events_append_only();
DROP TABLE IF EXISTS vijesti.article_transitions;
DROP TABLE IF EXISTS vijesti.allowed_channels;
DROP TABLE IF EXISTS vijesti.staff;

DROP FUNCTION IF EXISTS vijesti._actor_label();
DROP FUNCTION IF EXISTS vijesti._require_role(text);
DROP FUNCTION IF EXISTS vijesti.has_role(text);
DROP FUNCTION IF EXISTS vijesti.current_user_id();

DROP INDEX IF EXISTS vijesti.article_sources_moment_idx;

ALTER TABLE vijesti.corrections DROP COLUMN IF EXISTS replaced_version_id;
ALTER TABLE vijesti.corrections DROP CONSTRAINT corrections_kind_check;
ALTER TABLE vijesti.corrections ADD CONSTRAINT corrections_kind_check
  CHECK (kind IN ('quote', 'fact', 'attribution', 'other'));

ALTER TABLE vijesti.articles
  DROP CONSTRAINT IF EXISTS articles_published_version_fkey,
  DROP CONSTRAINT IF EXISTS articles_approved_version_fkey,
  DROP COLUMN IF EXISTS published_version_id,
  DROP COLUMN IF EXISTS approved_version_id;
ALTER TABLE vijesti.article_versions DROP CONSTRAINT IF EXISTS article_versions_article_id_id_key;

ALTER TABLE vijesti.articles DROP CONSTRAINT articles_status_check;
ALTER TABLE vijesti.articles ADD CONSTRAINT articles_status_check
  CHECK (status IN ('draft', 'review', 'approved', 'published', 'corrected', 'rejected'));

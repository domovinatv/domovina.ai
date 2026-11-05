-- S1: osnovna shema portala vijesti. Shemu `vijesti` i tablicu
-- `vijesti.schema_migrations` stvara runner (db/migrate.ts), ne ova migracija.

-- Svaki LLM prolaz (jedan korak nad jednom epizodom ili pričom).
CREATE TABLE vijesti.runs (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  step          text NOT NULL,
  video_id      text,
  model         text NOT NULL,
  prompt_version text,
  status        text NOT NULL DEFAULT 'running'
                CHECK (status IN ('running', 'ok', 'failed')),
  calls         integer NOT NULL DEFAULT 0 CHECK (calls >= 0),
  failed_calls  integer NOT NULL DEFAULT 0 CHECK (failed_calls >= 0 AND failed_calls <= calls),
  tokens_in     bigint NOT NULL DEFAULT 0 CHECK (tokens_in >= 0),
  tokens_out    bigint NOT NULL DEFAULT 0 CHECK (tokens_out >= 0),
  -- NULL dok cijena modela nije u konfiguraciji (odluka 107).
  cost_usd      numeric(12, 6) CHECK (cost_usd >= 0),
  error         text,
  started_at    timestamptz NOT NULL DEFAULT now(),
  finished_at   timestamptz
);

-- Trenutak: izjava s rasponom vremena, govornikom i doslovnim citatom.
CREATE TABLE vijesti.moments (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  video_id      text NOT NULL,
  start_ms      integer NOT NULL CHECK (start_ms >= 0),
  end_ms        integer NOT NULL,
  speaker       text NOT NULL,
  speaker_name  text,
  quote         text NOT NULL CHECK (length(btrim(quote)) > 0),
  quote_check   text NOT NULL
                CHECK (quote_check IN ('exact', 'fuzzy', 'srt_only', 'failed')),
  -- Jezik citata (jezik snimke): engleski kanal citira engleski izvornik.
  quote_lang    text NOT NULL DEFAULT 'hr',
  topics        text[] NOT NULL DEFAULT '{}',
  entities      text[] NOT NULL DEFAULT '{}',
  score         real,
  run_id        bigint REFERENCES vijesti.runs (id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (end_ms > start_ms),
  UNIQUE (video_id, start_ms, end_ms, quote)
);
CREATE INDEX moments_video_idx ON vijesti.moments (video_id, start_ms);

CREATE TABLE vijesti.stories (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  slug          text NOT NULL UNIQUE,
  title         text NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vijesti.story_moments (
  story_id      bigint NOT NULL REFERENCES vijesti.stories (id) ON DELETE CASCADE,
  moment_id     bigint NOT NULL REFERENCES vijesti.moments (id) ON DELETE CASCADE,
  PRIMARY KEY (story_id, moment_id)
);

-- Članak: priča × format × jezik. Sadržaj je u verzijama.
CREATE TABLE vijesti.articles (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  story_id      bigint NOT NULL REFERENCES vijesti.stories (id) ON DELETE RESTRICT,
  format        text NOT NULL,
  lang          text NOT NULL DEFAULT 'hr' CHECK (lang IN ('hr', 'en')),
  slug          text NOT NULL,
  status        text NOT NULL DEFAULT 'draft'
                CHECK (status IN ('draft', 'review', 'approved', 'published', 'corrected', 'rejected')),
  published_at  timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (story_id, format, lang),
  UNIQUE (lang, slug)
);

CREATE TABLE vijesti.article_versions (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  article_id    bigint NOT NULL REFERENCES vijesti.articles (id) ON DELETE CASCADE,
  version       integer NOT NULL CHECK (version >= 1),
  title         text NOT NULL,
  body          text NOT NULL,
  run_id        bigint REFERENCES vijesti.runs (id) ON DELETE SET NULL,
  created_by    text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (article_id, version)
);

-- Verzija članka ↔ trenutak na koji se poziva. Trenutak se ne smije obrisati
-- dok ga neka verzija citira.
CREATE TABLE vijesti.article_sources (
  version_id    bigint NOT NULL REFERENCES vijesti.article_versions (id) ON DELETE CASCADE,
  moment_id     bigint NOT NULL REFERENCES vijesti.moments (id) ON DELETE RESTRICT,
  position      integer NOT NULL DEFAULT 0 CHECK (position >= 0),
  PRIMARY KEY (version_id, moment_id)
);

CREATE TABLE vijesti.corrections (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  article_id    bigint NOT NULL REFERENCES vijesti.articles (id) ON DELETE CASCADE,
  -- Verzija koja ispravlja; prethodna ostaje u article_versions.
  version_id    bigint REFERENCES vijesti.article_versions (id) ON DELETE SET NULL,
  kind          text NOT NULL CHECK (kind IN ('quote', 'fact', 'attribution', 'other')),
  description   text NOT NULL CHECK (length(btrim(description)) > 0),
  created_by    text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

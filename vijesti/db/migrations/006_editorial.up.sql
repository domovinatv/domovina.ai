-- S5: urednički tok članka i API kroz Postgres (odluke 500–520).
-- Čitanje: PostgREST nad shemom `vijesti` uz RLS. Pisanje urednika: SECURITY
-- DEFINER funkcije (Supabase `rpc`) koje same provjere ulogu i dopušteni
-- prijelaz, atomarno. Engine piše kao vlasnik ili `service_role` (bez RLS-a).

-- Uloge PostgREST-a. Na Supabaseu već postoje; na PGliteu ih stvaramo. `down`
-- ih ne dira (odluka 502).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    CREATE ROLE anon NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    CREATE ROLE authenticated NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    CREATE ROLE service_role NOLOGIN BYPASSRLS;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- Shema
-- ---------------------------------------------------------------------------

ALTER TABLE vijesti.articles DROP CONSTRAINT articles_status_check;
ALTER TABLE vijesti.articles ADD CONSTRAINT articles_status_check
  CHECK (status IN ('draft', 'review', 'approved', 'published', 'corrected', 'rejected', 'retracted'));

-- Verzija pripada članku: složeni FK (članak, verzija) ne dopušta odobriti ili
-- objaviti tuđu verziju.
ALTER TABLE vijesti.article_versions
  ADD CONSTRAINT article_versions_article_id_id_key UNIQUE (article_id, id);

ALTER TABLE vijesti.articles
  ADD COLUMN approved_version_id  bigint,
  ADD COLUMN published_version_id bigint,
  ADD CONSTRAINT articles_approved_version_fkey FOREIGN KEY (id, approved_version_id)
    REFERENCES vijesti.article_versions (article_id, id),
  ADD CONSTRAINT articles_published_version_fkey FOREIGN KEY (id, published_version_id)
    REFERENCES vijesti.article_versions (article_id, id);

ALTER TABLE vijesti.corrections DROP CONSTRAINT corrections_kind_check;
ALTER TABLE vijesti.corrections
  ADD CONSTRAINT corrections_kind_check
    CHECK (kind IN ('quote', 'fact', 'attribution', 'other', 'retraction')),
  -- Verzija koja je bila objavljena prije ispravka ili povlačenja.
  ADD COLUMN replaced_version_id bigint REFERENCES vijesti.article_versions (id);

CREATE INDEX article_sources_moment_idx ON vijesti.article_sources (moment_id);

CREATE TABLE vijesti.staff (
  user_id   uuid PRIMARY KEY,
  role      text NOT NULL CHECK (role IN ('editor', 'admin')),
  added_by  uuid,
  added_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE vijesti.allowed_channels (
  channel   text PRIMARY KEY CHECK (length(btrim(channel)) > 0),
  note      text,
  added_by  uuid,
  added_at  timestamptz NOT NULL DEFAULT now()
);

-- Stroj stanja (odluka 504). Čita ga okidač i za vlasnika.
CREATE TABLE vijesti.article_transitions (
  from_status text NOT NULL,
  to_status   text NOT NULL,
  PRIMARY KEY (from_status, to_status)
);
INSERT INTO vijesti.article_transitions (from_status, to_status) VALUES
  ('draft', 'review'),
  ('draft', 'rejected'),
  ('review', 'draft'),
  ('review', 'approved'),
  ('review', 'rejected'),
  ('approved', 'review'),
  ('approved', 'published'),
  ('published', 'corrected'),
  ('corrected', 'corrected'),
  ('published', 'retracted'),
  ('corrected', 'retracted'),
  ('rejected', 'draft');

-- Dnevnik: jedan redak po prijelazu (i po nastanku članka), samo dodavanje.
CREATE TABLE vijesti.article_events (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  article_id   bigint NOT NULL REFERENCES vijesti.articles (id) ON DELETE CASCADE,
  -- NULL samo za nastanak članka.
  from_status  text,
  to_status    text NOT NULL,
  version_id   bigint REFERENCES vijesti.article_versions (id),
  actor        uuid,
  actor_label  text NOT NULL CHECK (length(btrim(actor_label)) > 0),
  note         text,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX article_events_article_idx ON vijesti.article_events (article_id, id);

-- Urednikovo razrješenje rečenice koju provjera nije potvrdila (odluka 507).
CREATE TABLE vijesti.sentence_resolutions (
  version_id  bigint NOT NULL REFERENCES vijesti.article_versions (id) ON DELETE CASCADE,
  n           integer NOT NULL CHECK (n >= 1),
  resolution  text NOT NULL CHECK (resolution IN ('verified', 'no_claim')),
  resolved_by uuid NOT NULL,
  note        text NOT NULL CHECK (length(btrim(note)) > 0),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (version_id, n)
);

-- ---------------------------------------------------------------------------
-- Identitet i uloge
-- ---------------------------------------------------------------------------

-- Isto što Supabaseov `auth.uid()`, bez ovisnosti o shemi `auth`.
CREATE FUNCTION vijesti.current_user_id() RETURNS uuid
LANGUAGE sql STABLE SET search_path = vijesti, pg_temp AS $$
  SELECT CASE WHEN s ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN s::uuid END
  FROM (SELECT nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub' AS s) c
$$;

-- `admin` ima sva prava urednika.
CREATE FUNCTION vijesti.has_role(p_role text) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
  SELECT EXISTS (
    SELECT 1 FROM vijesti.staff s
    WHERE s.user_id = vijesti.current_user_id()
      AND CASE p_role
            WHEN 'editor' THEN s.role IN ('editor', 'admin')
            WHEN 'admin' THEN s.role = 'admin'
            ELSE false
          END
  )
$$;

CREATE FUNCTION vijesti._require_role(p_role text) RETURNS uuid
LANGUAGE plpgsql STABLE SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti.current_user_id();
BEGIN
  IF uid IS NULL THEN
    RAISE EXCEPTION 'forbidden: potrebna je prijava';
  END IF;
  IF NOT vijesti.has_role(p_role) THEN
    RAISE EXCEPTION 'forbidden: potrebna je uloga %', p_role;
  END IF;
  RETURN uid;
END
$$;

-- Oznaka autora za `created_by` i dnevnik: korisnik ili uloga baze. Zove se iz
-- SECURITY DEFINER okidača, gdje je `current_user` vlasnik funkcije: uloga
-- pozivatelja je postavka `role` (SET ROLE, kako radi PostgREST), inače
-- `session_user` (odluka 527).
CREATE FUNCTION vijesti._actor_label() RETURNS text
LANGUAGE sql STABLE SET search_path = vijesti, pg_temp AS $$
  SELECT coalesce(
    nullif(current_setting('vijesti.actor_label', true), ''),
    'editor:' || vijesti.current_user_id()::text,
    'db:' || coalesce(nullif(current_setting('role'), 'none'), session_user)
  )
$$;

-- ---------------------------------------------------------------------------
-- Okidači: stroj stanja, dnevnik, samo dodavanje. SECURITY DEFINER jer ih okida
-- i `service_role` (engine na Supabaseu), koji nema EXECUTE na pomoćnim funkcijama.
-- ---------------------------------------------------------------------------

CREATE FUNCTION vijesti._articles_status_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  -- Nepoznato stanje prijavljuje CHECK (articles_status_check).
  IF NOT EXISTS (SELECT 1 FROM vijesti.article_transitions WHERE to_status = NEW.status) THEN
    RETURN NEW;
  END IF;
  -- Članak nastaje samo kao nacrt (odluka 522).
  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'draft' OR NEW.approved_version_id IS NOT NULL
       OR NEW.published_version_id IS NOT NULL OR NEW.published_at IS NOT NULL THEN
      RAISE EXCEPTION 'invalid_state: članak se stvara samo kao nacrt, bez odobrene i objavljene verzije';
    END IF;
    RETURN NEW;
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT EXISTS (
    SELECT 1 FROM vijesti.article_transitions WHERE from_status = OLD.status AND to_status = NEW.status
  ) THEN
    RAISE EXCEPTION 'invalid_transition: % → % nije dopušten (članak %)', OLD.status, NEW.status, OLD.id;
  END IF;
  -- Verzije i tragovi vrijede za svaki UPDATE, ne samo za promjenu stanja (odluka 523).
  IF NEW.approved_version_id IS NOT NULL AND NEW.approved_version_id IS DISTINCT FROM OLD.approved_version_id
     AND OLD.status <> 'review' THEN
    RAISE EXCEPTION 'invalid_state: odobrena verzija se postavlja samo članku u pregledu (članak %)', OLD.id;
  END IF;
  IF NEW.published_version_id IS DISTINCT FROM OLD.published_version_id THEN
    IF OLD.published_version_id IS NULL THEN
      IF OLD.status <> 'approved' OR NEW.published_version_id IS DISTINCT FROM OLD.approved_version_id THEN
        RAISE EXCEPTION 'invalid_state: objavljuje se samo odobrena verzija odobrenog članka (članak %)', OLD.id;
      END IF;
    ELSIF NOT EXISTS (
      SELECT 1 FROM vijesti.corrections c
      WHERE c.article_id = OLD.id AND c.kind <> 'retraction'
        AND c.version_id = NEW.published_version_id AND c.replaced_version_id = OLD.published_version_id
    ) THEN
      RAISE EXCEPTION 'invalid_state: objavljena verzija se mijenja samo uz zapis ispravka (članak %)', OLD.id;
    END IF;
  END IF;
  IF NEW.status = 'approved' AND NEW.approved_version_id IS NULL THEN
    RAISE EXCEPTION 'invalid_state: odobren članak mora imati odobrenu verziju (članak %)', OLD.id;
  END IF;
  IF NEW.status IN ('published', 'corrected') AND NEW.published_version_id IS NULL THEN
    RAISE EXCEPTION 'invalid_state: objavljen članak mora imati objavljenu verziju (članak %)', OLD.id;
  END IF;
  IF NEW.status = 'corrected' AND NOT EXISTS (
    SELECT 1 FROM vijesti.corrections c
    WHERE c.article_id = OLD.id AND c.kind <> 'retraction' AND c.version_id = NEW.published_version_id
  ) THEN
    RAISE EXCEPTION 'invalid_state: ispravljen članak mora imati zapis ispravka objavljene verzije (članak %)', OLD.id;
  END IF;
  IF NEW.status = 'retracted' AND NOT EXISTS (
    SELECT 1 FROM vijesti.corrections c WHERE c.article_id = OLD.id AND c.kind = 'retraction'
  ) THEN
    RAISE EXCEPTION 'invalid_state: povučen članak mora imati obavijest o povlačenju (članak %)', OLD.id;
  END IF;
  RETURN NEW;
END
$$;

-- Svaki INSERT i UPDATE, ne samo `UPDATE OF status`: inače bi vlasnik ili
-- engine tiho zamijenio objavljenu verziju (odluke 504, 522, 523).
CREATE TRIGGER articles_status_guard
  BEFORE INSERT OR UPDATE ON vijesti.articles
  FOR EACH ROW EXECUTE FUNCTION vijesti._articles_status_guard();

CREATE FUNCTION vijesti._articles_status_log() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  IF NEW.status = OLD.status AND NOT EXISTS (
    SELECT 1 FROM vijesti.article_transitions WHERE from_status = OLD.status AND to_status = NEW.status
  ) THEN
    RETURN NULL;
  END IF;
  INSERT INTO vijesti.article_events (article_id, from_status, to_status, version_id, actor, actor_label, note)
  VALUES (
    NEW.id,
    OLD.status,
    NEW.status,
    coalesce(
      nullif(current_setting('vijesti.event_version', true), '')::bigint,
      (SELECT v.id FROM vijesti.article_versions v WHERE v.article_id = NEW.id ORDER BY v.version DESC LIMIT 1)
    ),
    vijesti.current_user_id(),
    vijesti._actor_label(),
    nullif(current_setting('vijesti.event_note', true), '')
  );
  RETURN NULL;
END
$$;

CREATE TRIGGER articles_status_log
  AFTER UPDATE OF status ON vijesti.articles
  FOR EACH ROW EXECUTE FUNCTION vijesti._articles_status_log();

-- Jedini put promjene stanja iz funkcija: postavi kontekst dnevnika, promijeni
-- stanje, očisti kontekst. Odobrena verzija vrijedi samo u stanju `approved`
-- i dalje (objava); povratak u pregled, nacrt ili odbijanje je briše.
CREATE FUNCTION vijesti._transition(p_article_id bigint, p_to text, p_version_id bigint, p_note text, p_label text)
RETURNS void
LANGUAGE plpgsql SET search_path = vijesti, pg_temp AS $$
BEGIN
  PERFORM set_config('vijesti.event_version', coalesce(p_version_id::text, ''), true);
  PERFORM set_config('vijesti.event_note', coalesce(p_note, ''), true);
  PERFORM set_config('vijesti.actor_label', coalesce(p_label, ''), true);
  UPDATE vijesti.articles
     SET status = p_to,
         updated_at = now(),
         approved_version_id = CASE WHEN p_to IN ('review', 'draft', 'rejected') THEN NULL ELSE approved_version_id END
   WHERE id = p_article_id;
  PERFORM set_config('vijesti.event_version', '', true);
  PERFORM set_config('vijesti.event_note', '', true);
  PERFORM set_config('vijesti.actor_label', '', true);
END
$$;

-- Nova verzija: prva upisuje nastanak članka; verzija na odobrenom članku ga
-- vraća u pregled (odobrava se verzija, ne članak).
CREATE FUNCTION vijesti._article_versions_after_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  st text;
BEGIN
  SELECT status INTO st FROM vijesti.articles WHERE id = NEW.article_id FOR UPDATE;
  IF NEW.version = 1 THEN
    INSERT INTO vijesti.article_events (article_id, from_status, to_status, version_id, actor, actor_label, note)
    VALUES (NEW.article_id, NULL, st, NEW.id, vijesti.current_user_id(),
            coalesce(NEW.created_by, vijesti._actor_label()), 'članak stvoren');
  ELSIF st = 'approved' THEN
    PERFORM vijesti._transition(NEW.article_id, 'review', NEW.id,
      'nova verzija ' || NEW.version::text || ' na odobrenom članku', coalesce(NEW.created_by, vijesti._actor_label()));
  END IF;
  RETURN NULL;
END
$$;

CREATE TRIGGER article_versions_after_insert
  AFTER INSERT ON vijesti.article_versions
  FOR EACH ROW EXECUTE FUNCTION vijesti._article_versions_after_insert();

-- Dnevnik se ne mijenja ni ne briše, ni vlasniku. Iznimka: brisanje cijelog
-- članka (CASCADE) nosi i njegov dnevnik (odluka 505).
CREATE FUNCTION vijesti._article_events_append_only() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM vijesti.articles WHERE id = OLD.article_id) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'append_only: dnevnik prijelaza se ne mijenja (%)', TG_OP;
END
$$;

CREATE TRIGGER article_events_append_only
  BEFORE UPDATE OR DELETE ON vijesti.article_events
  FOR EACH ROW EXECUTE FUNCTION vijesti._article_events_append_only();

CREATE FUNCTION vijesti._article_events_no_truncate() RETURNS trigger
LANGUAGE plpgsql SET search_path = vijesti, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'append_only: dnevnik prijelaza se ne mijenja (TRUNCATE)';
END
$$;

CREATE TRIGGER article_events_no_truncate
  BEFORE TRUNCATE ON vijesti.article_events
  FOR EACH STATEMENT EXECUTE FUNCTION vijesti._article_events_no_truncate();

-- Zapis ispravka i povlačenja je javni trag: ne mijenja se ni ne briše, ni
-- vlasniku. Iznimka kao za dnevnik: brisanje cijelog članka (CASCADE, uz FK
-- `version_id → SET NULL` u istoj naredbi) (odluka 521).
CREATE FUNCTION vijesti._corrections_append_only() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM vijesti.articles WHERE id = OLD.article_id) THEN
    RETURN CASE WHEN TG_OP = 'DELETE' THEN OLD ELSE NEW END;
  END IF;
  RAISE EXCEPTION 'append_only: zapis ispravka se ne mijenja (%)', TG_OP;
END
$$;

CREATE TRIGGER corrections_append_only
  BEFORE UPDATE OR DELETE ON vijesti.corrections
  FOR EACH ROW EXECUTE FUNCTION vijesti._corrections_append_only();

-- Razrješenje rečenice je urednikovo jamstvo uz odobrenje: isto samo dodavanje.
-- Iznimka: brisanje verzije (CASCADE iz brisanja članka) (odluka 521).
CREATE FUNCTION vijesti._sentence_resolutions_append_only() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  IF TG_OP = 'DELETE' AND NOT EXISTS (SELECT 1 FROM vijesti.article_versions WHERE id = OLD.version_id) THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION 'append_only: razrješenje rečenice se ne mijenja (%)', TG_OP;
END
$$;

CREATE TRIGGER sentence_resolutions_append_only
  BEFORE UPDATE OR DELETE ON vijesti.sentence_resolutions
  FOR EACH ROW EXECUTE FUNCTION vijesti._sentence_resolutions_append_only();

CREATE FUNCTION vijesti._append_only_no_truncate() RETURNS trigger
LANGUAGE plpgsql SET search_path = vijesti, pg_temp AS $$
BEGIN
  RAISE EXCEPTION 'append_only: % se ne prazni (TRUNCATE)', TG_TABLE_NAME;
END
$$;

CREATE TRIGGER corrections_no_truncate
  BEFORE TRUNCATE ON vijesti.corrections
  FOR EACH STATEMENT EXECUTE FUNCTION vijesti._append_only_no_truncate();
CREATE TRIGGER sentence_resolutions_no_truncate
  BEFORE TRUNCATE ON vijesti.sentence_resolutions
  FOR EACH STATEMENT EXECUTE FUNCTION vijesti._append_only_no_truncate();

-- Verzija se nikad ne mijenja (odobrava se verzija, odluka 506). Dopušteno je
-- samo `run_id → NULL` iz FK-a pri brisanju runa.
CREATE FUNCTION vijesti._article_versions_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
BEGIN
  IF ROW(NEW.id, NEW.article_id, NEW.version, NEW.title, NEW.body, NEW.lead, NEW.category, NEW.content,
         NEW.word_count, NEW.prompt_version, NEW.verify, NEW.created_by, NEW.created_at)
     IS DISTINCT FROM
     ROW(OLD.id, OLD.article_id, OLD.version, OLD.title, OLD.body, OLD.lead, OLD.category, OLD.content,
         OLD.word_count, OLD.prompt_version, OLD.verify, OLD.created_by, OLD.created_at)
     OR (NEW.run_id IS NOT NULL AND NEW.run_id IS DISTINCT FROM OLD.run_id) THEN
    RAISE EXCEPTION 'immutable: verzija % se ne mijenja; izmjena je nova verzija', OLD.id;
  END IF;
  RETURN NEW;
END
$$;

CREATE TRIGGER article_versions_immutable
  BEFORE UPDATE ON vijesti.article_versions
  FOR EACH ROW EXECUTE FUNCTION vijesti._article_versions_immutable();

-- ---------------------------------------------------------------------------
-- Pomoćne funkcije sadržaja (isto što engine/write/content.ts i text.ts)
-- ---------------------------------------------------------------------------

-- `clock` iz text.ts: m:ss ili h:mm:ss.
CREATE FUNCTION vijesti._clock(p_ms integer) RETURNS text
LANGUAGE sql IMMUTABLE SET search_path = vijesti, pg_temp AS $$
  SELECT CASE WHEN h > 0
    THEN h::text || ':' || lpad(mm::text, 2, '0') || ':' || lpad(ss::text, 2, '0')
    ELSE mm::text || ':' || lpad(ss::text, 2, '0')
  END
  FROM (SELECT s / 3600 AS h, (s % 3600) / 60 AS mm, s % 60 AS ss FROM (SELECT p_ms / 1000 AS s) x) y
$$;

-- `wordCount` iz text.ts (isti uzorak WORD_RE).
CREATE FUNCTION vijesti._word_count(p_text text) RETURNS integer
LANGUAGE sql IMMUTABLE SET search_path = vijesti, pg_temp AS $$
  SELECT count(*)::integer FROM regexp_matches(
    coalesce(p_text, ''),
    '[[:digit:]]+(?:[.,][[:digit:]]+)*(?![[:alpha:]])|[[:alnum:]]+(?:[-''’][[:alnum:]]+)*',
    'g'
  )
$$;

-- `renderQuote` iz content.ts.
CREATE FUNCTION vijesti._render_quote(p_moment_id bigint) RETURNS text
LANGUAGE sql STABLE SET search_path = vijesti, pg_temp AS $$
  SELECT '„' || m.quote || '” – ' || coalesce(m.speaker_name, m.speaker) || ', ' || vijesti._clock(m.start_ms)
         || CASE WHEN m.quote_lang = 'hr' THEN '' ELSE ' (izvornik, ' || m.quote_lang || ')' END
  FROM vijesti.moments m WHERE m.id = p_moment_id
$$;

CREATE FUNCTION vijesti._latest_version_id(p_article_id bigint) RETURNS bigint
LANGUAGE sql STABLE SET search_path = vijesti, pg_temp AS $$
  SELECT id FROM vijesti.article_versions WHERE article_id = p_article_id ORDER BY version DESC LIMIT 1
$$;

-- Uvjet odobravanja i ispravka (odluka 506): verzija ima provjeru koja je
-- napravljena nad njom i svaka rečenica koja nije `supported` je razriješena.
CREATE FUNCTION vijesti._require_ready(p_version_id bigint) RETURNS void
LANGUAGE plpgsql STABLE SET search_path = vijesti, pg_temp AS $$
DECLARE
  v record;
  open_n integer[];
BEGIN
  SELECT id, version, verify INTO v FROM vijesti.article_versions WHERE id = p_version_id;
  IF v.verify IS NULL THEN
    RAISE EXCEPTION 'not_verified: verzija % nema provjeru (pokreni verify)', p_version_id;
  END IF;
  IF jsonb_typeof(v.verify -> 'sentences') IS DISTINCT FROM 'array'
     OR NOT coalesce((v.verify ->> 'base_version') ~ '^[0-9]+$' AND (v.verify ->> 'base_version')::integer < v.version, false) THEN
    RAISE EXCEPTION 'not_verified: provjera verzije % nije valjana provjera te verzije', p_version_id;
  END IF;
  SELECT array_agg(x.n ORDER BY x.n) INTO open_n
  FROM (
    SELECT (s ->> 'n')::integer AS n
    FROM jsonb_array_elements(v.verify -> 'sentences') s
    WHERE (s ->> 'status') IS DISTINCT FROM 'supported'
  ) x
  WHERE x.n IS NULL OR NOT EXISTS (
    SELECT 1 FROM vijesti.sentence_resolutions r WHERE r.version_id = p_version_id AND r.n = x.n
  );
  IF open_n IS NOT NULL THEN
    RAISE EXCEPTION 'unresolved: verzija % ima nerazriješene rečenice %', p_version_id, open_n;
  END IF;
END
$$;

CREATE FUNCTION vijesti._lock_article(p_article_id bigint) RETURNS vijesti.articles
LANGUAGE plpgsql SET search_path = vijesti, pg_temp AS $$
DECLARE
  a vijesti.articles;
BEGIN
  SELECT * INTO a FROM vijesti.articles WHERE id = p_article_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: članak % ne postoji', p_article_id;
  END IF;
  RETURN a;
END
$$;

CREATE FUNCTION vijesti._nonblank(p_value text, p_what text) RETURNS text
LANGUAGE plpgsql IMMUTABLE SET search_path = vijesti, pg_temp AS $$
BEGIN
  -- Razmak, tabulator ili NBSP nije obrazloženje: barem jedno slovo ili znamenka (odluka 526).
  IF p_value IS NULL OR p_value !~ '[[:alnum:]]' THEN
    RAISE EXCEPTION 'invalid_input: % ne smije biti prazno (barem jedno slovo ili znamenka)', p_what;
  END IF;
  RETURN p_value;
END
$$;

-- ---------------------------------------------------------------------------
-- Javni API urednika (rpc)
-- ---------------------------------------------------------------------------

-- Jednostavni prijelazi: u pregled, natrag u nacrt, odbijanje, ponovno otvaranje,
-- povlačenje odobrenja. Odobravanje, objava, ispravak i povlačenje imaju svoje funkcije.
CREATE FUNCTION vijesti.transition_article(p_article_id bigint, p_to text, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF p_to IS NULL OR p_to NOT IN ('review', 'draft', 'rejected') THEN
    RAISE EXCEPTION 'invalid_input: prijelaz u % ide kroz svoju funkciju (approve, publish, correct, retract)', coalesce(p_to, 'NULL');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM vijesti.article_transitions WHERE from_status = a.status AND to_status = p_to) THEN
    RAISE EXCEPTION 'invalid_transition: % → % nije dopušten (članak %)', a.status, p_to, a.id;
  END IF;
  IF p_to = 'rejected' THEN
    PERFORM vijesti._nonblank(p_note, 'obrazloženje odbijanja');
  END IF;
  PERFORM vijesti._transition(a.id, p_to, NULL, nullif(btrim(coalesce(p_note, '')), ''), 'editor:' || uid::text);
END
$$;

-- review → approved za točno navedenu verziju, koja mora biti zadnja.
CREATE FUNCTION vijesti.approve_article(p_article_id bigint, p_version_id bigint, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF a.status <> 'review' THEN
    RAISE EXCEPTION 'invalid_transition: % → approved nije dopušten (članak %)', a.status, a.id;
  END IF;
  IF p_version_id IS DISTINCT FROM vijesti._latest_version_id(a.id) THEN
    RAISE EXCEPTION 'stale_version: verzija % nije zadnja verzija članka %', coalesce(p_version_id::text, 'NULL'), a.id;
  END IF;
  PERFORM vijesti._require_ready(p_version_id);
  UPDATE vijesti.articles SET approved_version_id = p_version_id WHERE id = a.id;
  PERFORM vijesti._transition(a.id, 'approved', p_version_id, nullif(btrim(coalesce(p_note, '')), ''), 'editor:' || uid::text);
END
$$;

-- approved → published: objavljuje se odobrena verzija, samo s dopuštenog kanala.
CREATE FUNCTION vijesti.publish_article(p_article_id bigint, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
  ch text;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF a.status <> 'approved' THEN
    RAISE EXCEPTION 'invalid_transition: % → published nije dopušten (članak %)', a.status, a.id;
  END IF;
  IF a.approved_version_id IS DISTINCT FROM vijesti._latest_version_id(a.id) THEN
    RAISE EXCEPTION 'stale_version: odobrena verzija nije zadnja (članak %)', a.id;
  END IF;
  SELECT content -> 'episode' ->> 'channel' INTO ch FROM vijesti.article_versions WHERE id = a.approved_version_id;
  IF ch IS NULL OR NOT EXISTS (SELECT 1 FROM vijesti.allowed_channels WHERE channel = ch) THEN
    RAISE EXCEPTION 'channel_not_allowed: kanal % nije na popisu dopuštenih', coalesce(ch, '(nepoznat)');
  END IF;
  UPDATE vijesti.articles
     SET published_version_id = a.approved_version_id,
         published_at = coalesce(published_at, now())
   WHERE id = a.id;
  PERFORM vijesti._transition(a.id, 'published', a.approved_version_id, nullif(btrim(coalesce(p_note, '')), ''), 'editor:' || uid::text);
END
$$;

-- Urednička izmjena = nova verzija bez provjere (odluka 508). Izvori: svi
-- trenutci prethodne verzije (s istim pozicijama) + novi citirani trenutci iste
-- epizode na kraju. `body` i `word_count` računa baza iz blokova i trenutaka.
CREATE FUNCTION vijesti.save_editor_version(
  p_article_id bigint,
  p_base_version_id bigint,
  p_title text,
  p_lead text,
  p_category text,
  p_blocks jsonb
) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
  base vijesti.article_versions;
  video text;
  blk jsonb;
  mid bigint;
  pos integer;
  idx integer;
  next_pos integer;
  new_ids bigint[] := '{}';
  blocks jsonb := '[]'::jsonb;
  parts text[] := '{}';
  words integer;
  new_id bigint;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF a.status IN ('rejected', 'retracted') THEN
    RAISE EXCEPTION 'invalid_state: članak % je u stanju % i ne uređuje se', a.id, a.status;
  END IF;
  SELECT * INTO base FROM vijesti.article_versions WHERE article_id = a.id ORDER BY version DESC LIMIT 1;
  IF base.id IS NULL OR base.id IS DISTINCT FROM p_base_version_id THEN
    RAISE EXCEPTION 'stale_version: verzija % nije zadnja verzija članka %', coalesce(p_base_version_id::text, 'NULL'), a.id;
  END IF;
  IF base.content IS NULL THEN
    RAISE EXCEPTION 'invalid_state: zadnja verzija članka % nema strukturirani sadržaj', a.id;
  END IF;
  PERFORM vijesti._nonblank(p_title, 'naslov');
  PERFORM vijesti._nonblank(p_lead, 'lead');
  IF p_category IS NULL OR p_category !~ '^[a-z]+(-[a-z]+)*$' THEN
    RAISE EXCEPTION 'invalid_input: kategorija mora biti slug';
  END IF;
  IF jsonb_typeof(p_blocks) IS DISTINCT FROM 'array' OR jsonb_array_length(p_blocks) = 0 THEN
    RAISE EXCEPTION 'invalid_input: blokovi moraju biti neprazan niz';
  END IF;
  video := base.content -> 'episode' ->> 'videoId';
  SELECT coalesce(max(position), 0) INTO next_pos FROM vijesti.article_sources WHERE version_id = base.id;
  words := vijesti._word_count(p_lead);

  FOR blk IN SELECT value FROM jsonb_array_elements(p_blocks) LOOP
    IF jsonb_typeof(blk) IS DISTINCT FROM 'object' THEN
      RAISE EXCEPTION 'invalid_input: blok mora biti objekt';
    ELSIF blk ->> 'type' = 'p' THEN
      IF jsonb_typeof(blk -> 'text') IS DISTINCT FROM 'string' OR btrim(blk ->> 'text') = '' THEN
        RAISE EXCEPTION 'invalid_input: odlomak mora imati tekst';
      END IF;
      blocks := blocks || jsonb_build_array(jsonb_build_object('type', 'p', 'text', blk ->> 'text'));
      parts := parts || (blk ->> 'text');
      words := words + vijesti._word_count(blk ->> 'text');
    ELSIF blk ->> 'type' = 'quote' THEN
      IF jsonb_typeof(blk -> 'moment_id') IS DISTINCT FROM 'number' OR (blk ->> 'moment_id') !~ '^[0-9]{1,18}$' THEN
        RAISE EXCEPTION 'invalid_input: citat mora imati cjelobrojni moment_id';
      END IF;
      mid := (blk ->> 'moment_id')::bigint;
      IF NOT EXISTS (
        SELECT 1 FROM vijesti.moments m WHERE m.id = mid AND m.video_id = video AND m.quote_check <> 'failed'
      ) THEN
        RAISE EXCEPTION 'invalid_quote: trenutak % ne postoji, nije iz epizode % ili mu citat nije potvrđen', mid, video;
      END IF;
      SELECT s.position INTO pos FROM vijesti.article_sources s WHERE s.version_id = base.id AND s.moment_id = mid;
      IF NOT FOUND THEN
        idx := array_position(new_ids, mid);
        IF idx IS NULL THEN
          new_ids := new_ids || mid;
          idx := array_length(new_ids, 1);
        END IF;
        pos := next_pos + idx;
      END IF;
      blocks := blocks || jsonb_build_array(jsonb_build_object('type', 'quote', 'moment_id', mid, 'ref', 't' || pos::text));
      parts := parts || vijesti._render_quote(mid);
      words := words + vijesti._word_count((SELECT quote FROM vijesti.moments WHERE id = mid));
    ELSE
      RAISE EXCEPTION 'invalid_input: nepoznata vrsta bloka %', coalesce(blk ->> 'type', 'NULL');
    END IF;
  END LOOP;

  INSERT INTO vijesti.article_versions
    (article_id, version, title, body, lead, category, content, word_count, prompt_version, verify, run_id, created_by)
  VALUES (
    a.id, base.version + 1, p_title, array_to_string(parts, E'\n\n'), p_lead, p_category,
    jsonb_build_object(
      'schema', base.content -> 'schema',
      'episode', base.content -> 'episode',
      'title', p_title,
      'lead', p_lead,
      'category', p_category,
      'blocks', blocks
    ),
    words, NULL, NULL, NULL, 'editor:' || uid::text
  ) RETURNING id INTO new_id;

  INSERT INTO vijesti.article_sources (version_id, moment_id, position)
  SELECT new_id, s.moment_id, s.position FROM vijesti.article_sources s WHERE s.version_id = base.id;
  INSERT INTO vijesti.article_sources (version_id, moment_id, position)
  SELECT new_id, x.mid, next_pos + x.ord::integer FROM unnest(new_ids) WITH ORDINALITY AS x (mid, ord);

  RETURN new_id;
END
$$;

-- Urednik razrješava rečenicu zadnje verzije koju provjera nije potvrdila.
CREATE FUNCTION vijesti.resolve_sentence(p_version_id bigint, p_n integer, p_resolution text, p_note text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  v vijesti.article_versions;
  a vijesti.articles;
BEGIN
  SELECT * INTO v FROM vijesti.article_versions WHERE id = p_version_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: verzija % ne postoji', p_version_id;
  END IF;
  a := vijesti._lock_article(v.article_id);
  IF a.status NOT IN ('draft', 'review', 'published', 'corrected') THEN
    RAISE EXCEPTION 'invalid_state: u stanju % se rečenice ne razrješavaju (članak %)', a.status, a.id;
  END IF;
  IF v.id IS DISTINCT FROM vijesti._latest_version_id(a.id) THEN
    RAISE EXCEPTION 'stale_version: verzija % nije zadnja verzija članka %', v.id, a.id;
  END IF;
  IF v.verify IS NULL THEN
    RAISE EXCEPTION 'not_verified: verzija % nema provjeru', v.id;
  END IF;
  IF p_resolution IS NULL OR p_resolution NOT IN ('verified', 'no_claim') THEN
    RAISE EXCEPTION 'invalid_input: razrješenje mora biti verified ili no_claim';
  END IF;
  PERFORM vijesti._nonblank(p_note, 'bilješka razrješenja');
  IF NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(v.verify -> 'sentences') = 'array'
                                            THEN v.verify -> 'sentences' ELSE '[]'::jsonb END) s
    WHERE (s ->> 'n') = p_n::text AND (s ->> 'status') IS DISTINCT FROM 'supported'
  ) THEN
    RAISE EXCEPTION 'invalid_input: rečenica % verzije % nije označena kao nepotvrđena', p_n, v.id;
  END IF;
  INSERT INTO vijesti.sentence_resolutions (version_id, n, resolution, resolved_by, note)
  VALUES (v.id, p_n, p_resolution, uid, p_note)
  ON CONFLICT (version_id, n) DO NOTHING;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'already_resolved: rečenica % verzije % je već razriješena', p_n, v.id;
  END IF;
END
$$;

-- Ispravak objavljenog članka: zadnja verzija (provjerena i razriješena)
-- postaje objavljena, uz javni zapis u `corrections`.
CREATE FUNCTION vijesti.correct_article(p_article_id bigint, p_version_id bigint, p_kind text, p_description text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
  cid bigint;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF a.status NOT IN ('published', 'corrected') THEN
    RAISE EXCEPTION 'invalid_transition: % → corrected nije dopušten (članak %)', a.status, a.id;
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('quote', 'fact', 'attribution', 'other') THEN
    RAISE EXCEPTION 'invalid_input: vrsta ispravka mora biti quote, fact, attribution ili other';
  END IF;
  PERFORM vijesti._nonblank(p_description, 'opis ispravka');
  IF p_version_id IS DISTINCT FROM vijesti._latest_version_id(a.id) THEN
    RAISE EXCEPTION 'stale_version: verzija % nije zadnja verzija članka %', coalesce(p_version_id::text, 'NULL'), a.id;
  END IF;
  IF p_version_id = a.published_version_id THEN
    RAISE EXCEPTION 'invalid_input: verzija % je već objavljena', p_version_id;
  END IF;
  PERFORM vijesti._require_ready(p_version_id);
  INSERT INTO vijesti.corrections (article_id, version_id, kind, description, created_by, replaced_version_id)
  VALUES (a.id, p_version_id, p_kind, p_description, 'editor:' || uid::text, a.published_version_id)
  RETURNING id INTO cid;
  UPDATE vijesti.articles SET published_version_id = p_version_id WHERE id = a.id;
  PERFORM vijesti._transition(a.id, 'corrected', p_version_id, p_description, 'editor:' || uid::text);
  RETURN cid;
END
$$;

-- Povlačenje: javno ostaje obavijest (corrections, kind `retraction`), tijelo se skriva.
CREATE FUNCTION vijesti.retract_article(p_article_id bigint, p_reason text)
RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('editor');
  a vijesti.articles;
  cid bigint;
BEGIN
  a := vijesti._lock_article(p_article_id);
  IF a.status NOT IN ('published', 'corrected') THEN
    RAISE EXCEPTION 'invalid_transition: % → retracted nije dopušten (članak %)', a.status, a.id;
  END IF;
  PERFORM vijesti._nonblank(p_reason, 'razlog povlačenja');
  INSERT INTO vijesti.corrections (article_id, version_id, kind, description, created_by, replaced_version_id)
  VALUES (a.id, NULL, 'retraction', p_reason, 'editor:' || uid::text, a.published_version_id)
  RETURNING id INTO cid;
  PERFORM vijesti._transition(a.id, 'retracted', a.published_version_id, p_reason, 'editor:' || uid::text);
  RETURN cid;
END
$$;

-- Administracija: uloge i dopušteni kanali. Zadnji admin se ne može ukloniti.
CREATE FUNCTION vijesti.set_staff_role(p_user_id uuid, p_role text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('admin');
BEGIN
  IF p_user_id IS NULL OR p_role IS NULL OR p_role NOT IN ('editor', 'admin') THEN
    RAISE EXCEPTION 'invalid_input: korisnik i uloga (editor ili admin) su obavezni';
  END IF;
  PERFORM 1 FROM vijesti.staff WHERE role = 'admin' FOR UPDATE;
  IF p_role = 'editor' AND EXISTS (SELECT 1 FROM vijesti.staff WHERE user_id = p_user_id AND role = 'admin')
     AND (SELECT count(*) FROM vijesti.staff WHERE role = 'admin') = 1 THEN
    RAISE EXCEPTION 'last_admin: zadnji admin ne može izgubiti ulogu';
  END IF;
  INSERT INTO vijesti.staff (user_id, role, added_by) VALUES (p_user_id, p_role, uid)
  ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role, added_by = EXCLUDED.added_by, added_at = now();
END
$$;

CREATE FUNCTION vijesti.remove_staff(p_user_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('admin');
BEGIN
  PERFORM 1 FROM vijesti.staff WHERE role = 'admin' FOR UPDATE;
  IF EXISTS (SELECT 1 FROM vijesti.staff WHERE user_id = p_user_id AND role = 'admin')
     AND (SELECT count(*) FROM vijesti.staff WHERE role = 'admin') = 1 THEN
    RAISE EXCEPTION 'last_admin: zadnji admin se ne može ukloniti';
  END IF;
  DELETE FROM vijesti.staff WHERE user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: korisnik % nema ulogu', p_user_id;
  END IF;
  PERFORM uid;
END
$$;

CREATE FUNCTION vijesti.allow_channel(p_channel text, p_note text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('admin');
BEGIN
  PERFORM vijesti._nonblank(p_channel, 'kanal');
  INSERT INTO vijesti.allowed_channels (channel, note, added_by) VALUES (btrim(p_channel), p_note, uid)
  ON CONFLICT (channel) DO UPDATE SET note = EXCLUDED.note, added_by = EXCLUDED.added_by, added_at = now();
END
$$;

CREATE FUNCTION vijesti.disallow_channel(p_channel text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = vijesti, pg_temp AS $$
DECLARE
  uid uuid := vijesti._require_role('admin');
BEGIN
  DELETE FROM vijesti.allowed_channels WHERE channel = p_channel;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not_found: kanal % nije na popisu', coalesce(p_channel, 'NULL');
  END IF;
  PERFORM uid;
END
$$;

-- ---------------------------------------------------------------------------
-- Pogledi
-- ---------------------------------------------------------------------------

-- Javni stupci verzije (bez `verify`, `run_id`, `created_by`), prava čitatelja.
CREATE VIEW vijesti.public_article_versions WITH (security_invoker = true) AS
SELECT id, article_id, version, title, body, lead, category, content, word_count, prompt_version, created_at
FROM vijesti.article_versions;

CREATE VIEW vijesti.public_corrections WITH (security_invoker = true) AS
SELECT id, article_id, version_id, kind, description, created_at
FROM vijesti.corrections;

-- Javni stupci trenutka: citat i vrijeme, bez ocjene, sažetka modela, razloga
-- odbijanja i runova (odluka 524).
CREATE VIEW vijesti.public_moments WITH (security_invoker = true) AS
SELECT id, video_id, start_ms, end_ms, speaker, speaker_name, quote, quote_check, quote_match, quote_lang,
       topics, entities, cue_from, cue_to, created_at
FROM vijesti.moments;

-- Naslov priče je naslov prve (generatorove) verzije, dakle nacrt (odluka 525).
CREATE VIEW vijesti.public_stories WITH (security_invoker = true) AS
SELECT id, slug, created_at, updated_at
FROM vijesti.stories;

-- Pune verzije (s provjerom) samo za urednike: prava vlasnika, filtar uloge.
CREATE VIEW vijesti.editor_article_versions WITH (security_barrier = true) AS
SELECT v.*
FROM vijesti.article_versions v
WHERE vijesti.has_role('editor');

-- Red čekanja za verify (S8): zadnja verzija sa sadržajem, bez provjere.
CREATE VIEW vijesti.versions_awaiting_verify WITH (security_barrier = true) AS
SELECT a.id AS article_id, a.status, v.id AS version_id, v.version, v.created_by, v.created_at
FROM vijesti.articles a
JOIN LATERAL (
  SELECT * FROM vijesti.article_versions x WHERE x.article_id = a.id ORDER BY x.version DESC LIMIT 1
) v ON true
WHERE v.verify IS NULL
  AND v.content IS NOT NULL
  AND a.status NOT IN ('rejected', 'retracted')
  AND (vijesti.has_role('editor') OR current_user NOT IN ('anon', 'authenticated'));

-- ---------------------------------------------------------------------------
-- RLS i prava
-- ---------------------------------------------------------------------------

ALTER TABLE vijesti.runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.moments ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.stories ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.story_moments ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.articles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.eval_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.eval_sample ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.allowed_channels ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_transitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.article_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE vijesti.sentence_resolutions ENABLE ROW LEVEL SECURITY;

-- Javno (odluka 509): objavljeni, ispravljeni i povučeni članci; od verzija
-- samo trenutno objavljena, a za povučen članak nijedna.
CREATE POLICY articles_read ON vijesti.articles FOR SELECT TO anon, authenticated
  USING (status IN ('published', 'corrected', 'retracted') OR vijesti.has_role('editor'));

CREATE POLICY article_versions_read ON vijesti.article_versions FOR SELECT TO anon, authenticated
  USING (
    vijesti.has_role('editor')
    OR EXISTS (
      SELECT 1 FROM vijesti.articles a
      WHERE a.published_version_id = article_versions.id AND a.status IN ('published', 'corrected')
    )
  );

CREATE POLICY article_sources_read ON vijesti.article_sources FOR SELECT TO anon, authenticated
  USING (
    vijesti.has_role('editor')
    OR EXISTS (
      SELECT 1 FROM vijesti.articles a
      WHERE a.published_version_id = article_sources.version_id AND a.status IN ('published', 'corrected')
    )
  );

-- Trenutak je javan samo ako ga objavljena verzija CITIRA (blok `quote`), ne
-- kad je samo među izvorima: ispravak koji uklanja citat ga skriva (odluka 524).
CREATE POLICY moments_read ON vijesti.moments FOR SELECT TO anon, authenticated
  USING (
    vijesti.has_role('editor')
    OR EXISTS (
      SELECT 1 FROM vijesti.article_sources s
      JOIN vijesti.articles a ON a.published_version_id = s.version_id
      JOIN vijesti.article_versions v ON v.id = s.version_id
      WHERE s.moment_id = moments.id AND a.status IN ('published', 'corrected')
        AND v.content -> 'blocks' @> jsonb_build_array(jsonb_build_object('type', 'quote', 'moment_id', moments.id))
    )
  );

CREATE POLICY stories_read ON vijesti.stories FOR SELECT TO anon, authenticated
  USING (
    vijesti.has_role('editor')
    OR EXISTS (
      SELECT 1 FROM vijesti.articles a
      WHERE a.story_id = stories.id AND a.status IN ('published', 'corrected', 'retracted')
    )
  );

CREATE POLICY corrections_read ON vijesti.corrections FOR SELECT TO anon, authenticated
  USING (
    vijesti.has_role('editor')
    OR EXISTS (
      SELECT 1 FROM vijesti.articles a
      WHERE a.id = corrections.article_id AND a.status IN ('published', 'corrected', 'retracted')
    )
  );

CREATE POLICY story_moments_read ON vijesti.story_moments FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY runs_read ON vijesti.runs FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY eval_channels_read ON vijesti.eval_channels FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY eval_sample_read ON vijesti.eval_sample FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY allowed_channels_read ON vijesti.allowed_channels FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY article_transitions_read ON vijesti.article_transitions FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY article_events_read ON vijesti.article_events FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY sentence_resolutions_read ON vijesti.sentence_resolutions FOR SELECT TO authenticated USING (vijesti.has_role('editor'));
CREATE POLICY staff_read ON vijesti.staff FOR SELECT TO authenticated
  USING (user_id = vijesti.current_user_id() OR vijesti.has_role('editor'));

-- Supabase može imati zadana prava (ALTER DEFAULT PRIVILEGES) koja anon i
-- authenticated daju sve izravno, a ne kroz PUBLIC: prvo sve oduzmi.
REVOKE ALL ON ALL TABLES IN SCHEMA vijesti FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vijesti FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA vijesti FROM PUBLIC, anon, authenticated, service_role;

GRANT USAGE ON SCHEMA vijesti TO anon, authenticated, service_role;

-- Engine na Supabaseu (service_role, BYPASSRLS). Vrijedi za tablice koje
-- postoje sada; nova migracija daje prava svojim tablicama.
GRANT ALL ON ALL TABLES IN SCHEMA vijesti TO service_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA vijesti TO service_role;

-- Čitatelji: samo SELECT, nikad INSERT/UPDATE/DELETE (pisanje ide kroz funkcije).
GRANT SELECT ON vijesti.articles, vijesti.article_sources TO anon, authenticated;
GRANT SELECT (id, slug, created_at, updated_at) ON vijesti.stories TO anon, authenticated;
GRANT SELECT (id, video_id, start_ms, end_ms, speaker, speaker_name, quote, quote_check, quote_match, quote_lang,
              topics, entities, cue_from, cue_to, created_at)
  ON vijesti.moments TO anon, authenticated;
GRANT SELECT (id, article_id, version, title, body, lead, category, content, word_count, prompt_version, created_at)
  ON vijesti.article_versions TO anon, authenticated;
GRANT SELECT (id, article_id, version_id, kind, description, created_at)
  ON vijesti.corrections TO anon, authenticated;
GRANT SELECT ON vijesti.public_article_versions, vijesti.public_corrections, vijesti.public_moments,
  vijesti.public_stories TO anon, authenticated;
GRANT SELECT ON vijesti.story_moments, vijesti.runs, vijesti.eval_channels, vijesti.eval_sample, vijesti.staff,
  vijesti.allowed_channels, vijesti.article_transitions, vijesti.article_events, vijesti.sentence_resolutions,
  vijesti.editor_article_versions, vijesti.versions_awaiting_verify TO authenticated;

-- Funkcije: PostgreSQL daje EXECUTE svima (PUBLIC); oduzeto gore, daj izričito.
GRANT EXECUTE ON FUNCTION vijesti.current_user_id(), vijesti.has_role(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION
  vijesti.transition_article(bigint, text, text),
  vijesti.approve_article(bigint, bigint, text),
  vijesti.publish_article(bigint, text),
  vijesti.save_editor_version(bigint, bigint, text, text, text, jsonb),
  vijesti.resolve_sentence(bigint, integer, text, text),
  vijesti.correct_article(bigint, bigint, text, text),
  vijesti.retract_article(bigint, text),
  vijesti.set_staff_role(uuid, text),
  vijesti.remove_staff(uuid),
  vijesti.allow_channel(text, text),
  vijesti.disallow_channel(text)
TO authenticated;

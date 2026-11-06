-- Provjera sheme `vijesti` nakon primjene paketa (odluka 732). Samo čita; ne
-- mijenja ništa (sve je u transakciji koja se na kraju poništava).
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f vijesti/db/prod/verify.sql
-- Prolaz: NOTICE „vijesti: provjera prošla …” i exit 0. Pad: EXCEPTION s popisom
-- svih problema i exit različit od 0. Isti fajl vrti test nad PGliteom
-- (db/bundle.test.ts), pa mijenja li se migracija, mijenja se i ova provjera.

BEGIN;

DO $verify$
DECLARE
  problems text[] := ARRAY[]::text[];
  versions integer[];
  r record;
  n integer;
BEGIN
  -- 1. Migracije: 1..N bez rupa.
  SELECT coalesce(array_agg(version ORDER BY version), ARRAY[]::integer[]) INTO versions FROM vijesti.schema_migrations;
  IF cardinality(versions) = 0 OR versions <> ARRAY(SELECT generate_series(1, cardinality(versions))) THEN
    problems := problems || format('schema_migrations nije 1..N: %s', versions);
  END IF;

  -- 2. RLS uključen na svakoj tablici sheme (odluka 516).
  FOR r IN
    SELECT c.relname FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
    WHERE ns.nspname = 'vijesti' AND c.relkind = 'r' AND c.relname <> 'schema_migrations' AND NOT c.relrowsecurity
  LOOP
    problems := problems || format('RLS isključen: vijesti.%I', r.relname);
  END LOOP;

  -- 3. anon i authenticated nikad ne pišu izravno (pisanje ide kroz funkcije).
  FOR r IN
    SELECT c.relname, g.rolname, p.priv
    FROM pg_class c JOIN pg_namespace ns ON ns.oid = c.relnamespace
    CROSS JOIN (VALUES ('anon'), ('authenticated')) g(rolname)
    CROSS JOIN (VALUES ('INSERT'), ('UPDATE'), ('DELETE'), ('TRUNCATE')) p(priv)
    WHERE ns.nspname = 'vijesti' AND c.relkind IN ('r', 'v')
      AND has_table_privilege(g.rolname, c.oid, p.priv)
  LOOP
    problems := problems || format('%s ima %s na vijesti.%I', r.rolname, r.priv, r.relname);
  END LOOP;

  -- 4. Čitatelj (anon) vidi javne relacije, a ne vidi urednički i interni sloj.
  FOR r IN
    SELECT x.rel FROM (VALUES ('articles'), ('public_article_versions'), ('public_corrections'), ('public_moments'),
                              ('public_stories')) x(rel)
    WHERE NOT has_table_privilege('anon', format('vijesti.%I', x.rel), 'SELECT')
  LOOP
    problems := problems || format('anon ne može čitati vijesti.%I', r.rel);
  END LOOP;
  FOR r IN
    SELECT x.rel FROM (VALUES ('staff'), ('runs'), ('allowed_channels'), ('editor_article_versions'),
                              ('versions_awaiting_verify'), ('sentence_resolutions'), ('article_events'),
                              ('eval_sample'), ('schema_migrations')) x(rel)
    WHERE has_table_privilege('anon', format('vijesti.%I', x.rel), 'SELECT')
  LOOP
    problems := problems || format('anon može čitati vijesti.%I', r.rel);
  END LOOP;

  -- 5. Uredničke funkcije: authenticated da (uloga se provjerava unutra), anon i PUBLIC ne.
  FOR r IN
    SELECT p.oid::regprocedure AS fn FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'vijesti' AND p.proname IN ('approve_article', 'publish_article', 'correct_article',
      'retract_article', 'save_editor_version', 'resolve_sentence', 'transition_article', 'set_staff_role',
      'remove_staff', 'allow_channel', 'disallow_channel')
  LOOP
    IF has_function_privilege('anon', r.fn, 'EXECUTE') THEN
      problems := problems || format('anon smije izvršiti %s', r.fn);
    END IF;
    IF NOT has_function_privilege('authenticated', r.fn, 'EXECUTE') THEN
      problems := problems || format('authenticated ne smije izvršiti %s', r.fn);
    END IF;
  END LOOP;
  SELECT count(*) INTO n FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
  WHERE ns.nspname = 'vijesti' AND p.proname = 'approve_article';
  IF n <> 1 THEN
    problems := problems || format('approve_article: %s definicija umjesto 1', n);
  END IF;

  -- 6. Kao `anon` (kako ga PostgREST pušta): nijedan nacrt nije vidljiv.
  EXECUTE 'SET LOCAL ROLE anon';
  SELECT count(*) INTO n FROM vijesti.articles WHERE status NOT IN ('published', 'corrected', 'retracted');
  IF n <> 0 THEN
    problems := problems || format('anon vidi %s neobjavljenih članaka', n);
  END IF;
  EXECUTE 'RESET ROLE';

  IF cardinality(problems) > 0 THEN
    RAISE EXCEPTION 'vijesti: provjera NIJE prošla (%):%', cardinality(problems),
      E'\n  - ' || array_to_string(problems, E'\n  - ');
  END IF;
  RAISE NOTICE 'vijesti: provjera prošla, migracije %', versions;
END
$verify$;

ROLLBACK;

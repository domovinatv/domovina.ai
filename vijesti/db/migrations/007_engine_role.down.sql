-- Vraća `save_editor_version` iz 006 (bez `related`) i miče ulogu enginea.
REVOKE ALL ON ALL TABLES IN SCHEMA vijesti FROM vijesti_engine;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA vijesti FROM vijesti_engine;
REVOKE ALL ON SCHEMA vijesti FROM vijesti_engine;
REVOKE ALL ON FUNCTION vijesti.current_user_id(), vijesti.has_role(text) FROM vijesti_engine;
ALTER DEFAULT PRIVILEGES IN SCHEMA vijesti REVOKE ALL ON TABLES FROM vijesti_engine;
ALTER DEFAULT PRIVILEGES IN SCHEMA vijesti REVOKE ALL ON SEQUENCES FROM vijesti_engine;
DROP ROLE IF EXISTS vijesti_engine;

CREATE OR REPLACE FUNCTION vijesti.save_editor_version(
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

-- S4: sadržaj verzije članka „vijest iz podcasta” (odluke 413–425).
-- `title` i `body` iz 001 ostaju: `body` je čitljiv tekst (odlomci i citati
-- kako se prikazuju), a strukturirani sadržaj s citatima kao REFERENCAMA na
-- `moments.id` je u `content`. Verzija koju je napisao urednik smije biti bez
-- strukture (sve NULL).
ALTER TABLE vijesti.article_versions
  ADD COLUMN lead           text,
  -- Slug iz zatvorenog popisa (docs/stil.md, engine/write/prompt.ts CATEGORIES).
  ADD COLUMN category       text CHECK (category ~ '^[a-z]+(-[a-z]+)*$'),
  -- {schema, episode, blocks: [{type:'p', text} | {type:'quote', moment_id, ref}]}
  ADD COLUMN content        jsonb,
  -- Riječi leada, odlomaka i citata kako se prikazuju (naslov ne ulazi).
  ADD COLUMN word_count     integer CHECK (word_count >= 0),
  -- `write-vijest/1` ili `verify-article/1+d1`: što je proizvelo ovu verziju.
  ADD COLUMN prompt_version text CHECK (length(btrim(prompt_version)) > 0),
  -- Rezultat verifyja za OVU verziju (rečenice, potpora, problemi, uklonjeno).
  ADD COLUMN verify         jsonb,
  ADD CONSTRAINT article_versions_content_consistent CHECK (
    (content IS NULL) = (lead IS NULL)
    AND (content IS NULL) = (category IS NULL)
    AND (content IS NULL) = (word_count IS NULL)
  ),
  ADD CONSTRAINT article_versions_verify_needs_content CHECK (verify IS NULL OR content IS NOT NULL);

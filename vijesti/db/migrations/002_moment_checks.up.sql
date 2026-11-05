-- S2: trenutak nosi ishod provjere citata (odluke 205, 207). Odbačeni trenuci
-- se zapisuju (quote_check = 'failed' + razlog), nikad ne nestaju tiho.
ALTER TABLE vijesti.moments
  -- Kratki sažetak tvrdnje na hrvatskom (od modela).
  ADD COLUMN claim         text,
  -- Razlog odbijanja; postoji točno kad je quote_check = 'failed'.
  ADD COLUMN reject_reason text CHECK (length(btrim(reject_reason)) > 0),
  -- Kako se tekst poklopio (exact/fuzzy), i kad je vrijeme samo iz SRT-a.
  ADD COLUMN quote_match   text CHECK (quote_match IN ('exact', 'fuzzy')),
  -- Cueovi koje je model naveo (indeksi u titlu); mogu biti nevaljani (bad_cue_ref).
  ADD COLUMN cue_from      integer,
  ADD COLUMN cue_to        integer,
  ADD CONSTRAINT moments_reject_reason_consistent
    CHECK ((quote_check = 'failed') = (reject_reason IS NOT NULL)),
  ADD CONSTRAINT moments_quote_match_consistent
    CHECK (
      (quote_check = 'failed' AND quote_match IS NULL)
      OR (quote_check = 'srt_only' AND quote_match IS NOT NULL)
      OR (quote_check IN ('exact', 'fuzzy') AND quote_match = quote_check)
    );

-- S4: `npm run eval` (odluke 401, 405, 408).
-- Tokeni iz `agy` nisu brojka API-ja nego procjena iz znakova (odluka 305):
-- run s barem jednim takvim pozivom nosi oznaku, pa izvještaj ne miješa mjereno i procijenjeno.
ALTER TABLE vijesti.runs
  ADD COLUMN tokens_estimated boolean NOT NULL DEFAULT false;

-- Uzorak epizoda za mjerenje: što je izabrano i zašto (svježa/starija, ima words.json).
CREATE TABLE vijesti.eval_sample (
  video_id      text PRIMARY KEY,
  channel       text NOT NULL CHECK (length(btrim(channel)) > 0),
  episode_date  date,
  has_words     boolean NOT NULL,
  pick          text NOT NULL CHECK (pick IN ('fresh', 'older')),
  sampled_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX eval_sample_channel_idx ON vijesti.eval_sample (channel);

-- Dotok po kanalu iz listinga u trenutku uzorkovanja (procjena „vijesti dnevno”).
CREATE TABLE vijesti.eval_channels (
  channel       text PRIMARY KEY CHECK (length(btrim(channel)) > 0),
  name          text,
  listed        integer NOT NULL CHECK (listed >= 0),
  -- Epizode s datumom u (window_end − 30 dana, window_end].
  episodes_30d  integer NOT NULL CHECK (episodes_30d >= 0 AND episodes_30d <= listed),
  window_end    date NOT NULL,
  measured_at   timestamptz NOT NULL DEFAULT now()
);

// Ključevi postavki kanala (odluka 1 lanca `postavke-kanala/`). Ugovor svih
// potrošača; ne preimenuju se. Isti popis vraća `domovina_ai.channel_setting_keys()`
// u domovina-api. Ključ koji izvor ne pošalje = `true` (tvrdi uvjet 4), a ključ
// kojeg ovdje nema se čuva (novi prekidač stiže prije novog builda kataloga).

export const SETTING_KEYS = [
  "channel_enabled",
  "processing",
  "home_featured",
  "in_app_search",
  "search_engines",
  "push_notifications",
  "cdn_playback",
  "share_clips",
  "ebook",
  "article_summary",
  "transcript_subtitles",
  "english_translation",
  "magisterium",
  "highlights_reels",
  "persons_mentions",
  "news_portal",
  "ai_assistants",
  "donations",
  "paid_sponsor_moments",
  "sponsors_in_video",
] as const;

export type SettingKey = (typeof SETTING_KEYS)[number];

/** YouTube UC id, isti CHECK kao u domovina-api (`^UC[0-9A-Za-z_-]{22}$`). */
export const UC_PATTERN = /^UC[0-9A-Za-z_-]{22}$/;

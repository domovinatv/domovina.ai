// Datoteke po epizodi: `data/<id>/info.json`, `summary.json`, `episode.json`.
// Oblik: docs/research/2026-11-05-oblik-ulaza.md.
import { InputError } from "./errors.ts";
import {
  asObject,
  at,
  index,
  type JsonObject,
  optCompactDate,
  optIsoOrCompactDate,
  optNonNegative,
  optObject,
  optString,
  optTimestamp,
  reqArray,
  reqString,
  ROOT,
} from "./read.ts";

/** yt-dlp `info.json`, samo polja koja katalog treba. */
export interface EpisodeInfo {
  readonly id: string;
  readonly title: string;
  /** Nedostaje u X/Twitter zapisu (`CUJmOc91C64`: ključa nema, nije `null`). */
  readonly channel: string | null;
  /** YouTube `UC…` ili numerički X ID (`1973380383166050304`). */
  readonly channelId: string | null;
  /**
   * Ime autora kako ga yt-dlp zna; jedino ime X/Twitter zapisa (`CUJmOc91C64`:
   * `channel` nema, `uploader` je „Hobba …”). Uvoznik ga koristi kad `channel` nema.
   */
  readonly uploader: string | null;
  /** `upload_date` `YYYYMMDD` pretvoren u `YYYY-MM-DD`. */
  readonly uploadDate: string | null;
  /**
   * yt-dlp `timestamp` (Unix sekunde). Za premijeru u ponoć je `upload_date`
   * dan u UTC-u (23:00Z = prethodni dan), pa uvoznik dan računa iz ovoga u
   * Europe/Zagreb kad točnog datuma iz `backfill.json` nema (odluka 1200).
   */
  readonly timestamp: number | null;
  /** Može biti decimalan (245.295) ili nepoznat (`hmM9f_3Mqm4`: ključa nema). */
  readonly durationSeconds: number | null;
  /** `youtube`, `twitter`, … */
  readonly extractor: string | null;
}

export function parseEpisodeInfo(raw: unknown): EpisodeInfo {
  const o = asObject(raw, ROOT);
  return {
    id: reqString(o, "id", ROOT),
    title: reqString(o, "title", ROOT),
    channel: optString(o, "channel", ROOT),
    channelId: optString(o, "channel_id", ROOT),
    uploader: optString(o, "uploader", ROOT),
    uploadDate: optCompactDate(o, "upload_date", ROOT),
    timestamp: optNonNegative(o, "timestamp", ROOT),
    durationSeconds: optNonNegative(o, "duration", ROOT),
    extractor: optString(o, "extractor", ROOT),
  };
}

export interface EpisodeSummary {
  /** `source.title` (izvorni naslov, kao `info.json` `title`). */
  readonly title: string | null;
  readonly titleHr: string | null;
  readonly abstractHr: string | null;
  /** `summary.language`, 2–16 znakova kao `episodes.lang`. */
  readonly language: string | null;
  /** `source.duration_seconds`; prati `info.json` (i decimalno i `null`). */
  readonly durationSeconds: number | null;
  /** `source.upload_date` (`YYYY-MM-DD` ili `YYYYMMDD`, vraća se `YYYY-MM-DD`); jedini datum epizode bez `info.json`. */
  readonly uploadDate: string | null;
  /**
   * `source.channel`: većinom `"_unlisted"` (ne govori ništa), ali tri epizode bez
   * `info.json` nose CDN slug kanala (`subclub`, `launched`), odluka 206.
   */
  readonly sourceChannel: string | null;
}

function optLang(o: JsonObject, key: string, path: string): string | null {
  const v = optString(o, key, path);
  if (v !== null && (v.length < 2 || v.length > 16)) {
    throw new InputError(at(path, key), `oznaka jezika nije 2–16 znakova: ${v}`);
  }
  return v;
}

export function parseEpisodeSummary(raw: unknown): EpisodeSummary {
  const o = asObject(raw, ROOT);
  const source = optObject(o, "source", ROOT);
  const summary = optObject(o, "summary", ROOT);
  return {
    title: source === null ? null : optString(source, "title", "source"),
    titleHr: summary === null ? null : optString(summary, "title_hr", "summary"),
    abstractHr: summary === null ? null : optString(summary, "abstract_hr", "summary"),
    language: summary === null ? null : optLang(summary, "language", "summary"),
    durationSeconds: source === null ? null : optNonNegative(source, "duration_seconds", "source"),
    uploadDate: source === null ? null : optIsoOrCompactDate(source, "upload_date", "source"),
    sourceChannel: source === null ? null : optString(source, "channel", "source"),
  };
}

/** `episode.json`: popis datoteka u `data/<id>/`. `inline` se ne čita. */
export interface EpisodeManifest {
  readonly generatedAt: string | null;
  readonly files: readonly string[];
}

/** Jedina verzija koju čita i klijent (`EpisodeBundle.supportedVersion`). */
export const EPISODE_MANIFEST_VERSION = 1;

export function parseEpisodeManifest(raw: unknown): EpisodeManifest {
  const o = asObject(raw, ROOT);
  const version = o.version;
  if (version !== EPISODE_MANIFEST_VERSION) {
    const shown = version === undefined ? "nedostaje" : JSON.stringify(version);
    throw new InputError("version", `nepoznata verzija: ${shown}`);
  }
  const files = reqArray(o, "files", ROOT).map((f, i) => {
    if (typeof f !== "string" || f.length === 0) {
      throw new InputError(index("files", i), "očekivano ime datoteke (neprazan string)");
    }
    return f;
  });
  return { generatedAt: optTimestamp(o, "generated_at", ROOT), files };
}

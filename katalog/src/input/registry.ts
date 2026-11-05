// `../fetch.domovina.tv/data/podcasts_registry.json`: `{version, podcasts: [...]}`.
// Oblik: docs/research/2026-11-05-oblik-ulaza.md.
import { InputError } from "./errors.ts";
import {
  asObject,
  at,
  index,
  optInteger,
  optObject,
  optString,
  reqArray,
  reqBoolean,
  reqString,
  ROOT,
} from "./read.ts";

export interface RegistryEntry {
  /**
   * Registry slug. NIJE nužno slug kanala na CDN-u: registry piše crtice
   * (`40-dana-za-zivot`), CDN podvlake (`40_dana_za_zivot`).
   */
  readonly slug: string;
  readonly displayName: string;
  /** `youtube.channel_id`; nedostaje (`nanovoroeni`, `dijalog`) ili je `null`. Nije jedinstven. */
  readonly youtubeChannelId: string | null;
  readonly trackingEnabled: boolean;
  /** Registry `tier` 1–4 (ocjena kvalitete). NIJE naš `tier` 1/2 (odluka 103). */
  readonly registryTier: number | null;
  /** `youtube.type`: `channel`, `playlist`, `umbrella`, `audio-only`, … (odluka 204). */
  readonly youtubeType: string | null;
  /** `parent_slug`: playlist unos pod umbrellom (`aktualno-hkm` → `hkm`). */
  readonly parentSlug: string | null;
}

export interface Registry {
  readonly version: string | null;
  readonly entries: readonly RegistryEntry[];
}

export function parseRegistry(raw: unknown): Registry {
  const o = asObject(raw, ROOT);
  const seen = new Set<string>();
  const entries = reqArray(o, "podcasts", ROOT).map((value, i): RegistryEntry => {
    const path = index("podcasts", i);
    const e = asObject(value, path);
    const youtube = optObject(e, "youtube", path);
    const tracking = optObject(e, "tracking", path);
    if (tracking === null) throw new InputError(at(path, "tracking"), "obavezno polje nedostaje ili je null");
    const entry = {
      slug: reqString(e, "slug", path),
      displayName: reqString(e, "display_name", path),
      youtubeChannelId: youtube === null ? null : optString(youtube, "channel_id", at(path, "youtube")),
      trackingEnabled: reqBoolean(tracking, "enabled", at(path, "tracking")),
      registryTier: optInteger(e, "tier", path),
      youtubeType: youtube === null ? null : optString(youtube, "type", at(path, "youtube")),
      parentSlug: optString(e, "parent_slug", path),
    };
    if (seen.has(entry.slug)) throw new InputError(at(path, "slug"), `slug se ponavlja: ${entry.slug}`);
    seen.add(entry.slug);
    return entry;
  });
  return { version: optString(o, "version", ROOT), entries };
}

// URL-ovi isječka, aplikacije i portala (odluka 605). Sve baze su iz
// konfiguracije, nijedna nije upisana ovdje.

/** Sekunde za media fragment: najviše tri decimale, bez suvišnih nula. */
export function fragmentSeconds(ms: number): string {
  return String(Math.round(Math.max(0, ms)) / 1000);
}

/**
 * Datoteka kojom `<audio>` pušta isječak, iz popisa `episode.json` (`files`).
 * `audio.mp3` postoji samo za audio epizode; za video epizode je to
 * `video_h264.mp4` (H.264/AAC, `<audio>` pušta zvučni zapis). Bez popisa: null
 * (stranica tada nudi samo poveznicu u aplikaciju).
 */
export function pickClipMedia(files: readonly string[] | null | undefined): string | null {
  if (!files) return null;
  if (files.includes('audio.mp3')) return 'audio.mp3';
  if (files.includes('video_h264.mp4')) return 'video_h264.mp4';
  return null;
}

/** `<cdn>/data/<id>/<datoteka>#t=<od>,<do>` (W3C Media Fragments). */
export function clipUrl(cdnBase: string, videoId: string, file: string, startMs: number, endMs: number): string {
  return `${cdnBase}/data/${encodeURIComponent(videoId)}/${file}#t=${fragmentSeconds(startMs)},${fragmentSeconds(endMs)}`;
}

/** `episode.json` epizode na CDN-u. */
export function episodeBundleUrl(cdnBase: string, videoId: string): string {
  return `${cdnBase}/data/${encodeURIComponent(videoId)}/episode.json`;
}

/** „Poslušaj cijeli razgovor”: `https://domovina.ai/v/<id>/t/<sekunda>`. */
export function appEpisodeUrl(appBase: string, videoId: string, startMs = 0): string {
  const sec = Math.floor(Math.max(0, startMs) / 1000);
  return `${appBase}/v/${encodeURIComponent(videoId)}${sec > 0 ? `/t/${String(sec)}` : ''}`;
}

/** Putanja unutar portala; `base` je Astro `BASE_URL` (`/vijesti` ili `/vijesti/`). */
export function portalPath(base: string, ...parts: string[]): string {
  const root = base.replace(/\/+$/, '');
  const rest = parts.map((p) => encodeURIComponent(p)).join('/');
  return rest ? `${root}/${rest}` : `${root}/`;
}

export const articlePath = (base: string, slug: string): string => portalPath(base, slug);
export const categoryPath = (base: string, category: string): string => portalPath(base, 'kategorija', category);
export const adminPath = (base: string): string => portalPath(base, 'admin');

// `npm run cdn:stats -- <id> [<id> …] [--lang en]`: učita CIJELE epizode sa
// stvarnog CDN-a (mreža, disk cache u .cache/cdn) i ispiše oblik titla i
// poklapanje words.json. Reproducira brojke iz
// docs/research/2026-11-05-oblik-cdn-datoteka.md. Nije dio `npm run check`.
import { join } from 'node:path';
import { createDiskCache } from './cache.js';
import { createCdnClient } from './loader.js';
import { wordsStats } from './words.js';

const args = process.argv.slice(2);
const langAt = args.indexOf('--lang');
const lang = langAt >= 0 ? args[langAt + 1] : undefined;
const ids = args.filter((a, i) => !a.startsWith('--') && (langAt < 0 || i !== langAt + 1));
if (ids.length === 0) {
  console.error('upotreba: npm run cdn:stats -- <id> [<id> …] [--lang en]');
  process.exit(2);
}

const cdn = createCdnClient({
  fetch: (url, init) => fetch(url, init),
  cache: createDiskCache(process.env.VIJESTI_CACHE_DIR ?? join(process.cwd(), '.cache', 'cdn')),
});

for (const id of ids) {
  const ep = await cdn.loadEpisode(id, lang ? { lang } : {});
  const s = wordsStats(ep.cues);
  const speakers = new Set(ep.cues.map((c) => c.speaker ?? '(bez oznake)'));
  const pct = s.cues ? ((100 * s.ok) / s.cues).toFixed(1) : '0.0';
  console.log(
    [
      id,
      `srt=${ep.srtFile ?? '-'}`,
      `words=${ep.wordsFile ?? '-'}(${ep.words?.source ?? '-'}, anchored ${String(ep.words?.anchored ?? '-')})`,
      `cues=${String(s.cues)}`,
      `ok=${String(s.ok)} (${pct} %)`,
      `mismatch=${String(s.countMismatch)}`,
      `missing=${String(s.missing)}`,
      `govornika=${String(speakers.size)}`,
      `trajanje=${String(ep.info?.duration ?? '-')} s`,
      `jezik_izlaza=${ep.summary?.summary.language ?? '-'}`,
    ].join('  '),
  );
}

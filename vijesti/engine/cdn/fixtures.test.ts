// Provjera uvjeta „Gotovo kad” iz S1 nad fixtureima i pravila dohvata koja
// loader.test.ts ne pokriva: svaki parser po fixtureu, veličina fixturea,
// 404 → jedan ponovljeni zahtjev u svim granama, cache nakon ponavljanja.
import { mkdtemp, readdir, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createFakeCdn, readFixture } from '../test/fake-cdn.js';
import { FIXTURES, FIXTURES_DIR } from '../test/fixtures-refresh.js';
import { createDiskCache } from './cache.js';
import { cacheBucket, CdnHttpError, createCdnClient } from './loader.js';
import {
  ArticleSchema,
  ChannelListingSchema,
  EpisodeBundleSchema,
  InfoSchema,
  SummarySchema,
  WordsFileSchema,
} from './schemas.js';
import { parseSrt } from './srt.js';

const NOW = Date.UTC(2026, 10, 5, 12, 3, 0);
const MAX_FIXTURE_BYTES = 200 * 1024;

async function dirBytes(dir: string): Promise<number> {
  let total = 0;
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    total += e.isDirectory() ? await dirBytes(p) : (await stat(p)).size;
  }
  return total;
}

describe('svaki fixture, svaki parser', () => {
  it.each(FIXTURES.map((f) => [f.id, f.criterion, f] as const))(
    '%s (%s)',
    async (id, _criterion, spec) => {
      const fake = createFakeCdn();
      const cdn = createCdnClient({ fetch: fake.fetch });

      // episode.json: sirovo kroz shemu i kroz klijenta.
      const bundle = EpisodeBundleSchema.parse(JSON.parse(readFixture(id, 'episode.json')));
      expect(await cdn.bundle(id)).toEqual(bundle);

      // info/summary/article: shema prolazi, sadržaj pripada epizodi.
      const info = await cdn.info(id);
      const summary = await cdn.summary(id);
      const article = await cdn.article(id);
      expect(info && InfoSchema.parse(info).id).toBe(id);
      expect(summary && SummarySchema.parse(summary).source.youtube_id).toBe(id);
      expect(article && ArticleSchema.parse(article).iterations.length).toBeGreaterThan(0);

      // SRT: zadani i (za engleski) izvorni.
      const srtNames = ['diarized.srt', ...(spec.lang ? [`diarized.${spec.lang}.srt`] : [])];
      for (const name of srtNames) {
        const parsed = parseSrt(readFixture(id, name));
        expect(parsed.skippedBlocks, name).toBe(0);
        expect(parsed.cues.length, name).toBeGreaterThan(0);
        expect(await cdn.srt(id, name === 'diarized.srt' ? undefined : spec.lang)).toEqual(parsed);
      }

      // words: parsira se točno ondje gdje ga episode.json navodi.
      const wordNames = ['words.json', ...(spec.lang ? [`words.${spec.lang}.json`] : [])];
      for (const name of wordNames) {
        const lang = name === 'words.json' ? undefined : spec.lang;
        const listed = bundle.files.includes(name);
        const words = await cdn.words(id, lang);
        if (listed) {
          expect(words, name).toEqual(WordsFileSchema.parse(JSON.parse(readFixture(id, name))));
        } else {
          expect(words, name).toBeNull();
        }
      }
      expect(bundle.files.includes('words.json')).toBe(spec.criterion !== 'no_words' && !spec.lang);

      // Listing: epizoda je u listingu kanala iz manifesta (ili domovina_tv za _unlisted).
      const index = await cdn.channelIndex();
      let found = false;
      for (const ch of index.channels) {
        const listing = await cdn.channel(ch.id);
        if (!listing) continue;
        ChannelListingSchema.parse(listing);
        if (listing.videos.some((v) => v.id === id)) found = true;
      }
      expect(found).toBe(true);

      // Nijedan zahtjev za datoteku koja nije na popisu.
      for (const url of fake.calls) {
        const m = /\/data\/[^/]+\/([^/?]+)/.exec(url);
        if (m?.[1] && m[1] !== 'episode.json') expect(bundle.files).toContain(m[1]);
      }
    },
  );
});

describe('veličina fixturea', () => {
  it.each(FIXTURES.map((f) => [f.id] as const))('%s je ≤ 200 kB', async (id) => {
    expect(await dirBytes(join(FIXTURES_DIR, id))).toBeLessThanOrEqual(MAX_FIXTURE_BYTES);
  });
});

describe('404 pravila, rubni slučajevi', () => {
  const id = FIXTURES[0]?.id ?? '';
  const base = `https://cdn.domovina.ai/data/${id}`;
  let dir = '';
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'vijesti-404-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  it('cb je 5-min bucket: isti unutar prozora, drugi u sljedećem', () => {
    const start = Math.floor(NOW / 300_000) * 300_000;
    expect(cacheBucket(start)).toBe(cacheBucket(start + 299_999));
    expect(cacheBucket(start + 300_000)).toBe(cacheBucket(start) + 1);
  });

  it('404 pa 500 na ponovljenom zahtjevu je greška, ne „nema”', async () => {
    let n = 0;
    const cdn = createCdnClient({
      fetch: (url) => {
        n++;
        if (url.endsWith('episode.json')) return createFakeCdn().fetch(url);
        const status = url.includes('cb=') ? 500 : 404;
        return Promise.resolve({ status, ok: false, text: () => Promise.resolve('') });
      },
      now: () => NOW,
    });
    await expect(cdn.srt(id)).rejects.toBeInstanceOf(CdnHttpError);
    expect(n).toBe(3);
  });

  it('403 i 304 nisu „nema datoteke”; greška bez ponavljanja', async () => {
    for (const status of [403, 304]) {
      const fake = createFakeCdn({ statuses: { [`data/${id}/diarized.srt`]: status } });
      const cdn = createCdnClient({ fetch: fake.fetch });
      await expect(cdn.srt(id)).rejects.toMatchObject({ status });
      expect(fake.calls.filter((u) => u.includes('diarized.srt'))).toHaveLength(1);
    }
  });

  it('uspjeh na ponovljenom zahtjevu se kešira pod putanjom bez ?cb', async () => {
    const cache = createDiskCache(dir);
    const fake = createFakeCdn({ stale404: [`data/${id}/diarized.srt`] });
    await createCdnClient({ fetch: fake.fetch, cache, now: () => NOW }).srt(id);
    expect(fake.calls).toContain(`${base}/diarized.srt?cb=${String(cacheBucket(NOW))}`);
    expect(await cache.get(`data/${id}/diarized.srt`)).toBe(readFixture(id, 'diarized.srt'));
    const left = await readdir(join(dir, 'data', id));
    expect(left.some((f) => f.includes('cb=') || f.endsWith('.tmp'))).toBe(false);
  });

  it('dvaput 404 za datoteku s popisa ne ostavlja ništa u cacheu', async () => {
    const cache = createDiskCache(dir);
    const fake = createFakeCdn({ overrides: { [`data/${id}/diarized.srt`]: null } });
    expect(await createCdnClient({ fetch: fake.fetch, cache }).srt(id)).toBeNull();
    expect(await cache.get(`data/${id}/diarized.srt`)).toBeNull();
    // Sljedeći klijent pita CDN iznova (404 nije zapamćen).
    const again = createFakeCdn();
    expect(await createCdnClient({ fetch: again.fetch, cache }).srt(id)).not.toBeNull();
    expect(again.calls).toContain(`${base}/diarized.srt`);
  });

  it('istodobni zapisi iste putanje u cache ne ruše se', async () => {
    const cache = createDiskCache(dir);
    const bodies = Array.from({ length: 8 }, (_, i) => `sadržaj ${String(i)}`);
    await Promise.all(bodies.map((b) => cache.set('data/x/isti.json', b)));
    expect(bodies).toContain(await cache.get('data/x/isti.json'));
  });

  it('inline null nije „ima”: has() i file() se slažu, lang pada na zadani titl', async () => {
    const bundle = JSON.parse(readFixture(id, 'episode.json')) as {
      files: string[];
      inline: Record<string, unknown>;
    };
    bundle.inline['diarized.en.srt'] = null;
    const fake = createFakeCdn({ overrides: { [`data/${id}/episode.json`]: JSON.stringify(bundle) } });
    const cdn = createCdnClient({ fetch: fake.fetch });
    expect(await cdn.has(id, 'diarized.en.srt')).toBe(false);
    expect(await cdn.file(id, 'diarized.en.srt')).toBeNull();
    expect((await cdn.loadEpisode(id, { lang: 'en' })).srtFile).toBe('diarized.srt');
  });

  it('neuspjela revalidacija popisa se ne pamti', async () => {
    const cache = createDiskCache(dir);
    const full = JSON.parse(readFixture(id, 'episode.json')) as { files: string[] };
    await cache.set(
      `data/${id}/episode.json`,
      JSON.stringify({ ...full, files: full.files.filter((f) => f !== 'words.json') }),
    );
    let fail = true;
    const good = createFakeCdn();
    const cdn = createCdnClient({
      cache,
      fetch: (url, init) =>
        fail && url.includes('episode.json')
          ? Promise.resolve({ status: 503, ok: false, text: () => Promise.resolve('') })
          : good.fetch(url, init),
    });
    await expect(cdn.words(id)).rejects.toBeInstanceOf(CdnHttpError);
    fail = false;
    expect((await cdn.words(id))?.cues.length).toBeGreaterThan(0);
  });
});

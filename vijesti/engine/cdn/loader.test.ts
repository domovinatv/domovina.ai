import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createFakeCdn, readFixture } from '../test/fake-cdn.js';
import { FIXTURES } from '../test/fixtures-refresh.js';
import { createDiskCache } from './cache.js';
import {
  cacheBucket,
  CdnHttpError,
  CdnSchemaError,
  createCdnClient,
  DEFAULT_USER_AGENT,
  type FetchLike,
} from './loader.js';
import { wordsStats } from './words.js';

const NOW = Date.UTC(2026, 10, 5, 12, 0, 0);
const byCriterion = (c: string) => {
  const f = FIXTURES.find((x) => x.criterion === c);
  if (!f) throw new Error(`nema fixturea ${c}`);
  return f.id;
};

describe('loader nad svih 5 fixturea', () => {
  it.each(FIXTURES.map((f) => [f.id, f.criterion] as const))(
    '%s (%s) se učita bez greške',
    async (id) => {
      const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
      const ep = await cdn.loadEpisode(id);
      expect(ep.bundle?.files).toContain('diarized.srt');
      expect(ep.info?.id).toBe(id);
      expect(ep.summary?.source.youtube_id).toBe(id);
      expect(ep.article?.iterations.length).toBeGreaterThan(0);
      expect(ep.article?.iterations[0]?.sections.length).toBeGreaterThan(0);
      expect(ep.srt?.skippedBlocks).toBe(0);
      expect(ep.cues.length).toBeGreaterThan(50);
      for (const c of ep.cues) {
        expect(c.speaker).toMatch(/^SPEAKER_\d{2}$/);
        expect(c.endMs).toBeGreaterThanOrEqual(c.startMs);
      }
    },
  );

  it('izlaz pipelinea je hrvatski za sve, i za engleski kanal', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    for (const f of FIXTURES) {
      const s = await cdn.summary(f.id);
      expect(s?.summary.language, f.id).toBe('hr');
    }
  });

  it('epizoda s words.json: svaki cue u fixtureu ima vremena riječi', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const ep = await cdn.loadEpisode(byCriterion('words'));
    expect(ep.wordsFile).toBe('words.json');
    expect(ep.words?.source).toBe('soniox');
    const stats = wordsStats(ep.cues);
    expect(stats.ok).toBe(stats.cues);
    const first = ep.cues[0]?.words;
    expect(first?.[0]?.startMs).toBeGreaterThanOrEqual(ep.cues[0]?.startMs ?? -1);
  });

  it('epizoda bez words.json: words.json se uopće ne traži', async () => {
    const fake = createFakeCdn();
    const cdn = createCdnClient({ fetch: fake.fetch });
    const id = byCriterion('no_words');
    const ep = await cdn.loadEpisode(id);
    expect(ep.words).toBeNull();
    expect(wordsStats(ep.cues).missing).toBe(ep.cues.length);
    expect(fake.calls.some((u) => u.includes('words'))).toBe(false);
    // info/summary/article su inline u episode.json: nijedan zaseban zahtjev.
    expect(fake.calls).toEqual([
      `https://cdn.domovina.ai/data/${id}/episode.json`,
      `https://cdn.domovina.ai/data/${id}/diarized.srt`,
    ]);
  });

  it('engleski kanal: diarized.srt je prijevod, izvorni par je diarized.en.srt + words.en.json', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const id = byCriterion('english');
    const hr = await cdn.loadEpisode(id);
    expect(hr.srtFile).toBe('diarized.srt');
    expect(hr.words).toBeNull();
    const en = await cdn.loadEpisode(id, { lang: 'en' });
    expect(en.srtFile).toBe('diarized.en.srt');
    expect(en.wordsFile).toBe('words.en.json');
    expect(wordsStats(en.cues).ok).toBe(en.cues.length);
    // Isti trenutak, dva jezika: engleski tekst nema hrvatskih dijakritika.
    const enText = en.cues.map((c) => c.text).join(' ');
    const hrText = hr.cues.map((c) => c.text).join(' ');
    expect(enText).toMatch(/\b(the|and|is)\b/);
    expect(hrText).toMatch(/[čćšžđ]/);
  });

  it('lang bez para na CDN-u pada na zadani titl', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const ep = await cdn.loadEpisode(byCriterion('words'), { lang: 'en' });
    expect(ep.srtFile).toBe('diarized.srt');
    expect(ep.wordsFile).toBe('words.json');
  });

  it('epizoda s više od 3 govornika', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const ep = await cdn.loadEpisode(byCriterion('many_speakers'));
    expect(new Set(ep.cues.map((c) => c.speaker)).size).toBeGreaterThan(3);
    expect(ep.summary?.summary.speakers.length).toBeGreaterThan(3);
  });

  it('duga epizoda (> 2 h)', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const ep = await cdn.loadEpisode(byCriterion('long'));
    expect(ep.info?.duration).toBeGreaterThan(2 * 3600);
  });
});

describe('pravila dohvata', () => {
  it('šalje vlastiti User-Agent', async () => {
    const fake = createFakeCdn();
    await createCdnClient({ fetch: fake.fetch }).bundle(byCriterion('words'));
    expect(fake.userAgents).toEqual([DEFAULT_USER_AGENT]);
  });

  it('404 ponovi jednom s cache-busterom ?cb=<5-min bucket>', async () => {
    const id = byCriterion('words');
    const fake = createFakeCdn({ stale404: [`data/${id}/diarized.srt`] });
    const cdn = createCdnClient({ fetch: fake.fetch, now: () => NOW });
    const srt = await cdn.srt(id);
    expect(srt?.cues.length).toBeGreaterThan(0);
    expect(fake.calls.slice(-2)).toEqual([
      `https://cdn.domovina.ai/data/${id}/diarized.srt`,
      `https://cdn.domovina.ai/data/${id}/diarized.srt?cb=${String(cacheBucket(NOW))}`,
    ]);
    expect(cacheBucket(NOW)).toBe(Math.floor(NOW / 300_000));
  });

  it('dvaput 404 za datoteku s popisa = nema je (null), bez trećeg pokušaja', async () => {
    const id = byCriterion('words');
    const fake = createFakeCdn({ overrides: { [`data/${id}/words.json`]: null } });
    const cdn = createCdnClient({ fetch: fake.fetch });
    expect(await cdn.words(id)).toBeNull();
    expect(fake.calls.filter((u) => u.includes('words.json'))).toHaveLength(2);
  });

  it('datoteka koje nema na popisu se ne traži', async () => {
    const fake = createFakeCdn();
    const cdn = createCdnClient({ fetch: fake.fetch });
    expect(await cdn.file(byCriterion('words'), 'nepostojece.json')).toBeNull();
    expect(fake.calls).toHaveLength(1);
  });

  it('HTTP 500 je greška, ne „nema datoteke”', async () => {
    const id = byCriterion('words');
    const fake = createFakeCdn({ statuses: { [`data/${id}/diarized.srt`]: 500 } });
    const cdn = createCdnClient({ fetch: fake.fetch });
    await expect(cdn.srt(id)).rejects.toBeInstanceOf(CdnHttpError);
  });

  it('nečitljiv JSON i krivi oblik su CdnSchemaError', async () => {
    const id = byCriterion('words');
    const broken = createFakeCdn({ overrides: { [`data/${id}/words.json`]: '{"v":1,' } });
    await expect(createCdnClient({ fetch: broken.fetch }).words(id)).rejects.toBeInstanceOf(
      CdnSchemaError,
    );
    const odd = JSON.stringify({ v: 1, source: 'x', anchored: 1, cues: [{ s: 0, e: 1, w: [1] }] });
    const wrong = createFakeCdn({ overrides: { [`data/${id}/words.json`]: odd } });
    await expect(createCdnClient({ fetch: wrong.fetch }).words(id)).rejects.toThrow(/paran/);
    const v2 = createFakeCdn({ overrides: { [`data/${id}/episode.json`]: '{"version":2,"files":[]}' } });
    await expect(createCdnClient({ fetch: v2.fetch }).bundle(id)).rejects.toBeInstanceOf(
      CdnSchemaError,
    );
  });

  it('bez episode.json ide datoteku po datoteku', async () => {
    const id = byCriterion('no_words');
    const fake = createFakeCdn({
      overrides: {
        [`data/${id}/episode.json`]: null,
        [`data/${id}/summary.json`]: JSON.stringify(
          (JSON.parse(readFixture(id, 'episode.json')) as { inline: Record<string, unknown> })
            .inline['summary.json'],
        ),
      },
    });
    const cdn = createCdnClient({ fetch: fake.fetch });
    expect(await cdn.bundle(id)).toBeNull();
    expect((await cdn.summary(id))?.source.youtube_id).toBe(id);
    expect((await cdn.srt(id))?.cues.length).toBeGreaterThan(0);
    expect(await cdn.words(id)).toBeNull();
    // episode.json 2× (404 + cb), summary 1×, srt 1×, words 2× (404 + cb).
    expect(fake.calls).toHaveLength(6);
  });

  it('neispravan ID ili ime datoteke se odbija prije zahtjeva', async () => {
    const fake = createFakeCdn();
    const cdn = createCdnClient({ fetch: fake.fetch });
    await expect(cdn.bundle('../etc')).rejects.toThrow(/ID/);
    await expect(cdn.file(byCriterion('words'), '../x')).rejects.toThrow(/ime/);
    expect(fake.calls).toHaveLength(0);
  });

  it('listing kanala i indeks', async () => {
    const cdn = createCdnClient({ fetch: createFakeCdn().fetch });
    const index = await cdn.channelIndex();
    expect(index.channels.map((c) => c.id)).toContain('domovina_tv');
    const listing = await cdn.channel('domovina_tv');
    expect(listing?.version).toBe('1.0');
    expect(listing?.videos.map((v) => v.id)).toContain(byCriterion('long'));
    // Kanal epizode je onaj iz listinga: summary.source.channel je ovdje `_unlisted`.
    const s = await cdn.summary(byCriterion('long'));
    expect(s?.source.channel).toBe('_unlisted');
    expect(await cdn.channel('nepostojeci_kanal')).toBeNull();
  });
});

describe('disk cache', () => {
  let dir = '';
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'vijesti-cache-'));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  const offline: FetchLike = (url) => Promise.reject(new Error(`ne smije na mrežu: ${url}`));

  it('drugi klijent čita iz cachea bez mreže', async () => {
    const id = byCriterion('words');
    let t = Date.now();
    const cache = createDiskCache(dir, () => t);
    const first = await createCdnClient({ fetch: createFakeCdn().fetch, cache }).loadEpisode(id);
    const second = await createCdnClient({ fetch: offline, cache }).loadEpisode(id);
    expect(second.cues).toEqual(first.cues);
    // Promjenjivi episode.json istekne, immutable datoteke ne.
    t = Date.now() + 10 * 60 * 1000;
    await expect(createCdnClient({ fetch: offline, cache }).bundle(id)).rejects.toThrow(/mrežu/);
    expect(await cache.get(`data/${id}/diarized.srt`)).not.toBeNull();
  });

  it('popis iz cachea koji kaže „nema” se jednom revalidira', async () => {
    const id = byCriterion('words');
    const cache = createDiskCache(dir);
    const full = JSON.parse(readFixture(id, 'episode.json')) as { files: string[] };
    const old = { ...full, files: full.files.filter((f) => f !== 'words.json') };
    await cache.set(`data/${id}/episode.json`, JSON.stringify(old));
    const fake = createFakeCdn();
    const cdn = createCdnClient({ fetch: fake.fetch, cache });
    const words = await cdn.words(id);
    expect(words?.cues.length).toBeGreaterThan(0);
    expect(fake.calls).toEqual([
      `https://cdn.domovina.ai/data/${id}/episode.json`,
      `https://cdn.domovina.ai/data/${id}/words.json`,
    ]);
  });

  it('404 se ne sprema u cache', async () => {
    const id = byCriterion('no_words');
    const cache = createDiskCache(dir);
    const fake = createFakeCdn({ overrides: { [`data/${id}/episode.json`]: null } });
    await createCdnClient({ fetch: fake.fetch, cache }).bundle(id);
    expect(await cache.get(`data/${id}/episode.json`)).toBeNull();
  });

  it('putanja izvan korijena cachea se odbija', async () => {
    const cache = createDiskCache(dir);
    await expect(cache.set('../izvan.txt', 'x')).rejects.toThrow(/putanja/);
  });
});

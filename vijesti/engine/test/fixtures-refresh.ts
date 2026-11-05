// `npm run fixtures:refresh`: ponovno izvuče fixturee s cdn.domovina.ai.
// Ide na mrežu, zato NIJE dio `npm run check`. Testovi čitaju samo ono što
// ova skripta zapiše u engine/test/fixtures/.
//
// Svaka epizoda se skrati na prvih 15 min (SRT, words, sekcije članka koje
// počinju prije te granice), ali JSON zadržava stvarni oblik. Iz info.json se
// zadržavaju samo polja koja loader čita (pravi je yt-dlp dump od ~85 kB).
// Ako epizoda više ne zadovoljava svoj kriterij (npr. dobila je words.json
// backfillom), skripta pada i traži novi izbor umjesto da tiho promijeni test.
import { mkdir, rm, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { InfoSchema } from '../cdn/schemas.js';
import { cacheBucket, DEFAULT_CDN_BASE, DEFAULT_USER_AGENT } from '../cdn/loader.js';
import { parseSrt } from '../cdn/srt.js';
import { hmsToMs } from '../cdn/time.js';

export const LIMIT_MS = 15 * 60 * 1000;

export type Criterion = 'words' | 'no_words' | 'english' | 'many_speakers' | 'long';

export interface FixtureSpec {
  id: string;
  criterion: Criterion;
  reason: string;
  /** Dodatni titl/words par na jeziku snimke (engleski kanali). */
  lang?: string;
}

/** Izbor 5.11.2026. Kriteriji i razlozi su i u fixtures/README.md. */
export const FIXTURES: FixtureSpec[] = [
  {
    id: 'pIx_7N-6HJ4',
    criterion: 'words',
    reason:
      'mreze_rijeci, 32 min, 2 govornika; words.json (soniox, anchored 1), 178/179 cueova s poklapanjem broja riječi',
  },
  {
    id: 'P9sLks-f2mQ',
    criterion: 'no_words',
    reason:
      'iva_kraljevic, 83 min, 2 govornika; bez words.json (stariji katalog), članak gemini-3.5-flash',
  },
  {
    id: 'x3w2BVZJ9vQ',
    criterion: 'english',
    lang: 'en',
    reason:
      'catholic_futurist, 21 min; diarized.srt je HRVATSKI prijevod, izvorni engleski je diarized.en.srt + words.en.json; summary/article na hrvatskom',
  },
  {
    id: 'MGLq9v3AtvE',
    criterion: 'many_speakers',
    reason:
      'CroAI Code Club (summary.source.channel = _unlisted, listing domovina_tv), 12 govornika u SRT-u, 10 u prvih 15 min; ujedno 2 h 11 min s words.json',
  },
  {
    id: 'b-nls1ck8EE',
    criterion: 'long',
    reason: 'domovina_tv, 2 h 41 min, 4 iteracije članka; words.json (soniox), 782/782 cueova se poklapa',
  },
];

const here = dirname(fileURLToPath(import.meta.url));
export const FIXTURES_DIR = join(here, 'fixtures');

type Json = Record<string, unknown>;

async function getText(path: string): Promise<string | null> {
  const url = `${DEFAULT_CDN_BASE}/${path}`;
  const headers = { 'user-agent': DEFAULT_USER_AGENT };
  let res = await fetch(url, { headers });
  if (res.status === 404) res = await fetch(`${url}?cb=${String(cacheBucket(Date.now()))}`, { headers });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`${url} -> HTTP ${String(res.status)}`);
  return res.text();
}

async function getJson(path: string): Promise<Json> {
  const body = await getText(path);
  if (body === null) throw new Error(`nema ${path}`);
  return JSON.parse(body) as Json;
}

/** Zadrži SRT blokove koji počinju prije granice, bajt-za-bajt kao na CDN-u. */
export function trimSrt(raw: string, limitMs: number): string {
  const blocks = raw.trim().split(/\r?\n\s*\r?\n/);
  const kept = blocks.filter((b) => {
    const cue = parseSrt(b).cues[0];
    return cue !== undefined && cue.startMs < limitMs;
  });
  return `${kept.join('\n\n')}\n`;
}

function trimWords(words: Json, limitMs: number): Json {
  const cues = (words.cues as { s: number }[]).filter((c) => c.s < limitMs);
  return { ...words, cues };
}

function trimInfo(info: Json): Json {
  const keep = Object.keys(InfoSchema.shape);
  return Object.fromEntries(Object.entries(info).filter(([k]) => keep.includes(k)));
}

interface Iteration {
  start_time: string;
  sections?: { screenshot_timestamp: string }[];
  chapters?: { timestamp: string }[];
}

function trimIterations(doc: Json, limitMs: number): Json {
  const iterations = (doc.iterations as Iteration[])
    .filter((it) => hmsToMs(it.start_time) < limitMs)
    .map((it) => ({
      ...it,
      ...(it.sections && {
        sections: it.sections.filter((s) => hmsToMs(s.screenshot_timestamp) < limitMs),
      }),
      ...(it.chapters && {
        chapters: it.chapters.filter((c) => hmsToMs(c.timestamp) < limitMs),
      }),
    }));
  return { ...doc, iterations };
}

/** Inline datoteke koje fixture zadržava; ostale (Magisterium) se izbace radi veličine. */
const INLINE_KEEP = ['info.json', 'summary.json', 'outline.json', 'article.json'];

async function refreshEpisode(spec: FixtureSpec): Promise<Json> {
  const { id } = spec;
  const bundle = await getJson(`data/${id}/episode.json`);
  const files = bundle.files as string[];
  const inline = bundle.inline as Json;
  const summary = inline['summary.json'] as { source: { channel: string } } | undefined;
  if (!summary) throw new Error(`${id}: episode.json nema inline summary.json`);

  const hasWords = files.includes('words.json');
  if (spec.criterion === 'words' && !hasWords) throw new Error(`${id}: nema words.json`);
  if (spec.criterion === 'no_words' && hasWords) {
    throw new Error(`${id}: dobio je words.json; izaberi drugu epizodu bez njega`);
  }
  if (spec.lang && !files.includes(`diarized.${spec.lang}.srt`)) {
    throw new Error(`${id}: nema diarized.${spec.lang}.srt`);
  }

  const dir = join(FIXTURES_DIR, id);
  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });

  const trimmedInline: Json = {};
  for (const name of INLINE_KEEP) {
    const v = inline[name] as Json | undefined;
    if (!v) continue;
    if (name === 'info.json') trimmedInline[name] = trimInfo(v);
    else if (name === 'article.json' || name === 'outline.json') {
      trimmedInline[name] = trimIterations(v, LIMIT_MS);
    } else trimmedInline[name] = v;
  }
  const out: Record<string, string> = {
    'episode.json': JSON.stringify({ ...bundle, inline: trimmedInline }, null, 1),
  };

  const srtNames = ['diarized.srt', ...(spec.lang ? [`diarized.${spec.lang}.srt`] : [])];
  const wordNames = ['words.json', ...(spec.lang ? [`words.${spec.lang}.json`] : [])];
  for (const name of srtNames) {
    const raw = await getText(`data/${id}/${name}`);
    if (raw === null) throw new Error(`${id}: ${name} je na popisu, a CDN vraća 404`);
    out[name] = trimSrt(raw, LIMIT_MS);
  }
  for (const name of wordNames) {
    if (!files.includes(name)) continue;
    out[name] = JSON.stringify(trimWords(await getJson(`data/${id}/${name}`), LIMIT_MS));
  }

  const sizes: Record<string, number> = {};
  for (const [name, body] of Object.entries(out)) {
    await writeFile(join(dir, name), body);
    sizes[name] = Buffer.byteLength(body);
  }
  const total = Object.values(sizes).reduce((a, b) => a + b, 0);
  if (total > 200 * 1024) throw new Error(`${id}: fixture ima ${String(total)} B (> 200 kB)`);
  return { ...spec, channel: summary.source.channel, files: sizes, totalBytes: total };
}

async function main(): Promise<void> {
  const manifest: Json[] = [];
  for (const spec of FIXTURES) {
    manifest.push(await refreshEpisode(spec));
    console.log(`ok ${spec.id} (${spec.criterion})`);
  }

  // Listinzi kanala: zaglavlje + samo fixture epizode, stvarni oblik.
  const ids = new Set(FIXTURES.map((f) => f.id));
  const index = await getJson('channels/data/index.json');
  const channels = index.channels as { id: string }[];
  const keptChannels: { id: string }[] = [];
  await mkdir(join(FIXTURES_DIR, 'channels'), { recursive: true });
  for (const ch of channels) {
    const listing = await getJson(`channels/data/${ch.id}.json`);
    const videos = (listing.videos as { id: string }[]).filter((v) => ids.has(v.id));
    if (videos.length === 0) continue;
    keptChannels.push(ch);
    await writeFile(
      join(FIXTURES_DIR, 'channels', `${ch.id}.json`),
      JSON.stringify({ ...listing, videos }, null, 1),
    );
  }
  await writeFile(
    join(FIXTURES_DIR, 'channels', 'index.json'),
    JSON.stringify({ ...index, channels: keptChannels }, null, 1),
  );
  await writeFile(
    join(FIXTURES_DIR, 'manifest.json'),
    JSON.stringify({ refreshed_at: new Date().toISOString(), limit_ms: LIMIT_MS, fixtures: manifest }, null, 1),
  );
  console.log(`kanali: ${keptChannels.map((c) => c.id).join(', ')}`);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  await main();
}

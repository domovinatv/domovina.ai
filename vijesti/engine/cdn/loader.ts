// CDN loader: čita cdn.domovina.ai samo čitanjem. Pravila iz korijenskog
// CLAUDE.md vrijede i ovdje:
// - datoteku koje nema u `episode.json` ne traži (popis je izmjeren na R2);
// - popis iz cachea nije zadnja riječ: kad kaže „nema”, episode.json se jednom
//   traži iznova prije zaključka;
// - 404 s CDN-a se ponovi jednom s cache-busterom (`?cb=<5-min bucket>`), jer
//   CDN cachira 404 i do 4 h.
// `fetch` je injektiran: testovi nikad ne idu na mrežu.
import type { z } from 'zod';
import type { DiskCache } from './cache.js';
import {
  ArticleSchema,
  ChannelIndexSchema,
  ChannelListingSchema,
  EpisodeBundleSchema,
  InfoSchema,
  SummarySchema,
  WordsFileSchema,
  type Article,
  type ChannelIndex,
  type ChannelListing,
  type EpisodeBundle,
  type Info,
  type Summary,
  type WordsFile,
} from './schemas.js';
import { parseSrt, type ParsedSrt } from './srt.js';
import { attachWords, type TimedCue } from './words.js';

export interface FetchResponseLike {
  status: number;
  ok: boolean;
  text(): Promise<string>;
}
export type FetchLike = (
  url: string,
  init?: { headers?: Record<string, string> },
) => Promise<FetchResponseLike>;

export const DEFAULT_CDN_BASE = 'https://cdn.domovina.ai';
/** Cloudflare na CDN-u odbija neke zadane klijente (Python urllib dobije 403). */
export const DEFAULT_USER_AGENT = 'domovina-vijesti/0.1 (+https://domovina.ai/vijesti)';
const BUCKET_MS = 5 * 60 * 1000;

export interface CdnClientOptions {
  fetch: FetchLike;
  baseUrl?: string;
  cache?: DiskCache | null;
  now?: () => number;
  /** Rok za promjenjive datoteke u cacheu (episode.json, listinzi). Zadano 5 min. */
  mutableMaxAgeMs?: number;
  userAgent?: string;
}

export class CdnHttpError extends Error {
  constructor(
    readonly url: string,
    readonly status: number,
  ) {
    super(`CDN ${url} -> HTTP ${status}`);
    this.name = 'CdnHttpError';
  }
}

export class CdnSchemaError extends Error {
  constructor(
    readonly path: string,
    readonly detail: string,
  ) {
    super(`CDN ${path}: neispravan oblik (${detail})`);
    this.name = 'CdnSchemaError';
  }
}

export interface LoadedEpisode {
  id: string;
  /** `null` kad epizoda nema episode.json (stari put, datoteku po datoteku). */
  bundle: EpisodeBundle | null;
  info: Info | null;
  summary: Summary | null;
  article: Article | null;
  /** Ime titla koji je učitan (`diarized.srt` ili `diarized.<lang>.srt`). */
  srtFile: string | null;
  srt: ParsedSrt | null;
  wordsFile: string | null;
  words: WordsFile | null;
  /** SRT cue-ovi s vremenima riječi gdje ih ugovor dopušta. */
  cues: TimedCue[];
}

export interface CdnClient {
  readonly baseUrl: string;
  channelIndex(): Promise<ChannelIndex>;
  channel(slug: string): Promise<ChannelListing | null>;
  bundle(id: string): Promise<EpisodeBundle | null>;
  /** Sirovi sadržaj `data/<id>/<name>` ili `null` ako datoteke nema. */
  file(id: string, name: string): Promise<string | null>;
  has(id: string, name: string): Promise<boolean>;
  info(id: string): Promise<Info | null>;
  summary(id: string): Promise<Summary | null>;
  article(id: string): Promise<Article | null>;
  srt(id: string, lang?: string): Promise<ParsedSrt | null>;
  words(id: string, lang?: string): Promise<WordsFile | null>;
  /**
   * Sve što engine treba za epizodu. Uz `lang` uzima `diarized.<lang>.srt` i
   * `words.<lang>.json` ako ih episode.json navodi, inače zadani par
   * (pravilo iz docs/plans/2026-10-29-titlovi-na-dva-jezika.md).
   */
  loadEpisode(id: string, opts?: { lang?: string }): Promise<LoadedEpisode>;
}

const ID_RE = /^[A-Za-z0-9_-]{6,64}$/;
const NAME_RE = /^[A-Za-z0-9_.-]+$/;

function assertId(id: string): void {
  if (!ID_RE.test(id)) throw new Error(`neispravan ID epizode: ${id}`);
}

/**
 * Navodi li episode.json datoteku: na popisu `files` ili inline s vrijednošću.
 * Inline `null` nije sadržaj, pa ne smije reći „ima” dok `file()` vraća null.
 */
function listedIn(bundle: EpisodeBundle, name: string): boolean {
  const inline = bundle.inline[name];
  return bundle.files.includes(name) || (inline !== undefined && inline !== null);
}

export function cacheBucket(nowMs: number): number {
  return Math.floor(nowMs / BUCKET_MS);
}

function parseJson<S extends z.ZodType>(path: string, body: string, schema: S): z.infer<S> {
  let raw: unknown;
  try {
    raw = JSON.parse(body);
  } catch (e) {
    throw new CdnSchemaError(path, `nije JSON: ${(e as Error).message}`);
  }
  return validate(path, raw, schema);
}

function validate<S extends z.ZodType>(path: string, raw: unknown, schema: S): z.infer<S> {
  const res = schema.safeParse(raw);
  if (!res.success) {
    const first = res.error.issues[0];
    const where = first ? first.path.join('.') : '';
    throw new CdnSchemaError(path, `${where}: ${first?.message ?? 'nepoznato'}`);
  }
  return res.data;
}

export function createCdnClient(opts: CdnClientOptions): CdnClient {
  const baseUrl = (opts.baseUrl ?? DEFAULT_CDN_BASE).replace(/\/+$/, '');
  const now = opts.now ?? Date.now;
  const cache = opts.cache ?? null;
  const mutableMaxAgeMs = opts.mutableMaxAgeMs ?? BUCKET_MS;
  const headers = { 'user-agent': opts.userAgent ?? DEFAULT_USER_AGENT };
  const bundles = new Map<string, Promise<{ bundle: EpisodeBundle | null; fromCache: boolean }>>();

  async function get(url: string): Promise<FetchResponseLike> {
    return opts.fetch(url, { headers });
  }

  /**
   * Tekst s CDN-a ili `null` za 404 (nakon jednog ponavljanja s cache-busterom).
   * `mutable` datoteke imaju rok u cacheu; `fresh` preskače cache.
   */
  async function fetchText(
    path: string,
    mode: { mutable: boolean; fresh?: boolean },
  ): Promise<{ body: string | null; fromCache: boolean }> {
    if (cache && !mode.fresh) {
      const hit = await cache.get(path, mode.mutable ? mutableMaxAgeMs : undefined);
      if (hit !== null) return { body: hit, fromCache: true };
    }
    const url = `${baseUrl}/${path}`;
    let res = await get(url);
    if (res.status === 404) {
      res = await get(`${url}?cb=${String(cacheBucket(now()))}`);
    }
    if (res.status === 404) return { body: null, fromCache: false };
    if (!res.ok) throw new CdnHttpError(url, res.status);
    const body = await res.text();
    if (cache) await cache.set(path, body);
    return { body, fromCache: false };
  }

  function loadBundle(id: string, fresh: boolean) {
    const path = `data/${id}/episode.json`;
    return fetchText(path, { mutable: true, fresh }).then(({ body, fromCache }) => ({
      bundle: body === null ? null : parseJson(path, body, EpisodeBundleSchema),
      fromCache,
    }));
  }

  /** Memoiziran dohvat; neuspjeh se ne pamti (sljedeći poziv pokušava iznova). */
  function remember(id: string, fresh: boolean) {
    const p = loadBundle(id, fresh);
    bundles.set(id, p);
    p.catch(() => {
      if (bundles.get(id) === p) bundles.delete(id);
    });
    return p;
  }

  async function bundleState(id: string) {
    assertId(id);
    return bundles.get(id) ?? remember(id, false);
  }

  /** Bundle koji navodi `name`, uz jednu revalidaciju kad cache kaže „nema”. */
  async function bundleFor(id: string, name: string) {
    let state = await bundleState(id);
    if (state.bundle && !listedIn(state.bundle, name) && state.fromCache) {
      state = await remember(id, true);
    }
    return state;
  }

  async function file(id: string, name: string): Promise<string | null> {
    if (!NAME_RE.test(name)) throw new Error(`neispravno ime datoteke: ${name}`);
    const { bundle } = await bundleFor(id, name);
    if (bundle) {
      const inline = bundle.inline[name];
      if (inline !== undefined && inline !== null) {
        return typeof inline === 'string' ? inline : JSON.stringify(inline);
      }
      if (!bundle.files.includes(name)) return null;
    }
    const { body } = await fetchText(`data/${id}/${name}`, { mutable: false });
    return body;
  }

  async function has(id: string, name: string): Promise<boolean> {
    const { bundle } = await bundleFor(id, name);
    if (bundle) return listedIn(bundle, name);
    return (await file(id, name)) !== null;
  }

  async function json<S extends z.ZodType>(
    id: string,
    name: string,
    schema: S,
  ): Promise<z.infer<S> | null> {
    const body = await file(id, name);
    return body === null ? null : parseJson(`data/${id}/${name}`, body, schema);
  }

  async function srtNamed(id: string, name: string): Promise<ParsedSrt | null> {
    const body = await file(id, name);
    return body === null ? null : parseSrt(body);
  }

  const client: CdnClient = {
    baseUrl,
    async channelIndex() {
      const path = 'channels/data/index.json';
      const { body } = await fetchText(path, { mutable: true });
      if (body === null) throw new CdnHttpError(`${baseUrl}/${path}`, 404);
      return parseJson(path, body, ChannelIndexSchema);
    },
    async channel(slug) {
      if (!NAME_RE.test(slug)) throw new Error(`neispravan slug kanala: ${slug}`);
      const path = `channels/data/${slug}.json`;
      const { body } = await fetchText(path, { mutable: true });
      return body === null ? null : parseJson(path, body, ChannelListingSchema);
    },
    async bundle(id) {
      return (await bundleState(id)).bundle;
    },
    file,
    has,
    info: (id) => json(id, 'info.json', InfoSchema),
    summary: (id) => json(id, 'summary.json', SummarySchema),
    article: (id) => json(id, 'article.json', ArticleSchema),
    srt: (id, lang) => srtNamed(id, lang ? `diarized.${lang}.srt` : 'diarized.srt'),
    words: (id, lang) => json(id, lang ? `words.${lang}.json` : 'words.json', WordsFileSchema),
    async loadEpisode(id, o = {}) {
      const bundle = await client.bundle(id);
      let srtFile = 'diarized.srt';
      let wordsFile = 'words.json';
      if (o.lang && (await has(id, `diarized.${o.lang}.srt`))) {
        srtFile = `diarized.${o.lang}.srt`;
        wordsFile = `words.${o.lang}.json`;
      }
      const [info, summary, article, srt, words] = await Promise.all([
        client.info(id),
        client.summary(id),
        client.article(id),
        srtNamed(id, srtFile),
        json(id, wordsFile, WordsFileSchema),
      ]);
      return {
        id,
        bundle,
        info,
        summary,
        article,
        srtFile: srt ? srtFile : null,
        srt,
        wordsFile: words ? wordsFile : null,
        words,
        cues: srt ? attachWords(srt.cues, words) : [],
      };
    },
  };
  return client;
}

export { validate as validateCdnJson };

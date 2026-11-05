// Osobe iz `https://mcp.domovina.ai/api/persons` (domovina-rag) i
// determinističko uparivanje imena govornika s osobom (odluke 308, 314).
// Ime govornika dolazi iz `summary.json` (`speakers[].suggested_name` po
// oznaci SPEAKER_XX); LLM ga ne bira.
import { z } from 'zod';
import type { DiskCache } from '../cdn/cache.js';
import { DEFAULT_USER_AGENT, type FetchLike } from '../cdn/loader.js';

export const PERSONS_URL = 'https://mcp.domovina.ai/api/persons';
export const PERSONS_CACHE_PATH = 'persons/persons.json';
/** Popis se mijenja kad backend uvrsti novu osobu; dan je dovoljno svježe. */
export const PERSONS_MAX_AGE_MS = 24 * 60 * 60 * 1000;

export const PersonSchema = z.object({
  slug: z.string().min(1),
  name: z.string().min(1),
  episode_count: z.number().int().nonnegative(),
  channel_count: z.number().int().nonnegative(),
  is_virtual_channel: z.boolean().nullish(),
});
export type Person = z.infer<typeof PersonSchema>;

export const PersonsFileSchema = z.object({
  version: z.string(),
  person_count: z.number().int().nonnegative(),
  persons: z.array(PersonSchema),
});
export type PersonsFile = z.infer<typeof PersonsFileSchema>;

/**
 * Titule i oslovljavanja koja nisu dio imena (nakon normalizacije, bez točke):
 * „don”, „fra”, „dr.”, „p.”/„pater”, „vlč.”, „fr.”, „mons.”… „o.” (otac) je
 * namjerno samo kao zasebna riječ ispred imena.
 */
export const NAME_TITLES = new Set([
  'don',
  'fra',
  'dr',
  'sc',
  'prof',
  'doc',
  'izv',
  'mr',
  'mag',
  'ing',
  'dipl',
  'mons',
  'msgr',
  'vlc',
  'p',
  'pater',
  'otac',
  'o',
  'fr',
  'father',
  'rev',
  'sv',
  'sveti',
  's',
  'sestra',
  'sr',
  'br',
  'brat',
  'gosp',
  'gdin',
  'gda',
]);

/** Oznake koje nisu ime (pipeline ih piše kad govornika ne zna). */
const PLACEHOLDER_RE = /^(gost|govornik|sugovornik|voditelj|nepoznat\p{L}*|speaker|unknown|guest|host)\b/u;

/** Mala slova, bez dijakritike (`đ → d`), bez zagrada, interpunkcije i titula. */
export function nameTokens(name: string): string[] {
  const base = name
    .replace(/\([^)]*\)/g, ' ')
    .toLowerCase()
    .replace(/đ/g, 'd')
    .normalize('NFD')
    .replace(/\p{M}/gu, '')
    .replace(/[^\p{L}\p{N}]+/gu, ' ')
    .trim();
  if (!base) return [];
  return base.split(/\s+/).filter((t) => !NAME_TITLES.has(t));
}

export function normalizeName(name: string): string {
  return nameTokens(name).join(' ');
}

export type NoMatchReason = 'empty' | 'placeholder' | 'single_token' | 'not_found';

export type PersonMatch =
  | {
      matched: true;
      person: Person;
      key: string;
      /** Više zapisa s istim imenom (npr. „p.” i „Pater” Horvat): uzet onaj s najviše epizoda. */
      alternates: string[];
    }
  | { matched: false; key: string; reason: NoMatchReason };

export interface PersonIndex {
  readonly size: number;
  match(name: string | null | undefined): PersonMatch;
}

export function buildPersonIndex(persons: readonly Person[]): PersonIndex {
  const byKey = new Map<string, Person[]>();
  for (const p of persons) {
    const key = normalizeName(p.name);
    if (nameTokens(p.name).length < 2 || PLACEHOLDER_RE.test(key)) continue;
    const list = byKey.get(key) ?? [];
    list.push(p);
    byKey.set(key, list);
  }
  for (const list of byKey.values()) {
    list.sort((a, b) => b.episode_count - a.episode_count || a.slug.localeCompare(b.slug));
  }
  return {
    size: byKey.size,
    match(name) {
      const raw = (name ?? '').trim();
      if (!raw) return { matched: false, key: '', reason: 'empty' };
      const tokens = nameTokens(raw);
      const key = tokens.join(' ');
      if (/^SPEAKER_\d+$/i.test(raw) || PLACEHOLDER_RE.test(key)) {
        return { matched: false, key, reason: 'placeholder' };
      }
      if (tokens.length === 0) return { matched: false, key, reason: 'empty' };
      // Samo ime ili samo prezime nije dovoljno: „Ana”, „Raspudić”.
      if (tokens.length < 2) return { matched: false, key, reason: 'single_token' };
      const list = byKey.get(key);
      const first = list?.[0];
      if (!list || !first) return { matched: false, key, reason: 'not_found' };
      return { matched: true, person: first, key, alternates: list.slice(1).map((p) => p.slug) };
    },
  };
}

export function parsePersons(body: string): PersonsFile {
  return PersonsFileSchema.parse(JSON.parse(body));
}

export interface LoadPersonsOptions {
  fetch: FetchLike;
  cache?: DiskCache | null;
  url?: string;
  maxAgeMs?: number;
}

export interface LoadedPersons {
  file: PersonsFile;
  source: 'network' | 'cache' | 'stale-cache';
}

/**
 * Svjež disk cache → mreža → zastario cache. Nečitljiv odgovor se ne sprema.
 * Bez ičega baca: ocjena bez popisa osoba bi tiho dala nulu svakom govorniku.
 */
export async function loadPersons(opts: LoadPersonsOptions): Promise<LoadedPersons> {
  const cache = opts.cache ?? null;
  const fresh = await cache?.get(PERSONS_CACHE_PATH, opts.maxAgeMs ?? PERSONS_MAX_AGE_MS);
  if (fresh) return { file: parsePersons(fresh), source: 'cache' };
  let netError: Error;
  try {
    const res = await opts.fetch(opts.url ?? PERSONS_URL, { headers: { 'user-agent': DEFAULT_USER_AGENT } });
    if (!res.ok) throw new Error(`HTTP ${String(res.status)}`);
    const body = await res.text();
    const file = parsePersons(body);
    await cache?.set(PERSONS_CACHE_PATH, body);
    return { file, source: 'network' };
  } catch (e) {
    netError = e as Error;
  }
  const stale = await cache?.get(PERSONS_CACHE_PATH);
  if (stale) return { file: parsePersons(stale), source: 'stale-cache' };
  throw new Error(`popis osoba nedostupan (${opts.url ?? PERSONS_URL}): ${netError.message}`);
}

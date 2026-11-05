// Lažni CDN nad fixtureima: `https://cdn.domovina.ai/<putanja>` se čita iz
// engine/test/fixtures/. Upit (`?cb=…`) se ignorira pri čitanju, ali se bilježi.
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';
import type { FetchLike, FetchResponseLike } from '../cdn/loader.js';
import { FIXTURES_DIR } from './fixtures-refresh.js';

export interface FakeCdn {
  fetch: FetchLike;
  /** Svi traženi URL-ovi, redom. */
  calls: string[];
  /** Zahtjevi s User-Agent zaglavljem. */
  userAgents: (string | undefined)[];
}

export interface FakeCdnOptions {
  base?: string;
  /** Putanje (bez upita) koje vraćaju 404 dok URL nema `cb=` (cachiran 404). */
  stale404?: string[];
  /** Zamjenski sadržaj po putanji; `null` = 404. */
  overrides?: Record<string, string | null>;
  /** HTTP status po putanji (npr. 500). */
  statuses?: Record<string, number>;
}

function response(status: number, body: string): FetchResponseLike {
  return { status, ok: status >= 200 && status < 300, text: () => Promise.resolve(body) };
}

function fixturePath(path: string): string | null {
  const data = /^data\/([^/]+)\/([^/]+)$/.exec(path);
  if (data) return join(FIXTURES_DIR, data[1] ?? '', data[2] ?? '');
  const ch = /^channels\/data\/([^/]+)$/.exec(path);
  if (ch) return join(FIXTURES_DIR, 'channels', ch[1] ?? '');
  return null;
}

export function createFakeCdn(opts: FakeCdnOptions = {}): FakeCdn {
  const base = opts.base ?? 'https://cdn.domovina.ai';
  const calls: string[] = [];
  const userAgents: (string | undefined)[] = [];
  const fetch: FetchLike = (url, init) => {
    calls.push(url);
    userAgents.push(init?.headers?.['user-agent']);
    if (!url.startsWith(`${base}/`)) return Promise.resolve(response(404, ''));
    const [path = '', query = ''] = url.slice(base.length + 1).split('?');
    const status = opts.statuses?.[path];
    if (status !== undefined) return Promise.resolve(response(status, ''));
    if (opts.stale404?.includes(path) && !query.includes('cb=')) {
      return Promise.resolve(response(404, ''));
    }
    if (opts.overrides && path in opts.overrides) {
      const body = opts.overrides[path];
      return Promise.resolve(body == null ? response(404, '') : response(200, body));
    }
    const file = fixturePath(path);
    if (!file || !existsSync(file)) return Promise.resolve(response(404, ''));
    return Promise.resolve(response(200, readFileSync(file, 'utf8')));
  };
  return { fetch, calls, userAgents };
}

export function readFixture(id: string, name: string): string {
  return readFileSync(join(FIXTURES_DIR, id, name), 'utf8');
}

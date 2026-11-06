// Čista logika portala (S6): vrijeme, URL-ovi, konfiguracija, kategorije,
// greške i PostgREST klijent nad lažnim fetchom.
import { describe, expect, it } from 'vitest';
import { CATEGORIES } from '../../../engine/write/prompt.js';
import { mintUnsignedJwt } from '../scripts/admin/auth-local.js';
import { decodeJwtPayload } from '../../dev/rest-shim.js';
import { CATEGORY_SLUGS, categoryLabel, isCategory } from './categories.js';
import { DEFAULT_CONFIG, readConfig } from './config.js';
import { describeError } from './errors.js';
import { clipLength, clock, hrDateTime, zagrebDay } from './format.js';
import { createRest, eq, inList, RestError, type FetchFn } from './rest.js';
import {
  appEpisodeUrl,
  articlePath,
  categoryPath,
  clipUrl,
  episodeBundleUrl,
  fragmentSeconds,
  pickClipMedia,
  portalPath,
} from './urls.js';

describe('vrijeme i datum', () => {
  it('clock: m:ss ispod sata, h:mm:ss iznad (isto kao vijesti._clock)', () => {
    expect(clock(0)).toBe('0:00');
    expect(clock(13_590)).toBe('0:13');
    expect(clock(657_150)).toBe('10:57');
    expect(clock(3_599_999)).toBe('59:59');
    expect(clock(3_600_000)).toBe('1:00:00');
    expect(clock(5_963_000)).toBe('1:39:23');
  });
  it('trajanje isječka', () => {
    expect(clipLength(13_590, 27_750)).toBe('0:14');
    expect(clipLength(5000, 1000)).toBe('0:00');
  });
  it('datum objave je zagrebački dan', () => {
    expect(zagrebDay('2026-11-06T23:30:00Z')).toBe('2026-11-07');
    expect(zagrebDay('2026-07-01T21:59:00Z')).toBe('2026-07-01');
    expect(hrDateTime('2026-11-06T10:00:00.000Z')).toBe('6. studenoga 2026.');
    expect(zagrebDay('nije datum')).toBeNull();
    expect(hrDateTime(null)).toBeNull();
  });
});

describe('URL-ovi', () => {
  it('isječak: media fragment u sekundama s najviše tri decimale', () => {
    expect(fragmentSeconds(657_150)).toBe('657.15');
    expect(fragmentSeconds(1000)).toBe('1');
    expect(fragmentSeconds(-5)).toBe('0');
    expect(clipUrl('https://cdn.domovina.ai', 'pIx_7N-6HJ4', 'audio.mp3', 13_590, 27_750)).toBe(
      'https://cdn.domovina.ai/data/pIx_7N-6HJ4/audio.mp3#t=13.59,27.75',
    );
    expect(episodeBundleUrl('http://127.0.0.1:8790/cdn', 'a b')).toBe('http://127.0.0.1:8790/cdn/data/a%20b/episode.json');
  });
  it('medij isječka: audio.mp3 ako postoji, inače video_h264.mp4, inače ništa', () => {
    expect(pickClipMedia(['audio.mp3', 'video_h264.mp4'])).toBe('audio.mp3');
    expect(pickClipMedia(['video_h264.mp4', 'video.mp4'])).toBe('video_h264.mp4');
    expect(pickClipMedia(['video.mp4'])).toBeNull();
    expect(pickClipMedia(null)).toBeNull();
  });
  it('aplikacija: /v/<id>/t/<sekunda>, bez /t/ na početku', () => {
    expect(appEpisodeUrl('https://domovina.ai', 'pIx_7N-6HJ4', 657_150)).toBe('https://domovina.ai/v/pIx_7N-6HJ4/t/657');
    expect(appEpisodeUrl('https://domovina.ai', 'pIx_7N-6HJ4', 999)).toBe('https://domovina.ai/v/pIx_7N-6HJ4');
  });
  it('putanje portala pod /vijesti', () => {
    expect(portalPath('/vijesti')).toBe('/vijesti/');
    expect(portalPath('/vijesti/')).toBe('/vijesti/');
    expect(articlePath('/vijesti/', 'naslov-abc')).toBe('/vijesti/naslov-abc');
    expect(categoryPath('/vijesti', 'znanost-tehnologija')).toBe('/vijesti/kategorija/znanost-tehnologija');
  });
});

describe('kategorije i konfiguracija', () => {
  it('nazivi pokrivaju točno zatvoreni popis generatora', () => {
    expect([...CATEGORY_SLUGS].sort()).toEqual([...CATEGORIES].sort());
    expect(categoryLabel('znanost-tehnologija')).toBe('Znanost i tehnologija');
    expect(categoryLabel('nepostojeca')).toBe('Vijesti');
    expect(isCategory('toString')).toBe(false);
  });
  it('zadane vrijednosti su produkcijske; prazno i kosa crta na kraju se čiste', () => {
    expect(readConfig({})).toEqual(DEFAULT_CONFIG);
    const c = readConfig({ VIJESTI_REST_URL: 'http://127.0.0.1:8790/', VIJESTI_CDN_BASE: ' ', VIJESTI_ANON_KEY: 'k' });
    expect(c.restUrl).toBe('http://127.0.0.1:8790');
    expect(c.authUrl).toBe('http://127.0.0.1:8790');
    expect(c.cdnBase).toBe(DEFAULT_CONFIG.cdnBase);
    expect(c.anonKey).toBe('k');
  });
});

describe('greške za urednika', () => {
  it('urednička pravila po prefiksu koda, s pojedinostima iz baze', () => {
    const e = describeError(new RestError(400, 'P0001', 'unresolved: rečenice 4, 7 nemaju razrješenje'));
    expect(e.code).toBe('unresolved');
    expect(e.text).toMatch(/razriješi/);
    expect(e.detail).toBe('rečenice 4, 7 nemaju razrješenje');
    expect(describeError(new RestError(400, 'P0001', 'stale_version: verzija 3 nije zadnja')).text).toMatch(/novija verzija/);
  });
  it('prava, istek prijave, mreža i nepoznato', () => {
    expect(describeError(new RestError(401, '42501', 'permission denied for function')).text).toMatch(/Prijava/);
    expect(describeError(new RestError(403, '42501', 'permission denied')).text).toMatch(/ovlasti/);
    expect(describeError(new RestError(401, 'PGRST303', 'JWT expired')).text).toMatch(/istekla/);
    expect(describeError(new TypeError('Failed to fetch')).text).toMatch(/nije dostupan/);
    expect(describeError(new Error('nešto: drugo')).code).toBeNull();
  });
});

describe('PostgREST klijent', () => {
  const calls: { url: string; init: RequestInit | undefined }[] = [];
  const fake =
    (status: number, body: string): FetchFn =>
    (url, init) => {
      calls.push({ url, init });
      return Promise.resolve(new Response(body, { status }));
    };

  it('select šalje apikey, Bearer i Accept-Profile: vijesti', async () => {
    calls.length = 0;
    const rest = createRest({ url: 'https://api.example/', anonKey: 'anon', fetch: fake(200, '[{"id":1}]') });
    expect(await rest.select('articles', { select: 'id', id: eq(1), status: inList(['a', 'b,c']) })).toEqual([{ id: 1 }]);
    const c = calls[0];
    expect(c?.url).toBe(
      'https://api.example/rest/v1/articles?select=id&id=eq.1&status=in.%28%22a%22%2C%22b%2Cc%22%29',
    );
    expect(c?.init?.headers).toMatchObject({ apikey: 'anon', authorization: 'Bearer anon', 'accept-profile': 'vijesti' });
  });
  it('rpc šalje JWT korisnika i Content-Profile; greška nosi kod i poruku', async () => {
    calls.length = 0;
    const rest = createRest({
      url: 'https://api.example',
      anonKey: 'anon',
      token: 'jwt',
      fetch: fake(400, '{"code":"P0001","message":"stale_version: verzija 2 nije zadnja","details":null}'),
    });
    const err = await rest.rpc('approve_article', { p_article_id: 1 }).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(RestError);
    expect((err as RestError).code).toBe('P0001');
    expect(describeError(err).code).toBe('stale_version');
    expect(calls[0]?.url).toBe('https://api.example/rest/v1/rpc/approve_article');
    expect(calls[0]?.init?.headers).toMatchObject({ authorization: 'Bearer jwt', 'content-profile': 'vijesti' });
    expect(calls[0]?.init?.body).toBe('{"p_article_id":1}');
  });
});

describe('lažna prijava (lokalno)', () => {
  it('token je nepotpisan (alg none, prazan potpis) i nosi sub i ulogu', () => {
    const t = mintUnsignedJwt('11111111-1111-4111-8111-111111111111', 1_000);
    const [header, , sig] = t.split('.');
    expect(JSON.parse(Buffer.from(header ?? '', 'base64url').toString())).toEqual({ alg: 'none', typ: 'JWT' });
    expect(sig).toBe('');
    expect(decodeJwtPayload(t)).toMatchObject({
      sub: '11111111-1111-4111-8111-111111111111',
      role: 'authenticated',
      exp: 1_000 + 8 * 3600,
    });
  });
});

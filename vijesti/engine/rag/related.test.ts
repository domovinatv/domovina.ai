import { describe, expect, it } from 'vitest';
import type { FetchLike } from '../cdn/loader.js';
import { findRelated, topicLine } from './related.js';

const hit = (id: string, t: number, score: number, text = `Tema: tema ${id}\n\n[X] tekst`) => ({
  youtube_id: id,
  channel: 'hnb',
  episode_title: `Epizoda ${id}`,
  upload_date: '2026-05-15',
  start_ts: String(t),
  text,
  score: String(score),
});

function fakeFetch(body: unknown, status = 200, seen: string[] = []): FetchLike {
  return (url) => {
    seen.push(url);
    return Promise.resolve({ ok: status === 200, status, text: () => Promise.resolve(JSON.stringify(body)) } as never);
  };
}

describe('RAG „ista tema drugdje” (odluka 803)', () => {
  it('isključuje vlastitu epizodu, prag, jedna po epizodi, najviše 3', async () => {
    const seen: string[] = [];
    const out = await findRelated({
      fetch: fakeFetch(
        {
          results: [
            hit('SELF', 10, 0.9),
            hit('A', 0, 0.7, 'Naslov: sažetak A'),
            hit('A', 120, 0.7),
            hit('B', 30, 0.66),
            hit('C', 40, 0.65),
            hit('D', 50, 0.64),
            hit('E', 60, 0.5),
          ],
        },
        200,
        seen,
      ),
      query: 'EU Inc',
      excludeVideoId: 'SELF',
    });
    expect(out.map((r) => [r.videoId, r.t])).toEqual([
      ['A', 120],
      ['B', 30],
      ['C', 40],
    ]);
    expect(out[0]).toMatchObject({ topic: 'tema A', channel: 'hnb', episodeTitle: 'Epizoda A', score: 0.7 });
    expect(seen[0]).toContain('q=EU+Inc');
  });

  it('HTTP greška baca (pozivatelj je bilježi, članak ostaje)', async () => {
    await expect(findRelated({ fetch: fakeFetch({}, 502), query: 'x', excludeVideoId: 'y' })).rejects.toThrow(/HTTP 502/);
  });

  it('neispravan pogodak se preskače, ne ruši', async () => {
    const out = await findRelated({ fetch: fakeFetch({ results: [{ nesto: 1 }, hit('A', 5, 0.8)] }), query: 'x', excludeVideoId: 'y' });
    expect(out).toHaveLength(1);
  });

  it('topicLine skida oznaku', () => {
    expect(topicLine('Tema: EU Inc kao prvi korak\n\n[M] …')).toBe('EU Inc kao prvi korak');
    expect(topicLine('\nNaslov: Što donosi')).toBe('Što donosi');
  });
  it('tema s vremenom blizu sažetka iste epizode vodi na sekundu', async () => {
    const out = await findRelated({
      fetch: fakeFetch({ results: [hit('H', 0, 0.637, 'Naslov: sažetak'), hit('H', 2070, 0.62), hit('K', 0, 0.7, 'Naslov: s'), hit('K', 50, 0.6)] }),
      query: 'x',
      excludeVideoId: 'y',
    });
    expect(out.map((r) => [r.videoId, r.t, r.score])).toEqual([
      ['K', 0, 0.7],
      ['H', 2070, 0.637],
    ]);
  });
});

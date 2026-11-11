import { describe, expect, it } from 'vitest';
import type { ArticleBundle, EditorVersion, Resolution, SentenceCheck, Status } from './api.js';
import { blockerText, nextStep, plural, problemText, segmentText, sentencesByPlace, stepOf } from './flow.js';

const sentence = (n: number, text: string, over: Partial<SentenceCheck> = {}): SentenceCheck => ({
  n,
  part: 'block',
  block: 0,
  text,
  status: 'supported',
  supported_by: [1],
  metadata: false,
  problems: [],
  ...over,
});

function version(over: Partial<EditorVersion> = {}): EditorVersion {
  return {
    id: 10,
    article_id: 1,
    version: 3,
    title: 'Naslov',
    lead: null,
    category: null,
    content: null,
    verify: {
      version: 'x',
      base_version: 2,
      sentences: [sentence(1, 'Prva.'), sentence(2, 'Druga.', { status: 'unsupported' }), sentence(3, 'Treća.', { status: 'unsupported' })],
      removed: [],
      style: [],
      summary: { sentences: 3, supported: 1, unsupported: 2, removed: 0, style: 0 },
    },
    word_count: null,
    prompt_version: null,
    created_by: 'engine:verify',
    created_at: '2026-11-11T10:00:00Z',
    ...over,
  };
}

function bundle(status: Status, latest = version(), resolutions: Resolution[] = []): Pick<ArticleBundle, 'article' | 'latest' | 'resolutions'> {
  return {
    article: { id: 1, slug: 's', status, approved_version_id: null, published_version_id: null, updated_at: '' },
    latest,
    resolutions,
  };
}

const resolution = (n: number): Resolution => ({ version_id: 10, n, resolution: 'verified', note: 'ok', created_at: '' });

describe('urednički tok: jedan sljedeći korak', () => {
  it('traka koraka: ispravljeno je na „Objavljeno”, odbijeno i povučeno su izvan trake', () => {
    expect(stepOf('draft')).toBe('draft');
    expect(stepOf('corrected')).toBe('published');
    expect(stepOf('rejected')).toBeNull();
    expect(stepOf('retracted')).toBeNull();
  });

  it('nacrt: slanje u pregled nije blokirano, ali najavi što čeka odobrenje', () => {
    const s = nextStep(bundle('draft'));
    expect(s.action).toBe('to-review');
    expect(s.blockers).toEqual([]);
    expect(s.hint).toContain('2 rečenice čekaju potvrdu');
  });

  it('pregled: odobrenje blokirano dok rečenice čekaju, s prvom koju treba riješiti', () => {
    const s = nextStep(bundle('review'));
    expect(s.action).toBe('approve');
    expect(s.label).toBe('Odobri v3');
    expect(s.blockers).toEqual([{ kind: 'sentences', count: 2, first: 2 }]);
    expect(nextStep(bundle('review', version(), [resolution(2)])).blockers).toEqual([{ kind: 'sentences', count: 1, first: 3 }]);
    expect(nextStep(bundle('review', version(), [resolution(2), resolution(3)])).blockers).toEqual([]);
  });

  it('razrješenje druge verzije ne otključava zadnju', () => {
    const other: Resolution = { ...resolution(2), version_id: 9 };
    expect(nextStep(bundle('review', version(), [other])).blockers[0]).toMatchObject({ count: 2 });
  });

  it('verzija bez provjere (spremljena u adminu) blokira odobrenje i to kaže', () => {
    const s = nextStep(bundle('review', version({ verify: null, version: 4, created_by: 'editor:abc' })));
    expect(s.blockers).toEqual([{ kind: 'verify', version: 4, byEditor: true }]);
    expect(blockerText(s.blockers[0])).toBe('verzija v4 čeka automatsku provjeru');
  });

  it('odobreno → Objavi; odbijeno → Vrati u nacrt; objavljeno i povučeno nemaju sljedeći korak', () => {
    expect(nextStep(bundle('approved')).action).toBe('publish');
    expect(nextStep(bundle('rejected')).action).toBe('to-draft');
    expect(nextStep(bundle('published')).action).toBeNull();
    expect(nextStep(bundle('retracted')).action).toBeNull();
  });

  it('hrvatski plural u razlogu blokade', () => {
    expect(blockerText({ kind: 'sentences', count: 1, first: 1 })).toBe('1 rečenica čeka potvrdu');
    expect(blockerText({ kind: 'sentences', count: 3, first: 1 })).toBe('3 rečenice čekaju potvrdu');
    expect(blockerText({ kind: 'sentences', count: 5, first: 1 })).toBe('5 rečenica čeka potvrdu');
    expect(plural(11, 'a', 'b', 'c')).toBe('c');
    expect(plural(21, 'a', 'b', 'c')).toBe('a');
    expect(plural(12, 'a', 'b', 'c')).toBe('c');
    expect(plural(22, 'a', 'b', 'c')).toBe('b');
  });
});

describe('rečenice u tekstu', () => {
  it('odlomak se razlama na rečenice redom, razmaci ostaju tekst', () => {
    const s1 = sentence(1, 'Prva rečenica.');
    const s2 = sentence(2, 'Druga rečenica.');
    expect(segmentText('Prva rečenica. Druga rečenica.', [s1, s2])).toEqual([
      { kind: 'sentence', sentence: s1 },
      { kind: 'text', text: ' ' },
      { kind: 'sentence', sentence: s2 },
    ]);
  });

  it('rečenica koje nema u tekstu: null (crta se običan tekst, kartice ispod)', () => {
    expect(segmentText('Prva rečenica.', [sentence(1, 'Nema je.')])).toBeNull();
    // Redoslijed se poštuje: druga se ne traži prije kraja prve.
    expect(segmentText('A. B.', [sentence(1, 'B.'), sentence(2, 'A.')])).toBeNull();
  });

  it('grupiranje po mjestu: naslov, uvod, blok', () => {
    const m = sentencesByPlace([
      sentence(1, 'N', { part: 'title', block: null }),
      sentence(2, 'U', { part: 'lead', block: null }),
      sentence(3, 'B', { block: 2 }),
      sentence(4, 'C', { block: 2 }),
    ]);
    expect([...m.keys()]).toEqual(['title', 'lead', 'block:2']);
    expect(m.get('block:2')?.map((s) => s.n)).toEqual([3, 4]);
  });

  it('razlog označavanja ljudskim riječima; nepoznato ime ostaje doslovno', () => {
    expect(problemText({ code: 'low_overlap', detail: 'preklapanje 0.25 < 0.4' })).toBe('malo zajedničkih riječi s izvornim trenutkom');
    expect(problemText({ code: 'unknown_name', detail: 'ime „X” nije u izvoru' })).toBe('ime „X” nije u izvoru');
    expect(problemText({ code: 'llm_unsupported', detail: 'nije rečeno' })).toBe('provjera nije našla potporu u snimci: nije rečeno');
    expect(problemText({ code: 'novo' })).toBe('novo');
  });
});

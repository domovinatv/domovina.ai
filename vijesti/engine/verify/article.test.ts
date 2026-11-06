// Provjera članka: LLM sloj nad lažnim klijentom i deterministički pod koji
// hvata izmišljenu tvrdnju, krivo ime, krivi broj i citat kojeg nema i kad
// provjeravatelj laže „podržano” (odluke 426–433).
import type { PGlite } from '@electric-sql/pglite';
import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createFakeLlmClient, createResponderLlm } from '../llm/fake.js';
import { parseLlmJson } from '../llm/validate.js';
import { fixtureCdn, scoredDb } from '../test/scored-db.js';
import type { ArticleContent, SourceMoment } from '../write/content.js';
import { loadLatestVersion } from '../write/store.js';
import { prepareWrite, runWrite, type PreparedWrite } from '../write/vijest.js';
import { cleanContent, runVerify, VERIFY_CREATED_BY, VERIFY_VERSION, VerifyMismatchError } from './article.js';
import {
  lexicalOverlap,
  MIN_LEXICAL_OVERLAP,
  normalizeQuote,
  numbersIn,
  sameNameToken,
  unknownNames,
} from './article-checks.js';
import { fakeVerifyResponse, lyingVerifyResponse } from './article-fake-llm.js';
import { buildVerifyPrompt, VerifyOutputSchema } from './article-prompt.js';

const VIDEO = 'MGLq9v3AtvE';
const CHANNEL = 'domovina_tv';

const words = (s: string, n: number) =>
  s
    .split(/\s+/)
    .map((t) => t.replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, ''))
    .filter(Boolean)
    .slice(0, n)
    .join(' ');

describe('deterministički pod: jedinice', () => {
  it('brojevi: razdjelnici tisućica, decimale, brojevi riječima', () => {
    expect(numbersIn('8 000 i 1.500 te 3,5 posto, 2026.')).toEqual(['8000', '1500', '3.5', '2026']);
    expect(numbersIn('dvadeset pet ljudi i tri milijuna eura', { parts: true }).sort()).toEqual(
      ['1000000', '20', '25', '3', '3000000', '5'].sort(),
    );
    expect(numbersIn('jedan od njih')).toEqual([]);
    expect(numbersIn('five thousand people')).toEqual(['5000']);
  });

  it('imena: padeži da, drugo ime ne; na početku rečenice prva riječ smije biti obična', () => {
    expect(sameNameToken('horvatu', 'horvat')).toBe(true);
    expect(sameNameToken('ivanu', 'ivan')).toBe(true);
    expect(sameNameToken('marko', 'marija')).toBe(false);
    expect(sameNameToken('kovac', 'kong')).toBe(false);
    const corpus = 'Ivan Horvat\nCatholic Futurist';
    expect(unknownNames('Prema Ivanu Horvatu, to je tako.', corpus)).toEqual([]);
    expect(unknownNames('Gost podcasta Catholic Futurist kaže da je tako.', corpus)).toEqual([]);
    expect(unknownNames('Ivan Kovač kaže da je tako.', corpus)).toEqual(['Kovač']);
    expect(unknownNames('Tako kaže Ivan Kovačević.', corpus)).toEqual(['Ivan Kovačević']);
    expect(unknownNames('Fr. Ivan Horvat kaže da je tako.', corpus)).toEqual([]);
  });

  it('citat: normalizacija samo razmaka i oblika navodnika', () => {
    expect(normalizeQuote(' Ovo  je\n„rečeno” don’t ')).toBe(normalizeQuote('Ovo je "rečeno" don\'t'));
    expect(normalizeQuote('Ovo je rečeno.')).not.toBe(normalizeQuote('Ovo je rečeno'));
    expect(normalizeQuote('Ovo je rečeno')).not.toBe(normalizeQuote('ovo je rečeno'));
  });

  it('preklapanje: riječi izvještavanja se ne broje, prekratka rečenica nema sud', () => {
    expect(lexicalOverlap('Prema riječima govornika, škola otvara novu radionicu.', 'Škola otvara novu radionicu.')).toBe(1);
    expect(lexicalOverlap('Vlada je najavila povećanje mirovina.', 'Škola otvara novu radionicu.')).toBe(0);
    expect(lexicalOverlap('Rekao je to.', 'bilo što')).toBeNull();
  });
});

describe('runVerify nad fixtureom', () => {
  let db: PGlite;
  let prep: PreparedWrite;
  let m1: SourceMoment;
  beforeEach(async () => {
    db = await scoredDb(VIDEO, CHANNEL);
    prep = await prepareWrite({ cdn: fixtureCdn(), db }, { videoId: VIDEO, channel: CHANNEL });
    const first = prep.moments.find((m) => m.position === 1);
    if (!first) throw new Error('fixture bez trenutka iznad praga');
    m1 = first;
  });
  afterEach(async () => {
    await db.close();
  });

  /** Članak iz ručno složenog izlaza generatora (lažni klijent sa snimkom). */
  async function writeArticle(out: unknown): Promise<number> {
    const recorder = createSqlRunRecorder(db);
    const llm = createFakeLlmClient({ recorder, byName: { 'write-vijest': { text: JSON.stringify(out), usage: { tokensIn: 0, tokensOut: 0 } } } });
    const r = await runWrite({ cdn: fixtureCdn(), llm, recorder, db }, { videoId: VIDEO, channel: CHANNEL });
    if (!r.saved) throw new Error('članak nije spremljen');
    return r.saved.articleId;
  }

  it('lažni provjeravatelj prolazi shemu; nova verzija engine:verify s rezultatom i istim izvorima', async () => {
    const recorder = createSqlRunRecorder(db);
    const llm = createResponderLlm('fake-verify', recorder, (req) => fakeVerifyResponse(req.prompt));
    const name = m1.speakerName ?? 'Govornik';
    const id = await writeArticle({
      title: `${name} u podcastu ${prep.episode.channelName ?? ''}`,
      lead: `${name} govorio je u podcastu ${prep.episode.channelName ?? ''} o temi: ${words(m1.quote, 12)}.`,
      body: [{ type: 'p', text: `Prema riječima govornika ${name}, ${words(m1.quote, 20)}.` }, { type: 'quote', moment: 1 }],
      category: 'drustvo',
    });
    const r = await runVerify({ llm, recorder, db }, { articleId: id });
    const prompt = buildVerifyPrompt({
      episode: prep.episode,
      moments: prep.moments,
      sentences: [{ n: 1, part: 'title', text: 'x' }],
    });
    expect(parseLlmJson(fakeVerifyResponse(prompt), VerifyOutputSchema).sentences).toHaveLength(1);
    expect(r.saved.version).toBe(2);
    expect(r.result).toMatchObject({ version: VERIFY_VERSION, base_version: 1, summary: { unsupported: 0, removed: 0 } });
    const v = await loadLatestVersion(db, id);
    expect(v).toMatchObject({ createdBy: VERIFY_CREATED_BY, version: 2, runId: r.runId });
    expect(v?.sources.map((s) => [s.id, s.position])).toEqual(prep.moments.map((m) => [m.id, m.position]));
    expect((v?.verify as { summary: unknown }).summary).toEqual(r.result.summary);
  });

  it('provjeravatelj laže „podržano t1”: izmišljena tvrdnja, krivo ime, krivi broj i citat kojeg nema se hvataju', async () => {
    const name = m1.speakerName ?? 'Govornik';
    const channel = prep.episode.channelName ?? '';
    const fabricated = 'Vlada je najavila povećanje mirovina za umirovljenike od siječnja.';
    const wrongName = `Prema riječima govornika Ivan Kovačević, ${words(m1.quote, 20)}.`;
    const wrongNumber = `Prema riječima govornika ${name}, skup je okupio 4817 ljudi, a ${words(m1.quote, 15)}.`;
    const fakeQuote = 'Govornik je rekao „ovo nitko nikad nije izgovorio na snimci”.';
    const realQuote = `Govornik je rekao „${m1.quote}”`;
    const valid = `Prema riječima govornika ${name}, ${words(m1.quote, 20)}.`;
    await writeArticle({
      title: `${name} u podcastu ${channel}`,
      lead: `${name} govorio je u podcastu ${channel} o temi: ${words(m1.quote, 12)}.`,
      body: [
        { type: 'p', text: valid },
        { type: 'quote', moment: 1 },
        { type: 'p', text: fabricated },
        { type: 'p', text: wrongName },
        { type: 'p', text: wrongNumber },
        { type: 'p', text: fakeQuote },
        { type: 'p', text: realQuote },
        { type: 'quote', moment: 99 },
      ],
      category: 'drustvo',
    });
    const recorder = createSqlRunRecorder(db);
    const llm = createResponderLlm('lying-verify', recorder, (req) => lyingVerifyResponse(req.prompt));
    const r = await runVerify({ llm, recorder, db }, { videoId: VIDEO });

    // Uklonjeno automatski: citat koji nije doslovan i citat-blok bez trenutka.
    expect(r.result.removed.map((x) => [x.code, x.text])).toEqual([
      ['quote_not_verbatim', fakeQuote],
      ['quote_ref_missing', 't99'],
    ]);
    const v = await loadLatestVersion(db, r.articleId);
    const blocks = v?.content?.blocks ?? [];
    expect(blocks.some((b) => b.type === 'quote' && b.ref === 't99')).toBe(false);
    expect(blocks.some((b) => b.type === 'p' && b.text.includes('nitko nikad'))).toBe(false);
    expect(v?.body).not.toContain('nitko nikad');
    expect(blocks.some((b) => b.type === 'p' && b.text === realQuote)).toBe(true);

    // Ostaje za urednika, označeno: LLM kaže „podržano”, pod kaže ne.
    const by = new Map(r.result.sentences.map((s) => [s.text, s]));
    const codes = (t: string) => by.get(t)?.problems.map((p) => p.code) ?? ['(nema rečenice)'];
    expect(by.get(fabricated)?.status).toBe('unsupported');
    expect(codes(fabricated)).toContain('low_overlap');
    expect(by.get(fabricated)?.overlap ?? 1).toBeLessThan(MIN_LEXICAL_OVERLAP);
    expect(by.get(wrongName)?.status).toBe('unsupported');
    expect(by.get(wrongName)?.problems).toContainEqual({
      code: 'unknown_name',
      detail: 'ime „Ivan Kovačević” nije u izvoru ni u podacima o epizodi',
    });
    expect(by.get(wrongNumber)?.status).toBe('unsupported');
    expect(by.get(wrongNumber)?.problems).toContainEqual({
      code: 'unknown_number',
      detail: 'broj 4817 nije u izvoru ni u podacima o epizodi',
    });
    // Ispravne rečenice i doslovan citat prolaze.
    expect(by.get(valid)?.status).toBe('supported');
    expect(by.get(realQuote)?.status).toBe('supported');
    expect(r.result.summary).toMatchObject({ removed: 2, unsupported: 3 });
  });

  it('referenca na trenutak izvan izvora se uklanja (urednička verzija)', () => {
    const content: ArticleContent = {
      schema: 1,
      episode: prep.episode,
      title: 'Naslov',
      lead: 'Lead.',
      category: 'drustvo',
      blocks: [
        { type: 'quote', moment_id: m1.id, ref: 't1' },
        { type: 'quote', moment_id: 999_999, ref: 't1' },
      ],
    };
    const c = cleanContent(content, prep.moments);
    expect(c.content.blocks).toEqual([{ type: 'quote', moment_id: m1.id, ref: 't1' }]);
    expect(c.removed.map((x) => x.code)).toEqual(['quote_ref_not_source']);
  });

  it('nepostojeća rečenica u izlazu: cijeli izlaz se odbija, run failed, nema nove verzije; izostavljena je nepodržana', async () => {
    const name = m1.speakerName ?? 'Govornik';
    const id = await writeArticle({
      title: `${name} u podcastu ${prep.episode.channelName ?? ''}`,
      lead: `${name} govori o temi: ${words(m1.quote, 12)}.`,
      body: [{ type: 'p', text: `Prema riječima govornika ${name}, ${words(m1.quote, 20)}.` }, { type: 'quote', moment: 1 }],
      category: 'drustvo',
    });
    const recorder = createSqlRunRecorder(db);
    const bad = createResponderLlm('bad-verify', recorder, () =>
      JSON.stringify({ sentences: [{ id: 999, supported_by: [1], metadata: false, reason: null }] }),
    );
    await expect(runVerify({ llm: bad, recorder, db }, { articleId: id })).rejects.toThrow(VerifyMismatchError);
    expect((await loadLatestVersion(db, id))?.version).toBe(1);
    const runs = await db.query<{ status: string }>(`SELECT status FROM vijesti.runs WHERE step = 'verify'`);
    expect(runs.rows).toEqual([{ status: 'failed' }]);

    const partial = createResponderLlm('partial-verify', recorder, () =>
      JSON.stringify({ sentences: [{ id: 1, supported_by: [], metadata: true, reason: null }] }),
    );
    const r = await runVerify({ llm: partial, recorder, db }, { articleId: id });
    expect(r.result.sentences[0]?.status).toBe('supported');
    expect(r.result.sentences.slice(1).every((s) => s.problems.some((p) => p.code === 'verifier_omitted'))).toBe(true);
  });
});

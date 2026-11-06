// `vijesti verify`: drugi prolaz nad zadnjom verzijom članka (odluke 426–433).
//
// 1. Strukturni pod, bez modela: citat-blok bez trenutka izvora i rečenica s
//    navodnicima koji nisu doslovno `moments.quote` se UKLANJAJU (zapis u
//    `removed`). Naslov se ne uklanja nikad, samo označava.
// 2. LLM: za svaku preostalu rečenicu `supported_by` ili razlog.
// 3. Sadržajni pod (imena, brojevi, preklapanje) nad trenucima koje je LLM
//    naveo: označava `unsupported` i kad LLM kaže „podržano”, ali ne briše.
// 4. Nova verzija (`engine:verify`) s očišćenim sadržajem i rezultatom u
//    `article_versions.verify`; izvori se prenose s prethodne verzije.
import type { SqlDb } from '../../db/sql.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import {
  articleWordCount,
  renderBody,
  type ArticleContent,
  type ContentBlock,
  type SourceMoment,
} from '../write/content.js';
import { WORD_RANGE } from '../write/prompt.js';
import { findArticleId, loadLatestVersion, saveArticleVersion, type SavedVersion } from '../write/store.js';
import { splitSentences } from '../write/text.js';
import {
  checkSentence,
  DETERMINISTIC_VERSION,
  metaText,
  MIN_LEXICAL_OVERLAP,
  nonVerbatimQuotes,
  STEM_LEN,
  styleIssues,
  type Problem,
  type ProblemCode,
  type StyleIssue,
} from './article-checks.js';
import {
  buildVerifyPrompt,
  PROMPT_NAME,
  PROMPT_VERSION,
  SYSTEM_PROMPT,
  VerifyOutputSchema,
  type PromptSentence,
  type SentencePart,
  type SentenceVerdict,
} from './article-prompt.js';

export const VERIFY_VERSION = `${PROMPT_VERSION}+${DETERMINISTIC_VERSION}`;
export const VERIFY_CREATED_BY = 'engine:verify';

export interface VerifyDeps {
  llm: LlmClient;
  recorder: RunRecorder;
  db: SqlDb;
}

/** Model je naveo rečenicu koja ne postoji ili istu dvaput: izlaz se odbija cijeli (kao 312). */
export class VerifyMismatchError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VerifyMismatchError';
  }
}

export interface RemovedItem {
  part: SentencePart;
  /** Indeks bloka u PRETHODNOJ verziji (null za lead). */
  block: number | null;
  text: string;
  code: Extract<ProblemCode, 'quote_not_verbatim' | 'quote_ref_missing' | 'quote_ref_not_source'>;
  detail: string;
}

export interface SentenceResult {
  n: number;
  part: SentencePart;
  /** Indeks bloka u OVOJ verziji (null za naslov i lead). */
  block: number | null;
  text: string;
  status: 'supported' | 'unsupported';
  /** `moments.id` koje je LLM naveo i koji postoje u izvoru. */
  supported_by: number[];
  metadata: boolean;
  overlap: number | null;
  problems: Problem[];
}

export interface VerifyResult {
  version: string;
  base_version: number;
  run_id: number;
  rules: { min_lexical_overlap: number; stem_len: number };
  word_count: number;
  word_range: { min: number; max: number; ok: boolean };
  sentences: SentenceResult[];
  removed: RemovedItem[];
  style: (StyleIssue & { part: SentencePart; block: number | null })[];
  summary: { sentences: number; supported: number; unsupported: number; removed: number; style: number };
}

interface Cleaned {
  content: ArticleContent;
  removed: RemovedItem[];
  /** Problemi naslova (ne uklanja se). */
  titleProblems: Problem[];
}

/** Korak 1: strukturni pod. */
export function cleanContent(content: ArticleContent, sources: readonly SourceMoment[]): Cleaned {
  const ids = new Set(sources.map((m) => m.id));
  const removed: RemovedItem[] = [];
  const keep = (part: SentencePart, block: number | null, text: string): string => {
    const kept: string[] = [];
    for (const s of splitSentences(text)) {
      const bad = nonVerbatimQuotes(s, sources);
      if (bad.length === 0) kept.push(s);
      else {
        removed.push({
          part,
          block,
          text: s,
          code: 'quote_not_verbatim',
          detail: `u navodnicima nije doslovan citat trenutka: „${bad[0] ?? ''}”`,
        });
      }
    }
    return kept.join(' ');
  };
  const lead = keep('lead', null, content.lead);
  const blocks: ContentBlock[] = [];
  content.blocks.forEach((b, i) => {
    if (b.type === 'quote') {
      if (b.moment_id === null) {
        removed.push({ part: 'block', block: i, text: b.ref, code: 'quote_ref_missing', detail: `trenutak ${b.ref} ne postoji` });
      } else if (!ids.has(b.moment_id)) {
        removed.push({
          part: 'block',
          block: i,
          text: `${b.ref} (moment_id ${String(b.moment_id)})`,
          code: 'quote_ref_not_source',
          detail: `trenutak ${String(b.moment_id)} nije u izvorima verzije`,
        });
      } else blocks.push(b);
      return;
    }
    const text = keep('block', i, b.text);
    if (text) blocks.push({ type: 'p', text });
  });
  const titleProblems: Problem[] = nonVerbatimQuotes(content.title, sources).map((q) => ({
    code: 'quote_not_verbatim',
    detail: `naslov s navodnicima koji nisu doslovan citat: „${q}” (naslov se ne uklanja)`,
  }));
  return { content: { ...content, lead, blocks }, removed, titleProblems };
}

/** Rečenice za provjeru: naslov, lead, odlomci; citat-blokovi nisu rečenice (provjereni su referencom). */
export function articleSentences(content: ArticleContent): (PromptSentence & { block: number | null })[] {
  const out: (PromptSentence & { block: number | null })[] = [];
  const push = (part: SentencePart, block: number | null, text: string) =>
    out.push({ n: out.length + 1, part, block, text });
  push('title', null, content.title);
  for (const s of splitSentences(content.lead)) push('lead', null, s);
  content.blocks.forEach((b, i) => {
    if (b.type === 'p') for (const s of splitSentences(b.text)) push('block', i, s);
  });
  return out;
}

/** Uparuje presude s rečenicama. Nepoznat ili ponovljen broj baca; izostavljene se vraćaju. */
export function matchVerdicts(verdicts: readonly SentenceVerdict[], count: number): Map<number, SentenceVerdict> {
  const by = new Map<number, SentenceVerdict>();
  const unknown: number[] = [];
  const dup: number[] = [];
  for (const v of verdicts) {
    if (v.id < 1 || v.id > count) unknown.push(v.id);
    else if (by.has(v.id)) dup.push(v.id);
    else by.set(v.id, v);
  }
  if (unknown.length > 0 || dup.length > 0) {
    const parts = [
      ...(unknown.length > 0 ? [`nepostojeće ${unknown.map((n) => `s${String(n)}`).join(',')}`] : []),
      ...(dup.length > 0 ? [`ponovljene ${dup.map((n) => `s${String(n)}`).join(',')}`] : []),
    ];
    throw new VerifyMismatchError(`izlaz provjere ne odgovara rečenicama: ${parts.join('; ')}`);
  }
  return by;
}

/** Korak 3 za jednu rečenicu. */
export function judgeSentence(
  s: PromptSentence & { block: number | null },
  verdict: SentenceVerdict | undefined,
  content: ArticleContent,
  byPosition: ReadonlyMap<number, SourceMoment>,
  extra: readonly Problem[] = [],
): SentenceResult {
  const problems: Problem[] = [...extra];
  const support: SourceMoment[] = [];
  if (!verdict) problems.push({ code: 'verifier_omitted', detail: 'provjeravatelj nije vratio presudu za rečenicu' });
  for (const t of verdict?.supported_by ?? []) {
    const m = byPosition.get(t);
    if (m) support.push(m);
    else problems.push({ code: 'unknown_moment_ref', detail: `provjeravatelj je naveo nepostojeći trenutak t${String(t)}` });
  }
  const metadata = verdict?.metadata ?? false;
  const llmSupported = verdict !== undefined && (support.length > 0 || metadata);
  if (verdict && !llmSupported) {
    problems.push({ code: 'llm_unsupported', detail: verdict.reason ?? 'provjeravatelj bez potpore i bez razloga' });
  }
  const check = checkSentence(s.text, support, content.episode, { overlap: llmSupported });
  problems.push(...check.problems);
  return {
    n: s.n,
    part: s.part,
    block: s.block,
    text: s.text,
    status: llmSupported && problems.length === 0 ? 'supported' : 'unsupported',
    supported_by: support.map((m) => m.id),
    metadata,
    overlap: check.overlap,
    problems,
  };
}

export interface VerifyOptions {
  /** Članak; ili `videoId` (članak formata vijest te epizode). */
  articleId?: number;
  videoId?: string;
}

export interface VerifyReport {
  articleId: number;
  runId: number;
  baseVersion: number;
  saved: SavedVersion;
  result: VerifyResult;
}

export async function resolveArticleId(db: SqlDb, opts: VerifyOptions): Promise<number> {
  if (opts.articleId !== undefined) return opts.articleId;
  if (opts.videoId === undefined) throw new Error('verify traži članak ili video');
  const id = await findArticleId(db, opts.videoId);
  if (id === null) throw new Error(`epizoda ${opts.videoId} nema članak (prvo \`vijesti write\`)`);
  return id;
}

export async function runVerify(deps: VerifyDeps, opts: VerifyOptions): Promise<VerifyReport> {
  const articleId = await resolveArticleId(deps.db, opts);
  const base = await loadLatestVersion(deps.db, articleId);
  if (!base) throw new Error(`članak ${String(articleId)} nema verzija`);
  if (!base.content) throw new Error(`verzija ${String(base.version)} članka ${String(articleId)} nema strukturirani sadržaj`);
  const sources = base.sources;
  const byPosition = new Map(sources.map((m) => [m.position, m]));
  const byId = new Map(sources.map((m) => [m.id, m]));

  const cleaned = cleanContent(base.content, sources);
  const content = cleaned.content;
  const sentences = articleSentences(content);
  const prompt = buildVerifyPrompt({ episode: content.episode, moments: sources, sentences });

  const runId = await deps.recorder.startRun({
    step: 'verify',
    model: deps.llm.model,
    videoId: content.episode.videoId,
    promptVersion: PROMPT_VERSION,
  });
  try {
    const out = await deps.llm.generate({
      prompt,
      system: SYSTEM_PROMPT,
      schema: VerifyOutputSchema,
      runId,
      name: PROMPT_NAME,
      temperature: 0,
    });
    const verdicts = matchVerdicts(out.sentences, sentences.length);
    const results = sentences.map((s) =>
      judgeSentence(s, verdicts.get(s.n), content, byPosition, s.part === 'title' ? cleaned.titleProblems : []),
    );
    const wordCount = articleWordCount(content, byId);
    const corpus = [metaText(content.episode), ...sources.map((m) => m.quote)].join('\n');
    const style = sentences.flatMap((s) =>
      styleIssues(s.text, { title: s.part === 'title', corpus }).map((i) => ({ ...i, part: s.part, block: s.block })),
    );
    const supported = results.filter((r) => r.status === 'supported').length;
    const result: VerifyResult = {
      version: VERIFY_VERSION,
      base_version: base.version,
      run_id: runId,
      rules: { min_lexical_overlap: MIN_LEXICAL_OVERLAP, stem_len: STEM_LEN },
      word_count: wordCount,
      word_range: {
        min: WORD_RANGE.min,
        max: WORD_RANGE.max,
        ok: wordCount >= WORD_RANGE.min && wordCount <= WORD_RANGE.max,
      },
      sentences: results,
      removed: cleaned.removed,
      style,
      summary: {
        sentences: results.length,
        supported,
        unsupported: results.length - supported,
        removed: cleaned.removed.length,
        style: style.length,
      },
    };
    const saved = await saveArticleVersion(deps.db, {
      videoId: content.episode.videoId,
      title: content.title,
      lead: content.lead,
      body: renderBody(content.blocks, byId),
      category: content.category,
      content,
      wordCount,
      promptVersion: VERIFY_VERSION,
      runId,
      createdBy: VERIFY_CREATED_BY,
      sources: sources.map((m) => ({ momentId: m.id, position: m.position })),
      verify: result,
    });
    await deps.recorder.finishRun(runId, { status: 'ok' });
    return { articleId, runId, baseVersion: base.version, saved, result };
  } catch (e) {
    await deps.recorder.finishRun(runId, { status: 'failed', error: (e as Error).message });
    throw e;
  }
}

export function formatVerifyReport(r: VerifyReport): string {
  const s = r.result.summary;
  const lines = [
    `članak=${String(r.articleId)}  verzija ${String(r.baseVersion)} → ${String(r.saved.version)}  run=${String(r.runId)}  ${r.result.version}`,
    `  rečenica=${String(s.sentences)}  podržanih=${String(s.supported)}  nepodržanih=${String(s.unsupported)}  uklonjeno=${String(s.removed)}  stil=${String(s.style)}` +
      `  riječi=${String(r.result.word_count)}${r.result.word_range.ok ? '' : ` (izvan ${String(WORD_RANGE.min)}–${String(WORD_RANGE.max)})`}`,
  ];
  for (const x of r.result.removed) lines.push(`  UKLONJENO ${x.code}: ${x.text}`);
  for (const x of r.result.sentences.filter((y) => y.status === 'unsupported')) {
    lines.push(`  s${String(x.n)} ${x.problems.map((p) => p.code).join(',')}: ${x.text}`);
  }
  return lines.join('\n');
}

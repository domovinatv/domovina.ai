// `vijesti write`: trenuci epizode s ocjenom ≥ praga → jedan poziv modela →
// strukturirani članak s citatima kao referencama → nova verzija u bazi
// (odluke 413–421). Epizoda bez trenutka iznad praga nema članak ni poziv.
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import { findChannel } from '../score/context.js';
import { NEWS_SCORE_THRESHOLD } from '../score/formula.js';
import {
  articleWordCount,
  CONTENT_SCHEMA,
  renderBody,
  type ArticleContent,
  type ContentBlock,
  type EpisodeMeta,
  type SourceMoment,
} from './content.js';
import {
  buildWritePrompt,
  MAX_WRITE_MOMENTS,
  PROMPT_NAME,
  PROMPT_VERSION,
  SYSTEM_PROMPT,
  WORD_RANGE,
  WriteOutputSchema,
  type WriteOutput,
} from './prompt.js';
import { loadEligibleMoments, saveArticleVersion, type SavedVersion } from './store.js';

export const WRITE_CREATED_BY = 'engine:write';

export interface WriteDeps {
  cdn: CdnClient;
  llm: LlmClient;
  recorder: RunRecorder;
  db: SqlDb;
}

export interface WriteOptions {
  videoId: string;
  channel?: string | undefined;
}

export interface PreparedWrite {
  videoId: string;
  episode: EpisodeMeta;
  /** Izvor članka, redom snimke; `position` = broj iza „t” u promptu. */
  moments: SourceMoment[];
  /** Trenutaka ≥ praga prije ograde `MAX_WRITE_MOMENTS`. */
  eligible: number;
  /** null: nijedan trenutak nije iznad praga, nema poziva ni članka. */
  prompt: string | null;
  system: string;
}

/** Sve do poziva modela, bez poziva (i za procjenu u `npm run eval`). */
export async function prepareWrite(deps: Pick<WriteDeps, 'cdn' | 'db'>, opts: WriteOptions): Promise<PreparedWrite> {
  const all = await loadEligibleMoments(deps.db, opts.videoId, NEWS_SCORE_THRESHOLD);
  const moments = all
    .slice(0, MAX_WRITE_MOMENTS)
    .sort((a, b) => a.startMs - b.startMs || a.id - b.id)
    .map((m, i) => ({ ...m, position: i + 1 }));
  const [info, summary] = await Promise.all([deps.cdn.info(opts.videoId), deps.cdn.summary(opts.videoId)]);
  const ch = await findChannel(deps.cdn, opts.videoId, opts.channel);
  const listed = ch?.listing.videos.find((v) => v.id === opts.videoId);
  const episode: EpisodeMeta = {
    videoId: opts.videoId,
    title: info?.title ?? summary?.summary.title_hr ?? summary?.source.title ?? listed?.title ?? null,
    channel: ch?.slug ?? null,
    channelName: ch?.listing.name ?? null,
    date: listed?.date ?? summary?.source.upload_date ?? null,
    lang: moments[0]?.quoteLang ?? 'hr',
    speakers: (summary?.summary.speakers ?? []).map((s) => ({
      label: s.id,
      name: s.suggested_name?.trim() || null,
      role: s.role?.trim() || null,
    })),
  };
  const prompt =
    moments.length === 0
      ? null
      : buildWritePrompt({
          title: episode.title,
          channelName: episode.channelName,
          date: episode.date,
          lang: episode.lang,
          speakers: episode.speakers.filter((s) => moments.some((m) => m.speaker === s.label)),
          moments: moments.map((m) => ({
            n: m.position,
            speaker: m.speaker,
            speakerName: m.speakerName,
            startMs: m.startMs,
            score: m.score ?? 0,
            quote: m.quote,
            quoteLang: m.quoteLang,
            claim: m.claim,
            entities: m.entities,
          })),
        });
  return { videoId: opts.videoId, episode, moments, eligible: all.length, prompt, system: SYSTEM_PROMPT };
}

/** Blokovi modela → sadržaj: `quote N` postaje `moment_id` (NULL kad tN ne postoji, odluka 422). */
export function toContent(out: WriteOutput, prep: Pick<PreparedWrite, 'episode' | 'moments'>): ArticleContent {
  const byN = new Map(prep.moments.map((m) => [m.position, m]));
  const blocks: ContentBlock[] = out.body.map((b) =>
    b.type === 'p'
      ? { type: 'p', text: b.text.trim() }
      : { type: 'quote', moment_id: byN.get(b.moment)?.id ?? null, ref: `t${String(b.moment)}` },
  );
  return {
    schema: CONTENT_SCHEMA,
    episode: prep.episode,
    title: out.title.trim(),
    lead: out.lead.trim(),
    category: out.category,
    blocks,
  };
}

export interface WriteReport {
  videoId: string;
  /** null: nema trenutka iznad praga (nema poziva). */
  runId: number | null;
  calls: number;
  eligible: number;
  moments: number;
  threshold: number;
  saved: SavedVersion | null;
  title: string | null;
  category: string | null;
  wordCount: number | null;
  /** Broj riječi izvan V10 (300–500): članak je spremljen, verify ga označi. */
  outOfRange: boolean;
  /** Citati koji upućuju na nepostojeći trenutak (verify ih uklanja). */
  missingRefs: string[];
}

export async function runWrite(deps: WriteDeps, opts: WriteOptions): Promise<WriteReport> {
  const prep = await prepareWrite(deps, opts);
  const base = {
    videoId: opts.videoId,
    eligible: prep.eligible,
    moments: prep.moments.length,
    threshold: NEWS_SCORE_THRESHOLD,
  };
  if (prep.prompt === null) {
    return {
      ...base,
      runId: null,
      calls: 0,
      saved: null,
      title: null,
      category: null,
      wordCount: null,
      outOfRange: false,
      missingRefs: [],
    };
  }
  const runId = await deps.recorder.startRun({
    step: 'write',
    model: deps.llm.model,
    videoId: opts.videoId,
    promptVersion: PROMPT_VERSION,
  });
  try {
    const out = await deps.llm.generate({
      prompt: prep.prompt,
      system: prep.system,
      schema: WriteOutputSchema,
      runId,
      name: PROMPT_NAME,
      temperature: 0.3,
    });
    const content = toContent(out, prep);
    const byId = new Map(prep.moments.map((m) => [m.id, m]));
    const wordCount = articleWordCount(content, byId);
    const saved = await saveArticleVersion(deps.db, {
      videoId: opts.videoId,
      title: content.title,
      lead: content.lead,
      body: renderBody(content.blocks, byId),
      category: content.category,
      content,
      wordCount,
      promptVersion: PROMPT_VERSION,
      runId,
      createdBy: WRITE_CREATED_BY,
      sources: prep.moments.map((m) => ({ momentId: m.id, position: m.position })),
    });
    await deps.recorder.finishRun(runId, { status: 'ok' });
    return {
      ...base,
      runId,
      calls: 1,
      saved,
      title: content.title,
      category: content.category,
      wordCount,
      outOfRange: wordCount < WORD_RANGE.min || wordCount > WORD_RANGE.max,
      missingRefs: content.blocks.flatMap((b) => (b.type === 'quote' && b.moment_id === null ? [b.ref] : [])),
    };
  } catch (e) {
    await deps.recorder.finishRun(runId, { status: 'failed', error: (e as Error).message });
    throw e;
  }
}

export function formatWriteReport(r: WriteReport): string {
  if (r.saved === null) {
    return `${r.videoId}  nema članka: nijedan trenutak nije iznad praga ${String(r.threshold)} (prihvaćenih ocijenjenih ≥ praga: 0)`;
  }
  return [
    `${r.videoId}  članak=${String(r.saved.articleId)}  verzija=${String(r.saved.version)}  run=${String(r.runId)}  slug=${r.saved.slug}`,
    `  trenutaka ≥ praga=${String(r.eligible)}  u promptu=${String(r.moments)}  kategorija=${r.category ?? '-'}` +
      `  riječi=${String(r.wordCount)}${r.outOfRange ? ` (izvan ${String(WORD_RANGE.min)}–${String(WORD_RANGE.max)})` : ''}`,
    `  naslov: ${r.title ?? ''}`,
    ...(r.missingRefs.length > 0 ? [`  citati bez trenutka: ${r.missingRefs.join(', ')} (verify ih uklanja)`] : []),
    `  dalje: npm run vijesti -- verify ${String(r.saved.articleId)}`,
  ].join('\n');
}

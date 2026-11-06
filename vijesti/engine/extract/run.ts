// `vijesti extract`: jezik snimke → titl → sekcije → model → provjera
// citata → baza. Svaki poziv modela ide u jedan `runs` zapis.
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient, LoadedEpisode } from '../cdn/loader.js';
import type { RunRecorder } from '../llm/runs.js';
import { LlmSchemaError, LlmTimeoutError, type LlmClient } from '../llm/types.js';
import { verifyQuote, type QuoteCheck, type VerifyOptions } from '../verify/quote.js';
import { assertTextLang, decideQuoteLang, QuoteLangError, type LangSource } from './lang.js';
import {
  buildExtractPrompt,
  ExtractOutputSchema,
  PROMPT_NAME,
  PROMPT_VERSION,
  SYSTEM_PROMPT,
} from './prompt.js';
import { splitSections, type TranscriptSection } from './sections.js';
import { saveMoments, type MomentRow } from './store.js';

export interface ExtractDeps {
  cdn: CdnClient;
  llm: LlmClient;
  recorder: RunRecorder;
  db: SqlDb;
}

/**
 * Toliko timeouta ZA REDOM prekida izvlačenje (odluka 406): jedan je vjerojatno
 * odbijen upit za tu sekciju, dva znače da agy ne odgovara i daljnje čekanje
 * (do 10 min po sekciji) ništa ne donosi.
 */
export const MAX_CONSECUTIVE_TIMEOUTS = 2;

export interface ExtractOptions {
  videoId: string;
  /** `--lang`. */
  lang?: string | undefined;
  /** Jezik kanala iz popisa dopuštenih, kad ga bude (odluka 200). */
  channelLang?: string | null | undefined;
  verify?: VerifyOptions;
}

export interface ExtractReport {
  videoId: string;
  runId: number;
  lang: string;
  langSource: LangSource;
  srtFile: string | null;
  wordsFile: string | null;
  sections: number;
  calls: number;
  /** Sekcije za koje izlaz modela nije prošao shemu (trenuci iz njih ne postoje). */
  failedSections: number;
  moments: number;
  byCheck: Record<QuoteCheck, number>;
  reasons: Record<string, number>;
  inserted: number;
  deleted: number;
  skipped: number;
}

export interface PreparedExtract {
  videoId: string;
  lang: string;
  langSource: LangSource;
  episode: LoadedEpisode;
  sections: TranscriptSection[];
  /** Jedan prompt po sekciji, redom (bez poziva modela; i za procjenu u `npm run eval`). */
  prompts: { section: TranscriptSection; prompt: string }[];
  system: string;
}

/** Jezik, titl, sekcije i promptovi, bez poziva modela i bez zapisa u bazu. */
export async function prepareExtract(
  cdn: CdnClient,
  opts: Pick<ExtractOptions, 'videoId' | 'lang' | 'channelLang'>,
): Promise<PreparedExtract> {
  const { videoId } = opts;
  const bundle = await cdn.bundle(videoId);
  const decision = decideQuoteLang({ bundle, explicit: opts.lang, channelLang: opts.channelLang });
  const ep = await cdn.loadEpisode(videoId, { lang: decision.lang });
  if (!ep.srt || ep.cues.length === 0) {
    throw new QuoteLangError(`epizoda ${videoId} nema titl (${ep.srtFile ?? 'diarized.srt'})`);
  }
  // Prije ijednog poziva: tekst titla mora biti na jeziku snimke.
  assertTextLang(ep.cues.map((c) => c.text).join(' '), decision.lang);
  const sections = splitSections(ep.cues, ep.article);
  const title = ep.info?.title ?? ep.summary?.source.title ?? null;
  return {
    videoId,
    lang: decision.lang,
    langSource: decision.source,
    episode: ep,
    sections,
    prompts: sections.map((section) => ({
      section,
      prompt: buildExtractPrompt({ cues: ep.cues, section, lang: decision.lang, title }),
    })),
    system: SYSTEM_PROMPT,
  };
}

export async function runExtract(deps: ExtractDeps, opts: ExtractOptions): Promise<ExtractReport> {
  const { cdn, llm, recorder, db } = deps;
  const { videoId } = opts;
  const prep = await prepareExtract(cdn, opts);
  const ep = prep.episode;
  const decision = { lang: prep.lang, source: prep.langSource };
  const sections = prep.sections;
  const runId = await recorder.startRun({
    step: 'extract',
    model: llm.model,
    videoId,
    promptVersion: PROMPT_VERSION,
  });
  const rows: MomentRow[] = [];
  let calls = 0;
  let failedSections = 0;
  let timeoutsInRow = 0;
  try {
    for (const { section, prompt } of prep.prompts) {
      calls++;
      let out;
      try {
        out = await llm.generate({
          prompt,
          system: prep.system,
          schema: ExtractOutputSchema,
          runId,
          name: PROMPT_NAME,
          temperature: 0,
        });
      } catch (e) {
        if (e instanceof LlmSchemaError) {
          failedSections++;
          timeoutsInRow = 0;
          continue;
        }
        if (e instanceof LlmTimeoutError && ++timeoutsInRow < MAX_CONSECUTIVE_TIMEOUTS) {
          failedSections++;
          continue;
        }
        throw e;
      }
      timeoutsInRow = 0;
      for (const m of out.moments) {
        const v = verifyQuote(
          ep.cues,
          { cueFrom: m.cue_from, cueTo: m.cue_to, speaker: m.speaker, quote: m.quote },
          opts.verify,
        );
        const base = {
          videoId,
          speaker: m.speaker,
          quote: m.quote,
          quoteLang: decision.lang,
          claim: m.claim,
          topics: m.topics,
          entities: m.entities,
          cueFrom: m.cue_from,
          cueTo: m.cue_to,
          runId,
        };
        if (v.check === 'failed') {
          // Nevaljane reference: raspon sekcije u kojoj je model odgovarao.
          const range = v.range ?? { startMs: section.startMs, endMs: section.endMs };
          rows.push({ ...base, ...range, quoteCheck: 'failed', quoteMatch: null, rejectReason: v.reason });
        } else {
          rows.push({
            ...base,
            startMs: v.span.startMs,
            endMs: v.span.endMs,
            quoteCheck: v.check,
            quoteMatch: v.match,
            rejectReason: null,
          });
        }
      }
    }
    const saved = await saveMoments(db, videoId, rows);
    await recorder.finishRun(
      runId,
      failedSections > 0
        ? { status: 'failed', error: `${String(failedSections)} sekcija bez valjanog izlaza` }
        : { status: 'ok' },
    );
    const byCheck: Record<QuoteCheck, number> = { exact: 0, fuzzy: 0, srt_only: 0, failed: 0 };
    const reasons: Record<string, number> = {};
    for (const r of rows) {
      byCheck[r.quoteCheck]++;
      if (r.rejectReason) reasons[r.rejectReason] = (reasons[r.rejectReason] ?? 0) + 1;
    }
    return {
      videoId,
      runId,
      lang: decision.lang,
      langSource: decision.source,
      srtFile: ep.srtFile,
      wordsFile: ep.wordsFile,
      sections: sections.length,
      calls,
      failedSections,
      moments: rows.length,
      byCheck,
      reasons,
      ...saved,
    };
  } catch (e) {
    await recorder.finishRun(runId, { status: 'failed', error: (e as Error).message });
    throw e;
  }
}

export function formatReport(r: ExtractReport): string {
  const reasons = Object.entries(r.reasons)
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([k, n]) => `${k}=${String(n)}`)
    .join(' ');
  return [
    `${r.videoId}  run=${String(r.runId)}  jezik=${r.lang} (${r.langSource})  srt=${r.srtFile ?? '-'}  words=${r.wordsFile ?? '-'}`,
    `  sekcija=${String(r.sections)}  poziva=${String(r.calls)}  neuspjelih=${String(r.failedSections)}  trenutaka=${String(r.moments)}`,
    `  exact=${String(r.byCheck.exact)} fuzzy=${String(r.byCheck.fuzzy)} srt_only=${String(r.byCheck.srt_only)} failed=${String(r.byCheck.failed)}` +
      (reasons ? `  razlozi: ${reasons}` : ''),
    `  baza: upisano=${String(r.inserted)} obrisano=${String(r.deleted)} preskočeno=${String(r.skipped)}`,
  ].join('\n');
}

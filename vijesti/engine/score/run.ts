// `vijesti score`: prihvaćeni trenuci epizode → kontekst kanala → jedan poziv
// modela → deterministička formula → baza (odluke 306–314).
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import { buildNoveltyContext, findChannel, type NoveltyContext } from './context.js';
import { concreteFeatures } from './features.js';
import { combineScore, SCORE_VERSION, type CatalogPerson } from './formula.js';
import type { PersonIndex, PersonMatch } from './persons.js';
import {
  buildScorePrompt,
  PROMPT_NAME,
  PROMPT_VERSION,
  ScoreOutputSchema,
  SYSTEM_PROMPT,
  type MomentScore,
  type ScoreMomentInput,
  type ScoreSpeaker,
} from './prompt.js';
import { loadAcceptedMoments, saveScores, type ScoreRow, type StoredMoment } from './store.js';

export interface ScoreDeps {
  cdn: CdnClient;
  llm: LlmClient;
  recorder: RunRecorder;
  db: SqlDb;
  persons: PersonIndex;
}

export interface ScoreOptions {
  videoId: string;
  /** Slug kanala ako je poznat (eval); inače se traži po listinzima. */
  channel?: string | undefined;
  priorEpisodes?: number;
  priorMoments?: number;
}

export interface SpeakerInfo {
  label: string;
  name: string | null;
  role: string | null;
  match: PersonMatch;
  person: CatalogPerson | null;
}

export interface PreparedScore {
  videoId: string;
  channel: string | null;
  moments: StoredMoment[];
  speakers: Map<string, SpeakerInfo>;
  context: NoveltyContext;
  /** `null` kad epizoda nema prihvaćenih trenutaka (nema poziva). */
  prompt: string | null;
  system: string;
}

/** Model je naveo trenutak koji ne postoji ili isti dvaput: izlaz se odbija cijeli. */
export class ScoreMismatchError extends Error {
  constructor(
    message: string,
    readonly unknown: number[],
    readonly duplicate: number[],
  ) {
    super(message);
    this.name = 'ScoreMismatchError';
  }
}

/** Sve do poziva modela, bez poziva (i za procjenu tokena u `npm run eval`). */
export async function prepareScore(
  deps: Pick<ScoreDeps, 'cdn' | 'db' | 'persons'>,
  opts: ScoreOptions,
): Promise<PreparedScore> {
  const { cdn, db, persons } = deps;
  const moments = await loadAcceptedMoments(db, opts.videoId);
  const summary = await cdn.summary(opts.videoId);
  const info = await cdn.info(opts.videoId);
  const ch = await findChannel(cdn, opts.videoId, opts.channel);
  const context = await buildNoveltyContext(
    { cdn, db },
    {
      videoId: opts.videoId,
      listing: ch?.listing ?? null,
      ...(opts.priorEpisodes !== undefined && { priorEpisodes: opts.priorEpisodes }),
      ...(opts.priorMoments !== undefined && { priorMoments: opts.priorMoments }),
    },
  );

  const speakers = new Map<string, SpeakerInfo>();
  const declared = new Map((summary?.summary.speakers ?? []).map((s) => [s.id, s]));
  for (const label of [...new Set(moments.map((m) => m.speaker))].sort()) {
    const s = declared.get(label);
    const name = s?.suggested_name?.trim() || null;
    const match = persons.match(name);
    speakers.set(label, {
      label,
      name,
      role: s?.role?.trim() || null,
      match,
      person: match.matched
        ? {
            slug: match.person.slug,
            name: match.person.name,
            episodes: match.person.episode_count,
            channels: match.person.channel_count,
          }
        : null,
    });
  }

  const inputs: ScoreMomentInput[] = moments.map((m, i) => ({
    n: i + 1,
    speaker: m.speaker,
    startMs: m.startMs,
    quote: m.quote,
    claim: m.claim,
    entities: m.entities,
  }));
  const promptSpeakers: ScoreSpeaker[] = [...speakers.values()].map((s) => ({
    label: s.label,
    name: s.name,
    role: s.role,
    person: s.person ? { name: s.person.name, episodes: s.person.episodes, channels: s.person.channels } : null,
  }));
  const prompt =
    moments.length === 0
      ? null
      : buildScorePrompt({
          title: info?.title ?? summary?.summary.title_hr ?? summary?.source.title ?? null,
          date: context.date ?? summary?.source.upload_date ?? null,
          channel: ch?.listing.name ?? null,
          speakers: promptSpeakers,
          prior: context.prior,
          priorMoments: context.priorMoments,
          moments: inputs,
        });
  return { videoId: opts.videoId, channel: ch?.slug ?? null, moments, speakers, context, prompt, system: SYSTEM_PROMPT };
}

/** Uparuje izlaz s trenucima po broju. Nepoznat ili ponovljen broj baca; izostavljeni se vraćaju. */
export function matchScores(
  scores: readonly MomentScore[],
  count: number,
): { byN: Map<number, MomentScore>; missing: number[] } {
  const byN = new Map<number, MomentScore>();
  const unknown: number[] = [];
  const duplicate: number[] = [];
  for (const s of scores) {
    if (s.id < 1 || s.id > count) unknown.push(s.id);
    else if (byN.has(s.id)) duplicate.push(s.id);
    else byN.set(s.id, s);
  }
  if (unknown.length > 0 || duplicate.length > 0) {
    const parts = [
      ...(unknown.length > 0 ? [`nepostojeći ${unknown.map((n) => `t${String(n)}`).join(',')}`] : []),
      ...(duplicate.length > 0 ? [`ponovljeni ${duplicate.map((n) => `t${String(n)}`).join(',')}`] : []),
    ];
    throw new ScoreMismatchError(`izlaz modela ne odgovara trenucima: ${parts.join('; ')}`, unknown, duplicate);
  }
  const missing: number[] = [];
  for (let n = 1; n <= count; n++) if (!byN.has(n)) missing.push(n);
  return { byN, missing };
}

export interface ScoredMoment {
  n: number;
  momentId: number;
  startMs: number;
  speaker: string;
  speakerName: string | null;
  quote: string;
  score: number;
}

export interface ScoreReport {
  videoId: string;
  channel: string | null;
  /** `null` kad nije bilo poziva (nema prihvaćenih trenutaka). */
  runId: number | null;
  calls: number;
  moments: number;
  scored: number;
  /** Brojevi trenutaka (t1…) koje je model izostavio; ostaju bez ocjene. */
  missing: number[];
  cleared: number;
  priorEpisodes: number;
  priorMoments: number;
  speakersMatched: number;
  speakers: number;
  version: string;
  /** Po ocjeni silazno. */
  ranked: ScoredMoment[];
}

export async function runScore(deps: ScoreDeps, opts: ScoreOptions): Promise<ScoreReport> {
  const prep = await prepareScore(deps, opts);
  const base = {
    videoId: opts.videoId,
    channel: prep.channel,
    moments: prep.moments.length,
    priorEpisodes: prep.context.prior.length,
    priorMoments: prep.context.priorMoments.length,
    speakersMatched: [...prep.speakers.values()].filter((s) => s.person).length,
    speakers: prep.speakers.size,
    version: SCORE_VERSION,
  };
  if (prep.prompt === null) {
    return { ...base, runId: null, calls: 0, scored: 0, missing: [], cleared: 0, ranked: [] };
  }

  const runId = await deps.recorder.startRun({
    step: 'score',
    model: deps.llm.model,
    videoId: opts.videoId,
    promptVersion: PROMPT_VERSION,
  });
  try {
    const out = await deps.llm.generate({
      prompt: prep.prompt,
      system: prep.system,
      schema: ScoreOutputSchema,
      runId,
      name: PROMPT_NAME,
      temperature: 0,
    });
    const { byN, missing } = matchScores(out.scores, prep.moments.length);
    const rows: ScoreRow[] = [];
    const ranked: ScoredMoment[] = [];
    prep.moments.forEach((m, i) => {
      const s = byN.get(i + 1);
      if (!s) return;
      const sp = prep.speakers.get(m.speaker);
      const { score, parts } = combineScore(
        s,
        concreteFeatures(m.quote, m.entities),
        sp?.person ?? null,
        sp?.name ?? null,
      );
      rows.push({ momentId: m.id, score, parts, reasons: s.reasons, speakerName: sp?.name ?? null });
      ranked.push({
        n: i + 1,
        momentId: m.id,
        startMs: m.startMs,
        speaker: m.speaker,
        speakerName: sp?.name ?? null,
        quote: m.quote,
        score,
      });
    });
    const saved = await saveScores(deps.db, opts.videoId, rows, { version: SCORE_VERSION, runId });
    await deps.recorder.finishRun(
      runId,
      missing.length > 0
        ? {
            status: 'failed',
            error: `${String(missing.length)} trenutaka bez ocjene: ${missing.map((n) => `t${String(n)}`).join(',')}`,
          }
        : { status: 'ok' },
    );
    ranked.sort((a, b) => b.score - a.score || a.startMs - b.startMs);
    return { ...base, runId, calls: 1, scored: saved.updated, missing, cleared: saved.cleared, ranked };
  } catch (e) {
    await deps.recorder.finishRun(runId, { status: 'failed', error: (e as Error).message });
    throw e;
  }
}

function hms(ms: number): string {
  const s = Math.floor(ms / 1000);
  const p = (n: number) => String(n).padStart(2, '0');
  return `${p(Math.floor(s / 3600))}:${p(Math.floor((s % 3600) / 60))}:${p(s % 60)}`;
}

export function formatScoreReport(r: ScoreReport): string {
  const lines = [
    `${r.videoId}  kanal=${r.channel ?? '-'}  run=${r.runId === null ? '-' : String(r.runId)}  verzija=${r.version}`,
    `  trenutaka=${String(r.moments)}  poziva=${String(r.calls)}  ocijenjeno=${String(r.scored)}` +
      (r.missing.length > 0 ? `  bez ocjene=${r.missing.map((n) => `t${String(n)}`).join(',')}` : ''),
    `  kontekst: ranijih epizoda=${String(r.priorEpisodes)}  ranijih tvrdnji=${String(r.priorMoments)}  govornika u katalogu=${String(r.speakersMatched)}/${String(r.speakers)}`,
  ];
  if (r.moments === 0) lines.push('  nema prihvaćenih trenutaka (prvo `vijesti extract`)');
  for (const m of r.ranked) {
    const q = m.quote.length > 90 ? `${m.quote.slice(0, 90)}…` : m.quote;
    lines.push(
      `  ${m.score.toFixed(3)}  t${String(m.n)} ${hms(m.startMs)} ${m.speakerName ?? m.speaker}: „${q}”  https://domovina.ai/v/${r.videoId}/t/${String(Math.floor(m.startMs / 1000))}`,
    );
  }
  return lines.join('\n');
}

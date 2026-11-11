// `npm run eval`: uzorak → plan (što je već gotovo) → procjena bez poziva →
// izvlačenje, ocjena, članak i provjera epizodu po epizodu (odluke 405–411,
// 434). Nastavlja gdje je stao: gotov korak se preskače, jer agy uzorak
// traje satima. Greška jedne epizode se zapiše i ide se dalje. Napredak se NE
// ispisuje po pozivu (globalno pravilo o tokenima): jedan redak po epizodi u
// log datoteku i završni sažetak.
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import { prepareExtract, runExtract } from '../extract/run.js';
import { ExtractOutputSchema, PROMPT_VERSION as EXTRACT_VERSION } from '../extract/prompt.js';
import { DEFAULT_GEMINI_MODEL, defaultPricing } from '../llm/config.js';
import { estimateTokens } from '../llm/estimate.js';
import { toGeminiSchema } from '../llm/gemini.js';
import type { RunRecorder } from '../llm/runs.js';
import { costUsd, type GenerateRequest, type LlmClient, type LlmPricing } from '../llm/types.js';
import type { z } from 'zod';
import { SCORE_VERSION } from '../score/formula.js';
import type { PersonIndex } from '../score/persons.js';
import {
  PROMPT_VERSION as SCORE_PROMPT_VERSION,
  ScoreOutputSchema,
  SYSTEM_PROMPT as SCORE_SYSTEM,
} from '../score/prompt.js';
import { prepareScore, runScore } from '../score/run.js';
import { runVerify } from '../verify/article.js';
import {
  PROMPT_VERSION as VERIFY_PROMPT_VERSION,
  SYSTEM_PROMPT as VERIFY_SYSTEM,
  VerifyOutputSchema,
} from '../verify/article-prompt.js';
import { loadEligibleMoments } from '../write/store.js';
import {
  MAX_WRITE_MOMENTS,
  PROMPT_VERSION as WRITE_PROMPT_VERSION,
  SYSTEM_PROMPT as WRITE_SYSTEM,
  WriteOutputSchema,
} from '../write/prompt.js';
import { prepareWrite, runWrite } from '../write/vijest.js';
import { NEWS_SCORE_THRESHOLD } from '../score/formula.js';
import {
  loadChannelSample,
  processingOrder,
  sampleChannel,
  saveChannelSample,
  type ChannelSample,
  type SampledEpisode,
  type SampleRejection,
} from './sample.js';

export type EvalBackend = 'agy' | 'claude' | 'vertex' | 'studio' | 'fake';

/** Pretpostavljeno trajanje poziva za procjenu (odluka 408). agy: 23–124 s izmjereno u pipelineu 28.10. */
export const SECONDS_PER_CALL: Record<EvalBackend, number> = { agy: 60, claude: 30, vertex: 15, studio: 15, fake: 0 };

/**
 * Pretpostavke procjene koje nisu u promptu (odluka 408). Izlaz uključuje
 * „thinking”; broj trenutaka po sekciji i veličina ocjene vrijede samo za
 * epizode koje još nisu izvučene (za izvučene se gradi pravi prompt ocjene).
 */
export const ESTIMATE = {
  extractOutTokens: 2000,
  scoreOutTokens: 3000,
  momentsPerSection: 2,
  scoreTokensPerMoment: 120,
  scoreBaseTokens: 1500,
  /** Članak (odluka 434): podaci o epizodi i uputa bez trenutaka, pa po trenutku u promptu. */
  writeBaseTokens: 800,
  writeTokensPerMoment: 150,
  writeOutTokens: 2500,
  /** Provjera: isti trenuci uz ~500 riječi članka po rečenicama. */
  verifyArticleTokens: 1300,
  verifyOutTokens: 2000,
} as const;

/** Izlazni kod kad je procjena ili potrošnja iznad `--max-calls`. */
export const EXIT_OVER_BUDGET = 3;

export interface EvalOptions {
  channels: string[];
  /** Epizoda po kanalu. */
  limit: number;
  /** null: bez ograde (samo `--fake` ili `--dry-run`). */
  maxCalls: number | null;
  dryRun: boolean;
  /** Neuspjelih runova za korak prije odustajanja (zadano 2). */
  attempts: number;
  /** Novi uzorak umjesto spremljenog. */
  resample: boolean;
  now: Date;
}

export interface EvalDeps {
  cdn: CdnClient;
  db: SqlDb;
  recorder: RunRecorder;
  persons: PersonIndex;
  /** Stvara se tek kad treba zvati model (suhi prolaz ga ne stvara). */
  llm: () => LlmClient;
  backend: EvalBackend;
  pricing: LlmPricing | null;
  /** Jedan redak po obrađenoj epizodi (log datoteka). */
  log?: (line: string) => Promise<void>;
  clock?: () => number;
}

/** `none`: korak nema posla (epizoda bez trenutka ≥ praga nema članak, odluka 414). */
export type StepState = 'done' | 'todo' | 'gave_up' | 'none';

export interface EpisodePlan {
  ep: SampledEpisode;
  extract: StepState;
  score: StepState;
  write: StepState;
  verify: StepState;
  calls: number;
  tokensIn: number;
  tokensOut: number;
  /** Epizoda se ne može pokrenuti (nema titla, krivi jezik…). */
  error: string | null;
}

export interface EvalEstimate {
  episodes: number;
  done: number;
  todo: number;
  gaveUp: number;
  unrunnable: number;
  calls: number;
  tokensIn: number;
  tokensOut: number;
  seconds: number;
  costUsd: number | null;
  /** Isti tokeni po zadanom Vertex cjeniku (odluka 304): koliko bi koštalo bez pretplate. */
  apiEquivalentUsd: number | null;
}

export interface EpisodeOutcome {
  videoId: string;
  channel: string;
  extract: string;
  score: string;
  write: string;
  verify: string;
  calls: number;
  error: string | null;
}

export interface EvalResult {
  exitCode: 0 | typeof EXIT_OVER_BUDGET;
  plans: EpisodePlan[];
  rejected: SampleRejection[];
  estimate: EvalEstimate;
  outcomes: EpisodeOutcome[];
  callsMade: number;
  stoppedByBudget: boolean;
  /** Procjena i (ako se radilo) završni sažetak, za ispis. */
  text: string;
}

export class BudgetExceededError extends Error {
  constructor(max: number) {
    super(`dosegnut --max-calls ${String(max)}`);
    this.name = 'BudgetExceededError';
  }
}

/** Tvrda ograda: poziv preko `max` se ne šalje. */
export function budgetedLlm(llm: LlmClient, max: number | null): LlmClient & { readonly used: number } {
  let used = 0;
  return {
    model: llm.model,
    get used() {
      return used;
    },
    generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      if (max !== null && used >= max) return Promise.reject(new BudgetExceededError(max));
      used++;
      return llm.generate(req);
    },
  };
}

interface StatusRow {
  id: number | string;
  status: string;
}

/**
 * Zadnji run koraka je `ok` → done; inače broj neuspjelih zaredom od zadnjeg
 * uspjeha. `afterId`: samo runovi noviji od njega (provjera nakon zadnjeg članka).
 */
async function stepHistory(db: SqlDb, step: string, videoId: string, version: string, afterId = 0) {
  const res = await db.query<StatusRow>(
    `SELECT id, status FROM vijesti.runs
     WHERE step = $1 AND video_id = $2 AND prompt_version = $3 AND id > $4 ORDER BY id DESC`,
    [step, videoId, version, afterId],
  );
  const ok = res.rows[0]?.status === 'ok';
  const lastOkId = Number(res.rows.find((r) => r.status === 'ok')?.id ?? 0);
  let failures = 0;
  for (const r of res.rows) {
    if (r.status === 'ok') break;
    failures++;
  }
  return { ok, failures, lastOkId };
}

async function pendingScores(db: SqlDb, videoId: string): Promise<number> {
  const res = await db.query<{ n: number | string }>(
    `SELECT count(*) AS n FROM vijesti.moments
     WHERE video_id = $1 AND quote_check <> 'failed' AND score_version IS DISTINCT FROM $2`,
    [videoId, SCORE_VERSION],
  );
  return Number(res.rows[0]?.n ?? 0);
}

type Steps = Pick<EpisodePlan, 'extract' | 'score' | 'write' | 'verify'>;

const state = (h: { ok: boolean; failures: number }, attempts: number): StepState =>
  h.ok ? 'done' : h.failures >= attempts ? 'gave_up' : 'todo';

/**
 * Stanje četiri koraka (odluke 407, 434). Korak koji čeka prethodni nasljeđuje
 * njegovo stanje (`todo` ili `gave_up`). Članak je gotov kad je zadnji `write`
 * run trenutne verzije `ok`; provjera kad je `ok` zadnji `verify` run NOVIJI od
 * tog članka. Bez trenutka ≥ praga članka nema (`none`).
 */
export async function stepStates(db: SqlDb, videoId: string, attempts: number): Promise<Steps> {
  const ex = await stepHistory(db, 'extract', videoId, EXTRACT_VERSION);
  const extract = state(ex, attempts);
  if (extract !== 'done') return { extract, score: extract, write: extract, verify: extract };
  if ((await pendingScores(db, videoId)) > 0) {
    const sc = await stepHistory(db, 'score', videoId, SCORE_PROMPT_VERSION);
    const score: StepState = sc.failures >= attempts ? 'gave_up' : 'todo';
    return { extract, score, write: score, verify: score };
  }
  if ((await loadEligibleMoments(db, videoId, NEWS_SCORE_THRESHOLD)).length === 0) {
    return { extract, score: 'done', write: 'none', verify: 'none' };
  }
  const wr = await stepHistory(db, 'write', videoId, WRITE_PROMPT_VERSION);
  const write = state(wr, attempts);
  if (write !== 'done') return { extract, score: 'done', write, verify: write };
  const vr = await stepHistory(db, 'verify', videoId, VERIFY_PROMPT_VERSION, wr.lastOkId);
  return { extract, score: 'done', write, verify: state(vr, attempts) };
}

const schemaTokens = (s: z.ZodType) => estimateTokens(JSON.stringify(toGeminiSchema(s)));

async function planEpisode(deps: EvalDeps, ep: SampledEpisode, attempts: number): Promise<EpisodePlan> {
  const st = await stepStates(deps.db, ep.videoId, attempts);
  const plan: EpisodePlan = { ep, ...st, calls: 0, tokensIn: 0, tokensOut: 0, error: null };
  // Trenutaka u promptu članka i provjere; dok ocjena nije gotova, gornja granica.
  let writeMoments: number = MAX_WRITE_MOMENTS;
  try {
    let sections = 0;
    if (st.extract === 'todo') {
      const prep = await prepareExtract(deps.cdn, { videoId: ep.videoId });
      sections = prep.prompts.length;
      const perCall = estimateTokens(prep.system) + schemaTokens(ExtractOutputSchema);
      plan.calls += sections;
      plan.tokensIn += prep.prompts.reduce((n, p) => n + estimateTokens(p.prompt) + perCall, 0);
      plan.tokensOut += sections * ESTIMATE.extractOutTokens;
    }
    if (st.score === 'todo') {
      let tokensIn: number;
      if (st.extract === 'done') {
        const prep = await prepareScore(
          { cdn: deps.cdn, db: deps.db, persons: deps.persons },
          { videoId: ep.videoId, channel: ep.channel },
        );
        tokensIn = prep.prompt === null ? 0 : estimateTokens(prep.prompt) + estimateTokens(prep.system);
      } else {
        tokensIn =
          estimateTokens(SCORE_SYSTEM) +
          ESTIMATE.scoreBaseTokens +
          sections * ESTIMATE.momentsPerSection * ESTIMATE.scoreTokensPerMoment;
      }
      if (tokensIn > 0) {
        plan.calls += 1;
        plan.tokensIn += tokensIn + schemaTokens(ScoreOutputSchema);
        plan.tokensOut += ESTIMATE.scoreOutTokens;
      }
    }
    if (st.write === 'todo') {
      // Pretpostavka dok ocjena nije gotova: epizoda dobiva članak (gornja granica poziva).
      let tokensIn = estimateTokens(WRITE_SYSTEM) + ESTIMATE.writeBaseTokens + writeMoments * ESTIMATE.writeTokensPerMoment;
      if (st.score === 'done') {
        const prep = await prepareWrite({ cdn: deps.cdn, db: deps.db }, { videoId: ep.videoId, channel: ep.channel });
        writeMoments = prep.moments.length;
        tokensIn = prep.prompt === null ? 0 : estimateTokens(prep.prompt) + estimateTokens(prep.system);
      }
      if (tokensIn > 0) {
        plan.calls += 1;
        plan.tokensIn += tokensIn + schemaTokens(WriteOutputSchema);
        plan.tokensOut += ESTIMATE.writeOutTokens;
      }
    }
    if (st.verify === 'todo') {
      plan.calls += 1;
      plan.tokensIn +=
        estimateTokens(VERIFY_SYSTEM) +
        ESTIMATE.writeBaseTokens +
        writeMoments * ESTIMATE.writeTokensPerMoment +
        ESTIMATE.verifyArticleTokens +
        schemaTokens(VerifyOutputSchema);
      plan.tokensOut += ESTIMATE.verifyOutTokens;
    }
  } catch (e) {
    plan.error = (e as Error).message;
    plan.calls = 0;
    plan.tokensIn = 0;
    plan.tokensOut = 0;
  }
  return plan;
}

function estimateOf(plans: EpisodePlan[], backend: EvalBackend, pricing: LlmPricing | null, now: Date): EvalEstimate {
  const live = plans.filter((p) => p.error === null);
  const steps = (p: EpisodePlan) => [p.extract, p.score, p.write, p.verify];
  const calls = live.reduce((n, p) => n + p.calls, 0);
  const tokensIn = live.reduce((n, p) => n + p.tokensIn, 0);
  const tokensOut = live.reduce((n, p) => n + p.tokensOut, 0);
  const api = defaultPricing('vertex', DEFAULT_GEMINI_MODEL, 'global', now.getTime());
  return {
    episodes: plans.length,
    done: live.filter((p) => steps(p).every((x) => x === 'done' || x === 'none')).length,
    todo: live.filter((p) => steps(p).includes('todo')).length,
    gaveUp: live.filter((p) => steps(p).includes('gave_up')).length,
    unrunnable: plans.length - live.length,
    calls,
    tokensIn,
    tokensOut,
    seconds: calls * SECONDS_PER_CALL[backend],
    costUsd: costUsd({ tokensIn, tokensOut }, pricing),
    apiEquivalentUsd: costUsd({ tokensIn, tokensOut }, api),
  };
}

export function formatDuration(seconds: number): string {
  const s = Math.round(seconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  return h > 0 ? `${String(h)} h ${String(m)} min` : m > 0 ? `${String(m)} min ${String(s % 60)} s` : `${String(s)} s`;
}

const usd = (n: number | null) => (n === null ? 'nepoznato' : `$${n.toFixed(2)}`);

export function formatEstimate(e: EvalEstimate, opts: { backend: EvalBackend; maxCalls: number | null }): string {
  const cost =
    opts.backend === 'agy' || opts.backend === 'claude'
      ? `$0 (pretplata); API-ekvivalent po Vertex cjeniku ${usd(e.apiEquivalentUsd)} (procjena)`
      : opts.backend === 'fake'
        ? `$0 (lažni LLM); API-ekvivalent ${usd(e.apiEquivalentUsd)} (procjena)`
        : `${usd(e.costUsd)} (procjena)`;
  return [
    `Procjena (backend ${opts.backend}, bez poziva modela; tokeni = znakovi / 3, odluka 305):`,
    `  epizoda u uzorku: ${String(e.episodes)}  gotovih: ${String(e.done)}  za obradu: ${String(e.todo)}  odustalih: ${String(e.gaveUp)}  ne mogu se pokrenuti: ${String(e.unrunnable)}`,
    `  poziva: ${String(e.calls)}${opts.maxCalls === null ? '' : ` (--max-calls ${String(opts.maxCalls)})`}`,
    `  tokena: ulaz ~${String(e.tokensIn)}, izlaz ~${String(e.tokensOut)} (pretpostavka izlaza po pozivu: izvlačenje ${String(ESTIMATE.extractOutTokens)}, ocjena ${String(ESTIMATE.scoreOutTokens)}, članak ${String(ESTIMATE.writeOutTokens)}, provjera ${String(ESTIMATE.verifyOutTokens)})`,
    `  trajanje: ~${formatDuration(e.seconds)} (${String(SECONDS_PER_CALL[opts.backend])} s po pozivu, serijski)`,
    `  trošak: ${cost}`,
  ].join('\n');
}

function logLine(o: EpisodeOutcome, at: number): string {
  return [
    new Date(at).toISOString(),
    o.videoId,
    o.channel,
    `extract=${o.extract}`,
    `score=${o.score}`,
    `write=${o.write}`,
    `verify=${o.verify}`,
    `poziva=${String(o.calls)}`,
    o.error ?? '',
  ].join('\t');
}

async function loadSample(deps: EvalDeps, opts: EvalOptions): Promise<{ samples: ChannelSample[]; notes: string[] }> {
  const samples: ChannelSample[] = [];
  const notes: string[] = [];
  const seen = new Set<string>();
  for (const slug of opts.channels) {
    let s = opts.resample ? null : await loadChannelSample(deps.db, slug);
    if (s) notes.push(`kanal ${slug}: uzorak iz baze (${String(s.episodes.length)} epizoda; --resample za novi)`);
    else {
      s = await sampleChannel(deps.cdn, slug, { limit: opts.limit, now: opts.now });
      // Ista epizoda u dva listinga ide u prvi kanal.
      s = { ...s, episodes: s.episodes.filter((e) => !seen.has(e.videoId)) };
      if (!opts.dryRun) await saveChannelSample(deps.db, s);
    }
    for (const e of s.episodes) seen.add(e.videoId);
    samples.push(s);
  }
  return { samples, notes };
}

export async function runEval(deps: EvalDeps, opts: EvalOptions): Promise<EvalResult> {
  const clock = deps.clock ?? Date.now;
  const { samples, notes } = await loadSample(deps, opts);
  const episodes = processingOrder(samples.flatMap((s) => s.episodes));
  const rejected = samples.flatMap((s) => s.rejected);
  const plans: EpisodePlan[] = [];
  for (const ep of episodes) plans.push(await planEpisode(deps, ep, opts.attempts));
  const estimate = estimateOf(plans, deps.backend, deps.pricing, opts.now);
  const lines = [...notes, formatEstimate(estimate, { backend: deps.backend, maxCalls: opts.maxCalls })];
  for (const p of plans.filter((x) => x.error !== null)) {
    lines.push(`  ne može se pokrenuti: ${p.ep.videoId} (${p.ep.channel}): ${p.error ?? ''}`);
  }
  const base = { plans, rejected, estimate, outcomes: [], callsMade: 0, stoppedByBudget: false };
  if (opts.maxCalls !== null && estimate.calls > opts.maxCalls) {
    lines.push(`STOP: procjena ${String(estimate.calls)} poziva je iznad --max-calls ${String(opts.maxCalls)}.`);
    return { ...base, exitCode: EXIT_OVER_BUDGET, text: lines.join('\n') };
  }
  if (opts.dryRun) {
    lines.push('--dry-run: ništa nije pozvano ni upisano.');
    return { ...base, exitCode: 0, text: lines.join('\n') };
  }

  const started = clock();
  const outcomes: EpisodeOutcome[] = [];
  let llm: (LlmClient & { readonly used: number }) | null = null;
  let stoppedByBudget = false;
  for (const p of plans) {
    const o: EpisodeOutcome = {
      videoId: p.ep.videoId,
      channel: p.ep.channel,
      extract: p.extract,
      score: p.score,
      write: p.write,
      verify: p.verify,
      calls: 0,
      error: p.error,
    };
    const todo = p.error === null && [p.extract, p.score, p.write, p.verify].includes('todo');
    if (todo) {
      llm ??= budgetedLlm(deps.llm(), opts.maxCalls);
      const before = llm.used;
      const runDeps = { cdn: deps.cdn, llm, recorder: deps.recorder, db: deps.db };
      try {
        let extractOk = p.extract === 'done';
        if (p.extract === 'todo') {
          const r = await runExtract(runDeps, { videoId: p.ep.videoId });
          extractOk = r.failedSections === 0;
          o.extract = extractOk ? 'ok' : `djelomično (${String(r.failedSections)}/${String(r.sections)} sekcija bez izlaza)`;
        }
        let scoreOk = p.score === 'done';
        if (extractOk && p.score === 'todo') {
          const s = await runScore({ ...runDeps, persons: deps.persons }, { videoId: p.ep.videoId, channel: p.ep.channel });
          scoreOk = s.missing.length === 0;
          o.score = scoreOk ? 'ok' : `djelomično (${String(s.missing.length)} bez ocjene)`;
        } else if (!extractOk) o.score = 'čeka izvlačenje';
        // Članak i provjera (odluka 434): samo nad potpuno ocijenjenom epizodom.
        let writeOk = p.write === 'done';
        if (scoreOk && p.write === 'todo') {
          const w = await runWrite(runDeps, { videoId: p.ep.videoId, channel: p.ep.channel });
          writeOk = w.saved !== null;
          o.write = writeOk ? 'ok' : 'none';
          if (!writeOk) o.verify = 'none';
        } else if (!scoreOk && p.write === 'todo') {
          o.write = 'čeka ocjenu';
          o.verify = 'čeka ocjenu';
        }
        if (writeOk && p.verify === 'todo') {
          const v = await runVerify(runDeps, { videoId: p.ep.videoId });
          o.verify = `ok (${String(v.result.summary.unsupported)} nepodržanih, ${String(v.result.summary.removed)} uklonjeno)`;
        }
      } catch (e) {
        if (e instanceof BudgetExceededError) stoppedByBudget = true;
        o.error = (e as Error).message;
      }
      o.calls = llm.used - before;
    }
    outcomes.push(o);
    if (todo || p.error !== null) await deps.log?.(logLine(o, clock()));
    if (stoppedByBudget) break;
  }

  const callsMade = llm?.used ?? 0;
  const failed = outcomes.filter((o) => o.error !== null && !o.error.startsWith('dosegnut --max-calls'));
  lines.push(
    '',
    `Gotovo za ${formatDuration((clock() - started) / 1000)}: poziva ${String(callsMade)}, ` +
      `epizoda obrađeno ${String(outcomes.filter((o) => o.calls > 0 && o.error === null).length)}, ` +
      `već gotovih ${String(estimate.done)}, s greškom ${String(failed.length)}, odustalih ${String(estimate.gaveUp)}.`,
  );
  for (const o of failed) lines.push(`  greška: ${o.videoId} (${o.channel}): ${o.error ?? ''}`);
  if (stoppedByBudget) lines.push(`STOP: dosegnut --max-calls ${String(opts.maxCalls)}; ponovno pokretanje nastavlja.`);
  return {
    ...base,
    outcomes,
    callsMade,
    stoppedByBudget,
    exitCode: stoppedByBudget ? EXIT_OVER_BUDGET : 0,
    text: lines.join('\n'),
  };
}

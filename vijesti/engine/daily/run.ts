// Dnevni job (S8, odluke 806 i 809): red provjere urednikovih verzija, pa nove
// epizode s dopuštenih kanala → izvlačenje → ocjena → članak → provjera.
//
// Idempotentno bez vlastitog knjigovodstva: stanje koraka po epizodi čita se iz
// `vijesti.runs` (`stepStates`, isto kao `npm run eval`), pa gotova epizoda ne
// troši ni jedan poziv, a epizoda kojoj je korak dvaput pao se ne pokušava
// treći put (`gave_up`). Ponovna obrada je ručna (`npm run vijesti -- write`).
//
// Limit je DNEVNI, ne po pokretanju: od limita se oduzima zbroj `runs.calls`
// od ponoći po Zagrebu, pa ručno drugo pokretanje istog dana ne dobije novi.
// Epizode koje ne stanu u ostatak čekaju sutra i to se javi.
import type { SqlDb } from '../../db/sql.js';
import type { CdnClient } from '../cdn/loader.js';
import type { RunRecorder } from '../llm/runs.js';
import type { LlmClient } from '../llm/types.js';
import type { PersonIndex } from '../score/persons.js';
import { runVerify } from '../verify/article.js';
import { budgetedLlm, BudgetExceededError, runEval, type EvalBackend, type EvalDeps, type EpisodePlan } from '../eval/run.js';
import { isoDay, probe, type SampledEpisode } from '../eval/sample.js';

/** Zadani dnevni limit poziva modela (odluka 809). */
export const DEFAULT_DAILY_MAX_CALLS = 150;
/** Koliko dana unatrag se gledaju epizode u listingu. */
export const DEFAULT_DAYS = 7;
export const ZONE = 'Europe/Zagreb';

/** Izlazni kodovi: 0 sve gotovo, 3 dio čeka sutra (limit), 1 greška. */
export const EXIT_DEFERRED = 3;

export interface DailyOptions {
  now: Date;
  days: number;
  maxCalls: number;
  dryRun: boolean;
  attempts: number;
  /** Poveznica za obavijest (admin). */
  adminUrl: string;
}

export interface DailyDeps {
  cdn: CdnClient;
  db: SqlDb;
  recorder: RunRecorder;
  persons: PersonIndex;
  llm: () => LlmClient;
  backend: EvalBackend;
  log?: (line: string) => Promise<void>;
}

export interface QueueItem {
  articleId: number;
  versionId: number;
  version: number;
  status: string;
}

export interface DailyResult {
  exitCode: 0 | 1 | typeof EXIT_DEFERRED;
  usedBefore: number;
  callsMade: number;
  queue: { item: QueueItem; result: string }[];
  candidates: number;
  /** Epizode s poslom (ne gotove, ne odustale). */
  planned: number;
  ran: number;
  deferred: SampledEpisode[];
  newDrafts: { articleId: number; title: string }[];
  errors: string[];
  text: string;
  /** HTML za Telegram (kroz scripts/telegram-notify.rb). */
  notify: string;
}

/** Ponoć po Zagrebu za dan od `now`, kao UTC trenutak. */
export function zagrebMidnight(now: Date): Date {
  const day = new Intl.DateTimeFormat('en-CA', { timeZone: ZONE }).format(now);
  // Pomak zone u tom trenutku (CET +1 / CEST +2).
  const probeAt = new Date(`${day}T12:00:00Z`);
  const local = new Date(probeAt.toLocaleString('en-US', { timeZone: ZONE }));
  const utc = new Date(probeAt.toLocaleString('en-US', { timeZone: 'UTC' }));
  const offsetMs = local.getTime() - utc.getTime();
  return new Date(new Date(`${day}T00:00:00Z`).getTime() - offsetMs);
}

/** Pozivi modela potrošeni od ponoći po Zagrebu (svi koraci, i ručni). */
export async function callsUsedToday(db: SqlDb, now: Date): Promise<number> {
  const res = await db.query<{ n: number | string | null }>(
    'SELECT coalesce(sum(calls), 0) AS n FROM vijesti.runs WHERE started_at >= $1',
    [zagrebMidnight(now).toISOString()],
  );
  return Number(res.rows[0]?.n ?? 0);
}

export async function loadAllowedChannels(db: SqlDb): Promise<string[]> {
  const res = await db.query<{ channel: string }>('SELECT channel FROM vijesti.allowed_channels ORDER BY channel');
  return res.rows.map((r) => r.channel);
}

export async function loadVerifyQueue(db: SqlDb): Promise<QueueItem[]> {
  const res = await db.query<{ article_id: number | string; version_id: number | string; version: number; status: string }>(
    'SELECT article_id, version_id, version, status FROM vijesti.versions_awaiting_verify ORDER BY article_id',
  );
  return res.rows.map((r) => ({
    articleId: Number(r.article_id),
    versionId: Number(r.version_id),
    version: r.version,
    status: r.status,
  }));
}

/**
 * Epizode dopuštenih kanala s datumom u zadnjih `days` dana (po Zagrebu),
 * najnovije prvo. Epizoda u dva listinga ide u prvi kanal. Bez titla
 * (`diarized.srt`) nema izvlačenja, pa se ne uzima.
 */
export async function recentEpisodes(
  cdn: CdnClient,
  channels: readonly string[],
  now: Date,
  days: number,
): Promise<{ episodes: SampledEpisode[]; notes: string[] }> {
  const today = new Intl.DateTimeFormat('en-CA', { timeZone: ZONE }).format(now);
  const from = isoDay(new Date(new Date(`${today}T00:00:00Z`).getTime() - (days - 1) * 86_400_000));
  const seen = new Set<string>();
  const episodes: SampledEpisode[] = [];
  const notes: string[] = [];
  for (const slug of channels) {
    const listing = await cdn.channel(slug);
    if (!listing) {
      notes.push(`kanal ${slug} nema listing na CDN-u`);
      continue;
    }
    const recent = listing.videos.filter((v) => v.date != null && v.date >= from && !seen.has(v.id));
    for (const v of recent) {
      seen.add(v.id);
      const p = await probe(cdn, v.id);
      if (!p.srt) {
        notes.push(`${v.id} (${slug}): još nema titla, čeka pipeline`);
        continue;
      }
      episodes.push({ videoId: v.id, channel: slug, date: v.date ?? null, hasWords: p.words, pick: 'fresh' });
    }
  }
  episodes.sort((a, b) => (b.date ?? '').localeCompare(a.date ?? '') || a.videoId.localeCompare(b.videoId));
  return { episodes, notes };
}

const hasWork = (p: EpisodePlan) => p.error === null && [p.extract, p.score, p.write, p.verify].includes('todo');

/** Najnovije prvo, dok procjena stane u ostatak; ostale čekaju sutra. */
export function fitBudget(plans: readonly EpisodePlan[], remaining: number): { take: EpisodePlan[]; rest: EpisodePlan[] } {
  const take: EpisodePlan[] = [];
  const rest: EpisodePlan[] = [];
  let sum = 0;
  for (const p of plans) {
    if (rest.length === 0 && sum + p.calls <= remaining) {
      take.push(p);
      sum += p.calls;
    } else rest.push(p);
  }
  return { take, rest };
}

async function draftsSince(db: SqlDb, since: Date): Promise<{ articleId: number; title: string }[]> {
  const res = await db.query<{ id: number | string; title: string }>(
    `SELECT a.id, v.title FROM vijesti.articles a
     JOIN LATERAL (SELECT title FROM vijesti.article_versions x WHERE x.article_id = a.id ORDER BY version DESC LIMIT 1) v ON true
     WHERE a.created_at >= $1 AND a.status = 'draft' ORDER BY a.id`,
    [since.toISOString()],
  );
  return res.rows.map((r) => ({ articleId: Number(r.id), title: r.title }));
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

export function formatNotify(r: Omit<DailyResult, 'text' | 'notify'>, opts: Pick<DailyOptions, 'adminUrl' | 'maxCalls'>): string {
  const lines: string[] = [];
  const head =
    r.exitCode === 1 ? 'Vijesti: dnevni job s greškom' : r.exitCode === EXIT_DEFERRED ? 'Vijesti: dnevni limit dosegnut' : 'Vijesti: dnevni job gotov';
  lines.push(`<b>${head}</b>`);
  lines.push(`Novih nacrta: ${String(r.newDrafts.length)}`);
  for (const d of r.newDrafts) lines.push(`• ${esc(d.title)} — ${opts.adminUrl}?clanak=${String(d.articleId)}`);
  if (r.queue.length > 0) lines.push(`Provjerenih uredničkih verzija: ${String(r.queue.length)}`);
  lines.push(`Poziva modela danas: ${String(r.usedBefore + r.callsMade)}/${String(opts.maxCalls)}`);
  if (r.deferred.length > 0) lines.push(`Čeka sutra (limit): ${String(r.deferred.length)} epizoda`);
  for (const e of r.errors.slice(0, 5)) lines.push(`Greška: ${esc(e)}`);
  if (r.errors.length > 5) lines.push(`… i još ${String(r.errors.length - 5)}`);
  if (r.newDrafts.length === 0) lines.push(opts.adminUrl);
  return lines.join('\n');
}

export async function runDaily(deps: DailyDeps, opts: DailyOptions): Promise<DailyResult> {
  const started = new Date();
  const lines: string[] = [];
  const errors: string[] = [];
  const usedBefore = await callsUsedToday(deps.db, opts.now);
  let remaining = Math.max(0, opts.maxCalls - usedBefore);
  lines.push(`Dnevni limit ${String(opts.maxCalls)} poziva, danas već ${String(usedBefore)}, ostaje ${String(remaining)}.`);

  // 1. Red provjere (odluka 806): urednikova verzija bez provjere ne može se odobriti.
  const queueItems = await loadVerifyQueue(deps.db);
  const queue: DailyResult['queue'] = [];
  let callsMade = 0;
  for (const item of queueItems) {
    if (opts.dryRun) {
      queue.push({ item, result: 'čeka (--dry-run)' });
      continue;
    }
    if (remaining < 1) {
      queue.push({ item, result: 'čeka sutra (limit)' });
      continue;
    }
    const llm = budgetedLlm(deps.llm(), remaining);
    try {
      const v = await runVerify({ llm, recorder: deps.recorder, db: deps.db }, { articleId: item.articleId });
      queue.push({ item, result: `provjereno (${String(v.result.summary.unsupported)} nepodržanih)` });
    } catch (e) {
      const msg = e instanceof BudgetExceededError ? 'čeka sutra (limit)' : (e as Error).message;
      queue.push({ item, result: msg });
      if (!(e instanceof BudgetExceededError)) errors.push(`provjera članka ${String(item.articleId)}: ${msg}`);
    }
    callsMade += llm.used;
    remaining -= llm.used;
  }
  for (const q of queue) lines.push(`  red provjere: članak ${String(q.item.articleId)} v${String(q.item.version)}: ${q.result}`);

  // 2. Nove epizode.
  const channels = await loadAllowedChannels(deps.db);
  const { episodes, notes } = await recentEpisodes(deps.cdn, channels, opts.now, opts.days);
  lines.push(`Kanali: ${channels.join(', ') || '(nijedan)'}; epizoda u zadnjih ${String(opts.days)} dana s titlom: ${String(episodes.length)}.`);
  for (const n of notes) lines.push(`  ${n}`);

  const evalDeps: EvalDeps = {
    cdn: deps.cdn,
    db: deps.db,
    recorder: deps.recorder,
    persons: deps.persons,
    llm: deps.llm,
    backend: deps.backend,
    pricing: null,
    ...(deps.log ? { log: deps.log } : {}),
  };
  const base = { channels: [], limit: 0, resample: false, now: opts.now, attempts: opts.attempts };
  const plan = await runEval(evalDeps, { ...base, episodes, maxCalls: null, dryRun: true });
  const work = plan.plans.filter(hasWork);
  // Trajno neobradivo (krivi jezik, nema sekcija): napomena, ne greška, inače bi javljalo svaki dan.
  for (const p of plan.plans.filter((x) => x.error !== null)) lines.push(`  ne može se obraditi: ${p.ep.videoId} (${p.ep.channel}): ${p.error ?? ''}`);
  const { take, rest } = fitBudget(work, remaining);
  lines.push(`S poslom: ${String(work.length)} (procjena ${String(work.reduce((n, p) => n + p.calls, 0))} poziva); stane danas: ${String(take.length)}.`);

  let ran = 0;
  if (!opts.dryRun && take.length > 0) {
    const res = await runEval(evalDeps, { ...base, episodes: take.map((p) => p.ep), maxCalls: remaining, dryRun: false });
    callsMade += res.callsMade;
    ran = res.outcomes.filter((o) => o.calls > 0).length;
    for (const o of res.outcomes) if (o.error !== null) errors.push(`${o.videoId} (${o.channel}): ${o.error}`);
    if (res.stoppedByBudget) {
      const done = new Set(res.outcomes.filter((o) => o.error === null).map((o) => o.videoId));
      rest.unshift(...take.filter((p) => !done.has(p.ep.videoId)));
    }
    lines.push(res.text);
  } else if (opts.dryRun) lines.push('--dry-run: ništa nije pozvano ni upisano.');

  const newDrafts = opts.dryRun ? [] : await draftsSince(deps.db, started);
  const deferred = rest.map((p) => p.ep);
  const realErrors = errors.filter((e) => !e.includes('dosegnut --max-calls'));
  const exitCode = realErrors.length > 0 ? 1 : deferred.length > 0 ? EXIT_DEFERRED : 0;
  const result = { exitCode, usedBefore, callsMade, queue, candidates: episodes.length, planned: work.length, ran, deferred, newDrafts, errors: realErrors } as const;
  for (const e of deferred) lines.push(`  čeka sutra: ${e.videoId} (${e.channel}, ${e.date ?? '?'})`);
  lines.push(`Novih nacrta: ${String(newDrafts.length)}; poziva sada: ${String(callsMade)}; izlaz ${String(exitCode)}.`);
  return { ...result, text: lines.join('\n'), notify: formatNotify(result, opts) };
}

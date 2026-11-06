// Izvještaj mjerenja F0 iz baze (odluka 411): Markdown, uz svaku tablicu
// naredba koja je reproducira (`npm run eval:report -- --db … --query "…"`).
// Čita samo uzorak (`vijesti.eval_sample`) i ocjene trenutne verzije.
import type { SqlDb } from '../../db/sql.js';
import { DEFAULT_GEMINI_MODEL, defaultPricing } from '../llm/config.js';
import { costUsd } from '../llm/types.js';
import { NEWS_SCORE_THRESHOLD, SCORE_VERSION } from '../score/formula.js';
import { INFLOW_DAYS } from './sample.js';

export interface ReportOptions {
  /** Putanja baze za naredbe reprodukcije. */
  dbPath: string;
  threshold?: number;
  /** Zaglavlje (testovi daju stalnu vrijednost). */
  generatedAt?: Date;
  top?: number;
}

type Row = Record<string, unknown>;

/** SQL u jednom retku, bez dvostrukih navodnika (ide u ljusku unutar "…"). */
function oneLine(sql: string): string {
  return sql.replace(/\s+/g, ' ').trim();
}

export function reproduceCommand(dbPath: string, sql: string): string {
  return `npm run eval:report -- --db '${dbPath}' --query "${oneLine(sql)}"`;
}

function cell(v: unknown): string {
  if (v === null || v === undefined) return '–';
  if (v instanceof Date) return v.toISOString();
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : String(Math.round(v * 1000) / 1000);
  if (typeof v === 'boolean') return v ? 'da' : 'ne';
  if (typeof v === 'string') return v.replace(/\|/g, '\\|').replace(/\n/g, ' ');
  return JSON.stringify(v);
}

/** Markdown tablica redaka (stupci redom prvog retka). */
export function markdownTable(rows: readonly Row[]): string {
  const first = rows[0];
  if (!first) return '_(nema redaka)_';
  const cols = Object.keys(first);
  return [
    `| ${cols.join(' | ')} |`,
    `| ${cols.map(() => '---').join(' | ')} |`,
    ...rows.map((r) => `| ${cols.map((c) => cell(r[c])).join(' | ')} |`),
  ].join('\n');
}

/** SQL u read-only transakciji (`--query`). */
export async function readOnlyQuery(db: SqlDb, sql: string): Promise<Row[]> {
  await db.exec('BEGIN TRANSACTION READ ONLY');
  try {
    return (await db.query<Row>(sql)).rows;
  } finally {
    await db.exec('ROLLBACK');
  }
}

const num = (v: unknown): number => (v === null || v === undefined ? 0 : Number(v));
const pct = (a: number, b: number): string => (b === 0 ? '–' : `${(Math.round((1000 * a) / b) / 10).toFixed(1)} %`);

export function momentLink(videoId: string, startMs: number): string {
  return `https://domovina.ai/v/${videoId}/t/${String(Math.floor(startMs / 1000))}`;
}

export async function buildEvalReport(db: SqlDb, opts: ReportOptions): Promise<string> {
  const th = opts.threshold ?? NEWS_SCORE_THRESHOLD;
  const top = opts.top ?? 10;
  const v = SCORE_VERSION;
  const out: string[] = [];
  const section = async (title: string, sql: string, note?: string): Promise<Row[]> => {
    const rows = (await db.query<Row>(sql)).rows;
    out.push(`## ${title}`, '');
    if (note) out.push(note, '');
    out.push(markdownTable(rows), '', `Reprodukcija: \`${reproduceCommand(opts.dbPath, sql)}\``, '');
    return rows;
  };

  out.push(
    '# Mjerenje F0: trenuci i ocjena vijesti',
    '',
    `Izvještaj iz baze \`${opts.dbPath}\`${opts.generatedAt ? `, ${opts.generatedAt.toISOString()}` : ''}. ` +
      `Ocjene verzije \`${v}\`; prag ${String(th)} je PRIVREMEN (odluka 315), konstanta \`NEWS_SCORE_THRESHOLD\`.`,
    '',
    `Cijeli izvještaj: \`npm run eval:report -- --db '${opts.dbPath}'\``,
    '',
  );

  await section(
    'Uzorak',
    `SELECT channel, count(*) AS epizoda, count(*) FILTER (WHERE has_words) AS s_words,
       count(*) FILTER (WHERE pick = 'fresh') AS svjezih, count(*) FILTER (WHERE pick = 'older') AS starijih
     FROM vijesti.eval_sample GROUP BY channel ORDER BY channel`,
  );

  const perEpisodeSql = `SELECT s.channel, s.video_id, to_char(s.episode_date, 'YYYY-MM-DD') AS datum,
       EXISTS (SELECT 1 FROM vijesti.runs r WHERE r.video_id = s.video_id AND r.step = 'extract' AND r.status = 'ok') AS izvuceno,
       count(m.id) AS trenutaka,
       count(m.id) FILTER (WHERE m.quote_check <> 'failed') AS prihvacenih,
       count(m.id) FILTER (WHERE m.score_version = '${v}') AS ocijenjenih,
       count(m.id) FILTER (WHERE m.score_version = '${v}' AND m.score >= ${String(th)}) AS iznad_praga,
       round(max(m.score) FILTER (WHERE m.score_version = '${v}')::numeric, 3) AS najbolja
     FROM vijesti.eval_sample s LEFT JOIN vijesti.moments m ON m.video_id = s.video_id
     GROUP BY s.channel, s.video_id, s.episode_date ORDER BY s.channel, s.episode_date, s.video_id`;
  const eps = await section('Trenuci po epizodi', perEpisodeSql);
  const done = eps.filter((r) => r.izvuceno === true);
  const sum = (k: string) => done.reduce((n, r) => n + num(r[k]), 0);
  const withNews = done.filter((r) => num(r.iznad_praga) > 0).length;
  out.push(
    `Izvučenih epizoda: ${String(done.length)} od ${String(eps.length)}. ` +
      `Prosjek po izvučenoj epizodi: ${done.length ? (sum('trenutaka') / done.length).toFixed(1) : '–'} trenutaka, ` +
      `${done.length ? (sum('prihvacenih') / done.length).toFixed(1) : '–'} prihvaćenih, ` +
      `${done.length ? (sum('iznad_praga') / done.length).toFixed(1) : '–'} iznad praga. ` +
      `Epizoda s barem jednim trenutkom iznad praga: ${String(withNews)} (${pct(withNews, done.length)}). ` +
      'Izračun iz tablice iznad (stupci `izvuceno`, `trenutaka`, `prihvacenih`, `iznad_praga`).',
    '',
  );

  await section(
    'Provjera citata: ishod',
    `SELECT m.quote_check AS ishod, count(*) AS n, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS posto
     FROM vijesti.moments m JOIN vijesti.eval_sample s ON s.video_id = m.video_id
     GROUP BY m.quote_check ORDER BY n DESC, m.quote_check`,
  );
  await section(
    'Provjera citata: razlog odbijanja',
    `SELECT m.reject_reason AS razlog, count(*) AS n, round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS posto
     FROM vijesti.moments m JOIN vijesti.eval_sample s ON s.video_id = m.video_id
     WHERE m.quote_check = 'failed' GROUP BY m.reject_reason ORDER BY n DESC, m.reject_reason`,
    'Udio je među odbijenim (`failed`) trenucima.',
  );
  const above = await section(
    'Ocjena: udio iznad praga',
    `SELECT count(*) AS ocijenjenih, count(*) FILTER (WHERE m.score >= ${String(th)}) AS iznad_praga,
       round(100.0 * count(*) FILTER (WHERE m.score >= ${String(th)}) / nullif(count(*), 0), 1) AS posto,
       round(avg(m.score)::numeric, 3) AS prosjek
     FROM vijesti.moments m JOIN vijesti.eval_sample s ON s.video_id = m.video_id
     WHERE m.score_version = '${v}'`,
  );
  await section(
    'Ocjena: raspodjela',
    `SELECT floor(m.score * 10) / 10 AS od, count(*) AS n
     FROM vijesti.moments m JOIN vijesti.eval_sample s ON s.video_id = m.video_id
     WHERE m.score_version = '${v}' GROUP BY 1 ORDER BY 1 DESC`,
    'Razred `od` znači [od, od + 0,1).',
  );

  const momentsSql = (dir: 'DESC' | 'ASC') => `SELECT m.video_id, m.start_ms, m.speaker, m.speaker_name,
       round(m.score::numeric, 3) AS score, m.quote, m.claim
     FROM vijesti.moments m JOIN vijesti.eval_sample s ON s.video_id = m.video_id
     WHERE m.score_version = '${v}' ORDER BY m.score ${dir}, m.video_id, m.start_ms LIMIT ${String(top)}`;
  for (const [title, dir] of [
    [`${String(top)} najboljih trenutaka`, 'DESC'],
    [`${String(top)} najlošijih trenutaka`, 'ASC'],
  ] as const) {
    const sql = momentsSql(dir);
    const rows = (await db.query<Row>(sql)).rows;
    out.push(`## ${title}`, '');
    if (rows.length === 0) out.push('_(nema ocijenjenih trenutaka)_', '');
    rows.forEach((r, i) => {
      const who = typeof r.speaker_name === 'string' && r.speaker_name ? `${r.speaker_name} (${cell(r.speaker)})` : cell(r.speaker);
      const id = cell(r.video_id);
      out.push(
        `${String(i + 1)}. **${cell(num(r.score))}** · ${who} · ${momentLink(id, num(r.start_ms))}`,
        '',
        `   > ${cell(r.quote)}`,
        '',
        `   Tvrdnja: ${cell(r.claim)}`,
        '',
      );
    });
    out.push(`Reprodukcija: \`${reproduceCommand(opts.dbPath, sql)}\``, '');
  }

  const inflowSql = `SELECT c.channel, c.listed AS u_listingu, c.episodes_30d AS epizoda_${String(INFLOW_DAYS)}d,
       to_char(c.window_end, 'YYYY-MM-DD') AS do_dana
     FROM vijesti.eval_channels c ORDER BY c.channel`;
  const inflow = await section(
    'Dotok i procjena „vijesti dnevno”',
    inflowSql,
    `Dotok je broj epizoda s datumom u zadnjih ${String(INFLOW_DAYS)} dana u listingu kanala u trenutku uzorkovanja.`,
  );
  const byChannel = new Map<string, { done: number; news: number }>();
  for (const r of done) {
    const c = cell(r.channel);
    const e = byChannel.get(c) ?? { done: 0, news: 0 };
    e.done++;
    if (num(r.iznad_praga) > 0) e.news++;
    byChannel.set(c, e);
  }
  let perDay = 0;
  let epPerDay = 0;
  const lines: string[] = [];
  for (const r of inflow) {
    const c = cell(r.channel);
    const daily = num(r[`epizoda_${String(INFLOW_DAYS)}d`]) / INFLOW_DAYS;
    const e = byChannel.get(c);
    epPerDay += daily;
    if (!e || e.done === 0) {
      lines.push(`- ${c}: ${daily.toFixed(2)} epizoda dnevno, nema izvučenih epizoda u uzorku`);
      continue;
    }
    const est = daily * (e.news / e.done);
    perDay += est;
    lines.push(
      `- ${c}: ${daily.toFixed(2)} epizoda dnevno × ${String(e.news)}/${String(e.done)} epizoda uzorka s vijesti = ${est.toFixed(2)} vijesti dnevno`,
    );
  }
  out.push(
    'Pretpostavka: jedna vijest po epizodi koja ima barem jedan trenutak iznad praga (generator S4 piše članak iz trenutaka jedne epizode).',
    '',
    ...lines,
    '',
    `Ukupno za kanale uzorka: ${epPerDay.toFixed(2)} epizoda dnevno, procjena **${perDay.toFixed(2)} vijesti dnevno**. ` +
      'Izračun iz tablice dotoka i tablice „Trenuci po epizodi”.',
    '',
  );

  const costSql = `SELECT r.step, r.model, count(*) AS runova, sum(r.calls) AS poziva, sum(r.failed_calls) AS neuspjelih,
       sum(r.tokens_in) AS tokena_ulaz, sum(r.tokens_out) AS tokena_izlaz, sum(r.cost_usd) AS usd,
       bool_or(r.tokens_estimated) AS procjena,
       round(extract(epoch FROM sum(r.finished_at - r.started_at))::numeric, 1) AS sekundi
     FROM vijesti.runs r JOIN vijesti.eval_sample s ON s.video_id = r.video_id
     GROUP BY r.step, r.model ORDER BY r.step, r.model`;
  const cost = await section(
    'Trošak i trajanje',
    costSql,
    'Stupac `procjena` = tokeni su procjena iz znakova (odluka 305), ne brojka API-ja; agy ih ne vraća (odluka 401).',
  );
  const tIn = cost.reduce((n, r) => n + num(r.tokena_ulaz), 0);
  const tOut = cost.reduce((n, r) => n + num(r.tokena_izlaz), 0);
  const calls = cost.reduce((n, r) => n + num(r.poziva), 0);
  const secs = cost.reduce((n, r) => n + num(r.sekundi), 0);
  const paid = cost.reduce((n, r) => n + num(r.usd), 0);
  const estimated = cost.some((r) => r.procjena === true);
  const api = costUsd(
    { tokensIn: tIn, tokensOut: tOut },
    defaultPricing('vertex', DEFAULT_GEMINI_MODEL, 'global', (opts.generatedAt ?? new Date()).getTime()),
  );
  const n = done.length;
  const tag = estimated ? ' (PROCJENA iz znakova)' : '';
  out.push(
    `Po izvučenoj epizodi (${String(n)}): ` +
      (n === 0
        ? 'nema podataka.'
        : `${(calls / n).toFixed(1)} poziva, ~${String(Math.round(tIn / n))} ulaznih i ~${String(Math.round(tOut / n))} izlaznih tokena${tag}, ` +
          `stvarni trošak $${(paid / n).toFixed(4)}, API-ekvivalent po Vertex cjeniku $${((api ?? 0) / n).toFixed(4)}${tag}, ` +
          `${calls ? (secs / calls).toFixed(1) : '–'} s po pozivu.`),
    '',
    `Udio iznad praga je ${cell(above[0]?.posto ?? null)} % ocijenjenih trenutaka (tablica „Ocjena: udio iznad praga”).`,
    '',
  );
  return out.join('\n');
}

// Izvoz nacrta iz baze u Markdown za korisnika (odluka 435): zadnja verzija
// svakog članka formata `vijest`, citati umetnuti iz `moments.quote` s imenom,
// vremenom i linkom na trenutak, kategorija, broj riječi i rezultat provjere.
// Uz svaku tablicu naredba koja je reproducira (kao odluka 411).
import type { SqlDb } from '../../db/sql.js';
import { NEWS_SCORE_THRESHOLD, SCORE_VERSION } from '../score/formula.js';
import type { VerifyResult } from '../verify/article.js';
import type { SourceMoment } from '../write/content.js';
import { WORD_RANGE } from '../write/prompt.js';
import { ARTICLE_FORMAT, loadLatestVersion } from '../write/store.js';
import { clock, hrDate, momentUrl } from '../write/text.js';
import { markdownTable, readOnlyQuery, reproduceCommand } from './report.js';

export interface DraftsOptions {
  dbPath: string;
  generatedAt?: Date;
}

export const SUMMARY_SQL = `SELECT a.id AS clanak, s.slug AS prica, v.version AS verzija, v.created_by AS autor,
  v.category AS kategorija, v.word_count AS rijeci,
  (v.verify->'summary'->>'sentences')::int AS recenica, (v.verify->'summary'->>'supported')::int AS podrzanih,
  (v.verify->'summary'->>'unsupported')::int AS nepodrzanih, (v.verify->'summary'->>'removed')::int AS uklonjeno,
  (v.verify->'summary'->>'style')::int AS stil
FROM vijesti.articles a JOIN vijesti.stories s ON s.id = a.story_id
JOIN vijesti.article_versions v ON v.article_id = a.id
  AND v.version = (SELECT max(x.version) FROM vijesti.article_versions x WHERE x.article_id = a.id)
WHERE a.format = '${ARTICLE_FORMAT}' ORDER BY a.id`;

/** Epizode uzorka bez članka i zašto (nema trenutaka, nema ocjene, ništa ≥ praga). */
export const NO_DRAFT_SQL = `SELECT e.video_id, e.channel AS kanal,
  (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.quote_check <> 'failed') AS prihvacenih,
  (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.score_version = '${SCORE_VERSION}') AS ocijenjenih,
  (SELECT count(*) FROM vijesti.moments m WHERE m.video_id = e.video_id AND m.score_version = '${SCORE_VERSION}'
     AND m.score >= ${String(NEWS_SCORE_THRESHOLD)}) AS iznad_praga
FROM vijesti.eval_sample e
WHERE NOT EXISTS (SELECT 1 FROM vijesti.stories s WHERE s.slug = 'video-' || e.video_id)
ORDER BY e.channel, e.video_id`;

export function flaggedSql(versionId: number): string {
  return `SELECT x->>'n' AS n, x->>'part' AS dio, x->'problems' AS problemi, x->>'text' AS tekst
FROM vijesti.article_versions v, jsonb_array_elements(v.verify->'sentences') x
WHERE v.id = ${String(versionId)} AND x->>'status' = 'unsupported'`;
}

function quoteBlock(m: SourceMoment): string {
  const lang = m.quoteLang === 'hr' ? '' : ` · izvornik (${m.quoteLang}), ne prijevod`;
  return [
    `> „${m.quote}”`,
    `> – ${m.speakerName ?? m.speaker}, ${clock(m.startMs)} · ${momentUrl(m.videoId, m.startMs)}${lang}`,
  ].join('\n');
}

export async function buildDrafts(db: SqlDb, opts: DraftsOptions): Promise<string> {
  const at = (opts.generatedAt ?? new Date()).toISOString();
  const repro = (sql: string) => `Reprodukcija: \`${reproduceCommand(opts.dbPath, sql)}\``;
  const summary = await readOnlyQuery(db, SUMMARY_SQL);
  const out: string[] = [
    '# Nacrti vijesti iz podcasta',
    '',
    `Generirano ${at} iz baze \`${opts.dbPath}\`. Prag ocjene ${String(NEWS_SCORE_THRESHOLD)} je PRIVREMEN (odluka 315); ` +
      `raspon riječi ${String(WORD_RANGE.min)}–${String(WORD_RANGE.max)} (docs/stil.md V10). ` +
      'Citati su umetnuti iz `moments.quote`; generator ih ne piše (odluka 417).',
    '',
    '## Sažetak',
    '',
    `Nacrta: ${String(summary.length)}.`,
    '',
    markdownTable(summary),
    '',
    repro(SUMMARY_SQL),
  ];
  try {
    const none = await readOnlyQuery(db, NO_DRAFT_SQL);
    out.push('', '## Epizode uzorka bez nacrta', '', markdownTable(none), '', repro(NO_DRAFT_SQL));
  } catch {
    // Baza bez tablice uzorka (samo `vijesti write`): sekcije nema.
  }

  for (const row of summary) {
    const v = await loadLatestVersion(db, Number(row.clanak));
    if (!v?.content) continue;
    const c = v.content;
    const e = c.episode;
    const byId = new Map(v.sources.map((m) => [m.id, m]));
    const verify = v.verify as VerifyResult | null;
    const inRange = v.wordCount !== null && v.wordCount >= WORD_RANGE.min && v.wordCount <= WORD_RANGE.max;
    out.push(
      '',
      `## ${c.title}`,
      '',
      `- Epizoda: ${e.title ?? e.videoId} · ${e.channelName ?? e.channel ?? 'kanal nepoznat'} · ${hrDate(e.date) ?? 'datum nepoznat'} · https://domovina.ai/v/${e.videoId}`,
      `- Članak ${String(v.articleId)}, verzija ${String(v.version)} (${v.createdBy ?? '-'}, ${v.promptVersion ?? '-'}), kategorija \`${c.category}\``,
      `- Riječi: ${String(v.wordCount)} (${inRange ? 'u rasponu' : `IZVAN ${String(WORD_RANGE.min)}–${String(WORD_RANGE.max)}`})`,
      verify
        ? `- Provjera: ${String(verify.summary.sentences)} rečenica, podržanih ${String(verify.summary.supported)}, nepodržanih ${String(verify.summary.unsupported)}, uklonjeno ${String(verify.summary.removed)}, stilskih napomena ${String(verify.summary.style)}`
        : '- Provjera: još nije pokrenuta (`npm run vijesti -- verify …`)',
      '',
      `**${c.lead}**`,
    );
    for (const b of c.blocks) {
      out.push('');
      if (b.type === 'p') out.push(b.text);
      else {
        const m = b.moment_id === null ? undefined : byId.get(b.moment_id);
        out.push(m ? quoteBlock(m) : `> [citat ${b.ref}: trenutak ne postoji]`);
      }
    }
    if (verify) {
      const flagged = verify.sentences.filter((s) => s.status === 'unsupported');
      out.push('', '### Provjera', '');
      if (flagged.length === 0 && verify.removed.length === 0 && verify.style.length === 0) out.push('Bez napomena.');
      for (const s of flagged) {
        out.push(`- s${String(s.n)} (${s.part}) NEPODRŽANO: ${s.problems.map((p) => `${p.code}: ${p.detail}`).join('; ')}. Rečenica: ${s.text}`);
      }
      for (const r of verify.removed) out.push(`- UKLONJENO (${r.code}): ${r.detail}. Tekst: ${r.text}`);
      for (const st of verify.style) out.push(`- Stil (${st.code}): ${st.detail}`);
      out.push('', repro(flaggedSql(v.versionId)));
    }
  }
  return `${out.join('\n')}\n`;
}

// `npm run portal:release-check [-- <wrangler.json>]` (odluka 710): provjera
// produkcijskog builda prije objave. Čita konfiguraciju koja bi otišla na
// Cloudflare (`portal/dist/server/wrangler.json`, varijable već spojene iz
// wrangler.jsonc) i pada (exit 1) dok impresum ima prazno polje ili Worker nema
// anon ključ. Build u produkcijskom načinu poziva istu provjeru: ispiše
// upozorenje, a uz `VIJESTI_RELEASE=1` pada (astro.config.mjs).
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { LEGAL_VARS, missingLegal, readLegal } from '../src/lib/config.js';

export const DEFAULT_WRANGLER_JSON = fileURLToPath(new URL('../dist/server/wrangler.json', import.meta.url));

export interface ReleaseProblem {
  variable: string;
  why: string;
}

const LEGAL_WHY: Record<keyof typeof LEGAL_VARS, string> = {
  publisherName: 'impresum: nakladnik',
  publisherAddress: 'impresum: sjedište nakladnika',
  editorInChief: 'impresum: glavni urednik',
  contactEmail: 'kontakt za ispravke i kreatore',
  aemRegistration: 'impresum: upis kod AEM-a',
};

/** Što u varijablama Workera još čeka izdavača ili konfiguraciju. */
export function releaseProblems(vars: Record<string, unknown>): ReleaseProblem[] {
  const out: ReleaseProblem[] = missingLegal(readLegal(vars)).map((f) => ({ variable: LEGAL_VARS[f], why: LEGAL_WHY[f] }));
  const anon = vars.VIJESTI_ANON_KEY;
  if (typeof anon !== 'string' || anon.trim() === '') {
    out.push({ variable: 'VIJESTI_ANON_KEY', why: 'javni anon ključ Supabasea (bez njega PostgREST odbija svaki upit)' });
  }
  if (vars.VIJESTI_NOINDEX === '1') {
    out.push({ variable: 'VIJESTI_NOINDEX', why: 'portal je noindex (tehnička produkcija, odluka 801); makni varijablu' });
  }
  return out;
}

export function readWranglerVars(path: string): Record<string, unknown> {
  const j = JSON.parse(readFileSync(path, 'utf8')) as { vars?: unknown };
  return j.vars && typeof j.vars === 'object' ? (j.vars as Record<string, unknown>) : {};
}

export function formatProblems(problems: readonly ReleaseProblem[]): string {
  return [
    `Portal vijesti NIJE spreman za objavu: ${String(problems.length)} vrijednosti nedostaje.`,
    ...problems.map((p) => `  - ${p.variable}: ${p.why}`),
    'Upiši ih u portal/wrangler.jsonc (`vars`) i ponovi build. Impresum ih dotad prikazuje kao „[upisuje izdavač]”.',
  ].join('\n');
}

const isMain = import.meta.url === `file://${process.argv[1] ?? ''}`;
if (isMain) {
  const args = process.argv.slice(2);
  const warnOnly = args.includes('--warn');
  const path = args.find((a) => !a.startsWith('--')) ?? DEFAULT_WRANGLER_JSON;
  const problems = releaseProblems(readWranglerVars(path));
  if (problems.length === 0) {
    console.log('[vijesti] release-check: impresum i konfiguracija su potpuni.');
  } else {
    console.error(`\n[vijesti] ${formatProblems(problems)}\n`);
    if (!warnOnly) process.exit(1);
  }
}

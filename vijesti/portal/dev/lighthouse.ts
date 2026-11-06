// `npm run lighthouse`: Lighthouse (mobile, zadani profil: simulirani Slow 4G i
// 4× sporiji CPU) nad lokalnim produkcijskim buildom portala + shim (`startPreview`).
// LIGHTHOUSE_THROTTLING=devtools mjeri sa stvarnim usporenjem umjesto simulacije.
// Članak (cilj performance ≥ 90, odluka 3) i naslovnica, svaki RUNS puta; ispisuje
// medijan po kategoriji i sprema HTML izvještaje u `.cache/lighthouse/`.
// Chrome: CHROME_PATH, inače /Applications/Google Chrome.app. Izlaz 1 ako je
// medijan performancea članka ispod 90.
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as chromeLauncher from 'chrome-launcher';
import lighthouse from 'lighthouse';
import { startPreview } from './preview.js';

const RUNS = Number(process.env.LIGHTHOUSE_RUNS ?? 3);
// `simulate` (zadano, Lantern) ili `devtools` (stvarno usporena mreža i CPU, sporije i šumovitije).
const THROTTLING = process.env.LIGHTHOUSE_THROTTLING === 'devtools' ? 'devtools' : 'simulate';
const TARGET = 90;
const CATEGORIES = ['performance', 'accessibility', 'best-practices', 'seo'] as const;
const METRICS = ['first-contentful-paint', 'largest-contentful-paint', 'total-blocking-time', 'cumulative-layout-shift', 'speed-index'] as const;
const OUT = fileURLToPath(new URL('../../.cache/lighthouse/', import.meta.url));
const MAC_CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const median = (xs: number[]): number => {
  const s = [...xs].sort((a, b) => a - b);
  return s[Math.floor(s.length / 2)] ?? NaN;
};

const chromePath = process.env.CHROME_PATH ?? (existsSync(MAC_CHROME) ? MAC_CHROME : undefined);
if (!chromePath) throw new Error('Nema Chromea: postavi CHROME_PATH');

mkdirSync(OUT, { recursive: true });
const preview = await startPreview({ build: !process.argv.includes('--no-build') });
const chrome = await chromeLauncher.launch({ chromePath, chromeFlags: ['--headless=new', '--no-first-run', '--disable-extensions'] });
let failed = false;
try {
  const published = preview.shim.articles().find((a) => a.state === 'published');
  if (!published) throw new Error('seed nema objavljen članak');
  const pages = [
    { name: 'clanak', url: `${preview.url}${published.slug}` },
    { name: 'naslovnica', url: preview.url },
  ];
  const ua = (await (await fetch(`http://127.0.0.1:${String(chrome.port)}/json/version`)).json()) as { Browser?: string };
  console.log(`[lighthouse] ${ua.Browser ?? chromePath}, ${String(RUNS)}× po stranici, mobile, throttling ${THROTTLING}`);
  for (const p of pages) {
    const scores: Record<string, number[]> = {};
    const metrics: Record<string, number[]> = {};
    for (let i = 0; i < RUNS; i++) {
      const r = await lighthouse(p.url, { port: chrome.port, output: 'html', logLevel: 'error', onlyCategories: [...CATEGORIES], throttlingMethod: THROTTLING });
      if (!r) throw new Error(`lighthouse nije vratio rezultat za ${p.url}`);
      if (r.lhr.runtimeError) throw new Error(`${p.url}: ${r.lhr.runtimeError.message}`);
      for (const c of CATEGORIES) (scores[c] ??= []).push(Math.round((r.lhr.categories[c]?.score ?? 0) * 100));
      for (const m of METRICS) (metrics[m] ??= []).push(r.lhr.audits[m]?.numericValue ?? NaN);
      if (i === 0) writeFileSync(join(OUT, `${p.name}.html`), String(r.report));
    }
    const line = CATEGORIES.map((c) => `${c} ${String(median(scores[c] ?? []))} (${(scores[c] ?? []).join('/')})`).join(', ');
    const ms = (m: string) => median(metrics[m] ?? []);
    console.log(`[lighthouse] ${p.name}: ${line}`);
    console.log(
      `[lighthouse] ${p.name}: FCP ${ms('first-contentful-paint').toFixed(0)} ms, LCP ${ms('largest-contentful-paint').toFixed(0)} ms, TBT ${ms('total-blocking-time').toFixed(0)} ms, CLS ${ms('cumulative-layout-shift').toFixed(3)}, SI ${ms('speed-index').toFixed(0)} ms`,
    );
    if (p.name === 'clanak' && median(scores.performance ?? []) < TARGET) failed = true;
  }
  console.log(`[lighthouse] izvještaji: ${OUT}`);
} finally {
  chrome.kill();
  await preview.stop();
}
if (failed) {
  console.error(`[lighthouse] performance članka ispod ${String(TARGET)}`);
  process.exit(1);
}
process.exit(0);

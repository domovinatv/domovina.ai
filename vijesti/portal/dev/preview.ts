// `npm run portal:preview`: produkcijski build portala u lokalnom načinu
// (VIJESTI_AUTH_MODE=local, CLOUDFLARE_ENV=local → varijable shima upečene u
// wrangler.json) u `portal/dist-local/`, pa shim (8790) + `astro preview` (workerd)
// na 127.0.0.1:${VIJESTI_PORTAL_PORT:-4322}. Isti izlaz kao produkcija osim
// prijave i adresa, pa ga koriste e2e i Lighthouse. `--no-build` preskače build.
// Astro se pokreće programski: CLI iz agenta se sam odvaja u pozadinu.
import { fileURLToPath } from 'node:url';
import { startShim } from './serve-shim.js';

export const DEFAULT_PREVIEW_PORT = 4322;

export async function startPreview(opts: { build?: boolean; port?: number } = {}) {
  const port = opts.port ?? Number(process.env.VIJESTI_PORTAL_PORT ?? DEFAULT_PREVIEW_PORT);
  const root = fileURLToPath(new URL('..', import.meta.url));
  const outDir = fileURLToPath(new URL('../dist-local/', import.meta.url));
  const { build, preview } = await import('astro');
  if (opts.build !== false) {
    const env = { mode: process.env.VIJESTI_AUTH_MODE, cf: process.env.CLOUDFLARE_ENV };
    process.env.VIJESTI_AUTH_MODE = 'local';
    process.env.CLOUDFLARE_ENV = 'local';
    try {
      await build({ root, outDir, logLevel: 'warn' });
    } finally {
      restore('VIJESTI_AUTH_MODE', env.mode);
      restore('CLOUDFLARE_ENV', env.cf);
    }
  }
  // Varijable su već upečene u dist-local/server/wrangler.json; s CLOUDFLARE_ENV
  // bi ih preview tražio ponovno pod `env.local` i upozoravao.
  const cf = process.env.CLOUDFLARE_ENV;
  delete process.env.CLOUDFLARE_ENV;
  const shim = await startShim();
  const server = await preview({ root, outDir, logLevel: 'warn', server: { port, host: '127.0.0.1' } });
  restore('CLOUDFLARE_ENV', cf);
  const stop = async () => {
    await Promise.allSettled([server.stop(), shim.stop()]);
  };
  return { url: `http://127.0.0.1:${String(port)}/vijesti/`, port, shim, stop };
}

function restore(key: string, value: string | undefined): void {
  if (value === undefined) Reflect.deleteProperty(process.env, key);
  else process.env[key] = value;
}

const isMain = import.meta.url === `file://${process.argv[1] ?? ''}`;
if (isMain) {
  const p = await startPreview({ build: !process.argv.includes('--no-build') });
  console.log(`[portal] preview ${p.url}  (shim :${String(p.shim.port)})`);
  for (const a of p.shim.articles()) console.log(`[portal] ${a.state.padEnd(9)} ${p.url}${a.slug}`);
  let quitting = false;
  const quit = () => {
    if (quitting) return;
    quitting = true;
    void p.stop().then(() => process.exit(0));
  };
  process.on('SIGINT', quit);
  process.on('SIGTERM', quit);
}

// `npm run portal:preview`: produkcijski build portala u lokalnom načinu
// (VIJESTI_AUTH_MODE=local, CLOUDFLARE_ENV=local → varijable shima upečene u
// wrangler.json) u `portal/dist-local/`, pa shim (8790) + `astro preview` (workerd)
// na 127.0.0.1:${VIJESTI_PORTAL_PORT:-4322}. Isti izlaz kao produkcija osim
// prijave i adresa, pa ga koriste e2e i Lighthouse. `--no-build` preskače build.
// Astro se pokreće programski: CLI iz agenta se sam odvaja u pozadinu.
import { fileURLToPath } from 'node:url';
import { startShim } from './serve-shim.js';

process.env.VIJESTI_AUTH_MODE = 'local';
process.env.CLOUDFLARE_ENV = 'local';
const port = Number(process.env.VIJESTI_PORTAL_PORT ?? 4322);
const root = fileURLToPath(new URL('..', import.meta.url));
const outDir = fileURLToPath(new URL('../dist-local/', import.meta.url));

const { build, preview } = await import('astro');
if (!process.argv.includes('--no-build')) {
  await build({ root, outDir, logLevel: 'warn' });
}
// Varijable okoline su već upečene u dist-local/server/wrangler.json; s
// CLOUDFLARE_ENV bi ih preview tražio ponovno pod `env.local` i upozoravao.
delete process.env.CLOUDFLARE_ENV;
const shim = await startShim();
const server = await preview({ root, outDir, logLevel: 'warn', server: { port, host: '127.0.0.1' } });
console.log(`[portal] preview http://127.0.0.1:${String(port)}/vijesti/  (shim :${String(shim.port)})`);

let quitting = false;
const quit = () => {
  if (quitting) return;
  quitting = true;
  void Promise.allSettled([server.stop(), shim.stop()]).then(() => process.exit(0));
};
process.on('SIGINT', quit);
process.on('SIGTERM', quit);

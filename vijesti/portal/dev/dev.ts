// `npm run portal:dev`: shim (8790) + `astro dev` (4321) nad lokalnim podacima,
// lažna prijava urednika (VIJESTI_AUTH_MODE=local, CLOUDFLARE_ENV=local). Astro
// se pokreće programski da proces ostane u prvom planu i da ga Ctrl+C ugasi.
import { fileURLToPath } from 'node:url';
import { startShim } from './serve-shim.js';

process.env.VIJESTI_AUTH_MODE = 'local';
process.env.CLOUDFLARE_ENV = 'local';
const port = Number(process.env.VIJESTI_PORTAL_PORT ?? 4321);
const root = fileURLToPath(new URL('..', import.meta.url));

const shim = await startShim();
const { dev } = await import('astro');
const server = await dev({ root, server: { port, host: '127.0.0.1' } });
console.log(`[portal] http://127.0.0.1:${String(port)}/vijesti/  (admin: /vijesti/admin, prijava: lokalni urednik)`);
for (const a of shim.articles()) console.log(`[portal] ${a.state.padEnd(9)} /vijesti/${a.slug}`);

const quit = () => {
  void Promise.allSettled([server.stop(), shim.stop()]).then(() => process.exit(0));
};
process.on('SIGINT', quit);
process.on('SIGTERM', quit);

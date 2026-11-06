// `npm run portal:shim`: lokalni PostgREST-shim + lažni CDN nad seedom
// (127.0.0.1:${VIJESTI_SHIM_PORT:-8790}). Gasi se na SIGINT/SIGTERM.
import { createRestShim, serveShim } from './rest-shim.js';
import { seededDb } from './seed.js';

export const DEFAULT_SHIM_PORT = 8790;

export async function startShim(port = Number(process.env.VIJESTI_SHIM_PORT ?? DEFAULT_SHIM_PORT)) {
  const { db, articles } = await seededDb();
  const shim = createRestShim({ db, reset: async () => (await seededDb()).db });
  const server = await serveShim(shim, port);
  const stop = async () => {
    await new Promise<void>((r) => {
      server.close(() => {
        r();
      });
    });
    await shim.db().close();
  };
  return { shim, server, articles, port, stop };
}

const isMain = import.meta.url === `file://${process.argv[1] ?? ''}`;
if (isMain) {
  const s = await startShim();
  console.log(`[shim] PostgREST http://127.0.0.1:${String(s.port)}/rest/v1, CDN http://127.0.0.1:${String(s.port)}/cdn`);
  for (const a of s.articles) console.log(`[shim] ${a.state.padEnd(9)} #${String(a.articleId)} /vijesti/${a.slug}`);
  const quit = () => {
    void s.stop().then(() => process.exit(0));
  };
  process.on('SIGINT', quit);
  process.on('SIGTERM', quit);
}

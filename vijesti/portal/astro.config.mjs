// Portal vijesti: Astro SSR na Cloudflare Workers, pod domovina.ai/vijesti (S6).
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import cloudflare from '@astrojs/cloudflare';
import { defineConfig } from 'astro/config';

// Način prijave u admin se odlučuje PRI BUILDU (odluka 606): `local` (lažna
// prijava za shim) ili `supabase` (zadano). Sve ostalo je greška, da tipfeler ne
// proizvede ni jedno ni drugo.
const authMode = process.env.VIJESTI_AUTH_MODE ?? 'supabase';
if (authMode !== 'local' && authMode !== 'supabase') {
  throw new Error(`VIJESTI_AUTH_MODE mora biti „local” ili „supabase”, ne „${authMode}”`);
}

// Produkcijski build ne smije tiho pustiti prazan impresum (odluka 710): nakon
// builda ista provjera kao `npm run portal:release-check` nad izlaznim
// wrangler.json. Upozorenje, a uz VIJESTI_RELEASE=1 build pada. Lokalni build
// (CLOUDFLARE_ENV=local, lažna prijava) se ne provjerava.
let outDir = null;
const releaseGuard = {
  name: 'vijesti-release-guard',
  hooks: {
    'astro:config:done': ({ config }) => {
      outDir = config.outDir;
    },
    'astro:build:done': () => {
      if (authMode !== 'supabase' || process.env.CLOUDFLARE_ENV || !outDir) return;
      const wrangler = fileURLToPath(new URL('server/wrangler.json', outDir));
      if (!existsSync(wrangler)) throw new Error(`release-guard: nema ${wrangler}`);
      const strict = process.env.VIJESTI_RELEASE === '1';
      const tsx = fileURLToPath(new URL('../node_modules/.bin/tsx', import.meta.url));
      const script = fileURLToPath(new URL('./dev/release-check.ts', import.meta.url));
      execFileSync(tsx, [script, wrangler, ...(strict ? [] : ['--warn'])], { stdio: 'inherit' });
    },
  },
};

export default defineConfig({
  output: 'server',
  base: '/vijesti',
  trailingSlash: 'ignore',
  // Bez sesija i bez obrade slika: adapter bi inače tražio KV i Images binding.
  session: false,
  build: { inlineStylesheets: 'always' },
  devToolbar: { enabled: false },
  adapter: cloudflare({ imageService: 'passthrough' }),
  integrations: [releaseGuard],
  vite: {
    define: { __VIJESTI_AUTH_MODE__: JSON.stringify(authMode) },
  },
});

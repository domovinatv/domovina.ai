// Portal vijesti: Astro SSR na Cloudflare Workers, pod domovina.ai/vijesti (S6).
import cloudflare from '@astrojs/cloudflare';
import { defineConfig } from 'astro/config';

// Način prijave u admin se odlučuje PRI BUILDU (odluka 606): `local` (lažna
// prijava za shim) ili `supabase` (zadano). Sve ostalo je greška, da tipfeler ne
// proizvede ni jedno ni drugo.
const authMode = process.env.VIJESTI_AUTH_MODE ?? 'supabase';
if (authMode !== 'local' && authMode !== 'supabase') {
  throw new Error(`VIJESTI_AUTH_MODE mora biti „local” ili „supabase”, ne „${authMode}”`);
}

export default defineConfig({
  output: 'server',
  base: '/vijesti',
  trailingSlash: 'ignore',
  // Bez sesija i bez obrade slika: adapter bi inače tražio KV i Images binding.
  session: false,
  build: { inlineStylesheets: 'always' },
  devToolbar: { enabled: false },
  adapter: cloudflare({ imageService: 'passthrough' }),
  vite: {
    define: { __VIJESTI_AUTH_MODE__: JSON.stringify(authMode) },
  },
});

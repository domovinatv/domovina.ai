// Odgovor XML ruta (sitemap, news sitemap, RSS): isti cache kao popisi (odluka
// 608), greška baze = 503 bez cachea, kao HTML stranice.
import { CACHE_ERROR, CACHE_LIST } from './cache.js';

export function xmlResponse(body: string, contentType: string): Response {
  return new Response(body, {
    status: 200,
    headers: { 'content-type': `${contentType}; charset=utf-8`, 'cache-control': CACHE_LIST },
  });
}

export function xmlError(what: string, e: unknown): Response {
  console.error(`[vijesti] ${what}:`, e);
  return new Response('Privremeno nedostupno.\n', {
    status: 503,
    headers: { 'content-type': 'text/plain; charset=utf-8', 'cache-control': CACHE_ERROR, 'retry-after': '60' },
  });
}

// `fetch` koji zahtjev predaje shimu u istom procesu (testovi bez mreže).
import type { FetchFn } from '../src/lib/rest.js';
import type { RestShim } from './rest-shim.js';

export function fetchViaShim(shim: RestShim): FetchFn {
  return async (input, init) => {
    const u = new URL(input);
    const headers: Record<string, string> = {};
    for (const [k, v] of Object.entries((init?.headers ?? {}) as Record<string, string>)) headers[k.toLowerCase()] = v;
    const res = await shim.handle({
      method: init?.method ?? 'GET',
      url: u.pathname + u.search,
      headers,
      body: typeof init?.body === 'string' ? init.body : '',
    });
    const body = typeof res.body === 'string' ? res.body : new Uint8Array(res.body);
    return new Response(body, { status: res.status, headers: res.headers });
  };
}

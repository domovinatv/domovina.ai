// Testovi nikad ne idu na mrežu (odluka 6). Globalni fetch baca; sve što
// treba CDN ili Gemini dobiva injektiran lažni fetch.
export class NetworkDisabledError extends Error {
  constructor(url: string) {
    super(`mreža je u testovima isključena: ${url}`);
    this.name = 'NetworkDisabledError';
  }
}

function blockedFetch(input: unknown): Promise<Response> {
  const url =
    typeof input === 'string' ? input : input instanceof URL ? input.href : '[Request]';
  return Promise.reject(new NetworkDisabledError(url));
}

globalThis.fetch = blockedFetch;

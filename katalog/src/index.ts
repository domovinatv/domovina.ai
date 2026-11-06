import { handleIngest, handleIngestIds } from "./api/ingest.ts";
import { API_PREFIX } from "./api/prefix.ts";
import { errorResponse, handleV1, internalErrorResponse, jsonResponse } from "./api/v1.ts";
import type { Env } from "./env.js";

// Glavni modul izvozi SAMO handler: workerd svaki imenovani export čita kao
// entrypoint (funkcija, klasa ili ExportedHandler), pa konstanta ovdje ruši
// `wrangler dev` dok ga vitest pool ne primijeti (odluka 312).

async function route(request: Request, url: URL, env: Env, ctx: ExecutionContext): Promise<Response> {
  const { pathname } = url;
  if (!pathname.startsWith(`${API_PREFIX}/`)) return errorResponse(404, "not_found");
  const rest = pathname.slice(API_PREFIX.length + 1);
  // Jedina ruta koja nije GET (odluka 603); sve ostale metode su 404 (odluka 308).
  if (request.method === "POST" && rest === "ingest") return handleIngest(request, url, env);
  if (request.method !== "GET") return errorResponse(404, "not_found");
  if (rest === "health") {
    return jsonResponse({ ok: true, service: "katalog", version: 1 }, 200, "no-store");
  }
  if (rest === "ingest/ids") return handleIngestIds(request, url, env);
  return handleV1(url, rest, env, ctx);
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    // Svaka iznimka (D1, cache, bug) → 500 `internal` s CORS i `no-store`.
    // U Cache API ide samo 200 iz `handleV1`, pa se ni ovaj odgovor ne sprema.
    try {
      return await route(request, url, env, ctx);
    } catch (err) {
      return internalErrorResponse(err, url);
    }
  },
} satisfies ExportedHandler<Env>;

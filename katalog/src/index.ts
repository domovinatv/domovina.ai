import { API_PREFIX } from "./api/prefix.ts";
import { errorResponse, handleV1, jsonResponse } from "./api/v1.ts";
import type { Env } from "./env.js";

// Glavni modul izvozi SAMO handler: workerd svaki imenovani export čita kao
// entrypoint (funkcija, klasa ili ExportedHandler), pa konstanta ovdje ruši
// `wrangler dev` dok ga vitest pool ne primijeti (odluka 312).

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const { pathname } = url;

    if (request.method !== "GET" || !pathname.startsWith(`${API_PREFIX}/`)) {
      return errorResponse(404, "not_found");
    }
    const rest = pathname.slice(API_PREFIX.length + 1);
    if (rest === "health") {
      return jsonResponse({ ok: true, service: "katalog", version: 1 }, 200, "no-store");
    }
    return handleV1(url, rest, env, ctx);
  },
} satisfies ExportedHandler<Env>;

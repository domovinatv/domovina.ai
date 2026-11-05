import type { Env } from "./env.js";

export const API_PREFIX = "/api/katalog/v1";

const JSON_HEADERS = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
} as const;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}

export default {
  fetch(request: Request): Response {
    const { pathname } = new URL(request.url);

    if (request.method === "GET" && pathname === `${API_PREFIX}/health`) {
      return json({ ok: true, service: "katalog", version: 1 });
    }

    return json({ ok: false, error: "not_found" }, 404);
  },
} satisfies ExportedHandler<Env>;

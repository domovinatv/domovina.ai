// Lažni PostgREST za poglede postavki domovina-api: dovoljno filtara da poller
// ide istim putem kao prema pravom izvoru (gte kursor, keyset `or=(…)`,
// `limit`, `in.(…)`). Bez mreže: `fetch` se predaje polleru.

export interface FakeSettings {
  youtube_channel_id: string;
  effective: Record<string, unknown>;
  updated_at: string;
  tombstoned: boolean;
}

export interface FakeTombstone {
  youtube_channel_id: string;
  channel_title: string | null;
  slugs: string[];
  requested_at: string | null;
  phone_confirmed_at: string | null;
  deleted_at: string;
}

export interface FakeSource {
  settings: FakeSettings[];
  tombstones: FakeTombstone[];
  /** Kad je postavljen, svaki zahtjev vraća taj status. */
  failWith?: number;
  readonly requests: { url: URL; headers: Headers }[];
  readonly fetch: typeof fetch;
}

/** Vrijeme do mikrosekunde kao broj (Date.parse reže na milisekunde). */
export function instantKey(s: string): number {
  const frac = /\.(\d+)/.exec(s)?.[1] ?? "";
  const base = Date.parse(s.replace(/\.\d+/, ""));
  return base * 1000 + Number(frac.padEnd(6, "0").slice(0, 6));
}

function unquote(v: string): string {
  return v.startsWith('"') && v.endsWith('"') ? v.slice(1, -1).replaceAll('\\"', '"').replaceAll("\\\\", "\\") : v;
}

const OR_KEYSET = /^\(updated_at\.gt\.(".*?"),and\(updated_at\.eq\.(".*?"),youtube_channel_id\.gt\.([^)]+)\)\)$/;

export function fakeSource(init: { settings?: FakeSettings[]; tombstones?: FakeTombstone[] } = {}): FakeSource {
  const src: FakeSource = {
    settings: init.settings ?? [],
    tombstones: init.tombstones ?? [],
    requests: [],
    fetch: (input: RequestInfo | URL, reqInit?: RequestInit): Promise<Response> => {
      const url = new URL(input instanceof Request ? input.url : String(input));
      src.requests.push({ url, headers: new Headers(reqInit?.headers) });
      if (src.failWith !== undefined) return Promise.resolve(new Response("upstream", { status: src.failWith }));
      const p = url.searchParams;
      if (url.pathname.endsWith("/public_channel_settings")) {
        let rows = [...src.settings].sort(
          (a, b) => instantKey(a.updated_at) - instantKey(b.updated_at) || (a.youtube_channel_id < b.youtube_channel_id ? -1 : 1),
        );
        const gte = p.get("updated_at");
        if (gte !== null) {
          if (!gte.startsWith("gte.")) throw new Error(`nepoznat filtar ${gte}`);
          const since = instantKey(gte.slice(4));
          rows = rows.filter((r) => instantKey(r.updated_at) >= since);
        }
        const or = p.get("or");
        if (or !== null) {
          const m = OR_KEYSET.exec(or);
          if (m === null) throw new Error(`nepoznat or ${or}`);
          const t = instantKey(unquote(m[1] ?? ""));
          const uc = m[3] ?? "";
          rows = rows.filter((r) => {
            const k = instantKey(r.updated_at);
            return k > t || (k === t && r.youtube_channel_id > uc);
          });
        }
        rows = rows.slice(0, Number(p.get("limit") ?? "1000"));
        return Promise.resolve(Response.json(rows));
      }
      if (url.pathname.endsWith("/public_channel_tombstones")) {
        const inF = /^in\.\((.*)\)$/.exec(p.get("youtube_channel_id") ?? "");
        const wanted = new Set((inF?.[1] ?? "").split(","));
        return Promise.resolve(Response.json(src.tombstones.filter((t) => wanted.has(t.youtube_channel_id))));
      }
      return Promise.resolve(new Response("not found", { status: 404 }));
    },
  };
  return src;
}

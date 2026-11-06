// Latencija stagingova API-ja s ovog stroja, naspram CDN-a (S5).
//
//   npm run latency
//   npm run latency -- --reps 50 --base https://domovina-katalog-staging.d-o-m.workers.dev
//
// Za svaku rutu dva niza od `--reps` uzastopnih zahtjeva:
//   miss — svaki zahtjev ima DRUGI ključ cachea (druga epizoda, drugi kanal, drugi
//          dan, drugi `limit`), pa mjeri Worker + D1. Ključevi su stvarni podaci
//          dohvaćeni na početku (popis kanala i epizoda velikih kanala uz
//          `limit=100`, koji se ne mjeri). Uzorak koji ipak dođe kao `hit`
//          (ponovljeno pokretanje unutar TTL-a) broji se zasebno i ne ulazi u miss.
//   hit  — isti ključ, nakon zagrijavanja do prvog `x-katalog-cache: hit`.
// Usporedba: `cdn.domovina.ai/channels/data/home.json` i listing velikog kanala,
// isti broj zahtjeva.
//
// Veza: `fetch` (undici) drži keep-alive, pa je TLS + DNS samo u prvom zahtjevu
// prema hostu; taj se zahtjev bilježi zasebno („prvi zahtjev”) i ne ulazi u nizove.
// Vrijeme je do zadnjeg bajta tijela. `cf-ray` daje podatkovni centar.
//
// Broj zahtjeva: ~2 + 2 (otkrivanje) + 4 × 2 × reps + reps (health) + 2 × reps + zagrijavanje,
// uz reps 50 oko 670. Ponovljeno pokretanje unutar sata (TTL Worker cachea) daje
// hit i u miss nizu; pravi miss traži novu verziju kataloga (novi uvoz). Izlaz: JSON u `--out` (zadano `.wrangler/measure/latency-<ts>.json`)
// i tablica na stdout.
//
// Node 24+ (type stripping).
import { mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { parseArgs } from "node:util";

const { values: args } = parseArgs({
  options: {
    base: { type: "string", default: "https://domovina-katalog-staging.d-o-m.workers.dev" },
    cdn: { type: "string", default: "https://cdn.domovina.ai" },
    reps: { type: "string", default: "50" },
    out: { type: "string" },
  },
});

const REPS = Number(args.reps);
if (!Number.isInteger(REPS) || REPS < 5) throw new Error(`--reps mora biti cijeli broj ≥ 5, ne ${args.reps}`);
const API = `${args.base}/api/katalog/v1`;
const CDN = args.cdn;

interface Sample {
  readonly url: string;
  readonly status: number;
  readonly ms: number;
  readonly bytes: number;
  readonly cache: string | null;
  readonly colo: string | null;
}

async function get(url: string): Promise<Sample> {
  const t0 = performance.now();
  const res = await fetch(url, { headers: { "accept-encoding": "gzip, br" } });
  const buf = await res.arrayBuffer();
  const ms = performance.now() - t0;
  const ray = res.headers.get("cf-ray");
  return {
    url,
    status: res.status,
    ms,
    bytes: buf.byteLength,
    cache: res.headers.get("x-katalog-cache") ?? res.headers.get("cf-cache-status"),
    colo: ray?.split("-").pop() ?? null,
  };
}

async function json<T>(url: string): Promise<T> {
  const res = await fetch(url);
  if (res.status !== 200) throw new Error(`${url} → ${res.status}`);
  return (await res.json());
}

interface Stats {
  readonly n: number;
  readonly p50: number;
  readonly p95: number;
  readonly min: number;
  readonly max: number;
  readonly mean: number;
}

function stats(xs: readonly number[]): Stats {
  const s = [...xs].sort((a, b) => a - b);
  const q = (p: number): number => s[Math.min(s.length - 1, Math.max(0, Math.ceil(p * s.length) - 1))] ?? NaN;
  const r = (x: number): number => Math.round(x * 10) / 10;
  return {
    n: s.length,
    p50: r(q(0.5)),
    p95: r(q(0.95)),
    min: r(s[0] ?? NaN),
    max: r(s[s.length - 1] ?? NaN),
    mean: r(s.reduce((a, b) => a + b, 0) / Math.max(1, s.length)),
  };
}

interface Series {
  readonly stats: Stats;
  /** Brojanje po vrijednosti `x-katalog-cache` / `cf-cache-status`. */
  readonly cache: Record<string, number>;
  readonly colo: Record<string, number>;
  readonly bytesMedian: number;
  readonly status: Record<string, number>;
}

function count(xs: readonly (string | null)[]): Record<string, number> {
  const out: Record<string, number> = {};
  for (const x of xs) out[x ?? "—"] = (out[x ?? "—"] ?? 0) + 1;
  return out;
}

function series(samples: readonly Sample[]): Series {
  const b = samples.map((s) => s.bytes).sort((x, y) => x - y);
  return {
    stats: stats(samples.map((s) => s.ms)),
    cache: count(samples.map((s) => s.cache)),
    colo: count(samples.map((s) => s.colo)),
    bytesMedian: b[Math.floor(b.length / 2)] ?? 0,
    status: count(samples.map((s) => String(s.status))),
  };
}

async function run(urls: readonly string[]): Promise<Sample[]> {
  const out: Sample[] = [];
  for (const u of urls) out.push(await get(u));
  return out;
}

async function hitSeries(url: string): Promise<{ samples: Sample[]; warmups: number }> {
  let warmups = 0;
  let s = await get(url);
  while (s.cache !== "hit" && warmups < 30) {
    warmups++;
    s = await get(url);
  }
  if (s.cache !== "hit") throw new Error(`${url}: nema hita ni nakon 30 pokušaja`);
  return { samples: await run(Array.from({ length: REPS }, () => url)), warmups };
}

// --- otkrivanje stvarnih ključeva ---------------------------------------------

interface ChannelItem {
  readonly slug: string;
  readonly processed_count: number;
}
interface EpisodeItem {
  readonly id: string;
  readonly date: string | null;
}
interface Page<T> {
  readonly items: T[];
  readonly next: string | null;
}

const first: Record<string, Sample> = {};
first.api = await get(`${API}/health`);
first.cdn = await get(`${CDN}/channels/data/home.json`);

const channels: ChannelItem[] = [];
for (let cursor: string | null = null, i = 0; i === 0 || (cursor && i < 5); i++) {
  const page: Page<ChannelItem> = await json(`${API}/channels?limit=100${cursor ? `&cursor=${cursor}` : ""}`);
  channels.push(...page.items);
  cursor = page.next;
}
const big = [...channels].sort((a, b) => b.processed_count - a.processed_count);
const withEpisodes = big.filter((c) => c.processed_count > 0);
if (withEpisodes.length < REPS) throw new Error(`samo ${withEpisodes.length} kanala s epizodama, treba ${REPS}`);

const episodes: EpisodeItem[] = [];
for (const c of big.slice(0, 4)) {
  const page: Page<EpisodeItem> = await json(`${API}/channels/${encodeURIComponent(c.slug)}/episodes?limit=100`);
  episodes.push(...page.items);
}
const ids = [...new Set(episodes.map((e) => e.id))];
const dates = [...new Set(episodes.map((e) => e.date).filter((d): d is string => d !== null))].sort().reverse();
if (ids.length < REPS + 1 || dates.length < REPS + 1) {
  throw new Error(`premalo ključeva: ${ids.length} epizoda, ${dates.length} dana`);
}

const today = new Date().toISOString().slice(0, 10);
const diva = big[0]?.slug;
const hitId = ids[0];
if (diva === undefined || hitId === undefined) throw new Error("nema kanala ili epizoda");
const L = 30;

// Miss ključevi: hit ključ (prvi) se NE koristi u miss nizu.
const routes = {
  [`days/${today}`]: {
    // Današnji dan je jedan ključ; za miss uzimamo druge dane istog oblika.
    miss: dates.slice(1, REPS + 1).map((d) => `${API}/days/${d}?limit=${L}`),
    hit: `${API}/days/${today}?limit=${L}`,
  },
  [`channels/:slug/episodes`]: {
    miss: withEpisodes.slice(1, REPS + 1).map((c) => `${API}/channels/${encodeURIComponent(c.slug)}/episodes?limit=${L}`),
    hit: `${API}/channels/${encodeURIComponent(diva)}/episodes?limit=${L}`,
  },
  [`episodes/:id/card`]: {
    miss: ids.slice(1, REPS + 1).map((id) => `${API}/episodes/${encodeURIComponent(id)}/card`),
    hit: `${API}/episodes/${encodeURIComponent(hitId)}/card`,
  },
  [`channels`]: {
    // Jedan popis; miss kroz različit `limit` (poznat parametar, dio ključa).
    miss: Array.from({ length: REPS }, (_, i) => `${API}/channels?limit=${L + 1 + i}`),
    hit: `${API}/channels?limit=${L}`,
  },
} as const;

const result: Record<string, unknown> = {
  at: new Date().toISOString(),
  base: args.base,
  reps: REPS,
  first: Object.fromEntries(Object.entries(first).map(([k, s]) => [k, { ms: Math.round(s.ms), colo: s.colo, url: s.url }])),
  routes: {},
  cdn: {},
};

for (const [name, r] of Object.entries(routes)) {
  const missRaw = await run(r.miss);
  const miss = missRaw.filter((s) => s.cache === "miss");
  const missWasHit = missRaw.length - miss.length;
  const hit = await hitSeries(r.hit);
  (result.routes as Record<string, unknown>)[name] = {
    miss: series(miss),
    missWasHit,
    hit: series(hit.samples),
    warmups: hit.warmups,
  };
}

// Worker bez D1 i bez cachea: razlika prema hitu = jedno putovanje do D1 (upit konteksta).
result.health = series(await run(Array.from({ length: REPS }, () => `${API}/health`)));

const cdnUrls = {
  "home.json": `${CDN}/channels/data/home.json`,
  [`${diva}.json (listing)`]: `${CDN}/channels/data/${diva}.json`,
};
for (const [name, u] of Object.entries(cdnUrls)) {
  await get(u); // zagrijavanje edge cachea
  (result.cdn as Record<string, unknown>)[name] = series(await run(Array.from({ length: REPS }, () => u)));
}

const out = args.out ?? `.wrangler/measure/latency-${result.at as string}.json`.replaceAll(":", "-");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify(result, null, 2));

const row = (name: string, s: Series): string =>
  `${name.padEnd(44)} n=${String(s.stats.n).padStart(3)}  p50 ${String(s.stats.p50).padStart(6)}  p95 ${String(s.stats.p95).padStart(6)}  max ${String(s.stats.max).padStart(6)} ms  ${String(s.bytesMedian).padStart(7)} B  ${JSON.stringify(s.cache)} ${JSON.stringify(s.colo)}`;
console.log(`prvi zahtjev (TLS+DNS): API ${Math.round(first.api.ms)} ms, CDN ${Math.round(first.cdn.ms)} ms`);
for (const [name, v] of Object.entries(result.routes as Record<string, { miss: Series; hit: Series; missWasHit: number }>)) {
  console.log(row(`${name} miss`, v.miss) + (v.missWasHit ? `  (+${v.missWasHit} hit izbačeno)` : ""));
  console.log(row(`${name} hit`, v.hit));
}
console.log(row("health (Worker bez D1)", result.health as Series));
for (const [name, s] of Object.entries(result.cdn as Record<string, Series>)) console.log(row(`CDN ${name}`, s));
console.log(`→ ${out}`);

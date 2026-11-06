// Mjerenje sintetičkog (ili bilo kojeg lokalnog) kataloga, S4.
//
//   npm run measure -- --persist .wrangler/synth-1m
//   npm run measure -- --persist .wrangler/synth-10k --reps 30 --deep 20 --port 8799
//   npm run measure -- --persist .wrangler/synth-10k --no-serve   # wrangler dev već radi na --port
//
// Dva dijela:
//   (a) SQLite datoteka lokalnog D1 (samo čitanje): `page_count`, `page_size`,
//       `freelist_count`, `dbstat` po tablici/indeksu, broj redaka, bajtova po
//       epizodi (s indeksima).
//   (b) API nad `wrangler dev --local --persist-to <dir>` (skripta ga sama digne
//       i ugasi): za svaku rutu `meta.rows_read` i trajanje (p50/p95 preko
//       `--reps` ponavljanja) na prvoj i dubokoj stranici (slijedi `next`
//       `--deep` puta), limit 20 i 100.
//
// Cache: ključ cachea nosi origin (odluka 307, 314 d), pa svako ponavljanje
// MISS-a ide s drugim `Host` zaglavljem (`m<i>.measure.test`; host nije u
// `brands`, pa brend daje `DEFAULT_BRAND`). HIT se mjeri zasebno: isti host,
// nakon zagrijavanja. Na pravom edgeu `Host` je ruta zone, pa je ovo samo
// lokalni trik. `meta.rows_read` u tijelu HIT-a je iz izračuna koji je zapis
// stvorio; stvarni D1 trošak HIT-a je samo upit konteksta (2–3, odluka 305).
//
// Trajanje je lokalno: Node → wrangler dev → workerd → SQLite na Macu. To NIJE
// latencija D1 na edgeu; mjerodavna je ona sa staginga (S5).
//
// Izlaz: JSON u `--out` (zadano `.wrangler/measure/<ime persist direktorija>.json`)
// i čitljiva tablica na stdout.
//
// Node 24+ (type stripping).
import { type ChildProcess, spawn } from "node:child_process";
import { existsSync, mkdirSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { Agent, request } from "node:http";
import { basename, dirname, join, relative, resolve } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const KATALOG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const PREFIX = "/api/katalog/v1";
const LIMITS = [20, 100] as const;

function fail(msg: string): never {
  console.error(`measure: ${msg}`);
  process.exit(2);
}

// ---- (a) SQLite ------------------------------------------------------------

interface ObjectSize {
  readonly name: string;
  readonly type: "table" | "index";
  readonly table: string;
  readonly bytes: number;
  readonly pages: number;
}

interface Storage {
  readonly file: string;
  readonly fileBytes: number;
  readonly pageSize: number;
  readonly pageCount: number;
  readonly freelistCount: number;
  readonly usedBytes: number;
  readonly objects: readonly ObjectSize[] | null;
  readonly rows: {
    readonly episodes: number;
    readonly episodesListed: number;
    readonly variants: number;
    readonly channels: number;
    readonly channelsProcessed: number;
  };
  /** (page_count − freelist) × page_size / epizoda: cijela baza s indeksima. */
  readonly bytesPerEpisode: number;
  /** Samo `episodes` + njeni indeksi (iz `dbstat`), po epizodi. */
  readonly episodeBytesPerEpisode: number | null;
  /** Samo `channels` + njeni indeksi, po kanalu. */
  readonly channelBytesPerChannel: number | null;
}

interface Targets {
  readonly hotDay: { readonly date: string; readonly episodes: number };
  readonly diva: { readonly slug: string; readonly episodes: number };
  readonly small: { readonly slug: string; readonly episodes: number };
  readonly cardId: string;
}

function sqliteFile(dir: string): string {
  const d1 = join(dir, "v3", "d1", "miniflare-D1DatabaseObject");
  const files = existsSync(d1) ? readdirSync(d1).filter((f) => f.endsWith(".sqlite") && f !== "metadata.sqlite") : [];
  if (files.length !== 1) fail(`u ${d1} očekujem jednu .sqlite datoteku, ima ih ${files.length}`);
  return join(d1, files[0] ?? "");
}

function num(db: DatabaseSync, sql: string): number {
  const row = db.prepare(sql).get() as Record<string, unknown> | undefined;
  const v = row === undefined ? undefined : Object.values(row)[0];
  if (typeof v !== "number") fail(`upit nije vratio broj: ${sql}`);
  return v;
}

function readStorage(file: string): { storage: Storage; targets: Targets } {
  const db = new DatabaseSync(file, { readOnly: true });
  const pageSize = num(db, "PRAGMA page_size");
  const pageCount = num(db, "PRAGMA page_count");
  const freelistCount = num(db, "PRAGMA freelist_count");
  const usedBytes = (pageCount - freelistCount) * pageSize;

  let objects: ObjectSize[] | null = null;
  try {
    const schema = new Map<string, { type: string; table: string }>();
    for (const r of db.prepare("SELECT name, type, tbl_name FROM sqlite_schema").all() as {
      name: string;
      type: string;
      tbl_name: string;
    }[]) {
      schema.set(r.name, { type: r.type, table: r.tbl_name });
    }
    const rows = db
      .prepare("SELECT name, sum(pgsize) AS bytes, count(*) AS pages FROM dbstat GROUP BY name ORDER BY bytes DESC")
      .all() as { name: string; bytes: number; pages: number }[];
    objects = rows.map((r) => {
      const s = schema.get(r.name);
      // sqlite_autoindex_<tablica>_N: PK/UNIQUE; za WITHOUT ROWID tablicu PK je sama tablica
      // i nema zaseban unos u dbstat, pa ovdje ostaju samo dodatni autoindeksi.
      const auto = /^sqlite_autoindex_(.+)_\d+$/.exec(r.name);
      const type: "table" | "index" = s?.type === "table" || r.name === "sqlite_schema" ? "table" : "index";
      const table = s?.table ?? auto?.[1] ?? r.name;
      return { name: r.name, type, table, bytes: r.bytes, pages: r.pages };
    });
  } catch {
    objects = null; // SQLite bez SQLITE_ENABLE_DBSTAT_VTAB
  }

  const episodes = num(db, "SELECT count(*) FROM episodes");
  const variants = num(db, "SELECT count(*) FROM episodes WHERE variant_of IS NOT NULL");
  const episodesListed = num(
    db,
    "SELECT count(*) FROM episodes WHERE variant_of IS NULL AND published_date IS NOT NULL",
  );
  const channels = num(db, "SELECT count(*) FROM channels");
  const channelsProcessed = num(db, "SELECT count(*) FROM channels WHERE processed_count >= 1");
  if (episodes === 0) fail("baza nema epizoda");

  const sumFor = (table: string): number | null =>
    objects === null ? null : objects.filter((o) => o.table === table).reduce((s, o) => s + o.bytes, 0);
  const epBytes = sumFor("episodes");
  const chBytes = sumFor("channels");

  // Ciljevi mjerenja: najveći dan, najveći kanal (div), mali kanal, jedna kartica.
  const hot = db
    .prepare(
      `SELECT published_date AS date, count(*) AS n FROM episodes INDEXED BY episodes_by_date
       WHERE variant_of IS NULL AND published_date IS NOT NULL GROUP BY brand, published_date ORDER BY n DESC LIMIT 1`,
    )
    .get() as { date: string; n: number } | undefined;
  const diva = db
    .prepare("SELECT slug, processed_count AS n FROM channels ORDER BY processed_count DESC, slug LIMIT 1")
    .get() as { slug: string; n: number } | undefined;
  const small = db
    .prepare(
      "SELECT slug, processed_count AS n FROM channels WHERE processed_count BETWEEN 1 AND 2 ORDER BY slug LIMIT 1",
    )
    .get() as { slug: string; n: number } | undefined;
  const card = db
    .prepare("SELECT id FROM episodes WHERE id >= 'M' AND variant_of IS NULL ORDER BY brand, id LIMIT 1")
    .get() as { id: string } | undefined;
  db.close();
  if (hot === undefined || diva === undefined || small === undefined || card === undefined) {
    fail("nema dana, kanala ili epizode za mjerenje");
  }

  return {
    storage: {
      file,
      fileBytes: statSync(file).size,
      pageSize,
      pageCount,
      freelistCount,
      usedBytes,
      objects,
      rows: { episodes, episodesListed, variants, channels, channelsProcessed },
      bytesPerEpisode: usedBytes / episodes,
      episodeBytesPerEpisode: epBytes === null ? null : epBytes / episodes,
      channelBytesPerChannel: chBytes === null || channels === 0 ? null : chBytes / channels,
    },
    targets: {
      hotDay: { date: hot.date, episodes: hot.n },
      diva: { slug: diva.slug, episodes: diva.n },
      small: { slug: small.slug, episodes: small.n },
      cardId: card.id,
    },
  };
}

// ---- (b) API ---------------------------------------------------------------

interface Got {
  readonly status: number;
  readonly cache: string | null;
  readonly ms: number;
  readonly body: { items?: unknown[]; next?: string | null; meta?: { rows_read?: number } } | null;
}

const agent = new Agent({ keepAlive: true, maxSockets: 1 });

function get(port: number, path: string, host: string): Promise<Got> {
  return new Promise((ok, ko) => {
    const t0 = performance.now();
    const req = request({ host: "127.0.0.1", port, path, agent, headers: { host } }, (res) => {
      const chunks: Buffer[] = [];
      res.on("data", (c: Buffer) => chunks.push(c));
      res.on("end", () => {
        const ms = performance.now() - t0;
        const text = Buffer.concat(chunks).toString("utf8");
        let body: Got["body"];
        try {
          body = JSON.parse(text) as Got["body"];
        } catch {
          body = null;
        }
        const cache = res.headers["x-katalog-cache"];
        ok({ status: res.statusCode ?? 0, cache: typeof cache === "string" ? cache : null, ms, body });
      });
      res.on("error", ko);
    });
    req.on("error", ko);
    req.end();
  });
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
  const r = (x: number): number => Math.round(x * 100) / 100;
  return {
    n: s.length,
    p50: r(q(0.5)),
    p95: r(q(0.95)),
    min: r(s[0] ?? NaN),
    max: r(s[s.length - 1] ?? NaN),
    mean: r(s.reduce((a, b) => a + b, 0) / Math.max(1, s.length)),
  };
}

let hostSeq = 0;
const missHost = (): string => `m${++hostSeq}.measure.test`;

interface Timing {
  readonly miss: Stats;
  readonly hit: Stats;
  /** Koliko „miss” ponavljanja je ipak dobilo `hit` (mora biti 0). */
  readonly missWasHit: number;
}

async function timing(port: number, path: string, reps: number): Promise<Timing> {
  const miss: number[] = [];
  let missWasHit = 0;
  for (let i = 0; i < reps; i++) {
    const g = await get(port, path, missHost());
    if (g.status !== 200) fail(`${path} → ${g.status}`);
    if (g.cache !== "miss") missWasHit++;
    miss.push(g.ms);
  }
  // Zagrijavanje: upis u cache ide kroz waitUntil, pa se ponavlja do prvog hita.
  const host = `hit${++hostSeq}.measure.test`;
  let warm = await get(port, path, host);
  for (let i = 0; i < 50 && warm.cache !== "hit"; i++) warm = await get(port, path, host);
  if (warm.cache !== "hit") fail(`${path}: cache nije dao hit ni nakon 50 pokušaja`);
  const hit: number[] = [];
  for (let i = 0; i < reps; i++) {
    const g = await get(port, path, host);
    if (g.cache !== "hit") fail(`${path}: očekivan hit, dobiven ${g.cache ?? "bez zaglavlja"}`);
    hit.push(g.ms);
  }
  return { miss: stats(miss), hit: stats(hit), missWasHit };
}

interface Walk {
  /** `rows_read`, broj stavki i putanja po stranici, redom. */
  readonly pages: readonly { readonly rowsRead: number; readonly items: number; readonly path: string }[];
  readonly reachedEnd: boolean;
}

async function walk(port: number, path: string, maxPages: number): Promise<Walk> {
  const pages: { rowsRead: number; items: number; path: string }[] = [];
  let current = path;
  for (let i = 0; i < maxPages; i++) {
    const g = await get(port, current, missHost());
    if (g.status !== 200 || g.body === null) fail(`${current} → ${g.status}`);
    const rr = g.body.meta?.rows_read;
    if (typeof rr !== "number") fail(`${current}: nema meta.rows_read`);
    pages.push({ rowsRead: rr, items: g.body.items?.length ?? 0, path: current });
    const next = g.body.next;
    if (typeof next !== "string") return { pages, reachedEnd: true };
    const sep = path.includes("?") ? "&" : "?";
    current = `${path}${sep}cursor=${encodeURIComponent(next)}`;
  }
  return { pages, reachedEnd: false };
}

interface Case {
  readonly name: string;
  readonly path: string;
  readonly paginated: boolean;
  /** Najviše stranica za duboku stranicu (zadano `--deep`). */
  readonly maxPages?: number;
}

interface CaseResult {
  readonly name: string;
  readonly limit: number | null;
  readonly path: string;
  readonly first: { readonly rowsRead: number; readonly items: number; readonly timing: Timing };
  readonly deep: {
    readonly depthPages: number;
    readonly depthItems: number;
    readonly reachedEnd: boolean;
    readonly rowsRead: number;
    readonly items: number;
    /** `rows_read` zadnje dohvaćene stranice (na kraju popisa je kratka). */
    readonly lastPage: number;
    /** Najveći `rows_read` na bilo kojoj stranici prolaza. */
    readonly maxRowsRead: number;
    readonly timing: Timing;
  } | null;
}

function cases(t: Targets, limit: number, deep: number): Case[] {
  const q = `?limit=${limit}`;
  return [
    { name: "days (vrući dan)", path: `${PREFIX}/days/${t.hotDay.date}${q}`, paginated: true },
    { name: "channels", path: `${PREFIX}/channels${q}`, paginated: true },
    { name: "channels?tier=1", path: `${PREFIX}/channels${q}&tier=1`, paginated: true },
    { name: "channels?tier=2", path: `${PREFIX}/channels${q}&tier=2`, paginated: true },
    { name: "directory", path: `${PREFIX}/directory${q}`, paginated: true },
    {
      name: "channels/:div/episodes",
      path: `${PREFIX}/channels/${encodeURIComponent(t.diva.slug)}/episodes${q}`,
      paginated: true,
      // Div se prolista do kraja (limit 100: ~30 stranica na 1M), ostalo do `--deep`.
      maxPages: Math.max(deep, Math.ceil(t.diva.episodes / limit) + 1),
    },
    {
      name: "channels/:mali/episodes",
      path: `${PREFIX}/channels/${encodeURIComponent(t.small.slug)}/episodes${q}`,
      paginated: true,
    },
  ];
}

function singleCases(t: Targets): Case[] {
  return [
    { name: "channels/:div", path: `${PREFIX}/channels/${encodeURIComponent(t.diva.slug)}`, paginated: false },
    { name: "channels/:mali", path: `${PREFIX}/channels/${encodeURIComponent(t.small.slug)}`, paginated: false },
    { name: "episodes/:id/card", path: `${PREFIX}/episodes/${encodeURIComponent(t.cardId)}/card`, paginated: false },
  ];
}

async function runCase(port: number, c: Case, limit: number | null, reps: number, deep: number): Promise<CaseResult> {
  if (!c.paginated) {
    const g = await get(port, c.path, missHost());
    const rr = g.body?.meta?.rows_read;
    if (g.status !== 200 || typeof rr !== "number") fail(`${c.path} → ${g.status}`);
    return { name: c.name, limit, path: c.path, first: { rowsRead: rr, items: 1, timing: await timing(port, c.path, reps) }, deep: null };
  }
  const w = await walk(port, c.path, c.maxPages ?? deep);
  const first = w.pages[0];
  if (first === undefined) fail(`${c.path}: nema stranica`);
  // Duboka stranica = najdublja PUNA stranica (zadnja kratka stranica čita manje i ne govori ništa o dubini).
  const full = limit ?? 0;
  let deepIdx = -1;
  for (let i = w.pages.length - 1; i > 0; i--) {
    if (w.pages[i]?.items === full) {
      deepIdx = i;
      break;
    }
  }
  const last = deepIdx > 0 ? w.pages[deepIdx] : undefined;
  const firstTiming = await timing(port, c.path, reps);
  const deepResult =
    last !== undefined
      ? {
          depthPages: deepIdx,
          depthItems: w.pages.slice(0, deepIdx).reduce((s, p) => s + p.items, 0),
          reachedEnd: w.reachedEnd,
          rowsRead: last.rowsRead,
          items: last.items,
          maxRowsRead: Math.max(...w.pages.map((p) => p.rowsRead)),
          lastPage: w.pages[w.pages.length - 1]?.rowsRead ?? 0,
          timing: await timing(port, last.path, reps),
        }
      : null;
  return { name: c.name, limit, path: c.path, first: { rowsRead: first.rowsRead, items: first.items, timing: firstTiming }, deep: deepResult };
}

// ---- wrangler dev ----------------------------------------------------------

async function startDev(dir: string, port: number): Promise<ChildProcess> {
  const wrangler = join(KATALOG, "node_modules", ".bin", "wrangler");
  const child = spawn(wrangler, ["dev", "--local", "--persist-to", dir, "--port", String(port), "--show-interactive-dev-session=false"], {
    cwd: KATALOG,
    stdio: ["ignore", "ignore", "pipe"],
    env: { ...process.env, CI: "1", WRANGLER_SEND_METRICS: "false" },
    detached: true,
  });
  let stderr = "";
  child.stderr.on("data", (c: Buffer) => (stderr += c.toString("utf8")));
  for (let i = 0; i < 120; i++) {
    if (child.exitCode !== null) fail(`wrangler dev je izašao (${child.exitCode}): ${stderr.slice(-500)}`);
    try {
      const g = await get(port, `${PREFIX}/health`, "localhost");
      if (g.status === 200) return child;
    } catch {
      // još se diže
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  stopDev(child);
  return fail(`wrangler dev nije odgovorio na :${port} u 60 s`);
}

function stopDev(child: ChildProcess): void {
  if (child.pid !== undefined && child.exitCode === null) {
    try {
      process.kill(-child.pid, "SIGTERM"); // cijela grupa (wrangler + workerd)
    } catch {
      child.kill("SIGTERM");
    }
  }
}

// ---- izlaz -----------------------------------------------------------------

const mb = (b: number): string => `${(b / 1024 / 1024).toFixed(1)} MB`;

function printReport(name: string, s: Storage, t: Targets, results: readonly CaseResult[]): void {
  console.log(`\nmeasure: ${name}`);
  console.log(
    `  baza       ${mb(s.usedBytes)} (datoteka ${mb(s.fileBytes)}, ${s.pageCount} × ${s.pageSize} B, slobodno ${s.freelistCount})`,
  );
  console.log(
    `  retci      ${s.rows.episodes} epizoda (${s.rows.episodesListed} u popisima, ${s.rows.variants} varijanti), ${s.rows.channels} kanala (${s.rows.channelsProcessed} s epizodom)`,
  );
  console.log(
    `  B/epizodi  ${s.bytesPerEpisode.toFixed(0)} cijela baza; ${s.episodeBytesPerEpisode?.toFixed(0) ?? "-"} episodes + indeksi; ${s.channelBytesPerChannel?.toFixed(0) ?? "-"} B/kanalu`,
  );
  if (s.objects !== null) {
    for (const o of s.objects.slice(0, 8)) console.log(`    ${o.name.padEnd(34)} ${o.type.padEnd(5)} ${mb(o.bytes).padStart(9)}`);
  }
  console.log(
    `  ciljevi    vrući dan ${t.hotDay.date} (${t.hotDay.episodes}), div ${t.diva.slug} (${t.diva.episodes}), mali ${t.small.slug} (${t.small.episodes}), kartica ${t.cardId}`,
  );
  console.log("  trajanje je lokalno (Node → wrangler dev → workerd → SQLite na Macu), ms; NIJE D1 na edgeu");
  const head = ["ruta", "lim", "rr prva", "rr duboka", "dubina", "miss p50/p95", "hit p50/p95", "duboka miss p50/p95"];
  console.log(`  ${head[0]?.padEnd(26)} ${head.slice(1).map((h) => h.padStart(12)).join(" ")}`);
  for (const r of results) {
    const t1 = r.first.timing;
    const d = r.deep;
    const cols = [
      r.limit === null ? "-" : String(r.limit),
      String(r.first.rowsRead),
      d === null ? "-" : `${d.rowsRead} (max ${d.maxRowsRead})`,
      d === null ? "-" : `${d.depthItems}${d.reachedEnd ? " kraj" : ""}`,
      `${t1.miss.p50}/${t1.miss.p95}`,
      `${t1.hit.p50}/${t1.hit.p95}`,
      d === null ? "-" : `${d.timing.miss.p50}/${d.timing.miss.p95}`,
    ];
    console.log(`  ${r.name.padEnd(26)} ${cols.map((c) => c.padStart(12)).join(" ")}`);
  }
}

async function main(): Promise<void> {
  const { values } = parseArgs({
    options: {
      persist: { type: "string" },
      port: { type: "string", default: "8799" },
      reps: { type: "string", default: "30" },
      deep: { type: "string", default: "20" },
      out: { type: "string" },
      "no-serve": { type: "boolean", default: false },
    },
  });
  if (values.persist === undefined) fail("--persist <dir> je obavezan (npr. .wrangler/synth-1m)");
  const dir = resolve(process.cwd(), values.persist);
  const port = Number(values.port);
  const reps = Number(values.reps);
  const deep = Number(values.deep);
  if (!Number.isInteger(port) || !Number.isInteger(reps) || reps < 1 || !Number.isInteger(deep) || deep < 2) {
    fail("--port, --reps (≥ 1) i --deep (≥ 2) su cijeli brojevi");
  }
  const name = basename(dir);
  const out = resolve(process.cwd(), values.out ?? join(KATALOG, ".wrangler", "measure", `${name}.json`));

  const { storage, targets } = readStorage(sqliteFile(dir));

  const child = values["no-serve"] ? null : await startDev(dir, port);
  const results: CaseResult[] = [];
  try {
    for (const limit of LIMITS) {
      for (const c of cases(targets, limit, deep)) results.push(await runCase(port, c, limit, reps, deep));
    }
    for (const c of singleCases(targets)) results.push(await runCase(port, c, null, reps, deep));
  } finally {
    agent.destroy();
    if (child !== null) stopDev(child);
  }

  mkdirSync(dirname(out), { recursive: true });
  const report = {
    measuredAt: new Date().toISOString(),
    persist: relative(KATALOG, dir),
    reps,
    deep,
    note: "trajanje: lokalni wrangler dev (workerd + SQLite na Macu), ms; nije D1 na edgeu",
    storage,
    targets,
    results,
  };
  writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
  printReport(name, storage, targets, results);
  console.log(`\n  JSON: ${relative(process.cwd(), out)}`);
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? (err.stack ?? err.message) : err);
  process.exit(1);
});

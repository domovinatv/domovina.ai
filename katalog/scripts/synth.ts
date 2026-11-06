// Sintetički katalog u ODVOJENOM lokalnom D1 (S4), za mjerenja na 10k / 100k / 1M.
//
//   npm run synth -- --episodes 10000 --seed 1 --persist .wrangler/synth-10k
//   npm run synth -- --episodes 1000000 --seed 1 --persist .wrangler/synth-1m --force
//   npx wrangler dev --local --persist-to .wrangler/synth-10k --port 8799
//
// Raspodjela je `korpus` (oblik stvarnog kataloga, `src/synth/korpus.ts`) ili
// `s3` (ograda za paginaciju iz odluke 313, `src/synth/s3.ts`, samo do 200k).
// Deterministička po sjemenu: isto sjeme → isti ID-evi i brojke (`updated_at`
// je vrijeme pokretanja, kao kod uvoznika).
//
// Postojeća lokalna baza iz S2 uvoza (`.wrangler/state`) se NIKAD ne dira:
// `--persist` mora biti pod `.wrangler/`, a ne pod `.wrangler/state`.
//
// Zašto izravno u SQLite (`node:sqlite`), a ne kroz `getPlatformProxy` kao
// `import.mjs`: 1M redaka kroz proxy je 5000 odlazaka `db.batch` po 200 naredbi
// preko miniflarea, dok je izravan upis u transakcijama jedna Node petlja.
// Shema i stupci su ipak isti kao kod uvoznika: migracije primjenjuje
// `wrangler d1 migrations apply --local` (ista naredba kao `npm run
// migrate:local`, samo s `--persist-to`), a retci idu kroz ISTE SQL naredbe i
// parametre kao `applyPlan` (`UPSERT_*`, `channelParams`, `episodeParams` iz
// `src/ingest/write.ts`), istim redom: brend, kanali, epizode. Brojevi kanala
// (`processed_count`, `latest_published_date`) računaju se prvim prolazom
// generatora, pa kanal odmah dobije konačne vrijednosti, kao iz plana.
//
// Node 24+ (izvršava .ts izravno, type stripping).
import { spawnSync } from "node:child_process";
import { existsSync, readdirSync, rmSync } from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import type { ChannelRow, EpisodeRow } from "../src/ingest/plan.ts";
import { channelParams, episodeParams, UPSERT_BRAND, UPSERT_CHANNEL, UPSERT_EPISODE } from "../src/ingest/write.ts";
import { Korpus } from "../src/synth/korpus.ts";
import { synthesizeS3 } from "../src/synth/s3.ts";
import { type CatalogSummary, Tally } from "../src/synth/tally.ts";

const KATALOG = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const WRANGLER_DIR = join(KATALOG, ".wrangler");
const PROTECTED = join(WRANGLER_DIR, "state");
/** Brend kao kod uvoznika (`DOMOVINA_BRAND`); na localhostu ga daje `DEFAULT_BRAND`. */
const BRAND = { id: "domovina", host: "domovina.ai" } as const;
/** Redaka po transakciji: dovoljno velike da upis bude brz, dovoljno male da journal ostane malen. */
const TX_ROWS = 50_000;
const S3_MAX = 200_000;

interface Source {
  readonly profile: string;
  /** Prvi prolaz: kanali s konačnim brojevima i sažetak. */
  readonly plan: () => { channels: readonly ChannelRow[]; summary: CatalogSummary };
  /** Drugi prolaz: iste epizode, redom. */
  readonly episodes: () => Iterable<EpisodeRow>;
}

function fail(msg: string): never {
  console.error(`synth: ${msg}`);
  process.exit(2);
}

function source(profile: string, episodes: number, seed: number): Source {
  if (profile === "korpus") {
    const k = new Korpus({ episodes, seed });
    return {
      profile,
      plan: () => {
        const it = k.episodes();
        while (it.next().done !== true) {
          // samo brojači
        }
        return { channels: k.channelRows(), summary: k.summary() };
      },
      episodes: () => k.episodes(),
    };
  }
  if (profile === "s3") {
    if (episodes > S3_MAX) fail(`profil s3 drži sve retke u memoriji; najviše ${S3_MAX} epizoda`);
    const s = synthesizeS3({ episodes, seed });
    return {
      profile,
      plan: () => {
        const t = new Tally();
        for (const e of s.episodes) t.add(e);
        return { channels: s.channels, summary: t.summary(s.channels) };
      },
      episodes: () => s.episodes,
    };
  }
  return fail(`nepoznat profil ${profile} (korpus | s3)`);
}

function persistDir(arg: string): string {
  const dir = resolve(process.cwd(), arg);
  const rel = relative(WRANGLER_DIR, dir);
  if (rel === "" || rel.startsWith("..") || resolve(WRANGLER_DIR, rel) !== dir) {
    fail(`--persist mora biti poddirektorij od ${relative(process.cwd(), WRANGLER_DIR) || ".wrangler"}/ (u .gitignore)`);
  }
  if (dir === PROTECTED || dir.startsWith(PROTECTED + sep)) {
    fail("--persist ne smije biti .wrangler/state: ondje je lokalna baza iz uvoza (S2)");
  }
  return dir;
}

function sqliteFile(dir: string): string {
  const d1 = join(dir, "v3", "d1", "miniflare-D1DatabaseObject");
  const files = existsSync(d1) ? readdirSync(d1).filter((f) => f.endsWith(".sqlite") && f !== "metadata.sqlite") : [];
  if (files.length !== 1) fail(`u ${d1} očekujem jednu .sqlite datoteku, ima ih ${files.length}`);
  return join(d1, files[0] ?? "");
}

function main(): void {
  const { values } = parseArgs({
    options: {
      episodes: { type: "string" },
      seed: { type: "string", default: "1" },
      persist: { type: "string" },
      profile: { type: "string", default: "korpus" },
      force: { type: "boolean", default: false },
    },
    strict: true,
  });
  const episodes = Number(values.episodes);
  const seed = Number(values.seed);
  if (!Number.isInteger(episodes) || episodes <= 0) fail("--episodes N (cijeli broj) je obavezan");
  if (!Number.isInteger(seed) || seed < 0) fail("--seed mora biti nenegativan cijeli broj");
  const dir = persistDir(values.persist ?? `.wrangler/synth-${episodes}`);
  const src = source(values.profile, episodes, seed);
  const t0 = performance.now();
  const lap = (from: number): string => `${((performance.now() - from) / 1000).toFixed(1)} s`;

  if (existsSync(dir)) {
    if (!values.force) fail(`${relative(KATALOG, dir)} već postoji; --force ga briše i puni iznova`);
    rmSync(dir, { recursive: true, force: true });
  }

  // 1. Shema: iste migracije kao `npm run migrate:local`, u vlastiti direktorij.
  const tm = performance.now();
  const wrangler = join(KATALOG, "node_modules", ".bin", "wrangler");
  const mig = spawnSync(wrangler, ["d1", "migrations", "apply", "katalog", "--local", "--persist-to", dir], {
    cwd: KATALOG,
    stdio: ["ignore", "ignore", "inherit"],
    env: { ...process.env, CI: "1", WRANGLER_SEND_METRICS: "false" },
  });
  if (mig.status !== 0) fail(`wrangler d1 migrations apply nije uspio (izlaz ${mig.status ?? "signal"})`);
  const file = sqliteFile(dir);
  const migrations = readdirSync(join(KATALOG, "migrations")).filter((f) => f.endsWith(".sql")).length;
  const db = new DatabaseSync(file);
  const applied = (db.prepare("SELECT count(*) AS n FROM d1_migrations").get() as { n: number }).n;
  if (applied !== migrations) fail(`primijenjeno ${applied} od ${migrations} migracija`);
  const migTime = lap(tm);

  // 2. Prvi prolaz: konačni brojevi kanala (generator je deterministički).
  const tp = performance.now();
  const { channels, summary } = src.plan();
  const planTime = lap(tp);

  // 3. Upis istim SQL-om i redom kao `applyPlan`: brend, kanali, epizode.
  const tw = performance.now();
  const now = new Date().toISOString();
  db.exec("PRAGMA synchronous = OFF");
  // 64 MB stranica: izmjereno jednako brzo kao 256 MB (300k redaka 5,6 s), a memorija ostaje mala.
  db.exec("PRAGMA cache_size = -65536");
  if ((db.prepare("PRAGMA foreign_keys").get() as { foreign_keys: number }).foreign_keys !== 1) {
    fail("foreign_keys nije uključen (D1 ga uvijek provjerava)");
  }
  db.exec("BEGIN");
  db.prepare(UPSERT_BRAND).run(BRAND.id, BRAND.host);
  const channel = db.prepare(UPSERT_CHANNEL);
  for (const c of channels) channel.run(...channelParams(BRAND.id, c));
  db.exec("COMMIT");
  const episode = db.prepare(UPSERT_EPISODE);
  let written = 0;
  db.exec("BEGIN");
  for (const e of src.episodes()) {
    episode.run(...episodeParams(BRAND.id, e, now));
    if (++written % TX_ROWS === 0) {
      db.exec("COMMIT");
      if (written % 200_000 === 0) console.error(`  … ${written} epizoda, ${lap(tw)}`);
      db.exec("BEGIN");
    }
  }
  db.exec("COMMIT");
  if (written !== summary.episodes.total) fail(`upisano ${written}, a sažetak kaže ${summary.episodes.total}`);
  const counts = { source: "synth", profile: src.profile, seed, summary };
  db.prepare(
    "INSERT INTO ingest_runs (started_at, finished_at, source, counts, status) VALUES (?1, ?2, 'synth', ?3, 'ok')",
  ).run(now, new Date().toISOString(), JSON.stringify(counts));
  db.exec("PRAGMA wal_checkpoint(TRUNCATE)");
  const writeTime = lap(tw);
  const stored = db.prepare("SELECT (SELECT count(*) FROM channels) AS c, (SELECT count(*) FROM episodes) AS e").get() as {
    c: number;
    e: number;
  };
  db.close();
  if (stored.c !== channels.length || stored.e !== written) fail(`u bazi ${stored.c} kanala / ${stored.e} epizoda`);

  const s = summary;
  const pct = (x: number): string => `${((100 * x) / s.episodes.total).toFixed(2)} %`;
  const rel = relative(KATALOG, dir);
  console.log(`synth: profil ${src.profile}, sjeme ${seed}, ${rel}`);
  console.log(
    `  kanala     ${s.channels.total} (Tier 1: ${s.channels.tier1}, Tier 2: ${s.channels.tier2}, ` +
      `bez registryja: ${s.channels.unregistered}), najveći ${s.channels.largest}`,
  );
  console.log(
    `  po veličini ${Object.entries(s.channels.bySize)
      .map(([k, v]) => `${k}: ${v}`)
      .join(", ")}`,
  );
  console.log(
    `  epizoda    ${s.episodes.total} (Tier 1: ${s.episodes.tier1}, Tier 2: ${s.episodes.tier2} = ${pct(s.episodes.tier2)})`,
  );
  console.log(
    `  varijanti  ${s.episodes.variants} (${pct(s.episodes.variants)}), bez kanala ${s.episodes.withoutChannel}, ` +
      `bez datuma ${s.episodes.withoutDate}`,
  );
  console.log(`  vrući dan  ${s.hotDay.date ?? "-"} (${s.hotDay.episodes} ne-varijanti)`);
  console.log(`  trajanje   ${lap(t0)} (migracije ${migTime}, prvi prolaz ${planTime}, upis ${writeTime})`);
  console.log(`  posluži:   npx wrangler dev --local --persist-to ${rel} --port 8799`);
  if (s.hotDay.date !== null) {
    console.log(`  provjera:  curl -s 'localhost:8799/api/katalog/v1/days/${s.hotDay.date}?limit=100'`);
  }
}

main();

// Zastoj promjene postavke kanala do D1 (odluka 106 lanca `postavke-kanala/`),
// izmjeren nad LOKALNIM stackom domovina-api. Nikad produkcija.
//
//   npm run settings-latency                 # 10 promjena
//   npm run settings-latency -- --reps 30
//
// Preduvjet: lokalni Supabase stack domovina-api radi (Kong 55321, kontejner
// `supabase_db_domovina-api`). Skripta ga ne pokreće ni ne mijenja osim jednog
// probnog retka (`PROBE_UC`) u `domovina_ai.channel_settings`, koji na kraju briše.
//
// Jedan uzorak:
//   1. `docker exec … psql`: upsert probnog retka (`home_featured` naizmjence
//      true/false, `updated_at = now()`); t0 = trenutak kad psql vrati (commit vidljiv);
//   2. `pollSettings` (isti kod kao Cron Trigger) prema `http://localhost:55321`
//      i lokalnom D1 (`getPlatformProxy`, zasebna `--persist-to` mapa, migracije
//      `wrangler d1 migrations apply --local`); t1 = kad poller vrati;
//   3. provjera da D1 ima novu vrijednost. Uzorak = t1 − t0.
// Upis ide izravno u tablicu, ne kroz RPC `set_channel_setting` (traži JWT
// potvrđenog vlasnika); poller vidi isto: novi redak u `public_channel_settings`.
//
// Ovo mjeri RPC → D1 kad cron okine odmah. Gornja granica u produkciji:
//   čekanje na cron (≤ 60 s) + trajanje poziva (ovo, uz mrežu do api.domovina.ai
//   i produkcijski D1) + memorija konteksta u izolatu (≤ 30 s, CONTEXT_TTL_MS)
//   + rub/klijent (`max-age=60`, uz `stale-while-revalidate=600` na popisima).
//
// Node 24+ (type stripping).
import { execFileSync } from "node:child_process";
import { mkdirSync } from "node:fs";
import { join } from "node:path";
import { parseArgs } from "node:util";
import { pollSettings } from "../src/settings/poller.ts";
import { KATALOG } from "./lib/paths.ts";
import { resolveSupabaseKey } from "./lib/supabase-keys.ts";

const API = "http://localhost:55321";
const CONTAINER = "supabase_db_domovina-api";
const PROBE_UC = "UClatencyprobe0000000000";
const SOURCE = "latency-probe";

const { values: args } = parseArgs({
  options: {
    reps: { type: "string", default: "10" },
    "persist-to": { type: "string", default: join(KATALOG, ".wrangler", "measure", "settings-latency-d1") },
  },
});
const reps = Number(args.reps);
if (!Number.isInteger(reps) || reps < 1 || reps > 1000) throw new Error("--reps mora biti 1–1000");

function psql(sql: string): string {
  return execFileSync("docker", ["exec", CONTAINER, "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1", "-tAc", sql], {
    encoding: "utf8",
  }).trim();
}

function flip(value: boolean): void {
  psql(
    `insert into domovina_ai.channel_settings (youtube_channel_id, settings, updated_at)
     values ('${PROBE_UC}', jsonb_build_object('home_featured', ${String(value)}), now())
     on conflict (youtube_channel_id) do update set settings = excluded.settings, updated_at = now()`,
  );
}

const pct = (sorted: readonly number[], p: number): number => sorted[Math.min(sorted.length - 1, Math.floor((sorted.length - 1) * p))] ?? NaN;

async function main(): Promise<void> {
  // Stack mora već raditi; ne dižemo ga.
  try {
    await fetch(`${API}/rest/v1/`, { signal: AbortSignal.timeout(3000) });
  } catch {
    throw new Error(`lokalni stack domovina-api ne odgovara na ${API} (ne pokrećem ga)`);
  }
  const anonKey = await resolveSupabaseKey(API, "anon");
  if (anonKey === null) throw new Error("nema lokalnog anon ključa (`supabase status -o env`)");

  const persist = args["persist-to"];
  mkdirSync(persist, { recursive: true });
  execFileSync("npx", ["wrangler", "d1", "migrations", "apply", "katalog", "--local", "--persist-to", persist], {
    cwd: KATALOG,
    stdio: ["ignore", "ignore", "inherit"],
  });
  const { getPlatformProxy } = await import("wrangler");
  const proxy = await getPlatformProxy<{ DB: D1Database }>({
    configPath: join(KATALOG, "wrangler.jsonc"),
    // `wrangler d1 … --persist-to X` piše u `X/v3`; proxy čita mapu koju mu se da.
    persist: { path: join(persist, "v3") },
    remoteBindings: false,
  });
  const db = proxy.env.DB;
  const deps = { db, apiUrl: API, anonKey, fetch: (i: RequestInfo | URL, init?: RequestInit) => fetch(i, init), source: SOURCE };
  const samples: number[] = [];
  const pollOnly: number[] = [];
  try {
    flip(true);
    const first = await pollSettings(deps); // početni prolaz: sve iz izvora
    if (first.status !== "ok") throw new Error(`početni poll: ${first.status} ${first.error ?? ""}`);
    console.log(`početni poll: ${first.fetched} redaka, ${first.pages} str.`);

    for (let i = 0; i < reps; i++) {
      const value = i % 2 !== 0;
      flip(value);
      const t0 = performance.now();
      const r = await pollSettings(deps);
      const t1 = performance.now();
      if (r.status !== "ok" || r.effectiveChanged < 1) throw new Error(`uzorak ${i}: ${r.status} effectiveChanged=${r.effectiveChanged}`);
      const row = await db
        .prepare("SELECT json_extract(effective, '$.home_featured') AS v FROM channel_settings WHERE youtube_channel_id = ?1")
        .bind(PROBE_UC)
        .first<{ v: number }>();
      if (row?.v !== (value ? 1 : 0)) throw new Error(`uzorak ${i}: D1 nema novu vrijednost`);
      samples.push(t1 - t0);

      // Poziv bez promjene (samo čitanje i usporedba): trošak svake minute.
      const s0 = performance.now();
      await pollSettings(deps);
      pollOnly.push(performance.now() - s0);
    }
  } finally {
    psql(`delete from domovina_ai.channel_settings where youtube_channel_id = '${PROBE_UC}'`);
    await proxy.dispose();
  }
  const s = [...samples].sort((a, b) => a - b);
  const p = [...pollOnly].sort((a, b) => a - b);
  const ms = (n: number): string => `${n.toFixed(1)} ms`;
  console.log(`promjena → D1 (lokalno, cron okida odmah), n=${s.length}`);
  console.log(`  min ${ms(s[0] ?? NaN)}  medijan ${ms(pct(s, 0.5))}  p90 ${ms(pct(s, 0.9))}  max ${ms(s[s.length - 1] ?? NaN)}`);
  console.log(`poll bez promjene, n=${p.length}`);
  console.log(`  min ${ms(p[0] ?? NaN)}  medijan ${ms(pct(p, 0.5))}  max ${ms(p[p.length - 1] ?? NaN)}`);
  const worst = s[s.length - 1] ?? 0;
  console.log("gornja granica u produkciji (bez mreže do api.domovina.ai i produkcijskog D1):");
  console.log(`  D1: 60 s (cron) + ${ms(worst)} ≈ ${((60_000 + worst) / 1000).toFixed(1)} s`);
  console.log(`  API (nova verzija kataloga): + 30 s memorija konteksta ≈ ${((90_000 + worst) / 1000).toFixed(1)} s`);
  console.log("  klijent iza ruba: + max-age 60 s (popisi i do 600 s stale-while-revalidate)");
}

main().catch((err: unknown) => {
  console.error(err instanceof Error ? err.message : String(err));
  process.exitCode = 2;
});

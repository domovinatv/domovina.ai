// Ključevi domovina-api za Node skripte (`channel-slugs-sync`, `drift-check`,
// `settings-latency`). Vrijednost se nikad ne ispisuje. Ključ ne ide u Worker:
// Worker ima svoj secret `SETTINGS_ANON_KEY`.
//
// Redom:
//   1. okolina: anon `SETTINGS_ANON_KEY` ili `SUPABASE_ANON_KEY`, service
//      `SUPABASE_SERVICE_ROLE_KEY`;
//   2. anon: redak `SETTINGS_ANON_KEY=` u `katalog/.dev.vars` (gitignoran);
//   3. localhost: `supabase status -o env` u domovina-api (samo čita stanje stacka);
//   4. inače env datoteke domovina-api (`.env`, pa `.coolify-current.env`).
//      Coolify: prava vrijednost je u `SERVICE_SUPABASE*`; `SUPABASE_ANON_KEY` i
//      `SUPABASE_SERVICE_KEY` su ondje reference (`${…}`) i preskaču se.
import { execFileSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { valueFromEnvText } from "./channel-slugs.ts";
import { KATALOG } from "./paths.ts";

export const DOMOVINA_API_REPO = resolve(KATALOG, "../../domovina-api");

export type KeyKind = "anon" | "service";

export const isLocalBase = (base: string): boolean => /^https?:\/\/(localhost|127\.0\.0\.1)(:\d+)?(\/|$)/.test(base);

async function fromFile(path: string, names: readonly string[]): Promise<string | null> {
  let text: string;
  try {
    text = await readFile(path, "utf8");
  } catch {
    return null;
  }
  for (const n of names) {
    const v = valueFromEnvText(text, n);
    if (v !== null && !v.startsWith("${")) return v;
  }
  return null;
}

export async function resolveSupabaseKey(base: string, kind: KeyKind): Promise<string | null> {
  const envNames = kind === "anon" ? ["SETTINGS_ANON_KEY", "SUPABASE_ANON_KEY"] : ["SUPABASE_SERVICE_ROLE_KEY"];
  for (const n of envNames) {
    const v = process.env[n];
    if (v !== undefined && v !== "") return v;
  }
  if (isLocalBase(base)) {
    try {
      const out = execFileSync("supabase", ["status", "-o", "env"], {
        cwd: DOMOVINA_API_REPO,
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      });
      return valueFromEnvText(out, kind === "anon" ? "ANON_KEY" : "SERVICE_ROLE_KEY");
    } catch {
      return null;
    }
  }
  if (kind === "anon") {
    const dev = await fromFile(join(KATALOG, ".dev.vars"), ["SETTINGS_ANON_KEY"]);
    if (dev !== null) return dev;
  }
  const names =
    kind === "anon"
      ? ["SERVICE_SUPABASEANON_KEY", "ANON_KEY", "SUPABASE_ANON_KEY"]
      : ["SERVICE_SUPABASESERVICE_KEY", "SERVICE_ROLE_KEY", "SUPABASE_SERVICE_ROLE_KEY", "SUPABASE_SERVICE_KEY"];
  for (const file of [".env", ".coolify-current.env"]) {
    const v = await fromFile(join(DOMOVINA_API_REPO, file), names);
    if (v !== null) return v;
  }
  return null;
}

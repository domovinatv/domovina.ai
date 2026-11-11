// Puni `domovina_ai.channel_slugs` (domovina-api) slugovima kataloga
// (odluka 202 lanca `postavke-kanala/`): pinka kampanje kanal nose po slugu, a
// postavke po UC-u.
//
//   npm run channel-slugs-sync                                     # dry-run prema produkciji (samo čita)
//   npm run channel-slugs-sync -- --base http://localhost:55321 --commit   # lokalni stack
//   npm run channel-slugs-sync -- --commit --confirm-production    # VRATA: samo čovjek
//   (`--verbose` ispiše sve slugove, ne samo uzorak)
//
// Izvor: katalog `GET {--katalog}/api/katalog/v1/channels` (sve stranice) +
// registry (`KATALOG_REGISTRY_PATH`, zadano fetch repo) za kanale bez UC-a.
// Cilj: `{--base}/rest/v1/channel_slugs` (PostgREST, shema `domovina_ai`).
// Samo upsert; slug kojeg katalog nema se javlja, ne briše.
//
// Ključevi (vrijednost se nikad ne ispisuje; redoslijed izvora u
// `scripts/lib/supabase-keys.ts`): dry-run čita anon ključem (tablica je javno
// čitljiva), `--commit` piše `service_role` ključem.
//
// Exit: 0 nema razlike (ili upisano i ponovno izmjereno bez razlike),
// 1 dry-run ima razliku, 2 greška ili upis nije konvergirao.
//
// Node 24+ (type stripping).
import { readFile } from "node:fs/promises";
import { parseArgs } from "node:util";
import { parseRegistry } from "../src/input/index.ts";
import { registryUcBySlug } from "../src/ingest/plan.ts";
import {
  buildSlugMap,
  diffSlugs,
  fetchCatalogChannels,
  fetchChannelSlugs,
  redactKey,
  upsertChannelSlugs,
} from "./lib/channel-slugs.ts";
import { REGISTRY_PATH } from "./lib/paths.ts";
import { isLocalBase as isLocal, resolveSupabaseKey } from "./lib/supabase-keys.ts";

async function main(): Promise<number> {
  const { values: args } = parseArgs({
    options: {
      base: { type: "string", default: "https://api.domovina.ai" },
      katalog: { type: "string", default: "https://domovina.ai" },
      commit: { type: "boolean", default: false },
      "confirm-production": { type: "boolean", default: false },
      verbose: { type: "boolean", default: false },
    },
  });
  const base = args.base.replace(/\/+$/, "");
  const katalog = args.katalog.replace(/\/+$/, "");
  if (args.commit && !isLocal(base) && !args["confirm-production"]) {
    console.error(`--commit prema ${base} traži --confirm-production (vrata: upis u produkciju radi čovjek).`);
    return 2;
  }

  const key = await resolveSupabaseKey(base, args.commit ? "service" : "anon");
  if (key === null) {
    console.error(`nema ${args.commit ? "service_role" : "anon"} ključa za ${base} (vidi zaglavlje skripte)`);
    return 2;
  }
  try {
    const registry = parseRegistry(JSON.parse(await readFile(REGISTRY_PATH, "utf8")) as unknown);
    const channels = await fetchCatalogChannels(fetch, katalog);
    const slugs = buildSlugMap(channels, registryUcBySlug(registry));
    const existing = await fetchChannelSlugs(fetch, base, key);
    const diff = diffSlugs(slugs.map, existing);

    const line = (k: string, v: string | number): void => {
      console.log(`  ${k.padEnd(26)} ${v}`);
    };
    const SAMPLE = 12;
    const list = (a: readonly string[]): string =>
      a.length === 0
        ? "0"
        : `${a.length}  ${(args.verbose ? a : a.slice(0, SAMPLE)).join(" ")}${!args.verbose && a.length > SAMPLE ? " …" : ""}`;
    console.log(`channel-slugs-sync  ${katalog} → ${base}  (${args.commit ? "commit" : "dry-run"})`);
    line("kanala u katalogu", channels.length);
    line("slug → UC", slugs.map.size);
    line("UC iz registryja", list(slugs.fromRegistry));
    line("bez UC-a (bez postavki)", list(slugs.withoutUc));
    line("u channel_slugs", existing.size);
    line("novi", list(diff.insert.map((r) => r.slug)));
    line("drugi UC", list(diff.update.map((r) => `${r.slug}(${r.from}→${r.youtube_channel_id})`)));
    line("isti", diff.unchanged);
    line("samo u channel_slugs", list(diff.onlyInTarget));

    const pending = [...diff.insert, ...diff.update];
    if (!args.commit) return pending.length === 0 ? 0 : 1;

    const written = await upsertChannelSlugs(fetch, base, key, pending, new Date());
    const after = diffSlugs(slugs.map, await fetchChannelSlugs(fetch, base, key));
    line("upisano", written);
    const left = after.insert.length + after.update.length;
    line("nakon upisa razlika", left);
    return left === 0 ? 0 : 2;
  } catch (err) {
    console.error(redactKey(err instanceof Error ? err.message : String(err), key));
    return 2;
  }
}

main().then(
  (code) => {
    process.exitCode = code;
  },
  (err: unknown) => {
    console.error(err instanceof Error ? err.message : String(err));
    process.exitCode = 2;
  },
);

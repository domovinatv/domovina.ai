// Produkcijski paket migracija (S7, odluke 730–734): jedan SQL za `psql` nad
// Supabaseom na api.domovina.ai, isti tekst migracija i isto knjigovodstvo kao
// `migrateUp` (db/migrate.ts), u jednoj transakciji. Ovaj modul samo SASTAVLJA
// SQL; nikad se ne spaja na bazu.
//
//   npm run db:bundle                      → stdout, sve migracije (prazna shema)
//   npm run db:bundle -- --from 7          → samo 007+, uz provjeru da je baza na 006
//   npm run db:bundle -- --out db/prod/vijesti-install.sql
import { writeFile } from 'node:fs/promises';
import { loadMigrations, type Migration } from './migrate.js';

/** Isto knjigovodstvo koje stvara `migrateUp` (ensureBookkeeping u migrate.ts). */
export const BOOKKEEPING_SQL = `CREATE SCHEMA IF NOT EXISTS vijesti;
CREATE TABLE IF NOT EXISTS vijesti.schema_migrations (
  version    integer PRIMARY KEY,
  name       text NOT NULL,
  applied_at timestamptz NOT NULL DEFAULT now()
);`;

const pad = (n: number) => String(n).padStart(3, '0');

export interface BundleOptions {
  /** Prva migracija u paketu; baza mora imati točno sve prije nje. Zadano prva postojeća. */
  from?: number;
}

/**
 * SQL paketa: knjigovodstvo, provjera stanja baze, pa svaka migracija s retkom u
 * `schema_migrations`, sve u jednoj transakciji; na kraju PostgREST ponovno
 * učita shemu (`NOTIFY pgrst`). Greška bilo gdje = ništa nije primijenjeno.
 */
export function bundleSql(all: readonly Migration[], opts: BundleOptions = {}): string {
  if (all.length === 0) throw new Error('nema migracija');
  const from = opts.from ?? all[0]?.version ?? 1;
  const before = all.filter((m) => m.version < from).map((m) => m.version);
  const included = all.filter((m) => m.version >= from);
  if (included.length === 0) throw new Error(`nema migracija od ${pad(from)}`);
  const last = included.at(-1);
  const expected = before.length === 0 ? 'ARRAY[]::integer[]' : `ARRAY[${before.join(', ')}]`;
  const out: string[] = [
    `-- Paket migracija sheme \`vijesti\`: ${included.map((m) => `${pad(m.version)}_${m.name}`).join(', ')}.`,
    '-- GENERIRANO naredbom `npm run db:bundle` iz db/migrations/*.up.sql; ne uređuj ručno.',
    '-- Primjena (jedna transakcija, staje na prvoj grešci):',
    '--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f <ova datoteka>',
    '-- Upute i provjera nakon primjene: vijesti/db/prod/README.md.',
    '',
    'BEGIN;',
    '',
    BOOKKEEPING_SQL,
    '',
    '-- Baza mora biti točno u stanju prije paketa, inače se ništa ne primjenjuje.',
    'DO $bundle_guard$',
    'DECLARE applied integer[];',
    'BEGIN',
    '  SELECT coalesce(array_agg(version ORDER BY version), ARRAY[]::integer[]) INTO applied',
    '    FROM vijesti.schema_migrations;',
    `  IF applied <> ${expected} THEN`,
    `    RAISE EXCEPTION 'paket ${pad(from)}–${pad(last?.version ?? from)}: baza ima migracije %, očekivano %', applied, ${expected};`,
    '  END IF;',
    'END',
    '$bundle_guard$;',
  ];
  for (const m of included) {
    out.push(
      '',
      `-- ===========================================================================`,
      `-- ${pad(m.version)}_${m.name}.up.sql`,
      `-- ===========================================================================`,
      '',
      m.up.trimEnd(),
      '',
      `INSERT INTO vijesti.schema_migrations (version, name) VALUES (${String(m.version)}, '${m.name}');`,
    );
  }
  out.push(
    '',
    '-- PostgREST (Supabase `rest`) ponovno čita shemu kad transakcija prođe.',
    "NOTIFY pgrst, 'reload schema';",
    '',
    'COMMIT;',
    '',
  );
  return out.join('\n');
}

const isMain = import.meta.url === `file://${process.argv[1] ?? ''}`;
if (isMain) {
  const args = process.argv.slice(2);
  const val = (flag: string) => {
    const i = args.indexOf(flag);
    return i >= 0 ? args[i + 1] : undefined;
  };
  const fromArg = val('--from');
  const from = fromArg === undefined ? undefined : Number(fromArg);
  if (from !== undefined && !Number.isInteger(from)) throw new Error(`--from mora biti broj, ne „${fromArg ?? ''}”`);
  const sql = bundleSql(await loadMigrations(), from === undefined ? {} : { from });
  const out = val('--out');
  if (out) {
    await writeFile(out, sql);
    console.error(`[vijesti] paket migracija → ${out}`);
  } else {
    process.stdout.write(sql);
  }
}

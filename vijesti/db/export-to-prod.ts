// Prijenos nacrta iz lokalne PGlite baze u produkcijsku shemu `vijesti`
// (odluka 804). Privremeni most dok engine nema adapter za pravi Postgres (S8):
// engine radi lokalno, a ova skripta iz cijele lokalne baze napiše JEDNU SQL
// transakciju koja retke umetne s istim ID-evima. Primjena kao paket migracije
// (`db/prod/README.md`): `psql -v ON_ERROR_STOP=1` u kontejneru baze.
//
//   npx tsx db/export-to-prod.ts --db .cache/proba.pglite > /tmp/vijesti-export.sql
//
// - `article_transitions` je stroj stanja koji puni migracija, ne kopira se.
// - Kopira urednički tok (prolazi, trenuci, priče, članci, verzije, izvori,
//   dnevnici). NE kopira `staff`, `allowed_channels` ni `eval_*`: to su
//   produkcijske odluke, ne podaci enginea.
// - `session_replication_role = replica` za vrijeme kopije: okidači (dnevnik
//   prijelaza, zaštita statusa, append-only) bi inače na umetanju napisali
//   nove retke dnevnika ili odbili povijesne. Retci se prenose kakvi jesu.
// - Sukob ID-a (redak već postoji u produkciji) ruši cijelu transakciju:
//   prijenos je za prazne tablice ili nove ID-eve, nikad prepisivanje.
import { PGlite } from '@electric-sql/pglite';
import { parseArgs } from 'node:util';
import type { SqlDb } from './sql.js';

/** Redoslijed po stranim ključevima (okidači su ugašeni, ali čitljivost). */
export const EXPORT_TABLES = [
  'runs',
  'moments',
  'stories',
  'story_moments',
  'articles',
  'article_versions',
  'article_sources',
  'article_events',
  'corrections',
  'sentence_resolutions',
] as const;

const lit = (s: string) => `'${s.replace(/'/g, "''")}'`;

export async function exportSql(db: SqlDb): Promise<{ sql: string; counts: Record<string, number> }> {
  const out: string[] = [
    '-- GENERIRANO: vijesti/db/export-to-prod.ts (odluka 804). Ne uređivati ručno.',
    '\\set ON_ERROR_STOP on',
    'BEGIN;',
    'SET LOCAL session_replication_role = replica;',
  ];
  const counts: Record<string, number> = {};
  for (const t of EXPORT_TABLES) {
    const r = await db.query<{ j: unknown[] | null }>(`SELECT json_agg(x) AS j FROM vijesti.${t} x`);
    const rows = r.rows[0]?.j ?? [];
    counts[t] = rows.length;
    if (rows.length === 0) continue;
    out.push(
      `INSERT INTO vijesti.${t} OVERRIDING SYSTEM VALUE SELECT * FROM json_populate_recordset(NULL::vijesti.${t}, ${lit(JSON.stringify(rows))}::json);`,
    );
  }
  // Sekvence iza najvećeg ID-a, da sljedeći INSERT u produkciji ne sudari.
  out.push(`DO $$
DECLARE r record; m bigint;
BEGIN
  FOR r IN
    SELECT c.relname AS tab, a.attname AS col, pg_get_serial_sequence(format('vijesti.%I', c.relname), a.attname) AS seq
    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'vijesti' AND c.relkind = 'r'
      AND pg_get_serial_sequence(format('vijesti.%I', c.relname), a.attname) IS NOT NULL
  LOOP
    EXECUTE format('SELECT max(%I) FROM vijesti.%I', r.col, r.tab) INTO m;
    IF m IS NOT NULL THEN PERFORM setval(r.seq, m); END IF;
  END LOOP;
END $$;`);
  out.push('COMMIT;', `SELECT 'vijesti export: ' || ${lit(JSON.stringify(counts))} AS ishod;`);
  return { sql: out.join('\n') + '\n', counts };
}

async function main(): Promise<void> {
  const { values } = parseArgs({ options: { db: { type: 'string' } } });
  if (!values.db) {
    process.stderr.write('upotreba: npx tsx db/export-to-prod.ts --db <pglite-direktorij> > export.sql\n');
    process.exit(2);
  }
  const db = new PGlite(values.db);
  try {
    const { sql, counts } = await exportSql(db);
    process.stdout.write(sql);
    process.stderr.write(`export: ${JSON.stringify(counts)}\n`);
  } finally {
    await db.close();
  }
}

if (import.meta.url === `file://${process.argv[1] ?? ''}`) await main();

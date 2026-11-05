// Jednostavan runner migracija: db/migrations/NNN_ime.up.sql + .down.sql.
// Shemu `vijesti` i tablicu `vijesti.schema_migrations` stvara runner, pa
// `down` prve migracije ostavlja praznu shemu i trag o stanju.
import { readdir, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import type { SqlDb } from './sql.js';

export const MIGRATIONS_DIR = join(dirname(fileURLToPath(import.meta.url)), 'migrations');

export interface Migration {
  version: number;
  name: string;
  up: string;
  down: string;
}

const FILE_RE = /^(\d{3})_([a-z0-9_]+)\.(up|down)\.sql$/;

export async function loadMigrations(dir: string = MIGRATIONS_DIR): Promise<Migration[]> {
  const parts = new Map<number, { name: string; up?: string; down?: string }>();
  for (const file of (await readdir(dir)).sort()) {
    const m = FILE_RE.exec(file);
    if (!m) {
      if (file.endsWith('.sql')) throw new Error(`neispravno ime migracije: ${file}`);
      continue;
    }
    const version = Number(m[1]);
    const name = m[2] ?? '';
    const entry = parts.get(version) ?? { name };
    if (entry.name !== name) throw new Error(`dvije migracije s brojem ${m[1] ?? ''}`);
    const sql = await readFile(join(dir, file), 'utf8');
    if (m[3] === 'up') entry.up = sql;
    else entry.down = sql;
    parts.set(version, entry);
  }
  return [...parts.entries()]
    .sort(([a], [b]) => a - b)
    .map(([version, e]) => {
      if (e.up === undefined || e.down === undefined) {
        throw new Error(`migracija ${String(version)}_${e.name} nema i up i down`);
      }
      return { version, name: e.name, up: e.up, down: e.down };
    });
}

async function ensureBookkeeping(db: SqlDb): Promise<void> {
  await db.exec(`
    CREATE SCHEMA IF NOT EXISTS vijesti;
    CREATE TABLE IF NOT EXISTS vijesti.schema_migrations (
      version    integer PRIMARY KEY,
      name       text NOT NULL,
      applied_at timestamptz NOT NULL DEFAULT now()
    );
  `);
}

export async function appliedVersions(db: SqlDb): Promise<number[]> {
  await ensureBookkeeping(db);
  const res = await db.query<{ version: number }>(
    'SELECT version FROM vijesti.schema_migrations ORDER BY version',
  );
  return res.rows.map((r) => r.version);
}

async function inTransaction(db: SqlDb, fn: () => Promise<void>): Promise<void> {
  await db.exec('BEGIN');
  try {
    await fn();
    await db.exec('COMMIT');
  } catch (e) {
    await db.exec('ROLLBACK');
    throw e;
  }
}

/** Primijeni sve neprimijenjene migracije (ili do `to` uključivo). Vraća primijenjene brojeve. */
export async function migrateUp(
  db: SqlDb,
  opts: { to?: number; migrations?: Migration[] } = {},
): Promise<number[]> {
  const migrations = opts.migrations ?? (await loadMigrations());
  const applied = new Set(await appliedVersions(db));
  const done: number[] = [];
  for (const m of migrations) {
    if (applied.has(m.version)) continue;
    if (opts.to !== undefined && m.version > opts.to) break;
    await inTransaction(db, async () => {
      await db.exec(m.up);
      await db.query('INSERT INTO vijesti.schema_migrations (version, name) VALUES ($1, $2)', [
        m.version,
        m.name,
      ]);
    });
    done.push(m.version);
  }
  return done;
}

/** Vrati zadnjih `steps` migracija (zadano 1; `Infinity` = sve). Vraća vraćene brojeve. */
export async function migrateDown(
  db: SqlDb,
  opts: { steps?: number; migrations?: Migration[] } = {},
): Promise<number[]> {
  const migrations = opts.migrations ?? (await loadMigrations());
  const byVersion = new Map(migrations.map((m) => [m.version, m]));
  const applied = (await appliedVersions(db)).reverse();
  const steps = opts.steps ?? 1;
  const done: number[] = [];
  for (const version of applied.slice(0, steps)) {
    const m = byVersion.get(version);
    if (!m) throw new Error(`primijenjena migracija ${String(version)} nema datoteku`);
    await inTransaction(db, async () => {
      await db.exec(m.down);
      await db.query('DELETE FROM vijesti.schema_migrations WHERE version = $1', [version]);
    });
    done.push(version);
  }
  return done;
}

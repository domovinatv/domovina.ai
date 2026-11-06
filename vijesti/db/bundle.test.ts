// Produkcijski paket migracija (odluke 730–733): primijenjen na praznu bazu daje
// istu shemu kao `migrateUp`, ne primjenjuje se na bazu u krivom stanju, a
// provjera nakon primjene (db/prod/verify.sql) prolazi i hvata pokvarena prava.
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { afterEach, describe, expect, it } from 'vitest';
import { bundleSql } from './bundle.js';
import { appliedVersions, loadMigrations, migrateUp, MIGRATIONS_DIR } from './migrate.js';

const PROD_DIR = join(MIGRATIONS_DIR, '..', 'prod');
const INSTALL = join(PROD_DIR, 'vijesti-install.sql');
const VERIFY = join(PROD_DIR, 'verify.sql');

/** Sve što čini shemu `vijesti`: relacije, stupci, ograničenja, indeksi, pogledi, funkcije, okidači, RLS, prava. */
async function signature(db: PGlite): Promise<Record<string, unknown[]>> {
  const q = async (sql: string) => (await db.query<Record<string, unknown>>(sql)).rows;
  return {
    columns: await q(`SELECT table_name, column_name, data_type, is_nullable, column_default, is_identity
      FROM information_schema.columns WHERE table_schema = 'vijesti' ORDER BY 1, 2`),
    constraints: await q(`SELECT c.conrelid::regclass::text AS rel, c.conname, pg_get_constraintdef(c.oid) AS def
      FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace WHERE n.nspname = 'vijesti' ORDER BY 1, 2`),
    indexes: await q(`SELECT indexname, indexdef FROM pg_indexes WHERE schemaname = 'vijesti' ORDER BY 1`),
    views: await q(`SELECT c.relname, pg_get_viewdef(c.oid) AS def, c.reloptions::text AS opts
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'vijesti' AND c.relkind = 'v' ORDER BY 1`),
    functions: await q(`SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosrc,
        p.prosecdef, p.provolatile, p.proconfig::text AS config, p.proacl::text AS acl
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'vijesti' ORDER BY 1, 2`),
    triggers: await q(`SELECT t.tgname, pg_get_triggerdef(t.oid) AS def FROM pg_trigger t
      JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'vijesti' AND NOT t.tgisinternal ORDER BY 1`),
    rls: await q(`SELECT c.relname, c.relkind::text AS kind, c.relrowsecurity, c.relforcerowsecurity, c.relacl::text AS acl
      FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'vijesti' ORDER BY 1`),
    policies: await q(`SELECT tablename, policyname, permissive, roles::text, cmd, qual, with_check
      FROM pg_policies WHERE schemaname = 'vijesti' ORDER BY 1, 2`),
    columnGrants: await q(`SELECT table_name, column_name, grantee, privilege_type FROM information_schema.column_privileges
      WHERE table_schema = 'vijesti' AND grantee IN ('anon', 'authenticated', 'service_role', 'PUBLIC') ORDER BY 1, 2, 3, 4`),
    schema: await q(`SELECT nspacl::text AS acl FROM pg_namespace WHERE nspname = 'vijesti'`),
    migrations: await q(`SELECT version, name FROM vijesti.schema_migrations ORDER BY version`),
  };
}

const fresh = async (): Promise<PGlite> => {
  const db = new PGlite();
  await db.waitReady;
  return db;
};

describe('produkcijski paket migracija', () => {
  const dbs: PGlite[] = [];
  const open = async () => {
    const db = await fresh();
    dbs.push(db);
    return db;
  };
  afterEach(async () => {
    await Promise.all(dbs.splice(0).map((d) => d.close()));
  });

  it('paket u repou je točno ono što generira `npm run db:bundle` (nema ručnih izmjena)', async () => {
    expect(await readFile(INSTALL, 'utf8')).toBe(bundleSql(await loadMigrations()));
  });

  it('na praznoj bazi daje istu shemu kao migrateUp', async () => {
    const viaRunner = await open();
    await migrateUp(viaRunner);
    const viaBundle = await open();
    await viaBundle.exec(await readFile(INSTALL, 'utf8'));
    const all = await loadMigrations();
    expect(await appliedVersions(viaBundle)).toEqual(all.map((m) => m.version));
    expect(await signature(viaBundle)).toEqual(await signature(viaRunner));
    // Runner i dalje radi nad bazom iz paketa (isto knjigovodstvo): nema ničeg za primijeniti.
    expect(await migrateUp(viaBundle)).toEqual([]);
  });

  it('ponovna primjena pada na provjeri stanja i ne mijenja ništa', async () => {
    const db = await open();
    const sql = await readFile(INSTALL, 'utf8');
    await db.exec(sql);
    const before = await signature(db);
    await expect(db.exec(sql)).rejects.toThrow(/baza ima migracije/);
    await db.exec('ROLLBACK');
    expect(await signature(db)).toEqual(before);
  });

  it('paket od N primjenjuje se samo na bazu s točno 1..N-1', async () => {
    const all = await loadMigrations();
    const last = all.at(-1)?.version ?? 0;
    const partial = await open();
    await migrateUp(partial, { to: last - 1 });
    await partial.exec(bundleSql(all, { from: last }));
    const full = await open();
    await migrateUp(full);
    expect(await signature(partial)).toEqual(await signature(full));

    const empty = await open();
    await expect(empty.exec(bundleSql(all, { from: last }))).rejects.toThrow(/očekivano/);
    await empty.exec('ROLLBACK');
    expect(() => bundleSql(all, { from: last + 1 })).toThrow(/nema migracija/);
  });

  it('provjera nakon primjene prolazi na ispravnoj shemi', async () => {
    const db = await open();
    await db.exec(await readFile(INSTALL, 'utf8'));
    await expect(db.exec(await readFile(VERIFY, 'utf8'))).resolves.toBeDefined();
  });

  it('provjera hvata pokvarena prava, isključen RLS i nedostajuću migraciju', async () => {
    const db = await open();
    await db.exec(await readFile(INSTALL, 'utf8'));
    await db.exec(`
      GRANT SELECT ON vijesti.staff TO anon;
      GRANT INSERT ON vijesti.articles TO authenticated;
      ALTER TABLE vijesti.runs DISABLE ROW LEVEL SECURITY;
      GRANT EXECUTE ON FUNCTION vijesti.publish_article(bigint, text) TO anon;
      DELETE FROM vijesti.schema_migrations WHERE version = 3;
    `);
    const err = await db.exec(await readFile(VERIFY, 'utf8')).catch((e: unknown) => e);
    await db.exec('ROLLBACK');
    const msg = (err as Error).message;
    expect(msg).toMatch(/provjera NIJE prošla \(5\)/);
    expect(msg).toMatch(/anon može čitati vijesti\.staff/);
    expect(msg).toMatch(/authenticated ima INSERT na vijesti\.articles/);
    expect(msg).toMatch(/RLS isključen: vijesti\.runs/);
    expect(msg).toMatch(/anon smije izvršiti vijesti\.publish_article/);
    expect(msg).toMatch(/schema_migrations nije 1\.\.N/);
  });
});

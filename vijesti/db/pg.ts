// Produkcijski Postgres za engine (odluka 808): `SqlDb` nad JEDNIM `pg.Client`.
//
// Jedna veza, ne pool: engine transakcije vodi kroz `exec('BEGIN')` …
// `exec('COMMIT')`, a pool bi naredbe iste transakcije poslao kroz različite
// veze. Engine je serijski (jedan poziv modela za drugim), pa pool ništa ne
// donosi.
//
// Tipovi se poravnavaju s PGliteom, na kojem su pisani i testirani svi
// potrošači (izmjereno 12.11.2026.):
//   int8 → number (pg: string). ID-evi i count(*) su daleko ispod 2^53.
//   date → Date u ponoć UTC (pg: ponoć po LOKALNOM vremenu, pa bi u Zagrebu
//          `toISOString().slice(0, 10)` vratio dan ranije).
// numeric ostaje string u oba. Parseri su po klijentu, ne globalni
// (`pg.types.setTypeParser` bi promijenio i tuđe veze u istom procesu).
import pg from 'pg';
import type { SqlDb } from './sql.js';

const INT8 = 20;
const INT8_ARRAY = 1016;
const DATE = 1082;

const parseDate = (v: string): Date => new Date(`${v}T00:00:00Z`);

/** Parsira tekstualni Postgres niz cijelih brojeva (`{1,2,NULL}`). */
export function parseInt8Array(v: string): (number | null)[] {
  const inner = v.slice(1, -1);
  if (inner === '') return [];
  return inner.split(',').map((x) => (x === 'NULL' ? null : Number(x)));
}

type TypeId = (typeof pg.types.builtins)[keyof typeof pg.types.builtins];

/** Parser za tekstualni oblik tipa `oid` (izvan tri gornja: zadani iz `pg`). */
export function typeParser(oid: number): (v: string) => unknown {
  if (oid === INT8) return Number;
  if (oid === INT8_ARRAY) return parseInt8Array;
  if (oid === DATE) return parseDate;
  // pg-types vraća `any`; oid je broj iz Postgresovog kataloga, ne član enuma.
  // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-enum-assignment, @typescript-eslint/no-unnecessary-type-assertion
  const parse: (v: string) => unknown = pg.types.getTypeParser(oid as TypeId, 'text');
  return parse;
}

export const pgTypes: pg.CustomTypesConfig = {
  getTypeParser: ((oid: TypeId, format?: 'text' | 'binary') =>
    // eslint-disable-next-line @typescript-eslint/no-unsafe-return
    format === 'binary' ? pg.types.getTypeParser(oid, 'binary') : typeParser(oid)) as pg.CustomTypesConfig['getTypeParser'],
};

export interface PgDb extends SqlDb {
  close(): Promise<void>;
}

/**
 * Spoji se na `url` (npr. `postgres://vijesti_engine:…@127.0.0.1:54329/postgres`).
 * `statement_timeout` čuva od zaglavljene naredbe kad tunel pukne usred upita.
 */
export async function connectPg(url: string, opts: { statementTimeoutMs?: number } = {}): Promise<PgDb> {
  const client = new pg.Client({
    connectionString: url,
    types: pgTypes,
    statement_timeout: opts.statementTimeoutMs ?? 60_000,
    application_name: 'vijesti-engine',
  });
  await client.connect();
  return {
    exec: (sql) => client.query(sql),
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
    async query<T>(sql: string, params?: unknown[]) {
      const res = await client.query(sql, params);
      // Tip retka daje pozivatelj (kao u PGliteu), pg ga ne zna.
      // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
      const rows: T[] = res.rows;
      return { rows };
    },
    close: () => client.end(),
  };
}

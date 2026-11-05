/**
 * Najmanje sučelje baze koje engine treba. PGlite ga zadovoljava izravno;
 * produkcijski Postgres (S7) dobiva tanak adapter.
 */
export interface SqlDb {
  /** Jedna ili više naredbi bez parametara. */
  exec(sql: string): Promise<unknown>;
  // T je tip retka koji pozivatelj očekuje (kao u PGlite i node-postgres).
  // eslint-disable-next-line @typescript-eslint/no-unnecessary-type-parameters
  query<T>(sql: string, params?: unknown[]): Promise<{ rows: T[] }>;
}

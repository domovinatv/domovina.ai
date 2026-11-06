// Baza s izvučenim i ocijenjenim trenucima epizode fixturea (lažni LLM, bez
// mreže): polazište testova generatora i provjere članka.
import { readFileSync } from 'node:fs';
import { PGlite } from '@electric-sql/pglite';
import { migrateUp } from '../../db/migrate.js';
import { createSqlRunRecorder } from '../../db/runs.js';
import { createCdnClient, type CdnClient } from '../cdn/loader.js';
import { PERSONS_FIXTURE } from '../cli.js';
import { createFakeExtractLlm } from '../extract/fake-llm.js';
import { runExtract } from '../extract/run.js';
import { createFakeScoreLlm } from '../score/fake-llm.js';
import { buildPersonIndex, parsePersons } from '../score/persons.js';
import { runScore } from '../score/run.js';
import { createFakeCdn } from './fake-cdn.js';

export const fixtureCdn = (): CdnClient => createCdnClient({ fetch: createFakeCdn().fetch });

export async function scoredDb(videoId: string, channel: string): Promise<PGlite> {
  const persons = buildPersonIndex(parsePersons(readFileSync(PERSONS_FIXTURE, 'utf8')).persons);
  const db = new PGlite();
  await db.waitReady;
  await migrateUp(db);
  const recorder = createSqlRunRecorder(db);
  await runExtract({ cdn: fixtureCdn(), llm: createFakeExtractLlm(recorder), recorder, db }, { videoId });
  await runScore({ cdn: fixtureCdn(), llm: createFakeScoreLlm(recorder), recorder, db, persons }, { videoId, channel });
  return db;
}

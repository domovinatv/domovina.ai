import type { z } from 'zod';
import { LlmSchemaError } from './types.js';

/** Parsira tekst modela kao JSON i validira shemom. Ništa se ne popravlja. */
export function parseLlmJson<S extends z.ZodType>(raw: string, schema: S): z.infer<S> {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch (e) {
    throw new LlmSchemaError(`izlaz modela nije JSON: ${(e as Error).message}`, raw);
  }
  const res = schema.safeParse(value);
  if (!res.success) {
    const issues = res.error.issues
      .slice(0, 5)
      .map((i) => `${i.path.join('.') || '(korijen)'}: ${i.message}`)
      .join('; ');
    throw new LlmSchemaError(`izlaz modela ne prolazi shemu: ${issues}`, raw);
  }
  return res.data;
}

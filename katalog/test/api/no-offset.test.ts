// `OFFSET` je zabranjen (odluke 8, 304): paginacija je samo keyset. Test čita
// izvorni kod (odluka 117) i pada ako se `OFFSET` pojavi igdje izvan komentara.
import { describe, expect, it } from "vitest";

const sources = import.meta.glob<string>("../../src/**/*.ts", { query: "?raw", import: "default", eager: true });

/** Kod bez komentara: `/* … *\/` i `// …` do kraja retka. */
export function stripComments(code: string): string {
  return code.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}

const OFFSET = /\bOFFSET\b/i;

describe("bez OFFSET-a", () => {
  it("izvorni kod je učitan", () => {
    expect(Object.keys(sources)).toContain("../../src/db/queries.ts");
    expect(Object.keys(sources)).toContain("../../src/api/v1.ts");
  });

  it.each(Object.entries(sources))("%s", (_path, code) => {
    expect(stripComments(code)).not.toMatch(OFFSET);
  });

  it("provjera bi uhvatila OFFSET u SQL-u, i malim slovima", () => {
    expect(stripComments("const q = `SELECT 1 LIMIT ?1 OFFSET ?2`;")).toMatch(OFFSET);
    expect(stripComments("const q = `select 1 limit 10 offset 20`;")).toMatch(OFFSET);
    expect(stripComments("// OFFSET ne postoji\n/* ni OFFSET */ const x = 1;")).not.toMatch(OFFSET);
  });
});

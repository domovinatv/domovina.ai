// Glavni modul (`main` u wrangler.jsonc) smije imenovano izvoziti samo
// entrypointe. workerd svaki imenovani export glavnog modula čita kao
// entrypoint i odbija sve što nije funkcija/klasa ili ExportedHandler:
// `export const API_PREFIX` u `src/index.ts` rušio je `wrangler dev`
// („Incorrect type for map entry 'API_PREFIX'”), a vitest pool to ne vidi
// jer glavni modul uvozi drukčije (odluka 312).
import { describe, expect, it } from "vitest";
import * as main from "../src/index.ts";

describe("glavni modul", () => {
  it("imenovani exporti su samo funkcije ili klase (entrypointi)", () => {
    const bad = Object.entries(main)
      .filter(([name]) => name !== "default")
      .filter(([, value]) => typeof value !== "function")
      .map(([name]) => name);
    expect(bad).toEqual([]);
  });

  it("default je ExportedHandler s fetch", () => {
    expect(typeof main.default.fetch).toBe("function");
  });
});

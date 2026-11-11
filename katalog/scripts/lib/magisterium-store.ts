// Datotečno spremište cachea Magisterium ocjena (odluka 1206). Odvojeno od
// `magisterium-scores.ts` jer testovi idu u workerd, gdje `node:fs` nema.
import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { ScoreStore } from "./magisterium-scores.ts";

export function fileStore(path: string): ScoreStore {
  return {
    async read() {
      try {
        return await readFile(path, "utf8");
      } catch {
        return null;
      }
    },
    async write(text) {
      await mkdir(dirname(path), { recursive: true });
      const tmp = `${path}.${String(process.pid)}.tmp`;
      await writeFile(tmp, text);
      await rename(tmp, path);
    },
  };
}

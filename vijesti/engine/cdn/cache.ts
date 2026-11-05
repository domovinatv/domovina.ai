// Disk cache za CDN odgovore (`vijesti/.cache/cdn/<putanja>`). Per-epizoda
// datoteke su immutable i čuvaju se zauvijek; promjenjive (episode.json,
// listinzi) imaju rok, nakon kojeg se traže iznova.
import { mkdir, readFile, stat, writeFile, rename } from 'node:fs/promises';
import { dirname, join, normalize, sep } from 'node:path';

export interface DiskCache {
  /** Sadržaj ako postoji i nije stariji od `maxAgeMs` (bez roka: zauvijek). */
  get(path: string, maxAgeMs?: number): Promise<string | null>;
  set(path: string, body: string): Promise<void>;
}

function safeJoin(root: string, path: string): string {
  const rel = normalize(path).replace(/^([/\\])+/, '');
  if (rel.split(sep).includes('..')) throw new Error(`neispravna putanja za cache: ${path}`);
  return join(root, rel);
}

export function createDiskCache(root: string, now: () => number = Date.now): DiskCache {
  return {
    async get(path, maxAgeMs) {
      const file = safeJoin(root, path);
      try {
        if (maxAgeMs !== undefined) {
          const st = await stat(file);
          if (now() - st.mtimeMs > maxAgeMs) return null;
        }
        return await readFile(file, 'utf8');
      } catch (e) {
        if ((e as NodeJS.ErrnoException).code === 'ENOENT') return null;
        throw e;
      }
    },
    async set(path, body) {
      const file = safeJoin(root, path);
      await mkdir(dirname(file), { recursive: true });
      // Atomarno: prekinut zapis ne smije ostaviti pola datoteke u cacheu.
      const tmp = `${file}.${String(process.pid)}.tmp`;
      await writeFile(tmp, body, 'utf8');
      await rename(tmp, file);
    },
  };
}

// Gemini kroz `agy` (Antigravity CLI) u tmux sesiji, na Google AI Pro pretplati
// (odluke 315, 400–404). Po uzoru na `fetch.domovina.tv/lib/agy_tmux.js`:
// `agy -p` ne vraća odgovor, pa upit ide kroz interaktivnu sesiju. Upit se
// zapiše u datoteku, agy dobije jednu rečenicu („pročitaj X, zapiši JSON u Y”)
// i čeka se da Y nastane. Pozivi kroz jedan klijent se SERIJALIZIRAJU (jedna
// sesija = jedan razgovor). Gledanje: `tmux attach -t =agyvij -r`.
//
// agy ne vraća tokene ni `blockReason`: tokeni se procjenjuju iz znakova
// (odluka 305) i poziv se tako označi u `runs`, a odbijen upit izgleda kao
// timeout (zamka iz pipelinea, 28.10.2026.).
//
// Sloj tmux/datoteke (`AgyIo`) je ubrizgan: testovi ne pokreću ni tmux ni agy.
import { execFile } from 'node:child_process';
import { mkdir, readFile, rm, stat, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import type { z } from 'zod';
import { estimateTokens } from './estimate.js';
import { toGeminiSchema } from './gemini.js';
import type { RunRecorder } from './runs.js';
import { LlmResponseError, LlmSchemaError, type GenerateRequest, type LlmClient } from './types.js';
import { parseLlmJson } from './validate.js';

/** Model kao u pipelineu (`AGY_MODEL` u `fetch.domovina.tv/lib/agy_tmux.js`). */
export const DEFAULT_AGY_MODEL = 'gemini-3.8-flash-high';
/** Vlastita sesija: pipeline koristi `agyen`, `agyss`, `agyt`, globalna skripta `agyg`. */
export const DEFAULT_AGY_SESSION = 'agyvij';
/** Isti korijen kao pipeline: direktorij mora biti „trusted” za agy, prvi put se potvrđuje sam. */
export const DEFAULT_AGY_ROOT = join(homedir(), 'git', '.agy-tmux');
export const DEFAULT_AGY_TIMEOUT_MS = 600_000;

/** Tmux i datotečni sloj. Prava izvedba: `createTmuxAgyIo`. */
export interface AgyIo {
  hasSession(session: string): Promise<boolean>;
  /** Nova odvojena sesija u `cwd` koja odmah pokrene `command`. */
  newSession(session: string, cwd: string, command: string): Promise<void>;
  /** Doslovan tekst pa Enter (kao `send-keys -l` + `Enter`). */
  sendText(session: string, text: string): Promise<void>;
  sendKey(session: string, key: 'Enter' | 'Escape'): Promise<void>;
  capture(session: string): Promise<string>;
  killSession(session: string): Promise<void>;
  mkdir(dir: string): Promise<void>;
  writeFile(path: string, text: string): Promise<void>;
  readFile(path: string): Promise<string>;
  /** `null` kad datoteke nema. */
  stat(path: string): Promise<{ size: number; mtimeMs: number } | null>;
  rm(path: string): Promise<void>;
  sleep(ms: number): Promise<void>;
  now(): number;
}

export interface AgyTimings {
  /** Najdulje čekanje da se agy pokrene (prompt „for shortcuts”). */
  startupMs: number;
  /** Pauza nakon `/clear`. */
  clearMs: number;
  /** Razmak provjera izlazne datoteke. */
  pollMs: number;
  /** Druga provjera veličine: agy zna pisati datoteku u dva poteza. */
  settleMs: number;
  /** Koliko neispravan JSON mora stajati nepromijenjen prije zahtjeva za popravak sintakse. */
  badJsonSettleMs: number;
  /** Produljenje roka nakon zahtjeva za popravak. */
  repairTimeoutMs: number;
  maxJsonRepairs: number;
}

export const DEFAULT_AGY_TIMINGS: AgyTimings = {
  startupMs: 60_000,
  clearMs: 3000,
  pollMs: 3000,
  settleMs: 1500,
  badJsonSettleMs: 20_000,
  repairTimeoutMs: 360_000,
  maxJsonRepairs: 2,
};

export interface AgyClientOptions {
  io: AgyIo;
  recorder: RunRecorder;
  model?: string;
  session?: string;
  /** Radni direktorij sesije; zadano `<DEFAULT_AGY_ROOT>/<session>`. */
  dir?: string;
  timeoutMs?: number;
  timings?: Partial<AgyTimings>;
  /** Dio imena datoteke upita (zadano PID); testovi daju stalnu vrijednost. */
  tag?: string;
}

/** Nema izlazne datoteke do roka. Kod agyja to uključuje i ODBIJEN upit (nema `blockReason`). */
export class AgyTimeoutError extends LlmResponseError {
  constructor(message: string) {
    super(message);
    this.name = 'AgyTimeoutError';
  }
}

/** Sesija se nije pokrenula (prijava, `agy` nije instaliran). Zahtjev nije poslan: nije poziv. */
export class AgyStartError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AgyStartError';
  }
}

/** Tekst datoteke upita: uputa, JSON Schema izlaza i ulaz. agy nema `responseJsonSchema`. */
export function buildAgyRequest(req: Pick<GenerateRequest<z.ZodType>, 'prompt' | 'schema' | 'system'>): string {
  const schema = JSON.stringify(toGeminiSchema(req.schema), null, 1);
  return [
    '# UPUTA',
    '',
    req.system ?? 'Odgovori isključivo JSON objektom.',
    '',
    'Izlaz je JEDAN JSON objekt koji prolazi JSON Schemu iz odjeljka SHEMA. Bez proze i bez ograđivača koda.',
    '',
    '# SHEMA',
    '',
    schema,
    '',
    '# ULAZ',
    '',
    req.prompt,
    '',
  ].join('\n');
}

/** Rečenica koja ide u agy. Ista kao u pipelineu, uz odjeljak SHEMA. */
export function agyInstruction(stem: string): string {
  return (
    `Read the file ${stem}.md and do exactly what its UPUTA section says with its ULAZ section; ` +
    `the output must validate against the JSON Schema in its SHEMA section. ` +
    `Write ONLY the resulting JSON to the file ${stem}.json — no prose, no code fences. ` +
    `Do not run scripts or other tools besides reading that file and writing that one file.`
  );
}

export function agyRepairInstruction(stem: string, why: string): string {
  return (
    `The file ${stem}.json is not valid JSON (${why}). Fix ONLY the JSON syntax ` +
    `(quotes, escapes, commas, brackets) and write the corrected JSON back to ${stem}.json. ` +
    `Do not change, add or remove any content. No prose, no code fences.`
  );
}

/**
 * Skida samo omot koji nije sadržaj: BOM i JEDAN ograđivač ```json … ``` oko
 * cijelog teksta. Proza oko objekta se NE reže (za razliku od `parseLoose` u
 * pipelineu): takav izlaz nije JSON i ide u popravak sintakse ili pada.
 */
export function unwrapAgyOutput(text: string): string {
  const t = text.replace(/^\uFEFF/, '').trim();
  const m = /^```(?:json)?\s*\n?([\s\S]*?)\n?```$/i.exec(t);
  return (m?.[1] ?? t).trim();
}

function isJsonSyntaxOk(text: string): string | null {
  try {
    JSON.parse(text);
    return null;
  } catch (e) {
    return (e as Error).message;
  }
}

export function createAgyClient(opts: AgyClientOptions): LlmClient & { readonly session: string } {
  const io = opts.io;
  const agyModel = opts.model ?? DEFAULT_AGY_MODEL;
  const session = opts.session ?? DEFAULT_AGY_SESSION;
  if (!/^[A-Za-z0-9_-]+$/.test(session)) throw new Error(`neispravno ime tmux sesije: ${session}`);
  const dir = opts.dir ?? join(DEFAULT_AGY_ROOT, session);
  const timeoutMs = opts.timeoutMs ?? DEFAULT_AGY_TIMEOUT_MS;
  const t: AgyTimings = { ...DEFAULT_AGY_TIMINGS, ...opts.timings };
  const tag = opts.tag ?? String(process.pid);
  const model = `agy:${agyModel}`;
  let ready = false;
  let seq = 0;
  let queue: Promise<unknown> = Promise.resolve();

  async function ensureSession(): Promise<void> {
    if (ready && (await io.hasSession(session))) return;
    ready = false;
    await io.mkdir(dir);
    if (!(await io.hasSession(session))) {
      await io.newSession(session, dir, `agy --model ${agyModel} --dangerously-skip-permissions`);
    }
    const until = io.now() + t.startupMs;
    while (io.now() < until) {
      await io.sleep(1000);
      const screen = await io.capture(session);
      // Novi direktorij: agy pita za povjerenje. Prva opcija je „Yes”.
      if (/trust the contents/i.test(screen)) {
        await io.sendKey(session, 'Enter');
        continue;
      }
      if (screen.includes('for shortcuts')) {
        ready = true;
        return;
      }
    }
    await io.killSession(session);
    throw new AgyStartError(`agy se nije pokrenuo u tmux sesiji ${session} (prijava? pokreni \`agy\` ručno)`);
  }

  /** Vraća sirovi tekst izlazne datoteke (sintaksno valjan JSON) ili baca. */
  async function ask(request: string): Promise<string> {
    await ensureSession();
    const stem = `req-${tag}-${String(++seq)}-${String(io.now())}`;
    const reqFile = join(dir, `${stem}.md`);
    const outFile = join(dir, `${stem}.json`);
    await io.writeFile(reqFile, request);
    try {
      await io.sendText(session, '/clear');
      await io.sleep(t.clearMs);
      // /clear zna proći kao običan tekst (pipeline, 29.10.2026.): tada kontekst raste
      // od upita do upita. Ekran nakon pravog /clear nema starih upita.
      if ((await io.capture(session)).includes('Read the file req-')) {
        await io.killSession(session);
        ready = false;
        await ensureSession();
      }
      await io.sendText(session, agyInstruction(stem));
      // Neparsabilan izlaz nije „još piše” (pipeline, 29.10.2026.): kad se datoteka
      // smiri, a nije JSON, agy dobije kratki potez da popravi samo sintaksu.
      let deadline = io.now() + timeoutMs;
      let repairs = 0;
      let badMtime = 0;
      let badSince = 0;
      let repairSentAt = 0;
      while (io.now() < deadline) {
        await io.sleep(t.pollMs);
        const s1 = await io.stat(outFile);
        if (!s1) continue;
        await io.sleep(t.settleMs);
        const s2 = await io.stat(outFile);
        if (!s2 || s2.size !== s1.size || s2.mtimeMs !== s1.mtimeMs) continue;
        if (repairSentAt && s2.mtimeMs <= repairSentAt) continue;
        const raw = await io.readFile(outFile);
        const text = unwrapAgyOutput(raw);
        const err = isJsonSyntaxOk(text);
        if (err === null) return text;
        if (s2.mtimeMs !== badMtime) {
          badMtime = s2.mtimeMs;
          badSince = io.now();
          continue;
        }
        if (io.now() - badSince < t.badJsonSettleMs) continue;
        if (repairs >= t.maxJsonRepairs) {
          throw new LlmSchemaError(
            `agy: izlaz nije valjan JSON ni nakon ${String(repairs)} popravka (${err})`,
            raw,
          );
        }
        repairs++;
        repairSentAt = io.now();
        await io.sendText(session, agyRepairInstruction(stem, err));
        deadline = Math.max(deadline, io.now() + t.repairTimeoutMs);
      }
      // Prekini zaglavljeni potez, inače /clear i idući upit čekaju u redu iza njega.
      await io.sendKey(session, 'Escape');
      await io.sleep(2000);
      await io.sendKey(session, 'Escape');
      throw new AgyTimeoutError(
        `agy: nema odgovora nakon ${String(Math.round(timeoutMs / 1000))} s (sesija ${session}; ` +
          'agy nema blockReason, pa i odbijen upit izgleda ovako)',
      );
    } finally {
      await io.rm(reqFile);
      await io.rm(outFile);
    }
  }

  return {
    model,
    session,
    generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      const run = queue.then(async () => {
        const request = buildAgyRequest(req);
        const tokensIn = estimateTokens(request);
        const record = (out: string, ok: boolean) =>
          opts.recorder.recordCall(req.runId, {
            model,
            tokensIn,
            tokensOut: estimateTokens(out),
            // Pretplata: stvarni trošak je $0; API-ekvivalent računa izvještaj (odluka 403).
            costUsd: 0,
            ok,
            tokensEstimated: true,
          });
        let text: string;
        try {
          text = await ask(request);
        } catch (e) {
          // Sesija se nije digla: upit nije poslan, nije poziv (kao token u odluci 300).
          if (e instanceof AgyStartError) throw e;
          await record(e instanceof LlmSchemaError ? e.raw : '', false);
          throw e;
        }
        try {
          const data = parseLlmJson(text, req.schema);
          await record(text, true);
          return data;
        } catch (e) {
          await record(text, false);
          throw e;
        }
      });
      queue = run.catch(() => undefined);
      return run;
    },
  };
}

/** `tmux` s argumentima, bez ljuske. Vraća izlazni kod i stdout. */
export type TmuxExec = (args: string[]) => Promise<{ code: number; stdout: string }>;

const defaultTmuxExec: TmuxExec = (args) =>
  new Promise((resolve) => {
    execFile('tmux', args, { encoding: 'utf8', timeout: 15_000 }, (err, stdout) => {
      const code = err ? (typeof err.code === 'number' ? err.code : 1) : 0;
      resolve({ code, stdout });
    });
  });

/**
 * Pravi sloj: `tmux` kroz execFile (bez ljuske) i node:fs. Cilj sesije uvijek
 * s `=` (točno ime): tmux inače radi prefix matching i `agy` bi pogodio `agyvij`.
 */
export function createTmuxAgyIo(opts: { exec?: TmuxExec; sendDelayMs?: number } = {}): AgyIo {
  const tmuxRun = opts.exec ?? defaultTmuxExec;
  const sendDelayMs = opts.sendDelayMs ?? 500;
  const tmuxOk = async (args: string[]): Promise<void> => {
    const r = await tmuxRun(args);
    if (r.code !== 0) throw new Error(`tmux ${args[0] ?? ''} nije uspio (kod ${String(r.code)})`);
  };
  const target = (s: string) => `=${s}`;
  const pane = (s: string) => `=${s}:`;
  return {
    async hasSession(s) {
      return (await tmuxRun(['has-session', '-t', target(s)])).code === 0;
    },
    async newSession(s, cwd, command) {
      await tmuxOk(['new-session', '-d', '-s', s, '-x', '180', '-y', '50', '-c', cwd]);
      await tmuxOk(['send-keys', '-t', pane(s), command, 'Enter']);
    },
    async sendText(s, text) {
      await tmuxOk(['send-keys', '-t', pane(s), '-l', text]);
      await new Promise((r) => setTimeout(r, sendDelayMs));
      await tmuxOk(['send-keys', '-t', pane(s), 'Enter']);
    },
    async sendKey(s, key) {
      await tmuxOk(['send-keys', '-t', pane(s), key]);
    },
    async capture(s) {
      return (await tmuxRun(['capture-pane', '-p', '-t', pane(s)])).stdout;
    },
    async killSession(s) {
      await tmuxRun(['kill-session', '-t', target(s)]);
    },
    async mkdir(d) {
      await mkdir(d, { recursive: true });
    },
    writeFile: (p, text) => writeFile(p, text, 'utf8'),
    readFile: (p) => readFile(p, 'utf8'),
    async stat(p) {
      try {
        const s = await stat(p);
        return { size: s.size, mtimeMs: s.mtimeMs };
      } catch {
        return null;
      }
    },
    rm: (p) => rm(p, { force: true }),
    sleep: (ms) => new Promise((r) => setTimeout(r, ms)),
    now: () => Date.now(),
  };
}

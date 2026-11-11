// Claude kroz `claude -p` (Claude Code CLI) na pretplati korisnika (odluka 802).
// Za razliku od agyja (odluka 400) nema tmuxa: `claude -p` je neinteraktivan,
// prima upit na stdin, poštuje `--json-schema` i vraća JSON s
// `structured_output` i STVARNIM tokenima (`usage`), pa trošak nije procjena.
//
// Izolacija poziva: bez alata (`--tools ""`), bez MCP-a, bez korisnikovih
// postavki i hookova (`--setting-sources ""`), bez spremanja sesije. Model je
// zadano Sonnet: pretplata je kvota, a ulaz su već kvalitetni tekstovi (Opus
// članci i sažetci iz pipelinea), pa Opus nije potreban (globalno pravilo o
// tokenima).
//
// Proces je ubrizgan (`ClaudeExec`): testovi ne pokreću `claude`.
import { execFile } from 'node:child_process';
import type { z } from 'zod';
import { toGeminiSchema } from './gemini.js';
import type { RunRecorder } from './runs.js';
import { LlmSchemaError, LlmTimeoutError, type GenerateRequest, type LlmClient } from './types.js';
import { parseLlmJson } from './validate.js';

export const DEFAULT_CLAUDE_MODEL = 'sonnet';
export const DEFAULT_CLAUDE_TIMEOUT_MS = 600_000;

/** Pokreće `claude` s argumentima i stdinom; nikad kroz ljusku. */
export type ClaudeExec = (
  args: string[],
  stdin: string,
  timeoutMs: number,
) => Promise<{ code: number; stdout: string; stderr: string; timedOut: boolean }>;

export interface ClaudeClientOptions {
  recorder: RunRecorder;
  exec?: ClaudeExec;
  /** Alias ili puni ID (`sonnet`, `claude-sonnet-5-5`). */
  model?: string;
  timeoutMs?: number;
}

/** Dio izlaza `claude -p --output-format json` koji koristimo. */
interface ClaudeResult {
  is_error?: boolean;
  subtype?: string;
  result?: string;
  structured_output?: unknown;
  api_error_status?: number | null;
  usage?: {
    input_tokens?: number;
    cache_creation_input_tokens?: number;
    cache_read_input_tokens?: number;
    output_tokens?: number;
  };
}

export class ClaudeCallError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'ClaudeCallError';
  }
}

export function claudeArgs(model: string, system: string, schema: unknown): string[] {
  return [
    '-p',
    '--model',
    model,
    '--output-format',
    'json',
    '--tools',
    '',
    '--strict-mcp-config',
    '--setting-sources',
    '',
    '--no-session-persistence',
    '--system-prompt',
    system,
    '--json-schema',
    JSON.stringify(schema),
  ];
}

const defaultExec: ClaudeExec = (args, stdin, timeoutMs) =>
  new Promise((resolve) => {
    const child = execFile(
      'claude',
      args,
      { encoding: 'utf8', timeout: timeoutMs, maxBuffer: 64 * 1024 * 1024 },
      (err, stdout, stderr) => {
        const timedOut = Boolean(err && (err as NodeJS.ErrnoException & { killed?: boolean }).killed);
        const code = err ? (typeof err.code === 'number' ? err.code : 1) : 0;
        resolve({ code, stdout, stderr, timedOut });
      },
    );
    child.stdin?.end(stdin);
  });

function tokens(u: ClaudeResult['usage']): { tokensIn: number; tokensOut: number } {
  return {
    tokensIn: (u?.input_tokens ?? 0) + (u?.cache_creation_input_tokens ?? 0) + (u?.cache_read_input_tokens ?? 0),
    tokensOut: u?.output_tokens ?? 0,
  };
}

export function createClaudeClient(opts: ClaudeClientOptions): LlmClient {
  const exec = opts.exec ?? defaultExec;
  const cliModel = opts.model ?? DEFAULT_CLAUDE_MODEL;
  const timeoutMs = opts.timeoutMs ?? DEFAULT_CLAUDE_TIMEOUT_MS;
  const model = `claude:${cliModel}`;

  return {
    model,
    async generate<S extends z.ZodType>(req: GenerateRequest<S>): Promise<z.infer<S>> {
      const system =
        (req.system ?? 'Odgovori isključivo JSON objektom.') +
        '\n\nIzlaz je JEDAN JSON objekt koji prolazi zadanu JSON Schemu.';
      const args = claudeArgs(cliModel, system, toGeminiSchema(req.schema));
      const record = (t: { tokensIn: number; tokensOut: number }, ok: boolean) =>
        opts.recorder.recordCall(req.runId, {
          model,
          ...t,
          // Pretplata: stvarni trošak je $0; tokeni su izmjereni, ne procijenjeni.
          costUsd: 0,
          ok,
        });

      const r = await exec(args, req.prompt, timeoutMs);
      if (r.timedOut) {
        await record({ tokensIn: 0, tokensOut: 0 }, false);
        throw new LlmTimeoutError(`claude -p: nema odgovora u ${String(timeoutMs / 1000)} s`);
      }
      let out: ClaudeResult;
      try {
        out = JSON.parse(r.stdout) as ClaudeResult;
      } catch {
        await record({ tokensIn: 0, tokensOut: 0 }, false);
        const why = (r.stderr || r.stdout).trim().slice(0, 300);
        throw new ClaudeCallError(`claude -p (kod ${String(r.code)}) nije vratio JSON: ${why}`);
      }
      const t = tokens(out.usage);
      if (out.is_error || r.code !== 0) {
        await record(t, false);
        const status = out.api_error_status ? ` HTTP ${String(out.api_error_status)}` : '';
        throw new ClaudeCallError(
          `claude -p greška (${out.subtype ?? '?'}${status}): ${(out.result ?? '').slice(0, 300)}`,
        );
      }
      const text =
        out.structured_output !== undefined && out.structured_output !== null
          ? JSON.stringify(out.structured_output)
          : (out.result ?? '');
      try {
        const data = parseLlmJson(text, req.schema);
        await record(t, true);
        return data;
      } catch (e) {
        await record(t, false);
        if (e instanceof LlmSchemaError) throw e;
        throw e;
      }
    },
  };
}

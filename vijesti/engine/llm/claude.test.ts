import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { claudeArgs, createClaudeClient, type ClaudeExec } from './claude.js';
import { createLlmFromConfig, describeLlmConfig, llmConfigFromEnv } from './config.js';
import { MemoryRunRecorder } from './runs.js';
import { LlmSchemaError, LlmTimeoutError } from './types.js';

const schema = z.object({ n: z.number().int() });
const usage = { input_tokens: 2, cache_creation_input_tokens: 1000, cache_read_input_tokens: 10, output_tokens: 50 };

function fakeExec(reply: Partial<Awaited<ReturnType<ClaudeExec>>>, seen: { args?: string[]; stdin?: string } = {}): ClaudeExec {
  return (args, stdin) => {
    seen.args = args;
    seen.stdin = stdin;
    return Promise.resolve({ code: 0, stdout: '', stderr: '', timedOut: false, ...reply });
  };
}

async function setup(exec: ClaudeExec) {
  const recorder = new MemoryRunRecorder();
  const runId = await recorder.startRun({ step: 't', model: 'claude:sonnet' });
  return { recorder, runId, llm: createClaudeClient({ recorder, exec }) };
}

describe('claude -p backend (odluka 802)', () => {
  it('structured_output prolazi shemu; tokeni su izmjereni, trošak $0', async () => {
    const seen: { args?: string[]; stdin?: string } = {};
    const { llm, recorder, runId } = await setup(
      fakeExec({ stdout: JSON.stringify({ is_error: false, result: '{"n":4}', structured_output: { n: 4 }, usage }) }, seen),
    );
    await expect(llm.generate({ prompt: 'ULAZ', schema, runId, system: 'SUSTAV' })).resolves.toEqual({ n: 4 });
    expect(seen.stdin).toBe('ULAZ');
    expect(seen.args).toContain('--json-schema');
    expect(seen.args?.[seen.args.indexOf('--tools') + 1]).toBe('');
    expect(seen.args?.[seen.args.indexOf('--system-prompt') + 1]).toMatch(/^SUSTAV/);
    const run = recorder.runs.get(runId);
    expect(run).toMatchObject({ calls: 1, failedCalls: 0, tokensIn: 1012, tokensOut: 50, tokensEstimated: false });
  });

  it('bez structured_output čita `result`', async () => {
    const { llm, runId } = await setup(fakeExec({ stdout: JSON.stringify({ result: '{"n":7}', usage }) }));
    await expect(llm.generate({ prompt: 'x', schema, runId })).resolves.toEqual({ n: 7 });
  });

  it('izlaz koji ne prolazi shemu je neuspio poziv, ne popravlja se', async () => {
    const { llm, recorder, runId } = await setup(fakeExec({ stdout: JSON.stringify({ structured_output: { n: 'četiri' }, usage }) }));
    await expect(llm.generate({ prompt: 'x', schema, runId })).rejects.toBeInstanceOf(LlmSchemaError);
    expect(recorder.runs.get(runId)).toMatchObject({ calls: 1, failedCalls: 1 });
  });

  it('is_error (npr. limit pretplate) baca s porukom', async () => {
    const { llm, runId } = await setup(
      fakeExec({ code: 1, stdout: JSON.stringify({ is_error: true, subtype: 'error', result: 'usage limit reached', api_error_status: 429 }) }),
    );
    await expect(llm.generate({ prompt: 'x', schema, runId })).rejects.toThrow(/HTTP 429.*usage limit/);
  });

  it('timeout je LlmTimeoutError, a ne-JSON stdout jasna greška', async () => {
    const a = await setup(fakeExec({ timedOut: true, code: 1 }));
    await expect(a.llm.generate({ prompt: 'x', schema, runId: a.runId })).rejects.toBeInstanceOf(LlmTimeoutError);
    const b = await setup(fakeExec({ code: 127, stderr: 'claude: command not found' }));
    await expect(b.llm.generate({ prompt: 'x', schema, runId: b.runId })).rejects.toThrow(/command not found/);
  });

  it('konfiguracija: VIJESTI_LLM_BACKEND=claude, zadano sonnet, cijena pretplate', () => {
    const cfg = llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'claude' });
    expect(cfg.backend).toBe('claude');
    expect(cfg.claude.model).toBe('sonnet');
    expect(cfg.pricingSource).toBe('subscription');
    expect(describeLlmConfig(cfg)).toMatch(/claude -p model=sonnet/);
    expect(llmConfigFromEnv({ VIJESTI_LLM_BACKEND: 'claude', VIJESTI_CLAUDE_MODEL: 'opus' }).claude.model).toBe('opus');
    const llm = createLlmFromConfig(cfg, {
      fetch: () => Promise.reject(new Error('ne zove se')),
      recorder: new MemoryRunRecorder(),
      claudeExec: fakeExec({}),
    });
    expect(llm.model).toBe('claude:sonnet');
    expect(claudeArgs('sonnet', 's', {})).toEqual(expect.arrayContaining(['--no-session-persistence', '--strict-mcp-config']));
  });
});

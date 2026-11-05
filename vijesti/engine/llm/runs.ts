// Zapis LLM prolaza u `vijesti.runs`. Sučelje je odvojeno od baze da lažni
// klijent i testovi mogu brojati pozive bez Postgresa; SQL izvedba je u
// db/runs.ts.

export interface RunStart {
  step: string;
  model: string;
  videoId?: string;
  promptVersion?: string;
}

export interface LlmCallRecord {
  model: string;
  tokensIn: number;
  tokensOut: number;
  /** `null` kad cijena modela nije poznata. */
  costUsd: number | null;
  /** `false` za HTTP grešku, prazan odgovor ili izlaz koji ne prolazi shemu. */
  ok: boolean;
}

export interface RunRecorder {
  startRun(run: RunStart): Promise<number>;
  recordCall(runId: number, call: LlmCallRecord): Promise<void>;
  finishRun(runId: number, result: { status: 'ok' | 'failed'; error?: string }): Promise<void>;
}

export interface RunTotals {
  id: number;
  step: string;
  model: string;
  status: 'running' | 'ok' | 'failed';
  calls: number;
  failedCalls: number;
  tokensIn: number;
  tokensOut: number;
  costUsd: number | null;
}

/** Recorder u memoriji (testovi, suhi prolazi). */
export class MemoryRunRecorder implements RunRecorder {
  readonly runs = new Map<number, RunTotals>();
  private next = 1;

  startRun(run: RunStart): Promise<number> {
    const id = this.next++;
    this.runs.set(id, {
      id,
      step: run.step,
      model: run.model,
      status: 'running',
      calls: 0,
      failedCalls: 0,
      tokensIn: 0,
      tokensOut: 0,
      costUsd: 0,
    });
    return Promise.resolve(id);
  }

  recordCall(runId: number, call: LlmCallRecord): Promise<void> {
    const r = this.get(runId);
    r.calls++;
    if (!call.ok) r.failedCalls++;
    r.tokensIn += call.tokensIn;
    r.tokensOut += call.tokensOut;
    r.costUsd = r.costUsd === null || call.costUsd === null ? null : r.costUsd + call.costUsd;
    return Promise.resolve();
  }

  finishRun(runId: number, result: { status: 'ok' | 'failed' }): Promise<void> {
    this.get(runId).status = result.status;
    return Promise.resolve();
  }

  get(runId: number): RunTotals {
    const r = this.runs.get(runId);
    if (!r) throw new Error(`nepoznat run ${String(runId)}`);
    return r;
  }
}

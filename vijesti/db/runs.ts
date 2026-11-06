// RunRecorder nad Postgresom (PGlite u testovima): tablica vijesti.runs.
import type { LlmCallRecord, RunRecorder, RunStart, RunTotals } from '../engine/llm/runs.js';
import type { SqlDb } from './sql.js';

interface RunRow {
  id: number | string;
  step: string;
  model: string;
  status: RunTotals['status'];
  calls: number;
  failed_calls: number;
  tokens_in: string | number;
  tokens_out: string | number;
  cost_usd: string | number | null;
  tokens_estimated: boolean;
}

export function createSqlRunRecorder(db: SqlDb): RunRecorder & {
  totals(runId: number): Promise<RunTotals>;
} {
  return {
    async startRun(run: RunStart) {
      const res = await db.query<{ id: number | string }>(
        `INSERT INTO vijesti.runs (step, model, video_id, prompt_version, cost_usd)
         VALUES ($1, $2, $3, $4, 0) RETURNING id`,
        [run.step, run.model, run.videoId ?? null, run.promptVersion ?? null],
      );
      const id = res.rows[0]?.id;
      if (id === undefined) throw new Error('INSERT u vijesti.runs nije vratio id');
      return Number(id);
    },
    async recordCall(runId: number, call: LlmCallRecord) {
      // Nepoznata cijena jednog poziva čini ukupni trošak nepoznatim (NULL).
      const res = await db.query(
        `UPDATE vijesti.runs SET
           calls = calls + 1,
           failed_calls = failed_calls + CASE WHEN $2 THEN 0 ELSE 1 END,
           tokens_in = tokens_in + $3,
           tokens_out = tokens_out + $4,
           cost_usd = cost_usd + $5::numeric,
           tokens_estimated = tokens_estimated OR $6
         WHERE id = $1 RETURNING id`,
        [runId, call.ok, call.tokensIn, call.tokensOut, call.costUsd, call.tokensEstimated === true],
      );
      if (res.rows.length !== 1) throw new Error(`nepoznat run ${String(runId)}`);
    },
    async finishRun(runId, result) {
      await db.query(
        `UPDATE vijesti.runs SET status = $2, error = $3, finished_at = now() WHERE id = $1`,
        [runId, result.status, result.error ?? null],
      );
    },
    async totals(runId: number) {
      const res = await db.query<RunRow>(
        `SELECT id, step, model, status, calls, failed_calls, tokens_in, tokens_out, cost_usd,
                tokens_estimated
         FROM vijesti.runs WHERE id = $1`,
        [runId],
      );
      const r = res.rows[0];
      if (!r) throw new Error(`nepoznat run ${String(runId)}`);
      return {
        id: Number(r.id),
        step: r.step,
        model: r.model,
        status: r.status,
        calls: r.calls,
        failedCalls: r.failed_calls,
        tokensIn: Number(r.tokens_in),
        tokensOut: Number(r.tokens_out),
        costUsd: r.cost_usd === null ? null : Number(r.cost_usd),
        tokensEstimated: r.tokens_estimated,
      };
    },
  };
}

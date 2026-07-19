import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { acceptTaskResult } from "../../../../../../lib/db/repositories/tasks";

type TaskResult = {
  contract_version: "v0";
  task_id: string;
  attempt: number;
  status: "succeeded";
  safe_checkpoint: string | null;
  raw_count: number;
  canonical_count: number;
  duplicate_count: number;
  unresolved_count: number;
  unparsed_media_count: number;
  structured_run_ids: string[];
  summary_batch_ids?: string[];
  daily_summary_ids?: string[];
  telemetry: { elapsed_ms: number; retry_count: number; failure_class: string | null };
};

export async function POST(
  request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  let result: TaskResult;
  try {
    result = parseContract<TaskResult>("task-result", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_task_result" }, { status: 422 });
  }
  if (result.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });
  try {
    return NextResponse.json(await acceptTaskResult(taskId, result.attempt, result, { worker_id: worker.id, persisted: true }));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_duplicate_result" }, { status: 409 });
    if (code === "55000") {
      const message = typeof error === "object" && error && "message" in error ? String(error.message) : "";
      return NextResponse.json({ error: message.includes("summary_receipt_mismatch") ? "summary_receipt_mismatch" : "persistence_not_confirmed" }, { status: 422 });
    }
    return NextResponse.json({ error: "result_rejected" }, { status: 503 });
  }
}

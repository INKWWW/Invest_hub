import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { recordTaskFailure } from "../../../../../../lib/db/repositories/tasks";

type TaskFailure = {
  contract_version: "v0";
  task_id: string;
  attempt: number;
  status: "retryable_failed" | "failed" | "cancelled";
  failure_class: string;
  failure_stage?: string;
  safe_checkpoint: string | null;
  retryable: boolean;
};

export async function POST(
  request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  let failure: TaskFailure;
  try {
    failure = parseContract<TaskFailure>("task-failure", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_task_failure" }, { status: 422 });
  }
  if (failure.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });
  try {
    return NextResponse.json(await recordTaskFailure(taskId, failure.attempt, failure, { worker_id: worker.id }));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_duplicate_failure" }, { status: 409 });
    return NextResponse.json({ error: "failure_rejected" }, { status: 503 });
  }
}

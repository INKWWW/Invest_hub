import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { persistWindowedCapturePage, persistWorkerExecution } from "../../../../../../lib/db/repositories/tasks";
import type { Json } from "../../../../../../lib/db/types";

type WorkerPersistencePayload = {
  contract_version: "v0";
  task_id: string;
  attempt: number;
  source_id: string;
  raw_messages: unknown[];
  canonical_messages: unknown[];
  structured_runs: unknown[];
  batch_summaries?: unknown[];
  capture_segment?: Json;
};

export async function POST(
  request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  const { taskId } = await context.params;
  let payload: WorkerPersistencePayload;
  try {
    payload = parseContract<WorkerPersistencePayload>("worker-persistence", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_worker_persistence" }, { status: 422 });
  }
  if (payload.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });

  try {
    if (payload.capture_segment) {
      return NextResponse.json(await persistWindowedCapturePage(taskId, payload.attempt, worker.id, payload as Json));
    }
    const persisted = await persistWorkerExecution(taskId, payload.attempt, worker.id, payload as Json);
    return NextResponse.json(persisted);
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_capture_segment" }, { status: 409 });
    if (code === "22023") return NextResponse.json({ error: "invalid_worker_persistence" }, { status: 422 });
    return NextResponse.json({ error: "persistence_rejected" }, { status: 503 });
  }
}

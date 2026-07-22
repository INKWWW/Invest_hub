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

const safeValidationFailureCodes = new Set([
  "invalid_capture_segment",
  "invalid_evidence_reference",
  "invalid_windowed_page_persistence",
  "invalid_worker_persistence",
  "raw_canonical_mismatch",
  "structured_run_mismatch",
]);

const safeConflictFailureCodes = new Set([
  "conflicting_capture_segment",
  "conflicting_raw_message",
  "conflicting_canonical_message",
  "conflicting_structured_run",
  "conflicting_persistence_receipt",
]);

function safeValidationFailureCode(error: unknown): string | undefined {
  const message = typeof error === "object" && error && "message" in error ? error.message : undefined;
  return typeof message === "string" && safeValidationFailureCodes.has(message) ? message : undefined;
}

function safeConflictFailureCode(error: unknown): string | undefined {
  const message = typeof error === "object" && error && "message" in error ? error.message : undefined;
  return typeof message === "string" && safeConflictFailureCodes.has(message) ? message : undefined;
}

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
    if (code === "23505") {
      const failureCode = safeConflictFailureCode(error);
      return NextResponse.json({
        error: "conflicting_worker_persistence",
        ...(failureCode ? { failure_code: failureCode } : {}),
      }, { status: 409 });
    }
    if (code === "22023") {
      const failureCode = safeValidationFailureCode(error);
      return NextResponse.json({
        error: "invalid_worker_persistence",
        ...(failureCode ? { failure_code: failureCode } : {}),
      }, { status: 422 });
    }
    return NextResponse.json({ error: "persistence_rejected" }, { status: 503 });
  }
}

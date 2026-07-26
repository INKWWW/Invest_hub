import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { completeWindowedCaptureRange } from "../../../../../../lib/db/repositories/tasks";
import type { Json } from "../../../../../../lib/db/types";

type RangeCompletionPayload = {
  contract_version: "v0";
  task_id: string;
  attempt: number;
  range_complete: true;
  capture_range: Json;
  boundary: Json;
  summary_batch_ids: string[];
  daily_summary_ids: string[];
  x_post_analyses?: Json[];
  x_daily_segments?: Json[];
  no_new_data: boolean;
};

export async function POST(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const startedAt = Date.now();
  const reportStage = (stage: string) => {
    console.info("range_completion_stage", { stage, elapsed_ms: Math.max(0, Date.now() - startedAt) });
  };
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  reportStage("authenticated");
  const { taskId } = await context.params;
  reportStage("params_resolved");

  let payload: RangeCompletionPayload;
  try {
    const body = await request.json();
    reportStage("body_parsed");
    payload = parseContract<RangeCompletionPayload>("window-range-completion", body);
    reportStage("contract_parsed");
  } catch {
    return NextResponse.json({ error: "invalid_range_completion" }, { status: 422 });
  }
  if (payload.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });
  reportStage("payload_validated");

  try {
    reportStage("rpc_started");
    const completion = await completeWindowedCaptureRange(taskId, payload.attempt, worker.id, payload as Json, request.signal);
    reportStage("rpc_succeeded");
    return NextResponse.json(completion);
  } catch (error) {
    reportStage("rpc_rejected");
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_range_completion" }, { status: 409 });
    if (code === "22023") return NextResponse.json({ error: "invalid_range_completion" }, { status: 422 });
    if (code === "55000") return NextResponse.json({ error: "persistence_not_confirmed" }, { status: 422 });
    return NextResponse.json({ error: "range_completion_rejected" }, { status: 503 });
  }
}

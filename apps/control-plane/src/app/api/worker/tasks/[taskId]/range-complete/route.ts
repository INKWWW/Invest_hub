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
  no_new_data: boolean;
};

export async function POST(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;

  let payload: RangeCompletionPayload;
  try {
    payload = parseContract<RangeCompletionPayload>("window-range-completion", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_range_completion" }, { status: 422 });
  }
  if (payload.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });

  try {
    return NextResponse.json(await completeWindowedCaptureRange(taskId, payload.attempt, worker.id, payload as Json));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_range_completion" }, { status: 409 });
    if (code === "22023") return NextResponse.json({ error: "invalid_range_completion" }, { status: 422 });
    if (code === "55000") return NextResponse.json({ error: "persistence_not_confirmed" }, { status: 422 });
    return NextResponse.json({ error: "range_completion_rejected" }, { status: 503 });
  }
}

import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { recordWindowedCaptureSegment } from "../../../../../../lib/db/repositories/tasks";
import type { Json } from "../../../../../../lib/db/types";

type CaptureSegmentPayload = {
  contract_version: "v0";
  task_id: string;
  attempt: number;
  capture_segment: Json;
};

export async function POST(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;

  let payload: CaptureSegmentPayload;
  try {
    payload = parseContract<CaptureSegmentPayload>("task-capture-segment", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_capture_segment" }, { status: 422 });
  }
  if (payload.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });

  try {
    return NextResponse.json(await recordWindowedCaptureSegment(taskId, payload.attempt, worker.id, payload.capture_segment));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "23505") return NextResponse.json({ error: "conflicting_capture_segment" }, { status: 409 });
    if (code === "22023") return NextResponse.json({ error: "invalid_capture_segment" }, { status: 422 });
    return NextResponse.json({ error: "capture_segment_rejected" }, { status: 503 });
  }
}

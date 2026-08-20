import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { claimXDemoFixedWindowTask } from "../../../../../../lib/db/repositories/tasks";

export async function POST(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  if (!taskId) return NextResponse.json({ error: "invalid_fixed_window_claim_request" }, { status: 422 });
  try {
    const claim = await claimXDemoFixedWindowTask(taskId, worker.id);
    return claim === null ? new NextResponse(null, { status: 204 }) : NextResponse.json(claim);
  } catch (error) {
    const message = error && typeof error === "object" && "message" in error && typeof error.message === "string" ? error.message : "";
    if (message === "worker_not_authorized") return NextResponse.json({ error: message }, { status: 403 });
    return NextResponse.json({ error: "fixed_window_claim_failed" }, { status: 503 });
  }
}

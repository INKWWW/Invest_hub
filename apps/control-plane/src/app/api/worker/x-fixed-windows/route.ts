import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../lib/auth/worker";
import { createXDemoFixedWindowTaskForWorker, TaskScopeError } from "../../../../lib/db/repositories/tasks";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_fixed_window_request" }, { status: 422 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return NextResponse.json({ error: "invalid_fixed_window_request" }, { status: 422 });
  const value = body as Record<string, unknown>;
  if (typeof value.source_id !== "string" || typeof value.cutoff_at !== "string" || typeof value.account_id !== "string") {
    return NextResponse.json({ error: "invalid_fixed_window_request" }, { status: 422 });
  }
  try {
    const task = await createXDemoFixedWindowTaskForWorker({
      sourceId: value.source_id,
      cutoffAt: value.cutoff_at,
      workerId: worker.id,
      accountId: value.account_id,
    });
    return NextResponse.json(task);
  } catch (error) {
    const message = error && typeof error === "object" && "message" in error && typeof error.message === "string" ? error.message : "";
    if (message === "worker_not_authorized") return NextResponse.json({ error: message }, { status: 403 });
    if (message === "x_source_unresolved" || message === "x_source_identity_mismatch" || message === "future_x_demo_cutoff" || message === "invalid_x_demo_cutoff" || error instanceof TaskScopeError) {
      return NextResponse.json({ error: message || "invalid_fixed_window_request" }, { status: 422 });
    }
    return NextResponse.json({ error: "fixed_window_creation_failed" }, { status: 503 });
  }
}

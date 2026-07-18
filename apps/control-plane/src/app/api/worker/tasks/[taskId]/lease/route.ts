import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { renewTaskLease } from "../../../../../../lib/db/repositories/tasks";

export async function POST(
  request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  let body: { attempt?: number };
  try {
    body = (await request.json()) as { attempt?: number };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  const attempt = body.attempt;
  if (typeof attempt !== "number" || !Number.isInteger(attempt) || attempt < 1) {
    return NextResponse.json({ error: "invalid_attempt" }, { status: 422 });
  }
  try {
    return NextResponse.json(await renewTaskLease(taskId, attempt, worker.id));
  } catch (error) {
    if (typeof error === "object" && error && "code" in error && error.code === "40001") {
      return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    }
    return NextResponse.json({ error: "lease_renew_failed" }, { status: 503 });
  }
}

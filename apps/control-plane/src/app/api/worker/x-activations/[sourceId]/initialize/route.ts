import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { initializeXActivation, XActivationError } from "../../../../../../lib/db/repositories/x-activations";

export async function POST(request: Request, context: { params: Promise<{ sourceId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { sourceId } = await context.params;
  if (!/^[0-9a-f-]{36}$/i.test(sourceId)) return NextResponse.json({ error: "invalid_x_activation" }, { status: 422 });
  try {
    const activation = await initializeXActivation({ sourceId, workerId: worker.id, now: new Date().toISOString() });
    return NextResponse.json({ activation: {
      task_id: activation.taskId,
      source_id: activation.sourceId,
      initial_end_at: activation.initialEndAt,
      idempotent: activation.idempotent,
    } });
  } catch (error) {
    if (error instanceof XActivationError && error.message === "worker_not_authorized") return NextResponse.json({ error: "worker_not_authorized" }, { status: 403 });
    if (error instanceof XActivationError && error.message === "x_source_unresolved") return NextResponse.json({ error: "x_source_unresolved" }, { status: 422 });
    return NextResponse.json({ error: "x_activation_initialize_failed" }, { status: 503 });
  }
}

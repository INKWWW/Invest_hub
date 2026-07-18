import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { parseContract } from "../../../../../../lib/contracts";
import { recordTaskEvent } from "../../../../../../lib/db/repositories/tasks";

export async function POST(
  request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  try {
    const event = parseContract<{ task_id: string; attempt: number; event_type: string; occurred_at: string; details: Record<string, unknown> }>(
      "task-event",
      await request.json(),
    );
    if (event.task_id !== taskId) return NextResponse.json({ error: "task_mismatch" }, { status: 409 });
    return NextResponse.json(await recordTaskEvent(event));
  } catch {
    return NextResponse.json({ error: "event_rejected" }, { status: 422 });
  }
}

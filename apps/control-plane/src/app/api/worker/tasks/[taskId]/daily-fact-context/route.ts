import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { getWindowDailyFactContext } from "../../../../../../lib/db/repositories/tasks";

export async function GET(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { taskId } = await context.params;
  const attempt = Number(new URL(request.url).searchParams.get("attempt"));
  if (!Number.isInteger(attempt) || attempt < 1) {
    return NextResponse.json({ error: "invalid_daily_fact_context" }, { status: 422 });
  }
  try {
    return NextResponse.json(await getWindowDailyFactContext(taskId, attempt, worker.id));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "daily_fact_context_rejected" }, { status: 503 });
  }
}

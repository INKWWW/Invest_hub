import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { getXDailyJudgementContext } from "../../../../../../lib/db/repositories/x-daily-judgements";

function isAttemptRequest(value: unknown): value is { attempt: number } {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === 1 && typeof (value as { attempt?: unknown }).attempt === "number"
    && Number.isInteger((value as { attempt: number }).attempt) && (value as { attempt: number }).attempt > 0;
}

export async function POST(request: Request, context: { params: Promise<{ runId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_daily_judgement_context" }, { status: 422 });
  }
  if (!isAttemptRequest(body)) return NextResponse.json({ error: "invalid_x_daily_judgement_context" }, { status: 422 });
  const { runId } = await context.params;
  try {
    return NextResponse.json(await getXDailyJudgementContext(runId, body.attempt, worker.id));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_daily_judgement_context_failed" }, { status: 503 });
  }
}

import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import {
  failXDailyJudgement,
  type XDailyJudgementFailureClass,
} from "../../../../../../lib/db/repositories/x-daily-judgements";

const failureClasses = new Set<XDailyJudgementFailureClass>([
  "timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure",
]);

function isFailureRequest(value: unknown): value is { attempt: number; failure_class: XDailyJudgementFailureClass } {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === 2 && typeof (value as { attempt?: unknown }).attempt === "number"
    && Number.isInteger((value as { attempt: number }).attempt) && (value as { attempt: number }).attempt > 0
    && typeof (value as { failure_class?: unknown }).failure_class === "string"
    && failureClasses.has((value as { failure_class: XDailyJudgementFailureClass }).failure_class);
}

export async function POST(request: Request, context: { params: Promise<{ runId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_daily_judgement_failure" }, { status: 422 });
  }
  if (!isFailureRequest(body)) return NextResponse.json({ error: "invalid_x_daily_judgement_failure" }, { status: 422 });
  const { runId } = await context.params;
  try {
    return NextResponse.json(await failXDailyJudgement(runId, body.attempt, worker.id, body.failure_class));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_daily_judgement_failure_rejected" }, { status: 503 });
  }
}

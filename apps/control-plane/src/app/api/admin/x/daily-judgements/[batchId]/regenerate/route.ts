import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../../lib/auth/require-role";
import { regenerateXDailyJudgement } from "../../../../../../../lib/db/repositories/x-daily-judgements";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isEmptyJsonObject(value: unknown): value is Record<string, never> {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0;
}

export async function POST(
  request: Request,
  context: { params: Promise<{ batchId: string }> },
) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  try {
    const { batchId } = await context.params;
    const body: unknown = await request.json();
    if (!uuidPattern.test(batchId) || !isEmptyJsonObject(body)) {
      return NextResponse.json({ error: "invalid_x_daily_judgement_regeneration" }, { status: 422 });
    }
    const regeneration = await regenerateXDailyJudgement(batchId, current.id);
    return NextResponse.json({
      runId: regeneration.runId,
      status: regeneration.status,
      attempt: regeneration.attempt,
    }, { status: 202 });
  } catch {
    return NextResponse.json({ error: "x_daily_judgement_regeneration_failed" }, { status: 503 });
  }
}

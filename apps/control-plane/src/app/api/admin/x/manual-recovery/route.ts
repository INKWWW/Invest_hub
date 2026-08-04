import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createManualXRecoveryRun } from "../../../../../lib/db/repositories/x-daily-judgements";

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json() as unknown;
    if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 0) {
      return NextResponse.json({ error: "invalid_manual_x_recovery" }, { status: 422 });
    }
    const run = await createManualXRecoveryRun(current.id);
    return NextResponse.json({ run: { status: run.status, target_cutoff_at: run.targetCutoffAt, idempotent: run.idempotent } }, { status: 202 });
  } catch {
    return NextResponse.json({ error: "manual_x_recovery_create_failed" }, { status: 503 });
  }
}

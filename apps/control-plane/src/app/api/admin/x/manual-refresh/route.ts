import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createManualXRefresh, XSourceError } from "../../../../../lib/db/repositories/x-sources";

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json() as Record<string, unknown>;
    if (Object.keys(body).length !== 1 || typeof body.source_id !== "string" || !body.source_id) return NextResponse.json({ error: "invalid_manual_refresh" }, { status: 422 });
    const task = await createManualXRefresh({ sourceId: body.source_id, actorId: current.id });
    return NextResponse.json({ task: { id: task.id, source_id: task.sourceId, status: task.status, trigger: "manual", start_at: task.startAt, end_at: task.endAt, idempotent: task.idempotent } }, { status: 202 });
  } catch (error) {
    if (error instanceof XSourceError) return NextResponse.json({ error: error.message }, { status: error.message === "coverage_not_initialized" ? 409 : 422 });
    return NextResponse.json({ error: "x_manual_refresh_create_failed" }, { status: 503 });
  }
}

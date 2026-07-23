import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createBoundedXHistory, XSourceError } from "../../../../../lib/db/repositories/x-sources";

function validInstant(value: unknown): value is string {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json() as Record<string, unknown>;
    if (Object.keys(body).length !== 3 || typeof body.source_id !== "string" || !body.source_id || !validInstant(body.start_at) || !validInstant(body.end_at)
      || Date.parse(body.start_at) >= Date.parse(body.end_at) || Date.parse(body.end_at) > Date.now()) {
      return NextResponse.json({ error: "invalid_history_range" }, { status: 422 });
    }
    const task = await createBoundedXHistory({ sourceId: body.source_id, actorId: current.id, startAt: body.start_at, endAt: body.end_at });
    return NextResponse.json({ task: { id: task.id, source_id: task.sourceId, status: task.status, trigger: "history", start_at: task.startAt, end_at: task.endAt } }, { status: 202 });
  } catch (error) {
    if (error instanceof XSourceError) return NextResponse.json({ error: error.message }, { status: error.message === "active_x_range_overlap" ? 409 : 422 });
    return NextResponse.json({ error: "x_history_create_failed" }, { status: 503 });
  }
}

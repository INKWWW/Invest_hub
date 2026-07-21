import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createManualDiscordRefresh, WindowedSyncError } from "../../../../../lib/db/repositories/windowed-sync";

function validBody(value: unknown): value is { source_id: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 1 && typeof body.source_id === "string" && body.source_id.length > 0;
}
export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json();
    if (!validBody(body)) return NextResponse.json({ error: "invalid_manual_refresh" }, { status: 422 });

    const task = await createManualDiscordRefresh({ sourceId: body.source_id, requestedBy: current.id });
    return NextResponse.json({
      task: {
        id: task.id,
        source_id: task.sourceId,
        status: task.status,
        trigger: task.trigger,
        start_at: task.startAt,
        end_at: task.endAt,
        queued_at: task.queuedAt,
        idempotent: task.idempotent,
      },
    }, { status: 202 });
  } catch (error) {
    if (error instanceof WindowedSyncError && error.message === "coverage_not_initialized") {
      return NextResponse.json({ error: error.message }, { status: 409 });
    }
    return NextResponse.json({ error: "manual_refresh_create_failed" }, { status: 503 });
  }
}

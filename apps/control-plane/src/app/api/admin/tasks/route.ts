import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import { createDiscordSyncTask, listRecentTasks } from "../../../../lib/db/repositories/tasks";

export async function GET() {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    return NextResponse.json({ tasks: await listRecentTasks() });
  } catch {
    return NextResponse.json({ error: "task_list_failed" }, { status: 503 });
  }
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (typeof body.source_id !== "string" || typeof body.parameter_version !== "string") {
      return NextResponse.json({ error: "invalid_task" }, { status: 422 });
    }
    const task = await createDiscordSyncTask({
      sourceId: body.source_id,
      parameterVersion: body.parameter_version,
      requestedBy: current.id,
    });
    return NextResponse.json({ task }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "task_create_failed" }, { status: 503 });
  }
}

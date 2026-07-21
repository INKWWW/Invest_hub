import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import { createDiscordSyncTask, listRecentTasks, type TaskScope } from "../../../../lib/db/repositories/tasks";

function hasOnlyKeys(body: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(body).every((key) => allowed.includes(key));
}

function parseTaskScope(value: unknown): TaskScope | null {
  if (value === undefined) return null;
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const scope = value as Record<string, unknown>;
  if (Object.keys(scope).some((key) => key !== "mode" && key !== "max_pages")
    || (scope.mode !== "incremental" && scope.mode !== "history")
    || !Number.isInteger(scope.max_pages)
    || (scope.max_pages as number) < 1
    || (scope.max_pages as number) > 25
    || (scope.mode === "incremental" && (scope.max_pages as number) > 5)) {
    return null;
  }
  return { mode: scope.mode, maxPages: scope.max_pages as number };
}

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
    const scope = parseTaskScope(body.scope);
    if (!hasOnlyKeys(body, ["source_id", "parameter_version", "scope"])
      || typeof body.source_id !== "string" || typeof body.parameter_version !== "string" || !scope) {
      return NextResponse.json({ error: "invalid_task" }, { status: 422 });
    }
    const task = await createDiscordSyncTask({
      sourceId: body.source_id,
      parameterVersion: body.parameter_version,
      requestedBy: current.id,
      scope,
    });
    return NextResponse.json({ task }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "task_create_failed" }, { status: 503 });
  }
}

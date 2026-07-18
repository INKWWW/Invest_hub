import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../lib/auth/require-role";
import { retryTask } from "../../../../../../lib/db/repositories/tasks";

export async function POST(
  _request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { taskId } = await context.params;
  try {
    const task = await retryTask(taskId, current.id);
    if (!task) return NextResponse.json({ error: "task_not_retryable" }, { status: 409 });
    return NextResponse.json({ task });
  } catch {
    return NextResponse.json({ error: "task_retry_failed" }, { status: 503 });
  }
}

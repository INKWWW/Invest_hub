import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../../lib/auth/current-user";
import { getDemoRun } from "../../../../../lib/db/repositories/agent-demo-runs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function GET(_request: Request, context: { params: Promise<{ runId: string }> }) {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { runId } = await context.params;
  if (!uuidPattern.test(runId)) return NextResponse.json({ error: "invalid_run_id" }, { status: 422 });
  try {
    const run = await getDemoRun(current.id, runId);
    if (!run) return NextResponse.json({ error: "run_not_found" }, { status: 404 });
    return NextResponse.json({ run: {
      id: run.id,
      thread_id: run.threadId,
      request_id: run.requestId,
      status: run.status,
      invocation_mode: run.invocationMode,
      skill_id: run.skillId,
      user_message_id: run.userMessageId,
      assistant_message_id: run.assistantMessageId,
      provider: run.provider,
      created_at: run.createdAt,
      started_at: run.startedAt,
      completed_at: run.completedAt,
    } });
  } catch {
    return NextResponse.json({ error: "run_read_failed" }, { status: 503 });
  }
}

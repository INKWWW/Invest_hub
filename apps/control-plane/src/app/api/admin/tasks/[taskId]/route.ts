import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { buildTaskViewModel } from "../../../../../lib/admin/view-model";
import { getTaskDetail } from "../../../../../lib/db/repositories/tasks";

export async function GET(
  _request: Request,
  context: { params: Promise<{ taskId: string }> },
) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { taskId } = await context.params;
  try {
    const detail = await getTaskDetail(taskId);
    if (!detail) return NextResponse.json({ error: "task_not_found" }, { status: 404 });
    const latestAttempt = detail.attempts[0];
    const task = buildTaskViewModel({
      ...detail.task,
      attempt: latestAttempt?.attempt,
      result: latestAttempt?.result,
      failure: latestAttempt?.failure,
    });
    return NextResponse.json({
      task,
      attempts: detail.attempts.map((attempt) => ({
        id: attempt.id,
        attempt: attempt.attempt,
        status: attempt.status,
        lease_expires_at: attempt.lease_expires_at,
        started_at: attempt.started_at,
        completed_at: attempt.completed_at,
      })),
      events: detail.events.map((event) => ({
        id: event.id,
        attempt: event.attempt,
        event_type: event.event_type,
        occurred_at: event.occurred_at,
        failure_class: safeFailureClass(event.details),
      })),
      structured_runs: detail.structuredRuns.map((run) => ({
        id: run.id,
        provider: run.provider,
        parameter_version: run.parameter_version,
        created_at: run.created_at,
      })),
      evidence_refs: detail.evidenceRefs.map((ref) => ({ id: ref.id, evidence_kind: ref.evidence_kind })),
    });
  } catch {
    return NextResponse.json({ error: "task_detail_failed" }, { status: 503 });
  }
}

function safeFailureClass(details: unknown): string | null {
  if (!details || typeof details !== "object" || Array.isArray(details)) return null;
  const value = (details as Record<string, unknown>).failure_class;
  return typeof value === "string" ? value : null;
}


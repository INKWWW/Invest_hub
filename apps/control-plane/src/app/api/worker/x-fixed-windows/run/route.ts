import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { claimXDemoFixedWindowJudgement } from "../../../../../lib/db/repositories/x-daily-judgements";
import {
  beginXDemoFixedWindowRun,
  bindXDemoFixedWindowTask,
  createXDemoFixedWindowTaskForRun,
  failXDemoFixedWindowSource,
  settleXDemoFixedWindowRun,
  terminalizeXDemoFixedWindowJudgement,
  TaskScopeError,
} from "../../../../../lib/db/repositories/tasks";

function text(value: unknown): value is string {
  return typeof value === "string" && value.length > 0;
}

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_demo_fixed_window_run_request" }, { status: 422 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return NextResponse.json({ error: "invalid_x_demo_fixed_window_run_request" }, { status: 422 });
  const value = body as Record<string, unknown>;
  const action = value.action;
  try {
    if (action === "start" && text(value.cutoff_at)) {
      return NextResponse.json(await beginXDemoFixedWindowRun(value.cutoff_at, worker.id));
    }
    if (action === "create_task" && text(value.run_id) && text(value.source_id) && text(value.cutoff_at) && text(value.account_id)) {
      return NextResponse.json(await createXDemoFixedWindowTaskForRun({
        runId: value.run_id, sourceId: value.source_id, cutoffAt: value.cutoff_at,
        workerId: worker.id, accountId: value.account_id,
      }));
    }
    if (action === "bind_task" && text(value.run_id) && text(value.source_id) && text(value.task_id)) {
      return NextResponse.json(await bindXDemoFixedWindowTask({ runId: value.run_id, sourceId: value.source_id, taskId: value.task_id, workerId: worker.id }));
    }
    if (action === "source_failure" && text(value.run_id) && text(value.source_id) && text(value.reason)) {
      return NextResponse.json(await failXDemoFixedWindowSource({ runId: value.run_id, sourceId: value.source_id, reason: value.reason, workerId: worker.id }));
    }
    if (action === "settle" && text(value.run_id)) {
      return NextResponse.json(await settleXDemoFixedWindowRun(value.run_id, worker.id));
    }
    if (action === "claim_judgement" && text(value.run_id)) {
      const claim = await claimXDemoFixedWindowJudgement(value.run_id, worker.id);
      return claim ? NextResponse.json(claim) : new NextResponse(null, { status: 204 });
    }
    if (action === "judgement_failure" && text(value.run_id) && text(value.judgement_run_id)) {
      return NextResponse.json(await terminalizeXDemoFixedWindowJudgement({
        demoRunId: value.run_id, judgementRunId: value.judgement_run_id, workerId: worker.id,
      }));
    }
    return NextResponse.json({ error: "invalid_x_demo_fixed_window_run_request" }, { status: 422 });
  } catch (error) {
    const message = error && typeof error === "object" && "message" in error && typeof error.message === "string" ? error.message : "";
    if (message === "worker_not_authorized") return NextResponse.json({ error: message }, { status: 403 });
    if (error instanceof TaskScopeError || [
      "invalid_x_demo_fixed_window_run", "invalid_x_demo_fixed_window_task", "invalid_x_demo_fixed_window_judgement", "invalid_x_demo_fixed_window_task_binding", "invalid_x_demo_fixed_window_source_failure",
      "invalid_x_demo_fixed_window_settlement", "invalid_x_demo_cutoff", "x_demo_fixed_window_batch_not_available", "x_demo_fixed_window_snapshot_changed", "x_source_identity_mismatch", "x_demo_sources_not_ready",
    ].includes(message)) return NextResponse.json({ error: message || "invalid_x_demo_fixed_window_run_request" }, { status: 422 });
    return NextResponse.json({ error: "x_demo_fixed_window_run_failed" }, { status: 503 });
  }
}

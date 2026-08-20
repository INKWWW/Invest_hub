import { createSupabaseAdminClient } from "../supabase-server";
import type { Database, Json } from "../types";
import { advanceXManualRecoveryRuns, ensureDueXCollectionBatches } from "./x-daily-judgements";

export type TaskScope = {
  mode: "incremental" | "history";
  maxPages: number;
};

export class TaskScopeError extends Error {}

export type ScheduledTask = {
  id: string;
  source_id: string;
  idempotent: boolean;
};

export type DemoFixedWindowTask = {
  id: string;
  source_id: string;
  idempotent: boolean;
  demo_fixed_window: Json;
};

export type DemoFixedWindowRun = {
  run_id: string;
  status: string;
  idempotent: boolean;
  cutoff_at: string;
  sources: Array<Record<string, unknown>>;
};

export type ScheduledTick = {
  window_key: string;
  tasks: ScheduledTask[];
};

export type DueScheduledTick = {
  scheduled_at: string;
  tasks: ScheduledTask[];
  deferred_source_ids: string[];
};

export type DueSourceScheduledTick = DueScheduledTick & {
  judgement_dispatch_failed: boolean;
};

const scheduleWindowPattern = /^\d{4}-\d{2}-\d{2}T(?:08:00|20:50)\+08:00$/;

export function isScheduleWindowKey(value: unknown): value is string {
  return typeof value === "string" && scheduleWindowPattern.test(value);
}

function assertTaskScope(scope: TaskScope): void {
  if (!Number.isInteger(scope.maxPages) || scope.maxPages < 1 || scope.maxPages > 25
    || (scope.mode === "incremental" && scope.maxPages > 5)) {
    throw new TaskScopeError("invalid_collection_scope");
  }
}

export async function createDiscordSyncTask(input: {
  sourceId: string;
  parameterVersion: string;
  requestedBy: string;
  scope: TaskScope;
}) {
  assertTaskScope(input.scope);
  const { data, error } = await createSupabaseAdminClient()
    .rpc("create_discord_sync_task", {
      p_source_id: input.sourceId,
      p_parameter_version: input.parameterVersion,
      p_requested_by: input.requestedBy,
      p_scope: { mode: input.scope.mode, max_pages: input.scope.maxPages },
    });
  if (error) throw error;
  if (!data || typeof data !== "object") throw new Error("invalid_created_task");
  return data as Database["public"]["Tables"]["sync_tasks"]["Row"];
}

export async function createXDemoFixedWindowTaskForWorker(input: {
  sourceId: string;
  cutoffAt: string;
  workerId: string;
  accountId: string;
}): Promise<DemoFixedWindowTask> {
  if (![input.sourceId, input.cutoffAt, input.workerId, input.accountId].every((value) => typeof value === "string" && value.length > 0)) {
    throw new TaskScopeError("invalid_fixed_window_request");
  }
  const client = createSupabaseAdminClient() as unknown as {
    rpc(name: string, args: Record<string, string>): Promise<{ data: unknown; error: { message?: string } | null }>;
  };
  const { data, error } = await client.rpc("create_x_demo_fixed_window_task_for_worker", {
    p_source_id: input.sourceId,
    p_cutoff_at: input.cutoffAt,
    p_worker_id: input.workerId,
    p_account_id: input.accountId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_created_fixed_window");
  const value = data as Record<string, unknown>;
  if (typeof value.id !== "string" || value.source_id !== input.sourceId || typeof value.idempotent !== "boolean" || !value.demo_fixed_window || typeof value.demo_fixed_window !== "object") {
    throw new TaskScopeError("invalid_created_fixed_window");
  }
  return {
    id: value.id,
    source_id: value.source_id as string,
    idempotent: value.idempotent,
    demo_fixed_window: value.demo_fixed_window as Json,
  };
}

export async function createXDemoFixedWindowTaskForRun(input: {
  runId: string;
  sourceId: string;
  cutoffAt: string;
  workerId: string;
  accountId: string;
}): Promise<DemoFixedWindowTask> {
  if (![input.runId, input.sourceId, input.cutoffAt, input.workerId, input.accountId].every((value) => typeof value === "string" && value.length > 0)) {
    throw new TaskScopeError("invalid_x_demo_fixed_window_task");
  }
  const { data, error } = await createSupabaseAdminClient().rpc("create_x_demo_fixed_window_task_for_run", {
    p_run_id: input.runId, p_source_id: input.sourceId, p_cutoff_at: input.cutoffAt,
    p_worker_id: input.workerId, p_account_id: input.accountId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_x_demo_fixed_window_task");
  const value = data as Record<string, unknown>;
  if (typeof value.id !== "string" || value.source_id !== input.sourceId || typeof value.idempotent !== "boolean" || !value.demo_fixed_window || typeof value.demo_fixed_window !== "object") {
    throw new TaskScopeError("invalid_x_demo_fixed_window_task");
  }
  return { id: value.id, source_id: value.source_id as string, idempotent: value.idempotent, demo_fixed_window: value.demo_fixed_window as Json };
}

export async function terminalizeXDemoFixedWindowJudgement(input: {
  demoRunId: string;
  judgementRunId: string;
  workerId: string;
}): Promise<Record<string, unknown>> {
  if (![input.demoRunId, input.judgementRunId, input.workerId].every((value) => typeof value === "string" && value.length > 0)) {
    throw new TaskScopeError("invalid_x_demo_fixed_window_judgement");
  }
  const { data, error } = await createSupabaseAdminClient().rpc("terminalize_x_demo_fixed_window_judgement", {
    p_demo_run_id: input.demoRunId,
    p_judgement_run_id: input.judgementRunId,
    p_worker_id: input.workerId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data) || (data as Record<string, unknown>).status !== "failed") {
    throw new TaskScopeError("invalid_x_demo_fixed_window_judgement");
  }
  return data as Record<string, unknown>;
}

function parseDemoFixedWindowRun(value: unknown): DemoFixedWindowRun {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new TaskScopeError("invalid_x_demo_fixed_window_run");
  const row = value as Record<string, unknown>;
  if (typeof row.run_id !== "string" || typeof row.status !== "string" || typeof row.idempotent !== "boolean"
    || typeof row.cutoff_at !== "string" || !Array.isArray(row.sources)) throw new TaskScopeError("invalid_x_demo_fixed_window_run");
  return { run_id: row.run_id, status: row.status, idempotent: row.idempotent, cutoff_at: row.cutoff_at, sources: row.sources as Array<Record<string, unknown>> };
}

export async function beginXDemoFixedWindowRun(cutoffAt: string, workerId: string): Promise<DemoFixedWindowRun> {
  if (![cutoffAt, workerId].every((value) => typeof value === "string" && value.length > 0)) throw new TaskScopeError("invalid_x_demo_fixed_window_run");
  const { data, error } = await createSupabaseAdminClient().rpc("start_x_demo_fixed_window_run", { p_cutoff_at: cutoffAt, p_worker_id: workerId });
  if (error) throw error;
  return parseDemoFixedWindowRun(data);
}

export async function bindXDemoFixedWindowTask(input: { runId: string; sourceId: string; taskId: string; workerId: string }) {
  if (![input.runId, input.sourceId, input.taskId, input.workerId].every((value) => typeof value === "string" && value.length > 0)) throw new TaskScopeError("invalid_x_demo_fixed_window_task_binding");
  const { data, error } = await createSupabaseAdminClient().rpc("bind_x_demo_fixed_window_task", {
    p_run_id: input.runId, p_source_id: input.sourceId, p_task_id: input.taskId, p_worker_id: input.workerId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_x_demo_fixed_window_task_binding");
  return data as Record<string, unknown>;
}

export async function failXDemoFixedWindowSource(input: { runId: string; sourceId: string; reason: string; workerId: string }) {
  if (![input.runId, input.sourceId, input.reason, input.workerId].every((value) => typeof value === "string" && value.length > 0)) throw new TaskScopeError("invalid_x_demo_fixed_window_source_failure");
  const { data, error } = await createSupabaseAdminClient().rpc("fail_x_demo_fixed_window_source", {
    p_run_id: input.runId, p_source_id: input.sourceId, p_reason: input.reason, p_worker_id: input.workerId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_x_demo_fixed_window_source_failure");
  return data as Record<string, unknown>;
}

export async function settleXDemoFixedWindowRun(runId: string, workerId: string) {
  if (![runId, workerId].every((value) => typeof value === "string" && value.length > 0)) throw new TaskScopeError("invalid_x_demo_fixed_window_settlement");
  const { data, error } = await createSupabaseAdminClient().rpc("settle_x_demo_fixed_window_run", { p_run_id: runId, p_worker_id: workerId });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_x_demo_fixed_window_settlement");
  return data as Record<string, unknown>;
}

export async function claimXDemoFixedWindowTask(taskId: string, workerId: string, now = new Date().toISOString()) {
  if (![taskId, workerId, now].every((value) => typeof value === "string" && value.length > 0)) {
    throw new TaskScopeError("invalid_fixed_window_claim_request");
  }
  const client = createSupabaseAdminClient() as unknown as {
    rpc(name: string, args: Record<string, string>): Promise<{ data: unknown; error: { message?: string } | null }>;
  };
  const { data, error } = await client.rpc("claim_x_demo_fixed_window_task", {
    p_task_id: taskId, p_worker_id: workerId, p_now: now,
  });
  if (error) throw error;
  if (data === null) return null;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new TaskScopeError("invalid_fixed_window_claim");
  return data as Record<string, unknown>;
}

export async function scheduleDiscordSyncTasks(workerId: string, windowKey: string): Promise<ScheduledTick> {
  if (!isScheduleWindowKey(windowKey)) throw new TaskScopeError("invalid_schedule_window");
  const { data, error } = await createSupabaseAdminClient().rpc("enqueue_scheduled_discord_tasks", {
    p_worker_id: workerId,
    p_window_key: windowKey,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_scheduled_tick");
  const tick = data as Record<string, unknown>;
  if (tick.window_key !== windowKey || !Array.isArray(tick.tasks)) throw new Error("invalid_scheduled_tick");
  const tasks = tick.tasks.map((task) => {
    if (!task || typeof task !== "object" || Array.isArray(task)) throw new Error("invalid_scheduled_task");
    const value = task as Record<string, unknown>;
    if (typeof value.id !== "string" || typeof value.source_id !== "string" || typeof value.idempotent !== "boolean") {
      throw new Error("invalid_scheduled_task");
    }
    return { id: value.id, source_id: value.source_id, idempotent: value.idempotent };
  });
  return { window_key: windowKey, tasks };
}

export async function scheduleDueDiscordTasks(workerId: string, now = new Date()): Promise<DueScheduledTick> {
  return scheduleDueTasksByRpc(workerId, "enqueue_due_discord_tasks", now);
}

export async function scheduleDueXTasks(workerId: string, now = new Date()): Promise<DueScheduledTick> {
  return scheduleDueTasksByRpc(workerId, "enqueue_due_x_tasks", now);
}

export async function scheduleDueSourceTasks(workerId: string, now = new Date()): Promise<DueSourceScheduledTick> {
  const [discordResult, xResult] = await Promise.allSettled([
    scheduleDueDiscordTasks(workerId, now),
    scheduleDueXTasks(workerId, now),
  ]);
  if (discordResult.status === "rejected" && xResult.status === "rejected") {
    throw xResult.reason;
  }
  const discord = discordResult.status === "fulfilled" ? discordResult.value : null;
  const x = xResult.status === "fulfilled" ? xResult.value : null;
  // Batch settlement is deliberately independent from both source families:
  // the pre-existing scheduler result remains durable even when its later
  // judgement dispatch cannot run on this tick.
  let judgementDispatchFailed = false;
  try {
    const judgementDispatch = await ensureDueXCollectionBatches(workerId, now);
    judgementDispatchFailed = Boolean(
      judgementDispatch
      && typeof judgementDispatch === "object"
      && !Array.isArray(judgementDispatch)
      && "settlement_dispatch_failed" in judgementDispatch
      && judgementDispatch.settlement_dispatch_failed === true,
    );
  } catch {
    judgementDispatchFailed = true;
  }
  try {
    await advanceXManualRecoveryRuns(workerId, now);
  } catch {
    judgementDispatchFailed = true;
  }
  const scheduledAt = x?.scheduled_at ?? discord?.scheduled_at;
  if (!scheduledAt) throw new Error("invalid_scheduled_tick");
  return {
    scheduled_at: scheduledAt,
    tasks: [...(discord?.tasks ?? []), ...(x?.tasks ?? [])],
    deferred_source_ids: [...(discord?.deferred_source_ids ?? []), ...(x?.deferred_source_ids ?? [])],
    judgement_dispatch_failed: judgementDispatchFailed,
  };
}

async function scheduleDueTasksByRpc(workerId: string, rpcName: "enqueue_due_discord_tasks" | "enqueue_due_x_tasks", now: Date): Promise<DueScheduledTick> {
  const { data, error } = await createSupabaseAdminClient().rpc(rpcName, {
    p_worker_id: workerId,
    p_now: now.toISOString(),
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_scheduled_tick");
  const tick = data as Record<string, unknown>;
  if (typeof tick.scheduled_at !== "string" || !Array.isArray(tick.tasks)
    || !Array.isArray(tick.deferred_source_ids) || !tick.deferred_source_ids.every((value) => typeof value === "string")) {
    throw new Error("invalid_scheduled_tick");
  }
  const tasks = tick.tasks.map((task) => {
    if (!task || typeof task !== "object" || Array.isArray(task)) throw new Error("invalid_scheduled_task");
    const value = task as Record<string, unknown>;
    if (typeof value.id !== "string" || typeof value.source_id !== "string" || typeof value.idempotent !== "boolean") {
      throw new Error("invalid_scheduled_task");
    }
    return { id: value.id, source_id: value.source_id, idempotent: value.idempotent };
  });
  return { scheduled_at: tick.scheduled_at, tasks, deferred_source_ids: tick.deferred_source_ids };
}

export async function listRecentTasks(limit = 50) {
  const { data, error } = await createSupabaseAdminClient()
    .from("sync_tasks")
    .select("id,task_type,source_id,status,parameter_version,requested_by,queued_at,lease_owner,lease_expires_at,last_checkpoint,created_at,updated_at")
    .order("queued_at", { ascending: false })
    .limit(limit);
  if (error) throw error;
  return data;
}

export async function getTaskDetail(taskId: string) {
  const supabase = createSupabaseAdminClient();
  const [{ data: task, error: taskError }, { data: attempts, error: attemptsError }, { data: events, error: eventsError }, { data: structuredRuns, error: runsError }] =
    await Promise.all([
      supabase.from("sync_tasks").select("*").eq("id", taskId).maybeSingle(),
      supabase
        .from("task_attempts")
        .select("id,task_id,attempt,worker_id,status,lease_expires_at,result,failure,started_at,completed_at,created_at,updated_at")
        .eq("task_id", taskId)
        .order("attempt", { ascending: false }),
      supabase
        .from("task_events")
        .select("id,task_id,attempt,event_type,occurred_at,details,created_at")
        .eq("task_id", taskId)
        .order("occurred_at", { ascending: true }),
      supabase
        .from("structured_runs")
        .select("id,task_id,provider,parameter_version,output,created_at")
        .eq("task_id", taskId)
        .order("created_at", { ascending: true }),
    ]);
  if (taskError) throw taskError;
  if (attemptsError) throw attemptsError;
  if (eventsError) throw eventsError;
  if (runsError) throw runsError;
  if (!task) return null;

  const runIds = (structuredRuns ?? []).map((run) => run.id);
  let evidenceRefs: Database["public"]["Tables"]["evidence_refs"]["Row"][] = [];
  if (runIds.length > 0) {
    const { data, error } = await supabase
      .from("evidence_refs")
      .select("id,structured_run_id,canonical_message_id,evidence_kind,local_raw_ref,created_at")
      .in("structured_run_id", runIds);
    if (error) throw error;
    evidenceRefs = data ?? [];
  }
  return { task, attempts: attempts ?? [], events: events ?? [], structuredRuns: structuredRuns ?? [], evidenceRefs };
}

export async function retryTask(taskId: string, requestedBy: string) {
  const { data, error } = await createSupabaseAdminClient()
    .from("sync_tasks")
    .update({ status: "queued", requested_by: requestedBy, lease_owner: null, lease_expires_at: null })
    .eq("id", taskId)
    .eq("status", "retryable_failed")
    .select()
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function recordTaskEvent(event: {
  task_id: string;
  attempt: number;
  event_type: string;
  occurred_at: string;
  details: Record<string, unknown>;
}) {
  const { data, error } = await createSupabaseAdminClient()
    .from("task_events")
    .insert({
      task_id: event.task_id,
      attempt: event.attempt,
      event_type: event.event_type,
      occurred_at: event.occurred_at,
      details: event.details as Json,
    })
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function claimNextTask(workerId: string, now = new Date().toISOString()) {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_next_task", {
    p_worker_id: workerId,
    p_now: now,
  });
  if (error) throw error;
  return data;
}

export async function renewTaskLease(
  taskId: string,
  attempt: number,
  workerId: string,
  now = new Date().toISOString(),
) {
  const { data, error } = await createSupabaseAdminClient().rpc("renew_task_lease", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_now: now,
  });
  if (error) throw error;
  return data;
}

export async function acceptTaskResult(
  taskId: string,
  attempt: number,
  result: Json,
  context: Json,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("accept_task_result", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_result: result,
    p_context: context,
  });
  if (error) throw error;
  return data;
}

export async function persistWorkerExecution(
  taskId: string,
  attempt: number,
  workerId: string,
  payload: Json,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("persist_worker_execution", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_payload: payload,
  });
  if (error) throw error;
  return data;
}

export async function persistWindowedCapturePage(
  taskId: string,
  attempt: number,
  workerId: string,
  payload: Json,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("persist_windowed_capture_page", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_payload: payload,
  });
  if (error) throw error;
  return data;
}

export async function getWindowDailyFactContext(
  taskId: string,
  attempt: number,
  workerId: string,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("get_window_daily_fact_context", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_daily_fact_context");
  return data;
}

export async function resolveWindowedAuthorProfiles(
  taskId: string,
  attempt: number,
  workerId: string,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("resolve_windowed_author_profiles", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
  });
  if (error) throw error;
  if (!data || typeof data !== "object" || Array.isArray(data)) throw new Error("invalid_resolved_author_profiles");
  return data;
}

export async function recordWindowedCaptureSegment(
  taskId: string,
  attempt: number,
  workerId: string,
  segment: Json,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("record_windowed_capture_segment", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_segment: segment,
  });
  if (error) throw error;
  return data;
}

export async function completeWindowedCaptureRange(
  taskId: string,
  attempt: number,
  workerId: string,
  completion: Json,
  signal?: AbortSignal,
) {
  const supabase = createSupabaseAdminClient();
  const captureRange = completion && typeof completion === "object" && !Array.isArray(completion)
    ? completion.capture_range
    : undefined;
  const history = captureRange && typeof captureRange === "object" && !Array.isArray(captureRange)
    && captureRange.mode === "history";
  const completionRequest = supabase.rpc(history ? "complete_bounded_x_history_range" : "complete_windowed_capture_range", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_payload: completion,
  });
  if (signal) completionRequest.abortSignal(signal);
  const { data, error } = await completionRequest;
  if (error) throw error;
  return data;
}

export async function recordTaskFailure(
  taskId: string,
  attempt: number,
  failure: Json,
  context: Json,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("record_task_failure", {
    p_task_id: taskId,
    p_attempt: attempt,
    p_failure: failure,
    p_context: context,
  });
  if (error) throw error;
  return data;
}

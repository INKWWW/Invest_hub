import { createSupabaseAdminClient } from "../supabase-server";
import type { Database, Json } from "../types";

type TaskInsert = Database["public"]["Tables"]["sync_tasks"]["Insert"];

export async function createDiscordSyncTask(input: {
  sourceId: string;
  parameterVersion: string;
  requestedBy: string;
}) {
  const row: TaskInsert = {
    task_type: "discord_sync",
    source_id: input.sourceId,
    parameter_version: input.parameterVersion,
    requested_by: input.requestedBy,
  };
  const { data, error } = await createSupabaseAdminClient()
    .from("sync_tasks")
    .insert(row)
    .select()
    .single();
  if (error) throw error;
  return data;
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

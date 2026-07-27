import { createSupabaseAdminClient } from "../supabase-server";
import type { Database, WorkerStatus } from "../types";

type WorkerInsert = Database["public"]["Tables"]["workers"]["Insert"];

export async function listWorkers() {
  const { data, error } = await createSupabaseAdminClient()
    .from("workers")
    .select("id,name,status,last_heartbeat_at,enrolled_at,revoked_at,created_at,updated_at")
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function registerWorker(input: {
  id?: string;
  name: string;
  deviceSecretHash: string;
  status?: WorkerStatus;
}) {
  const row: WorkerInsert = {
    id: input.id,
    name: input.name,
    device_secret_hash: input.deviceSecretHash,
    status: input.status ?? "enrolled",
  };
  const { data, error } = await createSupabaseAdminClient()
    .from("workers")
    .insert(row)
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function findWorkerBySecretHash(deviceSecretHash: string) {
  const { data, error } = await createSupabaseAdminClient()
    .from("workers")
    .select("id,name,status,last_heartbeat_at,enrolled_at,revoked_at,created_at,updated_at")
    .eq("device_secret_hash", deviceSecretHash)
    .maybeSingle();
  if (error) throw error;
  return data;
}

export async function updateWorkerHeartbeat(workerId: string, status: WorkerStatus, at: string, capabilities: Array<"discord_sync" | "x_sync"> = []) {
  const { data, error } = await createSupabaseAdminClient()
    .from("workers")
    .update({ status, last_heartbeat_at: at, capabilities })
    .eq("id", workerId)
    .select()
    .single();
  if (error) throw error;
  return data;
}

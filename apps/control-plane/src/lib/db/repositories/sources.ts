import { createSupabaseAdminClient } from "../supabase-server";
import type { Database } from "../types";

type SourceInsert = Database["public"]["Tables"]["sources"]["Insert"];

const sourceFields = "id,source_key,source_type,display_name,parameter_version,enabled,authorized_worker_id,author_rules_version,created_by,archived_at,archived_by,archive_reason,created_at,updated_at";
const adminSourceCardFields = "id,source_type,display_name,enabled,archived_at,workers(name),x_source_profiles(resolution_status),source_collection_coverage(source_id),sync_tasks(status,updated_at)";

export type AdminSourceCard = {
  id: string;
  sourceType: "discord" | "x";
  displayName: string;
  enabled: boolean;
  archivedAt: string | null;
  lifecycle: "ready" | "identity_pending" | "coverage_uninitialized" | "active_task" | "archived";
  workerName: string | null;
  latestCompletedAt: string | null;
};

type AdminSourceQuery = {
  id: string;
  source_type: "discord" | "x";
  display_name: string;
  enabled: boolean;
  archived_at: string | null;
  workers: { name: string } | null;
  x_source_profiles: Array<{ resolution_status: "pending" | "resolved" | "ambiguous" }>;
  source_collection_coverage: Array<{ source_id: string }>;
  sync_tasks: Array<{ status: string; updated_at: string }>;
};

function sourceLifecycle(source: AdminSourceQuery): AdminSourceCard["lifecycle"] {
  if (source.archived_at) return "archived";
  if (source.sync_tasks.some((task) => ["queued", "leased", "running", "retryable_failed"].includes(task.status))) return "active_task";
  if (source.source_type === "x" && source.x_source_profiles[0]?.resolution_status !== "resolved") return "identity_pending";
  if (source.source_collection_coverage.length === 0) return "coverage_uninitialized";
  return "ready";
}

function latestCompletedAt(tasks: AdminSourceQuery["sync_tasks"]): string | null {
  const completed = tasks
    .filter((task) => task.status === "succeeded")
    .map((task) => task.updated_at)
    .sort((left, right) => right.localeCompare(left));
  return completed[0] ?? null;
}

export async function listAdminSources(input: { sourceType: "discord" | "x"; includeArchived: boolean }): Promise<AdminSourceCard[]> {
  let query = createSupabaseAdminClient()
    .from("sources")
    .select(adminSourceCardFields)
    .eq("source_type", input.sourceType);
  if (!input.includeArchived) query = query.is("archived_at", null);
  const { data, error } = await query.order("created_at", { ascending: false });
  if (error) throw error;

  return ((data ?? []) as unknown as AdminSourceQuery[]).map((source) => ({
    id: source.id,
    sourceType: source.source_type,
    displayName: source.display_name,
    enabled: source.enabled,
    archivedAt: source.archived_at,
    lifecycle: sourceLifecycle(source),
    workerName: source.workers?.name ?? null,
    latestCompletedAt: latestCompletedAt(source.sync_tasks),
  }));
}

export class SourceAdministrationError extends Error {}

export async function listSources() {
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .select(sourceFields)
    .order("created_at", { ascending: false });
  if (error) throw error;
  return data;
}

export async function getSourceType(sourceId: string): Promise<"discord" | "x" | null> {
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .select("source_type")
    .eq("id", sourceId)
    .maybeSingle();
  if (error) throw error;
  return data?.source_type ?? null;
}

export async function updateSourceAdministration(input: {
  sourceId: string;
  displayName: string;
  enabled: boolean;
  authorizedWorkerId: string | null;
}) {
  const supabase = createSupabaseAdminClient();
  if (input.authorizedWorkerId) {
    const { data: worker, error: workerError } = await supabase
      .from("workers")
      .select("id,status")
      .eq("id", input.authorizedWorkerId)
      .maybeSingle();
    if (workerError) throw workerError;
    if (!worker || worker.status === "revoked") {
      throw new SourceAdministrationError("invalid_authorized_worker");
    }
  }

  const { data, error } = await supabase
    .from("sources")
    .update({
      display_name: input.displayName,
      enabled: input.enabled,
      authorized_worker_id: input.authorizedWorkerId,
    })
    .eq("id", input.sourceId)
    .select(sourceFields)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new SourceAdministrationError("source_not_found");
  return data;
}

export async function upsertDiscordSource(input: {
  sourceKey: string;
  displayName: string;
  parameterVersion: string;
  createdBy: string;
  enabled?: boolean;
}) {
  const row: SourceInsert = {
    source_key: input.sourceKey,
    source_type: "discord",
    display_name: input.displayName,
    parameter_version: input.parameterVersion,
    created_by: input.createdBy,
    enabled: input.enabled ?? true,
  };
  const { data, error } = await createSupabaseAdminClient()
    .from("sources")
    .upsert(row, { onConflict: "source_key" })
    .select()
    .single();
  if (error) throw error;
  return data;
}

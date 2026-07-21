import { createSupabaseAdminClient } from "../supabase-server";

type RecordValue = Record<string, unknown>;

export type SourceCoverage = {
  sourceId: string;
  coverageStartAt: string;
  coverageThroughAt: string;
};

export type ManualRefreshTask = {
  id: string;
  sourceId: string;
  status: string;
  trigger: "manual";
  startAt: string;
  endAt: string;
  queuedAt: string;
  idempotent: boolean;
};

export class WindowedSyncError extends Error {}

function asRecord(value: unknown, error: string): RecordValue {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new WindowedSyncError(error);
  return value as RecordValue;
}

function requiredString(value: unknown, error: string): string {
  if (typeof value !== "string" || value.length === 0) throw new WindowedSyncError(error);
  return value;
}

function parseCoverage(value: unknown): SourceCoverage {
  const row = asRecord(value, "invalid_coverage");
  return {
    sourceId: requiredString(row.source_id, "invalid_coverage"),
    coverageStartAt: requiredString(row.coverage_start_at, "invalid_coverage"),
    coverageThroughAt: requiredString(row.coverage_through_at, "invalid_coverage"),
  };
}

function parseManualRefreshTask(value: unknown): ManualRefreshTask {
  const row = asRecord(value, "invalid_window_task");
  const range = asRecord(row.capture_range, "invalid_window_task");
  if (row.collection_scope === null || typeof row.collection_scope !== "object") throw new WindowedSyncError("invalid_window_task");
  const scope = row.collection_scope as RecordValue;
  if (scope.mode !== "window" || range.trigger !== "manual") throw new WindowedSyncError("invalid_window_task");

  return {
    id: requiredString(row.id, "invalid_window_task"),
    sourceId: requiredString(row.source_id, "invalid_window_task"),
    status: requiredString(row.status, "invalid_window_task"),
    trigger: "manual",
    startAt: requiredString(range.start_at, "invalid_window_task"),
    endAt: requiredString(range.end_at, "invalid_window_task"),
    queuedAt: requiredString(row.queued_at, "invalid_window_task"),
    idempotent: row.idempotent === true,
  };
}

function rethrowWindowedSyncError(error: unknown): never {
  const message = error && typeof error === "object" && "message" in error && typeof error.message === "string"
    ? error.message
    : "";
  if (message === "coverage_not_initialized" || message === "coverage_already_initialized"
    || message === "source_not_found" || message === "source_disabled"
    || message === "source_parameter_version_mismatch" || message === "invalid_capture_range") {
    throw new WindowedSyncError(message);
  }
  throw error;
}

export async function getSourceCoverage(sourceId: string): Promise<SourceCoverage | null> {
  const { data, error } = await createSupabaseAdminClient()
    .from("source_collection_coverage")
    .select("source_id,coverage_start_at,coverage_through_at")
    .eq("source_id", sourceId)
    .maybeSingle();
  if (error) throw error;
  return data ? parseCoverage(data) : null;
}

export async function initializeSourceCoverage(input: {
  sourceId: string;
  actorId: string;
  coverageStartAt: string;
}): Promise<SourceCoverage> {
  const { data, error } = await createSupabaseAdminClient().rpc("initialize_discord_collection_coverage", {
    p_source_id: input.sourceId,
    p_actor_id: input.actorId,
    p_boundary: input.coverageStartAt,
  });
  if (error) rethrowWindowedSyncError(error);
  return parseCoverage(data);
}

export async function createManualDiscordRefresh(input: {
  sourceId: string;
  requestedBy: string;
  now?: Date;
}): Promise<ManualRefreshTask> {
  const supabase = createSupabaseAdminClient();
  const { data: source, error: sourceError } = await supabase
    .from("sources")
    .select("id,parameter_version")
    .eq("id", input.sourceId)
    .maybeSingle();
  if (sourceError) throw sourceError;
  if (!source) throw new WindowedSyncError("source_not_found");

  const { data, error } = await supabase.rpc("create_windowed_discord_sync_task", {
    p_source_id: input.sourceId,
    p_parameter_version: source.parameter_version,
    p_requested_by: input.requestedBy,
    p_trigger: "manual",
    p_end_at: (input.now ?? new Date()).toISOString(),
    p_scheduled_window_key: null,
  });
  if (error) rethrowWindowedSyncError(error);
  return parseManualRefreshTask(data);
}

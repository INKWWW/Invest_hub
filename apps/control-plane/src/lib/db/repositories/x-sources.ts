import { createSupabaseAdminClient } from "../supabase-server";

export class XSourceError extends Error {}

type Value = Record<string, unknown>;

function record(value: unknown, code: string): Value {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new XSourceError(code);
  return value as Value;
}

function text(value: unknown, code: string): string {
  if (typeof value !== "string" || !value) throw new XSourceError(code);
  return value;
}

function mapSource(value: unknown) {
  const source = record(value, "invalid_x_source");
  if (source.source_type !== "x" || source.resolution_status !== "pending") throw new XSourceError("invalid_x_source");
  return {
    id: text(source.id, "invalid_x_source"), sourceKey: text(source.source_key, "invalid_x_source"),
    displayName: text(source.display_name, "invalid_x_source"), parameterVersion: text(source.parameter_version, "invalid_x_source"),
    enabled: source.enabled === true, resolutionStatus: "pending" as const,
  };
}

function mapCoverage(value: unknown) {
  const row = record(value, "invalid_coverage");
  return { sourceId: text(row.source_id, "invalid_coverage"), coverageStartAt: text(row.coverage_start_at, "invalid_coverage"), coverageThroughAt: text(row.coverage_through_at, "invalid_coverage") };
}

function rethrow(error: unknown): never {
  const message = error && typeof error === "object" && "message" in error && typeof error.message === "string" ? error.message : "";
  if (["invalid_x_source", "invalid_coverage_boundary", "coverage_already_initialized", "coverage_not_initialized", "source_not_found", "source_not_x", "source_disabled", "x_source_unresolved", "source_parameter_version_mismatch", "actor_not_authorized", "invalid_capture_range", "active_x_range_overlap", "confirmation_mismatch", "source_has_active_task", "x_worker_unavailable"].includes(message)) throw new XSourceError(message);
  throw error;
}

export async function createXSource(input: { sourceKey: string; displayName: string; requestedHandle: string; parameterVersion: string; actorId: string }) {
  const { data, error } = await createSupabaseAdminClient().rpc("create_x_source", {
    p_source_key: input.sourceKey, p_display_name: input.displayName, p_requested_handle: input.requestedHandle,
    p_parameter_version: input.parameterVersion, p_actor_id: input.actorId,
  });
  if (error) rethrow(error);
  return mapSource(data);
}

export async function initializeXCoverage(input: { sourceId: string; actorId: string; boundary: string }) {
  const { data, error } = await createSupabaseAdminClient().rpc("initialize_x_collection_coverage", {
    p_source_id: input.sourceId, p_actor_id: input.actorId, p_boundary: input.boundary,
  });
  if (error) rethrow(error);
  return mapCoverage(data);
}

export async function removeXSource(input: { sourceId: string; actorId: string; confirmationName: string }) {
  const { data, error } = await createSupabaseAdminClient().rpc("remove_x_source", {
    p_source_id: input.sourceId,
    p_actor_id: input.actorId,
    p_confirmation_name: input.confirmationName,
  });
  if (error) rethrow(error);
  const row = record(data, "invalid_x_source_removal");
  if ((row.action !== "deleted" && row.action !== "archived")
    || typeof row.source_id !== "string" || !row.source_id
    || typeof row.display_name !== "string" || !row.display_name) {
    throw new XSourceError("invalid_x_source_removal");
  }
  return {
    action: row.action,
    sourceId: row.source_id,
    displayName: row.display_name,
  };
}

export async function createManualXRefresh(input: { sourceId: string; actorId: string; now?: Date }) {
  const supabase = createSupabaseAdminClient();
  const { data: source, error: sourceError } = await supabase.from("sources").select("id,source_type,parameter_version").eq("id", input.sourceId).maybeSingle();
  if (sourceError) throw sourceError;
  if (!source || source.source_type !== "x") throw new XSourceError("source_not_found");
  const { data, error } = await supabase.rpc("create_windowed_x_sync_task", {
    p_source_id: input.sourceId, p_parameter_version: source.parameter_version, p_requested_by: input.actorId,
    p_trigger: "manual", p_end_at: (input.now ?? new Date()).toISOString(), p_scheduled_window_key: null,
  });
  if (error) rethrow(error);
  const row = record(data, "invalid_x_task");
  const range = record(row.capture_range, "invalid_x_task");
  if (range.trigger !== "manual") throw new XSourceError("invalid_x_task");
  return { id: text(row.id, "invalid_x_task"), status: text(row.status, "invalid_x_task"), sourceId: text(row.source_id, "invalid_x_task"), startAt: text(range.start_at, "invalid_x_task"), endAt: text(range.end_at, "invalid_x_task"), idempotent: row.idempotent === true };
}

export async function createBoundedXHistory(input: { sourceId: string; actorId: string; startAt: string; endAt: string }) {
  const supabase = createSupabaseAdminClient();
  const { data: source, error: sourceError } = await supabase.from("sources").select("id,source_type,parameter_version").eq("id", input.sourceId).maybeSingle();
  if (sourceError) throw sourceError;
  if (!source || source.source_type !== "x") throw new XSourceError("source_not_found");
  const { data, error } = await supabase.rpc("create_bounded_x_history_task", {
    p_source_id: input.sourceId, p_parameter_version: source.parameter_version, p_requested_by: input.actorId,
    p_start_at: input.startAt, p_end_at: input.endAt,
  });
  if (error) rethrow(error);
  const row = record(data, "invalid_x_task");
  const range = record(row.capture_range, "invalid_x_task");
  if (range.mode !== "history" || range.trigger !== "history") throw new XSourceError("invalid_x_task");
  return { id: text(row.id, "invalid_x_task"), status: text(row.status, "invalid_x_task"), sourceId: text(row.source_id, "invalid_x_task"), startAt: text(range.start_at, "invalid_x_task"), endAt: text(range.end_at, "invalid_x_task") };
}

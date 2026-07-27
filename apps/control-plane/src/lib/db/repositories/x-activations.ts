import { createSupabaseAdminClient } from "../supabase-server";

export class XActivationError extends Error {}

export type XActivation = {
  sourceId: string;
  requestedHandle: string;
  parameterVersion: string;
  initialEndAt: string;
  idempotent: boolean;
};

export type InitializedXActivation = {
  taskId: string | null;
  sourceId: string;
  initialEndAt: string;
  idempotent: boolean;
};

export type FailedXActivation = { sourceId: string; stage: "identity_failed" };

function row(value: unknown, code: string): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new XActivationError(code);
  return value as Record<string, unknown>;
}

function text(value: unknown, code: string): string {
  if (typeof value !== "string" || !value) throw new XActivationError(code);
  return value;
}

function nullableText(value: unknown, code: string): string | null {
  return value === null ? null : text(value, code);
}

function flag(value: unknown, code: string): boolean {
  if (typeof value !== "boolean") throw new XActivationError(code);
  return value;
}

function rethrow(error: unknown): never {
  const message = error && typeof error === "object" && "message" in error && typeof error.message === "string" ? error.message : "";
  if (["worker_not_authorized", "x_source_unresolved", "source_not_found"].includes(message)) throw new XActivationError(message);
  throw error;
}

function exact(value: Record<string, unknown>, keys: string, code: string) {
  if (Object.keys(value).sort().join(",") !== keys) throw new XActivationError(code);
}

function activation(value: unknown): XActivation {
  const valueRow = row(value, "invalid_x_activation");
  exact(valueRow, "idempotent,initial_end_at,parameter_version,requested_handle,source_id", "invalid_x_activation");
  return { sourceId: text(valueRow.source_id, "invalid_x_activation"), requestedHandle: text(valueRow.requested_handle, "invalid_x_activation"), parameterVersion: text(valueRow.parameter_version, "invalid_x_activation"), initialEndAt: text(valueRow.initial_end_at, "invalid_x_activation"), idempotent: flag(valueRow.idempotent, "invalid_x_activation") };
}

function initialized(value: unknown): InitializedXActivation {
  const valueRow = row(value, "invalid_x_activation_initialization");
  exact(valueRow, "idempotent,initial_end_at,source_id,task_id", "invalid_x_activation_initialization");
  return { taskId: nullableText(valueRow.task_id, "invalid_x_activation_initialization"), sourceId: text(valueRow.source_id, "invalid_x_activation_initialization"), initialEndAt: text(valueRow.initial_end_at, "invalid_x_activation_initialization"), idempotent: flag(valueRow.idempotent, "invalid_x_activation_initialization") };
}

export async function claimXActivation(workerId: string, now: string): Promise<XActivation | null> {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_next_x_activation", { p_worker_id: workerId, p_now: now });
  if (error) rethrow(error);
  return data === null ? null : activation(data);
}

export async function initializeXActivation(input: { sourceId: string; workerId: string; now: string }): Promise<InitializedXActivation> {
  const { data, error } = await createSupabaseAdminClient().rpc("initialize_x_source_activation", { p_source_id: input.sourceId, p_worker_id: input.workerId, p_now: input.now });
  if (error) rethrow(error);
  return initialized(data);
}

export async function markXActivationIdentityFailed(input: { sourceId: string; workerId: string; errorCode: string }): Promise<FailedXActivation> {
  const { data, error } = await createSupabaseAdminClient().rpc("mark_x_source_activation_identity_failed", {
    p_source_id: input.sourceId, p_worker_id: input.workerId, p_error_code: input.errorCode,
  });
  if (error) rethrow(error);
  const value = row(data, "invalid_x_activation_failure");
  exact(value, "source_id,stage", "invalid_x_activation_failure");
  if (value.stage !== "identity_failed") throw new XActivationError("invalid_x_activation_failure");
  return { sourceId: text(value.source_id, "invalid_x_activation_failure"), stage: "identity_failed" };
}

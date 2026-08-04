import { createSupabaseAdminClient } from "../supabase-server";
import type { Json } from "../types";
import type { XVerificationReplayCompletion, XVerificationReplayContext } from "./x-v3-verification-replays";

export type XVerificationAcceptanceRunCreation = { acceptanceRunId: string; status: "queued" };
export type XVerificationAcceptanceRunClaim = { acceptanceRunId: string; attempt: 1; leaseExpiresAt: string };

const isObject = (value: unknown): value is Record<string, unknown> => Boolean(value) && typeof value === "object" && !Array.isArray(value);
const isString = (value: unknown): value is string => typeof value === "string" && value.length > 0;

export async function createXVerificationAcceptanceRun(parentReplayId: string, actorId: string): Promise<XVerificationAcceptanceRunCreation> {
  const { data, error } = await createSupabaseAdminClient().rpc("create_x_v3_verification_acceptance_run", { p_parent_replay_id: parentReplayId, p_requested_by: actorId });
  if (error) throw error;
  if (!isObject(data) || !isString(data.acceptance_run_id) || data.status !== "queued") throw new Error("invalid_x_v3_verification_acceptance_creation");
  return { acceptanceRunId: data.acceptance_run_id, status: "queued" };
}

export async function claimXVerificationAcceptanceRun(acceptanceRunId: string, workerId: string): Promise<XVerificationAcceptanceRunClaim | null> {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_x_v3_verification_acceptance_run", { p_acceptance_run_id: acceptanceRunId, p_worker_id: workerId });
  if (error) throw error;
  if (data === null) return null;
  if (!isObject(data) || !isString(data.acceptance_run_id) || data.acceptance_run_id !== acceptanceRunId || data.attempt !== 1 || !isString(data.lease_expires_at)) throw new Error("invalid_x_v3_verification_acceptance_claim");
  return { acceptanceRunId, attempt: 1, leaseExpiresAt: data.lease_expires_at };
}

export async function getXVerificationAcceptanceContext(acceptanceRunId: string, attempt: number, workerId: string): Promise<XVerificationReplayContext> {
  const { data, error } = await createSupabaseAdminClient().rpc("get_x_v3_verification_acceptance_context", { p_acceptance_run_id: acceptanceRunId, p_attempt: attempt, p_worker_id: workerId });
  if (error) throw error;
  if (!isObject(data) || data.acceptance_run_id !== acceptanceRunId || data.attempt !== 1 || !Array.isArray(data.sources)) throw new Error("invalid_x_v3_verification_acceptance_context");
  return { replay_id: acceptanceRunId, attempt: 1, sources: data.sources as XVerificationReplayContext["sources"] };
}

export async function completeXVerificationAcceptanceRun(acceptanceRunId: string, completion: XVerificationReplayCompletion, workerId: string) {
  const { replay_id: _replayId, attempt: _attempt, ...payload } = completion;
  const { data, error } = await createSupabaseAdminClient().rpc("complete_x_v3_verification_acceptance_run", { p_acceptance_run_id: acceptanceRunId, p_attempt: completion.attempt, p_worker_id: workerId, p_payload: payload as Json });
  if (error) throw error;
  return data;
}

export async function failXVerificationAcceptanceRun(acceptanceRunId: string, attempt: number, workerId: string, failureClass: "timeout" | "provider_failure" | "empty_response" | "invalid_json" | "schema_error" | "persistence_failure") {
  const { data, error } = await createSupabaseAdminClient().rpc("fail_x_v3_verification_acceptance_run", { p_acceptance_run_id: acceptanceRunId, p_attempt: attempt, p_worker_id: workerId, p_failure_class: failureClass });
  if (error) throw error;
  return data;
}

import { createSupabaseAdminClient } from "../supabase-server";

const expectedKeys = ["account_id", "idempotent", "parameter_version", "resolution_status", "source_id"];
const databaseErrorCodes = new Set([
  "source_not_found",
  "worker_not_authorized",
  "source_parameter_version_mismatch",
  "invalid_x_identity",
  "x_identity_conflict",
  "x_identity_activation_blocked",
]);

export class XIdentityResolutionError extends Error {}

export type XSourceIdentity = {
  sourceId: string;
  accountId: string;
  resolutionStatus: "resolved";
  parameterVersion: string;
  idempotent: boolean;
};

function parseIdentity(value: unknown, input: {
  sourceId: string;
  parameterVersion: string;
  accountId: string;
}): XSourceIdentity {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new XIdentityResolutionError("invalid_x_identity_resolution");
  const row = value as Record<string, unknown>;
  if (Object.keys(row).sort().join(",") !== expectedKeys.join(",")
    || typeof row.source_id !== "string" || !row.source_id
    || typeof row.account_id !== "string" || !row.account_id
    || row.resolution_status !== "resolved"
    || typeof row.parameter_version !== "string" || !row.parameter_version
    || typeof row.idempotent !== "boolean"
    || row.source_id !== input.sourceId
    || row.account_id !== input.accountId
    || row.parameter_version !== input.parameterVersion) {
    throw new XIdentityResolutionError("invalid_x_identity_resolution");
  }
  return {
    sourceId: row.source_id,
    accountId: row.account_id,
    resolutionStatus: "resolved",
    parameterVersion: row.parameter_version,
    idempotent: row.idempotent,
  };
}

function rethrowResolutionError(error: unknown): never {
  const message = error && typeof error === "object" && "message" in error && typeof error.message === "string"
    ? error.message
    : "";
  if (databaseErrorCodes.has(message)) throw new XIdentityResolutionError(message);
  throw error;
}

export async function resolveXSourceIdentity(input: {
  sourceId: string;
  workerId: string;
  parameterVersion: string;
  accountId: string;
}): Promise<XSourceIdentity> {
  const { data, error } = await createSupabaseAdminClient().rpc("resolve_x_source_identity", {
    p_source_id: input.sourceId,
    p_worker_id: input.workerId,
    p_parameter_version: input.parameterVersion,
    p_account_id: input.accountId,
  });
  if (error) rethrowResolutionError(error);
  return parseIdentity(data, input);
}

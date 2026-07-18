import type { AppRole, Json, TaskStatus } from "../db/types";

export type AdminDisplayStatus =
  | "no_new_data"
  | "retryable_failed"
  | "failed"
  | "succeeded_with_unresolved"
  | "succeeded"
  | "queued"
  | "leased"
  | "running"
  | "cancelled";

export type AdminTaskRecord = {
  id?: unknown;
  task_type?: unknown;
  source_id?: unknown;
  status?: unknown;
  parameter_version?: unknown;
  attempt?: unknown;
  lease_owner?: unknown;
  lease_expires_at?: unknown;
  last_checkpoint?: unknown;
  result?: unknown;
  failure?: unknown;
};

export type TaskViewModel = {
  id: string;
  taskType: string;
  sourceId: string;
  taskStatus: string;
  status: AdminDisplayStatus;
  statusLabel: string;
  parameterVersion: string;
  attempt: number | null;
  leaseOwner: string | null;
  leaseExpiresAt: string | null;
  checkpoint: string | null;
  rawCount: number;
  canonicalCount: number;
  duplicateCount: number;
  unresolvedCount: number;
  unparsedMediaCount: number;
  structuredRunIds: string[];
  chunkRanges: ChunkRange[];
  provider: string | null;
  modelReported: string | null;
  promptVersion: string | null;
  p50Ms: number | null;
  p95Ms: number | null;
  schemaStatus: string | null;
  evidenceRefs: string[];
  failureClass: string | null;
  retryable: boolean;
};

export type ChunkRange = {
  chunkId: string;
  startId: string | null;
  endId: string | null;
  messageIds: string[];
};

const DISPLAY_LABELS: Record<AdminDisplayStatus, string> = {
  no_new_data: "No new data",
  retryable_failed: "Retryable failure",
  failed: "Failed",
  succeeded_with_unresolved: "Succeeded with unresolved",
  succeeded: "Succeeded",
  queued: "Queued",
  leased: "Leased",
  running: "Running",
  cancelled: "Cancelled",
};

const SENSITIVE_KEY = /(cookie|token|secret|password|profile|prompt|raw[_-]?response|full[_-]?response)/i;

export function hasAdminRole(role: AppRole | string | null | undefined): role is "admin" {
  return role === "admin";
}

export function statusLabel(status: AdminDisplayStatus): string {
  return DISPLAY_LABELS[status];
}

export function canRetryTask(task: { status?: unknown }): boolean {
  return task.status === "retryable_failed";
}

export function deriveDisplayStatus(task: AdminTaskRecord): AdminDisplayStatus {
  const status = stringValue(task.status) as TaskStatus | "";
  if (status === "retryable_failed" || status === "failed" || status === "cancelled") return status;
  if (status === "queued" || status === "leased" || status === "running") return status;
  if (status !== "succeeded") return "failed";

  const result = recordValue(task.result);
  if (
    result &&
    numberValue(result.raw_count) === 0 &&
    numberValue(result.canonical_count) === 0 &&
    ("raw_count" in result || "canonical_count" in result)
  ) {
    return "no_new_data";
  }
  if (result && numberValue(result.unresolved_count) > 0) return "succeeded_with_unresolved";
  return "succeeded";
}

export function buildTaskViewModel(task: AdminTaskRecord): TaskViewModel {
  const result = recordValue(task.result) ?? {};
  const failure = recordValue(task.failure) ?? {};
  const status = deriveDisplayStatus(task);
  return {
    id: stringValue(task.id),
    taskType: stringValue(task.task_type, "discord_sync"),
    sourceId: stringValue(task.source_id),
    taskStatus: stringValue(task.status),
    status,
    statusLabel: statusLabel(status),
    parameterVersion: stringValue(task.parameter_version),
    attempt: integerValue(result.attempt) ?? integerValue(task.attempt),
    leaseOwner: nullableString(task.lease_owner),
    leaseExpiresAt: nullableString(task.lease_expires_at),
    checkpoint: nullableString(task.last_checkpoint) ?? nullableString(result.safe_checkpoint),
    rawCount: numberValue(result.raw_count),
    canonicalCount: numberValue(result.canonical_count),
    duplicateCount: numberValue(result.duplicate_count),
    unresolvedCount: numberValue(result.unresolved_count),
    unparsedMediaCount: numberValue(result.unparsed_media_count),
    structuredRunIds: stringArray(result.structured_run_ids),
    chunkRanges: chunkRanges(result.chunk_ranges),
    provider: nullableString(result.provider),
    modelReported: nullableString(result.model_reported),
    promptVersion: nullableString(result.prompt_version),
    p50Ms: numberOrNull(result.p50_ms),
    p95Ms: numberOrNull(result.p95_ms),
    schemaStatus: nullableString(result.schema_status),
    evidenceRefs: safeEvidenceRefs(result.evidence_refs),
    failureClass: nullableString(failure.failure_class) ?? nullableString(result.failure_class),
    retryable: failure.retryable === true || task.status === "retryable_failed",
  };
}

function recordValue(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, unknown>) : null;
}

function stringValue(value: unknown, fallback = ""): string {
  return typeof value === "string" ? value : fallback;
}

function nullableString(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

function numberValue(value: unknown): number {
  return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function numberOrNull(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function integerValue(value: unknown): number | null {
  return typeof value === "number" && Number.isInteger(value) ? value : null;
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];
}

function chunkRanges(value: unknown): ChunkRange[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    const row = recordValue(item);
    if (!row) return [];
    return [
      {
        chunkId: stringValue(row.chunk_id),
        startId: nullableString(row.start_id),
        endId: nullableString(row.end_id),
        messageIds: stringArray(row.message_ids),
      },
    ];
  });
}

function safeEvidenceRefs(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.flatMap((item) => {
    if (typeof item === "string") return SENSITIVE_KEY.test(item) || item.startsWith("/") ? [] : [item];
    const row = recordValue(item);
    if (!row) return [];
    const ref = nullableString(row.ref) ?? nullableString(row.id);
    return ref && !SENSITIVE_KEY.test(ref) && !ref.startsWith("/") ? [ref] : [];
  });
}

// Keep this module independent of the Supabase Json alias while documenting
// that all inputs originate from JSON-safe repository rows.
export type JsonLike = Json;


import { createSupabaseAdminClient } from "../supabase-server";
import type { Json } from "../types";

export type XDailyJudgementClaim = {
  run_id: string;
  attempt: number;
  lease_expires_at: string;
  batch: {
    id: string;
    natural_date: string;
    cutoff_at: string;
    coverage_status: "complete" | "partial";
  };
};

type XDailyJudgementAnalysis = {
  analysis_id: string;
  schema_version: "v3-x-post-analysis";
  prompt_version: "v3-x-post-analysis-1";
  analysis_output: Record<string, unknown>;
  evidence_post_ids: string[];
};

export type XDailyJudgementContext = {
  run_id: string;
  batch_id: string;
  attempt: number;
  prompt_version: "v3-x-cross-blogger-1";
  sources: Array<{
    source_id: string;
    display_name: string;
    window_segments: Array<{
      id: string;
      schema_version: "v3-x-window";
      prompt_version: "v3-x-window-1";
      occurred_from_at: string;
      occurred_through_at: string;
      segment_output: Record<string, unknown>;
      analyses: XDailyJudgementAnalysis[];
    }>;
  }>;
  excluded_sources: Array<{ source_id: string; display_name: string; reason: string }>;
};

export type XDailyJudgementItem = {
  statement: string;
  action_intent: "build_position" | "buy" | "add" | "hold" | "reduce" | "sell" | "watch" | "avoid" | "none";
  action_scope: string;
  conditions: string[];
  supporting_source_ids: string[];
  dissenting_source_ids: string[];
  analysis_ids: string[];
  evidence_post_ids: string[];
  uncertainties: string[];
};

export type XDailyJudgementCompletion = {
  run_id: string;
  attempt: number;
  schema_version: "v3-x-cross-blogger";
  provider: "codex_cli";
  model_reported: string | null;
  prompt_version: "v3-x-cross-blogger-1";
  security_industry_viewpoints: XDailyJudgementItem[];
  market_structure_viewpoints: XDailyJudgementItem[];
  strategy_mindset_viewpoints: XDailyJudgementItem[];
  uncertainties: string[];
};

export type XDailyJudgementFailureClass =
  | "timeout"
  | "provider_failure"
  | "empty_response"
  | "invalid_json"
  | "schema_error"
  | "persistence_failure";

export type XDailyJudgementRegeneration = {
  runId: string;
  status: "queued";
  attempt: 0;
};

export type XManualRecoveryRun = {
  id: string;
  status: "queued" | "collecting" | "summarizing" | "succeeded" | "failed";
  targetCutoffAt: string;
  idempotent: boolean;
};

const isObject = (value: unknown): value is Record<string, unknown> =>
  Boolean(value) && typeof value === "object" && !Array.isArray(value);

const isStringArray = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every((item) => typeof item === "string");

function parseClaim(value: unknown): XDailyJudgementClaim | null {
  if (!isObject(value) || typeof value.run_id !== "string" || typeof value.attempt !== "number" || !Number.isInteger(value.attempt)
    || value.attempt < 1 || typeof value.lease_expires_at !== "string" || !isObject(value.batch)
    || typeof value.batch.id !== "string" || typeof value.batch.natural_date !== "string"
    || typeof value.batch.cutoff_at !== "string"
    || (value.batch.coverage_status !== "complete" && value.batch.coverage_status !== "partial")) return null;
  return {
    run_id: value.run_id,
    attempt: value.attempt,
    lease_expires_at: value.lease_expires_at,
    batch: {
      id: value.batch.id,
      natural_date: value.batch.natural_date,
      cutoff_at: value.batch.cutoff_at,
      coverage_status: value.batch.coverage_status,
    },
  };
}

function parseRegeneration(value: unknown): XDailyJudgementRegeneration | null {
  if (!isObject(value) || typeof value.run_id !== "string" || value.status !== "queued" || value.attempt !== 0) return null;
  return { runId: value.run_id, status: value.status, attempt: value.attempt };
}

function parseManualRecoveryRun(value: unknown): XManualRecoveryRun | null {
  if (!isObject(value) || typeof value.id !== "string" || typeof value.target_cutoff_at !== "string"
    || typeof value.idempotent !== "boolean"
    || !["queued", "collecting", "summarizing", "succeeded", "failed"].includes(String(value.status))) return null;
  return { id: value.id, status: value.status as XManualRecoveryRun["status"], targetCutoffAt: value.target_cutoff_at, idempotent: value.idempotent };
}

function parseAnalysis(value: unknown): XDailyJudgementAnalysis | null {
  if (!isObject(value) || typeof value.analysis_id !== "string"
    || value.schema_version !== "v3-x-post-analysis" || value.prompt_version !== "v3-x-post-analysis-1"
    || !isObject(value.analysis_output) || !isStringArray(value.evidence_post_ids)) return null;
  return {
    analysis_id: value.analysis_id,
    schema_version: value.schema_version,
    prompt_version: value.prompt_version,
    analysis_output: value.analysis_output,
    evidence_post_ids: value.evidence_post_ids,
  };
}

function parseContext(value: unknown): XDailyJudgementContext | null {
  if (!isObject(value) || typeof value.run_id !== "string" || typeof value.batch_id !== "string"
    || typeof value.attempt !== "number" || !Number.isInteger(value.attempt)
    || value.attempt < 1 || value.prompt_version !== "v3-x-cross-blogger-1"
    || !Array.isArray(value.sources) || !Array.isArray(value.excluded_sources)) return null;
  const sources = value.sources.map((source) => {
    if (!isObject(source) || typeof source.source_id !== "string" || typeof source.display_name !== "string"
      || !Array.isArray(source.window_segments)) return null;
    const windowSegments = source.window_segments.map((segment) => {
      if (!isObject(segment) || typeof segment.id !== "string" || typeof segment.occurred_from_at !== "string"
        || typeof segment.occurred_through_at !== "string" || segment.schema_version !== "v3-x-window"
        || segment.prompt_version !== "v3-x-window-1" || !isObject(segment.segment_output)
        || !Array.isArray(segment.analyses)) return null;
      const analyses = segment.analyses.map(parseAnalysis);
      if (analyses.some((analysis) => !analysis)) return null;
      return {
        id: segment.id,
        schema_version: segment.schema_version,
        prompt_version: segment.prompt_version,
        occurred_from_at: segment.occurred_from_at,
        occurred_through_at: segment.occurred_through_at,
        segment_output: segment.segment_output,
        analyses: analyses as XDailyJudgementAnalysis[],
      };
    });
    if (windowSegments.some((segment) => !segment)) return null;
    return { source_id: source.source_id, display_name: source.display_name, window_segments: windowSegments as XDailyJudgementContext["sources"][number]["window_segments"] };
  });
  const excludedSources = value.excluded_sources.map((source) => {
    if (!isObject(source) || typeof source.source_id !== "string" || typeof source.display_name !== "string" || typeof source.reason !== "string") return null;
    return { source_id: source.source_id, display_name: source.display_name, reason: source.reason };
  });
  if (sources.some((source) => !source) || excludedSources.some((source) => !source)) return null;
  return {
    run_id: value.run_id,
    batch_id: value.batch_id,
    attempt: value.attempt,
    prompt_version: value.prompt_version,
    sources: sources as XDailyJudgementContext["sources"],
    excluded_sources: excludedSources as XDailyJudgementContext["excluded_sources"],
  };
}

export async function claimNextXDailyJudgement(workerId: string, now = new Date().toISOString()): Promise<XDailyJudgementClaim | null> {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_next_x_daily_judgement", {
    p_worker_id: workerId,
    p_now: now,
  });
  if (error) throw error;
  if (data === null) return null;
  const claim = parseClaim(data);
  if (!claim) throw new Error("invalid_x_daily_judgement_claim");
  return claim;
}

export async function ensureDueXCollectionBatches(workerId: string, now = new Date()) {
  const { data, error } = await createSupabaseAdminClient().rpc("ensure_due_x_collection_batches", {
    p_worker_id: workerId,
    p_now: now.toISOString(),
  });
  if (error) throw error;
  return data;
}

export async function advanceXManualRecoveryRuns(workerId: string, now = new Date()) {
  const { data, error } = await createSupabaseAdminClient().rpc("advance_x_manual_recovery_runs", {
    p_worker_id: workerId, p_now: now.toISOString(),
  });
  if (error) throw error;
  return data;
}

export async function createManualXRecoveryRun(actorId: string, now = new Date()): Promise<XManualRecoveryRun> {
  const { data, error } = await createSupabaseAdminClient().rpc("create_x_manual_recovery_run", {
    p_requested_by: actorId, p_now: now.toISOString(),
  });
  if (error) throw error;
  const run = parseManualRecoveryRun(data);
  if (!run) throw new Error("invalid_x_manual_recovery_run");
  return run;
}

export async function getXDailyJudgementContext(runId: string, attempt: number, workerId: string): Promise<XDailyJudgementContext> {
  const { data, error } = await createSupabaseAdminClient().rpc("get_x_daily_judgement_context", {
    p_run_id: runId,
    p_attempt: attempt,
    p_worker_id: workerId,
  });
  if (error) throw error;
  const context = parseContext(data);
  if (!context) throw new Error("invalid_x_daily_judgement_context");
  return context;
}

export async function completeXDailyJudgement(completion: XDailyJudgementCompletion, workerId: string) {
  const { run_id: _runId, attempt: _attempt, ...output } = completion;
  const { data, error } = await createSupabaseAdminClient().rpc("complete_x_daily_judgement", {
    p_run_id: completion.run_id,
    p_attempt: completion.attempt,
    p_worker_id: workerId,
    p_payload: output as Json,
  });
  if (error) throw error;
  return data;
}

export async function failXDailyJudgement(
  runId: string,
  attempt: number,
  workerId: string,
  failureClass: XDailyJudgementFailureClass,
) {
  const { data, error } = await createSupabaseAdminClient().rpc("fail_x_daily_judgement", {
    p_run_id: runId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_failure_class: failureClass,
  });
  if (error) throw error;
  return data;
}

export async function regenerateXDailyJudgement(batchId: string, actorId: string): Promise<XDailyJudgementRegeneration> {
  const { data, error } = await createSupabaseAdminClient().rpc("regenerate_x_daily_judgement", {
    p_batch_id: batchId,
    p_requested_by: actorId,
  });
  if (error) throw error;
  const regeneration = parseRegeneration(data);
  if (!regeneration) throw new Error("invalid_x_daily_judgement_regeneration");
  return regeneration;
}

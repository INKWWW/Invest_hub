import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import {
  completeXDailyJudgement,
  getXDailyJudgementContext,
  type XDailyJudgementCompletion,
  type XDailyJudgementContext,
  type XDailyJudgementItem,
} from "../../../../../../lib/db/repositories/x-daily-judgements";

const v4CompletionKeys = [
  "run_id", "attempt", "schema_version", "provider", "model_reported", "prompt_version",
  "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "uncertainties",
].sort();
const v5CompletionKeys = [
  "run_id", "attempt", "schema_version", "provider", "model_reported", "prompt_version",
  "ai_synthesis", "security_industry_theses", "market_structure_theses", "strategy_mindset_theses", "uncertainties",
].sort();
const strongConsensusWording = /共识|一致认为|共同认为|市场(?:已经|已)?确认/u;

function isObject(value: unknown): value is Record<string, unknown> {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function isStringArray(value: unknown, max = 500): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.length > 0 && item.length <= max);
}

function isUnique(values: string[]) {
  return new Set(values).size === values.length;
}

function hasExactKeys(value: Record<string, unknown>, keys: string[]) {
  return Object.keys(value).sort().join(",") === keys.join(",");
}

function sameSet(left: Set<string>, right: Set<string>) {
  return left.size === right.size && [...left].every((value) => right.has(value));
}

function containsOpaqueId(values: string[], opaqueIds: Set<string>) {
  const canonicalOpaqueIds = [...opaqueIds].map((opaqueId) => opaqueId.toLowerCase());
  return values.some((value) => {
    const canonicalValue = value.toLowerCase();
    return canonicalOpaqueIds.some((opaqueId) => canonicalValue.includes(opaqueId));
  });
}

function isSafeModelReported(value: unknown): value is string | null {
  if (value === null) return true;
  return typeof value === "string" && value.length > 0 && value.length <= 160
    && !/[\u0000-\u001f\u007f]/.test(value)
    && !/^\s*\//.test(value) && !/^\s*[A-Za-z]:[\\/]/.test(value) && !/^\s*file:/i.test(value)
    && !/^\s*(local_evidence(_path)?|local_path|raw_x_content|raw_content|cookie|browser[_ -]?profile)[\s:=/\\]/i.test(value);
}

function isJudgementItem(value: unknown): value is XDailyJudgementItem {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const item = value as Record<string, unknown>;
  return Object.keys(item).sort().join(",") === [
    "action_intent", "action_scope", "action_scope_status", "analysis_ids", "conditions", "dissenting_source_ids", "evidence_post_ids", "statement", "supporting_source_ids", "uncertainties",
  ].sort().join(",")
    && typeof item.statement === "string" && item.statement.length > 0 && item.statement.length <= 1000
    && ["build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid", "none"].includes(String(item.action_intent))
    && typeof item.action_scope === "string" && item.action_scope.length <= 300
    && ((item.action_intent === "none" && item.action_scope_status === "not_applicable" && item.action_scope === "") || (item.action_intent !== "none" && ((item.action_scope_status === "specified" && item.action_scope.trim().length > 0) || (item.action_scope_status === "unspecified" && item.action_scope === ""))))
    && isStringArray(item.conditions)
    && isStringArray(item.supporting_source_ids, 128) && isStringArray(item.dissenting_source_ids, 128)
    && isStringArray(item.analysis_ids, 128) && isStringArray(item.evidence_post_ids, 128)
    && isStringArray(item.uncertainties);
}

function isCompletion(value: unknown): value is XDailyJudgementCompletion {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const completion = value as Record<string, unknown>;
  const validMetadata = typeof completion.run_id === "string" && typeof completion.attempt === "number"
    && Number.isInteger(completion.attempt) && completion.attempt > 0
    && completion.provider === "codex_cli" && isSafeModelReported(completion.model_reported);
  if (!validMetadata) return false;
  if (hasExactKeys(completion, v4CompletionKeys)) {
    return completion.schema_version === "v4-x-cross-blogger"
      && completion.prompt_version === "v4-x-cross-blogger-1"
      && Array.isArray(completion.security_industry_viewpoints) && completion.security_industry_viewpoints.every(isJudgementItem)
      && Array.isArray(completion.market_structure_viewpoints) && completion.market_structure_viewpoints.every(isJudgementItem)
      && Array.isArray(completion.strategy_mindset_viewpoints) && completion.strategy_mindset_viewpoints.every(isJudgementItem)
      && isStringArray(completion.uncertainties);
  }
  return hasExactKeys(completion, v5CompletionKeys)
    && completion.schema_version === "v5-x-cross-blogger"
    && completion.prompt_version === "v5-x-cross-blogger-1"
    && isObject(completion.ai_synthesis)
    && Array.isArray(completion.security_industry_theses)
    && Array.isArray(completion.market_structure_theses)
    && Array.isArray(completion.strategy_mindset_theses)
    && isStringArray(completion.uncertainties);
}

function referencesFrozenContext(
  completion: Extract<XDailyJudgementCompletion, { schema_version: "v4-x-cross-blogger" }>,
  judgementContext: XDailyJudgementContext,
): boolean {
  if (completion.run_id !== judgementContext.run_id || completion.attempt !== judgementContext.attempt) return false;
  if (judgementContext.sources.length === 0) return false;
  const sourceIds = new Set(judgementContext.sources.map((source) => source.source_id));
  if (sourceIds.size !== judgementContext.sources.length) return false;
  const excludedSourceIds = new Set(judgementContext.excluded_sources.map((source) => source.source_id));
  if (excludedSourceIds.size !== judgementContext.excluded_sources.length
    || [...excludedSourceIds].some((sourceId) => sourceIds.has(sourceId))) return false;
  const analysisSourceIds = new Map<string, string>();
  const analysisEvidencePostIds = new Map<string, Set<string>>();
  const evidencePostIds = new Set<string>();
  const segmentIds = new Set<string>();
  for (const source of judgementContext.sources) {
    for (const segment of source.window_segments) {
      if (segmentIds.has(segment.id)) return false;
      segmentIds.add(segment.id);
      for (const analysis of segment.analyses) {
        if (analysisSourceIds.has(analysis.analysis_id) || analysis.evidence_post_ids.length === 0
          || !isUnique(analysis.evidence_post_ids)) return false;
        analysisSourceIds.set(analysis.analysis_id, source.source_id);
        const analysisEvidence = new Set(analysis.evidence_post_ids);
        analysisEvidencePostIds.set(analysis.analysis_id, analysisEvidence);
        for (const evidencePostId of analysisEvidence) evidencePostIds.add(evidencePostId);
      }
    }
  }
  const analysisIds = new Set(analysisSourceIds.keys());
  const opaqueIds = new Set([
    judgementContext.batch_id, judgementContext.run_id, ...segmentIds,
    ...sourceIds, ...excludedSourceIds, ...analysisIds, ...evidencePostIds,
  ]);
  if (containsOpaqueId(completion.uncertainties, opaqueIds)) return false;

  return [...completion.security_industry_viewpoints, ...completion.market_structure_viewpoints, ...completion.strategy_mindset_viewpoints].every((item) => {
    if (!isUnique(item.supporting_source_ids) || !isUnique(item.dissenting_source_ids)
      || !isUnique(item.analysis_ids) || !isUnique(item.evidence_post_ids)
      || item.analysis_ids.length === 0 || item.evidence_post_ids.length === 0
      || item.supporting_source_ids.some((id) => item.dissenting_source_ids.includes(id))
      || (strongConsensusWording.test(item.statement)
        && (item.supporting_source_ids.length < 2 || item.dissenting_source_ids.length > 0))
      || containsOpaqueId([item.statement, item.action_scope, ...item.conditions, ...item.uncertainties], opaqueIds)) return false;

    const itemSourceIds = new Set([...item.supporting_source_ids, ...item.dissenting_source_ids]);
    const citedAnalysisSourceIds = new Set<string>();
    const citedEvidencePostIds = new Set<string>();
    for (const analysisId of item.analysis_ids) {
      const sourceId = analysisSourceIds.get(analysisId);
      const analysisEvidence = analysisEvidencePostIds.get(analysisId);
      if (!sourceId || !analysisEvidence) return false;
      citedAnalysisSourceIds.add(sourceId);
      for (const evidencePostId of analysisEvidence) citedEvidencePostIds.add(evidencePostId);
    }
    return sameSet(itemSourceIds, citedAnalysisSourceIds)
      && sameSet(new Set(item.evidence_post_ids), citedEvidencePostIds);
  });
}

export async function POST(request: Request, context: { params: Promise<{ runId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let completion: unknown;
  try {
    completion = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_daily_judgement_completion" }, { status: 422 });
  }
  const { runId } = await context.params;
  if (!isCompletion(completion) || completion.run_id !== runId) {
    return NextResponse.json({ error: "invalid_x_daily_judgement_completion" }, { status: 422 });
  }
  let judgementContext: XDailyJudgementContext;
  try {
    judgementContext = await getXDailyJudgementContext(runId, completion.attempt, worker.id);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_daily_judgement_context_failed" }, { status: 503 });
  }
  if (judgementContext.prompt_version !== completion.prompt_version) {
    return NextResponse.json({ error: "invalid_x_daily_judgement_completion" }, { status: 422 });
  }
  if (completion.schema_version === "v4-x-cross-blogger" && !referencesFrozenContext(completion, judgementContext)) {
    return NextResponse.json({ error: "invalid_x_daily_judgement_completion" }, { status: 422 });
  }
  try {
    return NextResponse.json(await completeXDailyJudgement(completion, worker.id));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_daily_judgement_completion_rejected" }, { status: 503 });
  }
}

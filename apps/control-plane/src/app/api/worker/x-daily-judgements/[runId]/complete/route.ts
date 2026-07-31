import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import {
  completeXDailyJudgement,
  getXDailyJudgementContext,
  type XDailyJudgementCompletion,
  type XDailyJudgementContext,
  type XDailyJudgementItem,
} from "../../../../../../lib/db/repositories/x-daily-judgements";

const completionKeys = [
  "run_id", "attempt", "schema_version", "provider", "model_reported", "prompt_version",
  "stock_viewpoints", "market_industry_viewpoints", "uncertainties",
].sort();

function isStringArray(value: unknown, max = 500): value is string[] {
  return Array.isArray(value) && value.every((item) => typeof item === "string" && item.length > 0 && item.length <= max);
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
    "analysis_ids", "dissenting_source_ids", "evidence_post_ids", "statement", "supporting_source_ids", "uncertainties",
  ].sort().join(",")
    && typeof item.statement === "string" && item.statement.length > 0 && item.statement.length <= 1000
    && isStringArray(item.supporting_source_ids, 128) && isStringArray(item.dissenting_source_ids, 128)
    && isStringArray(item.analysis_ids, 128) && isStringArray(item.evidence_post_ids, 128)
    && isStringArray(item.uncertainties);
}

function isCompletion(value: unknown): value is XDailyJudgementCompletion {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const completion = value as Record<string, unknown>;
  return Object.keys(completion).sort().join(",") === completionKeys.join(",")
    && typeof completion.run_id === "string" && typeof completion.attempt === "number"
    && Number.isInteger(completion.attempt) && completion.attempt > 0
    && completion.schema_version === "v2-x-cross-blogger" && completion.provider === "codex_cli"
    && isSafeModelReported(completion.model_reported)
    && completion.prompt_version === "v2-x-cross-blogger-1"
    && Array.isArray(completion.stock_viewpoints) && completion.stock_viewpoints.every(isJudgementItem)
    && Array.isArray(completion.market_industry_viewpoints) && completion.market_industry_viewpoints.every(isJudgementItem)
    && isStringArray(completion.uncertainties);
}

function referencesFrozenContext(completion: XDailyJudgementCompletion, judgementContext: XDailyJudgementContext): boolean {
  const sourceIds = new Set(judgementContext.sources.map((source) => source.source_id));
  const analysisIds = new Set<string>();
  const evidencePostIds = new Set<string>();
  for (const source of judgementContext.sources) {
    for (const segment of source.window_segments) {
      for (const analysis of segment.analyses) {
        analysisIds.add(analysis.post_id);
        for (const evidencePostId of analysis.evidence_post_ids) evidencePostIds.add(evidencePostId);
      }
    }
  }
  return [...completion.stock_viewpoints, ...completion.market_industry_viewpoints].every((item) =>
    item.supporting_source_ids.every((id) => sourceIds.has(id))
    && item.dissenting_source_ids.every((id) => sourceIds.has(id))
    && item.analysis_ids.every((id) => analysisIds.has(id))
    && item.evidence_post_ids.every((id) => evidencePostIds.has(id)),
  );
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
  if (!referencesFrozenContext(completion, judgementContext)) {
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

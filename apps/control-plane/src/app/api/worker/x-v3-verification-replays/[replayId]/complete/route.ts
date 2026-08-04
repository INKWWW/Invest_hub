import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import {
  completeXVerificationReplay,
  getXVerificationReplayContext,
  type XVerificationReplayCompletion,
  type XVerificationReplayContext,
  type XVerificationReplayJudgementItem,
} from "../../../../../../lib/db/repositories/x-v3-verification-replays";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const completionKeys = ["replay_id", "attempt", "provider", "model_reported", "sources", "daily"].sort();
const sourceKeys = ["source_id", "analyses", "segment"].sort();
const analysisKeys = ["post_id", "analysis_id", "analysis_version", "schema_version", "prompt_version", "analysis_output", "blogger_viewpoint", "arguments", "quoted_post_viewpoint", "uncertainties", "evidence_post_ids", "post_link"].sort();
const segmentKeys = ["occurred_from_at", "occurred_through_at", "schema_version", "prompt_version", "segment_output", "analysis_ids", "evidence_post_ids", "uncertainties"].sort();
const dailyKeys = ["schema_version", "prompt_version", "security_industry_viewpoints", "market_structure_viewpoints", "strategy_mindset_viewpoints", "uncertainties"].sort();
const judgementKeys = ["statement", "action_intent", "action_scope", "conditions", "supporting_source_ids", "dissenting_source_ids", "analysis_ids", "evidence_post_ids", "uncertainties"].sort();
const actionIntents = new Set(["build_position", "buy", "add", "hold", "reduce", "sell", "watch", "avoid", "none"]);
const strongConsensusWording = /共识|一致认为|共同认为|市场(?:已经|已)?确认/u;

const isObject = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === "object" && !Array.isArray(value);
const equalKeys = (value: Record<string, unknown>, keys: string[]) => Object.keys(value).sort().join(",") === keys.join(",");
const isStringArray = (value: unknown, max = 500): value is string[] => Array.isArray(value) && value.every((item) => typeof item === "string" && item.length > 0 && item.length <= max);
const isUnique = (values: string[]) => new Set(values).size === values.length;
const sameSet = (left: string[], right: string[]) => left.length === right.length && left.every((value) => right.includes(value));

function isSafeModelReported(value: unknown): value is string | null {
  return value === null || typeof value === "string" && value.length > 0 && value.length <= 160
    && !/[\u0000-\u001f\u007f]/.test(value) && !/^\s*\//.test(value) && !/^\s*[A-Za-z]:[\\/]/.test(value)
    && !/^\s*file:/i.test(value) && !/^\s*(local_evidence(_path)?|local_path|raw_x_content|raw_content|cookie|browser[_ -]?profile)[\s:=/\\]/i.test(value);
}

function isJudgementItem(value: unknown): value is XVerificationReplayJudgementItem {
  if (!isObject(value) || !equalKeys(value, judgementKeys)) return false;
  const actionIntent = value.action_intent;
  return typeof value.statement === "string" && value.statement.length > 0 && value.statement.length <= 1000
    && typeof actionIntent === "string" && actionIntents.has(actionIntent)
    && typeof value.action_scope === "string" && value.action_scope.length <= 300
    && (actionIntent === "none" ? value.action_scope === "" : value.action_scope.trim().length > 0)
    && isStringArray(value.conditions) && isStringArray(value.supporting_source_ids, 128)
    && isStringArray(value.dissenting_source_ids, 128) && isStringArray(value.analysis_ids, 128)
    && isStringArray(value.evidence_post_ids, 128) && isStringArray(value.uncertainties);
}

function isCompletion(value: unknown): value is XVerificationReplayCompletion {
  if (!isObject(value) || !equalKeys(value, completionKeys) || typeof value.replay_id !== "string" || value.attempt !== 1
    || value.provider !== "codex_cli" || !isSafeModelReported(value.model_reported) || !Array.isArray(value.sources) || !isObject(value.daily)) return false;
  const daily = value.daily;
  return equalKeys(daily, dailyKeys) && daily.schema_version === "v3-x-cross-blogger" && daily.prompt_version === "v3-x-cross-blogger-1"
    && Array.isArray(daily.security_industry_viewpoints) && daily.security_industry_viewpoints.every(isJudgementItem)
    && Array.isArray(daily.market_structure_viewpoints) && daily.market_structure_viewpoints.every(isJudgementItem)
    && Array.isArray(daily.strategy_mindset_viewpoints) && daily.strategy_mindset_viewpoints.every(isJudgementItem)
    && isStringArray(daily.uncertainties)
    && value.sources.every((source) => {
      if (!isObject(source) || !equalKeys(source, sourceKeys) || typeof source.source_id !== "string"
        || !Array.isArray(source.analyses) || !isObject(source.segment) || !equalKeys(source.segment, segmentKeys)) return false;
      const segment = source.segment;
      if (typeof segment.occurred_from_at !== "string" || typeof segment.occurred_through_at !== "string"
        || segment.schema_version !== "v3-x-window" || segment.prompt_version !== "v3-x-window-1"
        || !isObject(segment.segment_output) || segment.segment_output.schema_version !== "v3-x-window"
        || !isStringArray(segment.analysis_ids, 128) || !isStringArray(segment.evidence_post_ids, 128) || !isStringArray(segment.uncertainties)) return false;
      return source.analyses.every((analysis) => isObject(analysis) && equalKeys(analysis, analysisKeys)
        && typeof analysis.post_id === "string" && typeof analysis.analysis_id === "string" && analysis.analysis_id === `${analysis.post_id}@2`
        && analysis.analysis_version === 2 && analysis.schema_version === "v3-x-post-analysis" && analysis.prompt_version === "v3-x-post-analysis-1"
        && isObject(analysis.analysis_output) && analysis.analysis_output.post_id === analysis.post_id
        && (analysis.blogger_viewpoint === null || typeof analysis.blogger_viewpoint === "string")
        && isStringArray(analysis.arguments) && (analysis.quoted_post_viewpoint === null || typeof analysis.quoted_post_viewpoint === "string")
        && isStringArray(analysis.uncertainties) && isStringArray(analysis.evidence_post_ids, 128) && analysis.evidence_post_ids.length > 0
        && typeof analysis.post_link === "string");
    });
}

function referencesFrozenContext(completion: XVerificationReplayCompletion, frozen: XVerificationReplayContext) {
  if (completion.replay_id !== frozen.replay_id || completion.attempt !== frozen.attempt || frozen.sources.length === 0) return false;
  const frozenSourceIds = frozen.sources.map((source) => source.source_id);
  if (!isUnique(frozenSourceIds) || completion.sources.length !== frozenSourceIds.length
    || !isUnique(completion.sources.map((source) => source.source_id)) || !sameSet(completion.sources.map((source) => source.source_id), frozenSourceIds)) return false;
  const analysisSourceById = new Map<string, string>();
  const evidenceByAnalysisId = new Map<string, string[]>();
  for (const source of completion.sources) {
    const frozenSource = frozen.sources.find((item) => item.source_id === source.source_id);
    if (!frozenSource || source.segment.occurred_from_at !== frozenSource.occurred_from_at || source.segment.occurred_through_at !== frozenSource.occurred_through_at
      || source.analyses.length !== frozenSource.posts.length || !isUnique(source.analyses.map((analysis) => analysis.post_id))) return false;
    if (!sameSet(source.analyses.map((analysis) => analysis.post_id), frozenSource.posts.map((post) => post.post_id))) return false;
    const submittedEvidence = new Set<string>();
    for (const analysis of source.analyses) {
      const post = frozenSource.posts.find((item) => item.post_id === analysis.post_id);
      if (!post || post.post_url !== analysis.post_link || !isUnique(analysis.evidence_post_ids)) return false;
      const allowedEvidence = [post.post_id, post.quoted_post_id, post.reply_to_post_id, post.reposted_post_id].filter((id): id is string => Boolean(id));
      if (analysis.evidence_post_ids.some((id) => !allowedEvidence.includes(id)) || analysisSourceById.has(analysis.analysis_id)) return false;
      analysisSourceById.set(analysis.analysis_id, source.source_id);
      evidenceByAnalysisId.set(analysis.analysis_id, analysis.evidence_post_ids);
      for (const evidence of analysis.evidence_post_ids) submittedEvidence.add(evidence);
    }
    if (!isUnique(source.segment.analysis_ids) || !sameSet(source.segment.analysis_ids, source.analyses.map((analysis) => analysis.analysis_id))
      || !isUnique(source.segment.evidence_post_ids) || !sameSet(source.segment.evidence_post_ids, [...submittedEvidence])) return false;
  }
  const items = [...completion.daily.security_industry_viewpoints, ...completion.daily.market_structure_viewpoints, ...completion.daily.strategy_mindset_viewpoints];
  return items.every((item) => {
    if (!isUnique(item.supporting_source_ids) || !isUnique(item.dissenting_source_ids) || !isUnique(item.analysis_ids) || !isUnique(item.evidence_post_ids)
      || item.analysis_ids.length === 0 || item.evidence_post_ids.length === 0
      || item.supporting_source_ids.some((sourceId) => item.dissenting_source_ids.includes(sourceId))
      || (strongConsensusWording.test(item.statement) && (item.supporting_source_ids.length < 2 || item.dissenting_source_ids.length > 0))) return false;
    const citedSources = item.analysis_ids.map((analysisId) => analysisSourceById.get(analysisId));
    if (citedSources.some((sourceId) => !sourceId) || !sameSet([...new Set([...item.supporting_source_ids, ...item.dissenting_source_ids])], [...new Set(citedSources as string[])])) return false;
    const evidence = [...new Set(item.analysis_ids.flatMap((analysisId) => evidenceByAnalysisId.get(analysisId) ?? []))];
    return sameSet(item.evidence_post_ids, evidence);
  });
}

export async function POST(request: Request, context: { params: Promise<{ replayId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let completion: unknown;
  try {
    completion = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
  }
  const { replayId } = await context.params;
  if (!uuidPattern.test(replayId) || !isCompletion(completion) || completion.replay_id !== replayId) {
    return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
  }
  let frozen: XVerificationReplayContext;
  try {
    frozen = await getXVerificationReplayContext(replayId, completion.attempt, worker.id);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_v3_verification_context_failed" }, { status: 503 });
  }
  if (!referencesFrozenContext(completion, frozen)) return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
  try {
    return NextResponse.json(await completeXVerificationReplay(completion, worker.id));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_v3_verification_completion_rejected" }, { status: 503 });
  }
}

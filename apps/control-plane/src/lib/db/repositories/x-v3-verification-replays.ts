import { createSupabaseAdminClient } from "../supabase-server";
import type { Json } from "../types";

export type XVerificationReplayFailureClass =
  | "timeout"
  | "provider_failure"
  | "empty_response"
  | "invalid_json"
  | "schema_error"
  | "persistence_failure";

export type XVerificationReplayCreation = { replayId: string; status: "queued" };
export type XVerificationReplayClaim = { replayId: string; attempt: 1; leaseExpiresAt: string };

export type XVerificationReplayContext = {
  replay_id: string;
  attempt: 1;
  sources: Array<{
    source_id: string;
    display_name: string;
    occurred_from_at: string;
    occurred_through_at: string;
    posts: Array<{
      post_id: string;
      content: string;
      occurred_at: string;
      post_url: string;
      post_type: string;
      quoted_post_id: string | null;
      reply_to_post_id: string | null;
      reposted_post_id: string | null;
      context_status: string;
      attachments: Json;
    }>;
  }>;
};

export type XVerificationReplayJudgementItem = {
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

export type XVerificationReplayCompletion = {
  replay_id: string;
  attempt: 1;
  provider: "codex_cli";
  model_reported: string | null;
  sources: Array<{
    source_id: string;
    analyses: Array<{
      post_id: string;
      analysis_id: string;
      analysis_version: 2;
      schema_version: "v3-x-post-analysis";
      prompt_version: "v3-x-post-analysis-1";
      analysis_output: Json;
      blogger_viewpoint: string | null;
      arguments: string[];
      quoted_post_viewpoint: string | null;
      uncertainties: string[];
      evidence_post_ids: string[];
      post_link: string;
    }>;
    segment: {
      occurred_from_at: string;
      occurred_through_at: string;
      schema_version: "v3-x-window";
      prompt_version: "v3-x-window-1";
      segment_output: Json;
      analysis_ids: string[];
      evidence_post_ids: string[];
      uncertainties: string[];
    };
  }>;
  daily: {
    schema_version: "v3-x-cross-blogger";
    prompt_version: "v3-x-cross-blogger-1";
    security_industry_viewpoints: XVerificationReplayJudgementItem[];
    market_structure_viewpoints: XVerificationReplayJudgementItem[];
    strategy_mindset_viewpoints: XVerificationReplayJudgementItem[];
    uncertainties: string[];
  };
};

const isObject = (value: unknown): value is Record<string, unknown> => Boolean(value) && typeof value === "object" && !Array.isArray(value);
const isString = (value: unknown): value is string => typeof value === "string";
const isStringOrNull = (value: unknown): value is string | null => value === null || typeof value === "string";
const isJson = (value: unknown): value is Json => value === null || typeof value === "string" || typeof value === "number" || typeof value === "boolean"
  || Array.isArray(value) && value.every(isJson) || isObject(value) && Object.values(value).every(isJson);

function parseCreation(value: unknown): XVerificationReplayCreation | null {
  if (!isObject(value) || !isString(value.replay_id) || value.status !== "queued") return null;
  return { replayId: value.replay_id, status: "queued" };
}

function parseClaim(value: unknown): XVerificationReplayClaim | null {
  if (!isObject(value) || !isString(value.replay_id) || value.attempt !== 1 || !isString(value.lease_expires_at)) return null;
  return { replayId: value.replay_id, attempt: 1, leaseExpiresAt: value.lease_expires_at };
}

function parseContext(value: unknown): XVerificationReplayContext | null {
  if (!isObject(value) || !isString(value.replay_id) || value.attempt !== 1 || !Array.isArray(value.sources)) return null;
  const sources = value.sources.map((source) => {
    if (!isObject(source) || !isString(source.source_id) || !isString(source.display_name)
      || !isString(source.occurred_from_at) || !isString(source.occurred_through_at) || !Array.isArray(source.posts)) return null;
    const posts = source.posts.map((post) => {
      if (!isObject(post) || !isString(post.post_id) || !isString(post.content) || !isString(post.occurred_at)
        || !isString(post.post_url) || !isString(post.post_type) || !isStringOrNull(post.quoted_post_id)
        || !isStringOrNull(post.reply_to_post_id) || !isStringOrNull(post.reposted_post_id)
        || !isString(post.context_status) || !isJson(post.attachments)) return null;
      return {
        post_id: post.post_id, content: post.content, occurred_at: post.occurred_at, post_url: post.post_url,
        post_type: post.post_type, quoted_post_id: post.quoted_post_id, reply_to_post_id: post.reply_to_post_id,
        reposted_post_id: post.reposted_post_id, context_status: post.context_status, attachments: post.attachments,
      };
    });
    if (posts.some((post) => !post)) return null;
    return {
      source_id: source.source_id, display_name: source.display_name, occurred_from_at: source.occurred_from_at,
      occurred_through_at: source.occurred_through_at, posts: posts as XVerificationReplayContext["sources"][number]["posts"],
    };
  });
  if (sources.some((source) => !source)) return null;
  return { replay_id: value.replay_id, attempt: 1, sources: sources as XVerificationReplayContext["sources"] };
}

export async function createXVerificationReplay(sourceBatchId: string, actorId: string): Promise<XVerificationReplayCreation> {
  const { data, error } = await createSupabaseAdminClient().rpc("create_x_v3_verification_replay", {
    p_source_batch_id: sourceBatchId,
    p_requested_by: actorId,
  });
  if (error) throw error;
  const creation = parseCreation(data);
  if (!creation) throw new Error("invalid_x_v3_verification_replay_creation");
  return creation;
}

export async function claimXVerificationReplay(replayId: string, workerId: string): Promise<XVerificationReplayClaim | null> {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_x_v3_verification_replay", {
    p_replay_id: replayId,
    p_worker_id: workerId,
  });
  if (error) throw error;
  if (data === null) return null;
  const claim = parseClaim(data);
  if (!claim) throw new Error("invalid_x_v3_verification_replay_claim");
  return claim;
}

export async function getXVerificationReplayContext(replayId: string, attempt: number, workerId: string): Promise<XVerificationReplayContext> {
  const { data, error } = await createSupabaseAdminClient().rpc("get_x_v3_verification_replay_context", {
    p_replay_id: replayId,
    p_attempt: attempt,
    p_worker_id: workerId,
  });
  if (error) throw error;
  const context = parseContext(data);
  if (!context) throw new Error("invalid_x_v3_verification_replay_context");
  return context;
}

export async function completeXVerificationReplay(completion: XVerificationReplayCompletion, workerId: string) {
  const { replay_id: _replayId, attempt: _attempt, ...payload } = completion;
  const { data, error } = await createSupabaseAdminClient().rpc("complete_x_v3_verification_replay", {
    p_replay_id: completion.replay_id,
    p_attempt: completion.attempt,
    p_worker_id: workerId,
    p_payload: payload as Json,
  });
  if (error) throw error;
  return data;
}

export async function failXVerificationReplay(replayId: string, attempt: number, workerId: string, failureClass: XVerificationReplayFailureClass) {
  const { data, error } = await createSupabaseAdminClient().rpc("fail_x_v3_verification_replay", {
    p_replay_id: replayId,
    p_attempt: attempt,
    p_worker_id: workerId,
    p_failure_class: failureClass,
  });
  if (error) throw error;
  return data;
}

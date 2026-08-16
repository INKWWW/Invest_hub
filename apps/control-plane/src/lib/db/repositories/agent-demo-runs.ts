import { createSupabaseAdminClient, createSupabaseServerClient } from "../supabase-server";
import type { Database, Json } from "../types";

export type DemoRunStatus = Database["public"]["Tables"]["agent_demo_runs"]["Row"]["status"];

export type DemoRun = {
  id: string;
  ownerId: string;
  threadId: string;
  requestId: string;
  userMessageId: string;
  assistantMessageId: string | null;
  question: string;
  invocationMode: "explicit" | "auto";
  skillId: "investment-research" | "portfolio-review" | "investment-checklist" | null;
  status: DemoRunStatus;
  provider: string | null;
  failureCode: string | null;
  createdAt: string;
  startedAt: string | null;
  completedAt: string | null;
  updatedAt: string;
};

const runFields = "id,owner_id,thread_id,request_id,user_message_id,assistant_message_id,question,invocation_mode,skill_id,status,provider,failure_code,created_at,started_at,completed_at,updated_at";

function asObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_demo_run_response");
  return value as Record<string, unknown>;
}

function parseRpc(value: Json): { runId: string; userMessageId: string; assistantMessageId: string | null; status: DemoRunStatus; idempotent: boolean; invocationMode: "explicit" | "auto"; skillId: DemoRun["skillId"] } {
  const row = asObject(value);
  if (typeof row.run_id !== "string" || typeof row.user_message_id !== "string" || typeof row.status !== "string" || typeof row.idempotent !== "boolean" || (row.invocation_mode !== "explicit" && row.invocation_mode !== "auto") || (row.skill_id !== null && typeof row.skill_id !== "string")) throw new Error("invalid_demo_run_response");
  return {
    runId: row.run_id,
    userMessageId: row.user_message_id,
    assistantMessageId: typeof row.assistant_message_id === "string" ? row.assistant_message_id : null,
    status: row.status as DemoRunStatus,
    idempotent: row.idempotent,
    invocationMode: row.invocation_mode,
    skillId: row.skill_id as DemoRun["skillId"],
  };
}

function mapRun(row: Database["public"]["Tables"]["agent_demo_runs"]["Row"]): DemoRun {
  return {
    id: row.id,
    ownerId: row.owner_id,
    threadId: row.thread_id,
    requestId: row.request_id,
    userMessageId: row.user_message_id,
    assistantMessageId: row.assistant_message_id,
    question: row.question,
    invocationMode: row.invocation_mode,
    skillId: row.skill_id,
    status: row.status,
    provider: row.provider,
    failureCode: row.failure_code,
    createdAt: row.created_at,
    startedAt: row.started_at,
    completedAt: row.completed_at,
    updatedAt: row.updated_at,
  };
}

export async function admitDemoRun(input: {
  ownerId: string;
  threadId: string;
  requestId: string;
  question: string;
  invocationMode?: "explicit" | "auto";
  skillId?: "investment-research" | "portfolio-review" | "investment-checklist" | null;
}): Promise<Pick<DemoRun, "id" | "userMessageId" | "assistantMessageId" | "status" | "invocationMode" | "skillId"> & { runId: string; idempotent: boolean }> {
  const { data, error } = await (await createSupabaseServerClient()).rpc("admit_agent_demo_run", {
    p_owner_id: input.ownerId,
    p_thread_id: input.threadId,
    p_request_id: input.requestId,
    p_question: input.question,
    p_invocation_mode: input.invocationMode ?? "auto",
    p_skill_id: input.skillId ?? null,
  });
  if (error) throw error;
  const parsed = parseRpc(data);
  return { ...parsed, id: parsed.runId };
}

export async function getDemoRun(ownerId: string, runId: string): Promise<DemoRun | null> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("agent_demo_runs")
    .select(runFields)
    .eq("owner_id", ownerId)
    .eq("id", runId)
    .maybeSingle();
  if (error) throw error;
  return data ? mapRun(data as Database["public"]["Tables"]["agent_demo_runs"]["Row"]) : null;
}

export async function claimDemoRun(runId: string, workerId: string): Promise<Json | null> {
  const { data, error } = await createSupabaseAdminClient().rpc("claim_agent_demo_run", { p_run_id: runId, p_worker_id: workerId });
  if (error) throw error;
  return data;
}

export async function completeDemoRun(runId: string, workerId: string, content: string, provider: string): Promise<Json> {
  const { data, error } = await createSupabaseAdminClient().rpc("complete_agent_demo_run", { p_run_id: runId, p_worker_id: workerId, p_content: content, p_provider: provider });
  if (error) throw error;
  return data;
}

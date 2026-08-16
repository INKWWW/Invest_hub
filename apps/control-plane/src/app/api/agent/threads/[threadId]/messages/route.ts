import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../../../lib/auth/current-user";
import { parseSkillCommand, type InvocationMode, type SkillId } from "../../../../../../lib/agent-demo/skill-routing";
import { admitDemoRun } from "../../../../../../lib/db/repositories/agent-demo-runs";
import { validateDemoMessage } from "../../../../../../lib/agent-demo/contract";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function errorIncludes(error: unknown, value: string): boolean {
  if (!error || typeof error !== "object") return false;
  const record = error as Record<string, unknown>;
  return [record.message, record.details, record.hint].some((field) => typeof field === "string" && field.includes(value));
}

export async function POST(request: Request, context: { params: Promise<{ threadId: string }> }) {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { threadId } = await context.params;
  if (!uuidPattern.test(threadId)) return NextResponse.json({ error: "invalid_thread_id" }, { status: 422 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).some((key) => !["content", "request_id", "invocation_mode", "skill_id"].includes(key)) || ![2, 3, 4].includes(Object.keys(body).length) || typeof (body as { content?: unknown }).content !== "string" || typeof (body as { request_id?: unknown }).request_id !== "string") {
    return NextResponse.json({ error: "invalid_message" }, { status: 422 });
  }
  const content = (body as { content: string }).content;
  const requestId = (body as { request_id: string }).request_id.trim();
  if (!requestId || requestId.length > 200) return NextResponse.json({ error: "invalid_message" }, { status: 422 });
  const rawMode = (body as { invocation_mode?: unknown }).invocation_mode;
  const rawSkill = (body as { skill_id?: unknown }).skill_id;
  if (rawMode !== undefined && rawMode !== "auto" && rawMode !== "explicit") return NextResponse.json({ error: "invalid_skill_route" }, { status: 422 });
  if (rawSkill !== undefined && rawSkill !== null && !["investment-research", "portfolio-review", "investment-checklist"].includes(rawSkill as string)) return NextResponse.json({ error: "invalid_skill_route" }, { status: 422 });
  const parsed = parseSkillCommand(content);
  const skillId = (rawSkill === undefined ? parsed.skillId : rawSkill) as SkillId | null;
  const invocationMode = (rawMode ?? (skillId ? "explicit" : "auto")) as InvocationMode;
  if (invocationMode === "explicit" && !skillId) return NextResponse.json({ error: "invalid_skill_route" }, { status: 422 });
  const question = parsed.skillId && rawSkill === undefined ? parsed.text : content;
  try {
    const run = await admitDemoRun({ ownerId: current.id, threadId, requestId, question: validateDemoMessage(question), invocationMode, skillId });
    return NextResponse.json({
      research_available: true,
      run: {
        id: run.runId,
        user_message_id: run.userMessageId,
        assistant_message_id: run.assistantMessageId,
        status: run.status,
        idempotent: run.idempotent,
        invocation_mode: run.invocationMode,
        skill_id: run.skillId,
      },
    }, { status: 201 });
  } catch (error) {
      if (errorIncludes(error, "invalid_message")) return NextResponse.json({ error: "invalid_message" }, { status: 422 });
      if (errorIncludes(error, "demo_runner_busy")) return NextResponse.json({ error: "demo_runner_busy", message: "Agent 正忙，请稍后重试" }, { status: 409 });
      if (errorIncludes(error, "demo_runner_unavailable")) return NextResponse.json({ error: "demo_runner_unavailable", message: "Agent 暂时不可用" }, { status: 503 });
      if (errorIncludes(error, "foreign key")) return NextResponse.json({ error: "thread_not_found" }, { status: 404 });
    return NextResponse.json({ error: "message_create_failed" }, { status: 503 });
  }
}

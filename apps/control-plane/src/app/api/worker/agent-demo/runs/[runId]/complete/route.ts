import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { completeDemoRun } from "../../../../../../lib/db/repositories/agent-demo-runs";
import { safeAssistantMarkdown } from "../../../../../../lib/agent-demo/contract";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function POST(request: Request, context: { params: Promise<{ runId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { runId } = await context.params;
  if (!uuidPattern.test(runId)) return NextResponse.json({ error: "invalid_run_id" }, { status: 422 });
  let body: unknown;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_json" }, { status: 400 }); }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 2 || typeof (body as { content?: unknown }).content !== "string" || typeof (body as { provider?: unknown }).provider !== "string") {
    return NextResponse.json({ error: "invalid_demo_completion" }, { status: 422 });
  }
  try {
    const content = safeAssistantMarkdown((body as { content: string }).content);
    const provider = (body as { provider: string }).provider.trim();
    if (!provider) return NextResponse.json({ error: "invalid_demo_completion" }, { status: 422 });
    return NextResponse.json(await completeDemoRun(runId, worker.id, content, provider));
  } catch (error) {
    if (error instanceof Error && error.message.includes("not_running")) return NextResponse.json({ error: "demo_run_not_owned" }, { status: 409 });
    return NextResponse.json({ error: "demo_completion_failed" }, { status: 503 });
  }
}

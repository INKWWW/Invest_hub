import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { claimDemoRun } from "../../../../../lib/db/repositories/agent-demo-runs";
import { buildGeneralPrompt, type GeneralHistoryMessage } from "../../../../../lib/agent-demo/general-answer";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_json" }, { status: 400 }); }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1 || typeof (body as { run_id?: unknown }).run_id !== "string" || !uuidPattern.test((body as { run_id: string }).run_id)) {
    return NextResponse.json({ error: "invalid_demo_claim" }, { status: 422 });
  }
  try {
    const claim = await claimDemoRun((body as { run_id: string }).run_id, worker.id);
    if (!claim) return new Response(null, { status: 204 });
    const record = claim as Record<string, unknown>;
    if (record.invocation_mode === "auto" && record.skill_id === null && Array.isArray(record.history) && typeof record.question === "string") {
      const history = record.history.filter((message): message is GeneralHistoryMessage => Boolean(message) && typeof message === "object" && ((message as Record<string, unknown>).role === "user" || (message as Record<string, unknown>).role === "assistant") && typeof (message as Record<string, unknown>).content === "string");
      return NextResponse.json({ ...record, general_prompt: buildGeneralPrompt(history, record.question) });
    }
    return NextResponse.json(claim);
  } catch { return NextResponse.json({ error: "demo_claim_failed" }, { status: 503 }); }
}

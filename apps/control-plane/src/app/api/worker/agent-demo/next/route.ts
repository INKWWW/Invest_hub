import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { findNextQueuedDemoRunId } from "../../../../../lib/db/repositories/agent-demo-runs";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const runId = await findNextQueuedDemoRunId();
    return runId ? NextResponse.json({ run_id: runId }) : new Response(null, { status: 204 });
  } catch {
    return NextResponse.json({ error: "demo_queue_unavailable" }, { status: 503 });
  }
}

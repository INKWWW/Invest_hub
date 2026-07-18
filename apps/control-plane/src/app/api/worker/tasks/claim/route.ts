import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { claimNextTask } from "../../../../../lib/db/repositories/tasks";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const claim = await claimNextTask(worker.id);
    if (!claim) return new Response(null, { status: 204 });
    return NextResponse.json(claim);
  } catch {
    return NextResponse.json({ error: "claim_failed" }, { status: 503 });
  }
}

import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { getXVerificationReplayContext } from "../../../../../../lib/db/repositories/x-v3-verification-replays";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isAttemptRequest(value: unknown): value is { attempt: 1 } {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 1
    && (value as { attempt?: unknown }).attempt === 1;
}

export async function POST(request: Request, context: { params: Promise<{ replayId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_v3_verification_context" }, { status: 422 });
  }
  const { replayId } = await context.params;
  if (!uuidPattern.test(replayId) || !isAttemptRequest(body)) return NextResponse.json({ error: "invalid_x_v3_verification_context" }, { status: 422 });
  try {
    return NextResponse.json(await getXVerificationReplayContext(replayId, body.attempt, worker.id));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_v3_verification_context_failed" }, { status: 503 });
  }
}

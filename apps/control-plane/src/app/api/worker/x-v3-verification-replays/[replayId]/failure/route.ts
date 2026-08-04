import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { failXVerificationReplay, type XVerificationReplayFailureClass } from "../../../../../../lib/db/repositories/x-v3-verification-replays";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const failureClasses = new Set<XVerificationReplayFailureClass>(["timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure"]);

function isFailureRequest(value: unknown): value is { attempt: 1; failure_class: XVerificationReplayFailureClass } {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 2
    && (value as { attempt?: unknown }).attempt === 1 && typeof (value as { failure_class?: unknown }).failure_class === "string"
    && failureClasses.has((value as { failure_class: XVerificationReplayFailureClass }).failure_class);
}

export async function POST(request: Request, context: { params: Promise<{ replayId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_v3_verification_failure" }, { status: 422 });
  }
  const { replayId } = await context.params;
  if (!uuidPattern.test(replayId) || !isFailureRequest(body)) return NextResponse.json({ error: "invalid_x_v3_verification_failure" }, { status: 422 });
  try {
    return NextResponse.json(await failXVerificationReplay(replayId, body.attempt, worker.id, body.failure_class));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "x_v3_verification_failure_rejected" }, { status: 503 });
  }
}

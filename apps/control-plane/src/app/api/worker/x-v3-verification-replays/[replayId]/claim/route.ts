import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { claimXVerificationReplay } from "../../../../../../lib/db/repositories/x-v3-verification-replays";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isEmptyObject(value: unknown) {
  return value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 0;
}

export async function POST(request: Request, context: { params: Promise<{ replayId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_v3_verification_claim" }, { status: 422 });
  }
  const { replayId } = await context.params;
  if (!uuidPattern.test(replayId) || !isEmptyObject(body)) return NextResponse.json({ error: "invalid_x_v3_verification_claim" }, { status: 422 });
  try {
    const claim = await claimXVerificationReplay(replayId, worker.id);
    if (!claim) return new Response(null, { status: 204 });
    return NextResponse.json({ replay_id: claim.replayId, attempt: claim.attempt, lease_expires_at: claim.leaseExpiresAt });
  } catch (error) {
    if ((error as { code?: string }).code === "42501") return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    return NextResponse.json({ error: "x_v3_verification_claim_failed" }, { status: 503 });
  }
}

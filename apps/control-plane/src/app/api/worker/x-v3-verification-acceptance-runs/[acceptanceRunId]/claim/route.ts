import { NextResponse } from "next/server";
import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { claimXVerificationAcceptanceRun } from "../../../../../../lib/db/repositories/x-v3-verification-acceptance-runs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request: Request, context: { params: Promise<{ acceptanceRunId: string }> }) {
  const worker = await authenticateWorker(request); if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown; try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_x_v3_verification_claim" }, { status: 422 }); }
  const { acceptanceRunId } = await context.params;
  if (!uuidPattern.test(acceptanceRunId) || body === null || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 0) return NextResponse.json({ error: "invalid_x_v3_verification_claim" }, { status: 422 });
  try { const claim = await claimXVerificationAcceptanceRun(acceptanceRunId, worker.id); return claim ? NextResponse.json({ acceptance_run_id: claim.acceptanceRunId, attempt: claim.attempt, lease_expires_at: claim.leaseExpiresAt }) : new Response(null, { status: 204 }); }
  catch { return NextResponse.json({ error: "x_v3_verification_claim_failed" }, { status: 503 }); }
}

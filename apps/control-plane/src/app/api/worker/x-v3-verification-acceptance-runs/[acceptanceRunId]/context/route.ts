import { NextResponse } from "next/server";
import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { getXVerificationAcceptanceContext } from "../../../../../../lib/db/repositories/x-v3-verification-acceptance-runs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request: Request, context: { params: Promise<{ acceptanceRunId: string }> }) {
  const worker = await authenticateWorker(request); if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown; try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_x_v3_verification_context" }, { status: 422 }); }
  const { acceptanceRunId } = await context.params;
  if (!uuidPattern.test(acceptanceRunId) || body === null || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1 || (body as { attempt?: unknown }).attempt !== 1) return NextResponse.json({ error: "invalid_x_v3_verification_context" }, { status: 422 });
  try {
    const frozenContext = await getXVerificationAcceptanceContext(acceptanceRunId, 1, worker.id);
    return NextResponse.json({
      acceptance_run_id: acceptanceRunId,
      attempt: frozenContext.attempt,
      sources: frozenContext.sources,
    });
  }
  catch (error) { const code = (error as { code?: string }).code; return NextResponse.json({ error: code === "PT409" || code === "40001" ? "lease_mismatch" : "x_v3_verification_context_failed" }, { status: code === "PT409" || code === "40001" ? 409 : 503 }); }
}

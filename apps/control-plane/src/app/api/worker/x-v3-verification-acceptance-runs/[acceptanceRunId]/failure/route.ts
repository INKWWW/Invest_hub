import { NextResponse } from "next/server";
import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { failXVerificationAcceptanceRun } from "../../../../../../lib/db/repositories/x-v3-verification-acceptance-runs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const classes = new Set(["timeout", "provider_failure", "empty_response", "invalid_json", "schema_error", "persistence_failure"]);
export async function POST(request: Request, context: { params: Promise<{ acceptanceRunId: string }> }) {
  const worker = await authenticateWorker(request); if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown; try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_x_v3_verification_failure" }, { status: 422 }); }
  const { acceptanceRunId } = await context.params; const failure = body as { attempt?: unknown; failure_class?: unknown };
  if (!uuidPattern.test(acceptanceRunId) || body === null || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 2 || failure.attempt !== 1 || typeof failure.failure_class !== "string" || !classes.has(failure.failure_class)) return NextResponse.json({ error: "invalid_x_v3_verification_failure" }, { status: 422 });
  try { return NextResponse.json(await failXVerificationAcceptanceRun(acceptanceRunId, 1, worker.id, failure.failure_class as "timeout" | "provider_failure" | "empty_response" | "invalid_json" | "schema_error" | "persistence_failure")); }
  catch (error) { const code = (error as { code?: string }).code; return NextResponse.json({ error: code === "PT409" || code === "40001" ? "lease_mismatch" : "x_v3_verification_failure_rejected" }, { status: code === "PT409" || code === "40001" ? 409 : 503 }); }
}

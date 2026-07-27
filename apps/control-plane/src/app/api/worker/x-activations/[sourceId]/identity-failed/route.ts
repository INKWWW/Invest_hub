import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { markXActivationIdentityFailed, XActivationError } from "../../../../../../lib/db/repositories/x-activations";

export async function POST(request: Request, context: { params: Promise<{ sourceId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { sourceId } = await context.params;
  try {
    const body = await request.json();
    if (!/^[0-9a-f-]{36}$/i.test(sourceId) || !body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).join(",") !== "error_code" || !["identity_mismatch", "invalid_x_identity", "profile_timeout", "profile_invocation_failed", "activation_protocol_failure", "identity_resolution_failed"].includes((body as { error_code?: unknown }).error_code as string)) {
      return NextResponse.json({ error: "invalid_x_activation" }, { status: 422 });
    }
    const activation = await markXActivationIdentityFailed({ sourceId, workerId: worker.id, errorCode: (body as { error_code: string }).error_code });
    return NextResponse.json({ activation: { source_id: activation.sourceId, stage: activation.stage } });
  } catch (error) {
    if (error instanceof XActivationError && error.message === "worker_not_authorized") return NextResponse.json({ error: "worker_not_authorized" }, { status: 403 });
    return NextResponse.json({ error: "x_activation_failure_record_failed" }, { status: 503 });
  }
}

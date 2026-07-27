import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { claimXActivation, XActivationError } from "../../../../../lib/db/repositories/x-activations";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const activation = await claimXActivation(worker.id, new Date().toISOString());
    return NextResponse.json({ activation: activation && {
      source_id: activation.sourceId,
      requested_handle: activation.requestedHandle,
      parameter_version: activation.parameterVersion,
      initial_end_at: activation.initialEndAt,
      idempotent: activation.idempotent,
    } });
  } catch (error) {
    if (error instanceof XActivationError && error.message === "worker_not_authorized") return NextResponse.json({ error: "worker_not_authorized" }, { status: 403 });
    return NextResponse.json({ error: "x_activation_claim_failed" }, { status: 503 });
  }
}

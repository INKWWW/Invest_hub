import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { resolveXSourceIdentity } from "../../../../../../lib/db/repositories/x-identities";

const xHandle = /^[a-z0-9_]{1,15}$/;

type IdentityBody = {
  parameterVersion: string;
  accountId: string;
};

async function parseIdentityBody(request: Request): Promise<IdentityBody | null> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body)) return null;
    const value = body as Record<string, unknown>;
    if (Object.keys(value).length !== 2
      || !("parameter_version" in value) || !("account_id" in value)
      || typeof value.parameter_version !== "string" || value.parameter_version.length === 0
      || typeof value.account_id !== "string" || !xHandle.test(value.account_id)) {
      return null;
    }
    return { parameterVersion: value.parameter_version, accountId: value.account_id };
  } catch {
    return null;
  }
}

function errorCode(error: unknown): string {
  return error && typeof error === "object" && "message" in error && typeof error.message === "string"
    ? error.message
    : "";
}

export async function POST(request: Request, context: { params: Promise<{ sourceId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const body = await parseIdentityBody(request);
  if (!body) return NextResponse.json({ error: "invalid_x_identity_resolution" }, { status: 422 });
  const { sourceId } = await context.params;
  try {
    const identity = await resolveXSourceIdentity({
      sourceId,
      workerId: worker.id,
      parameterVersion: body.parameterVersion,
      accountId: body.accountId,
    });
    return NextResponse.json({
      identity: {
        resolution_status: identity.resolutionStatus,
        parameter_version: identity.parameterVersion,
        idempotent: identity.idempotent,
      },
    });
  } catch (error) {
    const code = errorCode(error);
    if (code === "worker_not_authorized") return NextResponse.json({ error: "worker_not_authorized" }, { status: 403 });
    if (code === "x_identity_conflict" || code === "x_identity_activation_blocked") {
      return NextResponse.json({ error: code }, { status: 409 });
    }
    if (code === "source_not_found") return NextResponse.json({ error: "source_not_found" }, { status: 404 });
    if (code === "source_parameter_version_mismatch" || code === "invalid_x_identity") {
      return NextResponse.json({ error: "invalid_x_identity_resolution" }, { status: 422 });
    }
    return NextResponse.json({ error: "x_identity_resolution_rejected" }, { status: 503 });
  }
}

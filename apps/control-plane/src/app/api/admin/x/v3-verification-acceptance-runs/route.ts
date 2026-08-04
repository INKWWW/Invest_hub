import { NextResponse } from "next/server";
import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createXVerificationAcceptanceRun } from "../../../../../lib/db/repositories/x-v3-verification-acceptance-runs";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const isCreateRequest = (value: unknown): value is { replay_id: string } => value !== null && typeof value === "object" && !Array.isArray(value) && Object.keys(value).length === 1 && typeof (value as { replay_id?: unknown }).replay_id === "string" && uuidPattern.test((value as { replay_id: string }).replay_id);

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  let body: unknown;
  try { body = await request.json(); } catch { return NextResponse.json({ error: "invalid_x_v3_verification_acceptance" }, { status: 422 }); }
  if (!isCreateRequest(body)) return NextResponse.json({ error: "invalid_x_v3_verification_acceptance" }, { status: 422 });
  try {
    const run = await createXVerificationAcceptanceRun(body.replay_id, current.id);
    return NextResponse.json({ acceptance_run_id: run.acceptanceRunId, status: run.status }, { status: 202 });
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "22023" || code === "23505") return NextResponse.json({ error: "x_v3_verification_acceptance_unavailable" }, { status: 422 });
    if (code === "42501") return NextResponse.json({ error: "forbidden" }, { status: 403 });
    return NextResponse.json({ error: "x_v3_verification_acceptance_create_failed" }, { status: 503 });
  }
}

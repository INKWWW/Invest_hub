import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createXVerificationReplay } from "../../../../../lib/db/repositories/x-v3-verification-replays";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function isCreateRequest(value: unknown): value is { source_batch_id: string } {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    && Object.keys(value).length === 1 && typeof (value as { source_batch_id?: unknown }).source_batch_id === "string"
    && uuidPattern.test((value as { source_batch_id: string }).source_batch_id);
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_v3_verification_replay" }, { status: 422 });
  }
  if (!isCreateRequest(body)) return NextResponse.json({ error: "invalid_x_v3_verification_replay" }, { status: 422 });
  try {
    const replay = await createXVerificationReplay(body.source_batch_id, current.id);
    return NextResponse.json({ replay_id: replay.replayId, status: replay.status }, { status: 202 });
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "22023" || code === "23505") return NextResponse.json({ error: "x_v3_verification_replay_unavailable" }, { status: 422 });
    if (code === "42501") return NextResponse.json({ error: "forbidden" }, { status: 403 });
    return NextResponse.json({ error: "x_v3_verification_replay_create_failed" }, { status: 503 });
  }
}

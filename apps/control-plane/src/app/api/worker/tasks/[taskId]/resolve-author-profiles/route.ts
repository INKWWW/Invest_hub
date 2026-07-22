import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { resolveWindowedAuthorProfiles } from "../../../../../../lib/db/repositories/tasks";

async function parseAttempt(request: Request): Promise<number | null> {
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1) return null;
    const attempt = (body as { attempt?: unknown }).attempt;
    return Number.isInteger(attempt) && typeof attempt === "number" && attempt > 0 ? attempt : null;
  } catch {
    return null;
  }
}

export async function POST(request: Request, context: { params: Promise<{ taskId: string }> }) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const attempt = await parseAttempt(request);
  if (attempt === null) return NextResponse.json({ error: "invalid_author_profile_resolution" }, { status: 422 });
  const { taskId } = await context.params;
  try {
    return NextResponse.json(await resolveWindowedAuthorProfiles(taskId, attempt, worker.id));
  } catch (error) {
    const code = typeof error === "object" && error && "code" in error ? error.code : undefined;
    if (code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    return NextResponse.json({ error: "author_profile_resolution_rejected" }, { status: 503 });
  }
}

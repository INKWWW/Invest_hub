import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../../lib/auth/require-role";
import { initializeXCoverage, XSourceError } from "../../../../../../../lib/db/repositories/x-sources";

export async function POST(request: Request, context: { params: Promise<{ sourceId: string }> }) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const body = await request.json() as Record<string, unknown>;
    if (Object.keys(body).length !== 1 || typeof body.coverage_start_at !== "string" || !Number.isFinite(Date.parse(body.coverage_start_at))) return NextResponse.json({ error: "invalid_coverage_boundary" }, { status: 422 });
    const coverage = await initializeXCoverage({ sourceId, actorId: current.id, boundary: body.coverage_start_at });
    return NextResponse.json({ coverage: { source_id: coverage.sourceId, coverage_start_at: coverage.coverageStartAt, coverage_through_at: coverage.coverageThroughAt } });
  } catch (error) {
    if (error instanceof XSourceError) return NextResponse.json({ error: error.message }, { status: error.message === "coverage_already_initialized" ? 409 : 422 });
    return NextResponse.json({ error: "x_coverage_initialize_failed" }, { status: 503 });
  }
}

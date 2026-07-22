import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../lib/auth/require-role";
import { getSourceCoverage, initializeSourceCoverage, WindowedSyncError } from "../../../../../../lib/db/repositories/windowed-sync";

type RouteContext = { params: Promise<{ sourceId: string }> };

function diagnostic(error: unknown) {
  if (!error || typeof error !== "object") return { code: "unknown", message: "unknown" };
  const value = error as Record<string, unknown>;
  return {
    code: typeof value.code === "string" ? value.code : "unknown",
    message: typeof value.message === "string" ? value.message : "unknown",
  };
}

function validBody(value: unknown): value is { coverage_start_at: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 1
    && typeof body.coverage_start_at === "string"
    && Number.isFinite(Date.parse(body.coverage_start_at));
}

function coverageResponse(coverage: { sourceId: string; coverageStartAt: string; coverageThroughAt: string }) {
  return {
    source_id: coverage.sourceId,
    coverage_start_at: coverage.coverageStartAt,
    coverage_through_at: coverage.coverageThroughAt,
  };
}

export async function GET(_: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const coverage = await getSourceCoverage(sourceId);
    return NextResponse.json({ coverage: coverage ? coverageResponse(coverage) : null });
  } catch (error) {
    console.error("coverage_read_failed", diagnostic(error));
    return NextResponse.json({ error: "coverage_read_failed" }, { status: 503 });
  }
}

export async function POST(request: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const body = await request.json();
    if (!validBody(body)) return NextResponse.json({ error: "invalid_coverage_boundary" }, { status: 422 });
    const coverage = await initializeSourceCoverage({
      sourceId,
      actorId: current.id,
      coverageStartAt: body.coverage_start_at,
    });
    return NextResponse.json({ coverage: coverageResponse(coverage) });
  } catch (error) {
    if (error instanceof WindowedSyncError && error.message === "coverage_already_initialized") {
      return NextResponse.json({ error: error.message }, { status: 409 });
    }
    console.error("coverage_initialize_failed", diagnostic(error));
    return NextResponse.json({ error: "coverage_initialize_failed" }, { status: 503 });
  }
}

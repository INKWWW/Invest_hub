import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createXSource, XSourceError } from "../../../../../lib/db/repositories/x-sources";
import { buildSourceCreation, publicCreatedSource } from "../../../../../lib/source-creation";

function validBody(value: unknown): value is { display_name: string; requested_handle: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 2
    && [body.display_name, body.requested_handle].every((item) => typeof item === "string" && item.trim().length > 0 && item.length <= 128);
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json();
    if (!validBody(body)) return NextResponse.json({ error: "invalid_x_source" }, { status: 422 });
    const creation = buildSourceCreation("x");
    const source = await createXSource({
      sourceKey: creation.sourceKey,
      displayName: body.display_name.trim(),
      requestedHandle: body.requested_handle.trim().replace(/^@/, ""),
      parameterVersion: creation.parameterVersion,
      actorId: current.id,
    });
    return NextResponse.json({ source: publicCreatedSource({
      sourceType: "x",
      displayName: source.displayName,
      resolutionStatus: source.resolutionStatus,
      sourceKey: source.sourceKey,
      parameterVersion: source.parameterVersion,
      id: source.id,
    }) }, { status: 201 });
  } catch (error) {
    if (error instanceof XSourceError) return NextResponse.json({ error: error.message }, { status: 422 });
    return NextResponse.json({ error: "x_source_create_failed" }, { status: 503 });
  }
}

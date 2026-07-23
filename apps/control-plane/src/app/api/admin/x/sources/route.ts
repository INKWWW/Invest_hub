import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../lib/auth/require-role";
import { createXSource, XSourceError } from "../../../../../lib/db/repositories/x-sources";

function validBody(value: unknown): value is { source_key: string; display_name: string; requested_handle: string; parameter_version: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 4 && [body.source_key, body.display_name, body.requested_handle, body.parameter_version].every((item) => typeof item === "string" && item.trim().length > 0 && item.length <= 128);
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = await request.json();
    if (!validBody(body)) return NextResponse.json({ error: "invalid_x_source" }, { status: 422 });
    const source = await createXSource({ sourceKey: body.source_key.trim(), displayName: body.display_name.trim(), requestedHandle: body.requested_handle.trim().replace(/^@/, ""), parameterVersion: body.parameter_version.trim(), actorId: current.id });
    return NextResponse.json({ source }, { status: 201 });
  } catch (error) {
    if (error instanceof XSourceError) return NextResponse.json({ error: error.message }, { status: 422 });
    return NextResponse.json({ error: "x_source_create_failed" }, { status: 503 });
  }
}

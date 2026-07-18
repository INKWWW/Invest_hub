import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import { listSources, upsertDiscordSource } from "../../../../lib/db/repositories/sources";

export async function GET() {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    return NextResponse.json({ sources: await listSources() });
  } catch {
    return NextResponse.json({ error: "source_list_failed" }, { status: 503 });
  }
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (typeof body.source_key !== "string" || typeof body.display_name !== "string" || typeof body.parameter_version !== "string") {
      return NextResponse.json({ error: "invalid_source" }, { status: 422 });
    }
    const source = await upsertDiscordSource({
      sourceKey: body.source_key,
      displayName: body.display_name,
      parameterVersion: body.parameter_version,
      createdBy: current.id,
      enabled: body.enabled !== false,
    });
    return NextResponse.json({ source }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "source_create_failed" }, { status: 503 });
  }
}

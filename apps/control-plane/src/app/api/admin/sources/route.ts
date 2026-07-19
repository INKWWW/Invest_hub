import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import {
  listSources,
  SourceAdministrationError,
  updateSourceAdministration,
  upsertDiscordSource,
} from "../../../../lib/db/repositories/sources";

function hasOnlyKeys(body: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(body).every((key) => allowed.includes(key));
}

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
    if (!hasOnlyKeys(body, ["source_key", "display_name", "parameter_version", "enabled"])
      || typeof body.source_key !== "string" || typeof body.display_name !== "string" || typeof body.parameter_version !== "string") {
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

export async function PATCH(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (!hasOnlyKeys(body, ["source_id", "enabled", "authorized_worker_id"])
      || typeof body.source_id !== "string"
      || typeof body.enabled !== "boolean"
      || (typeof body.authorized_worker_id !== "string" && body.authorized_worker_id !== null)) {
      return NextResponse.json({ error: "invalid_source_administration" }, { status: 422 });
    }
    const source = await updateSourceAdministration({
      sourceId: body.source_id,
      enabled: body.enabled,
      authorizedWorkerId: body.authorized_worker_id,
    });
    return NextResponse.json({ source });
  } catch (error) {
    if (error instanceof SourceAdministrationError) {
      return NextResponse.json({ error: error.message }, { status: 422 });
    }
    return NextResponse.json({ error: "source_update_failed" }, { status: 503 });
  }
}

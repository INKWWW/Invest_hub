import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import {
  getSourceType,
  listSources,
  SourceAdministrationError,
  updateSourceAdministration,
  upsertDiscordSource,
} from "../../../../lib/db/repositories/sources";
import { buildSourceCreation, publicCreatedSource } from "../../../../lib/source-creation";

function hasOnlyKeys(body: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(body).every((key) => allowed.includes(key));
}

function isCommunityChannelName(value: string): boolean {
  const parts = value.split("·").map((part) => part.trim()).filter(Boolean);
  return value.trim().length <= 128
    && parts.length === 2
    && !/^discord\s+source\s+\d+$/i.test(value.trim());
}

function isXDisplayName(value: string): boolean {
  return value.trim().length > 0 && value.trim().length <= 128;
}

function validDiscordCreateBody(value: unknown): value is { display_name: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 1
    && typeof body.display_name === "string"
    && isCommunityChannelName(body.display_name);
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
    const body = await request.json();
    if (!validDiscordCreateBody(body)) {
      return NextResponse.json({ error: "invalid_source" }, { status: 422 });
    }
    const creation = buildSourceCreation("discord");
    const source = await upsertDiscordSource({
      sourceKey: creation.sourceKey,
      displayName: body.display_name.trim(),
      parameterVersion: creation.parameterVersion,
      createdBy: current.id,
      enabled: true,
    });
    return NextResponse.json({ source: publicCreatedSource({
      sourceType: "discord",
      displayName: source.display_name,
      sourceKey: source.source_key,
      parameterVersion: source.parameter_version,
      id: source.id,
    }) }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "source_create_failed" }, { status: 503 });
  }
}

export async function PATCH(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (!hasOnlyKeys(body, ["source_id", "display_name", "enabled", "authorized_worker_id"])
      || typeof body.source_id !== "string"
      || typeof body.display_name !== "string"
      || typeof body.enabled !== "boolean"
      || (typeof body.authorized_worker_id !== "string" && body.authorized_worker_id !== null)) {
      return NextResponse.json({ error: "invalid_source_administration" }, { status: 422 });
    }
    const sourceType = await getSourceType(body.source_id);
    if (!sourceType
      || (sourceType === "discord" && !isCommunityChannelName(body.display_name))
      || (sourceType === "x" && !isXDisplayName(body.display_name))) {
      return NextResponse.json({ error: "invalid_source_administration" }, { status: 422 });
    }
    const source = await updateSourceAdministration({
      sourceId: body.source_id,
      displayName: body.display_name.trim(),
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

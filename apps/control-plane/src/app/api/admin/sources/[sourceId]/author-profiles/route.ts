import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../lib/auth/require-role";
import {
  deleteSourceAuthorProfile,
  listSourceAuthorProfiles,
  saveSourceAuthorProfile,
  SourceAuthorProfileError,
} from "../../../../../../lib/db/repositories/author-profiles";

type RouteContext = { params: Promise<{ sourceId: string }> };

function validAuthorId(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0 && value.length <= 256;
}
function profileResponse(profile: {
  sourceId: string;
  authorId: string;
  authorDisplay: string;
  authorHandle: string | null;
  enabled: boolean;
}) {
  return {
    source_id: profile.sourceId,
    author_id: profile.authorId,
    author_display: profile.authorDisplay,
    author_handle: profile.authorHandle,
    enabled: profile.enabled,
  };
}

async function parseRequestBody(request: Request): Promise<Record<string, unknown> | null> {
  const value = await request.json();
  return value && typeof value === "object" && !Array.isArray(value) ? value as Record<string, unknown> : null;
}

export async function GET(_: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const profiles = await listSourceAuthorProfiles(sourceId);
    return NextResponse.json({ author_profiles: profiles.map(profileResponse) });
  } catch {
    return NextResponse.json({ error: "author_profile_list_failed" }, { status: 503 });
  }
}

export async function POST(request: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const body = await parseRequestBody(request);
    if (!body || Object.keys(body).length !== 1 || !validAuthorId(body.author_id)) {
      return NextResponse.json({ error: "invalid_author_profile" }, { status: 422 });
    }
    const profile = await saveSourceAuthorProfile({
      sourceId,
      authorId: body.author_id,
      enabled: true,
      actorId: current.id,
    });
    return NextResponse.json({ author_profile: profileResponse(profile) }, { status: 201 });
  } catch (error) {
    if (error instanceof SourceAuthorProfileError) {
      return NextResponse.json({ error: error.message }, { status: 422 });
    }
    return NextResponse.json({ error: "author_profile_save_failed" }, { status: 503 });
  }
}

export async function PATCH(request: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const body = await parseRequestBody(request);
    if (!body || Object.keys(body).some((key) => key !== "author_id" && key !== "enabled")
      || !validAuthorId(body.author_id) || typeof body.enabled !== "boolean") {
      return NextResponse.json({ error: "invalid_author_profile" }, { status: 422 });
    }
    const profile = await saveSourceAuthorProfile({
      sourceId,
      authorId: body.author_id,
      enabled: body.enabled,
      actorId: current.id,
    });
    return NextResponse.json({ author_profile: profileResponse(profile) });
  } catch (error) {
    if (error instanceof SourceAuthorProfileError) {
      return NextResponse.json({ error: error.message }, { status: 422 });
    }
    return NextResponse.json({ error: "author_profile_save_failed" }, { status: 503 });
  }
}

export async function DELETE(request: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const body = await parseRequestBody(request);
    if (!body || Object.keys(body).length !== 1 || !validAuthorId(body.author_id)) {
      return NextResponse.json({ error: "invalid_author_profile" }, { status: 422 });
    }
    const deleted = await deleteSourceAuthorProfile({ sourceId, authorId: body.author_id });
    return NextResponse.json({ deleted });
  } catch {
    return NextResponse.json({ error: "author_profile_delete_failed" }, { status: 503 });
  }
}

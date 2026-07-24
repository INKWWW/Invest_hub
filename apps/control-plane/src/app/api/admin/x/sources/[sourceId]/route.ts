import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../lib/auth/require-role";
import { removeXSource, XSourceError } from "../../../../../../lib/db/repositories/x-sources";

type RouteContext = { params: Promise<{ sourceId: string }> };

function validBody(value: unknown): value is { confirmation_name: string } {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const body = value as Record<string, unknown>;
  return Object.keys(body).length === 1
    && typeof body.confirmation_name === "string"
    && body.confirmation_name.length > 0
    && body.confirmation_name.length <= 256;
}

export async function DELETE(request: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_x_source_removal" }, { status: 422 });
  }
  if (!validBody(body)) return NextResponse.json({ error: "invalid_x_source_removal" }, { status: 422 });

  try {
    const { sourceId } = await context.params;
    const removal = await removeXSource({
      sourceId,
      actorId: current.id,
      confirmationName: body.confirmation_name,
    });
    return NextResponse.json({ removal: { action: removal.action, display_name: removal.displayName } });
  } catch (error) {
    if (error instanceof XSourceError) {
      if (error.message === "confirmation_mismatch" || error.message === "source_has_active_task") {
        return NextResponse.json({ error: error.message }, { status: 409 });
      }
      if (error.message === "source_not_found") return NextResponse.json({ error: error.message }, { status: 404 });
      return NextResponse.json({ error: error.message }, { status: 422 });
    }
    return NextResponse.json({ error: "x_source_removal_failed" }, { status: 503 });
  }
}

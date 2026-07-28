import { NextResponse } from "next/server";

import {
  createOneTimeUserInvite,
  createOneTimeWorkerInvite,
  listRecentUserInvites,
  type InvitePurpose,
} from "../../../../lib/auth/invites";
import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";

const allowedKeys = new Set(["purpose", "expires_in_hours"]);

export async function GET() {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  try {
    const invites = await listRecentUserInvites(20);
    return NextResponse.json({ invites: invites.map((invite) => ({
      code_mask: invite.codeMask,
      validity_hours: invite.validityHours,
      created_at: invite.createdAt,
      expires_at: invite.expiresAt,
      consumed_at: invite.consumedAt,
    })) });
  } catch {
    return NextResponse.json({ error: "invite_list_failed" }, { status: 503 });
  }
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  let body: Record<string, unknown>;
  try {
    const parsed = await request.json();
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return NextResponse.json({ error: "invalid_invite_parameters" }, { status: 422 });
    }
    body = parsed as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (Object.keys(body).some((key) => !allowedKeys.has(key))) {
    return NextResponse.json({ error: "invalid_invite_parameters" }, { status: 422 });
  }

  const purpose = (body.purpose ?? "user") as InvitePurpose;
  const hours = body.expires_in_hours ?? 24;
  if ((purpose !== "user" && purpose !== "worker") || typeof hours !== "number" || !Number.isInteger(hours) || hours <= 0 || hours > 168) {
    return NextResponse.json({ error: "invalid_invite_parameters" }, { status: 422 });
  }

  const now = new Date().toISOString();
  try {
    const invite = purpose === "user"
      ? await createOneTimeUserInvite({ role: "user", expiresInHours: hours, createdBy: current.id, now })
      : await createOneTimeWorkerInvite({
        role: "user",
        expiresAt: new Date(Date.parse(now) + hours * 60 * 60 * 1000).toISOString(),
        createdBy: current.id,
      });
    return NextResponse.json(
      { invite_id: invite.inviteId, code: invite.code, purpose: invite.purpose, expires_at: invite.expiresAt },
      { status: 201 },
    );
  } catch {
    return NextResponse.json({ error: "invite_create_failed" }, { status: 503 });
  }
}

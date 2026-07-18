import { NextResponse } from "next/server";

import { createOneTimeInvite, type InvitePurpose } from "../../../../lib/auth/invites";
import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;

  let body: { purpose?: InvitePurpose; expires_in_hours?: number };
  try {
    body = (await request.json()) as { purpose?: InvitePurpose; expires_in_hours?: number };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const purpose = body.purpose ?? "user";
  const hours = body.expires_in_hours ?? 24;
  if ((purpose !== "user" && purpose !== "worker") || !Number.isFinite(hours) || hours <= 0 || hours > 168) {
    return NextResponse.json({ error: "invalid_invite_parameters" }, { status: 422 });
  }

  const expiresAt = new Date(Date.now() + hours * 60 * 60 * 1000).toISOString();
  try {
    const invite = await createOneTimeInvite({
      purpose,
      role: "user",
      expiresAt,
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

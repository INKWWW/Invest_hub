import { NextResponse } from "next/server";

import { redeemInviteAccount } from "../../../../lib/auth/invites";

export async function POST(request: Request) {
  let body: { code?: string; email?: string; password?: string };
  try {
    body = (await request.json()) as { code?: string; email?: string; password?: string };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body.code || !body.email || !body.password || body.password.length < 8) {
    return NextResponse.json({ error: "invalid_invite_request" }, { status: 422 });
  }
  const result = await redeemInviteAccount({ code: body.code, email: body.email, password: body.password });
  if (!result.ok) {
    const status = result.error === "invite_replayed" ? 409 : 400;
    return NextResponse.json({ error: result.error }, { status });
  }
  return NextResponse.json({ ok: true }, { status: 201 });
}

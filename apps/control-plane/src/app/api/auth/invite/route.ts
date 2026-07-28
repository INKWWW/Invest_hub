import { NextResponse } from "next/server";

import { hashRedemptionSource } from "../../../../lib/auth/invite-code";
import { redeemInviteAccount } from "../../../../lib/auth/invites";

function requestSource(request: Request): string {
  const vercelSource = request.headers.get("x-vercel-forwarded-for")?.split(",")[0]?.trim();
  if (vercelSource) return vercelSource;
  const forwardedSource = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwardedSource || "unknown";
}

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

  const result = await redeemInviteAccount({
    code: body.code,
    email: body.email,
    password: body.password,
    sourceHash: hashRedemptionSource(requestSource(request)),
  });
  if (!result.ok) return NextResponse.json({ error: "invalid_invite" }, { status: 400 });
  return NextResponse.json({ ok: true }, { status: 201 });
}

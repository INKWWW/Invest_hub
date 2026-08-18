import { NextResponse } from "next/server";

import { hashRedemptionSource } from "../../../../lib/auth/invite-code";
import { redeemInviteAccount } from "../../../../lib/auth/invites";
import { loginWithPassword } from "../../../../lib/auth/login";
import { isValidRegistrationPassword } from "../../../../lib/auth/password";

function requestSource(request: Request): string {
  const vercelSource = request.headers.get("x-vercel-forwarded-for")?.split(",")[0]?.trim();
  if (vercelSource) return vercelSource;
  const forwardedSource = request.headers.get("x-forwarded-for")?.split(",")[0]?.trim();
  return forwardedSource || "unknown";
}

export async function POST(request: Request) {
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!isRegistrationRequest(body)) {
    return NextResponse.json({ error: "invalid_invite_request" }, { status: 422 });
  }

  const code = body.code.trim();
  const email = body.email.trim();
  if (!code || !email || !body.password || !isValidRegistrationPassword(body.password)
    || body.password !== body.password_confirmation) {
    return NextResponse.json({ error: "invalid_invite_request" }, { status: 422 });
  }

  const result = await redeemInviteAccount({
    code,
    email,
    password: body.password,
    sourceHash: hashRedemptionSource(requestSource(request)),
  });
  if (!result.ok) return NextResponse.json({ error: "registration_failed" }, { status: 400 });

  const session = await loginWithPassword(email, body.password);
  if (!session.ok) return NextResponse.json({ error: "registration_failed" }, { status: 503 });
  return NextResponse.json({ ok: true, redirect: "/agent" }, { status: 201 });
}

type RegistrationRequest = {
  code: string;
  email: string;
  password: string;
  password_confirmation: string;
};

function isRegistrationRequest(value: unknown): value is RegistrationRequest {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const keys = Object.keys(value);
  if (keys.length !== 4 || keys.some((key) => ![
    "code", "email", "password", "password_confirmation",
  ].includes(key))) return false;
  const body = value as Record<string, unknown>;
  return Object.values(body).every((field) => typeof field === "string");
}

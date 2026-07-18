import { NextResponse } from "next/server";

import { loginWithPassword } from "../../../../lib/auth/login";

export async function POST(request: Request) {
  let body: { email?: string; password?: string };
  try {
    body = (await request.json()) as { email?: string; password?: string };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body.email || !body.password) return NextResponse.json({ error: "invalid_credentials" }, { status: 422 });
  const result = await loginWithPassword(body.email, body.password);
  if (!result.ok) return NextResponse.json({ error: result.error }, { status: 401 });
  return NextResponse.json({ ok: true });
}

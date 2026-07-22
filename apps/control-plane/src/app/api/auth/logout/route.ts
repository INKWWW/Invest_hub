import { NextResponse } from "next/server";

import { signOutCurrentUser } from "../../../../lib/auth/logout";

export async function POST() {
  const result = await signOutCurrentUser();
  if (!result.ok) return NextResponse.json({ error: result.error }, { status: 500 });
  return NextResponse.json({ ok: true });
}

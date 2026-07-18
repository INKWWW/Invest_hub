import { NextResponse } from "next/server";

import { getCurrentUser, type CurrentUser } from "./current-user";
import type { AppRole } from "../db/types";

export async function requireRole(role: AppRole): Promise<CurrentUser | NextResponse> {
  const user = await getCurrentUser();
  if (!user) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  if (user.role !== role) return NextResponse.json({ error: "forbidden" }, { status: 403 });
  return user;
}

export function isCurrentUser(value: CurrentUser | NextResponse): value is CurrentUser {
  return !(value instanceof NextResponse);
}

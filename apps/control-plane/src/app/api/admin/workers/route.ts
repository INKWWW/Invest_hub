import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import { listWorkers } from "../../../../lib/db/repositories/workers";

export async function GET() {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    return NextResponse.json({ workers: await listWorkers() });
  } catch {
    return NextResponse.json({ error: "worker_list_failed" }, { status: 503 });
  }
}

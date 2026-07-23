import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { scheduleDueSourceTasks } from "../../../../../lib/db/repositories/tasks";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });

  let body: Record<string, unknown>;
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error("invalid_schedule_tick");
    body = value as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "invalid_schedule_tick" }, { status: 422 });
  }
  if (Object.keys(body).length !== 0) {
    return NextResponse.json({ error: "invalid_schedule_tick" }, { status: 422 });
  }

  try {
    const tick = await scheduleDueSourceTasks(worker.id);
    return NextResponse.json(tick);
  } catch (error) {
    if ((error as { code?: string }).code === "42501") return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    return NextResponse.json({ error: "schedule_tick_failed" }, { status: 503 });
  }
}

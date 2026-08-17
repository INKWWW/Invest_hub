import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../lib/auth/worker";
import { updateWorkerHeartbeat } from "../../../../lib/db/repositories/workers";
import { heartbeatDeadline } from "../../../../lib/tasks/lease";
import { parseContract } from "../../../../lib/contracts";

type Heartbeat = {
  contract_version: "v0";
  worker_id: string;
  sent_at: string;
  status: "idle" | "claimed" | "executing" | "reporting" | "recovering" | "stopped";
  capabilities: Array<"discord_sync" | "x_sync" | "agent_demo">;
};

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: Heartbeat;
  try {
    body = parseContract<Heartbeat>("heartbeat", await request.json());
  } catch {
    return NextResponse.json({ error: "invalid_heartbeat" }, { status: 422 });
  }
  if (body.worker_id !== worker.id) return NextResponse.json({ error: "worker_mismatch" }, { status: 403 });
  try {
    const status = body.status === "stopped" ? "offline" : "online";
    const capabilities = body.capabilities.filter((capability) => (
      capability !== "agent_demo" || worker.capabilities.includes("agent_demo")
    ));
    await updateWorkerHeartbeat(worker.id, status, body.sent_at, capabilities);
    return NextResponse.json({
      worker_id: worker.id,
      status,
      heartbeat_interval_seconds: 60,
      next_heartbeat_at: heartbeatDeadline(new Date(body.sent_at)),
    });
  } catch {
    return NextResponse.json({ error: "heartbeat_failed" }, { status: 503 });
  }
}

import { randomBytes, randomUUID, createHash } from "node:crypto";

import { NextResponse } from "next/server";

import { consumeWorkerInvite } from "../../../../lib/auth/invites";
import { registerWorker } from "../../../../lib/db/repositories/workers";

export async function POST(request: Request) {
  let body: { code?: string; name?: string };
  try {
    body = (await request.json()) as { code?: string; name?: string };
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body.code || !body.name || body.code.length < 8 || body.name.length > 128) {
    return NextResponse.json({ error: "invalid_enrolment" }, { status: 422 });
  }

  const workerId = randomUUID();
  const deviceSecret = randomBytes(32).toString("base64url");
  const deviceSecretHash = createHash("sha256").update(deviceSecret, "utf8").digest("hex");
  try {
    const invite = await consumeWorkerInvite(body.code, workerId);
    if (!invite) return NextResponse.json({ error: "invite_replayed" }, { status: 409 });
    await registerWorker({ id: workerId, name: body.name, deviceSecretHash });
    const expiresAt = invite.expires_at ?? new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    return NextResponse.json(
      { contract_version: "v0", worker_id: workerId, device_secret: deviceSecret, expires_at: expiresAt },
      { status: 201 },
    );
  } catch {
    return NextResponse.json({ error: "enrolment_failed" }, { status: 503 });
  }
}

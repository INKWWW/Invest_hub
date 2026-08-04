import { NextResponse } from "next/server";
import { authenticateWorker } from "../../../../../../lib/auth/worker";
import { completeXVerificationAcceptanceRun, getXVerificationAcceptanceContext } from "../../../../../../lib/db/repositories/x-v3-verification-acceptance-runs";
import { isCompletion, referencesFrozenContext } from "../../../x-v3-verification-replays/[replayId]/complete/route";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export async function POST(request: Request, context: { params: Promise<{ acceptanceRunId: string }> }) {
  const worker = await authenticateWorker(request); if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let completion: unknown; try { completion = await request.json(); } catch { return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 }); }
  const { acceptanceRunId } = await context.params;
  if (!uuidPattern.test(acceptanceRunId) || !isCompletion(completion) || completion.replay_id !== acceptanceRunId) return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
  try {
    const frozen = await getXVerificationAcceptanceContext(acceptanceRunId, completion.attempt, worker.id);
    if (!referencesFrozenContext(completion, frozen)) return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
    return NextResponse.json(await completeXVerificationAcceptanceRun(acceptanceRunId, completion, worker.id));
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code === "PT409" || code === "40001") return NextResponse.json({ error: "lease_mismatch" }, { status: 409 });
    if (code === "22023") return NextResponse.json({ error: "invalid_x_v3_verification_completion" }, { status: 422 });
    return NextResponse.json({ error: "x_v3_verification_completion_rejected" }, { status: 503 });
  }
}

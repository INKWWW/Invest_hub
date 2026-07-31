import { NextResponse } from "next/server";

import { authenticateWorker } from "../../../../../lib/auth/worker";
import { claimNextXDailyJudgement } from "../../../../../lib/db/repositories/x-daily-judgements";

export async function POST(request: Request) {
  const worker = await authenticateWorker(request);
  if (!worker) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const body = await request.json();
    if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 0) throw new Error("invalid");
  } catch {
    return NextResponse.json({ error: "invalid_x_daily_judgement_claim" }, { status: 422 });
  }
  try {
    const claim = await claimNextXDailyJudgement(worker.id);
    return claim ? NextResponse.json(claim) : new Response(null, { status: 204 });
  } catch (error) {
    if ((error as { code?: string }).code === "42501") return NextResponse.json({ error: "unauthorized" }, { status: 401 });
    return NextResponse.json({ error: "x_daily_judgement_claim_failed" }, { status: 503 });
  }
}

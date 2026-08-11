import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../../../lib/auth/current-user";
import {
  appendResearchMessage,
  ResearchThreadNotFoundError,
} from "../../../../../../lib/db/repositories/research-threads";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function POST(request: Request, context: { params: Promise<{ threadId: string }> }) {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { threadId } = await context.params;
  if (!uuidPattern.test(threadId)) return NextResponse.json({ error: "invalid_thread_id" }, { status: 422 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1 || typeof (body as { content?: unknown }).content !== "string") {
    return NextResponse.json({ error: "invalid_message" }, { status: 422 });
  }
  const content = (body as { content: string }).content.trim();
  if (content.length < 1 || content.length > 20000) return NextResponse.json({ error: "invalid_message" }, { status: 422 });
  try {
    const message = await appendResearchMessage(current.id, threadId, content);
    return NextResponse.json({
      research_available: false,
      message: { id: message.id, role: message.role, content: message.content, created_at: message.createdAt },
    }, { status: 201 });
  } catch (error) {
    if (error instanceof ResearchThreadNotFoundError) return NextResponse.json({ error: "thread_not_found" }, { status: 404 });
    return NextResponse.json({ error: "message_create_failed" }, { status: 503 });
  }
}

import { NextResponse } from "next/server";

import { getCurrentUser, type CurrentUser } from "../../../../../lib/auth/current-user";
import {
  deleteResearchThread,
  getResearchThread,
  ResearchThreadNotFoundError,
  renameResearchThread,
} from "../../../../../lib/db/repositories/research-threads";

const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
type RouteContext = { params: Promise<{ threadId: string }> };

function validThreadId(threadId: string): boolean {
  return uuidPattern.test(threadId);
}

function threadResponse(thread: {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
}) {
  return { id: thread.id, title: thread.title, created_at: thread.createdAt, updated_at: thread.updatedAt };
}

function detailResponse(detail: Awaited<ReturnType<typeof getResearchThread>>) {
  return {
    ...threadResponse(detail),
    messages: detail.messages.map((message) => ({
      id: message.id,
      role: message.role,
      content: message.content,
      skill_id: message.skillId,
      created_at: message.createdAt,
    })),
    artifacts: detail.artifacts.map((artifact) => ({
      id: artifact.id,
      artifact_type: artifact.artifactType,
      metadata: artifact.metadata,
      created_at: artifact.createdAt,
    })),
  };
}

type OwnerTarget = { response: NextResponse } | { current: CurrentUser; threadId: string };

async function ownerAndThread(context: RouteContext): Promise<OwnerTarget> {
  const current = await getCurrentUser();
  if (!current) return { response: NextResponse.json({ error: "unauthorized" }, { status: 401 }) };
  const { threadId } = await context.params;
  if (!validThreadId(threadId)) return { response: NextResponse.json({ error: "invalid_thread_id" }, { status: 422 }) };
  return { current, threadId };
}

export async function GET(_request: Request, context: RouteContext): Promise<NextResponse> {
  const target = await ownerAndThread(context);
  if ("response" in target) return target.response;
  try {
    return NextResponse.json({ thread: detailResponse(await getResearchThread(target.current.id, target.threadId)) });
  } catch (error) {
    if (error instanceof ResearchThreadNotFoundError) return NextResponse.json({ error: "thread_not_found" }, { status: 404 });
    return NextResponse.json({ error: "thread_read_failed" }, { status: 503 });
  }
}

export async function PATCH(request: Request, context: RouteContext): Promise<NextResponse> {
  const target = await ownerAndThread(context);
  if ("response" in target) return target.response;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1 || typeof (body as { title?: unknown }).title !== "string") {
    return NextResponse.json({ error: "invalid_thread_title" }, { status: 422 });
  }
  const title = (body as { title: string }).title.trim();
  if (title.length < 1 || title.length > 80) return NextResponse.json({ error: "invalid_thread_title" }, { status: 422 });
  try {
    return NextResponse.json({ thread: threadResponse(await renameResearchThread(target.current.id, target.threadId, title)) });
  } catch (error) {
    if (error instanceof ResearchThreadNotFoundError) return NextResponse.json({ error: "thread_not_found" }, { status: 404 });
    return NextResponse.json({ error: "thread_rename_failed" }, { status: 503 });
  }
}

export async function DELETE(request: Request, context: RouteContext): Promise<NextResponse> {
  const target = await ownerAndThread(context);
  if ("response" in target) return target.response;
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 1 || (body as { confirm?: unknown }).confirm !== true) {
    return NextResponse.json({ error: "deletion_not_confirmed" }, { status: 422 });
  }
  try {
    await deleteResearchThread(target.current.id, target.threadId);
    return NextResponse.json({ deleted: true, memory_management: "separate" });
  } catch (error) {
    if (error instanceof ResearchThreadNotFoundError) return NextResponse.json({ error: "thread_not_found" }, { status: 404 });
    return NextResponse.json({ error: "thread_delete_failed" }, { status: 503 });
  }
}

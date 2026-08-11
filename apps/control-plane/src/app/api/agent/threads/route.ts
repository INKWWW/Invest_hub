import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import {
  createResearchThread,
  listResearchThreads,
} from "../../../../lib/db/repositories/research-threads";

function threadResponse(thread: {
  id: string;
  title: string;
  createdAt: string;
  updatedAt: string;
}) {
  return {
    id: thread.id,
    title: thread.title,
    created_at: thread.createdAt,
    updated_at: thread.updatedAt,
  };
}

export async function GET() {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  try {
    const threads = await listResearchThreads(current.id);
    return NextResponse.json({ threads: threads.map(threadResponse) });
  } catch {
    return NextResponse.json({ error: "thread_list_failed" }, { status: 503 });
  }
}

export async function POST(request: Request) {
  const current = await getCurrentUser();
  if (!current) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }
  if (!body || typeof body !== "object" || Array.isArray(body) || Object.keys(body).length !== 0) {
    return NextResponse.json({ error: "invalid_thread_create" }, { status: 422 });
  }
  try {
    const thread = await createResearchThread(current.id);
    return NextResponse.json({ thread: threadResponse(thread) }, { status: 201 });
  } catch {
    return NextResponse.json({ error: "thread_create_failed" }, { status: 503 });
  }
}

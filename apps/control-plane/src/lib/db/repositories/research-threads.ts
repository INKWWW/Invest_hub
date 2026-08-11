import { automaticThreadTitle } from "../../agent/thread-title";

import { createSupabaseServerClient } from "../supabase-server";

const DEFAULT_THREAD_TITLE = "新研究会话";
const threadFields = "id,owner_id,title,created_at,updated_at";
const messageFields = "id,thread_id,owner_id,role,content,created_at";
const artifactFields = "id,thread_id,owner_id,artifact_type,metadata,created_at";

export type ResearchThread = {
  id: string;
  ownerId: string;
  title: string;
  createdAt: string;
  updatedAt: string;
};

export type ResearchMessage = {
  id: string;
  threadId: string;
  ownerId: string;
  role: "user" | "assistant";
  content: string;
  createdAt: string;
};

export type ResearchThreadArtifact = {
  id: string;
  threadId: string;
  ownerId: string;
  artifactType: string;
  metadata: import("../types").Json;
  createdAt: string;
};

export type ResearchThreadDetail = ResearchThread & {
  messages: ResearchMessage[];
  artifacts: ResearchThreadArtifact[];
};

export class ResearchThreadNotFoundError extends Error {
  constructor() {
    super("research_thread_not_found");
  }
}

function thread(row: {
  id: string;
  owner_id: string;
  title: string;
  created_at: string;
  updated_at: string;
}): ResearchThread {
  return { id: row.id, ownerId: row.owner_id, title: row.title, createdAt: row.created_at, updatedAt: row.updated_at };
}

function message(row: {
  id: string;
  thread_id: string;
  owner_id: string;
  role: "user" | "assistant";
  content: string;
  created_at: string;
}): ResearchMessage {
  return { id: row.id, threadId: row.thread_id, ownerId: row.owner_id, role: row.role, content: row.content, createdAt: row.created_at };
}

function artifact(row: {
  id: string;
  thread_id: string;
  owner_id: string;
  artifact_type: string;
  metadata: import("../types").Json;
  created_at: string;
}): ResearchThreadArtifact {
  const metadata = row.metadata && typeof row.metadata === "object" && !Array.isArray(row.metadata) ? row.metadata : {};
  return { id: row.id, threadId: row.thread_id, ownerId: row.owner_id, artifactType: row.artifact_type, metadata, createdAt: row.created_at };
}

export async function listResearchThreads(ownerId: string): Promise<ResearchThread[]> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("research_threads")
    .select(threadFields)
    .eq("owner_id", ownerId)
    .order("updated_at", { ascending: false })
    .order("id", { ascending: false });
  if (error) throw error;
  return (data ?? []).map(thread);
}

export async function createResearchThread(ownerId: string): Promise<ResearchThread> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("research_threads")
    .insert({ owner_id: ownerId, title: DEFAULT_THREAD_TITLE })
    .select(threadFields)
    .single();
  if (error) throw error;
  return thread(data);
}

export async function getResearchThread(ownerId: string, threadId: string): Promise<ResearchThreadDetail> {
  const supabase = await createSupabaseServerClient();
  const [threadResult, messagesResult, artifactsResult] = await Promise.all([
    supabase.from("research_threads").select(threadFields).eq("owner_id", ownerId).eq("id", threadId).maybeSingle(),
    supabase.from("research_messages").select(messageFields).eq("owner_id", ownerId).eq("thread_id", threadId).order("created_at", { ascending: true }).order("id", { ascending: true }),
    supabase.from("research_thread_artifacts").select(artifactFields).eq("owner_id", ownerId).eq("thread_id", threadId).order("created_at", { ascending: true }).order("id", { ascending: true }),
  ]);
  if (threadResult.error) throw threadResult.error;
  if (!threadResult.data) throw new ResearchThreadNotFoundError();
  if (messagesResult.error) throw messagesResult.error;
  if (artifactsResult.error) throw artifactsResult.error;
  return {
    ...thread(threadResult.data),
    messages: (messagesResult.data ?? []).map(message),
    artifacts: (artifactsResult.data ?? []).map(artifact),
  };
}

export async function renameResearchThread(ownerId: string, threadId: string, title: string): Promise<ResearchThread> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("research_threads")
    .update({ title: title.trim() })
    .eq("owner_id", ownerId)
    .eq("id", threadId)
    .select(threadFields)
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new ResearchThreadNotFoundError();
  return thread(data);
}

export async function deleteResearchThread(ownerId: string, threadId: string): Promise<void> {
  const { data, error } = await (await createSupabaseServerClient())
    .from("research_threads")
    .delete()
    .eq("owner_id", ownerId)
    .eq("id", threadId)
    .select("id")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new ResearchThreadNotFoundError();
}

export async function appendResearchMessage(ownerId: string, threadId: string, content: string): Promise<ResearchMessage> {
  const supabase = await createSupabaseServerClient();
  const { data: existingThread, error: threadError } = await supabase
    .from("research_threads")
    .select("id,title")
    .eq("owner_id", ownerId)
    .eq("id", threadId)
    .maybeSingle();
  if (threadError) throw threadError;
  if (!existingThread) throw new ResearchThreadNotFoundError();

  const { data, error } = await supabase
    .from("research_messages")
    .insert({ thread_id: threadId, owner_id: ownerId, role: "user", content: content.trim() })
    .select(messageFields)
    .single();
  if (error) throw error;

  if (existingThread.title === DEFAULT_THREAD_TITLE) {
    const { error: titleError } = await supabase
      .from("research_threads")
      .update({ title: automaticThreadTitle(content) })
      .eq("owner_id", ownerId)
      .eq("id", threadId)
      .eq("title", DEFAULT_THREAD_TITLE);
    if (titleError) throw titleError;
  }
  return message(data);
}

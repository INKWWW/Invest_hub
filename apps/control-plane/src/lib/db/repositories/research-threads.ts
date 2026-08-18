import { automaticThreadTitle, automaticThreadTitleUpdate, DEFAULT_THREAD_TITLE } from "../../agent/thread-title";
import { SKILL_DEFINITIONS, type SkillId } from "../../agent-demo/skill-routing";

import { createSupabaseServerClient } from "../supabase-server";

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
}, skillId: SkillId | null = null): ResearchMessage {
  return { id: row.id, threadId: row.thread_id, ownerId: row.owner_id, role: row.role, content: row.content, skillId, createdAt: row.created_at };
}

function persistedSkillId(value: unknown): SkillId | null {
  return SKILL_DEFINITIONS.some((definition) => definition.id === value) ? value as SkillId : null;
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
  const supabase = await createSupabaseServerClient();
  const { data, error } = await supabase
    .from("research_threads")
    .select(threadFields)
    .eq("owner_id", ownerId)
    .order("updated_at", { ascending: false })
    .order("id", { ascending: false });
  if (error) throw error;
  const rows = data ?? [];
  if (!rows.length) return [];
  const { data: messages, error: messagesError } = await supabase
    .from("research_messages")
    .select("id,thread_id,content,created_at")
    .eq("owner_id", ownerId)
    .eq("role", "user")
    .order("created_at", { ascending: true })
    .order("id", { ascending: true });
  if (messagesError) throw messagesError;
  const firstMessageByThread = new Map<string, string>();
  for (const row of messages ?? []) if (!firstMessageByThread.has(row.thread_id)) firstMessageByThread.set(row.thread_id, row.content);
  return Promise.all(rows.map(async (row) => {
    const firstUserMessage = firstMessageByThread.get(row.id);
    const title = automaticThreadTitleUpdate(row.title, firstUserMessage);
    if (!title) return thread(row);
    try {
      const { data: persisted, error: persistError } = await supabase
        .from("research_threads")
        .update({ title })
        .eq("owner_id", ownerId)
        .eq("id", row.id)
        .eq("title", DEFAULT_THREAD_TITLE)
        .select(threadFields)
        .maybeSingle();
      if (!persistError && persisted) return thread(persisted);
    } catch {
      // The derived title remains available for this response if persistence is temporarily unavailable.
    }
    return { ...thread(row), title };
  }));
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
  const messageRows = messagesResult.data ?? [];
  const userMessageIds = messageRows.filter((row) => row.role === "user").map((row) => row.id);
  const skillByUserMessageId = new Map<string, SkillId>();
  if (userMessageIds.length) {
    const { data: runs, error: runsError } = await supabase
      .from("agent_demo_runs")
      .select("user_message_id,skill_id")
      .eq("owner_id", ownerId)
      .in("user_message_id", userMessageIds);
    if (runsError) throw runsError;
    for (const run of runs ?? []) {
      const skillId = persistedSkillId(run.skill_id);
      if (skillId) skillByUserMessageId.set(run.user_message_id, skillId);
    }
  }
  const messages = messageRows.map((row) => message(row, skillByUserMessageId.get(row.id) ?? null));
  const firstUserMessage = messages.find((row) => row.role === "user")?.content;
  let resolvedThread = thread(threadResult.data);
  const title = automaticThreadTitleUpdate(threadResult.data.title, firstUserMessage);
  if (title) {
    try {
      const { data: persisted, error: persistError } = await supabase
        .from("research_threads")
        .update({ title })
        .eq("owner_id", ownerId)
        .eq("id", threadId)
        .eq("title", DEFAULT_THREAD_TITLE)
        .select(threadFields)
        .maybeSingle();
      if (!persistError && persisted) resolvedThread = thread(persisted);
    } catch {
      resolvedThread = { ...resolvedThread, title };
    }
  }
  return {
    ...resolvedThread,
    messages,
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

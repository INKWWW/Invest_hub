"use client";

import { FormEvent, useEffect, useMemo, useState } from "react";

import { SafeMarkdown } from "./SafeMarkdown";
import { SKILL_DEFINITIONS, parseSkillCommand, type SkillId } from "../../lib/agent-demo/skill-routing";
import type {
  ResearchMessage,
  ResearchThread,
  ResearchThreadDetail,
} from "../../lib/db/repositories/research-threads";

type ThreadSummary = Pick<ResearchThread, "id" | "title" | "createdAt" | "updatedAt">;
type AgentThreadDetail = Omit<ResearchThreadDetail, "ownerId" | "messages" | "artifacts"> & {
  messages: Array<Pick<ResearchMessage, "id" | "role" | "content" | "skillId" | "createdAt">>;
  artifacts: Array<Pick<ResearchThreadDetail["artifacts"][number], "id" | "artifactType" | "metadata" | "createdAt">>;
};
type ApiThread = { id: string; title: string; created_at: string; updated_at: string };
type ApiThreadDetail = ApiThread & {
  messages: Array<{ id: string; role: "user" | "assistant"; content: string; skill_id: SkillId | null; created_at: string }>;
  artifacts: Array<{ id: string; artifact_type: string; metadata: AgentThreadDetail["artifacts"][number]["metadata"]; created_at: string }>;
};
type ApiDemoRun = {
  id: string;
  status: "queued" | "running" | "succeeded" | "failed";
  thread_id: string;
  assistant_message_id: string | null;
  invocation_mode?: "explicit" | "auto";
  skill_id?: SkillId | null;
  created_at?: string;
  started_at?: string | null;
  completed_at?: string | null;
};

export function mapThread(thread: ApiThread): ThreadSummary {
  return { id: thread.id, title: thread.title, createdAt: thread.created_at, updatedAt: thread.updated_at };
}

export function mapThreadDetail(thread: ApiThreadDetail): AgentThreadDetail {
  return {
    id: thread.id,
    title: thread.title,
    createdAt: thread.created_at,
    updatedAt: thread.updated_at,
    messages: thread.messages.map((message) => ({
      id: message.id,
      role: message.role,
      content: message.content,
      skillId: message.skill_id,
      createdAt: message.created_at,
    })),
    artifacts: thread.artifacts.map((artifact) => ({
      id: artifact.id,
      artifactType: artifact.artifact_type,
      metadata: artifact.metadata,
      createdAt: artifact.created_at,
    })),
  };
}

function dateKey(value: string): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Shanghai",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(value));
}

function dateLabel(key: string): string {
  const today = dateKey(new Date().toISOString());
  const yesterday = dateKey(new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString());
  if (key === today) return "今天";
  if (key === yesterday) return "昨天";
  return key;
}

function groupThreads(threads: ThreadSummary[]): Array<[string, ThreadSummary[]]> {
  const groups = new Map<string, ThreadSummary[]>();
  for (const thread of threads) {
    const key = dateKey(thread.updatedAt);
    groups.set(key, [...(groups.get(key) ?? []), thread]);
  }
  return [...groups.entries()].sort(([left], [right]) => right.localeCompare(left));
}

function newestFirst(threads: ThreadSummary[]): ThreadSummary[] {
  return [...threads].sort((left, right) => right.updatedAt.localeCompare(left.updatedAt) || right.id.localeCompare(left.id));
}

function messageClass(message: Pick<ResearchMessage, "role">): string {
  return message.role === "user" ? "agent-message agent-message-user" : "agent-message agent-message-assistant";
}

function messageTime(value: string): string {
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  }).format(new Date(value));
}

function skillButtonLabel(skillId: SkillId | null | undefined): string | null {
  if (!skillId) return null;
  return SKILL_DEFINITIONS.find((skill) => skill.id === skillId)?.buttonLabel ?? null;
}

function runStatusCopy(status: ApiDemoRun["status"]): { title: string; detail: string } {
  if (status === "queued") return { title: "已排队", detail: "Agent 正在等待执行，预计 1–4 分钟返回结果。" };
  if (status === "running") return { title: "研究中", detail: "Agent 正在调用 Skill 并生成回答，预计还需 1–3 分钟。" };
  if (status === "succeeded") return { title: "已完成", detail: "回答已写回当前研究会话。" };
  return { title: "执行失败", detail: "本次研究没有完成，请保留原问题后重试。" };
}

async function readJson<T>(response: Response): Promise<T> {
  const payload = await response.json() as T & { error?: string };
  if (!response.ok) throw new Error(payload.error ?? "agent_request_failed");
  return payload;
}

export function ResearchAgentShell({ initialThreads }: { initialThreads: ThreadSummary[] }) {
  const [threads, setThreads] = useState(initialThreads);
  const [activeThreadId, setActiveThreadId] = useState<string | null>(initialThreads[0]?.id ?? null);
  const [detail, setDetail] = useState<AgentThreadDetail | null>(null);
  const [draft, setDraft] = useState("");
  const [renameId, setRenameId] = useState<string | null>(null);
  const [renameDraft, setRenameDraft] = useState("");
  const [deleteId, setDeleteId] = useState<string | null>(null);
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [activeRunId, setActiveRunId] = useState<string | null>(null);
  const [activeRun, setActiveRun] = useState<ApiDemoRun | null>(null);
  const [selectedSkill, setSelectedSkill] = useState<SkillId | null>(null);

  const activeThread = useMemo(
    () => threads.find((thread) => thread.id === activeThreadId) ?? null,
    [activeThreadId, threads],
  );

  useEffect(() => {
    if (!activeThreadId) {
      setDetail(null);
      return;
    }
    let cancelled = false;
    setError(null);
    void fetch(`/api/agent/threads/${activeThreadId}`)
      .then((response) => readJson<{ thread: ApiThreadDetail }>(response))
      .then(({ thread }) => { if (!cancelled) setDetail(mapThreadDetail(thread)); })
      .catch(() => { if (!cancelled) setError("会话读取失败，请刷新重试。"); });
    return () => { cancelled = true; };
  }, [activeThreadId]);

  useEffect(() => {
    if (!activeRunId) return;
    let cancelled = false;
    const timer = window.setInterval(() => {
      void fetch(`/api/agent/runs/${activeRunId}`, { cache: "no-store" })
        .then((response) => readJson<{ run: ApiDemoRun }>(response))
        .then(({ run }) => {
          if (cancelled) return;
          setActiveRun(run);
          if (run.status !== "succeeded" && run.status !== "failed") return;
          window.clearInterval(timer);
          setActiveRunId(null);
          if (run.status === "failed") {
            setActiveRun(null);
            setError("Agent 执行失败，请重新发送。请保留原问题后重试。");
            return;
          }
          setActiveRun(null);
          return fetch(`/api/agent/threads/${run.thread_id}`)
            .then((response) => readJson<{ thread: ApiThreadDetail }>(response))
            .then(({ thread }) => { if (!cancelled) setDetail(mapThreadDetail(thread)); });
        })
        .catch(() => undefined);
    }, 800);
    return () => { cancelled = true; window.clearInterval(timer); };
  }, [activeRunId]);

  function openThread(threadId: string) {
    setActiveThreadId(threadId);
    setDrawerOpen(false);
    setDeleteId(null);
    setRenameId(null);
    setSelectedSkill(null);
    setActiveRun(null);
    setActiveRunId(null);
  }

  async function createThread() {
    setBusy(true);
    setError(null);
    try {
      const result = await readJson<{ thread: ApiThread }>(await fetch("/api/agent/threads", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" }));
      const thread = mapThread(result.thread);
      setThreads((current) => [thread, ...current]);
      setActiveThreadId(thread.id);
      setDetail({ ...thread, messages: [], artifacts: [] });
      setDrawerOpen(false);
      setSelectedSkill(null);
      setActiveRun(null);
      setActiveRunId(null);
    } catch {
      setError("新建会话失败，请重试。");
    } finally {
      setBusy(false);
    }
  }

  async function submitMessage(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const content = draft.trim();
    if (!content || busy) return;
    setBusy(true);
    setError(null);
    const parsed = parseSkillCommand(content);
    const skillId = selectedSkill ?? parsed.skillId;
    try {
      let threadId = activeThreadId;
      if (!threadId) {
        const result = await readJson<{ thread: ApiThread }>(await fetch("/api/agent/threads", { method: "POST", headers: { "content-type": "application/json" }, body: "{}" }));
        const thread = mapThread(result.thread);
        threadId = thread.id;
        setThreads((current) => [thread, ...current]);
        setActiveThreadId(threadId);
      }
      const accepted = await readJson<{ run: ApiDemoRun }>(await fetch(`/api/agent/threads/${threadId}/messages`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ content, request_id: crypto.randomUUID(), ...(skillId ? { invocation_mode: "explicit", skill_id: skillId } : {}) }),
      }));
      setDraft("");
      setSelectedSkill(null);
      setActiveRunId(accepted.run.id);
      setActiveRun({ ...accepted.run, created_at: accepted.run.created_at ?? new Date().toISOString() });
      const refreshed = await readJson<{ thread: ApiThreadDetail }>(await fetch(`/api/agent/threads/${threadId}`));
      const refreshedThread = mapThreadDetail(refreshed.thread);
      setDetail(refreshedThread);
      setThreads((current) => newestFirst(current.map((thread) => thread.id === threadId ? {
        ...thread,
        title: refreshedThread.title,
        updatedAt: refreshedThread.updatedAt,
      } : thread)));
    } catch (error) {
      if (error instanceof Error && error.message === "demo_runner_busy") setError("Agent 正忙，请稍后重试");
      else if (error instanceof Error && error.message === "demo_runner_unavailable") setError("Agent 暂时不可用");
      else setError("消息保存失败，请重试。");
    } finally {
      setBusy(false);
    }
  }

  async function renameThread(event: FormEvent<HTMLFormElement>, threadId: string) {
    event.preventDefault();
    const title = renameDraft.trim();
    if (!title || busy) return;
    setBusy(true);
    setError(null);
    try {
      const result = await readJson<{ thread: ApiThread }>(await fetch(`/api/agent/threads/${threadId}`, {
        method: "PATCH", headers: { "content-type": "application/json" }, body: JSON.stringify({ title }),
      }));
      const renamedThread = mapThread(result.thread);
      setThreads((current) => newestFirst(current.map((thread) => thread.id === threadId ? renamedThread : thread)));
      setDetail((current) => current && current.id === threadId ? { ...current, ...renamedThread } : current);
      setRenameId(null);
    } catch {
      setError("重命名失败，请重试。");
    } finally {
      setBusy(false);
    }
  }

  async function deleteThread(threadId: string) {
    setBusy(true);
    setError(null);
    try {
      await readJson(await fetch(`/api/agent/threads/${threadId}`, {
        method: "DELETE", headers: { "content-type": "application/json" }, body: JSON.stringify({ confirm: true }),
      }));
      const remaining = threads.filter((thread) => thread.id !== threadId);
      setThreads(remaining);
      setDeleteId(null);
      setDetail(null);
      if (activeThreadId === threadId) setActiveThreadId(remaining[0]?.id ?? null);
    } catch {
      setError("删除失败，会话仍然保留。");
    } finally {
      setBusy(false);
    }
  }

  const groupedThreads = groupThreads(threads);
  const selectedSkillDefinition = selectedSkill
    ? SKILL_DEFINITIONS.find((skill) => skill.id === selectedSkill)
    : null;

  return <section className="agent-workbench" data-testid="agent-workbench">
    <button className="agent-drawer-trigger" type="button" aria-label="打开研究会话列表" onClick={() => setDrawerOpen(true)}>会话列表</button>
    {drawerOpen ? <button className="agent-drawer-backdrop" type="button" aria-label="关闭研究会话列表" onClick={() => setDrawerOpen(false)} /> : null}
    <aside className={`agent-thread-sidebar${drawerOpen ? " agent-thread-sidebar-open" : ""}`} aria-label="研究会话列表">
      <div className="agent-sidebar-heading">
        <div><p className="agent-kicker">Research Thread</p><h2>研究会话</h2></div>
        <button type="button" onClick={() => void createThread()} disabled={busy}>新建</button>
      </div>
      <div className="agent-thread-groups">
        {groupedThreads.length > 0 ? groupedThreads.map(([key, grouped]) => <section key={key} className="agent-thread-group" data-testid="thread-group">
          <h3>{dateLabel(key)}</h3>
          <div className="agent-thread-list">
            {grouped.map((thread) => <div className="agent-thread-item" key={thread.id}>
              <button type="button" className={`agent-thread-link${thread.id === activeThreadId ? " agent-thread-link-active" : ""}`} onClick={() => openThread(thread.id)}>
                <span>{thread.title}</span><time dateTime={thread.updatedAt}>{dateLabel(dateKey(thread.updatedAt))}</time>
              </button>
              {thread.id === activeThreadId ? <div className="agent-thread-actions">
                <button type="button" onClick={() => { setRenameId(thread.id); setRenameDraft(thread.title); }}>重命名</button>
                <button type="button" onClick={() => setDeleteId(thread.id)}>删除</button>
              </div> : null}
              {renameId === thread.id ? <form className="agent-inline-form" onSubmit={(event) => void renameThread(event, thread.id)}>
                <label><span className="sr-only">新的会话标题</span><input value={renameDraft} maxLength={80} onChange={(event) => setRenameDraft(event.target.value)} /></label>
                <button type="submit" disabled={busy}>保存</button>
              </form> : null}
              {deleteId === thread.id ? <div className="agent-delete-confirm" role="alertdialog" aria-label="确认删除研究会话">
                <p>删除会移除本会话消息与 Thread Artifact。独立的“我的记忆”需要另行管理。</p>
                <div><button type="button" onClick={() => void deleteThread(thread.id)} disabled={busy}>确认删除</button><button type="button" onClick={() => setDeleteId(null)}>取消</button></div>
              </div> : null}
            </div>)}
          </div>
        </section>) : <p className="agent-empty">还没有研究会话。新建一个空白会话，或直接在右侧开始输入。</p>}
      </div>
    </aside>
    <section className="agent-conversation" aria-label="研究对话">
      <header className="agent-conversation-header">
        <p className="agent-kicker">Private workspace</p>
        <h2>{activeThread?.title ?? "新的研究会话"}</h2>
      </header>
      <div className="agent-message-list" data-testid="agent-message-list" aria-live="polite">
        {detail?.messages.length ? detail.messages.map((message) => <article className={messageClass(message)} key={message.id}>
          <p className="agent-message-role">{message.role === "user" ? "你" : "Agent"}</p>{message.role === "user" && message.skillId ? <p className="agent-message-skill">已调用 Skill <strong>/{skillButtonLabel(message.skillId)}</strong></p> : null}{message.role === "assistant" ? <SafeMarkdown content={message.content} /> : <p>{message.content}</p>}<time dateTime={message.createdAt}>{messageTime(message.createdAt)}</time>
        </article>) : <div className="agent-conversation-empty"><p>把一个投资问题留在这里，作为你的研究起点。</p></div>}
      </div>
      {error ? <p className="agent-error" role="alert">{error}</p> : null}
      {activeRun && (activeRun.status === "queued" || activeRun.status === "running") ? <div className={`agent-run-status agent-run-status-${activeRun.status}`} role="status" aria-live="polite" aria-busy="true">
        <div className="agent-run-status-top"><strong>{runStatusCopy(activeRun.status).title}</strong><span>{activeRun.started_at ? `开始于 ${messageTime(activeRun.started_at)}` : "刚刚提交"}</span></div>
        <p>{runStatusCopy(activeRun.status).detail}</p>
      </div> : null}
      <form className="agent-composer" data-testid="agent-composer" onSubmit={(event) => void submitMessage(event)}>
        <div className="agent-skill-picker" aria-label="本条消息的 Skill 选择">
          <button type="button" aria-pressed={selectedSkill === null} onClick={() => setSelectedSkill(null)}>智能</button>
          {SKILL_DEFINITIONS.map((skill) => <button key={skill.id} type="button" aria-pressed={selectedSkill === skill.id} onClick={() => setSelectedSkill(skill.id)}>{skill.buttonLabel}</button>)}
        </div>
        <div className="agent-composer-editor">
          {selectedSkillDefinition ? <span className="agent-skill-token" aria-label={`已选择 ${selectedSkillDefinition.buttonLabel}`}>/{selectedSkillDefinition.buttonLabel}</span> : null}
          <textarea id="agent-message-input" aria-label="记录你的投资研究问题" value={draft} onChange={(event) => setDraft(event.target.value)} placeholder="记录你的投资研究问题……" maxLength={20000} rows={4} />
        </div>
        <div className="agent-composer-footer"><button type="submit" disabled={busy || !draft.trim()}>{busy ? "提交中…" : "点击发送（回车仅换行）"}</button></div>
      </form>
    </section>
  </section>;
}

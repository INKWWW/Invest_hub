"use client";

import { useEffect, useMemo, useState } from "react";

type ObservedAuthor = { author_id: string; author_display: string; author_handle: string | null };
type AuthorProfile = ObservedAuthor & { enabled: boolean };

export function authorOptionLabel(author: ObservedAuthor): string {
  return author.author_handle ? `${author.author_display} @${author.author_handle}` : author.author_display;
}

export function profileStatusLabel(enabled: boolean): string {
  return enabled ? "已启用" : "已停用";
}

export function SourceAuthorProfilesForm({ sourceId }: { sourceId: string }) {
  const [observed, setObserved] = useState<ObservedAuthor[]>([]);
  const [profiles, setProfiles] = useState<AuthorProfile[]>([]);
  const [selectedAuthorId, setSelectedAuthorId] = useState("");
  const [pendingAuthorId, setPendingAuthorId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    setMessage(null);
    const [authorsResponse, profilesResponse] = await Promise.all([
      fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/observed-authors`),
      fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`),
    ]);
    if (!authorsResponse.ok || !profilesResponse.ok) {
      setMessage("无法读取已观察到的作者，请检查管理员权限后重试。");
      return;
    }
    const authorsBody = await authorsResponse.json() as { authors?: ObservedAuthor[] };
    const profilesBody = await profilesResponse.json() as { author_profiles?: AuthorProfile[] };
    const nextObserved = Array.isArray(authorsBody.authors) ? authorsBody.authors : [];
    setObserved(nextObserved);
    setProfiles(Array.isArray(profilesBody.author_profiles) ? profilesBody.author_profiles : []);
    setSelectedAuthorId((current) => current || nextObserved[0]?.author_id || "");
  }

  useEffect(() => { void load(); }, [sourceId]);

  const observedById = useMemo(() => new Map(observed.map((author) => [author.author_id, author])), [observed]);

  async function save(authorId: string, enabled: boolean, method: "POST" | "PATCH") {
    setPendingAuthorId(authorId);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`, {
        method,
        headers: { "content-type": "application/json" },
        body: JSON.stringify(method === "POST" ? { author_id: authorId } : { author_id: authorId, enabled }),
      });
      if (!response.ok) {
        setMessage("作者配置未保存；该作者必须来自已观察到的稳定身份。");
        return;
      }
      await load();
      setMessage(enabled ? "作者已启用；仅影响后续任务。" : "作者已停用；仅影响后续任务。");
    } finally {
      setPendingAuthorId(null);
    }
  }

  async function remove(authorId: string) {
    setPendingAuthorId(authorId);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`, {
        method: "DELETE", headers: { "content-type": "application/json" }, body: JSON.stringify({ author_id: authorId }),
      });
      if (!response.ok) {
        setMessage("作者配置未删除，请稍后重试。");
        return;
      }
      await load();
      setMessage("作者配置已删除；仅影响后续任务。");
    } finally {
      setPendingAuthorId(null);
    }
  }

  return <section className="author-profiles-form" aria-label="作者配置">
    <h3>作者配置</h3>
    <p>从本来源已观察到的稳定作者身份中选择。配置仅影响后续任务。</p>
    <label>已观察到的作者
      <select value={selectedAuthorId} onChange={(event) => setSelectedAuthorId(event.target.value)} disabled={pendingAuthorId !== null || observed.length === 0}>
        {observed.length > 0 ? observed.map((author) => <option key={author.author_id} value={author.author_id}>{authorOptionLabel(author)}</option>) : <option value="">暂无已观察到的作者</option>}
      </select>
    </label>
    <button type="button" disabled={!selectedAuthorId || pendingAuthorId !== null} onClick={() => void save(selectedAuthorId, true, "POST")}>添加并启用</button>
    {profiles.length > 0 ? <ul className="author-profile-list">{profiles.map((profile) => <li key={profile.author_id}>
      <span><strong>{authorOptionLabel(observedById.get(profile.author_id) ?? profile)}</strong> · {profileStatusLabel(profile.enabled)}</span>
      <span className="author-profile-actions">
        <button type="button" disabled={pendingAuthorId !== null} onClick={() => void save(profile.author_id, !profile.enabled, "PATCH")}>{profile.enabled ? "停用" : "启用"}</button>
        <button type="button" disabled={pendingAuthorId !== null} onClick={() => void remove(profile.author_id)}>删除</button>
      </span>
    </li>)}</ul> : <p>尚未配置作者。</p>}
    {message ? <p role="status">{message}</p> : null}
  </section>;
}

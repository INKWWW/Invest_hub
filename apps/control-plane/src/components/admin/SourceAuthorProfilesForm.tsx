"use client";

import { useEffect, useState } from "react";

type ObservedAuthor = { author_id: string; author_display: string; author_handle: string | null };
type ResolutionStatus = "pending" | "resolved" | "ambiguous";
type AuthorProfile = {
  id: string;
  requested_author: string;
  resolution_status: ResolutionStatus;
  author_id: string | null;
  author_display: string;
  author_handle: string | null;
  enabled: boolean;
};

export function authorOptionLabel(author: Pick<ObservedAuthor, "author_display" | "author_handle">): string {
  return author.author_handle ? `${author.author_display} @${author.author_handle}` : author.author_display;
}

export function profileStatusLabel(enabled: boolean): string {
  return enabled ? "已启用" : "已停用";
}

export function resolutionStatusLabel(status: ResolutionStatus): string {
  if (status === "pending") return "等待匹配";
  if (status === "resolved") return "已匹配";
  return "匹配不唯一";
}

export function SourceAuthorProfilesForm({ sourceId }: { sourceId: string }) {
  const [observed, setObserved] = useState<ObservedAuthor[]>([]);
  const [profiles, setProfiles] = useState<AuthorProfile[]>([]);
  const [requestedAuthor, setRequestedAuthor] = useState("");
  const [pendingProfileId, setPendingProfileId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const suggestionListId = `observed-authors-${sourceId.replace(/[^a-zA-Z0-9_-]/g, "-")}`;

  async function load() {
    setMessage(null);
    const [authorsResponse, profilesResponse] = await Promise.all([
      fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/observed-authors`),
      fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`),
    ]);
    if (!authorsResponse.ok || !profilesResponse.ok) {
      setMessage("无法读取作者配置，请检查管理员权限后重试。");
      return;
    }
    const authorsBody = await authorsResponse.json() as { authors?: ObservedAuthor[] };
    const profilesBody = await profilesResponse.json() as { author_profiles?: AuthorProfile[] };
    setObserved(Array.isArray(authorsBody.authors) ? authorsBody.authors : []);
    setProfiles(Array.isArray(profilesBody.author_profiles) ? profilesBody.author_profiles : []);
  }

  useEffect(() => { void load(); }, [sourceId]);

  async function addProfile() {
    const selector = requestedAuthor.trim();
    if (!selector) {
      setMessage("请输入指定作者的显示名或用户名。");
      return;
    }
    setPendingProfileId("new");
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ requested_author: selector }),
      });
      if (!response.ok) {
        setMessage("作者配置未保存；请检查是否已配置了相同作者。");
        return;
      }
      setRequestedAuthor("");
      await load();
      setMessage("作者已保存；将在下一次采集后确认稳定身份，仅影响后续任务。");
    } finally {
      setPendingProfileId(null);
    }
  }

  async function setEnabled(profile: AuthorProfile, enabled: boolean) {
    setPendingProfileId(profile.id);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`, {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ profile_id: profile.id, enabled }),
      });
      if (!response.ok) {
        setMessage("作者配置未保存，请稍后重试。");
        return;
      }
      await load();
      setMessage(enabled ? "作者已启用；仅影响后续任务。" : "作者已停用；仅影响后续任务。");
    } finally {
      setPendingProfileId(null);
    }
  }

  async function remove(profile: AuthorProfile) {
    setPendingProfileId(profile.id);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/sources/${encodeURIComponent(sourceId)}/author-profiles`, {
        method: "DELETE", headers: { "content-type": "application/json" }, body: JSON.stringify({ profile_id: profile.id }),
      });
      if (!response.ok) {
        setMessage("作者配置未删除，请稍后重试。");
        return;
      }
      await load();
      setMessage("作者配置已删除；仅影响后续任务。");
    } finally {
      setPendingProfileId(null);
    }
  }

  return <section className="author-profiles-form" aria-label="作者配置">
    <h3>作者配置</h3>
    <p>输入指定作者的显示名或用户名。已观察到的作者仅作为输入提示，不构成可配置约束；配置仅影响后续任务。</p>
    <label>指定作者
      <input
        aria-label="指定作者"
        list={suggestionListId}
        value={requestedAuthor}
        onChange={(event) => setRequestedAuthor(event.target.value)}
        disabled={pendingProfileId !== null}
        placeholder="显示名或用户名"
      />
    </label>
    <datalist id={suggestionListId}>{observed.map((author) => <option key={author.author_id} value={author.author_display} label={authorOptionLabel(author)} />)}</datalist>
    <p className="author-profile-suggestions">已观察到的作者（仅作为输入提示）：{observed.length > 0 ? observed.map(authorOptionLabel).join("、") : "暂无"}</p>
    <button type="button" disabled={!requestedAuthor.trim() || pendingProfileId !== null} onClick={() => void addProfile()}>添加并启用</button>
    {profiles.length > 0 ? <ul className="author-profile-list">{profiles.map((profile) => <li key={profile.id}>
      <span><strong>{authorOptionLabel(profile)}</strong> · {resolutionStatusLabel(profile.resolution_status)} · {profileStatusLabel(profile.enabled)}</span>
      <span className="author-profile-actions">
        <button type="button" disabled={pendingProfileId !== null} onClick={() => void setEnabled(profile, !profile.enabled)}>{profile.enabled ? "停用" : "启用"}</button>
        <button type="button" disabled={pendingProfileId !== null} onClick={() => void remove(profile)}>删除</button>
      </span>
    </li>)}</ul> : <p>尚未配置作者。</p>}
    {message ? <p role="status">{message}</p> : null}
  </section>;
}

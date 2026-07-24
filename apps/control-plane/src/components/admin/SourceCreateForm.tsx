"use client";

import { useState } from "react";

export function discordCreationPayload(displayName: string) {
  return { display_name: displayName.trim() };
}

export function SourceCreateForm() {
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(formData: FormData) {
    setPending(true);
    setMessage(null);
    try {
      const response = await fetch("/api/admin/sources", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify(discordCreationPayload(String(formData.get("display_name") ?? ""))),
      });
      if (!response.ok) {
        setMessage("未能创建来源。请检查名称格式和管理员权限后重试。");
        return;
      }
      setMessage("Discord 来源已创建。下一步：配置采集范围。");
      window.location.reload();
    } finally {
      setPending(false);
    }
  }

  return (
    <form action={submit} className="source-create-form">
      <h2>新建 Discord 来源</h2>
      <p className="source-creation-intro">填写你要跟踪的频道名称即可。系统会为它建立内部关联和采集配置。</p>
      <label>
        显示名称（社区名 · 频道名）
        <input name="display_name" required maxLength={128} placeholder="例如：研究社区 · #美股讨论" />
      </label>
      <p className="source-creation-preset" role="note">
        <strong>采集方案</strong>
        <span>标准采集（推荐）</span>
        <small>系统自动维护</small>
      </p>
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建 Discord 来源"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

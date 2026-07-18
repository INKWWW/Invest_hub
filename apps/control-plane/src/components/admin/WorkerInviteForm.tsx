"use client";

import { useState } from "react";

import { parseWorkerInviteResponse } from "./worker-invite";

export function WorkerInviteForm() {
  const [invite, setInvite] = useState<{ code: string; expiresAt: string } | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function createInvite() {
    setPending(true);
    setMessage(null);
    setInvite(null);
    const response = await fetch("/api/admin/invites", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ purpose: "worker", expires_in_hours: 1 }),
    });
    const parsed = response.ok ? parseWorkerInviteResponse(await response.json()) : null;
    setPending(false);
    if (!parsed) {
      setMessage("创建失败，请检查管理员会话后重试。");
      return;
    }
    setInvite(parsed);
  }

  return (
    <section>
      <h2>创建一次性 Worker 邀请码</h2>
      <p>邀请码仅在本次页面显示，1 小时后失效。请复制到本地 owner-only 文件；不要提交到 Git 或发送到聊天记录。</p>
      <button type="button" onClick={createInvite} disabled={pending}>{pending ? "创建中…" : "创建 1 小时邀请码"}</button>
      {message ? <p role="status">{message}</p> : null}
      {invite ? (
        <div>
          <p role="status">邀请码已创建，过期时间：{new Date(invite.expiresAt).toLocaleString()}。</p>
          <label>一次性邀请码 <input readOnly value={invite.code} aria-label="一次性 Worker 邀请码" /></label>
        </div>
      ) : null}
    </section>
  );
}

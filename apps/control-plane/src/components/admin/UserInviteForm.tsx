"use client";

import { useState } from "react";

import { parseUserInviteResponse } from "./user-invite";

export function UserInviteForm() {
  const [invite, setInvite] = useState<{ code: string; expiresAt: string } | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function createInvite() {
    setPending(true);
    setMessage(null);
    setInvite(null);
    try {
      const response = await fetch("/api/admin/invites", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ purpose: "user", expires_in_hours: 24 }),
      });
      const parsed = response.ok ? parseUserInviteResponse(await response.json()) : null;
      if (!parsed) {
        setMessage("创建失败，请检查管理员会话后重试。");
        return;
      }
      setInvite(parsed);
    } catch {
      setMessage("创建失败，请检查网络后重试。");
    } finally {
      setPending(false);
    }
  }

  return (
    <section>
      <h2>创建一次性普通用户邀请码</h2>
      <p>邀请码仅在本次页面显示，24 小时后失效。请通过受信任渠道交给受邀者；不要提交到 Git、日志或证据文件。</p>
      <button type="button" onClick={createInvite} disabled={pending}>{pending ? "创建中…" : "创建 24 小时邀请码"}</button>
      {message ? <p role="status">{message}</p> : null}
      {invite ? (
        <div>
          <p role="status">邀请码已创建，过期时间：{new Date(invite.expiresAt).toLocaleString()}。</p>
          <label>一次性邀请码 <input readOnly value={invite.code} aria-label="一次性普通用户邀请码" /></label>
        </div>
      ) : null}
    </section>
  );
}

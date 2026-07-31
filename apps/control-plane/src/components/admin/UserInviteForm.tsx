"use client";

import { useEffect, useState } from "react";

import { isValidInviteHours, parseUserInviteListResponse, parseUserInviteResponse, type UserInviteListItem } from "./user-invite";
import { UserInviteList } from "./UserInviteList";

export function UserInviteForm() {
  const [hoursInput, setHoursInput] = useState("24");
  const [invite, setInvite] = useState<{ code: string; expiresAt: string } | null>(null);
  const [invites, setInvites] = useState<UserInviteListItem[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [listMessage, setListMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function refreshInvites() {
    try {
      const response = await fetch("/api/admin/invites", { method: "GET" });
      const parsed = response.ok ? parseUserInviteListResponse(await response.json()) : null;
      if (!parsed) {
        setListMessage("邀请码列表暂时无法加载，请稍后重试。");
        return;
      }
      setListMessage(null);
      setInvites(parsed);
    } catch {
      setListMessage("邀请码列表暂时无法加载，请稍后重试。");
    }
  }

  useEffect(() => {
    void refreshInvites();
  }, []);

  async function createInvite() {
    const hours = Number(hoursInput);
    if (!isValidInviteHours(hours)) {
      setMessage("有效时长必须是 1 到 168 之间的整数小时。");
      return;
    }
    setPending(true);
    setMessage(null);
    setInvite(null);
    try {
      const response = await fetch("/api/admin/invites", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ purpose: "user", expires_in_hours: hours }),
      });
      const parsed = response.ok ? parseUserInviteResponse(await response.json()) : null;
      if (!parsed) {
        setMessage("创建失败，请检查管理员会话后重试。");
        return;
      }
      setInvite(parsed);
      await refreshInvites();
    } catch {
      setMessage("创建失败，请检查网络后重试。");
    } finally {
      setPending(false);
    }
  }

  const hours = Number(hoursInput);
  const validHours = isValidInviteHours(hours);
  return (
    <section>
      <h2>创建一次性普通用户邀请码</h2>
      <p>邀请码仅在本次页面显示；请通过受信任渠道交给受邀者，不要提交到 Git、日志或证据文件。</p>
      <form onSubmit={(event) => { event.preventDefault(); void createInvite(); }}>
        <label>
          有效时长（小时）
          <input
            type="number"
            min={1}
            max={168}
            step={1}
            value={hoursInput}
            onChange={(event) => setHoursInput(event.target.value)}
            aria-describedby="user-invite-duration-help"
          />
          <small id="user-invite-duration-help">生成后立即开始计时，范围为 1–168 小时。</small>
        </label>
        <button type="submit" disabled={pending || !validHours}>
          {pending ? "创建中…" : `创建 ${validHours ? hours : ""} 小时邀请码`}
        </button>
      </form>
      {message ? <p role="status">{message}</p> : null}
      {invite ? (
        <div>
          <p role="status">邀请码已创建，过期时间：{new Date(invite.expiresAt).toLocaleString()}。</p>
          <label>一次性邀请码 <input readOnly value={invite.code} aria-label="一次性普通用户邀请码" /></label>
        </div>
      ) : null}
      {listMessage ? <p role="status">{listMessage}</p> : <UserInviteList invites={invites} />}
    </section>
  );
}

"use client";

import { useState } from "react";

import type { AppRole } from "../../lib/db/types";

export type SessionViewer = {
  email: string | null;
  role: AppRole;
};

function roleLabel(role: AppRole): string {
  return role === "admin" ? "管理员" : "普通用户";
}

export function SessionControls({ viewer }: { viewer: SessionViewer }) {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function signOut() {
    setIsSubmitting(true);
    setMessage(null);
    try {
      const response = await fetch("/api/auth/logout", { method: "POST" });
      if (!response.ok) {
        setMessage("退出失败，请重试。");
        return;
      }
      window.location.assign("/login");
    } catch {
      setMessage("退出失败，请重试。");
    } finally {
      setIsSubmitting(false);
    }
  }

  return <aside className="session-controls" data-testid="session-controls" aria-label="账户会话">
    <p className="session-identity">
      <strong>{viewer.email ?? "已登录账号"}</strong>
      <em>{roleLabel(viewer.role)}</em>
    </p>
    <button type="button" onClick={() => void signOut()} disabled={isSubmitting}>
      {isSubmitting ? "正在退出…" : "退出 / 切换账号"}
    </button>
    {message ? <p className="session-message" role="alert">{message}</p> : null}
  </aside>;
}

"use client";

import { useEffect, useState } from "react";

export type UserInviteListItem = {
  codeMask: string | null;
  validityHours: number | null;
  createdAt: string;
  expiresAt: string;
  consumedAt: string | null;
};

type ActiveInviteState = { label: "有效"; remaining: string };
type InactiveInviteState = { label: "已过期" | "已使用"; remaining: "已过期" | "已使用" };

function formatRemaining(totalSeconds: number): string {
  const seconds = Math.max(0, totalSeconds);
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  const remainder = seconds % 60;
  return [hours, minutes, remainder].map((part) => String(part).padStart(2, "0")).join(":");
}

export function inviteDisplayState(invite: UserInviteListItem, now: Date): ActiveInviteState | InactiveInviteState {
  if (invite.consumedAt) return { label: "已使用", remaining: "已使用" };
  const seconds = Math.ceil((Date.parse(invite.expiresAt) - now.getTime()) / 1000);
  if (seconds <= 0) return { label: "已过期", remaining: "已过期" };
  return { label: "有效", remaining: formatRemaining(seconds) };
}

export function UserInviteList({ invites, now: initialNow }: { invites: UserInviteListItem[]; now?: Date }) {
  const [now, setNow] = useState(initialNow ?? new Date());

  useEffect(() => {
    const timer = window.setInterval(() => setNow(new Date()), 1000);
    return () => window.clearInterval(timer);
  }, []);

  return (
    <section className="user-invite-list" aria-labelledby="user-invite-list-heading">
      <h3 id="user-invite-list-heading">最近创建的邀请码</h3>
      {invites.length === 0 ? <p>暂无邀请码记录。</p> : (
        <div className="user-invite-table-wrap">
          <table className="user-invite-table">
            <thead>
              <tr><th scope="col">邀请码</th><th scope="col">有效时长</th><th scope="col">剩余有效期</th><th scope="col">状态</th></tr>
            </thead>
            <tbody>
              {invites.map((invite) => {
                const state = inviteDisplayState(invite, now);
                return (
                  <tr key={`${invite.createdAt}-${invite.codeMask ?? "legacy"}`}>
                    <td>{invite.codeMask ?? "旧邀请码（无掩码）"}</td>
                    <td>{invite.validityHours === null ? "—" : `${invite.validityHours} 小时`}</td>
                    <td>{state.remaining}</td>
                    <td><span className="user-invite-status" data-status={state.label}>{state.label}</span></td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

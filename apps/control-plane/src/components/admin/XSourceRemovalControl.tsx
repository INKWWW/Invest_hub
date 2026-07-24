"use client";

import { useState } from "react";

export function isExactConfirmation(value: string, displayName: string) {
  return value === displayName;
}

export function XSourceRemovalControl({
  sourceId,
  displayName,
  canRemove,
}: {
  sourceId: string;
  displayName: string;
  canRemove: boolean;
}) {
  const [confirmationName, setConfirmationName] = useState("");
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function remove() {
    setPending(true);
    setMessage(null);
    try {
      const response = await fetch(`/api/admin/x/sources/${encodeURIComponent(sourceId)}`, {
        method: "DELETE",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ confirmation_name: confirmationName }),
      });
      const body = await response.json() as { removal?: { action?: string }; error?: string };
      if (!response.ok || !body.removal?.action) {
        setMessage(body.error === "source_has_active_task"
          ? "存在进行中或待恢复任务，暂不能移除。"
          : body.error === "confirmation_mismatch"
            ? "确认名称必须与博主展示名称完全一致。"
            : "移除失败，请刷新后重试。");
        return;
      }
      setMessage(body.removal.action === "deleted"
        ? "已删除空 X 来源。"
        : "已停止并归档 X 来源；历史事实仍按保留策略保存。");
      window.setTimeout(() => window.location.reload(), 1200);
    } catch {
      setMessage("移除失败，请刷新后重试。");
    } finally {
      setPending(false);
    }
  }

  if (!canRemove) return <section className="source-danger-zone" aria-labelledby="remove-x-source-heading">
    <h3 id="remove-x-source-heading">危险操作</h3>
    <p>存在进行中或待恢复任务，暂不能移除。请先按既有恢复或取消流程安全收口。</p>
  </section>;

  return <section className="source-danger-zone" aria-labelledby="remove-x-source-heading">
    <h3 id="remove-x-source-heading">危险操作</h3>
    <p>空来源会被删除；已有任务或事实的来源会停止并归档，历史内容不会被删除。</p>
    <label htmlFor={`remove-x-source-${sourceId}`}>输入 {displayName} 以确认</label>
    <input
      id={`remove-x-source-${sourceId}`}
      value={confirmationName}
      onChange={(event) => setConfirmationName(event.target.value)}
      autoComplete="off"
    />
    <button
      type="button"
      className="source-danger-action"
      disabled={!isExactConfirmation(confirmationName, displayName) || pending}
      onClick={() => void remove()}
    >{pending ? "正在移除…" : "确认移除博主"}</button>
    {message ? <p role="status">{message}</p> : null}
  </section>;
}

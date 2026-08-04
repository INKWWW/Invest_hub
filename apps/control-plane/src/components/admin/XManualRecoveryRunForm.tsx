"use client";

import { useState } from "react";

export function XManualRecoveryRunForm() {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit() {
    setPending(true); setMessage(null);
    try {
      const response = await fetch("/api/admin/x/manual-recovery", {
        method: "POST", headers: { "content-type": "application/json" }, body: "{}",
      });
      const body = await response.json().catch(() => null) as { run?: { idempotent?: boolean }; error?: string } | null;
      setMessage(response.ok
        ? body?.run?.idempotent ? "已有相同范围的恢复正在进行。" : "已排队；本机 Worker 完成补采后会生成新的 X 总结。"
        : "暂时无法创建恢复任务，请稍后重试。");
    } finally { setPending(false); }
  }

  return <section className="x-manual-recovery" aria-label="X 手动恢复">
    <h2>X 恢复</h2>
    <p>补齐全部当前启用博主至最近完整窗口，并在完成后生成新的 X 总结。</p>
    <button type="button" onClick={submit} disabled={pending}>{pending ? "正在排队…" : "补采并重新生成 X 总结"}</button>
    {message ? <p role="status">{message}</p> : null}
  </section>;
}

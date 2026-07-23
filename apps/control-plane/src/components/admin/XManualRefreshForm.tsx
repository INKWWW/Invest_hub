"use client";

import { useState } from "react";

export function XManualRefreshForm({ sourceId }: { sourceId: string }) {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  async function submit() {
    setPending(true); setMessage(null);
    try {
      const response = await fetch("/api/admin/x/manual-refresh", {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ source_id: sourceId }),
      });
      setMessage(response.ok ? "手动更新已排队；若已有活动连续范围，会安全复用该范围。" : "无法创建手动更新：请先完成身份验证和覆盖水位初始化。 ");
    } finally { setPending(false); }
  }
  return <form className="source-manual-refresh-form" action={submit}>
    <h3>X 手动更新</h3>
    <p>服务器固定本次结束时刻，不会把浏览器当前时间当作已完成覆盖。</p>
    <button type="submit" disabled={pending}>{pending ? "排队中…" : "立即更新"}</button>
    {message ? <p role="status">{message}</p> : null}
  </form>;
}

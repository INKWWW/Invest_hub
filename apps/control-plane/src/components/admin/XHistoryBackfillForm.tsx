"use client";

import { useState } from "react";

export function XHistoryBackfillForm({ sourceId }: { sourceId: string }) {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  async function submit(formData: FormData) {
    setPending(true); setMessage(null);
    try {
      const response = await fetch("/api/admin/x/history", {
        method: "POST", headers: { "content-type": "application/json" },
        body: JSON.stringify({ source_id: sourceId, start_at: formData.get("start_at"), end_at: formData.get("end_at") }),
      });
      setMessage(response.ok ? "有界历史任务已排队；只有与当前连续水位恰好相接的成功范围才会前移水位。" : "创建失败：请输入已经过去的有效范围，且不能和该博主的活动任务重叠。 ");
    } finally { setPending(false); }
  }
  return <form className="source-history-form" action={submit}>
    <h3>X 有界历史回填</h3>
    <p>仅采集这个明确的上海时区范围；非连续结果会保留为可追溯回填，不改变实时覆盖水位。</p>
    <label>开始 <input name="start_at" type="text" required placeholder="2026-07-20T00:00:00+08:00" /></label>
    <label>结束 <input name="end_at" type="text" required placeholder="2026-07-20T08:00:00+08:00" /></label>
    <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建历史回填"}</button>
    {message ? <p role="status">{message}</p> : null}
  </form>;
}

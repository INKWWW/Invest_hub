"use client";

import { useState } from "react";

export function XCoverageForm({ sourceId }: { sourceId: string }) {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  async function submit(formData: FormData) {
    setPending(true); setMessage(null);
    try {
      const response = await fetch(`/api/admin/x/sources/${encodeURIComponent(sourceId)}/coverage`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ coverage_start_at: formData.get("coverage_start_at") }) });
      setMessage(response.ok ? "覆盖水位已初始化。" : "初始化失败：必须使用上海时间 00:00、08:00、12:00、16:00 或 20:00。 ");
    } finally { setPending(false); }
  }
  return <form className="source-coverage-form" action={submit}>
    <h3>X 覆盖水位</h3><p>首次启用从当日固定截止点开始，不默认补采更早历史。</p>
    <label>上海时间边界 <input name="coverage_start_at" type="text" required placeholder="2026-07-23T08:00:00+08:00" /></label>
    <button type="submit" disabled={pending}>{pending ? "初始化中…" : "初始化"}</button>
    {message ? <p role="status">{message}</p> : null}
  </form>;
}

"use client";

import { useState } from "react";

type Source = { id: string; display_name: string; parameter_version: string; enabled: boolean };

export function TaskCreateForm({ sources }: { sources: Source[] }) {
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const [mode, setMode] = useState<"incremental" | "history">("incremental");

  async function submit(formData: FormData) {
    setPending(true);
    setMessage(null);
    const maxPages = mode === "incremental" ? 5 : Number(formData.get("max_pages"));
    if (!Number.isInteger(maxPages) || maxPages < 1 || maxPages > 25) {
      setMessage("history 补采必须显式选择 1–25 页。");
      return;
    }
    const response = await fetch("/api/admin/tasks", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_id: formData.get("source_id"),
        parameter_version: formData.get("parameter_version"),
        scope: { mode, max_pages: maxPages },
      }),
    });
    setPending(false);
    if (!response.ok) {
      setMessage("创建失败，请检查管理员权限、来源状态和参数版本。");
      return;
    }
    setMessage("同步任务已入队，等待已授权的本地 Worker 领取。");
    window.location.reload();
  }

  if (sources.length === 0) return <p>请先创建一个启用的逻辑来源。</p>;
  return (
    <form action={submit}>
      <h2>新建同步任务</h2>
      <label>来源 <select name="source_id" required>{sources.map((source) => <option key={source.id} value={source.id}>{source.display_name}</option>)}</select></label>{" "}
      <label>参数版本 <input name="parameter_version" required defaultValue={sources[0]?.parameter_version} maxLength={128} /></label>{" "}
      <label>任务类型 <select value={mode} onChange={(event) => setMode(event.target.value as "incremental" | "history")}><option value="incremental">常规增量（固定 5 页）</option><option value="history">有界 history 补采</option></select></label>{" "}
      {mode === "history" ? <label>history 页数 <input name="max_pages" type="number" min={1} max={25} required /></label> : <p>常规增量任务固定最多 5 页。</p>}
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建同步任务"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

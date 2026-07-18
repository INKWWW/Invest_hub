"use client";

import { useState } from "react";

type Source = { id: string; source_key: string; display_name: string; parameter_version: string; enabled: boolean };

export function TaskCreateForm({ sources }: { sources: Source[] }) {
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(formData: FormData) {
    setPending(true);
    setMessage(null);
    const response = await fetch("/api/admin/tasks", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_id: formData.get("source_id"),
        parameter_version: formData.get("parameter_version"),
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
      <label>来源 <select name="source_id" required>{sources.map((source) => <option key={source.id} value={source.id}>{source.display_name}（{source.source_key}）</option>)}</select></label>{" "}
      <label>参数版本 <input name="parameter_version" required defaultValue={sources[0]?.parameter_version} maxLength={128} /></label>{" "}
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建同步任务"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

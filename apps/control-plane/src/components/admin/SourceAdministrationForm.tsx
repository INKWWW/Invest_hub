"use client";

import { useState } from "react";

type Worker = { id: string; name: string; status: string };

export function SourceAdministrationForm({
  sourceId,
  enabled,
  authorizedWorkerId,
  workers,
}: {
  sourceId: string;
  enabled: boolean;
  authorizedWorkerId: string | null;
  workers: Worker[];
}) {
  const [message, setMessage] = useState<string | null>(null);

  async function submit(formData: FormData) {
    const response = await fetch("/api/admin/sources", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_id: sourceId,
        enabled: formData.get("enabled") === "on",
        authorized_worker_id: String(formData.get("authorized_worker_id") ?? "") || null,
      }),
    });
    setMessage(response.ok ? "来源设置已保存。" : "来源设置保存失败。仅可绑定未撤销的 Worker。");
    if (response.ok) window.location.reload();
  }

  return (
    <form action={submit}>
      <label><input name="enabled" type="checkbox" defaultChecked={enabled} /> 启用</label>{" "}
      <label>授权 Worker <select name="authorized_worker_id" defaultValue={authorizedWorkerId ?? ""}><option value="">任一已注册 Worker</option>{workers.filter((worker) => worker.status !== "revoked").map((worker) => <option key={worker.id} value={worker.id}>{worker.name} ({worker.status})</option>)}</select></label>{" "}
      <button type="submit">保存来源设置</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

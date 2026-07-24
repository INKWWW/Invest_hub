"use client";

import { useEffect, useState } from "react";

type Worker = { id: string; name: string; status: string };

export function SourceAdministrationForm({
  sourceId,
}: {
  sourceId: string;
}) {
  const [message, setMessage] = useState<string | null>(null);
  const [source, setSource] = useState<{ displayName: string; enabled: boolean; authorizedWorkerId: string | null } | null>(null);
  const [workers, setWorkers] = useState<Worker[]>([]);

  useEffect(() => {
    let active = true;
    void Promise.all([fetch("/api/admin/sources"), fetch("/api/admin/workers")])
      .then(async ([sourceResponse, workerResponse]) => {
        if (!sourceResponse.ok || !workerResponse.ok) throw new Error("source_configuration_unavailable");
        const sourceBody = await sourceResponse.json() as { sources?: Array<{ id: string; display_name: string; enabled: boolean; authorized_worker_id: string | null }> };
        const workerBody = await workerResponse.json() as { workers?: Worker[] };
        const row = sourceBody.sources?.find((item) => item.id === sourceId);
        if (!row) throw new Error("source_not_found");
        if (active) {
          setSource({ displayName: row.display_name, enabled: row.enabled, authorizedWorkerId: row.authorized_worker_id });
          setWorkers(Array.isArray(workerBody.workers) ? workerBody.workers : []);
        }
      })
      .catch(() => { if (active) setMessage("无法读取来源设置，请刷新后重试。"); });
    return () => { active = false; };
  }, [sourceId]);

  async function submit(formData: FormData) {
    const response = await fetch("/api/admin/sources", {
      method: "PATCH",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_id: sourceId,
        display_name: formData.get("display_name"),
        enabled: formData.get("enabled") === "on",
        authorized_worker_id: String(formData.get("authorized_worker_id") ?? "") || null,
      }),
    });
    setMessage(response.ok ? "来源设置已保存。" : "请使用“社区名 · 频道名”，并确认 Worker 未被撤销。");
    if (response.ok) window.location.reload();
  }

  if (!source) return <section className="source-administration-form" aria-label="来源设置"><p>{message ?? "正在读取来源设置…"}</p></section>;

  return (
    <form action={submit}>
      <h3>来源资料</h3>
      <label>显示名称 <input name="display_name" required maxLength={128} defaultValue={source.displayName} /></label>
      <label><input name="enabled" type="checkbox" defaultChecked={source.enabled} /> 启用</label>
      <label>授权 Worker <select name="authorized_worker_id" defaultValue={source.authorizedWorkerId ?? ""}><option value="">任一已注册 Worker</option>{workers.filter((worker) => worker.status !== "revoked").map((worker) => <option key={worker.id} value={worker.id}>{worker.name} ({worker.status})</option>)}</select></label>
      <button type="submit">保存来源设置</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

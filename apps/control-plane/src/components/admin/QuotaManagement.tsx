"use client";

import { FormEvent, useState } from "react";

export type AdminQuotaRow = {
  owner_id: string;
  display_name: string | null;
  email: string | null;
  lifetime_units: number;
  available_units: number;
  reserved_units: number;
  settled_units: number;
  updated_at: string | null;
};

export function QuotaManagement({ initialQuotas }: { initialQuotas: AdminQuotaRow[] }) {
  const [quotas, setQuotas] = useState(initialQuotas);
  const [values, setValues] = useState(() => Object.fromEntries(initialQuotas.map((quota) => [quota.owner_id, String(quota.lifetime_units)])));
  const [reasons, setReasons] = useState<Record<string, string>>(() => Object.fromEntries(initialQuotas.map((quota) => [quota.owner_id, ""])));
  const [busyId, setBusyId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function submit(event: FormEvent<HTMLFormElement>, ownerId: string) {
    event.preventDefault();
    const lifetimeUnits = Number(values[ownerId]);
    const reason = reasons[ownerId]?.trim() ?? "";
    if (!Number.isSafeInteger(lifetimeUnits) || lifetimeUnits < 0 || !reason) {
      setError("请填写非负整数额度和调整原因。");
      return;
    }
    setBusyId(ownerId);
    setError(null);
    try {
      const response = await fetch("/api/admin/agent/quota", {
        method: "PATCH",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ owner_id: ownerId, lifetime_units: lifetimeUnits, reason }),
      });
      const payload = await response.json() as { quota?: Omit<AdminQuotaRow, "display_name" | "email">; error?: string };
      if (!response.ok || !payload.quota) throw new Error(payload.error ?? "quota_adjustment_failed");
      setQuotas((current) => current.map((quota) => quota.owner_id === ownerId ? { ...quota, ...payload.quota } : quota));
      setReasons((current) => ({ ...current, [ownerId]: "" }));
    } catch {
      setError("额度调整失败，请检查余额约束后重试。");
    } finally {
      setBusyId(null);
    }
  }

  return <section className="admin-quota-management" aria-label="Agent quota management">
    <div className="admin-section-heading"><div><p className="admin-kicker">Agent management</p><h1>研究额度</h1></div><p>终身额度只由管理员调整；预占和结算由后续 Agent Run 的数据库 RPC 完成。</p></div>
    {error ? <p className="admin-error" role="alert">{error}</p> : null}
    {quotas.length === 0 ? <p>暂无普通用户 Test Identity。</p> : <div className="admin-quota-list">
      {quotas.map((quota) => <article className="admin-quota-card" key={quota.owner_id}>
        <header><div><h2>{quota.display_name || "未命名用户"}</h2><p>{quota.email || quota.owner_id}</p></div><span>{quota.owner_id}</span></header>
        <dl><div><dt>可用</dt><dd>{quota.available_units}</dd></div><div><dt>预占</dt><dd>{quota.reserved_units}</dd></div><div><dt>已结算</dt><dd>{quota.settled_units}</dd></div></dl>
        <form onSubmit={(event) => void submit(event, quota.owner_id)}>
          <label>终身总额<input type="number" min="0" step="1" value={values[quota.owner_id] ?? "0"} onChange={(event) => setValues((current) => ({ ...current, [quota.owner_id]: event.target.value }))} /></label>
          <label>调整原因<input required maxLength={500} value={reasons[quota.owner_id] ?? ""} onChange={(event) => setReasons((current) => ({ ...current, [quota.owner_id]: event.target.value }))} placeholder="例如：初始测试额度" /></label>
          <button type="submit" disabled={busyId === quota.owner_id}>{busyId === quota.owner_id ? "保存中…" : "保存额度"}</button>
        </form>
      </article>)}
    </div>}
  </section>;
}

"use client";

import { useState } from "react";

export function XSourceForm() {
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  async function submit(formData: FormData) {
    setPending(true); setMessage(null);
    try {
      const response = await fetch("/api/admin/x/sources", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ source_key: formData.get("source_key"), display_name: formData.get("display_name"), requested_handle: formData.get("requested_handle"), parameter_version: formData.get("parameter_version") }) });
      if (!response.ok) { setMessage("创建失败，请检查管理员权限和输入。"); return; }
      setMessage("X 来源已创建，身份仍待本地 Worker 验证；验证后初始化覆盖水位即可采集。");
      window.location.reload();
    } finally { setPending(false); }
  }
  return <form action={submit}>
    <h2>新建 X 博主</h2>
    <p>只保存面向用户的名称和请求的账号名；浏览器 URL、登录态和本地 Profile 不进入控制面。</p>
    <label>内部来源标识 <input name="source_key" required maxLength={128} /></label>
    <label>展示名称 <input name="display_name" required maxLength={128} placeholder="例如：研究博主 A" /></label>
    <label>X 账号名 <input name="requested_handle" required maxLength={128} placeholder="例如：researcher" /></label>
    <label>参数版本 <input name="parameter_version" required maxLength={128} /></label>
    <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建 X 来源"}</button>
    {message ? <p role="status">{message}</p> : null}
  </form>;
}

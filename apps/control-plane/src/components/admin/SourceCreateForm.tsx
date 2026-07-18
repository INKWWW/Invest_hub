"use client";

import { useState } from "react";

export function SourceCreateForm() {
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(formData: FormData) {
    setPending(true);
    setMessage(null);
    const response = await fetch("/api/admin/sources", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_key: formData.get("source_key"),
        display_name: formData.get("display_name"),
        parameter_version: formData.get("parameter_version"),
      }),
    });
    setPending(false);
    if (!response.ok) {
      setMessage("创建失败，请检查管理员权限和输入内容。");
      return;
    }
    setMessage("来源已创建，可以在任务页创建一次同步任务。");
    window.location.reload();
  }

  return (
    <form action={submit}>
      <h2>新建逻辑来源</h2>
      <p>只保存逻辑来源标识；Discord URL 和本地浏览器 Profile 只保存在 Worker 配置中。</p>
      <label>来源标识 <input name="source_key" required maxLength={128} /></label>{" "}
      <label>显示名称 <input name="display_name" required maxLength={128} /></label>{" "}
      <label>参数版本 <input name="parameter_version" required maxLength={128} /></label>{" "}
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建来源"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

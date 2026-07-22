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
      <h2>新建 Discord 来源</h2>
      <p>显示名称必须是“社区名 · 频道名”；它是阅读页、任务和管理页唯一展示给人的来源名称。内部标识、Discord URL 和本地浏览器 Profile 不会展示。</p>
      <label>内部来源标识 <input name="source_key" required maxLength={128} /></label>{" "}
      <label>显示名称（社区名 · 频道名） <input name="display_name" required maxLength={128} placeholder="例如：研究社区 · #美股讨论" /></label>{" "}
      <label>参数版本 <input name="parameter_version" required maxLength={128} /></label>{" "}
      <button type="submit" disabled={pending}>{pending ? "创建中…" : "创建来源"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

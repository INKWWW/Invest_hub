"use client";

import { useState } from "react";

export function parseAuthorIds(value: string): string[] {
  return [...new Set(value.split(/[\n,]/).map((item) => item.trim()).filter(Boolean))].sort();
}

export function validateRuleSets(sourceTargets: string[], sourceExcluded: string[]): string | null {
  const conflict = sourceTargets.find((authorId) => sourceExcluded.includes(authorId));
  return conflict ? `同一来源 author ID 不能同时 target 和 exclude：${conflict}` : null;
}

export function SourceRuleForm({ sourceId }: { sourceId: string }) {
  const [message, setMessage] = useState<string | null>(null);
  const [pending, setPending] = useState(false);

  async function submit(formData: FormData) {
    const globalTargets = parseAuthorIds(String(formData.get("global_target_author_ids") ?? ""));
    const sourceTargets = parseAuthorIds(String(formData.get("source_target_author_ids") ?? ""));
    const sourceExcluded = parseAuthorIds(String(formData.get("source_excluded_author_ids") ?? ""));
    const validation = validateRuleSets(sourceTargets, sourceExcluded);
    if (validation) {
      setMessage(validation);
      return;
    }
    setPending(true);
    setMessage(null);
    const response = await fetch("/api/admin/rules", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        source_id: sourceId,
        global_target_author_ids: globalTargets,
        source_target_author_ids: sourceTargets,
        source_excluded_author_ids: sourceExcluded,
      }),
    });
    setPending(false);
    if (!response.ok) {
      setMessage("规则保存失败，请检查管理员权限和 author ID。");
      return;
    }
    setMessage("规则已保存；后续任务会使用新的冻结版本。");
    window.location.reload();
  }

  return (
    <form action={submit}>
      <h3>Author 规则</h3>
      <p>以逗号或换行分隔 author ID；来源 exclude 优先于 target。</p>
      <label>全局 target <textarea name="global_target_author_ids" rows={2} /></label>{" "}
      <label>本来源 target <textarea name="source_target_author_ids" rows={2} /></label>{" "}
      <label>本来源 exclude <textarea name="source_excluded_author_ids" rows={2} /></label>{" "}
      <button type="submit" disabled={pending}>{pending ? "保存中…" : "保存规则"}</button>
      {message ? <p role="status">{message}</p> : null}
    </form>
  );
}

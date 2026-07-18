"use client";

import { useState } from "react";

export function RetryTaskButton({ taskId }: { taskId: string }) {
  const [state, setState] = useState<"idle" | "pending" | "error">("idle");

  async function retry() {
    setState("pending");
    try {
      const response = await fetch(`/api/admin/tasks/${encodeURIComponent(taskId)}/retry`, { method: "POST" });
      if (!response.ok) throw new Error("retry_failed");
      window.location.reload();
    } catch {
      setState("error");
    }
  }

  return (
    <span>
      <button type="button" onClick={retry} disabled={state === "pending"}>
        {state === "pending" ? "Retrying…" : "Retry task"}
      </button>
      {state === "error" ? <small role="alert"> Retry failed; inspect the task event.</small> : null}
    </span>
  );
}


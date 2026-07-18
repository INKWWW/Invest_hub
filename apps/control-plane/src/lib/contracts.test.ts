import { describe, expect, it } from "vitest";

import { parseContract } from "./contracts";

describe("v0 contracts", () => {
  it("accepts a valid heartbeat", () => {
    const heartbeat = parseContract<{ worker_id: string }>("heartbeat", {
      contract_version: "v0",
      worker_id: "worker-001",
      sent_at: "2026-07-18T12:00:00Z",
      status: "idle",
      capabilities: ["discord_sync"]
    });

    expect(heartbeat.worker_id).toBe("worker-001");
  });

  it("rejects unknown task result fields", () => {
    expect(() =>
      parseContract("task-result", {
        contract_version: "v0",
        task_id: "task-001",
        attempt: 1,
        status: "succeeded",
        safe_checkpoint: null,
        raw_count: 0,
        canonical_count: 0,
        duplicate_count: 0,
        unresolved_count: 0,
        unparsed_media_count: 0,
        structured_run_ids: [],
        telemetry: { elapsed_ms: 10, retry_count: 0, failure_class: null },
        prompt: "must not cross the boundary"
      })
    ).toThrow(/invalid task-result contract/);
  });
});

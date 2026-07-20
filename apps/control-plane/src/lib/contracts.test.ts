import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { parseContract } from "./contracts";

describe("v0 contracts", () => {
  it("ships the control-plane contract bundle and keeps it equal to the canonical contracts", () => {
    const names = [
      "heartbeat",
      "source-config",
      "task-claim",
      "task-event",
      "task-failure",
      "task-result",
      "worker-enrolment",
      "worker-persistence",
    ];
    const deploymentRoot = resolve(process.cwd(), "contracts", "v0");
    const canonicalRoot = resolve(process.cwd(), "..", "..", "contracts", "v0");

    for (const name of names) {
      const filename = `${name}.schema.json`;
      const deployed = resolve(deploymentRoot, filename);
      expect(existsSync(deployed)).toBe(true);
      expect(readFileSync(deployed, "utf8")).toBe(readFileSync(resolve(canonicalRoot, filename), "utf8"));
    }
  });

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

  it("accepts a bounded claim with an immutable rule snapshot", () => {
    const claim = parseContract<{
      rule_snapshot: { version: number; target_author_ids: string[] };
      collection_scope: { mode: string; max_pages: number };
    }>("task-claim", {
      contract_version: "v0",
      task_id: "task-001",
      attempt: 1,
      task_type: "discord_sync",
      source_id: "discord-source-001",
      parameter_version: "v1-test-1",
      lease_expires_at: "2026-07-19T12:00:00Z",
      safe_checkpoint: null,
      rule_snapshot: { version: 3, target_author_ids: ["author-1", "author-2"] },
      collection_scope: { mode: "history", max_pages: 2 },
    });

    expect(claim.rule_snapshot.target_author_ids).toEqual(["author-1", "author-2"]);
    expect(claim.collection_scope).toEqual({ mode: "history", max_pages: 2 });
  });

  it("rejects an invalid V1 task scope or duplicated target author", () => {
    const base = {
      contract_version: "v0",
      task_id: "task-001",
      attempt: 1,
      task_type: "discord_sync",
      source_id: "discord-source-001",
      parameter_version: "v1-test-1",
      lease_expires_at: "2026-07-19T12:00:00Z",
      safe_checkpoint: null,
      rule_snapshot: { version: 3, target_author_ids: ["author-1"] },
      collection_scope: { mode: "incremental", max_pages: 5 },
    };

    expect(() => parseContract("task-claim", { ...base, collection_scope: { mode: "history", max_pages: 0 } })).toThrow(/invalid task-claim contract/);
    expect(() => parseContract("task-claim", { ...base, collection_scope: { mode: "unbounded", max_pages: 5 } })).toThrow(/invalid task-claim contract/);
    expect(() => parseContract("task-claim", { ...base, rule_snapshot: { version: 3, target_author_ids: ["author-1", "author-1"] } })).toThrow(/invalid task-claim contract/);
  });

  it("rejects a batch summary without message or structured-run evidence", () => {
    expect(() => parseContract("worker-persistence", {
      contract_version: "v0",
      task_id: "task-001",
      attempt: 1,
      source_id: "discord-source-001",
      raw_messages: [],
      canonical_messages: [],
      structured_runs: [],
      batch_summaries: [{
        natural_date: "2026-07-19",
        input_message_ids: [],
        structured_run_keys: [],
        output: { topics: [] },
        coverage: { unparsed_media: false },
      }],
    })).toThrow(/invalid worker-persistence contract/);

    expect(() => parseContract("worker-persistence", {
      contract_version: "v0",
      task_id: "task-001",
      attempt: 1,
      source_id: "discord-source-001",
      raw_messages: [],
      canonical_messages: [],
      structured_runs: [],
      batch_summaries: [{
        natural_date: "2026-07-19",
        input_message_ids: ["message-001"],
        structured_run_keys: ["chunk-001"],
        output: { topics: [] },
      }],
    })).toThrow(/invalid worker-persistence contract/);
  });
});

import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

import { parseContract } from "./contracts";

describe("v0 contracts", () => {
  it("ships the control-plane contract bundle and keeps it equal to the canonical contracts", () => {
    const names = [
      "heartbeat",
      "source-config",
      "task-capture-segment",
      "task-claim",
      "task-event",
      "task-failure",
      "task-result",
      "window-range-completion",
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

  it("accepts a V1.1 window claim without a page-cap completion condition", () => {
    const claim = parseContract<{
      collection_scope: { mode: string };
      capture_range: { start_at: string; end_at: string; timezone: string };
      capture_progress: { resume_cursor: string | null; page_count: number };
      author_profile_snapshot: Array<{ profile_id: string; author_id: string | null }>;
    }>("task-claim", {
      contract_version: "v0",
      task_id: "task-window-001",
      attempt: 1,
      task_type: "discord_sync",
      source_id: "discord-source-001",
      parameter_version: "v1.1-test",
      lease_expires_at: "2026-07-22T08:10:00Z",
      safe_checkpoint: "legacy-audit-only",
      rule_snapshot: { version: 0, target_author_ids: [] },
      collection_scope: { mode: "window" },
      capture_range: {
        mode: "window",
        trigger: "manual",
        timezone: "Asia/Shanghai",
        start_at: "2026-07-22T00:00:00Z",
        end_at: "2026-07-22T08:00:00Z",
        scheduled_window_key: null,
      },
      coverage_snapshot: {
        coverage_start_at: "2026-07-22T00:00:00Z",
        coverage_through_at: "2026-07-22T00:00:00Z",
        last_completed_task_id: null,
      },
      capture_progress: { resume_cursor: null, page_count: 0, range_complete: false },
      author_profile_snapshot: [{
        profile_id: "profile-1",
        requested_author: "Priority author",
        resolution_status: "pending",
        author_id: null,
        author_display: "Priority author",
        author_handle: null,
        enabled: true,
      }],
    });

    expect(claim.collection_scope).toEqual({ mode: "window" });
    expect(claim.capture_range).toMatchObject({ timezone: "Asia/Shanghai", end_at: "2026-07-22T08:00:00Z" });
    expect(claim.capture_progress).toEqual({ resume_cursor: null, page_count: 0, range_complete: false });
    expect(claim.author_profile_snapshot[0]).toMatchObject({ profile_id: "profile-1", author_id: null });
  });

  it("accepts an X window claim only with a safe resolved-account snapshot", () => {
    const claim = parseContract<{ task_type: string; source_snapshot: { source_type: string; account_id: string } }>("task-claim", {
      contract_version: "v0",
      task_id: "x-window-001",
      attempt: 1,
      task_type: "x_sync",
      source_id: "x-source-001",
      parameter_version: "v2-test",
      lease_expires_at: "2026-07-23T08:10:00Z",
      safe_checkpoint: null,
      rule_snapshot: { version: 0, target_author_ids: [] },
      collection_scope: { mode: "window" },
      capture_range: {
        mode: "window", trigger: "scheduled", timezone: "Asia/Shanghai",
        start_at: "2026-07-23T00:00:00Z", end_at: "2026-07-23T08:00:00Z", scheduled_window_key: "2026-07-23T08:00+08:00",
      },
      coverage_snapshot: { coverage_start_at: "2026-07-23T00:00:00Z", coverage_through_at: "2026-07-23T00:00:00Z", last_completed_task_id: null },
      capture_progress: { resume_cursor: null, page_count: 0, range_complete: false },
      author_profile_snapshot: [],
      source_snapshot: { source_type: "x", account_id: "account-001", display_name: "X author", parameter_version: "v2-test" },
    });

    expect(claim).toMatchObject({ task_type: "x_sync", source_snapshot: { source_type: "x", account_id: "account-001" } });
  });

  it("accepts typed X post context while rejecting a mismatched relation", () => {
    const base = {
      contract_version: "v0",
      task_id: "x-window-001",
      attempt: 1,
      source_id: "x-source-001",
      raw_messages: [],
      canonical_messages: [],
      structured_runs: [],
    };
    const xContext = {
      external_message_id: "x-post-001",
      post_type: "quote",
      post_url: "https://x.com/author/status/100",
      quoted_post_id: "quoted-001",
      reply_to_post_id: null,
      reposted_post_id: null,
      context_status: "complete",
      attachments: [],
    };

    expect(parseContract<{ x_post_contexts: unknown[] }>("worker-persistence", { ...base, x_post_contexts: [xContext] }).x_post_contexts).toHaveLength(1);
    expect(() => parseContract("worker-persistence", { ...base, x_post_contexts: [{ ...xContext, reply_to_post_id: "reply-001" }] })).toThrow(/invalid worker-persistence contract/);
  });

  it("accepts a verified V1.1 page receipt while rejecting unknown persistence fields", () => {
    const payload = parseContract<{
      capture_segment: { idempotency_key: string; response_matched: boolean; response_fresh: boolean };
    }>("worker-persistence", {
      contract_version: "v0",
      task_id: "task-window-001",
      attempt: 1,
      source_id: "discord-source-001",
      raw_messages: [],
      canonical_messages: [],
      structured_runs: [],
      capture_segment: {
        idempotency_key: "page-001",
        request_cursor: null,
        next_cursor: "cursor-001",
        oldest_occurred_at: "2026-07-22T00:00:00Z",
        newest_occurred_at: "2026-07-22T08:00:00Z",
        response_matched: true,
        response_fresh: true,
      },
    });

    expect(payload.capture_segment).toMatchObject({ idempotency_key: "page-001", response_matched: true, response_fresh: true });
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

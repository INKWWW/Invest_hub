import { describe, expect, it } from "vitest";

import {
  buildTaskViewModel,
  canRetryTask,
  deriveDisplayStatus,
  hasAdminRole,
  statusLabel,
} from "../../lib/admin/view-model";
import { parseWorkerInviteResponse } from "../../components/admin/worker-invite";
import { parseUserInviteResponse } from "../../components/admin/user-invite";

describe("admin debug view models", () => {
  it("distinguishes no-new-data, retryable, failed, unresolved success and success", () => {
    expect(deriveDisplayStatus({ status: "succeeded", result: { raw_count: 0, canonical_count: 0 } })).toBe("no_new_data");
    expect(deriveDisplayStatus({ status: "retryable_failed" })).toBe("retryable_failed");
    expect(deriveDisplayStatus({ status: "failed" })).toBe("failed");
    expect(deriveDisplayStatus({ status: "succeeded", result: { unresolved_count: 2 } })).toBe("succeeded_with_unresolved");
    expect(deriveDisplayStatus({ status: "succeeded", result: { canonical_count: 2 } })).toBe("succeeded");
    expect(statusLabel("succeeded_with_unresolved")).toBe("Succeeded with unresolved");
  });

  it("keeps operational fields while filtering credentials and full content", () => {
    const view = buildTaskViewModel({
      id: "task-1",
      status: "succeeded",
      source_id: "source-1",
      parameter_version: "v0-default",
      last_checkpoint: "cursor-2",
      result: {
        raw_count: 4,
        canonical_count: 3,
        duplicate_count: 1,
        unresolved_count: 1,
        unparsed_media_count: 1,
        provider: "codex_cli",
        model_reported: "local-model",
        prompt_version: "prompt-v0",
        p50_ms: 100,
        p95_ms: 200,
        schema_status: "valid",
        evidence_refs: ["local://evidence/1"],
        cookie: "private-cookie",
        token: "private-token",
        profile_ref: "/private/profile",
        prompt: "private prompt",
        raw_response: "full response",
      },
    });

    expect(view.status).toBe("succeeded_with_unresolved");
    expect(view.provider).toBe("codex_cli");
    expect(view.promptVersion).toBe("prompt-v0");
    expect(view.evidenceRefs).toEqual(["local://evidence/1"]);
    const serialized = JSON.stringify(view);
    expect(serialized).not.toContain("private-cookie");
    expect(serialized).not.toContain("private-token");
    expect(serialized).not.toContain("/private/profile");
    expect(serialized).not.toContain("private prompt");
    expect(serialized).not.toContain("full response");
  });

  it("blocks ordinary users and only offers retry for retryable failures", () => {
    expect(hasAdminRole("user")).toBe(false);
    expect(hasAdminRole("admin")).toBe(true);
    expect(canRetryTask({ status: "retryable_failed" })).toBe(true);
    expect(canRetryTask({ status: "failed" })).toBe(false);
    expect(canRetryTask({ status: "succeeded" })).toBe(false);
  });

  it("accepts only a one-time Worker invite response and never treats a device secret as an invite code", () => {
    expect(parseWorkerInviteResponse({
      invite_id: "invite-1",
      code: "one-time-worker-code",
      purpose: "worker",
      expires_at: "2099-01-01T00:00:00.000Z",
    })).toEqual({ code: "one-time-worker-code", expiresAt: "2099-01-01T00:00:00.000Z" });
    expect(parseWorkerInviteResponse({ purpose: "worker", device_secret: "must-not-display" })).toBeNull();
  });

  it("accepts only a one-time user invite response", () => {
    expect(parseUserInviteResponse({
      invite_id: "invite-2",
      code: "one-time-user-code",
      purpose: "user",
      expires_at: "2099-01-01T00:00:00.000Z",
    })).toEqual({ code: "one-time-user-code", expiresAt: "2099-01-01T00:00:00.000Z" });
    expect(parseUserInviteResponse({ purpose: "worker", code: "worker-code", expires_at: "2099-01-01T00:00:00.000Z" })).toBeNull();
    expect(parseUserInviteResponse({ purpose: "user", device_secret: "must-not-display" })).toBeNull();
  });
});

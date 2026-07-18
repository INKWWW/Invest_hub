import { describe, expect, it } from "vitest";

import { InvalidTaskTransition, transitionTask, type TaskEvent } from "./state-machine";

describe("v0 task state machine", () => {
  const legalTransitions: Array<[string, TaskEvent, string]> = [
    ["queued", "claim", "leased"],
    ["leased", "start", "running"],
    ["leased", "retry", "retryable_failed"],
    ["leased", "fail", "failed"],
    ["leased", "cancel", "cancelled"],
    ["running", "succeed", "succeeded"],
    ["running", "retry", "retryable_failed"],
    ["running", "fail", "failed"],
    ["running", "cancel", "cancelled"],
    ["retryable_failed", "retry", "queued"],
    ["failed", "retry", "queued"],
  ];

  it.each(legalTransitions)("allows %s + %s -> %s", (current, event, expected) => {
    expect(transitionTask(current as never, event)).toBe(expected);
  });

  it("rejects a terminal succeeded task returning to running", () => {
    expect(() => transitionTask("succeeded", "start")).toThrow(InvalidTaskTransition);
    try {
      transitionTask("succeeded", "start");
    } catch (error) {
      expect(error).toMatchObject({ current: "succeeded", event: "start" });
    }
  });

  it("treats an expired lease as retryable rather than success", () => {
    expect(transitionTask("running", "lease_expired")).toBe("retryable_failed");
  });
});

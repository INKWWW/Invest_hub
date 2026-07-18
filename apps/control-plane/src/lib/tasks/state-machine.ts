import type { TaskStatus } from "../db/types";

export type TaskEvent =
  | "claim"
  | "start"
  | "succeed"
  | "retry"
  | "fail"
  | "cancel"
  | "lease_expired";

export class InvalidTaskTransition extends Error {
  readonly current: TaskStatus;
  readonly event: TaskEvent;

  constructor(current: TaskStatus, event: TaskEvent) {
    super(`invalid task transition: ${current} + ${event}`);
    this.name = "InvalidTaskTransition";
    this.current = current;
    this.event = event;
  }
}

const transitions: Partial<Record<TaskStatus, Partial<Record<TaskEvent, TaskStatus>>>> = {
  queued: { claim: "leased" },
  leased: {
    start: "running",
    retry: "retryable_failed",
    fail: "failed",
    cancel: "cancelled",
    lease_expired: "retryable_failed",
  },
  running: {
    succeed: "succeeded",
    retry: "retryable_failed",
    fail: "failed",
    cancel: "cancelled",
    lease_expired: "retryable_failed",
  },
  retryable_failed: { retry: "queued" },
  failed: { retry: "queued" },
};

export function transitionTask(current: TaskStatus, event: TaskEvent): TaskStatus {
  const next = transitions[current]?.[event];
  if (!next) throw new InvalidTaskTransition(current, event);
  return next;
}

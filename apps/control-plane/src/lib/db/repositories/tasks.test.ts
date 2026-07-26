import { describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ from: vi.fn(), rpc: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ from: databaseMocks.from, rpc: databaseMocks.rpc }),
}));

import { completeWindowedCaptureRange, scheduleDueSourceTasks } from "./tasks";

describe("due source scheduling", () => {
  it("keeps X scheduling available when the retired Discord scheduler fails", async () => {
    databaseMocks.rpc.mockImplementation((name: string) => {
      if (name === "enqueue_due_discord_tasks") {
        return Promise.resolve({ data: null, error: { message: "discord scheduler unavailable" } });
      }
      return Promise.resolve({
        data: { scheduled_at: "2026-07-25T12:00:00Z", tasks: [], deferred_source_ids: [] },
        error: null,
      });
    });

    await expect(scheduleDueSourceTasks("worker-1", new Date("2026-07-25T12:00:00Z"))).resolves.toEqual({
      scheduled_at: "2026-07-25T12:00:00Z", tasks: [], deferred_source_ids: [],
    });
  });

  it("binds range-completion database requests to the caller cancellation signal", async () => {
    const controller = new AbortController();
    const taskQuery = {
      abortSignal: vi.fn(),
      eq: vi.fn(),
      maybeSingle: vi.fn().mockResolvedValue({
        data: { task_type: "x_sync", capture_range: { mode: "window" } },
        error: null,
      }),
    };
    taskQuery.eq.mockReturnValue(taskQuery);
    taskQuery.abortSignal.mockReturnValue(taskQuery);
    const completionRequest = {
      abortSignal: vi.fn(),
      then: (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
        Promise.resolve({ data: { status: "succeeded" }, error: null }).then(resolve, reject),
    };
    completionRequest.abortSignal.mockReturnValue(completionRequest);
    databaseMocks.from.mockReturnValue({ select: vi.fn().mockReturnValue(taskQuery) });
    databaseMocks.rpc.mockReturnValue(completionRequest);

    await expect(completeWindowedCaptureRange(
      "task-1",
      1,
      "worker-1",
      { range_complete: true },
      controller.signal,
    )).resolves.toEqual({ status: "succeeded" });

    expect(taskQuery.abortSignal).toHaveBeenCalledWith(controller.signal);
    expect(completionRequest.abortSignal).toHaveBeenCalledWith(controller.signal);
  });
});

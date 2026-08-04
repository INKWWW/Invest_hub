import { describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ from: vi.fn(), rpc: vi.fn() }));
const judgementMocks = vi.hoisted(() => ({ ensureDueXCollectionBatches: vi.fn(), advanceXManualRecoveryRuns: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ from: databaseMocks.from, rpc: databaseMocks.rpc }),
}));
vi.mock("./x-daily-judgements", () => judgementMocks);

import { completeWindowedCaptureRange, scheduleDueSourceTasks } from "./tasks";

describe("due source scheduling", () => {
  it("keeps X scheduling available when the retired Discord scheduler fails", async () => {
    judgementMocks.ensureDueXCollectionBatches.mockResolvedValue({});
    judgementMocks.advanceXManualRecoveryRuns.mockResolvedValue({ runs: [] });
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
      judgement_dispatch_failed: false,
    });
    expect(judgementMocks.ensureDueXCollectionBatches).toHaveBeenCalledWith("worker-1", new Date("2026-07-25T12:00:00Z"));
    expect(judgementMocks.advanceXManualRecoveryRuns).toHaveBeenCalledWith("worker-1", new Date("2026-07-25T12:00:00Z"));
  });

  it("surfaces a safe judgement dispatch failure without discarding scheduled source work", async () => {
    judgementMocks.ensureDueXCollectionBatches.mockRejectedValue(new Error("private dispatcher detail"));
    judgementMocks.advanceXManualRecoveryRuns.mockResolvedValue({ runs: [] });
    databaseMocks.rpc.mockImplementation((name: string) => {
      if (name === "enqueue_due_discord_tasks") {
        return Promise.resolve({ data: null, error: { message: "discord scheduler unavailable" } });
      }
      return Promise.resolve({
        data: {
          scheduled_at: "2026-07-25T12:00:00Z",
          tasks: [{ id: "x-task-1", source_id: "x-source-1", idempotent: false }],
          deferred_source_ids: [],
        },
        error: null,
      });
    });

    const result = await scheduleDueSourceTasks("worker-1", new Date("2026-07-25T12:00:00Z"));

    expect(result).toEqual({
      scheduled_at: "2026-07-25T12:00:00Z",
      tasks: [{ id: "x-task-1", source_id: "x-source-1", idempotent: false }],
      deferred_source_ids: [],
      judgement_dispatch_failed: true,
    });
    expect(JSON.stringify(result)).not.toContain("private dispatcher detail");
  });

  it("maps an isolated database settlement failure to the safe judgement flag", async () => {
    judgementMocks.ensureDueXCollectionBatches.mockResolvedValue({ settlement_dispatch_failed: true });
    judgementMocks.advanceXManualRecoveryRuns.mockResolvedValue({ runs: [] });
    databaseMocks.rpc.mockResolvedValue({
      data: { scheduled_at: "2026-07-25T12:00:00Z", tasks: [], deferred_source_ids: [] },
      error: null,
    });

    await expect(scheduleDueSourceTasks("worker-1", new Date("2026-07-25T12:00:00Z"))).resolves.toMatchObject({
      judgement_dispatch_failed: true,
    });
  });

  it("binds window range completion directly to the caller cancellation signal", async () => {
    const controller = new AbortController();
    const completionRequest = {
      abortSignal: vi.fn(),
      then: (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
        Promise.resolve({ data: { status: "succeeded" }, error: null }).then(resolve, reject),
    };
    completionRequest.abortSignal.mockReturnValue(completionRequest);
    databaseMocks.from.mockImplementation(() => { throw new Error("range completion must not pre-read the locked task row"); });
    databaseMocks.rpc.mockReturnValue(completionRequest);

    await expect(completeWindowedCaptureRange(
      "task-1",
      1,
      "worker-1",
      { range_complete: true, capture_range: { mode: "window" } },
      controller.signal,
    )).resolves.toEqual({ status: "succeeded" });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("complete_windowed_capture_range", expect.objectContaining({
      p_task_id: "task-1",
    }));
    expect(completionRequest.abortSignal).toHaveBeenCalledWith(controller.signal);
  });

  it("chooses bounded history completion from the immutable capture range", async () => {
    const completionRequest = {
      abortSignal: vi.fn(),
      then: (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
        Promise.resolve({ data: { status: "succeeded" }, error: null }).then(resolve, reject),
    };
    completionRequest.abortSignal.mockReturnValue(completionRequest);
    databaseMocks.from.mockImplementation(() => { throw new Error("history completion must not pre-read the locked task row"); });
    databaseMocks.rpc.mockReturnValue(completionRequest);

    await expect(completeWindowedCaptureRange(
      "task-history-1",
      1,
      "worker-1",
      { range_complete: true, capture_range: { mode: "history" } },
    )).resolves.toEqual({ status: "succeeded" });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("complete_bounded_x_history_range", expect.objectContaining({
      p_task_id: "task-history-1",
    }));
  });
});

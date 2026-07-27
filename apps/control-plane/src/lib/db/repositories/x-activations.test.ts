import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import { claimXActivation, initializeXActivation } from "./x-activations";

describe("X activation repository", () => {
  beforeEach(() => vi.clearAllMocks());

  it("maps the exact safe activation receipt", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: { source_id: "source-x", requested_handle: "fixture", parameter_version: "x-standard-v2", initial_end_at: "2026-07-27T04:00:00Z", idempotent: false },
      error: null,
    });

    await expect(claimXActivation("worker-x", "2026-07-27T04:02:00Z")).resolves.toEqual({
      sourceId: "source-x", requestedHandle: "fixture", parameterVersion: "x-standard-v2", initialEndAt: "2026-07-27T04:00:00Z", idempotent: false,
    });
    expect(databaseMocks.rpc).toHaveBeenCalledWith("claim_next_x_activation", { p_worker_id: "worker-x", p_now: "2026-07-27T04:02:00Z" });
  });

  it("accepts a null task when activation occurs before the first daily cutoff", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: { task_id: null, source_id: "source-x", initial_end_at: "2026-07-27T16:00:00Z", idempotent: false },
      error: null,
    });

    await expect(initializeXActivation({ sourceId: "source-x", workerId: "worker-x", now: "2026-07-27T16:02:00Z" })).resolves.toEqual({
      taskId: null, sourceId: "source-x", initialEndAt: "2026-07-27T16:00:00Z", idempotent: false,
    });
  });
});

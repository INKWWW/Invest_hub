import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  coverageMaybeSingle: vi.fn(),
  rpc: vi.fn(),
  sourceMaybeSingle: vi.fn(),
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    rpc: databaseMocks.rpc,
    from(table: string) {
      if (table === "sources") {
        return {
          select: () => ({
            eq: () => ({ maybeSingle: databaseMocks.sourceMaybeSingle }),
          }),
        };
      }
      return {
        select: () => ({
          eq: () => ({ maybeSingle: databaseMocks.coverageMaybeSingle }),
        }),
      };
    },
  }),
}));

import {
  createManualDiscordRefresh,
  getSourceCoverage,
  initializeSourceCoverage,
  WindowedSyncError,
} from "./windowed-sync";

describe("windowed sync repository", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("maps a coverage initialization receipt without exposing internal state", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: {
        source_id: "source-1",
        coverage_start_at: "2026-07-22T00:00:00Z",
        coverage_through_at: "2026-07-22T00:00:00Z",
        idempotent: false,
      },
      error: null,
    });

    await expect(initializeSourceCoverage({
      sourceId: "source-1",
      actorId: "admin-1",
      coverageStartAt: "2026-07-22T00:00:00Z",
    })).resolves.toEqual({
      sourceId: "source-1",
      coverageStartAt: "2026-07-22T00:00:00Z",
      coverageThroughAt: "2026-07-22T00:00:00Z",
    });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("initialize_discord_collection_coverage", {
      p_source_id: "source-1",
      p_actor_id: "admin-1",
      p_boundary: "2026-07-22T00:00:00Z",
    });
  });

  it("uses a trusted server time and returns only safe manual task state", async () => {
    databaseMocks.sourceMaybeSingle.mockResolvedValue({
      data: { id: "source-1", parameter_version: "v1.1-test" },
      error: null,
    });
    databaseMocks.rpc.mockResolvedValue({
      data: {
        id: "task-1",
        source_id: "source-1",
        status: "queued",
        queued_at: "2026-07-22T03:00:00Z",
        collection_scope: { mode: "window" },
        capture_range: {
          mode: "window",
          trigger: "manual",
          timezone: "Asia/Shanghai",
          start_at: "2026-07-22T00:00:00Z",
          end_at: "2026-07-22T03:00:00Z",
          scheduled_window_key: null,
        },
        resume_cursor: "must-not-be-returned",
      },
      error: null,
    });

    await expect(createManualDiscordRefresh({
      sourceId: "source-1",
      requestedBy: "admin-1",
      now: new Date("2026-07-22T03:00:00Z"),
    })).resolves.toEqual({
      id: "task-1",
      sourceId: "source-1",
      status: "queued",
      trigger: "manual",
      startAt: "2026-07-22T00:00:00Z",
      endAt: "2026-07-22T03:00:00Z",
      queuedAt: "2026-07-22T03:00:00Z",
      idempotent: false,
    });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("create_windowed_discord_sync_task", {
      p_source_id: "source-1",
      p_parameter_version: "v1.1-test",
      p_requested_by: "admin-1",
      p_trigger: "manual",
      p_end_at: "2026-07-22T03:00:00.000Z",
      p_scheduled_window_key: null,
    });
  });

  it("requires explicit initial coverage rather than inferring a legacy cursor", async () => {
    databaseMocks.sourceMaybeSingle.mockResolvedValue({
      data: { id: "source-1", parameter_version: "v1.1-test" },
      error: null,
    });
    databaseMocks.rpc.mockResolvedValue({
      data: null,
      error: { message: "coverage_not_initialized" },
    });

    await expect(createManualDiscordRefresh({
      sourceId: "source-1",
      requestedBy: "admin-1",
      now: new Date("2026-07-22T03:00:00Z"),
    })).rejects.toMatchObject({ message: "coverage_not_initialized" } satisfies Partial<WindowedSyncError>);
  });

  it("reads only a source coverage waterline when requested", async () => {
    databaseMocks.coverageMaybeSingle.mockResolvedValue({
      data: {
        source_id: "source-1",
        coverage_start_at: "2026-07-22T00:00:00Z",
        coverage_through_at: "2026-07-22T03:00:00Z",
      },
      error: null,
    });

    await expect(getSourceCoverage("source-1")).resolves.toEqual({
      sourceId: "source-1",
      coverageStartAt: "2026-07-22T00:00:00Z",
      coverageThroughAt: "2026-07-22T03:00:00Z",
    });
  });
});

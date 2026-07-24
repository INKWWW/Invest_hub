import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  workerMaybeSingle: vi.fn(),
  sourceMaybeSingle: vi.fn(),
  sourceUpdate: vi.fn(),
  sourceListEq: vi.fn(),
  sourceListIs: vi.fn(),
  sourceListOrder: vi.fn(),
  sourceSelect: vi.fn(),
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({
    from(table: string) {
      if (table === "workers") {
        return {
          select: () => ({
            eq: () => ({ maybeSingle: databaseMocks.workerMaybeSingle }),
          }),
        };
      }
      return {
        select: databaseMocks.sourceSelect,
        update: databaseMocks.sourceUpdate,
      };
    },
  }),
}));

import { listAdminSources, SourceAdministrationError, updateSourceAdministration } from "./sources";

describe("source administration", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    databaseMocks.sourceUpdate.mockReturnValue({
      eq: () => ({
        select: () => ({ maybeSingle: databaseMocks.sourceMaybeSingle }),
      }),
    });
    databaseMocks.sourceSelect.mockReturnValue({ eq: databaseMocks.sourceListEq });
    databaseMocks.sourceListEq.mockReturnValue({
      is: databaseMocks.sourceListIs,
      order: databaseMocks.sourceListOrder,
    });
    databaseMocks.sourceListIs.mockReturnValue({ order: databaseMocks.sourceListOrder });
  });

  it("rejects binding a source to a revoked Worker", async () => {
    databaseMocks.workerMaybeSingle.mockResolvedValue({ data: { id: "worker-1", status: "revoked" }, error: null });

    await expect(updateSourceAdministration({
      sourceId: "source-1",
      displayName: "Research community · #daily",
      enabled: true,
      authorizedWorkerId: "worker-1",
    })).rejects.toMatchObject({ message: "invalid_authorized_worker" } satisfies Partial<SourceAdministrationError>);

    expect(databaseMocks.sourceUpdate).not.toHaveBeenCalled();
  });

  it("permits a non-revoked Worker binding and persists only the safe configuration fields", async () => {
    databaseMocks.workerMaybeSingle.mockResolvedValue({ data: { id: "worker-1", status: "online" }, error: null });
    databaseMocks.sourceMaybeSingle.mockResolvedValue({
      data: { id: "source-1", enabled: true, authorized_worker_id: "worker-1" },
      error: null,
    });

    await expect(updateSourceAdministration({
      sourceId: "source-1",
      displayName: "Research community · #daily",
      enabled: true,
      authorizedWorkerId: "worker-1",
    })).resolves.toMatchObject({ id: "source-1", authorized_worker_id: "worker-1" });

    expect(databaseMocks.sourceUpdate).toHaveBeenCalledWith({
      display_name: "Research community · #daily",
      enabled: true,
      authorized_worker_id: "worker-1",
    });
  });

  it("projects an X source as a safe lifecycle card", async () => {
    databaseMocks.sourceListOrder.mockResolvedValue({
      data: [{
        id: "source-x",
        source_type: "x",
        display_name: "AllInvestHK",
        enabled: true,
        archived_at: null,
        workers: { name: "local X worker" },
        x_source_profiles: [{ resolution_status: "pending" }],
        source_collection_coverage: [],
        sync_tasks: [{ status: "succeeded", updated_at: "2026-07-25T01:00:00Z" }],
        local_raw_ref: "must-not-reach-the-card",
      }],
      error: null,
    });

    await expect(listAdminSources({ sourceType: "x", includeArchived: false })).resolves.toEqual([{
      id: "source-x",
      sourceType: "x",
      displayName: "AllInvestHK",
      enabled: true,
      archivedAt: null,
      lifecycle: "identity_pending",
      workerName: "local X worker",
      latestCompletedAt: "2026-07-25T01:00:00Z",
    }]);
    expect(databaseMocks.sourceSelect).toHaveBeenCalledWith(expect.stringContaining("workers(name)"));
    expect(databaseMocks.sourceSelect.mock.calls[0]?.[0]).not.toContain("local_raw_ref");
    expect(databaseMocks.sourceListIs).toHaveBeenCalledWith("archived_at", null);
  });
});

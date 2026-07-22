import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  workerMaybeSingle: vi.fn(),
  sourceMaybeSingle: vi.fn(),
  sourceUpdate: vi.fn(),
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
      return { update: databaseMocks.sourceUpdate };
    },
  }),
}));

import { SourceAdministrationError, updateSourceAdministration } from "./sources";

describe("source administration", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    databaseMocks.sourceUpdate.mockReturnValue({
      eq: () => ({
        select: () => ({ maybeSingle: databaseMocks.sourceMaybeSingle }),
      }),
    });
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
});

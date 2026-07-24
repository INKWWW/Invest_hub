import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import { removeXSource, XSourceError } from "./x-sources";

describe("X source lifecycle repository", () => {
  beforeEach(() => vi.clearAllMocks());

  it("maps only the safe X removal receipt", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: { action: "archived", source_id: "source-x", display_name: "AllInvestHK" },
      error: null,
    });

    await expect(removeXSource({ sourceId: "source-x", actorId: "admin-1", confirmationName: "AllInvestHK" }))
      .resolves.toEqual({ action: "archived", sourceId: "source-x", displayName: "AllInvestHK" });
    expect(databaseMocks.rpc).toHaveBeenCalledWith("remove_x_source", {
      p_source_id: "source-x", p_actor_id: "admin-1", p_confirmation_name: "AllInvestHK",
    });
  });

  it("fails closed for an unknown removal result", async () => {
    databaseMocks.rpc.mockResolvedValue({ data: { action: "purged" }, error: null });

    await expect(removeXSource({ sourceId: "source-x", actorId: "admin-1", confirmationName: "AllInvestHK" }))
      .rejects.toMatchObject({ message: "invalid_x_source_removal" } satisfies Partial<XSourceError>);
  });

  it("preserves the lifecycle conflict code", async () => {
    databaseMocks.rpc.mockResolvedValue({ data: null, error: { message: "source_has_active_task" } });

    await expect(removeXSource({ sourceId: "source-x", actorId: "admin-1", confirmationName: "AllInvestHK" }))
      .rejects.toMatchObject({ message: "source_has_active_task" } satisfies Partial<XSourceError>);
  });
});

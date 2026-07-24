import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  rpc: vi.fn(),
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import { resolveXSourceIdentity } from "./x-identities";

const input = {
  sourceId: "source-1",
  workerId: "worker-1",
  parameterVersion: "v2-identity",
  accountId: "fixture_handle",
};

const receipt = {
  source_id: input.sourceId,
  account_id: input.accountId,
  resolution_status: "resolved",
  parameter_version: input.parameterVersion,
  idempotent: false,
};

describe("X source identity resolution", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it.each([
    ["source", { ...receipt, source_id: "other-source" }],
    ["account", { ...receipt, account_id: "other_handle" }],
    ["parameter version", { ...receipt, parameter_version: "v2-other" }],
  ])("rejects a valid-shaped receipt with a mismatched %s", async (_field, mismatchedReceipt) => {
    databaseMocks.rpc.mockResolvedValue({ data: mismatchedReceipt, error: null });

    await expect(resolveXSourceIdentity(input)).rejects.toMatchObject({
      message: "invalid_x_identity_resolution",
    });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("resolve_x_source_identity", {
      p_source_id: input.sourceId,
      p_worker_id: input.workerId,
      p_parameter_version: input.parameterVersion,
      p_account_id: input.accountId,
    });
  });
});

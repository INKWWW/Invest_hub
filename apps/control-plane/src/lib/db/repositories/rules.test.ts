import { beforeEach, describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({
  rpc: vi.fn(),
}));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import { deriveTargetAuthorIds, replaceSourceRules } from "./rules";

describe("source author rules", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("makes source exclusions win over global and source targets", () => {
    expect(deriveTargetAuthorIds({
      globalTargetAuthorIds: ["global-b", "global-a", "global-a"],
      sourceTargetAuthorIds: ["source-a", "shared"],
      sourceExcludedAuthorIds: ["global-b", "shared"],
    })).toEqual(["global-a", "source-a"]);
  });

  it("normalizes replacement input and returns the incremented database version", async () => {
    databaseMocks.rpc.mockResolvedValue({
      data: { version: 4, target_author_ids: ["global-a", "source-a"] },
      error: null,
    });

    await expect(replaceSourceRules({
      sourceId: "source-1",
      globalTargetAuthorIds: [" global-a ", "global-a"],
      sourceTargetAuthorIds: ["source-a"],
      sourceExcludedAuthorIds: [],
      actorId: "admin-1",
    })).resolves.toEqual({ version: 4, targetAuthorIds: ["global-a", "source-a"] });

    expect(databaseMocks.rpc).toHaveBeenCalledWith("replace_source_author_rules", {
      p_source_id: "source-1",
      p_global_target_author_ids: ["global-a"],
      p_source_target_author_ids: ["source-a"],
      p_source_excluded_author_ids: [],
      p_actor_id: "admin-1",
    });
  });
});

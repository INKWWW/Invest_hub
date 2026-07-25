import { describe, expect, it, vi } from "vitest";

const databaseMocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock("../supabase-server", () => ({
  createSupabaseAdminClient: () => ({ rpc: databaseMocks.rpc }),
}));

import { scheduleDueSourceTasks } from "./tasks";

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
});

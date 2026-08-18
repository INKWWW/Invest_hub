import { beforeEach, describe, expect, it, vi } from "vitest";

const supabaseMocks = vi.hoisted(() => ({
  getUser: vi.fn(),
  maybeSingle: vi.fn(),
}));

vi.mock("../db/supabase-server", () => ({
  createSupabaseServerClient: vi.fn(async () => ({
    auth: { getUser: supabaseMocks.getUser },
    from: () => ({
      select: () => ({
        eq: () => ({ maybeSingle: supabaseMocks.maybeSingle }),
      }),
    }),
  })),
}));

import { getCurrentUser } from "./current-user";

describe("current user Profile boundary", () => {
  beforeEach(() => vi.clearAllMocks());

  it("fails closed when Auth has no matching Profile", async () => {
    supabaseMocks.getUser.mockResolvedValue({
      data: { user: { id: "orphan-user", email: "orphan@example.invalid" } },
      error: null,
    });
    supabaseMocks.maybeSingle.mockResolvedValue({ data: null, error: null });

    await expect(getCurrentUser()).resolves.toBeNull();
  });

  it("fails closed when the Profile lookup errors", async () => {
    supabaseMocks.getUser.mockResolvedValue({
      data: { user: { id: "orphan-user", email: "orphan@example.invalid" } },
      error: null,
    });
    supabaseMocks.maybeSingle.mockResolvedValue({ data: null, error: new Error("database failure") });

    await expect(getCurrentUser()).resolves.toBeNull();
  });
});

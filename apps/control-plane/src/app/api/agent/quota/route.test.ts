import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const quotaMocks = vi.hoisted(() => ({ getResearchQuota: vi.fn() }));

vi.mock("../../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../../lib/db/repositories/research-quota", () => quotaMocks);

import { GET } from "./route";

describe("GET /api/agent/quota", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    quotaMocks.getResearchQuota.mockResolvedValue({
      ownerId: "user-one",
      lifetimeUnits: 8,
      reservedUnits: 1,
      settledUnits: 3,
      availableUnits: 4,
      updatedAt: "2099-01-01T00:00:00.000Z",
    });
  });

  it("returns the authoritative balance for the authenticated user", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({
      quota: {
        lifetime_units: 8,
        available_units: 4,
        reserved_units: 1,
        settled_units: 3,
        updated_at: "2099-01-01T00:00:00.000Z",
      },
    });
    expect(quotaMocks.getResearchQuota).toHaveBeenCalledWith("user-one");
  });

  it("does not expose quota data without an authenticated session", async () => {
    authMocks.getCurrentUser.mockResolvedValue(null);
    const response = await GET();
    expect(response.status).toBe(401);
    expect(await response.json()).toEqual({ error: "unauthorized" });
    expect(quotaMocks.getResearchQuota).not.toHaveBeenCalled();
  });
});

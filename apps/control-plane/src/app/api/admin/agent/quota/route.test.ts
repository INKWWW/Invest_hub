import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ requireRole: vi.fn(), isCurrentUser: vi.fn((value: unknown) => !(value instanceof Response)) }));
const quotaMocks = vi.hoisted(() => ({ listResearchQuotasForAdmin: vi.fn(), adjustResearchQuota: vi.fn() }));

vi.mock("../../../../../lib/auth/require-role", () => authMocks);
vi.mock("../../../../../lib/db/repositories/research-quota", () => quotaMocks);

import { GET, PATCH } from "./route";

const admin = { id: "admin-one", email: "admin@example.invalid", role: "admin" as const };

function jsonRequest(body: unknown, method = "PATCH") {
  return new Request("http://localhost/api/admin/agent/quota", {
    method,
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
}

describe("/api/admin/agent/quota", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.requireRole.mockResolvedValue(admin);
    quotaMocks.listResearchQuotasForAdmin.mockResolvedValue([{
      ownerId: "user-one",
      displayName: "Agent One",
      email: "one@example.invalid",
      lifetimeUnits: 8,
      availableUnits: 8,
      reservedUnits: 0,
      settledUnits: 0,
      updatedAt: "2099-01-01T00:00:00.000Z",
    }]);
    quotaMocks.adjustResearchQuota.mockResolvedValue({
      ownerId: "user-one",
      lifetimeUnits: 10,
      reservedUnits: 0,
      settledUnits: 0,
      availableUnits: 10,
      updatedAt: "2099-01-01T00:00:01.000Z",
    });
  });

  it("lists user balances only through the administrator path", async () => {
    const response = await GET();
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ quotas: [{
      owner_id: "user-one",
      display_name: "Agent One",
      email: "one@example.invalid",
      lifetime_units: 8,
      available_units: 8,
      reserved_units: 0,
      settled_units: 0,
      updated_at: "2099-01-01T00:00:00.000Z",
    }] });
    expect(quotaMocks.listResearchQuotasForAdmin).toHaveBeenCalledWith("admin-one");
  });

  it("rejects malformed or incomplete adjustments before persistence", async () => {
    const response = await PATCH(jsonRequest({ owner_id: "user-one", lifetime_units: -1 }));
    expect(response.status).toBe(422);
    expect(await response.json()).toEqual({ error: "invalid_quota_adjustment" });
    expect(quotaMocks.adjustResearchQuota).not.toHaveBeenCalled();
  });

  it("records the real administrator as the actor for an adjustment", async () => {
    const response = await PATCH(jsonRequest({
      owner_id: "00000000-0000-4000-8000-000000000001",
      lifetime_units: 10,
      reason: "为测试身份分配额度",
    }));
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ quota: {
      owner_id: "user-one",
      lifetime_units: 10,
      available_units: 10,
      reserved_units: 0,
      settled_units: 0,
      updated_at: "2099-01-01T00:00:01.000Z",
    } });
    expect(quotaMocks.adjustResearchQuota).toHaveBeenCalledWith({
      ownerId: "00000000-0000-4000-8000-000000000001",
      lifetimeUnits: 10,
      reason: "为测试身份分配额度",
    });
  });

  it("does not let ordinary users enumerate or adjust balances", async () => {
    authMocks.requireRole.mockResolvedValue(new Response(JSON.stringify({ error: "forbidden" }), { status: 403 }));
    authMocks.isCurrentUser.mockReturnValue(false);
    const response = await GET();
    expect(response.status).toBe(403);
    expect(quotaMocks.listResearchQuotasForAdmin).not.toHaveBeenCalled();
  });
});

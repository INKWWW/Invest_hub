import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const quotaMocks = vi.hoisted(() => ({ listResearchQuotasForAdmin: vi.fn() }));
const navigationMocks = vi.hoisted(() => ({ redirect: vi.fn((value: string) => { throw new Error(`redirect:${value}`); }) }));

vi.mock("../../../lib/auth/current-user", () => authMocks);
vi.mock("../../../lib/db/repositories/research-quota", () => quotaMocks);
vi.mock("next/navigation", () => navigationMocks);

import AdminAgentPage from "./page";

describe("AdminAgentPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-one", email: "admin@example.invalid", role: "admin" });
    quotaMocks.listResearchQuotasForAdmin.mockResolvedValue([{
      ownerId: "user-one",
      displayName: "Agent One",
      email: "one@example.invalid",
      lifetimeUnits: 8,
      availableUnits: 6,
      reservedUnits: 1,
      settledUnits: 1,
      updatedAt: "2099-01-01T00:00:00.000Z",
    }]);
  });

  it("renders the administrator quota area while its navigation entry stays hidden", async () => {
    const html = renderToStaticMarkup(await AdminAgentPage());
    expect(html).toContain("研究额度");
    expect(html).toContain("Agent One");
    expect(html).toContain("可用");
    expect(html).toContain("保存额度");
    expect(quotaMocks.listResearchQuotasForAdmin).toHaveBeenCalledWith("admin-one");
  });

  it("fails closed before service-role data access for an ordinary user", async () => {
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-one", email: "one@example.invalid", role: "user" });
    await expect(AdminAgentPage()).rejects.toThrow("redirect:/forbidden");
    expect(quotaMocks.listResearchQuotasForAdmin).not.toHaveBeenCalled();
  });
});

import { describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({
  isCurrentUser: vi.fn(),
  requireRole: vi.fn(),
}));
const navigationMocks = vi.hoisted(() => ({ redirect: vi.fn() }));

vi.mock("../../lib/auth/require-role", () => authMocks);
vi.mock("next/navigation", () => navigationMocks);

import AdminLayout from "./layout";

describe("AdminLayout", () => {
  it("sends an authenticated ordinary user to an explicit access-denied page", async () => {
    authMocks.requireRole.mockResolvedValue({ status: 403 });
    authMocks.isCurrentUser.mockReturnValue(false);

    await AdminLayout({ children: <p>Admin content</p> });

    expect(navigationMocks.redirect).toHaveBeenCalledWith("/forbidden");
  });
});

import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));

vi.mock("../../../lib/auth/current-user", () => authMocks);

import ForbiddenPage from "./page";

describe("ForbiddenPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "user-1", email: "user@example.invalid", role: "user" });
  });

  it("explains the administrator boundary and gives an ordinary user a safe account-switch action", async () => {
    const page = await ForbiddenPage();
    const html = renderToStaticMarkup(page);

    expect(html).toContain("仅限管理员");
    expect(html).toContain("返回 Discord 日度研判");
    expect(html).toContain('data-testid="session-controls"');
    expect(html).toContain("user@example.invalid");
  });
});

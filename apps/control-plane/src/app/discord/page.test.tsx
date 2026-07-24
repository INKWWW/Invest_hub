import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readDiscordDay: vi.fn() }));
const sourceMocks = vi.hoisted(() => ({ listSources: vi.fn() }));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);
vi.mock("../../lib/db/repositories/sources", () => sourceMocks);

import DiscordPage from "./page";

describe("DiscordPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "admin-1", email: "admin@example.invalid", role: "admin" });
    readerMocks.readDiscordDay.mockResolvedValue([]);
    sourceMocks.listSources.mockResolvedValue([]);
  });

  it("shows the current account and a session switch action in the reader header", async () => {
    const page = await DiscordPage();
    const html = renderToStaticMarkup(page);

    expect(html).toContain('data-testid="session-controls"');
    expect(html).toContain("admin@example.invalid");
    expect(html).toContain("管理员");
    expect(html).toContain("退出 / 切换账号");
  });

  it("places the source switcher between account information and the page title", async () => {
    const page = await DiscordPage();
    const html = renderToStaticMarkup(page);

    expect(html.indexOf("信息来源")).toBeLessThan(html.indexOf("Discord 日度研判"));
    expect(html).not.toContain("按频道和日期阅读已生成的观点与话题。");
  });
});

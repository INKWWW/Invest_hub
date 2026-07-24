import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readXDay: vi.fn() }));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);

import XPage from "./page";

describe("XPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "reader-1", email: "reader@example.invalid", role: "reader" });
    readerMocks.readXDay.mockResolvedValue([]);
  });

  it("keeps the source switcher as its own navigation level before the X page title", async () => {
    const page = await XPage();
    const html = renderToStaticMarkup(page);

    expect(html.indexOf("信息来源")).toBeLessThan(html.indexOf("X 信息采集"));
    expect(html).not.toContain("按博主和日期阅读每日综合观点");
  });
});

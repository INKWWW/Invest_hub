import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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

  afterEach(() => vi.useRealTimers());

  it("keeps the source switcher as its own navigation level before the X page title", async () => {
    const page = await XPage();
    const html = renderToStaticMarkup(page);

    expect(html.indexOf("信息来源")).toBeLessThan(html.indexOf("X 信息采集"));
    expect(html).not.toContain("按博主和日期阅读每日综合观点");
  });

  it("restores blogger and date selections from the reader URL", async () => {
    readerMocks.readXDay.mockResolvedValue([{ source: { sourceKey: "first", displayName: "First Author" }, naturalDate: "2099-01-01", status: "succeeded", segments: [] }, {
      source: { sourceKey: "second", displayName: "Second Author" }, naturalDate: "2099-01-02", status: "succeeded", segments: [],
    }]);

    const page = await XPage({ searchParams: Promise.resolve({ source: "second", date: "2099-01-02" }) } as never);
    const html = renderToStaticMarkup(page);

    expect(html).toContain("Second Author");
    expect(html).not.toContain("<strong>First Author</strong>");
  });

  it("defaults to the current Shanghai date even before that date has content", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-27T16:30:00.000Z"));
    readerMocks.readXDay.mockResolvedValue([{
      source: { sourceKey: "first", displayName: "First Author" }, naturalDate: "2026-07-27", status: "succeeded", segments: [],
    }]);

    const page = await XPage();
    const html = renderToStaticMarkup(page);

    expect(html).toContain('<option value="2026-07-28" selected="">2026-07-28</option>');
    expect(html).toContain("没有找到符合当前博主和日期筛选的 X 信息。");
  });
});

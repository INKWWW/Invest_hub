import { renderToStaticMarkup } from "react-dom/server";
import { beforeEach, describe, expect, it, vi } from "vitest";

const authMocks = vi.hoisted(() => ({ getCurrentUser: vi.fn() }));
const readerMocks = vi.hoisted(() => ({ readXDay: vi.fn() }));

vi.mock("../../lib/auth/current-user", () => authMocks);
vi.mock("../../lib/db/repositories/reader", () => readerMocks);

import XPage from "./page";

const days = [{
  naturalDate: "2026-07-28", judgement: { visible: true, batches: [] },
  bloggers: [{ source: { sourceKey: "second", displayName: "Second Author" }, status: "succeeded", segments: [] }],
}];

describe("XPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    authMocks.getCurrentUser.mockResolvedValue({ id: "reader-1", email: "reader@example.invalid", role: "reader" });
    readerMocks.readXDay.mockResolvedValue([]);
  });

  it("keeps the source switcher as its own navigation level before the X page title", async () => {
    const page = await XPage({});
    const html = renderToStaticMarkup(page);

    expect(html.indexOf("信息来源")).toBeLessThan(html.indexOf("X 信息采集"));
  });

  it("hydrates a valid shared date even when that date currently has no content", async () => {
    readerMocks.readXDay.mockResolvedValue(days);

    const page = await XPage({ searchParams: Promise.resolve({ source: "second", date: "2026-07-26" }) } as never);
    const html = renderToStaticMarkup(page);

    expect(html).toContain('<option value="second" selected="">Second Author</option>');
    expect(html).toContain('<option value="2026-07-26" selected="">2026-07-26</option>');
    expect(html).toContain("没有找到符合当前博主和日期筛选的 X 信息。");
  });

  it("defaults to all dates and ignores malformed or impossible date queries", async () => {
    readerMocks.readXDay.mockResolvedValue(days);

    const defaultPage = await XPage({});
    const malformedPage = await XPage({ searchParams: Promise.resolve({ date: "2026-7-28" }) } as never);
    const impossiblePage = await XPage({ searchParams: Promise.resolve({ date: "2099-02-29" }) } as never);
    const defaultHtml = renderToStaticMarkup(defaultPage);
    const malformedHtml = renderToStaticMarkup(malformedPage);
    const impossibleHtml = renderToStaticMarkup(impossiblePage);

    expect(defaultHtml).toContain('<option value="all" selected="">全部</option>');
    expect(defaultHtml).not.toContain('value="2026-08-01" selected=""');
    expect(malformedHtml).toContain('<option value="all" selected="">全部</option>');
    expect(malformedHtml).not.toContain('value="2026-7-28"');
    expect(impossibleHtml).toContain('<option value="all" selected="">全部</option>');
    expect(impossibleHtml).not.toContain('value="2099-02-29"');
  });
});

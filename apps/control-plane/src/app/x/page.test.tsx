import { renderToStaticMarkup } from "react-dom/server";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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

  afterEach(() => vi.useRealTimers());

  it("keeps the source switcher as its own navigation level before the X page title", async () => {
    const page = await XPage({});
    const html = renderToStaticMarkup(page);

    expect(html.indexOf("信息来源")).toBeLessThan(html.indexOf("X 信息采集"));
  });

  it("restores a blogger selector and resets a stale date to the current Shanghai date", async () => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date("2026-07-27T16:30:00.000Z"));
    readerMocks.readXDay.mockResolvedValue(days);

    const page = await XPage({ searchParams: Promise.resolve({ source: "second", date: "2026-07-26" }) } as never);
    const html = renderToStaticMarkup(page);

    expect(html).toContain('<option value="second" selected="">Second Author</option>');
    expect(html).toContain('<option value="2026-07-28" selected="">2026-07-28</option>');
    expect(html).not.toContain('<option value="2026-07-26" selected="">');
  });
});

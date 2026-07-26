import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { XReader } from "./XReader";

describe("XReader", () => {
  it("defaults to all authors and dates while keeping each author-day in safe evidence", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      source: { sourceKey: "fixture", displayName: "Fixture Author" }, naturalDate: "2099-01-01", status: "succeeded",
      segments: [{ id: "segment-safe", occurredThroughAt: "2099-01-01T12:00:00.000Z", viewpoints: ["每日观点"], uncertainties: ["不确定"], analyses: [{ postId: "post-private", postLink: "https://x.com/fixture/status/1", bloggerViewpoint: "博主判断", arguments: ["可见论据"], quotedPostViewpoint: "引用观点", uncertainties: [] }], }],
    }, {
      source: { sourceKey: "second", displayName: "Second Author" }, naturalDate: "2099-01-02", status: "succeeded",
      segments: [{ id: "segment-second", occurredThroughAt: "2099-01-02T12:00:00.000Z", viewpoints: ["第二位博主的观点"], uncertainties: [], analyses: [] }],
    }] as never} />);
    expect(html).toContain('<option value="all" selected="">全部</option>');
    expect(html).toContain("每日综合观点");
    expect(html).toContain("Fixture Author");
    expect(html).toContain("Second Author");
    expect(html).toContain("截止 2099-01-01 20:00，已更新。");
    expect(html).toContain("截止 2099-01-02 20:00，已更新。");
    expect(html).toContain("每日观点");
    expect(html).toContain("第二位博主的观点");
    expect(html).toContain("证据明细");
    expect(html).toContain("原始 X 帖子");
    expect(html).toContain("<details class=\"x-evidence\">");
    expect(html).not.toContain("第 1 次增量");
    for (const forbidden of ["post-private", "local_raw_ref", "canonical_messages", "worker", "prompt", "provider", "raw body"]) expect(html).not.toContain(forbidden);
  });

  it("uses the requested blogger and date together without combining authors", () => {
    const days = [{
      source: { sourceKey: "fixture", displayName: "Fixture Author" }, naturalDate: "2099-01-01", status: "succeeded",
      segments: [{ id: "fixture-segment", occurredThroughAt: "2099-01-01T12:00:00.000Z", viewpoints: ["首位博主观点"], uncertainties: [], analyses: [] }],
    }, {
      source: { sourceKey: "second", displayName: "Second Author" }, naturalDate: "2099-01-02", status: "succeeded",
      segments: [{ id: "second-segment", occurredThroughAt: "2099-01-02T12:00:00.000Z", viewpoints: ["第二位博主观点"], uncertainties: [], analyses: [] }],
    }];
    const html = renderToStaticMarkup(<XReader {...({ days, initialSourceKey: "second", initialNaturalDate: "2099-01-02" } as never)} />);

    expect(html).toContain("Second Author");
    expect(html).toContain("第二位博主观点");
    expect(html).not.toContain("<strong>Fixture Author</strong>");
    expect(html).not.toContain("首位博主观点");
  });
});

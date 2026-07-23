import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { XReader } from "./XReader";

describe("XReader", () => {
  it("defaults to viewpoint content and keeps per-post analysis in collapsed safe evidence", () => {
    const html = renderToStaticMarkup(<XReader days={[{
      source: { sourceKey: "fixture", displayName: "Fixture Author" }, naturalDate: "2099-01-01", status: "succeeded",
      segments: [{ id: "segment-safe", viewpoints: ["每日观点"], uncertainties: ["不确定"], analyses: [{ postId: "post-private", postLink: "https://x.com/fixture/status/1", bloggerViewpoint: "博主判断", arguments: ["可见论据"], quotedPostViewpoint: "引用观点", uncertainties: [] }], }],
    }] as never} />);
    expect(html).toContain("每日综合观点");
    expect(html).toContain("每日观点");
    expect(html).toContain("证据明细");
    expect(html).toContain("原始 X 帖子");
    expect(html).toContain("<details class=\"x-evidence\">");
    for (const forbidden of ["post-private", "local_raw_ref", "canonical_messages", "worker", "prompt", "provider", "raw body"]) expect(html).not.toContain(forbidden);
  });
});

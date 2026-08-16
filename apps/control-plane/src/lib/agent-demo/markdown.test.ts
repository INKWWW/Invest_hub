import { describe, expect, it } from "vitest";

import { parseSafeMarkdown } from "./markdown";

describe("safe Demo Markdown", () => {
  it("keeps headings, lists and code as structured blocks", () => {
    expect(parseSafeMarkdown("# 标题\n\n- 一\n- 二\n\n```txt\nconst x = 1\n```")).toEqual([
      { kind: "heading", level: 1, inlines: [{ kind: "text", value: "标题" }] },
      { kind: "list", ordered: false, items: [[{ kind: "text", value: "一" }], [{ kind: "text", value: "二" }]] },
      { kind: "code", value: "const x = 1" },
    ]);
  });

  it("allows only HTTPS links and never returns raw HTML", () => {
    const blocks = parseSafeMarkdown("[年报](https://example.com/report) [危险](javascript:alert(1)) <script>alert(1)</script>");
    expect(blocks[0]).toMatchObject({ kind: "paragraph" });
    expect(JSON.stringify(blocks)).toContain("https://example.com/report");
    expect(JSON.stringify(blocks)).toContain("javascript:alert(1)");
    expect(JSON.stringify(blocks)).toContain("<script>alert(1)</script>");
    expect(blocks[0]).not.toMatchObject({ kind: "link", href: "javascript:alert(1)" });
  });
});

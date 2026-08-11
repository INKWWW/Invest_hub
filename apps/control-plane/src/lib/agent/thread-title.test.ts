import { describe, expect, it } from "vitest";

import { automaticThreadTitle } from "./thread-title";

describe("automaticThreadTitle", () => {
  it("creates a short readable title from the first plain-text message", () => {
    expect(automaticThreadTitle("请帮我研究宁德时代的海外竞争格局和估值"))
      .toBe("宁德时代的海外竞争格局和估值");
  });

  it("collapses whitespace and never returns an unbounded title", () => {
    const title = automaticThreadTitle("  研究   美股 ETF 的长期配置价值。  ");
    expect(title).toBe("研究 美股 ETF 的长期配置价值。");
    expect(title.length).toBeLessThanOrEqual(40);
  });

  it("falls back to a neutral title for blank input", () => {
    expect(automaticThreadTitle(" \n\t ")).toBe("新研究会话");
  });
});

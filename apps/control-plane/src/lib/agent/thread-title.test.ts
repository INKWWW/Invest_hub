import { describe, expect, it } from "vitest";

import { automaticThreadTitle, automaticThreadTitleUpdate } from "./thread-title";

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

  it("returns a conditional storage update only for populated default threads", () => {
    expect(automaticThreadTitleUpdate("新研究会话", "近期 GOOGL 的表现如何？")).toBe("近期 GOOGL 的表现如何？");
    expect(automaticThreadTitleUpdate("我的重点公司", "近期 GOOGL 的表现如何？")).toBeNull();
    expect(automaticThreadTitleUpdate("新研究会话", " ")).toBeNull();
  });
});

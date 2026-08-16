import { describe, expect, it } from "vitest";

import {
  GENERAL_PRODUCT_INSTRUCTION_VERSION,
  buildGeneralPrompt,
  validateGeneralAnswer,
} from "./general-answer";

describe("Demo general-answer contract", () => {
  it("includes the complete ordered Thread history and versioned product instruction", () => {
    const prompt = buildGeneralPrompt([
      { role: "user", content: "研究公司" },
      { role: "assistant", content: "第一轮回答" },
    ], "继续比较风险");
    expect(prompt).toContain(GENERAL_PRODUCT_INSTRUCTION_VERSION);
    expect(prompt.indexOf("研究公司")).toBeLessThan(prompt.indexOf("第一轮回答"));
    expect(prompt).toContain("继续比较风险");
    expect(prompt).not.toContain("case_name");
  });

  it("accepts resolvable sources and evidence-bound advice", () => {
    const result = validateGeneralAnswer({
      markdown: "## 结论\n\n基于年报，若估值条件满足，可考虑分批建仓。\n\nAI投资建议，仅供参考。\n\n来源：[src-1]",
      sources: [{ id: "src-1", title: "年度报告", publisher: "公司", date: "2024-03-01", url: "https://example.com/report" }],
      contains_investment_advice: true,
    });
    expect(result.markdown).toContain("AI投资建议，仅供参考。");
  });

  it("rejects an advice result without a resolvable source or disclaimer", () => {
    expect(() => validateGeneralAnswer({ markdown: "建议加仓。", sources: [], contains_investment_advice: true })).toThrow("invalid_general_answer");
    expect(() => validateGeneralAnswer({ markdown: "建议加仓。来源：[src-1]", sources: [{ id: "src-1", title: "报告", publisher: "公司", date: "2024-03-01", url: "https://example.com" }], contains_investment_advice: true })).toThrow("invalid_general_answer");
  });

  it("does not silently truncate an overlong Thread", () => {
    expect(() => buildGeneralPrompt(Array.from({ length: 101 }, () => ({ role: "user" as const, content: "问题" })), "新问题")).toThrow("thread_context_too_long");
  });
});

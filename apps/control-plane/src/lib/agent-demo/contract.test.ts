import { describe, expect, it } from "vitest";

import {
  DemoRunStateError,
  acceptDemoMessage,
  completeDemoRun,
  validateDemoMessage,
} from "./contract";

describe("agent demo contract", () => {
  it("accepts every trimmed non-empty message up to 20000 characters without semantic prefiltering", () => {
    expect(validateDemoMessage("  crypto, weather, and a nonsense asset?  ")).toBe("crypto, weather, and a nonsense asset?");
    expect(validateDemoMessage("x".repeat(20000))).toHaveLength(20000);
  });

  it("rejects only transport-invalid message values", () => {
    expect(() => validateDemoMessage(" ")).toThrow("invalid_message");
    expect(() => validateDemoMessage("x".repeat(20001))).toThrow("invalid_message");
    expect(() => validateDemoMessage(42 as unknown as string)).toThrow("invalid_message");
  });

  it("transitions one accepted run to a sanitized assistant Markdown result", () => {
    const run = acceptDemoMessage({
      ownerId: "user-one",
      threadId: "thread-one",
      requestId: "request-one",
      question: "研究宁德时代",
    });
    expect(run.status).toBe("queued");
    const completed = completeDemoRun(run, {
      content: "# 研究结论\n\n基于公开资料。",
      provider: "scripted",
    });
    expect(completed.status).toBe("succeeded");
    expect(completed.assistantContent).toContain("# 研究结论");
    expect(completed.assistantContent).not.toContain("/Users/");
  });

  it("does not complete a run twice", () => {
    const run = acceptDemoMessage({ ownerId: "user-one", threadId: "thread-one", requestId: "request-one", question: "研究" });
    const completed = completeDemoRun(run, { content: "完成", provider: "scripted" });
    expect(() => completeDemoRun(completed, { content: "再次完成", provider: "scripted" })).toThrow(DemoRunStateError);
  });
});

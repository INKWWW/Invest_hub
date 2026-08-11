import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ResearchAgentShell } from "./ResearchAgentShell";

const threads = [
  { id: "thread-today", title: "今天的研究", createdAt: "2099-01-02T09:00:00.000Z", updatedAt: "2099-01-02T09:00:00.000Z" },
  { id: "thread-yesterday", title: "昨天的研究", createdAt: "2099-01-01T09:00:00.000Z", updatedAt: "2099-01-01T09:00:00.000Z" },
];

describe("ResearchAgentShell", () => {
  it("renders the A workbench hierarchy with a mobile drawer trigger", () => {
    const html = renderToStaticMarkup(<ResearchAgentShell initialThreads={threads} />);
    expect(html).toContain('data-testid="agent-workbench"');
    expect(html).toContain('aria-label="研究会话列表"');
    expect(html).toContain('aria-label="打开研究会话列表"');
    expect(html).toContain('data-testid="thread-group"');
    expect(html).toContain("今天的研究");
    expect(html).toContain("昨天的研究");
    expect(html).toContain('data-testid="agent-composer"');
    expect(html).toContain("研究执行暂未开放");
  });

  it("does not expose deferred tools or management affordances in the chat shell", () => {
    const html = renderToStaticMarkup(<ResearchAgentShell initialThreads={[]} />);
    for (const forbidden of ["搜索", "文件夹", "收藏", "分支", "Regenerate", "上传", "技术画线分析", "Quota", "Research Progress"]) {
      expect(html).not.toContain(forbidden);
    }
  });
});

import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { mapThread, mapThreadDetail, ResearchAgentShell } from "./ResearchAgentShell";

const threads = [
  { id: "thread-today", title: "今天的研究", createdAt: "2099-01-02T09:00:00.000Z", updatedAt: "2099-01-02T09:00:00.000Z" },
  { id: "thread-yesterday", title: "昨天的研究", createdAt: "2099-01-01T09:00:00.000Z", updatedAt: "2099-01-01T09:00:00.000Z" },
];

describe("ResearchAgentShell", () => {
  it("normalizes the snake_case API contract before rendering client state", () => {
    const thread = mapThread({
      id: "thread-one",
      title: "研究会话",
      created_at: "2099-01-01T00:00:00.000Z",
      updated_at: "2099-01-01T00:00:01.000Z",
    });
    const detail = mapThreadDetail({
      ...thread,
      created_at: thread.createdAt,
      updated_at: thread.updatedAt,
      messages: [{ id: "message-one", role: "user", content: "研究", created_at: "2099-01-01T00:00:02.000Z" }],
      artifacts: [],
    });
    expect(thread.updatedAt).toBe("2099-01-01T00:00:01.000Z");
    expect(detail.messages[0]?.createdAt).toBe("2099-01-01T00:00:02.000Z");
  });

  it("renders the A workbench hierarchy with a mobile drawer trigger", () => {
    const html = renderToStaticMarkup(<ResearchAgentShell initialThreads={threads} />);
    expect(html).toContain('data-testid="agent-workbench"');
    expect(html).toContain('aria-label="研究会话列表"');
    expect(html).toContain('aria-label="打开研究会话列表"');
    expect(html).toContain('data-testid="thread-group"');
    expect(html).toContain("今天的研究");
    expect(html).toContain("昨天的研究");
    expect(html).toContain('data-testid="agent-composer"');
    expect(html).toContain('data-testid="agent-message-list"');
    expect(html).toContain("发送问题");
    expect(html).toContain('class="agent-skill-picker"');
    expect(html).toContain("大师投研");
    expect(html).toContain("持仓组合分析");
    expect(html).toContain("下单前巴菲特拷问");
    expect(html).toContain('aria-pressed="true">智能</button>');
    expect(html).toContain('class="agent-composer-editor"');
    expect(html).not.toContain("已选择 Skill");
    expect(html).not.toContain("当前只提供私有 Thread 与纯文本消息保存");
    expect(html).not.toContain("本地 Demo Runner");
    expect(html).not.toContain("消息会持久化到当前 Research Thread");
    expect(html).not.toContain("研究额度");
    expect(html).not.toContain("Research Quota");
  });

  it("does not expose deferred tools or management affordances in the chat shell", () => {
    const html = renderToStaticMarkup(<ResearchAgentShell initialThreads={[]} />);
    for (const forbidden of ["搜索", "文件夹", "收藏", "分支", "Regenerate", "上传", "技术画线分析", "Research Progress"]) {
      expect(html).not.toContain(forbidden);
    }
  });
});

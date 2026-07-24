import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import type { AdminSourceCard } from "../../lib/db/repositories/sources";
import { SourceConfigurationCard } from "./SourceConfigurationCard";
import { SourceConfigurationWorkspace } from "./SourceConfigurationWorkspace";

const discord: AdminSourceCard = {
  id: "discord-private-id", sourceType: "discord", displayName: "研究社区 · #美股讨论", enabled: true,
  archivedAt: null, lifecycle: "coverage_uninitialized", workerName: "discord-worker", latestCompletedAt: null,
};
const x: AdminSourceCard = {
  id: "x-private-id", sourceType: "x", displayName: "AllInvestHK", enabled: true,
  archivedAt: null, lifecycle: "identity_pending", workerName: null, latestCompletedAt: "2026-07-25T00:00:00Z",
};

describe("SourceConfigurationWorkspace", () => {
  it("separates Discord and X controls without rendering a configuration table", () => {
    const html = renderToStaticMarkup(<SourceConfigurationWorkspace
      discordSources={[discord]}
      xSources={[x]}
      initialSourceType="discord"
      discordCreateForm={<p>Discord creation</p>}
      xCreateForm={<p>X creation</p>}
      discordDetails={{ [discord.id]: <p>Discord detail</p> }}
      xDetails={{ [x.id]: <p>X detail</p> }}
    />);

    expect(html).toContain('role="tablist"');
    expect(html).toContain('role="tab"');
    expect(html).toContain("Discord 配置 · 1");
    expect(html).toContain("X 配置 · 1");
    expect(html).toContain('aria-selected="true"');
    expect(html).toContain("Discord creation");
    expect(html).not.toContain("X creation");
    expect(html).not.toContain("<table");
  });

  it("uses lifecycle facts and safe display fields on a source card", () => {
    const html = renderToStaticMarkup(<SourceConfigurationCard source={x} selected={false} onManage={() => {}} />);

    expect(html).toContain("身份验证");
    expect(html).toContain('data-state="current">身份验证');
    expect(html).toContain("初始化覆盖");
    expect(html).toContain("更新与回填");
    expect(html).toContain("任一已注册 Worker");
    expect(html).not.toContain("x-private-id");
    expect(html).not.toContain("%");
  });
});

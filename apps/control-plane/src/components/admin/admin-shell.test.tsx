import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { AdminShell } from "./AdminShell";

describe("AdminShell", () => {
  it("renders only the four safe admin navigation destinations and the current admin session", () => {
    const html = renderToStaticMarkup(
      <AdminShell active="sources" viewer={{ email: "admin@example.invalid", role: "admin" }}><p>Sources</p></AdminShell>,
    );

    expect(html).toContain('href="/admin"');
    expect(html).toContain('href="/admin/sources"');
    expect(html).toContain('href="/admin/tasks"');
    expect(html).toContain('href="/admin/workers"');
    expect(html).toContain('aria-current="page"');
    expect(html).toContain('data-testid="session-controls"');
    expect(html).toContain("admin@example.invalid");
    expect(html).toContain("管理员");
    expect(html).toContain("退出 / 切换账号");
    expect(html).not.toContain("channel_url");
    expect(html).not.toContain("profile_ref");
    expect(html).not.toContain("prompt");
  });
});

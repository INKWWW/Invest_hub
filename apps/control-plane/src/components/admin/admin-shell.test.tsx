import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { AdminShell } from "./AdminShell";

describe("AdminShell", () => {
  it("renders only the four safe admin navigation destinations", () => {
    const html = renderToStaticMarkup(<AdminShell active="sources"><p>Sources</p></AdminShell>);

    expect(html).toContain('href="/admin"');
    expect(html).toContain('href="/admin/sources"');
    expect(html).toContain('href="/admin/tasks"');
    expect(html).toContain('href="/admin/workers"');
    expect(html).toContain('aria-current="page"');
    expect(html).not.toContain("channel_url");
    expect(html).not.toContain("profile_ref");
    expect(html).not.toContain("prompt");
  });
});

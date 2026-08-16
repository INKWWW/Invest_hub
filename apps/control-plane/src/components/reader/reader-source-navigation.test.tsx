import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ReaderSourceNavigation } from "./ReaderSourceNavigation";

describe("ReaderSourceNavigation", () => {
  it("keeps Agent, Discord, and X as peer destinations with one active page", () => {
    const discord = renderToStaticMarkup(<ReaderSourceNavigation active="discord" />);
    const x = renderToStaticMarkup(<ReaderSourceNavigation active="x" />);
    const agent = renderToStaticMarkup(<ReaderSourceNavigation active="agent" />);
    expect(agent).toContain('href="/agent"');
    expect(agent).toContain("投资研究 Agent");
    expect(agent).toContain('href="/agent" aria-current="page"');
    expect(discord).toContain('href="/discord"');
    expect(discord).toContain('href="/x"');
    expect(discord).toContain("Discord 信息-WIP");
    expect(discord).toContain('href="/discord" aria-current="page"');
    expect(discord).not.toContain('href="/agent" aria-current="page"');
    expect(x).toContain('href="/x" aria-current="page"');
    expect(x).not.toContain('href="/discord" aria-current="page"');
    expect(discord).not.toContain('<p class="reader-source-label">');
    expect(discord).not.toContain("admin");
    expect(x).not.toContain("sourceKey");
  });
});

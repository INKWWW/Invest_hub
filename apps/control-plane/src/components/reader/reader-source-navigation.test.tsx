import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";

import { ReaderSourceNavigation } from "./ReaderSourceNavigation";

describe("ReaderSourceNavigation", () => {
  it("keeps Discord and X as reader-only destinations with one active page", () => {
    const discord = renderToStaticMarkup(<ReaderSourceNavigation active="discord" />);
    const x = renderToStaticMarkup(<ReaderSourceNavigation active="x" />);
    expect(discord).toContain('href="/discord"');
    expect(discord).toContain('href="/x"');
    expect(discord).toContain("Discord 信息-WIP");
    expect(discord).toContain('href="/discord" aria-current="page"');
    expect(x).toContain('href="/x" aria-current="page"');
    expect(x).not.toContain('href="/discord" aria-current="page"');
    expect(discord).not.toContain('<p class="reader-source-label">');
    expect(discord).not.toContain("admin");
    expect(x).not.toContain("sourceKey");
  });
});

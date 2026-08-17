import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./globals.css", import.meta.url), "utf8");

describe("reader header visual hierarchy", () => {
  it("keeps the reader header undecorated and uses the approved responsive type scale", () => {
    expect(css).toMatch(/\.reader-page-header\s*\{[^}]*border-left:\s*0;[^}]*padding:\s*0;/s);
    expect(css).toMatch(/\.product-mark\s*\{[^}]*font-size:\s*clamp\(2rem, 5\.2vw, 2\.5rem\);/s);
    expect(css).toMatch(/\.reader-page-header h1, \.auth-card h1\s*\{[^}]*font-size:\s*clamp\(1\.5625rem, 3vw, 2\.25rem\);/s);
    expect(css).toMatch(/\.session-controls button\s*\{[^}]*font-size:\s*0\.625rem;/s);
  });
});

describe("X Reader category and evidence styling", () => {
  it("defines semantic category modules and a prominent responsive heading", () => {
    expect(css).toMatch(/\.x-reader-viewpoint-group--security\s*\{/);
    expect(css).toMatch(/\.x-reader-viewpoint-group--market\s*\{/);
    expect(css).toMatch(/\.x-reader-viewpoint-group--strategy\s*\{/);
    expect(css).toMatch(/\.reader-content\s+\.x-reader-viewpoint-heading\s*\{[^}]*font-size:\s*clamp\(/s);
    expect(css).toMatch(/\.x-reader-viewpoint-group\s*\{[^}]*overflow-wrap:\s*anywhere;/s);
    expect(css).toMatch(/\.x-analysis-body[^}]*overflow-wrap:\s*anywhere;/s);
  });

  it("defines a dedicated raw X post summary row", () => {
    expect(css).toMatch(/\.x-analysis\s+summary\s*\{/);
    expect(css).toMatch(/\.x-analysis\s+summary::before\s*\{/);
    expect(css).toMatch(/\.x-analysis\[open\]\s*>\s*summary::before/);
    expect(css).toMatch(/\.reader-content\s+details\.x-analysis\s+summary\s*\{[^}]*min-height:\s*2\.75rem;/s);
    expect(css).toMatch(/\.reader-content\s+details\.x-analysis\s+summary\s+a\s*\{[^}]*min-width:\s*0;[^}]*overflow-wrap:\s*anywhere;/s);
    expect(css).toMatch(/\.x-analysis-body[^}]*overflow-wrap:\s*anywhere;/s);
  });
});

describe("Agent conversation scrolling", () => {
  it("fixes the desktop workbench at 1200px and makes the message list scroll internally", () => {
    expect(css).toMatch(/\.agent-workbench\s*\{[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\);[^}]*height:\s*1200px;[^}]*min-height:\s*0;[^}]*overflow:\s*hidden;/s);
    expect(css).toMatch(/\.agent-conversation\s*\{[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\) auto auto auto;[^}]*min-height:\s*0;[^}]*overflow:\s*hidden;/s);
    expect(css).toMatch(/\.agent-message-list\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
  });

  it("keeps the mobile workbench within the same 1200px ceiling", () => {
    expect(css).toMatch(/\.agent-workbench\s*\{[^}]*height:\s*min\(1200px, calc\(100dvh - 9rem\)\);/s);
  });
});

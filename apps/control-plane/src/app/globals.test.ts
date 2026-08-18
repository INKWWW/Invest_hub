import { readFileSync } from "node:fs";
import { renderToStaticMarkup } from "react-dom/server";
import { createElement } from "react";

import { describe, expect, it } from "vitest";

import { ReaderSourceNavigation } from "../components/reader/ReaderSourceNavigation";

const css = readFileSync(new URL("./globals.css", import.meta.url), "utf8");

describe("reader header visual hierarchy", () => {
  it("keeps the reader header undecorated and uses the approved responsive type scale", () => {
    expect(css).toMatch(/\.reader-page-header\s*\{[^}]*border-left:\s*0;[^}]*padding:\s*0;/s);
    expect(css).toMatch(/\.product-mark\s*\{[^}]*font-size:\s*clamp\(2rem, 5\.2vw, 2\.5rem\);/s);
    expect(css).toMatch(/\.reader-page-header h1, \.auth-card h1\s*\{[^}]*font-size:\s*clamp\(1\.5625rem, 3vw, 2\.25rem\);/s);
    expect(css).toMatch(/\.session-controls button\s*\{[^}]*font-size:\s*0\.625rem;/s);
  });

  it("keeps the peer navigation and Agent workbench geometry contracts", () => {
    const agent = renderToStaticMarkup(createElement(ReaderSourceNavigation, { active: "agent" }));
    expect(agent).toContain('href="/agent" aria-current="page"');
    expect(agent).toContain('href="/x"');
    expect(agent).toContain('href="/discord"');
    expect(agent).toContain("投资研究 Agent");
    expect(agent).toContain("X 信息");
    expect(agent).toContain("Discord 信息-WIP");
    expect(css).toMatch(/\.reader-source-links\s*\{[^}]*display:\s*flex;[^}]*flex-wrap:\s*wrap;[^}]*gap:\s*0\.5rem;/s);
    expect(css).toMatch(/\.agent-workbench\s*\{[^}]*grid-template-rows:\s*auto\s+minmax\(0,\s*1fr\);[^}]*height:\s*1200px;[^}]*min-height:\s*0;[^}]*overflow:\s*hidden;/s);
    expect(css).toMatch(/\.agent-message-list\s*\{[^}]*min-height:\s*0;[^}]*overflow-y:\s*auto;/s);
    expect(css).toMatch(/\.agent-workbench\s*\{[^}]*height:\s*min\(1200px,\s*calc\(100dvh\s*-\s*9rem\)\)/s);
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

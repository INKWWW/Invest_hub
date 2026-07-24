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

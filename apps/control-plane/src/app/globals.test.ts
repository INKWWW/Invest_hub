import { readFileSync } from "node:fs";

import { describe, expect, it } from "vitest";

const css = readFileSync(new URL("./globals.css", import.meta.url), "utf8");

describe("reader header visual hierarchy", () => {
  it("keeps the reader header undecorated and reduces its display scale", () => {
    expect(css).toMatch(/\.reader-page-header\s*\{[^}]*border-left:\s*0;[^}]*padding:\s*0;/s);
    expect(css).toMatch(/\.product-mark\s*\{[^}]*font-size:\s*1\.05rem;/s);
    expect(css).toMatch(/\.reader-page-header h1, \.auth-card h1\s*\{[^}]*font-size:\s*clamp\(1\.8rem, 3\.5vw, 2\.75rem\);/s);
  });
});

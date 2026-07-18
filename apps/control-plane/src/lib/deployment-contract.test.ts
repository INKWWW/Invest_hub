import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

function variableNames(text: string): string[] {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line && !line.startsWith("#"))
    .map((line) => line.split("=", 1)[0]);
}

describe("V0 deployment environment contract", () => {
  it("documents exactly the Supabase variables read by the deployed control plane", () => {
    const example = readFileSync(resolve(process.cwd(), ".env.example"), "utf8");

    expect(variableNames(example)).toEqual([
      "NEXT_PUBLIC_SUPABASE_URL",
      "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      "SUPABASE_SERVICE_ROLE_KEY",
    ]);
  });
});

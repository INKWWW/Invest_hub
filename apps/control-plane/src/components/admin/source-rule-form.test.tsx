import { describe, expect, it } from "vitest";

import { parseAuthorIds, validateRuleSets } from "./SourceRuleForm";

describe("SourceRuleForm", () => {
  it("normalizes author IDs and rejects target/exclude conflicts without private collection fields", () => {
    expect(parseAuthorIds(" author-b,author-a\nauthor-a ")).toEqual(["author-a", "author-b"]);
    expect(validateRuleSets(["author-a"], ["author-a"])).toContain("不能同时");
    expect(validateRuleSets(["author-a"], ["author-b"])).toBeNull();
  });
});

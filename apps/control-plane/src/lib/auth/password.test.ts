import { describe, expect, it } from "vitest";

import { isValidRegistrationPassword } from "./password";

describe("registration password contract", () => {
  it.each([
    "Short1",
    "lowercase1",
    "UPPERCASE1",
    "NoDigitsHere",
    "Abcdefgh",
  ])("rejects a password without the complete registration policy: %s", (password) => {
    expect(isValidRegistrationPassword(password)).toBe(false);
  });

  it("accepts at least eight characters with upper, lower, and digit", () => {
    expect(isValidRegistrationPassword("Abcdefg1")).toBe(true);
    expect(isValidRegistrationPassword("LongerPass9")).toBe(true);
  });
});

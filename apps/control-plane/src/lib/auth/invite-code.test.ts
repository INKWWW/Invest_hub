import { beforeEach, describe, expect, it, vi } from "vitest";

import {
  generateUserInviteCode,
  hashLegacyInviteCode,
  hashUserInviteCode,
  isValidUserInviteCode,
} from "./invite-code";

describe("ordinary user invite code policy", () => {
  beforeEach(() => {
    vi.stubEnv("INVITE_CODE_PEPPER", "fixture-invite-pepper");
  });

  it("generates eight alphanumeric characters with all three required classes", () => {
    const generated = Array.from({ length: 200 }, () => generateUserInviteCode());
    const categoriesByIndex = generated.map(({ code }) => code.split("").map((char) => {
      if (/[A-Z]/.test(char)) return "upper";
      if (/[a-z]/.test(char)) return "lower";
      return "digit";
    }));

    for (const { code, mask } of generated) {
      expect(code).toMatch(/^[A-Za-z0-9]{8}$/);
      expect(code).toMatch(/[A-Z]/);
      expect(code).toMatch(/[a-z]/);
      expect(code).toMatch(/[0-9]/);
      expect(isValidUserInviteCode(code)).toBe(true);
      expect(mask).toBe(`${code.slice(0, 2)}••••${code.slice(-2)}`);
    }
    expect(categoriesByIndex.every((categories) => new Set(categories).size > 1)).toBe(true);
  });

  it("uses the server pepper for new user verification and preserves legacy SHA-256", () => {
    expect(hashUserInviteCode("Ab3xYz91")).not.toBe(hashLegacyInviteCode("Ab3xYz91"));
    expect(hashUserInviteCode("Ab3xYz91")).toMatch(/^[a-f0-9]{64}$/);
    expect(hashLegacyInviteCode("Ab3xYz91")).toMatch(/^[a-f0-9]{64}$/);
  });
});

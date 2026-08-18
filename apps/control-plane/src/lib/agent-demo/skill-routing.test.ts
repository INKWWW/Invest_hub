import { describe, expect, it } from "vitest";

import {
  HOLDINGS_CLARIFICATION,
  SKILL_DEFINITIONS,
  parseSkillCommand,
  routeSkill,
} from "./skill-routing";

describe("agent demo skill routing contract", () => {
  it("keeps the three button labels, skill IDs, and commands in one exact mapping", () => {
    expect(SKILL_DEFINITIONS).toContainEqual({
      buttonLabel: "大师投研",
      id: "investment-research",
      command: "/investment-research",
    });
    expect(SKILL_DEFINITIONS).toEqual([
      {
        buttonLabel: "大师投研",
        id: "investment-research",
        command: "/investment-research",
      },
      {
        buttonLabel: "持仓组合分析",
        id: "portfolio-review",
        command: "/portfolio-review",
      },
      {
        buttonLabel: "下单前巴菲特拷问",
        id: "investment-checklist",
        command: "/investment-checklist",
      },
    ]);
  });

  it("parses a known command only at the start and removes it from the question", () => {
    expect(parseSkillCommand("  /portfolio-review 请分析我的组合")).toEqual({
      text: "请分析我的组合",
      skillId: "portfolio-review",
      notice: undefined,
    });
    expect(parseSkillCommand("请分析 /portfolio-review 我的组合")).toEqual({
      text: "请分析 /portfolio-review 我的组合",
      skillId: null,
      notice: undefined,
    });
  });

  it("keeps an unknown leading command as ordinary text and explains the valid choices", () => {
    const result = parseSkillCommand("/not-a-skill 研究这家公司");

    expect(result.text).toBe("/not-a-skill 研究这家公司");
    expect(result.skillId).toBeNull();
    expect(result.notice).toContain("可用命令");
    expect(result.notice).toContain("/portfolio-review");
  });

  it("lets an explicit button or command win over the Auto decision and returns at most one Skill", () => {
    expect(
      routeSkill({
        message: "/investment-research 研究这家公司",
        autoDecision: "portfolio-review",
      }),
    ).toMatchObject({
      invocationMode: "explicit",
      skillId: "investment-research",
      decision: "skill",
    });
  });

  it("rejects an Auto result outside the general/refuse/allowlisted Skill closed set", () => {
    expect(() => routeSkill({ message: "研究", autoDecision: "two-skills" })).toThrow(
      "invalid_skill_id",
    );
  });

  it("routes an Auto decision to either one fixed Skill or general/refuse without combining Skills", () => {
    expect(routeSkill({ message: "帮我看组合", autoDecision: "portfolio-review", hasHoldings: true })).toMatchObject({
      invocationMode: "auto",
      skillId: "portfolio-review",
      decision: "skill",
    });
    expect(routeSkill({ message: "什么是市盈率", autoDecision: "general" })).toMatchObject({
      invocationMode: "auto",
      skillId: null,
      decision: "general",
    });
    expect(routeSkill({ message: "帮我写旅行计划", autoDecision: "refuse" })).toMatchObject({
      invocationMode: "auto",
      skillId: null,
      decision: "refuse",
    });
  });

  it("returns the agreed portfolio follow-up when the selected Skill lacks holdings", () => {
    expect(
      routeSkill({
        message: "帮我分析组合",
        explicitSkillId: "portfolio-review",
        hasHoldings: false,
      }),
    ).toMatchObject({
      invocationMode: "explicit",
      skillId: "portfolio-review",
      decision: "clarification",
      clarification: HOLDINGS_CLARIFICATION,
    });
  });

  it("does not carry an explicit Skill into the next message", () => {
    routeSkill({ message: "先看组合", explicitSkillId: "portfolio-review", hasHoldings: false });

    expect(routeSkill({ message: "这是我的持仓", autoDecision: "general" })).toMatchObject({
      invocationMode: "auto",
      skillId: null,
      decision: "general",
    });
  });
});

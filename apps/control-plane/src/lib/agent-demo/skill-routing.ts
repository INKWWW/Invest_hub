export const SKILL_DEFINITIONS = [
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
] as const;

export type SkillId = (typeof SKILL_DEFINITIONS)[number]["id"];
export type AutoDecision = "general" | "refuse" | SkillId;
export type InvocationMode = "explicit" | "auto";
export type SkillRouteDecision = "skill" | "general" | "refuse" | "clarification";

export const HOLDINGS_CLARIFICATION =
  "当前研究会话还没有持仓数据，请直接发送持仓清单。";

const UNKNOWN_COMMAND_NOTICE = `未识别的 Skill 命令，将按普通文本处理。可用命令：${SKILL_DEFINITIONS.map(
  ({ command }) => command,
).join("、")}。`;

const skillIds = new Set<SkillId>(SKILL_DEFINITIONS.map(({ id }) => id));
type SkillDefinition = (typeof SKILL_DEFINITIONS)[number];
const skillByCommand: ReadonlyMap<string, SkillDefinition> = new Map(
  SKILL_DEFINITIONS.map((definition) => [definition.command, definition]),
);

export type ParsedSkillCommand = {
  text: string;
  skillId: SkillId | null;
  notice?: string;
};

export type SkillRouteInput = {
  message: string;
  explicitSkillId?: SkillId | null;
  autoDecision?: string;
  hasHoldings?: boolean;
  scope?: "investment" | "refuse";
};

export type SkillRoute = {
  text: string;
  invocationMode: InvocationMode;
  skillId: SkillId | null;
  decision: SkillRouteDecision;
  notice?: string;
  clarification?: string;
};

function assertSkillId(value: string): asserts value is SkillId {
  if (!skillIds.has(value as SkillId)) {
    throw new Error("invalid_skill_id");
  }
}

function routeWithoutSkill(
  parsed: ParsedSkillCommand,
  invocationMode: InvocationMode,
  decision: "general" | "refuse",
): SkillRoute {
  return {
    text: parsed.text,
    invocationMode,
    skillId: null,
    decision,
    ...(parsed.notice ? { notice: parsed.notice } : {}),
  };
}

function routeToSkill(
  parsed: ParsedSkillCommand,
  invocationMode: InvocationMode,
  skillId: SkillId,
  hasHoldings: boolean | undefined,
  notice?: string,
): SkillRoute {
  if (skillId === "portfolio-review" && hasHoldings !== true) {
    return {
      text: parsed.text,
      invocationMode,
      skillId,
      decision: "clarification",
      clarification: HOLDINGS_CLARIFICATION,
      ...(notice ? { notice } : parsed.notice ? { notice: parsed.notice } : {}),
    };
  }

  return {
    text: parsed.text,
    invocationMode,
    skillId,
    decision: "skill",
    ...(notice ? { notice } : parsed.notice ? { notice: parsed.notice } : {}),
  };
}

/**
 * Parses a stable Skill command only when it is the first token in a message.
 * Unknown leading commands remain untouched so they still reach the normal LLM path.
 */
export function parseSkillCommand(message: string): ParsedSkillCommand {
  if (typeof message !== "string") {
    throw new Error("invalid_message");
  }

  const leadingText = message.trimStart();
  if (!leadingText.startsWith("/")) {
    return { text: message, skillId: null };
  }

  const commandMatch = leadingText.match(/^\/[^\s]+/u);
  if (!commandMatch) {
    return { text: message, skillId: null };
  }

  const command = commandMatch[0];
  const definition = skillByCommand.get(command);
  if (!definition) {
    return { text: message, skillId: null, notice: UNKNOWN_COMMAND_NOTICE };
  }

  return {
    text: leadingText.slice(command.length).trimStart(),
    skillId: definition.id,
  };
}

/**
 * Resolves one current-message invocation. No result carries more than one Skill ID.
 * `autoDecision` is the already-parsed closed-set result from the LLM router; this
 * function only validates and projects it into the runtime contract.
 */
export function routeSkill(input: SkillRouteInput): SkillRoute {
  const parsed = parseSkillCommand(input.message);
  const explicitSkillId = input.explicitSkillId ?? parsed.skillId;

  if (explicitSkillId !== null && explicitSkillId !== undefined) {
    assertSkillId(explicitSkillId);
    if (input.scope === "refuse") {
      return routeWithoutSkill(parsed, "explicit", "refuse");
    }
    return routeToSkill(parsed, "explicit", explicitSkillId, input.hasHoldings);
  }

  const autoDecision = input.autoDecision ?? "general";
  if (autoDecision === "general" || autoDecision === "refuse") {
    return routeWithoutSkill(parsed, "auto", autoDecision);
  }

  assertSkillId(autoDecision);
  if (input.scope === "refuse") {
    return routeWithoutSkill(parsed, "auto", "refuse");
  }
  return routeToSkill(parsed, "auto", autoDecision, input.hasHoldings);
}

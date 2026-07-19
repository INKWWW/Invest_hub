import { createSupabaseAdminClient } from "../supabase-server";

export type RuleSnapshot = {
  version: number;
  targetAuthorIds: string[];
};

export type RuleReplacementInput = {
  sourceId: string;
  globalTargetAuthorIds: string[];
  sourceTargetAuthorIds: string[];
  sourceExcludedAuthorIds: string[];
  actorId: string;
};

function normalizeAuthorIds(authorIds: string[]): string[] {
  return [...new Set(authorIds.map((authorId) => authorId.trim()).filter(Boolean))].sort();
}

export function deriveTargetAuthorIds(input: Pick<
  RuleReplacementInput,
  "globalTargetAuthorIds" | "sourceTargetAuthorIds" | "sourceExcludedAuthorIds"
>): string[] {
  const excluded = new Set(normalizeAuthorIds(input.sourceExcludedAuthorIds));
  return normalizeAuthorIds([...input.globalTargetAuthorIds, ...input.sourceTargetAuthorIds])
    .filter((authorId) => !excluded.has(authorId));
}

function parseRuleSnapshot(value: unknown): RuleSnapshot {
  if (!value || typeof value !== "object") throw new Error("invalid_rule_snapshot");
  const snapshot = value as { version?: unknown; target_author_ids?: unknown };
  if (!Number.isInteger(snapshot.version) || (snapshot.version as number) < 0 || !Array.isArray(snapshot.target_author_ids)
    || !snapshot.target_author_ids.every((authorId) => typeof authorId === "string")) {
    throw new Error("invalid_rule_snapshot");
  }
  return {
    version: snapshot.version as number,
    targetAuthorIds: [...snapshot.target_author_ids].sort(),
  };
}

export async function replaceSourceRules(input: RuleReplacementInput): Promise<RuleSnapshot> {
  const { data, error } = await createSupabaseAdminClient().rpc("replace_source_author_rules", {
    p_source_id: input.sourceId,
    p_global_target_author_ids: normalizeAuthorIds(input.globalTargetAuthorIds),
    p_source_target_author_ids: normalizeAuthorIds(input.sourceTargetAuthorIds),
    p_source_excluded_author_ids: normalizeAuthorIds(input.sourceExcludedAuthorIds),
    p_actor_id: input.actorId,
  });
  if (error) throw error;
  return parseRuleSnapshot(data);
}

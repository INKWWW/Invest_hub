import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../lib/auth/require-role";
import { replaceSourceRules } from "../../../../lib/db/repositories/rules";

const ruleKeys = [
  "source_id",
  "global_target_author_ids",
  "source_target_author_ids",
  "source_excluded_author_ids",
];

function isAuthorIdList(value: unknown): value is string[] {
  return Array.isArray(value)
    && value.every((authorId) => typeof authorId === "string" && authorId.trim().length > 0 && authorId.length <= 256);
}

export async function POST(request: Request) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  try {
    const body = (await request.json()) as Record<string, unknown>;
    if (Object.keys(body).some((key) => !ruleKeys.includes(key))
      || typeof body.source_id !== "string"
      || !isAuthorIdList(body.global_target_author_ids)
      || !isAuthorIdList(body.source_target_author_ids)
      || !isAuthorIdList(body.source_excluded_author_ids)) {
      return NextResponse.json({ error: "invalid_rules" }, { status: 422 });
    }
    const snapshot = await replaceSourceRules({
      sourceId: body.source_id,
      globalTargetAuthorIds: body.global_target_author_ids,
      sourceTargetAuthorIds: body.source_target_author_ids,
      sourceExcludedAuthorIds: body.source_excluded_author_ids,
      actorId: current.id,
    });
    return NextResponse.json({ source_id: body.source_id, rule_snapshot: snapshot });
  } catch {
    return NextResponse.json({ error: "rule_replace_failed" }, { status: 503 });
  }
}

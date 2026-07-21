import { NextResponse } from "next/server";

import { isCurrentUser, requireRole } from "../../../../../../lib/auth/require-role";
import { listObservedAuthors } from "../../../../../../lib/db/repositories/author-profiles";

type RouteContext = { params: Promise<{ sourceId: string }> };

export async function GET(_: Request, context: RouteContext) {
  const current = await requireRole("admin");
  if (!isCurrentUser(current)) return current;
  const { sourceId } = await context.params;
  try {
    const authors = await listObservedAuthors(sourceId);
    return NextResponse.json({
      authors: authors.map((author) => ({
        author_id: author.authorId,
        author_display: author.authorDisplay,
        author_handle: author.authorHandle,
      })),
    });
  } catch {
    return NextResponse.json({ error: "observed_author_list_failed" }, { status: 503 });
  }
}

import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import { readXDay, type XReaderDate } from "../../../../lib/db/repositories/reader";

function readerFilter(value: string | null) {
  return value && value !== "all" ? value : undefined;
}

/** Runtime JSON boundary: even a future repository DTO regression cannot expose internal fields. */
function readerSafeXDays(days: XReaderDate[]) {
  return days.map((day) => ({
    naturalDate: day.naturalDate,
    judgement: {
      visible: day.judgement.visible,
      batches: day.judgement.batches.map((batch) => ({
        cutoffAt: batch.cutoffAt,
        coverageStatus: batch.coverageStatus,
        status: batch.status,
        revision: batch.revision,
        stockViewpoints: batch.stockViewpoints.map((viewpoint) => ({
          statement: viewpoint.statement,
          supportingDisplayNames: [...viewpoint.supportingDisplayNames],
          dissentingDisplayNames: [...viewpoint.dissentingDisplayNames],
          uncertainties: [...viewpoint.uncertainties],
        })),
        marketIndustryViewpoints: batch.marketIndustryViewpoints.map((viewpoint) => ({
          statement: viewpoint.statement,
          supportingDisplayNames: [...viewpoint.supportingDisplayNames],
          dissentingDisplayNames: [...viewpoint.dissentingDisplayNames],
          uncertainties: [...viewpoint.uncertainties],
        })),
        uncertainties: [...batch.uncertainties],
        excludedSourceCount: batch.excludedSourceCount,
      })),
    },
    bloggers: day.bloggers.map((blogger) => ({
      source: { sourceKey: blogger.source.sourceKey, displayName: blogger.source.displayName },
      status: blogger.status,
      segments: blogger.segments.map((segment) => ({
        occurredFromAt: segment.occurredFromAt,
        occurredThroughAt: segment.occurredThroughAt,
        viewpoints: [...segment.viewpoints],
        uncertainties: [...segment.uncertainties],
        analyses: segment.analyses.map((analysis) => ({
          postLink: analysis.postLink,
          bloggerViewpoint: analysis.bloggerViewpoint,
          arguments: [...analysis.arguments],
          quotedPostViewpoint: analysis.quotedPostViewpoint,
          uncertainties: [...analysis.uncertainties],
        })),
      })),
    })),
  }));
}

export async function GET(request: Request) {
  if (!await getCurrentUser()) return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  const { searchParams } = new URL(request.url);
  const sourceKey = readerFilter(searchParams.get("source"));
  const date = readerFilter(searchParams.get("date"));
  if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) return NextResponse.json({ error: "invalid_reader_query" }, { status: 422 });
  try {
    return NextResponse.json({ status: "ok", days: readerSafeXDays(await readXDay({ sourceKey, date })) });
  } catch {
    return NextResponse.json({ error: "reader_unavailable" }, { status: 503 });
  }
}

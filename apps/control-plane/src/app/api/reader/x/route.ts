import { NextResponse } from "next/server";

import { getCurrentUser } from "../../../../lib/auth/current-user";
import { readXDay, type XReaderDate } from "../../../../lib/db/repositories/reader";
import { isValidReaderNaturalDate } from "../../../../lib/reader-date";

function readerFilter(value: string | null) {
  return value && value !== "all" ? value : undefined;
}

function readerSafeCoverageStatus(value: unknown, revision: number) {
  if (revision < 1) return null;
  return value === "complete" || value === "partial" || value === "no_new_information" ? value : null;
}

function readerSafeJudgement(viewpoint: {
  statement: string;
  actionIntent?: string | null;
  actionScope?: string;
  actionScopeStatus?: string;
  conditions?: string[];
  supportingDisplayNames: string[];
  dissentingDisplayNames: string[];
  uncertainties: string[];
}) {
  return {
    statement: viewpoint.statement,
    actionIntent: viewpoint.actionIntent ?? null,
    actionScope: viewpoint.actionScope ?? "",
    actionScopeStatus: viewpoint.actionScopeStatus ?? null,
    conditions: [...(viewpoint.conditions ?? [])],
    supportingDisplayNames: [...viewpoint.supportingDisplayNames],
    dissentingDisplayNames: [...viewpoint.dissentingDisplayNames],
    uncertainties: [...viewpoint.uncertainties],
  };
}

/** Runtime JSON boundary: even a future repository DTO regression cannot expose internal fields. */
function readerSafeXDays(days: XReaderDate[]) {
  return days.map((day) => ({
    naturalDate: day.naturalDate,
    judgement: {
      visible: day.judgement.visible,
      batches: day.judgement.batches.map((batch) => ({
        cutoffAt: batch.cutoffAt,
        coverageStatus: readerSafeCoverageStatus(batch.coverageStatus, batch.revision),
        status: batch.status,
        revision: batch.revision,
        stockViewpoints: batch.stockViewpoints.map(readerSafeJudgement),
        marketIndustryViewpoints: batch.marketIndustryViewpoints.map(readerSafeJudgement),
        strategyMindsetViewpoints: (batch.strategyMindsetViewpoints ?? []).map(readerSafeJudgement),
        uncertainties: [...batch.uncertainties],
        excludedSourceCount: batch.excludedSourceCount,
        revisionHistory: (batch.revisionHistory ?? []).map((revision) => ({
          revision: revision.revision,
          coverageStatus: readerSafeCoverageStatus(revision.coverageStatus, revision.revision),
          stockViewpoints: revision.stockViewpoints.map(readerSafeJudgement),
          marketIndustryViewpoints: revision.marketIndustryViewpoints.map(readerSafeJudgement),
          strategyMindsetViewpoints: (revision.strategyMindsetViewpoints ?? []).map(readerSafeJudgement),
          uncertainties: [...revision.uncertainties],
        })),
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
          actionIntent: analysis.actionIntent ?? null,
          actionScope: analysis.actionScope ?? "",
          actionScopeStatus: analysis.actionScopeStatus ?? null,
          conditions: [...(analysis.conditions ?? [])],
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
  if (date && !isValidReaderNaturalDate(date)) return NextResponse.json({ error: "invalid_reader_query" }, { status: 422 });
  try {
    return NextResponse.json({ status: "ok", days: readerSafeXDays(await readXDay({ sourceKey, date })) });
  } catch {
    return NextResponse.json({ error: "reader_unavailable" }, { status: 503 });
  }
}
